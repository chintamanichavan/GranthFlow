import XCTest
import SwiftUI
@testable import Anyfile

final class CoverTests: XCTestCase {
    func testBookCoverTakesTitleAndAuthorFromTheBook() {
        guard case let .book(title, author, cloth) = Cover.art(for: Fixtures.epub, name: "b.epub", kind: "epub") else { return XCTFail("not a book") }
        XCTAssertEqual(title, ["Tiny Book"])
        XCTAssertEqual(author, "Tester")
        XCTAssertEqual(cloth, Int(Cover.stableHash("Tiny Book") % UInt64(Cover.cloths.count)))
    }

    func testStableHashIsFnv1a() {
        XCTAssertEqual(Cover.stableHash(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(Cover.stableHash("a"), 0xaf63_dc4c_8601_ec8c)      // published FNV-1a test vector
    }

    func testTitleLines() {
        XCTAssertEqual(Cover.titleLines("Moby-Dick"), ["Moby-Dick"])
        XCTAssertEqual(Cover.titleLines("Pride and Prejudice"), ["Pride and", "Prejudice"])
        XCTAssertEqual(Cover.titleLines("one two three four five six seven eight nine"), ["one two", "three four", "five six…"])
        XCTAssertEqual(Cover.titleLines(""), [""])
    }

    func testMetaField() {
        XCTAssertEqual(Cover.field("title", in: "title: Moby-Dick\ncreator: Herman Melville\n"), "Moby-Dick")
        XCTAssertEqual(Cover.field("creator", in: "Creator:  Melville \n"), "Melville")
        XCTAssertNil(Cover.field("title", in: "title:\n"))
        XCTAssertNil(Cover.field("title", in: ""))
    }

    func testNoteCoverUsesTheFirstHeading() {
        let md = "intro line\n# Project notes\n\nReader works.\n## Status\n- open\n"
        guard case let .note(heading, rows) = Cover.art(for: Data(md.utf8), name: "p.md", kind: "markdown") else { return XCTFail("not a note") }
        XCTAssertEqual(heading, "Project notes")
        XCTAssertEqual(rows, ["intro line", "Reader works.", "## Status", "- open"])
        guard case let .note(fallback, _) = Cover.art(for: Data("no heading".utf8), name: "plan.md", kind: "markdown") else { return XCTFail() }
        XCTAssertEqual(fallback, "plan")
    }

    func testTextCoverShowsTheFirstLines() {
        let text = (1...20).map { "line \($0) " + String(repeating: "x", count: 40) }.joined(separator: "\n")
        guard case let .text(rows) = Cover.art(for: Data(text.utf8), name: "a.txt", kind: "text") else { return XCTFail("not text") }
        XCTAssertEqual(rows.count, 9)
        XCTAssertTrue(rows.allSatisfy { $0.count <= 28 })
        XCTAssertTrue(rows[0].hasPrefix("line 1 "))
    }

    func testPdfCoverIsItsFirstPage() {
        guard case let .page(thumb) = Cover.art(for: Data(Fixtures.tinyPdf.utf8), name: "t.pdf", kind: "pdf") else { return XCTFail("not a page") }
        XCTAssertNotNil(thumb)
        guard case let .page(none) = Cover.art(for: Data("%PDF-1.4 broken".utf8), name: "b.pdf", kind: "pdf") else { return XCTFail() }
        XCTAssertNil(none)
    }

    func testByteMapReadsWhatTheBytesAre() {
        let cells = Cover.mapCols * Cover.mapRows
        XCTAssertEqual(Cover.byteMap(Data()), [])
        XCTAssertEqual(Cover.byteMap(Data(count: cells * 8)), [UInt8](repeating: 0, count: cells))           // empty
        XCTAssertEqual(Set(Cover.byteMap(Data(String(repeating: "Call me Ishmael. ", count: 3000).utf8))), [4])   // text
        var rng = SystemRandomNumberGenerator()
        let random = Data((0..<cells * 512).map { _ in UInt8.random(in: 0...255, using: &rng) })
        XCTAssertEqual(Set(Cover.byteMap(random)), [6])                                                 // compressed or random
        let flat = Data((0..<cells * 64).map { UInt8(0x80 | ($0 / 64 % 2)) })
        XCTAssertEqual(Set(Cover.byteMap(flat)), [1])                                                   // two values only: low entropy
    }

    func testSmallFilesFillOnlyTheTopCells() {
        XCTAssertEqual(Cover.byteMap(Data([1, 2, 3])).count, 3)
        XCTAssertEqual(Cover.byteMap(Data(count: 5000)).count, (5000 + 3) / 4)       // blocks of 4 bytes
    }

    func testRealProgramGetsAVariedMap() throws {
        let zsh = try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh"))
        let map = Cover.byteMap(zsh)
        XCTAssertEqual(map.count, Cover.mapCols * Cover.mapRows)
        XCTAssertGreaterThanOrEqual(Set(map).count, 4, "a real program has empty, code and text regions")
    }

    /// Covers are made for every file on the shelf, so the byte map must be quick. Prints the time.
    func testByteMapSpeedOnFiftyMegabytes() {
        let data = Data((0..<50_000_000).map { UInt8(truncatingIfNeeded: $0 &* 2654435761 >> 13) })
        let start = Date()
        let map = Cover.byteMap(data)
        let seconds = Date().timeIntervalSince(start)
        print(String(format: "byte map of 50 MB: %.3f s", seconds))
        XCTAssertEqual(map.count, Cover.mapCols * Cover.mapRows)
        XCTAssertLessThan(seconds, 1.0)
    }
}

@MainActor
final class CoverRenderTests: XCTestCase {
    func testAShelfOfCoversDraws() throws {
        let zsh = try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh"))
        let report = "# Q3 Report\n\nCosts held flat.\n"
        let arts: [CoverArt] = [
            .book(title: ["Moby-Dick"], author: "Herman Melville", cloth: 0),
            .book(title: Cover.titleLines("Pride and Prejudice"), author: "Jane Austen", cloth: 1),
            Cover.art(for: Data(Fixtures.tinyPdf.utf8), name: "t.pdf", kind: "pdf"),
            Cover.art(for: Data("# Project notes\n\nReader and editor both work.\n\n## Status\n- Books open\n- Every edit can be undone\n".utf8), name: "n.md", kind: "markdown"),
            Cover.art(for: Data("# server settings\nhost=localhost\nport=8080\ndebug=false\n".utf8), name: "s.conf", kind: "text"),
            Cover.art(for: zsh, name: "zsh", kind: "binary"),
            Cover.art(for: Data(report.utf8), name: "r.md", kind: "markdown"),
        ]
        let shelf = HStack(spacing: 18) { ForEach(arts.indices, id: \.self) { CoverView(art: arts[$0]).frame(width: 120) } }
            .padding(24)
            .background(Color(nsColor: NSColor(hex: "#F5F4F0")!))
        let renderer = ImageRenderer(content: shelf)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.height, 168 + 48, accuracy: 1)
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("covers.png"))
        }
    }
}
