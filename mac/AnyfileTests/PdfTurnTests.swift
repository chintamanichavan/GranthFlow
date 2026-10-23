import XCTest
import PDFKit
@testable import Anyfile

@MainActor
final class PdfTurnTests: XCTestCase {
    func testOnePageAtATime() {
        XCTAssertEqual(Spread.target(from: 0, step: 1, count: 5, twoUp: false), 1)
        XCTAssertEqual(Spread.target(from: 4, step: 1, count: 5, twoUp: false), nil)          // the last page
        XCTAssertEqual(Spread.target(from: 0, step: -1, count: 5, twoUp: false), nil)
    }

    func testSpreadsLikeAPrintedBook() {
        XCTAssertEqual(Spread.start(of: 0, twoUp: true), 0)                                  // the cover alone
        XCTAssertEqual(Spread.start(of: 1, twoUp: true), 1)
        XCTAssertEqual(Spread.start(of: 2, twoUp: true), 1)                                  // pages 1 and 2 together
        XCTAssertEqual(Spread.start(of: 4, twoUp: true), 3)
        XCTAssertEqual(Spread.target(from: 0, step: 1, count: 6, twoUp: true), 1)
        XCTAssertEqual(Spread.target(from: 2, step: 1, count: 6, twoUp: true), 3)
        XCTAssertEqual(Spread.target(from: 4, step: 1, count: 6, twoUp: true), 5)
        XCTAssertEqual(Spread.target(from: 5, step: 1, count: 6, twoUp: true), nil)
        XCTAssertEqual(Spread.target(from: 2, step: -1, count: 6, twoUp: true), 0)
        XCTAssertEqual(Spread.target(from: 4, step: -1, count: 6, twoUp: true), 1)
    }

    func testTwoPagesOnlyWhenTheyFit() {
        let letter = CGSize(width: 612, height: 792)
        XCTAssertFalse(Spread.twoUp(view: CGSize(width: 800, height: 700), page: letter))
        XCTAssertTrue(Spread.twoUp(view: CGSize(width: 1400, height: 860), page: letter))
        XCTAssertFalse(Spread.twoUp(view: CGSize(width: 1400, height: 1200), page: letter))   // tall window: one page fills it
        XCTAssertFalse(Spread.twoUp(view: CGSize(width: 1400, height: 860), page: .zero))
    }

    /// A five-page PDF in a window, wired for turning as the app wires it.
    private func pdf() throws -> (PageTurnView, PagePDFView, NSWindow) {
        let doc = PDFDocument()
        let one = try XCTUnwrap(PDFDocument(data: Data(Fixtures.tinyPdf.utf8))?.page(at: 0))
        for i in 0..<5 { doc.insert(one.copy() as! PDFPage, at: i) }
        let v = PagePDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.document = doc
        let turner = PageTurnView(content: v)
        PdfKitView.wire(turner, v)
        turner.frame = NSRect(x: 0, y: 0, width: 600, height: 420)
        let window = NSWindow(contentRect: turner.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = turner
        return (turner, v, window)
    }

    func testArrowKeysTurnPages() async throws {
        let (turner, v, window) = try pdf()
        v.onTurn?(1)
        XCTAssertEqual(v.pageIndex, 1)
        XCTAssertTrue(turner.isBusy)                                                          // the turn is playing
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        v.onTurn?(-1)
        XCTAssertEqual(v.pageIndex, 0)
        _ = window
    }

    func testASwipeThatSettlesBackReturnsToTheSamePage() async throws {
        let (turner, v, window) = try pdf()
        v.show(page: 2)
        turner.swipeMoved(by: -12)                                                            // pictures page 3 underneath
        XCTAssertEqual(v.pageIndex, 3)
        turner.swipeMoved(by: 1)
        turner.swipeEnded()                                                                    // not far enough
        XCTAssertEqual(v.pageIndex, 2)
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        XCTAssertFalse(turner.isBusy)
        _ = window
    }

    func testASwipeFarEnoughStaysOnTheNewPage() async throws {
        let (turner, v, window) = try pdf()
        for _ in 0..<10 { turner.swipeMoved(by: -30) }
        turner.swipeEnded()
        XCTAssertEqual(v.pageIndex, 1)
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        XCTAssertEqual(v.pageIndex, 1)
        _ = window
    }
}
