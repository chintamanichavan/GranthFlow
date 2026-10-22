import XCTest
import CoreImage
import SwiftUI
@testable import Anyfile

@MainActor
final class PageTurnTests: XCTestCase {
    /// A page of reading text, as the reading view draws it.
    private func page(_ title: String, _ number: Int) -> CIImage {
        let view = ReadingText(text: title + "\n\n" + String(repeating: "It was a bright cold day in April, and the clocks were striking thirteen. ", count: 12),
                               number: number, title: title)
        let host = NSHostingView(rootView: view.frame(width: 700, height: 460))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 460)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return CIImage(cgImage: rep.cgImage!)
    }

    private func save(_ image: CIImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"] else { return }
        let rep = NSBitmapImageRep(ciImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    private func pixel(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> NSColor {
        NSBitmapImageRep(ciImage: image).colorAt(x: Int(x), y: Int(image.extent.height - y))!.usingColorSpace(.sRGB)!
    }

    func testTheTurnStartsOnTheOldPageAndEndsOnTheNew() {
        let a = page("Loomings", 1), b = page("The Carpet-Bag", 2)
        for forward in [true, false] {
            let first = PageCurl.frame(from: a, to: b, progress: 0, forward: forward)
            let last = PageCurl.frame(from: a, to: b, progress: 1, forward: forward)
            XCTAssertEqual(first.extent, a.extent)
            // Compare a strip through the title, where the two pages differ most.
            let y = a.extent.height * 0.22
            XCTAssertEqual(pixel(first, a.extent.midX, y), pixel(a, a.extent.midX, y), "forward \(forward): first frame is the old page")
            XCTAssertEqual(pixel(last, b.extent.midX, y), pixel(b, b.extent.midX, y), "forward \(forward): last frame is the new page")
        }
    }

    func testEasingIsSlowAtBothEnds() {
        XCTAssertEqual(PageCurl.eased(0), 0)
        XCTAssertEqual(PageCurl.eased(1), 1)
        XCTAssertEqual(PageCurl.eased(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(PageCurl.eased(0.1), 0.1)
        XCTAssertGreaterThan(PageCurl.eased(0.9), 0.9)
    }

    /// A turn draws about 33 frames in 0.55 s; each must fit well inside a 60 Hz frame. Prints the time.
    func testFrameSpeedAtWindowSize() {
        let size = CGRect(x: 0, y: 0, width: 2200, height: 1500)                // a large window on a Retina screen
        let a = CIImage(color: .white).cropped(to: size), b = CIImage(color: CIColor(red: 0.97, green: 0.94, blue: 0.88)).cropped(to: size)
        let context = CIContext(options: [.cacheIntermediates: false])
        _ = context.createCGImage(PageCurl.frame(from: a, to: b, progress: 0.5, forward: true), from: size)   // warm up
        let start = Date()
        for i in 0..<20 {
            let f = PageCurl.frame(from: a, to: b, progress: Double(i) / 20, forward: true)
            _ = context.createCGImage(f, from: f.extent)
        }
        let perFrame = Date().timeIntervalSince(start) / 20
        print(String(format: "page curl frame at 2200x1500: %.1f ms", perFrame * 1000))
        XCTAssertLessThan(perFrame, 1.0 / 60)
    }

    func testFramesForAPerson() {
        let a = page("Loomings", 1), b = page("The Carpet-Bag", 2)
        for p in [0.3, 0.6] {
            save(PageCurl.frame(from: a, to: b, progress: p, forward: true), "curl-forward-\(Int(p * 10))")
            save(PageCurl.frame(from: a, to: b, progress: p, forward: false), "curl-back-\(Int(p * 10))")
        }
        save(PageCurl.frame(from: a, to: b, progress: 0.5, forward: true, reduceMotion: true), "curl-reduced")
    }

    func testNeighbouringChapters() {
        XCTAssertEqual(EpubPane.neighbour(of: 2, step: 1, in: [3, 1, 2]), 3)
        XCTAssertEqual(EpubPane.neighbour(of: 2, step: -1, in: [3, 1, 2]), 1)
        XCTAssertNil(EpubPane.neighbour(of: 3, step: 1, in: [1, 2, 3]))         // no page after the last
        XCTAssertNil(EpubPane.neighbour(of: 1, step: -1, in: [1, 2, 3]))
        XCTAssertNil(EpubPane.neighbour(of: nil, step: 1, in: [1, 2]))
        XCTAssertNil(EpubPane.neighbour(of: 9, step: 1, in: [1, 2]))
    }

    func testSpaceTurnsOnlyAtTheEnd() {
        let bounds = NSRect(x: 0, y: 0, width: 600, height: 3000)
        XCTAssertFalse(PaperTextView.atEnd(NSRect(x: 0, y: 0, width: 600, height: 700), bounds))
        XCTAssertTrue(PaperTextView.atEnd(NSRect(x: 0, y: 2300, width: 600, height: 700), bounds))
        XCTAssertTrue(PaperTextView.atEnd(NSRect(x: 0, y: 0, width: 600, height: 700), NSRect(x: 0, y: 0, width: 600, height: 500)))  // short chapter
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

    /// The turn plays over the page and then gets out of the way.
    func testATurnPlaysThenClears() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.documentView = NSTextView(frame: scroll.bounds)
        let turner = PageTurnView(scroll: scroll)
        turner.frame = NSRect(x: 0, y: 0, width: 400, height: 300)              // the scroll view follows by autoresizing
        XCTAssertEqual(scroll.frame.size, turner.frame.size)
        let window = NSWindow(contentRect: turner.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = turner
        let old = try XCTUnwrap(turner.snapshot())
        turner.turn(from: old, forward: true)
        XCTAssertTrue(turner.isTurning)
        try await Task.sleep(for: .seconds(PageCurl.duration + 0.4))
        XCTAssertFalse(turner.isTurning)
    }
}
