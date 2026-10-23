import XCTest
@testable import Anyfile

@MainActor
final class LibraryTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-library-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! Data("x".utf8).write(to: url)
        return url
    }

    func testRemembersAcrossLaunches() throws {
        let store = dir.appendingPathComponent("library.json")
        let book = file("moby.epub")
        let first = Library(file: store)
        first.recordOpened(book, kind: "epub", at: Date(timeIntervalSince1970: 1000))
        first.recordPosition(book, position: 4, total: 135)
        let second = Library(file: store)
        XCTAssertEqual(second.entries, first.entries)
        XCTAssertEqual(second.entry(for: book)?.position, 4)
        let json = try String(contentsOf: store, encoding: .utf8)
        XCTAssertTrue(json.contains("\"position\" : 4"), json)          // plain, readable text
        XCTAssertTrue(json.contains("1970-01-01T00:16:40Z"), json)
    }

    func testRecentIsNewestFirstAndSkipsMissingFiles() {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let a = file("a.txt"), b = file("b.txt"), gone = file("gone.txt")
        lib.recordOpened(a, kind: "text", at: Date(timeIntervalSince1970: 1))
        lib.recordOpened(b, kind: "text", at: Date(timeIntervalSince1970: 3))
        lib.recordOpened(gone, kind: "text", at: Date(timeIntervalSince1970: 2))
        try! FileManager.default.removeItem(at: gone)
        lib.checkFiles()                                                            // as the window does when it comes forward
        XCTAssertEqual(lib.recent.map(\.name), ["b.txt", "a.txt"])
        lib.recordOpened(a, kind: "text", at: Date(timeIntervalSince1970: 9))       // reopening moves it to the front
        XCTAssertEqual(lib.recent.map(\.name), ["a.txt", "b.txt"])
        XCTAssertEqual(lib.entries.count, 3)                                        // reopened, not duplicated
    }

    func testContinueReadingHoldsUnfinishedBooksAndDocuments() {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let book = file("b.epub"), done = file("d.epub"), pdf = file("p.pdf"), note = file("n.md")
        for (i, (url, kind)) in [(book, "epub"), (done, "epub"), (pdf, "pdf"), (note, "markdown")].enumerated() {
            lib.recordOpened(url, kind: kind, at: Date(timeIntervalSince1970: Double(i)))
        }
        lib.recordPosition(book, position: 4, total: 135)
        lib.recordPosition(done, position: 135, total: 135)
        lib.recordPosition(pdf, position: 2, total: 12)
        XCTAssertEqual(lib.continueReading.map(\.name), ["p.pdf", "b.epub"])
    }

    func testProgressWording() {
        var e = LibraryEntry(path: "/x.epub", kind: "epub", opened: Date(), position: 4, total: 135)
        XCTAssertEqual(e.progressText, "Chapter 4 of 135")
        e.position = 135
        XCTAssertEqual(e.progressText, "Finished")
        XCTAssertFalse(e.isUnfinished)
        let pdf = LibraryEntry(path: "/x.pdf", kind: "pdf", opened: Date(), position: 0, total: 12)
        XCTAssertEqual(pdf.progressText, "Page 1 of 12")                         // page indexes are 0-based
        XCTAssertEqual(pdf.progress!, 1.0 / 12, accuracy: 1e-9)
        XCTAssertNil(LibraryEntry(path: "/n.md", kind: "markdown", opened: Date()).progressText)
    }

    func testOldestAreForgottenPastTheLimit() {
        let lib = Library(file: dir.appendingPathComponent("l.json"), limit: 40)
        for i in 0...lib.limit {
            lib.recordOpened(URL(fileURLWithPath: "/tmp/f\(i)"), kind: "text", at: Date(timeIntervalSince1970: Double(i)))
        }
        XCTAssertEqual(lib.entries.count, lib.limit)
        XCTAssertNil(lib.entry(for: URL(fileURLWithPath: "/tmp/f0")))
    }

    func testAnUnreadableLibraryStartsEmpty() throws {
        let store = dir.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: store)
        XCTAssertEqual(Library(file: store).entries, [])
    }

    func testKindLabels() throws {
        XCTAssertEqual(KindLabel.label(kind: "epub"), "Book")
        XCTAssertEqual(KindLabel.label(kind: "binary", data: Data([0x7f, 0x45, 0x4c, 0x46, 0])), "Program")
        XCTAssertEqual(KindLabel.label(kind: "binary", data: try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh"))), "Program")
        XCTAssertEqual(KindLabel.label(kind: "binary", data: Data([0x89, 0x50, 0x4e, 0x47])), "Data")
        XCTAssertEqual(KindLabel.label(kind: "binary", data: Data([0x4d, 0x5a])), "Program")
        XCTAssertEqual(KindLabel.label(kind: "binary"), "Data")
    }

    /// The window reads `recent` about ten times per redraw; a reading place saves the whole library.
    /// Both at the full 5000 files. Prints the times.
    func testSpeedAtTheLimit() {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let found = (0..<Library.defaultLimit).map { (url: URL(fileURLWithPath: "/tmp/book\($0).epub"), kind: "epub") }
        lib.add(found, at: Date(timeIntervalSince1970: 0))
        lib.checkFiles()
        var start = Date()
        for _ in 0..<10 { _ = lib.recent }
        let redraw = Date().timeIntervalSince(start)
        start = Date()
        lib.recordPosition(URL(fileURLWithPath: "/tmp/book7.epub"), position: 3, total: 9)
        let save = Date().timeIntervalSince(start)
        print(String(format: "library of %d: recent x10 %.4f s, one save %.4f s", lib.entries.count, redraw, save))
        XCTAssertLessThan(redraw, 0.05)
        XCTAssertLessThan(save, 0.1)
    }

}
