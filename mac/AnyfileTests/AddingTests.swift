import XCTest
@testable import Anyfile

@MainActor
final class AddingTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-adding-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    private func write(_ data: Data, _ path: String) -> URL {
        let url = dir.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! data.write(to: url)
        return url
    }

    func testFoldersAreWalkedAndHiddenThingsSkipped() {
        let a = write(Data("a".utf8), "Books/a.txt")
        let b = write(Data("b".utf8), "Books/Inner/b.md")
        write(Data("x".utf8), "Books/.hidden.txt")
        write(Data("x".utf8), "Books/.cache/inside.txt")
        write(Data("x".utf8), "Books/Thing.app/Contents/Info.plist")                 // a package: not walked into
        let found = Set(Adding.files(in: [dir.appendingPathComponent("Books")]).map(\.lastPathComponent))
        XCTAssertEqual(found, [a.lastPathComponent, b.lastPathComponent])
        XCTAssertEqual(Adding.files(in: [dir.appendingPathComponent("missing")]), [])
        XCTAssertEqual(Adding.files(in: [dir.appendingPathComponent("Books")], limit: 1).count, 1)
    }

    func testKindsComeFromTheStartOfTheFile() {
        // A book larger than the 64 KB read, so the kind must come from its start alone.
        let big = String(repeating: "Call me Ishmael. ", count: 8000)
        let epub = Fixtures.zip([
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"b.opf\"/></rootfiles></container>"),
            ("b.opf", "<package version=\"3.0\"><metadata/><manifest><item id=\"a\" href=\"a.xhtml\"/></manifest><spine><itemref idref=\"a\"/></spine></package>"),
            ("a.xhtml", "<html><body><p>\(big)</p></body></html>"),
        ])
        XCTAssertGreaterThan(epub.count, 1 << 16)
        XCTAssertEqual(Adding.kind(of: write(epub, "big.epub")), "epub")
        XCTAssertEqual(Adding.kind(of: write(Data(Fixtures.tinyPdf.utf8), "t.pdf")), "pdf")
        XCTAssertEqual(Adding.kind(of: write(Data("# Notes\n".utf8), "n.md")), "markdown")
        XCTAssertEqual(Adding.kind(of: write(Fixtures.binary, "blob")), "binary")
        XCTAssertNil(Adding.kind(of: dir.appendingPathComponent("missing")))
    }

    func testDroppedFilesJoinTheShelfOnceAndSaveOnce() throws {
        let store = dir.appendingPathComponent("l.json")
        let lib = Library(file: store)
        let a = write(Data("a".utf8), "a.txt"), b = write(Data("# b".utf8), "b.md")
        XCTAssertEqual(lib.add(Adding.scan([a, b])), 2)
        XCTAssertEqual(lib.add(Adding.scan([a]), at: Date().addingTimeInterval(60)), 0)   // already there: moved to the front
        XCTAssertEqual(Library(file: store).recent.first?.name, "a.txt")
        XCTAssertEqual(Library(file: store).entries.count, 2)
        XCTAssertEqual(Set(Library(file: store).entries.map(\.kind)), ["text", "markdown"])
    }

    /// A folder of 500 files: the scan runs off the main thread, the shelving on it. Prints both times.
    func testAddingSpeedForAFolderOf500() {
        for i in 0..<500 { write(Data("note \(i)\n".utf8), "Big/n\(i).md") }
        var start = Date()
        let found = Adding.scan([dir.appendingPathComponent("Big")])
        let scan = Date().timeIntervalSince(start)
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        start = Date()
        XCTAssertEqual(lib.add(found), 500)
        let shelve = Date().timeIntervalSince(start)
        print(String(format: "adding 500 files: scan %.3f s (background), shelve %.3f s (main)", scan, shelve))
        XCTAssertLessThan(shelve, 0.1)
    }
}
