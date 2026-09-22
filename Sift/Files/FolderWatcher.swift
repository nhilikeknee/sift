import Foundation

/// Fires (debounced) when the open folder changes, and — while subfolders are
/// included — when any folder under it does. A card copying in fills its
/// subfolders one at a time, and a viewer that only watches the top folder
/// shows a shoot that stopped growing ten seconds ago (D-38).
@MainActor
final class FolderWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?

    /// `depth` 0 watches the folder alone. 1 adds its subfolders, which is as
    /// deep as a card goes and keeps the descriptor count in single figures.
    func watch(_ url: URL, depth: Int = 0, onChange: @escaping @MainActor () -> Void) {
        stop()
        var folders = [url]
        if depth > 0 { folders += FolderScanner.subfolders(of: url) }
        for folder in folders { addSource(folder, onChange: onChange) }
    }

    private func addSource(_ url: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                onChange()
            }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        sources.append(s)
    }

    func stop() {
        for s in sources { s.cancel() }
        sources = []
    }
}
