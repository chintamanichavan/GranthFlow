import XCTest
@testable import Anyfile

final class SearchTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-search-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func entry(_ data: Data, _ name: String, _ kind: String) -> LibraryEntry {
        let url = dir.appendingPathComponent(name)
        try! data.write(to: url)
        return LibraryEntry(path: url.path, kind: kind, opened: Date())
    }

    func testFindsAcrossEveryKind() {
        let entries = [
            entry(Fixtures.epub, "b.epub", "epub"),
            entry(Data(Fixtures.tinyPdf.utf8), "t.pdf", "pdf"),
            entry(Data("# Notes\nhello there\n".utf8), "n.md", "markdown"),
            entry(Data("nothing to see\n".utf8), "a.txt", "text"),
            entry(Data([0, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0]), "blob", "binary"),
        ]
        let results = Search.run("hello", in: Search.prepare(entries))
        XCTAssertEqual(results.map(\.entry.name), ["b.epub", "t.pdf", "n.md", "blob"])   // library order, files with matches only
        XCTAssertEqual(results[0].hits.first?.target, 1)          // chapter
        XCTAssertEqual(results[1].hits.first?.target, 0)          // page index
        XCTAssertEqual(results[2].hits.first?.target, 2)          // line
        XCTAssertEqual(results[3].hits.first?.target, 1)          // byte offset
        XCTAssertEqual(Search.run("", in: Search.prepare(entries)).count, 0)
    }

    func testMissingFilesAreSkippedQuietly() {
        let gone = LibraryEntry(path: dir.appendingPathComponent("gone.txt").path, kind: "text", opened: Date())
        let prepared = Search.prepare([gone])
        XCTAssertEqual(prepared.count, 1)
        XCTAssertEqual(Search.run("x", in: prepared).count, 0)
    }

    func testPreparedFilesAreReusedUntilTheyChange() throws {
        let a = entry(Data("alpha\n".utf8), "a.txt", "text"), b = entry(Data("beta\n".utf8), "b.txt", "text")
        let first = Search.prepare([a, b])
        let second = Search.prepare([a, b], reusing: first)
        XCTAssertTrue(first[0] === second[0] && first[1] === second[1])
        try Data("alpha gamma\n".utf8).write(to: a.url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: a.path)
        let third = Search.prepare([a, b], reusing: second)
        XCTAssertFalse(third[0] === second[0])                    // changed on disk: read again
        XCTAssertTrue(third[1] === second[1])
        XCTAssertEqual(Search.run("gamma", in: third).map(\.entry.name), ["a.txt"])
    }

    /// A library of 20 files with one long book and one big text. Prints both times.
    func testSearchSpeedOnATwentyFileLibrary() {
        let paragraph = String(repeating: "Call me Ishmael. Some years ago, never mind how long precisely. ", count: 160)
        var files: [(name: String, content: String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
        ]
        let ids = (1...135).map { "c\($0)" }
        files.append(("OPS/book.opf", "<package version=\"3.0\"><metadata/><manifest>"
            + ids.map { "<item id=\"\($0)\" href=\"\($0).xhtml\"/>" }.joined()
            + "</manifest><spine>" + ids.map { "<itemref idref=\"\($0)\"/>" }.joined() + "</spine></package>"))
        for id in ids { files.append(("OPS/\(id).xhtml", "<html><body><p>\(paragraph)</p></body></html>")) }
        var entries = [entry(Fixtures.zip(files), "moby.epub", "epub"),
                       entry(Data(String(repeating: "The quick brown fox jumps over the lazy dog.\n", count: 180_000).utf8), "big.txt", "text")]
        for i in 0..<9 { entries.append(entry(Data("# Note \(i)\nwhale \(i)\n".utf8), "n\(i).md", "markdown")) }
        for i in 0..<9 { entries.append(entry(Data(Fixtures.tinyPdf.utf8), "p\(i).pdf", "pdf")) }

        var start = Date()
        let corpus = Search.prepare(entries)
        let prepare = Date().timeIntervalSince(start)
        start = Date()
        let results = Search.run("whale", in: corpus)
        let search = Date().timeIntervalSince(start)
        print(String(format: "search every file (20 files): prepare %.3f s, then each search %.3f s", prepare, search))
        XCTAssertEqual(results.count, 9)
        XCTAssertLessThan(search, 0.25)
    }
}
