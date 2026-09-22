# Security

## Reporting

Use GitHub's **Report a vulnerability** button, under the repository's Security
tab. That opens a private thread rather than a public issue, which is what you
want for anything that reads or writes a file it should not.

Please do not open a public issue for a vulnerability. Anything else, including
a bug that merely loses data in an ordinary way, belongs in a normal issue and
is easier to fix there.

This is one person's app, written for their own use and published because the
code may be useful. There is no on-call rotation and no response-time promise.
Expect a reply in days, not hours, and expect an honest answer if a fix is not
going to happen.

## What the app can reach

Sift runs in the App Sandbox, with three entitlements and no others:
`com.apple.security.app-sandbox`, `files.user-selected.read-write` and
`bookmarks.app-scope`. They are in `Resources/Sift.entitlements`, and
`scripts/bundle.sh` reads the sandbox back off the signed bundle and fails the
build if it is not there. A fourth entitlement would be a decision written down
first.

So the app starts with no reach at all. It reads a folder only after somebody
hands it one, through one of three doors: the open panel, a drop on the window,
or opening it from the Finder. Each grant is kept as an app-scoped bookmark so
the next launch can read the same folder, **Settings > Folders** lists every
grant the app holds, and **Remove** on a row drops one. A grant covers the
folder that was handed over and everything under it, which is why a folder
whose parent is also on the list stays readable after its own row is removed.

Inside a granted folder the app has the powers of the person running it and
nothing more: it reads and writes photo files there, because a culler that
cannot write to the card reader or the external drive is not a culler. macOS's
own switches for Desktop, Documents, Downloads and removable volumes sit
outside this fence and still apply.

This paragraph said the opposite until 2026-09-20, and had done since the app
was sandboxed. If you are auditing the boundary, audit
`Sift/Files/FolderAccess.swift`: which grant covers a folder, what a revoke
takes away, and whether a grant reaches where it should not.

It has no network code. There is no `URLSession` in the source, no analytics,
no crash reporting and no update check. A network call appearing in this app is
itself a finding, and you can check the claim against the source in a minute.

## Worth looking at

The parts where a mistake costs a photograph or exposes one:

- **File operations** in `Sift/Files/`. Every mutation builds its inverse
  before it runs. A path that can escape the folder it was given, a move that
  can overwrite something it did not name, or an inverse that restores the
  wrong bytes is the highest-value bug in the repository.
- **The kept original**, `.NAME.sift-original.EXT`, written beside a
  photograph on the first save-over. It is a full-size copy of the unedited
  frame. It is hidden, not protected.
- **The session backup directory**, mode 0700 under an unguessable name from
  `.itemReplacementDirectory`. It used to be a predictable path under
  `$TMPDIR`, which is `/tmp` when that variable is unset. Symlink and
  pre-creation attacks on it are in scope. It is deleted when the app quits,
  and, because a crash or a force-quit never reaches that, the next launch
  sweeps what the last session left: each directory carries a file naming the
  process that made it, and one whose process no longer answers is taken away.
  A directory with no such file belongs to somebody else and is left alone.
- **Extended attributes and XMP sidecars** in `Sift/Metadata/`. Sift writes
  `com.sift.adjust` and `com.sift.derived` on the photograph and, when sidecars
  are switched on, edits a `.xmp` that something else may have written.
- **The `SIFT_*` environment variables**, listed in `CONTRIBUTING.md`. The ones
  that ship shape a window, pick a palette, redirect preferences or report what
  came up, and write nothing. Seven are compiled out of the download: the six
  that can reach a `Command`, and `SIFT_START_IN`, which picks the folder a
  launch opens. `SecurityClaimTests` allowlists the ones that may ship and
  fails the build when a new name arrives without a gate, which is how the
  seventh was caught.

  Say plainly what that gate is for, because this file used to say the
  opposite. Launching the binary with a chosen environment is **not** already
  game over. TCC grants attach to Sift rather than to whatever launched it, so
  a process holding none of your grants for Desktop, Documents, Downloads or a
  card reader can start Sift with an environment of its choosing and have Sift
  do the reading and the writing under Sift's own consent. That is why
  `SIFT_SCRIPT` is debug-only, and it is why `SIFT_SHOW` is: one of its screens
  favorited the photograph under the cursor and pressed trash to assemble the
  one question the app asks, and on a photograph that was *already* a favorite
  the press unfavorited it instead, so the question was skipped and the file
  went to the Trash. A launch variable that reaches a file is the finding to
  send here.

## The download, and what signing it proves

There is a download. Every tag starting `v` builds a disk image on GitHub
Actions and attaches it to a release, and the README's button points at the
latest one. That is a change from what this file used to say, and it is worth
being exact about what arrived with it.

The app is **ad-hoc signed**. The signature seals the bundle, so macOS can tell
you the bytes have not been edited since they were signed. It names nobody. A
paid Apple developer account is what puts an identity behind a signature, and
this project does not have one, so there is nothing here for Apple to revoke
and nothing tying the build to a person.

It is **not notarized**, and Gatekeeper
refuses the first open; the reader clears it by hand in System Settings. It
**does** carry the hardened runtime, which is the one hardening an ad-hoc
signature can hold: `codesign -d -vv` on the installed app reports
`flags=0x10002(adhoc,runtime)`. That closes `DYLD_INSERT_LIBRARIES`, and it
matters here because Sift holds the reader's grants for Desktop, Documents,
Downloads and removable volumes, so anything injected into it would read their
photographs under Sift's name instead of asking for consent of its own. The
README says so above the button rather than below it. Teaching people to click
past a malware warning is a real cost, and it was accepted rather than argued
away: the alternative was a project nobody could run without a toolchain.

The release notes carry a SHA-256. Read what it is for. It proves your download
matches the file the workflow produced. It does not prove the workflow produced
what the tag said, because the same job computes the checksum and writes the
notes. The check that does not rest on that job is building the tag yourself and
comparing. The build log is public for the same reason.

In scope, and worth a report:

- **The release workflow**, `.github/workflows/release.yml`. It holds
  `contents: write` and publishes what people download. Its actions are pinned
  to commits rather than to tags; a way to make it build or publish something a
  tag did not name is the highest-value finding in this repository.
- **The disk image**, `scripts/dmg.sh`. It stages the bundle, stamps the
  version, signs, and packs. A path into the staged bundle between the sign and
  the pack would ship signed bytes nobody wrote.

## There is still no update channel

The app never looks for a new version, and it has no installer script and no
way to fetch and run anything. There is no code path that can bring another
person's code to your machine after the drag to Applications. You find out about
a release by looking, which is a deliberate constraint and not a gap waiting to
be filled.

Building from source is still there and is the option that trusts least. It is
two commands, and the README has them.
