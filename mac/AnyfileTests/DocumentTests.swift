import XCTest
@testable import Anyfile

final class DocumentTests: XCTestCase {
    func testInitDetectsKindFromNameAndBytes() {
        XCTAssertEqual(AnyfileDocument(data: Data("# x".utf8), name: "a.md").kind, "markdown")
        XCTAssertEqual(AnyfileDocument(data: Data(Fixtures.tinyPdf.utf8), name: "a.pdf").kind, "pdf")
        XCTAssertEqual(AnyfileDocument(data: Fixtures.binary, name: "a.bin").kind, "binary")
        XCTAssertEqual(AnyfileDocument().kind, "text")
        let book = AnyfileDocument(data: Fixtures.epub, name: "a.epub")
        XCTAssertEqual(book.kind, "epub")
        XCTAssertFalse(book.isTextual)
    }

    func testEpubChapterParsing() {
        let chapters = EpubChapter.parse("1\tOpening\tOPS/a.xhtml\n2\tTabs\tOPS/odd\tname.xhtml\n\nnot a row\nx\ty\tz\n3\t\tOPS/c.xhtml\n")
        XCTAssertEqual(chapters.map(\.number), [1, 2, 3])
        XCTAssertEqual(chapters[0], EpubChapter(number: 1, title: "Opening", path: "OPS/a.xhtml"))
        XCTAssertEqual(chapters[1].path, "OPS/odd\tname.xhtml")     // only the first two tabs separate fields
        XCTAssertEqual(chapters[2].title, "")
        XCTAssertEqual(EpubChapter.parse(""), [])
    }

    func testEpubChapterParsingMatchesEngineOutput() {
        let out = Engine.run("chapters", args: [], on: Fixtures.epub, name: "b.epub", kind: "epub").output
        XCTAssertEqual(EpubChapter.parse(out).map(\.title), ["Opening", "Second Heading"])
    }

    func testTextAccessorRoundTripsBytes() {
        var d = AnyfileDocument(data: Data("abc".utf8), name: "a.txt")
        XCTAssertTrue(d.isTextual)
        d.text = "xyz\n"
        XCTAssertEqual(d.data, Data("xyz\n".utf8))
        XCTAssertEqual(d.text, "xyz\n")
    }

    func testApplyUsesChangedDataOnly() {
        var d = AnyfileDocument(data: Data("abc".utf8), name: "a.txt")
        XCTAssertFalse(d.apply(RunResult(status: .ok, output: "", errorText: "", changedData: nil)))
        XCTAssertEqual(d.text, "abc")
        XCTAssertTrue(d.apply(RunResult(status: .ok, output: "", errorText: "", changedData: Data("new".utf8))))
        XCTAssertEqual(d.text, "new")
    }

    func testMarkdownRendererHeadingsAndFences() {
        XCTAssertEqual(MarkdownRenderer.headingLevel("## Two"), 2)
        XCTAssertEqual(MarkdownRenderer.headingLevel("#"), 1)
        XCTAssertNil(MarkdownRenderer.headingLevel("#notaheading"))
        XCTAssertNil(MarkdownRenderer.headingLevel("####### seven"))
        let rendered = MarkdownRenderer.render("# T\n\n```\n# code\n```\n- item\n")
        let plain = rendered.string
        XCTAssertTrue(plain.hasPrefix("T\n"))
        XCTAssertTrue(plain.contains("# code"))         // fenced line kept verbatim
        XCTAssertTrue(plain.contains("•  item"))
        XCTAssertFalse(plain.contains("```"))
    }
}
