# Contributing

Issues and pull requests are welcome. This is one person's app, so expect a
reply in days rather than hours, and expect an honest no when something does not
fit.

## Getting set up

```bash
git clone https://github.com/nhilikeknee/sift.git
cd sift && make test
```

`make run` builds the app and opens it.

CI runs `swift build --build-tests` and `swift test` on macOS 14 and macOS 15
for every push and pull request. The app's floor is 14, and the two runners are
the only thing that proves it: nothing on the author's machine runs Sonoma.

## Commands

```bash
make run
```

`make build` runs `scripts/bundle.sh`, which does `swift build` and wraps the
binary in `~/Applications/Sift.app`, so Launchpad and Spotlight find it.
`build/Sift.app` is a symlink to that bundle rather than a second copy. Open
`Package.swift` in Xcode for the debugger.

```bash
make test
```

```bash
make dmg VERSION=0.1.0
```

`scripts/dmg.sh` builds the download: a release bundle, the version stamped in,
an Applications symlink to drag onto, and the whole thing compressed into
`build/Sift-<version>.dmg`. It calls `bundle.sh` with a staging directory
rather than repeating what a `Sift.app` contains, so the release and your local
build can never be two different things. Pushing a tag like `v0.1.0` makes
`.github/workflows/release.yml` run it and attach the result to a release. The
build is ad-hoc signed and never notarized, which is why the README spends a
paragraph on getting it past Gatekeeper.

## The house rules

The ones that get people:

- **No third-party dependencies.** ImageIO, Core Graphics, AppKit, SwiftUI. If
  something seems to need a package, that is worth raising in an issue first.
- **No design literals in views.** Colors, sizes, spacing and durations come
  from `Tokens`. A test fails on a `.font(` in a view or a measurement off the
  scale.
- **Every file operation is undoable**, and the inverse is built before the
  change is made rather than reasoned about afterward.
- **A shortcut is never the only way in.** Every command has a control on
  screen. A feature reachable only by a keystroke is a feature nobody can find.
- **American English**, in the labels and in the comments. A test fails on the
  British spelling and names the line. It reads comments as well as strings,
  because that is where the wrong spelling sits before it reaches a label.
- **Swift 6, strict concurrency.** Image decode never touches the main actor.
- **Everything is on one of four scales.** Spacing is 4/8/12/16/24/32/48/64,
  every `layout.*` measurement is a multiple of 4, a glyph is drawn at 14, 20
  or 28, and a sheet or floating panel is 420, 520 or 640. Each scale is a list
  in `Tokens.swift` with a test behind it. A screen that wants a width between
  two steps takes the nearer step.
- **Text is set by role, never by size.** `.textStyle(.label)`, `.readout`,
  `.quiet`, `.strong`, `.data`, `.body`, `.heading`, `.title`: each pairs a
  size, a weight and a resting color, in `Sift/Design/TextRole.swift`.
- **One key map.** Keystrokes route through `Input/KeyMap.swift` and every
  binding says which window it belongs to. Nothing handles a raw `NSEvent`
  anywhere else, and the shortcuts overlay reads that same table.
- **Two windows, one cursor.** The gallery and the preview are separate scenes
  over one `LibraryStore`.

The design tokens are the one place a clone works differently from the author's
checkout. `Tokens.swift` mirrors a design document that is not in this
repository, so the names it declares are committed to
`Tests/SiftTests/Fixtures/design-names.txt` and `DesignSystemTests` checks
against that fixture. You can read and use every existing token. Adding a new
one is the thing to raise in an issue first, because the document it has to be
recorded in lives on one machine.

## Driving the app for a screenshot

A change to anything visual needs a picture, and a screen that takes a keystroke
to reach cannot be reached by a script without Accessibility permission. So the
app opens one directly when asked. These are read once at launch and do nothing
otherwise:

```bash
open --env SIFT_SHOW=preview,info ~/Applications/Sift.app --args ~/Pictures/shoot
```

| Variable | Effect |
|---|---|
| `SIFT_SHOW` | **Debug builds only.** Opens a screen directly, comma-separated: `info`, `filmstrip`, `help`, `summary`, `peek`, `search`, `clipping`, `favorites`, `confirm`, `crop`, `ratio`, `adjust`, `revert`, `trash`, `palette`, `jump`, `path`, `rejects`, `preview`, `zoom`, `undo`, `toast`, `focus`, `bare`, `select`, `settings` |
| `SIFT_APPEARANCE` | `light` or `dark`, without writing the preference |
| `SIFT_GRID` | Thumbnail step in points |
| `SIFT_CURSOR` | **Debug builds only.** Which photograph the cursor lands on |
| `SIFT_START_IN` | **Debug builds only.** Opens a named subfolder of the folder the launch was handed, so the app is granted the card and shows all of it |
| `SIFT_WIDTH` / `SIFT_HEIGHT` | The gallery window's content size |
| `SIFT_PREVIEW_WIDTH` / `SIFT_PREVIEW_HEIGHT` | The same for the preview window |
| `SIFT_BAR` | Pins the preview bar up |
| `SIFT_FEATURES_OFF` | Comma-separated features to switch off |
| `SIFT_WINDOW_REPORT` | Prints what is on screen, with each window's id |
| `SIFT_SCRATCH_PREFS` | Points the launch at a throwaway preferences domain |
| `SIFT_HINTS` | `off` spends every first-time hint, so none fires over a picture |
| `SIFT_FLOAT` | `1` holds Sift's windows above other apps' for the length of a recording |
| `SIFT_SETTINGS_AT` | Scrolls the settings form to a section: `features`, `appearance`, `panels`, `hints`, `access`, `history` or `keyboard`, which is the other tab |
| `SIFT_SETTINGS_TRAIL` | `1` opens the History row's list of stored paths, which is otherwise a click |
| `SIFT_SCRIPT` | **Debug builds only.** A run of commands to replay, comma-separated (see below) |
| `SIFT_SCRIPT_SETUP` | **Debug builds only.** The same, run first and fast, to put a clip's starting state there |
| `SIFT_SCRIPT_STEP` / `SIFT_SCRIPT_LEAD` | **Debug builds only.** The gap between commands, and the pause before the first, in milliseconds |

**Seven of these are not in the download.** `SIFT_SHOW`, `SIFT_CURSOR` and
`SIFT_START_IN` join the four scripting rows behind `#if DEBUG`, for the reason the scripting section
below gives and which turned out to apply here too: `SIFT_SHOW` assembles a
screen by running the same commands a key press runs, and two of the screens it
assembles write. `confirm` favorites the photograph under the cursor and then
presses trash, because the question the app asks needs a loved frame to ask
about; a frame that is already loved is *un*favorited by that press, so the
sheet is skipped and the file goes to the Trash. `undo` favorites twice, which
is two tag writes and, with sidecars on, an `.xmp` written into the shoot.

Neither costs you anything: `make run`, `bundle.sh`, `launch-check.sh`,
`contact-sheet.sh` and `record-demo.sh` all build debug. `SecurityClaimTests`
holds the line, so a launch variable added without a gate fails the suite and
is told which of the two it needs (D-308).

**Set `SIFT_SCRATCH_PREFS=1` on anything that drives the app for a picture.**
Without it, a run that toggles a panel writes that toggle into your real
preferences and the next launch inherits it.

`SIFT_WINDOW_REPORT=1` names each window and its id, and
`screencapture -x -o -l<id>` photographs that one window.

## Driving the app

The animations in the README are the app driving itself. Nothing outside it can
send it a keystroke, so `SIFT_SCRIPT` replays a list of steps through the same
command router the keyboard uses:

```bash
open --env SIFT_SCRIPT=next,flagKeep,flagReject,reviewRejects ~/Applications/Sift.app --args ~/Pictures/shoot
```

Every step is announced on stderr, and a token that is not a step stops the run
instead of skipping it: a clip that quietly drops the step it was made for is
worse than no clip.

A step is one of four things. A `Command` raw value from `Input/KeyMap.swift`,
so a rebound key cannot break a run; `wait` to rest one step or `wait:1200` to
rest that long; or `cropBox:x y w h` in fractions of the frame, because a crop
is a drag and a script has no pointer. `ScriptStepTests` holds that grammar, so
renaming a `Command` case is supported and the suite says what it broke.

The recorders that film the README are the author's own and are not in the
repository: they take over the display for eleven minutes and draw a photo card
to film on. `SIFT_SCRIPT` is the part in this repository, and it is what drives
the app for a screenshot of your own.

**It is a debug-build tool and is not in the download.** `make run` and
`bundle.sh` build debug, so it works in your clone; `dmg.sh` builds release,
where the four variables above are compiled out and a launch carrying one says
so on stderr and does nothing else. A script presses keys and `trash` is among
them, and TCC grants attach to Sift rather than to whatever launched it, so a
shipped build honoring the variable would let any process on the machine trash
somebody's photographs under Sift's consent instead of asking for its own
(D-300). `SecurityClaimTests` fails if a release build ever reads one of them
again, and this table is under the same test: a variable the code reads and
this file does not name is a failure, because SECURITY.md sends a reader here
for the list.

## Pull requests

- `make test` passes, and new behavior comes with a test that would fail
  without it.
- A change to anything visual comes with a screenshot. A green build is not a
  look.
- Commit messages say what was wrong and what the fix accepted in return. The
  history is the long-form record here, so it is worth the paragraph.

## Security

Report anything that reads or writes a file it should not through the
repository's **Security** tab, which opens a private thread, rather than a
public issue. See [SECURITY.md](SECURITY.md).
