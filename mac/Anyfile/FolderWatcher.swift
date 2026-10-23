// Watched folders: their files join the library by themselves. macOS reports changes in them
// (FSEvents); each change rescans that folder off the main thread and shelves only files not yet there.
import CoreServices
import Foundation
import Observation

/// Calls `changed` with a folder's path whenever something inside it changes. A short latency
/// gathers a burst of changes, such as a whole book being copied in, into one report.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let changed: (String) -> Void

    init?(paths: [String], latency: TimeInterval = 1.0, changed: @escaping (String) -> Void) {
        guard !paths.isEmpty else { return nil }
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            for path in paths.prefix(count) { watcher.changed(path) }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// The folders being watched, kept in UserDefaults, and the watcher over them.
@MainActor @Observable
final class WatchedFolders {
    static let shared = WatchedFolders(library: .shared, defaults: .standard)

    private(set) var paths: [String]
    private let library: Library
    private let defaults: UserDefaults
    @ObservationIgnored private var watcher: FolderWatcher?
    private static let key = "watchedFolders"

    init(library: Library, defaults: UserDefaults) {
        self.library = library
        self.defaults = defaults
        paths = defaults.stringArray(forKey: Self.key) ?? []
    }

    /// Starts watching and catches up with anything added while the app was closed.
    func start() {
        watcher = FolderWatcher(paths: paths) { [weak self] path in
            Task { @MainActor in self?.rescan(containing: path) }
        }
        for path in paths { rescan(folder: path) }
    }

    func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !paths.contains(path) else { return }
        paths.append(path)
        save()
        start()
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        save()
        start()
    }

    /// The watched folder holding a changed path.
    private func rescan(containing path: String) {
        guard let folder = Self.folder(holding: path, among: paths) else { return }
        rescan(folder: folder)
    }

    /// Whole folder names only: a change in ~/Books2 is not a change in ~/Books. Links are followed on
    /// both sides first: FSEvents reports /private/var/… for a folder saved as /var/…, and iCloud
    /// Drive is reached through links too.
    nonisolated static func folder(holding path: String, among folders: [String]) -> String? {
        let real = resolved(path)
        return folders.first { folder in
            let f = resolved(folder)
            return real == f || real.hasPrefix(f.hasSuffix("/") ? f : f + "/")
        }
    }

    nonisolated static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// How many files on the shelf came from a folder.
    func count(in folder: String) -> Int {
        library.entries.filter { Self.folder(holding: $0.path, among: [folder]) != nil }.count
    }

    func rescan(folder: String) {
        let url = URL(fileURLWithPath: folder)
        Task {
            let found = await Task.detached(priority: .utility) { Adding.scan([url]) }.value
            library.addFromFolder(found)
        }
    }

    private func save() { defaults.set(paths, forKey: Self.key) }
}
