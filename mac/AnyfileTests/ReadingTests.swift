import XCTest
import SwiftUI
@testable import Anyfile

final class ReadingTests: XCTestCase {
    func testHexColours() {
        let c = NSColor(hex: "#F7F0E1")!.usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent * 255, 0xF7, accuracy: 0.5)
        XCTAssertEqual(c.greenComponent * 255, 0xF0, accuracy: 0.5)
        XCTAssertEqual(c.blueComponent * 255, 0xE1, accuracy: 0.5)
        XCTAssertNotNil(NSColor(hex: "0e1330"))
        XCTAssertNil(NSColor(hex: "#F7F0E"))
        XCTAssertNil(NSColor(hex: "#GGGGGG"))
        XCTAssertNil(NSColor(hex: "+FFFFF"))        // UInt32(radix:) alone would accept this
    }

    func testPaperHasALightAndADarkFace() {
        func resolved(_ c: NSColor, _ name: NSAppearance.Name) -> NSColor {
            var out = c
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance { out = c.usingColorSpace(.sRGB)! }
            return out
        }
        let light = resolved(Theme.paper.window, .aqua), dark = resolved(Theme.paper.window, .darkAqua)
        XCTAssertGreaterThan(light.brightnessComponent, 0.9)
        XCTAssertLessThan(dark.brightnessComponent, 0.2)
        XCTAssertLessThan(resolved(Theme.paper.label, .aqua).brightnessComponent, 0.3)   // dark ink on light paper
        XCTAssertGreaterThan(resolved(Theme.paper.label, .darkAqua).brightnessComponent, 0.8)
    }

    func testReadingFontIsTheSystemSerif() {
        let f = Theme.readingFont(size: 17)
        XCTAssertEqual(f.pointSize, 17)
        // New York, which the system names ".AppleSystemUIFontSerif" when reached through the serif design.
        let family = f.familyName ?? ""
        XCTAssertTrue(family.contains("New York") || family == ".AppleSystemUIFontSerif", family)
    }

    func testChapterSetsLabelTitleThenBody() {
        let s = ReadingStyle.chapter("Loomings\n\nCall me Ishmael.", number: 1, title: "Loomings")
        XCTAssertEqual(s.string, "CHAPTER 1\nLoomings\nCall me Ishmael.")      // the heading is not repeated
        let label = s.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((label[.paragraphStyle] as? NSParagraphStyle)?.alignment, .center)
        let title = s.attributes(at: 10, effectiveRange: nil)
        XCTAssertEqual((title[.font] as? NSFont)?.pointSize, 30)
        let body = s.attributes(at: s.length - 3, effectiveRange: nil)
        XCTAssertEqual((body[.font] as? NSFont)?.pointSize, ReadingStyle.bodySize)
        XCTAssertEqual((body[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple, 1.45)
    }

    func testChapterWithoutNumberOrTitleIsJustBody() {
        XCTAssertEqual(ReadingStyle.chapter("text", number: nil, title: nil).string, "text")
        XCTAssertEqual(ReadingStyle.chapter("text", number: 2, title: "").string, "CHAPTER 2\ntext")
    }

    func testDropLeadingTitle() {
        XCTAssertEqual(ReadingStyle.dropLeadingTitle("\n  LOOMINGS \n\nbody", title: "Loomings"), "body")
        XCTAssertEqual(ReadingStyle.dropLeadingTitle("First\n\nbody", title: "Opening"), "First\n\nbody")
        XCTAssertEqual(ReadingStyle.dropLeadingTitle("Loomings", title: "Loomings"), "")
        XCTAssertEqual(ReadingStyle.dropLeadingTitle("body", title: ""), "body")
    }

    func testColumnStaysWithinTheMeasure() {
        XCTAssertEqual(ReadingStyle.sideInset(forWidth: 400), 32)
        XCTAssertEqual(ReadingStyle.sideInset(forWidth: 1040), 240)
        XCTAssertEqual(1040 - 2 * ReadingStyle.sideInset(forWidth: 1040), ReadingStyle.measure)
    }

    func testMarkdownPreviewUsesReadingType() {
        let r = MarkdownRenderer.render("# Title\n\nSome **bold** words.\n")
        let fonts = r.runs.compactMap(\.font)
        XCTAssertTrue(fonts.contains(MarkdownRenderer.body))
        XCTAssertTrue(r.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })   // bold survives
    }
}

/// Draws the AppKit reading view into a bitmap; ImageRenderer cannot draw AppKit views.
@MainActor
final class ReadingRenderTests: XCTestCase {
    func testReadingViewDrawsOnPaper() throws {
        let view = ReadingText(text: "Loomings\n\n" + String(repeating: "Call me Ishmael. Some years ago, never mind how long precisely, having little or no money in my purse. ", count: 6),
                               number: 1, title: "Loomings")
        let host = NSHostingView(rootView: view.frame(width: 900, height: 560))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("reading.png"))
        }
        // The corner is bare paper.
        let corner = try XCTUnwrap(rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
        let paper = NSColor(hex: "#F7F0E1")!
        if NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua {
            XCTAssertEqual(corner.redComponent, paper.redComponent, accuracy: 0.02)
            XCTAssertEqual(corner.blueComponent, paper.blueComponent, accuracy: 0.02)
        }
    }
}
