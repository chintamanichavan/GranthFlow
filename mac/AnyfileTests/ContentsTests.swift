import XCTest
import PDFKit
@testable import Anyfile

final class ContentsTests: XCTestCase {
    func testContentsOnlyForKindsWithStructure() {
        XCTAssertNil(DocumentAction.contents.unavailableReason(for: "pdf"))
        XCTAssertNil(DocumentAction.contents.unavailableReason(for: "epub"))
        XCTAssertNil(DocumentAction.contents.unavailableReason(for: "markdown"))
        XCTAssertNotNil(DocumentAction.contents.unavailableReason(for: "text"))
        XCTAssertNotNil(DocumentAction.contents.unavailableReason(for: "binary"))
        XCTAssertNil(DocumentAction.info.unavailableReason(for: "binary"))
    }

    func testOutlineParsingKeepsLevelsAndLines() {
        let entries = Contents.parseOutline("1\tTitle\n5\t  Status\n7\t    Deep\nbad line\n9\t  Tabs\tinside\n")
        XCTAssertEqual(entries.map(\.title), ["Title", "Status", "Deep", "Tabs\tinside"])
        XCTAssertEqual(entries.map(\.level), [0, 1, 2, 1])
        XCTAssertEqual(entries.map(\.target), [1, 5, 7, 9])
        XCTAssertEqual(entries.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(Contents.parseOutline(""), [])
    }

    func testMarkdownEntriesComeFromTheEngine() {
        let doc = AnyfileDocument(data: Data(Fixtures.markdown.utf8), name: "n.md")
        XCTAssertEqual(Contents.entries(for: doc).map(\.title), ["Title", "Status"])
        XCTAssertEqual(Contents.entries(for: doc).map(\.target), [1, 5])
    }

    func testEpubEntriesAreChapterNumbers() {
        let doc = AnyfileDocument(data: Fixtures.epub, name: "b.epub")
        let entries = Contents.entries(for: doc)
        XCTAssertEqual(entries.map(\.title), ["Opening", "Second Heading"])
        XCTAssertEqual(entries.map(\.target), [1, 2])
    }

    func testPdfWithoutOutlineListsPages() {
        let doc = AnyfileDocument(data: Data(Fixtures.tinyPdf.utf8), name: "t.pdf")
        let entries = Contents.entries(for: doc)
        XCTAssertEqual(entries.map(\.title), ["Page 1"])
        XCTAssertEqual(entries.first?.target, 0)
        XCTAssertEqual(Contents.pdf(nil), [])
    }

    func testPdfOutlineIsFlattenedWithLevels() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: Data(Fixtures.tinyPdf.utf8)))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let root = PDFOutline()
        let part = PDFOutline(); part.label = "Part"; part.destination = PDFDestination(page: page, at: .zero)
        let child = PDFOutline(); child.label = "Section"; child.destination = PDFDestination(page: page, at: .zero)
        let noDest = PDFOutline(); noDest.label = "Nowhere"
        part.insertChild(child, at: 0)
        root.insertChild(part, at: 0)
        root.insertChild(noDest, at: 1)
        pdf.outlineRoot = root
        let entries = Contents.pdf(pdf)
        XCTAssertEqual(entries.map(\.title), ["Part", "Section"])     // an item with no destination is skipped
        XCTAssertEqual(entries.map(\.level), [0, 1])
        XCTAssertEqual(entries.map(\.id), [0, 1])                     // unique even though both point at page 0
    }

    func testTextAndBinaryHaveNoEntries() {
        XCTAssertEqual(Contents.entries(for: AnyfileDocument(data: Data("x".utf8), name: "a.txt")), [])
        XCTAssertEqual(Contents.entries(for: AnyfileDocument(data: Fixtures.binary, name: "a.bin")), [])
    }

    func testJumpIsNewEachTimeEvenToTheSameTarget() {
        let first = Jump(target: 5, serial: 0).next(5)
        XCTAssertNotEqual(first, first.next(5))
        XCTAssertEqual(first.next(9).target, 9)
    }

    func testLineRanges() {
        let text = "one\ntwo\n\nfour"
        XCTAssertEqual(TextPane.range(ofLine: 1, in: text), NSRange(location: 0, length: 3))
        XCTAssertEqual(TextPane.range(ofLine: 2, in: text), NSRange(location: 4, length: 3))
        XCTAssertEqual(TextPane.range(ofLine: 3, in: text), NSRange(location: 8, length: 0))
        XCTAssertEqual(TextPane.range(ofLine: 4, in: text), NSRange(location: 9, length: 4))
        XCTAssertNil(TextPane.range(ofLine: 5, in: text))
        XCTAssertNil(TextPane.range(ofLine: 0, in: text))
        XCTAssertEqual(TextPane.range(ofLine: 2, in: "é😀\nx"), NSRange(location: 4, length: 1))   // UTF-16 offsets
    }

    func testEveryHeadingInThePreviewCanBeJumpedTo() {
        let source = "intro\n# One\nbody\n```\n# not a heading\n```\n## Two\n"
        let preview = MarkdownRenderer.render(source)
        let outline = Contents.parseOutline(Engine.run("outline", args: [], on: Data(source.utf8), name: "s.md", kind: "markdown").output)
        XCTAssertEqual(outline.map(\.target), [2, 7])
        for entry in outline {
            let c = try! XCTUnwrap(MarkdownRenderer.character(forLine: entry.target, in: preview))
            XCTAssertEqual(MarkdownRenderer.sourceLine(at: c, in: preview), entry.target)                     // lands on the heading
        }
        let fenced = (preview.string as NSString).range(of: "# not a heading").location
        XCTAssertEqual(MarkdownRenderer.sourceLine(at: fenced, in: preview), 5)                             // kept, as code, on its own line
        XCTAssertFalse(preview.string.contains("```"))
    }

}
