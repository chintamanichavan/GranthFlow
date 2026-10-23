import XCTest
@testable import Anyfile

final class MarkExportTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_792_000_000)        // a fixed date, so the text is exact

    private func mark(_ quote: String, _ target: Int, _ place: String, note: String = "", colour: MarkColour = .yellow, at t: Double = 0) -> Mark {
        Mark(path: "/moby.epub", kind: "epub", quote: quote, target: target, place: place, created: Date(timeIntervalSince1970: t),
             note: note, colour: colour)
    }

    func testABooksMarksInReadingOrderUnderTheirChapters() {
        let marks = [
            mark("It is a way I have of driving off the spleen.", 1, "Loomings", at: 2),
            mark("Call me Ishmael.", 1, "Loomings", note: "He names himself at once.", at: 1),
            mark("A tall, broad-shouldered man.", 3, "The Spouter-Inn", at: 3),
        ]
        let date = day.formatted(date: .long, time: .omitted)
        XCTAssertEqual(MarkExport.markdown(title: "Moby-Dick", author: "Herman Melville", marks: marks, on: day), """
            # Moby-Dick

            *Herman Melville*

            Exported from GranthFlow on \(date) · 3 marks

            ## Loomings

            > Call me Ishmael.

            He names himself at once.

            > It is a way I have of driving off the spleen.

            ## The Spouter-Inn

            > A tall, broad-shouldered man.

            """)
    }

    func testColoursAreNamedOnlyWhenMoreThanOneIsUsed() {
        let one = MarkExport.markdown(title: "T", marks: [mark("a", 1, "P"), mark("b", 1, "P")], on: day)
        XCTAssertFalse(one.contains("*Yellow*"))
        let two = MarkExport.markdown(title: "T", marks: [mark("a", 1, "P"), mark("b", 1, "P", colour: .pink, at: 1)], on: day)
        XCTAssertTrue(two.contains("*Yellow*") && two.contains("*Pink*"))
        XCTAssertTrue(MarkExport.markdown(title: "T", marks: [mark("a", 1, "P")], on: day).contains("· 1 mark\n"))
    }

    func testAPassageOfSeveralLinesStaysOneQuote() {
        XCTAssertEqual(MarkExport.quoted("first line\n\nthird line"), "> first line\n>\n> third line")
    }

    func testHeadingsAndFileNames() {
        XCTAssertEqual(MarkExport.heading(for: Fixtures.epub, name: "b.epub", kind: "epub").title, "Tiny Book")
        XCTAssertEqual(MarkExport.heading(for: Fixtures.epub, name: "b.epub", kind: "epub").author, "Tester")
        XCTAssertEqual(MarkExport.heading(for: Data(), name: "notes.md", kind: "markdown").title, "notes")
        XCTAssertEqual(MarkExport.suggestedName(for: "Either/Or: a life"), "Either-Or- a life — marks.md")
    }
}
