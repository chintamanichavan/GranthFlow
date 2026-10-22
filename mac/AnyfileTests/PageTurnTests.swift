import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class PageTurnTests: XCTestCase {
    func testEasingIsSlowAtBothEnds() {
        XCTAssertEqual(PageCurl.eased(0), 0)
        XCTAssertEqual(PageCurl.eased(1), 1)
        XCTAssertEqual(PageCurl.eased(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(PageCurl.eased(0.1), 0.1)
        XCTAssertGreaterThan(PageCurl.eased(0.9), 0.9)
        XCTAssertGreaterThan(PageCurl.easedOut(0.3), 0.3)              // a released page falls fast, then settles
        XCTAssertEqual(PageCurl.easedOut(1), 1)
    }

    func testProgressRunsTheTurnBothWays() {
        XCTAssertEqual(PageCurl.progress(fraction: 0, forward: true), 0)
        XCTAssertEqual(PageCurl.progress(fraction: 1, forward: true), PageCurl.visibleEnd)
        // Back: the previous page starts over the spine and ends lying flat.
        XCTAssertEqual(PageCurl.progress(fraction: 0, forward: false), PageCurl.visibleEnd)
        XCTAssertEqual(PageCurl.progress(fraction: 1, forward: false), 0)
        XCTAssertEqual(PageCurl.progress(fraction: 2, forward: true), PageCurl.visibleEnd)    // clamped
    }

    func testFingersLeftTurnToTheNextPage() {
        var s = SwipeTurn(width: 1000)
        s.move(by: -4)
        XCTAssertNil(s.step)                                            // a wobble decides nothing
        s.move(by: -6)
        XCTAssertEqual(s.step, 1)
        s.move(by: -265)                                                 // 275 of a 550-point span
        XCTAssertEqual(s.fraction, 0.5, accuracy: 1e-9)
        XCTAssertTrue(s.commits)
    }

    func testFingersRightTurnBackAndASmallSwipeSettles() {
        var s = SwipeTurn(width: 1000)
        s.move(by: 20)
        XCTAssertEqual(s.step, -1)
        XCTAssertEqual(s.fraction, 20 / 550, accuracy: 1e-9)
        s.move(by: 1)
        XCTAssertFalse(s.commits)                                       // not far, not flicked: the page settles back
        s.move(by: -60)
        XCTAssertEqual(s.fraction, 0)                                    // back past the start holds at 0
    }

    func testAFlickTurnsEvenIfShort() {
        var s = SwipeTurn(width: 1000)
        s.move(by: -30)
        s.move(by: -14)
        XCTAssertLessThan(s.fraction, 0.33)
        XCTAssertTrue(s.commits)
    }

    func testFingerDirectionFollowsTheScrollingSetting() {
        XCTAssertEqual(SwipeTurn.fingerDX(scrollingDeltaX: -5, invertedFromDevice: true), -5)    // natural scrolling
        XCTAssertEqual(SwipeTurn.fingerDX(scrollingDeltaX: -5, invertedFromDevice: false), 5)
    }

    func testOnlyClearlySidewaysSwipesTurn() {
        XCTAssertTrue(PageScrollView.isTurn(dx: -10, dy: 2))
        XCTAssertFalse(PageScrollView.isTurn(dx: 3, dy: -10))
        XCTAssertFalse(PageScrollView.isTurn(dx: 10, dy: 8))            // diagonal: keep scrolling
    }

    private func turner(width: CGFloat = 400, height: CGFloat = 300) -> (PageTurnView, NSWindow) {
        let scroll = ReadingText.makePage()
        let turner = PageTurnView(scroll: scroll)
        turner.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: turner.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = turner
        (scroll.documentView as? NSTextView)?.string = "Call me Ishmael."
        return (turner, window)
    }

    /// The turn plays over the page and then gets out of the way.
    func testAPlayedTurnClearsAfterwards() async throws {
        let (t, window) = turner()
        let old = try XCTUnwrap(t.snapshot())
        (t.scroll.documentView as? NSTextView)?.string = "The Carpet-Bag"
        t.turn(from: old, forward: true)
        XCTAssertTrue(t.isBusy)
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        XCTAssertFalse(t.isBusy)
        _ = window
    }

    func testASwipeHoldsThePageAndSettlesBackWithoutTurning() async throws {
        let (t, window) = turner()
        var turned: [Int] = []
        t.preview = { _ in t.snapshot() }
        t.commit = { turned.append($0) }
        t.swipeMoved(by: -12)
        XCTAssertTrue(t.isBusy)                                         // the page is under the fingers
        t.swipeMoved(by: 2)                                              // eased back, not flicked
        t.swipeEnded()
        XCTAssertEqual(turned, [])
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        XCTAssertFalse(t.isBusy)
        _ = window
    }

    func testASwipeFarEnoughTurnsThePage() async throws {
        let (t, window) = turner()
        var turned: [Int] = []
        t.preview = { _ in t.snapshot() }
        t.commit = { turned.append($0) }
        for _ in 0..<10 { t.swipeMoved(by: -20) }                       // 200 of 220 points
        t.swipeEnded()
        XCTAssertEqual(turned, [1])
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        XCTAssertFalse(t.isBusy)
        _ = window
    }

    func testNoTurnWhenThereIsNoPageThatWay() {
        let (t, window) = turner()
        var turned: [Int] = []
        t.preview = { _ in nil }                                         // the last chapter: nothing after it
        t.commit = { turned.append($0) }
        for _ in 0..<10 { t.swipeMoved(by: -20) }
        t.swipeEnded()
        XCTAssertFalse(t.isBusy)
        XCTAssertEqual(turned, [])
        _ = window
    }

    func testANeighbouringChapterIsPicturedAtThePageSize() throws {
        let page = ReadingText.Page(text: "The Carpet-Bag\n\nI stuffed a shirt or two into my old carpet-bag.", number: 2, title: "The Carpet-Bag")
        let image = try XCTUnwrap(ReadingText.picture(page, size: NSSize(width: 500, height: 320)))
        XCTAssertEqual(CGFloat(image.width) / CGFloat(image.height), 500.0 / 320.0, accuracy: 0.01)
        XCTAssertNil(ReadingText.picture(page, size: .zero))
    }

    func testNeighbouringChapters() {
        XCTAssertEqual(EpubPane.neighbour(of: 2, step: 1, in: [3, 1, 2]), 3)
        XCTAssertEqual(EpubPane.neighbour(of: 2, step: -1, in: [3, 1, 2]), 1)
        XCTAssertNil(EpubPane.neighbour(of: 3, step: 1, in: [1, 2, 3]))
        XCTAssertNil(EpubPane.neighbour(of: 1, step: -1, in: [1, 2, 3]))
        XCTAssertNil(EpubPane.neighbour(of: nil, step: 1, in: [1, 2]))
    }

    func testSpaceTurnsOnlyAtTheEnd() {
        let bounds = NSRect(x: 0, y: 0, width: 600, height: 3000)
        XCTAssertFalse(PaperTextView.atEnd(NSRect(x: 0, y: 0, width: 600, height: 700), bounds))
        XCTAssertTrue(PaperTextView.atEnd(NSRect(x: 0, y: 2300, width: 600, height: 700), bounds))
    }

    func testArrowKeysAskForATurn() throws {
        let tv = PaperTextView()
        var asked: [Int] = []
        tv.onTurn = { asked.append($0) }
        for code: UInt16 in [124, 123] {
            let e = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            tv.keyDown(with: e)
        }
        XCTAssertEqual(asked, [1, -1])
    }
}
