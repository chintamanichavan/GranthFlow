import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class MarkdownPreviewTests: XCTestCase {
    func testASelectionInThePreviewIsMarkedOnItsSourceLine() async throws {
        var reports: [Selection?] = []
        let coordinator = MarkdownPreview.Coordinator()
        coordinator.onSelect = { reports.append($0) }
        let tv = NSTextView()
        tv.textStorage?.setAttributedString(MarkdownRenderer.render("# Notes\n\nFirst point.\n- **Second** point\n"))
        let r = (tv.string as NSString).range(of: "Second point")
        tv.setSelectedRange(r)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: tv))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(reports.first??.quote, "Second point")                          // as read, without the **
        XCTAssertEqual(reports.first??.target, 4)                                       // the list item's line in the source
        XCTAssertEqual(reports.first??.place, "Line 4")
    }

    func testInlineStyleAndLinks() {
        let line = MarkdownRenderer.inline("see *this* and `code` at [the site](https://example.com)", body: Theme.readingFont(size: 17))
        let ns = line.string as NSString
        XCTAssertEqual(line.string, "see this and code at the site")
        let italic = line.attribute(.font, at: ns.range(of: "this").location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.italic))
        let code = line.attribute(.font, at: ns.range(of: "code").location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(code.isFixedPitch)
        XCTAssertEqual(line.attribute(.link, at: ns.range(of: "the site").location, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
    }

    func testEmptyPreviewHasNoLines() {
        XCTAssertNil(MarkdownRenderer.sourceLine(at: 0, in: NSAttributedString()))
        XCTAssertNil(MarkdownRenderer.character(forLine: 3, in: MarkdownRenderer.render("one line")))
    }
}

@MainActor
final class MarkdownPreviewRenderTests: XCTestCase {
    func testThePreviewDrawsAsAPage() throws {
        let source = "# Project notes\n\nReader and editor **both** work, *mostly*.\n\n## Status\n\n- Books open\n- Marks can be `exported`\n\n```\nlet x = 1\n```\n"
        let view = MarkdownPreview(source: source, jump: nil, marks: [Paint(quote: "Books open", colour: .green)], onSelect: { _ in })
        let host = NSHostingView(rootView: view.frame(width: 760, height: 460))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 460)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("markdown-preview.png"))
        }
    }
}
