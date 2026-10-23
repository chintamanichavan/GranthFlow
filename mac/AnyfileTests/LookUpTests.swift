import XCTest
@testable import Anyfile

/// AppKit's text views here leave Look Up out of their right-click menu; the app adds it.
@MainActor
final class LookUpTests: XCTestCase {
    private func textView(_ text: String) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = text
        return tv
    }

    func testTheSelectionOrElseTheClickedWord() {
        let tv = textView("Call me Ishmael. Some years ago.")
        XCTAssertEqual(LookUp.range(in: tv, at: 9), NSRange(location: 8, length: 7))          // the word clicked
        tv.setSelectedRange(NSRange(location: 17, length: 10))
        XCTAssertEqual(LookUp.range(in: tv, at: 9), NSRange(location: 17, length: 10))         // the selection wins
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertNil(LookUp.range(in: tv, at: 4))                                                // a space: nothing to look up
        XCTAssertNil(LookUp.range(in: tv, at: 999))
    }

    func testTheMenuGetsLookUpFirst() throws {
        let tv = textView("Call me Ishmael.")
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: nil, keyEquivalent: "")
        _ = LookUp.addItem(to: menu, in: tv, at: 9)
        XCTAssertEqual(menu.items.first?.title, "Look Up “Ishmael”")
        XCTAssertEqual(menu.items.first?.action, #selector(NSTextView.lookUp(_:)))
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        let long = textView(String(repeating: "word ", count: 20))
        long.setSelectedRange(NSRange(location: 0, length: 60))
        let menu2 = LookUp.addItem(to: NSMenu(), in: long, at: 0)
        XCTAssertTrue(menu2.items.first?.title.hasSuffix("…”") == true)                         // a long passage is shortened
    }

    func testEveryTextViewDelegateAddsIt() throws {
        let tv = textView("Call me Ishmael.")
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let delegates: [NSTextViewDelegate] = [TextPane.Coordinator(text: .constant("")), ReadingText.Coordinator(), MarkdownPreview.Coordinator()]
        for delegate in delegates {
            let menu = delegate.textView?(tv, menu: NSMenu(), for: event, at: 9)
            XCTAssertEqual(menu?.items.first?.title, "Look Up “Ishmael”", "\(type(of: delegate))")
        }
    }
}
