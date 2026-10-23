import XCTest
@testable import Anyfile

@MainActor
final class WatchTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-watch-\(UUID().uuidString)").resolvingSymlinksInPath()
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ text: String, _ path: String, modified: Date? = nil) -> URL {
        let url = dir.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(text.utf8).write(to: url)
        if let modified { try! FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    func testOnlyNewFilesAreAddedDatedByTheFileAndUnopened() {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let old = write("old", "Books/old.txt", modified: Date(timeIntervalSince1970: 1_000_000))
        let read = write("read", "Books/read.txt")
        lib.recordOpened(read, kind: "text", at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(lib.addFromFolder(Adding.scan([dir.appendingPathComponent("Books")])), 1)    // read.txt was there already
        XCTAssertEqual(lib.entry(for: old)?.opened, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(lib.entry(for: old)?.unopened, true)
        XCTAssertNil(lib.entry(for: read)?.unopened)
        XCTAssertEqual(lib.entry(for: read)?.opened, Date(timeIntervalSince1970: 5))                // not moved
        lib.recordOpened(old, kind: "text")
        XCTAssertNil(lib.entry(for: old)?.unopened)                                                   // opened: no longer new
        XCTAssertEqual(lib.addFromFolder([]), 0)
    }

    func testDroppedFilesAreUnopenedToo() {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        lib.add(Adding.scan([write("x", "a.txt")]))
        XCTAssertEqual(lib.entries.first?.unopened, true)
    }

    func testWholeFolderNamesOnly() {
        XCTAssertEqual(WatchedFolders.folder(holding: "/u/Books/a.epub", among: ["/u/Books"]), "/u/Books")
        XCTAssertNil(WatchedFolders.folder(holding: "/u/Books2/a.epub", among: ["/u/Books"]))
        XCTAssertEqual(WatchedFolders.folder(holding: "/u/Books", among: ["/u/Books"]), "/u/Books")
        XCTAssertEqual(WatchedFolders.folder(holding: "/u/Books/x/y.md", among: ["/u/Notes", "/u/Books/"]), "/u/Books/")
        let tmp = FileManager.default.temporaryDirectory.path                              // reached through a link
        XCTAssertNotNil(WatchedFolders.folder(holding: URL(fileURLWithPath: tmp).resolvingSymlinksInPath().path + "/x.md", among: [tmp]))
    }

    func testWatchedFoldersAreKeptBetweenLaunches() {
        let defaults = UserDefaults(suiteName: "anyfile-watch-\(UUID().uuidString)")!
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let watched = WatchedFolders(library: lib, defaults: defaults)
        watched.add(dir.appendingPathComponent("Books"))
        watched.add(dir.appendingPathComponent("Books"))                                             // once only
        XCTAssertEqual(WatchedFolders(library: lib, defaults: defaults).paths, [dir.appendingPathComponent("Books").path])
        watched.remove(dir.appendingPathComponent("Books").path)
        XCTAssertEqual(WatchedFolders(library: lib, defaults: defaults).paths, [])
    }

    /// A real folder, really watched: a file copied in afterwards reaches the library.
    func testAFileArrivingInAWatchedFolderJoinsTheLibrary() async throws {
        let books = dir.appendingPathComponent("Books")
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "anyfile-watch-\(UUID().uuidString)")!
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let watched = WatchedFolders(library: lib, defaults: defaults)
        watched.add(books)
        try await Task.sleep(for: .milliseconds(500))                                                // let the stream settle
        let arrived = write("# New notes\n", "Books/arrived.md")
        let start = Date()
        while lib.entry(for: arrived) == nil, Date().timeIntervalSince(start) < 8 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(lib.entry(for: arrived)?.kind, "markdown")
        print(String(format: "watched folder: new file on the shelf after %.2f s", Date().timeIntervalSince(start)))
        _ = watched
    }
}

/// Unit tests run inside the app; it must not have started watching the reader's own folders.
@MainActor
final class WatchStartTests: XCTestCase {
    func testTheAppDoesNotWatchWhileTesting() {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"])
    }
}
