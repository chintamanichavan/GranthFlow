import XCTest
import SwiftUI
import simd
@testable import Anyfile

@MainActor
final class PageRendererTests: XCTestCase {
    /// A page of reading text as the reading view draws it, at 2x.
    private func page(_ title: String, _ number: Int, width: CGFloat = 700, height: CGFloat = 460) -> CGImage {
        let view = ReadingText(text: title + "\n\n" + String(repeating: "It was a bright cold day in April, and the clocks were striking thirteen. ", count: 14),
                               number: number, title: title)
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.cgImage!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        let rep = NSBitmapImageRep(cgImage: image)
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    private func save(_ image: CGImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"] else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func testSwiftAndMetalAgreeOnLayout() {
        XCTAssertEqual(MemoryLayout<PageVertex>.stride, 48)          // float3, float3, float2 in Metal
        XCTAssertEqual(MemoryLayout<PageUniforms>.stride, 112)
    }

    func testAPageLyingFlatDrawsExactlyAsPrinted() throws {
        let renderer = try XCTUnwrap(PageRenderer())
        let old = page("Loomings", 1), new = page("The Carpet-Bag", 2)
        renderer.setPages(turning: old, beneath: new)
        let start = try XCTUnwrap(renderer.image(progress: 0, width: old.width, height: old.height))
        let end = try XCTUnwrap(renderer.image(progress: 1, width: old.width, height: old.height))
        for (x, y) in [(old.width / 2, old.height / 5), (old.width / 3, old.height / 2), (old.width - 20, old.height - 20)] {
            for (a, b) in zip(pixel(start, x, y), pixel(old, x, y)) { XCTAssertEqual(a, b, accuracy: 3, "start at \(x),\(y)") }
            for (a, b) in zip(pixel(end, x, y), pixel(new, x, y)) { XCTAssertEqual(a, b, accuracy: 3, "end at \(x),\(y)") }
        }
    }

    /// A turn ends at visibleEnd; by then the page must be wholly past the spine, out of view.
    func testATurnEndsWithTheNextPageInFullView() throws {
        let renderer = try XCTUnwrap(PageRenderer())
        let old = page("Loomings", 1), new = page("The Carpet-Bag", 2)
        renderer.setPages(turning: old, beneath: new)
        let end = try XCTUnwrap(renderer.image(progress: PageCurl.visibleEnd, width: old.width, height: old.height))
        for (x, y) in [(4, 4), (4, old.height - 4), (old.width / 6, old.height / 2), (old.width / 2, old.height / 5)] {
            for (a, b) in zip(pixel(end, x, y), pixel(new, x, y)) { XCTAssertEqual(a, b, accuracy: 4, "at \(x),\(y)") }
        }
    }

    /// About 33 frames make a turn; each must fit well inside a 60 Hz frame. Prints the time.
    func testFrameSpeedAtWindowSize() throws {
        let renderer = try XCTUnwrap(PageRenderer())
        let old = page("Loomings", 1, width: 1100, height: 750), new = page("The Carpet-Bag", 2, width: 1100, height: 750)
        renderer.setPages(turning: old, beneath: new)
        _ = renderer.image(progress: 0.5, width: old.width, height: old.height)          // warm up
        let start = Date()
        for k in 0..<20 { _ = renderer.image(progress: Float(k) / 20, width: old.width, height: old.height) }
        let perFrame = Date().timeIntervalSince(start) / 20
        print(String(format: "physical page turn frame at %dx%d (with read-back): %.1f ms", old.width, old.height, perFrame * 1000))
        XCTAssertLessThan(perFrame, 1.0 / 60)
    }

    func testFramesForAPerson() throws {
        let renderer = try XCTUnwrap(PageRenderer())
        let old = page("Loomings", 1), new = page("The Carpet-Bag", 2)
        renderer.setPages(turning: old, beneath: new)
        for p: Float in [0.15, 0.3, 0.45, 0.6, 0.75] {
            if let img = renderer.image(progress: p, width: old.width, height: old.height) { save(img, "turn-\(Int(p * 100))") }
        }
    }
}
