import AppKit

/// A card goes in, and the app that culls cards should say so. Watches for a
/// removable volume mounting and reports the folder worth opening on it: DCIM
/// if the camera wrote one, otherwise the volume root (D-39).
@MainActor
final class VolumeWatcher {
    private var token: (any NSObjectProtocol)?

    func start(onMount: @escaping @MainActor (URL, String) -> Void) {
        stop()
        token = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                guard let target = Self.photoFolder(on: url) else { return }
                onMount(target, url.lastPathComponent)
            }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    /// Only removable, local volumes: a mounted disk image of a backup is not a
    /// card, and neither is a network share.
    static func photoFolder(on volume: URL) -> URL? {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey]
        guard let v = try? volume.resourceValues(forKeys: keys),
              v.volumeIsLocal == true,
              v.volumeIsRemovable == true || v.volumeIsEjectable == true else { return nil }
        let dcim = volume.appendingPathComponent("DCIM")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dcim.path, isDirectory: &isDir), isDir.boolValue { return dcim }
        // No DCIM: worth offering only if there are photos to be found.
        let hasImages = !FolderScanner.subfolders(of: volume).isEmpty || FolderScanner.preview(of: volume).count > 0
        return hasImages ? volume : nil
    }
}
