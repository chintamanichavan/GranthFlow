import XCTest
import PDFKit
@testable import Anyfile

@MainActor
final class MarkTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-marks-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testMarksAreKeptAcrossLaunchesAndNotDuplicated() {
        let store = dir.appendingPathComponent("marks.json")
        let book = dir.appendingPathComponent("moby.epub")
        let first = MarkStore(file: store)
        let sel = Selection(quote: "  see the watery part of the world \n", target: 1, place: "Loomings")
        let mark = first.add(sel, in: book, kind: "epub", at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(mark?.quote, "see the watery part of the world")
        XCTAssertEqual(first.add(sel, in: book, kind: "epub")?.id, mark?.id)          // same passage, same place: one mark
        XCTAssertEqual(first.marks.count, 1)
        XCTAssertEqual(MarkStore(file: store).marks, first.marks)
    }

    func testEmptySelectionsAreNotMarks() {
        let marks = MarkStore(file: dir.appendingPathComponent("m.json"))
        XCTAssertNil(marks.add(Selection(quote: " \n ", target: 1, place: "Line 1"), in: dir.appendingPathComponent("a.txt"), kind: "text"))
        XCTAssertTrue(marks.marks.isEmpty)
    }

    func testMarksForAFileAreInReadingOrder() {
        let marks = MarkStore(file: dir.appendingPathComponent("m.json"))
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        marks.add(Selection(quote: "late", target: 9, place: "Line 9"), in: a, kind: "text", at: Date(timeIntervalSince1970: 1))
        marks.add(Selection(quote: "early", target: 2, place: "Line 2"), in: a, kind: "text", at: Date(timeIntervalSince1970: 2))
        marks.add(Selection(quote: "other", target: 1, place: "Line 1"), in: b, kind: "text", at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(marks.marks(for: a).map(\.quote), ["early", "late"])
        XCTAssertEqual(marks.all.map(\.quote), ["other", "early", "late"])           // newest first across files
        marks.remove(marks.marks(for: a)[0])
        XCTAssertEqual(marks.marks(for: a).map(\.quote), ["late"])
    }

    func testLongSelectionsAreCutOnAWord() {
        let long = String(repeating: "word ", count: 400)
        let cut = MarkStore.clean(long)
        XCTAssertTrue(cut.hasSuffix("word…"))
        XCTAssertLessThanOrEqual(cut.count, MarkStore.longest + 1)
    }

    func testHighlightRangesAndLines() {
        let ns = "a cat, a cat, a dog\nline two" as NSString
        XCTAssertEqual(Highlights.ranges(of: "a cat", in: ns), [NSRange(location: 0, length: 5), NSRange(location: 7, length: 5)])
        XCTAssertEqual(Highlights.ranges(of: "zebra", in: ns), [])
        XCTAssertEqual(Highlights.line(at: 0, in: ns), 1)
        XCTAssertEqual(Highlights.line(at: 22, in: ns), 2)
    }

    func testHighlightsDoNotChangeTheText() {
        let tv = NSTextView()
        tv.string = "Call me Ishmael."
        Highlights.apply([Paint(quote: "Ishmael", colour: .yellow)], to: tv)
        XCTAssertEqual(tv.string, "Call me Ishmael.")
        let painted = tv.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 9, effectiveRange: nil)
        XCTAssertNotNil(painted)
        XCTAssertNil(tv.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 2, effectiveRange: nil))
        XCTAssertNil(tv.textStorage?.attribute(.backgroundColor, at: 9, effectiveRange: nil))      // not stored in the text
    }

    func testPdfMarksAreFoundOnTheirPage() {
        let doc = PDFDocument(data: Data(Fixtures.tinyPdf.utf8))
        let here = Mark(path: "/t.pdf", kind: "pdf", quote: "PDF World", target: 0, place: "Page 1")
        let wrongPage = Mark(path: "/t.pdf", kind: "pdf", quote: "PDF World", target: 3, place: "Page 4")
        let absent = Mark(path: "/t.pdf", kind: "pdf", quote: "nowhere", target: 0, place: "Page 1")
        let found = PdfKitView.selections(for: [here, wrongPage, absent], in: doc)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.string, "PDF World")
    }

    func testMarkAvailability() {
        XCTAssertNil(DocumentAction.mark.unavailableReason(for: "epub"))
        XCTAssertNil(DocumentAction.mark.unavailableReason(for: "pdf"))
        XCTAssertNil(DocumentAction.mark.unavailableReason(for: "text"))
        XCTAssertNil(DocumentAction.mark.unavailableReason(for: "binary"))                        // bytes can be marked now
        XCTAssertEqual(MarkHint.text(kind: "markdown"), "Select a passage, then press Mark")     // the preview marks too
    }
}
