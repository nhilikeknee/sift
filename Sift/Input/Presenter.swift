import AppKit

/// Everything the router needs AppKit to put on screen and wait for: a folder
/// chooser, and a menu dropped from the header.
///
/// One protocol, so the half of the router that can be tested is not tangled
/// with the half that cannot (D-197). Before this, four `NSOpenPanel` sites and
/// two `NSMenu` sites sat inline among the commands, which meant the commands
/// that end in a panel — move to a folder, copy to a folder, open a folder, pin
/// one — could only be tested by reaching past the panel to the function behind
/// it. A test answers the panel now, and drives the command itself.
///
/// It is also the app's one piece of global state that is read rather than
/// owned: `NSApp.keyWindow` belongs to the process, not to the router.
@MainActor
protocol Presenter {
    /// The folders somebody chose, or empty when the panel was dismissed.
    func chooseFolders(prompt: String, message: String?, multiple: Bool, startingAt: URL?) -> [URL]

    /// A menu under the header, `x` points from the window's left edge, or
    /// centerd when `x` is nil. `pick` is called with what was chosen and not
    /// at all when the menu was dismissed.
    ///
    /// False when there is no window to hang a menu on, which is a real state
    /// and not a failure: the caller decides what to do without one.
    @discardableResult
    func menu(_ items: [(title: String, url: URL)], x: CGFloat?, drop: CGFloat,
              pick: @escaping (URL) -> Void) -> Bool

    /// Opens System Settings at **Privacy & Security > Files & Folders**, the
    /// one place the reader's grant to Sift can be taken back.
    ///
    /// Here rather than in the view for the reason the panel is: it launches
    /// another application, and a suite that ran it would open System Settings
    /// over whatever the author was doing. The stub records the call instead.
    ///
    /// False when the URL would not open, which is a real state: the pane's
    /// identifier is Apple's and has been renamed before. The caller says so
    /// rather than leaving a button that looks like it worked.
    @discardableResult
    func openFolderAccessSettings() -> Bool
}

extension Presenter {
    /// The four call sites that have no folder in mind. A default argument is
    /// not allowed on a protocol requirement, and widening all of them to
    /// pass `nil` would put the one caller that does care in a crowd.
    func chooseFolders(prompt: String, message: String?, multiple: Bool) -> [URL] {
        chooseFolders(prompt: prompt, message: message, multiple: multiple, startingAt: nil)
    }
}

/// The real one. The only place in the app that builds an `NSOpenPanel` or an
/// `NSMenu`.
@MainActor
final class AppKitPresenter: Presenter {
    /// The menu's target has to outlive `popUp`, which is why this is held
    /// rather than left to the stack.
    private var target: MenuTarget?

    func chooseFolders(prompt: String, message: String?, multiple: Bool, startingAt: URL?) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = multiple
        panel.prompt = prompt
        if let message { panel.message = message }
        // Landing the panel on the folder that was refused, so handing it
        // over is one press rather than a hunt (D-324). The panel runs
        // outside the sandbox, so it can show a folder this app cannot read.
        if let startingAt { panel.directoryURL = startingAt }
        guard panel.runModal() == .OK else { return [] }
        // A door. The panel is the sandbox extending this process, and the
        // bookmark is how that outlives the launch (D-324). Recorded here
        // rather than at the call sites, because a door that each caller has
        // to remember to declare is a door somebody leaves undeclared.
        for url in panel.urls { FolderAccess.remember(url) }
        return panel.urls
    }

    @discardableResult
    func menu(_ items: [(title: String, url: URL)], x: CGFloat?, drop: CGFloat,
              pick: @escaping (URL) -> Void) -> Bool {
        // Nil outside a running app, which is the test's world when no
        // presenter has been injected.
        let app: NSApplication? = NSApp
        guard let view = app?.keyWindow?.contentView else { return false }
        let target = MenuTarget(pick: pick)
        self.target = target
        let menu = NSMenu()
        for item in items {
            let entry = NSMenuItem(title: item.title,
                                   action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            entry.target = target
            entry.representedObject = item.url
            menu.addItem(entry)
        }
        // Under the header rather than at the pointer, so the menu comes out of
        // the control that shows the same list. The flip is AppKit's: a layer
        // backed content view measures from the top, an older one from the
        // bottom.
        let y = view.isFlipped ? drop : view.bounds.height - drop
        menu.popUp(positioning: nil, at: NSPoint(x: x ?? view.bounds.midX, y: y), in: view)
        return true
    }

    /// The anchor is Apple's, and `NSWorkspace.open` answers whether the
    /// system took it. It is not a network URL: `x-apple.systempreferences` is
    /// handled by System Settings on this machine and reaches nothing off it.
    @discardableResult
    func openFolderAccessSettings() -> Bool {
        guard let url = URL(string: AppKitPresenter.filesAndFoldersPane) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Named, so the test can read the string it is about to trust rather than
    /// spell a second copy of it.
    static let filesAndFoldersPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
}

/// `NSMenu` wants a target and a selector; this is the smallest object that is
/// one. There were two of these, identical but for the name of the closure they
/// held (D-197).
@MainActor private final class MenuTarget: NSObject {
    private let pick: (URL) -> Void
    init(pick: @escaping (URL) -> Void) { self.pick = pick }
    @objc func pick(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { pick(url) }
    }
}
