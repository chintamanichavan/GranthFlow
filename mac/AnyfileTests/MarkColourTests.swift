import XCTest
import PDFKit
@testable import Anyfile

@MainActor
final class MarkColourTests: XCTestCase {
    func testAColourIsKeptAndOldMarksAreYellow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-colour-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("m.json")
        let marks = MarkStore(file: store)
        let mark = try XCTUnwrap(marks.add(Selection(quote: "a quote", target: 1, place: "Line 1"), in: dir.appendingPathComponent("a.txt"), kind: "text"))
        XCTAssertEqual(mark.colour, .yellow)                                          // new marks start yellow
        marks.setColour(.pink, for: mark)
        XCTAssertEqual(MarkStore(file: store).marks.first?.colour, .pink)

        let old = dir.appendingPathComponent("old.json")
        try Data(#"[{"created":"2026-10-21T00:00:00Z","id":"6F1D1D3E-6E2B-4C5B-9A61-1A2B3C4D5E6F","kind":"text","path":"/a","place":"Line 1","quote":"q","target":1}]"#.utf8).write(to: old)
        XCTAssertEqual(MarkStore(file: old).marks.first?.colour, .yellow)
    }

    func testEachPassageIsPaintedInItsOwnColour() {
        let tv = NSTextView()
        tv.string = "an idea, and a quote"
        Highlights.apply([Paint(quote: "an idea", colour: .yellow), Paint(quote: "a quote", colour: .pink)], to: tv)
        let first = tv.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor
        let second = tv.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 15, effectiveRange: nil) as? NSColor
        XCTAssertEqual(first?.withAlphaComponent(1), MarkColour.yellow.paint.withAlphaComponent(1))
        XCTAssertEqual(second?.withAlphaComponent(1), MarkColour.pink.paint.withAlphaComponent(1))
    }

    func testOnDarkPaperHighlightsAreLighter() {
        let light = NSTextView(), dark = NSTextView()
        for (tv, paper) in [(light, Theme.fixedPaper.window), (dark, Theme.readingNight.window)] {
            tv.string = "Call me Ishmael."
            tv.backgroundColor = paper
            Highlights.apply([Paint(quote: "Ishmael", colour: .blue)], to: tv)
        }
        let a = (light.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 9, effectiveRange: nil) as? NSColor)?.alphaComponent ?? 0
        let b = (dark.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 9, effectiveRange: nil) as? NSColor)?.alphaComponent ?? 1
        XCTAssertGreaterThan(a, b)
    }

    func testPdfHighlightsTakeTheMarksColour() throws {
        let doc = try XCTUnwrap(PDFDocument(data: Data(Fixtures.tinyPdf.utf8)))
        let mark = Mark(path: "/t.pdf", kind: "pdf", quote: "PDF World", target: 0, place: "Page 1", colour: .green)
        XCTAssertEqual(PdfKitView.selections(for: [mark], in: doc).first?.color, MarkColour.green.paint)
    }

    func testFourDistinctColours() {
        XCTAssertEqual(Set(MarkColour.allCases.map { $0.paint.description }).count, 4)
    }
}
