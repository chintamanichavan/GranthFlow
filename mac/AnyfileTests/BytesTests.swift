import XCTest
import SwiftUI
@testable import Anyfile

final class BytesTests: XCTestCase {
    func testSignaturesInPlainWords() throws {
        XCTAssertEqual(Signature.describe(Data([0x7F, 0x45, 0x4C, 0x46, 2])), "this is a Linux program")
        XCTAssertEqual(Signature.describe(Data([0xCF, 0xFA, 0xED, 0xFE])), "this is a Mac program")
        XCTAssertEqual(Signature.describe(Data([0x4D, 0x5A, 0x90, 0])), "this is a Windows program")
        XCTAssertEqual(Signature.describe(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), "this is a PNG image")
        XCTAssertEqual(Signature.describe(Data("SQLite format 3\0".utf8)), "this is an SQLite database")
        XCTAssertEqual(Signature.describe(Data([0, 0, 0, 0x20] + Array("ftypisom".utf8))), "this is a video or audio file (MP4 family)")
        XCTAssertNil(Signature.describe(Data([1, 2, 3, 4])))
        XCTAssertNil(Signature.describe(Data()))
        XCTAssertNil(Signature.describe(Data([0x7F, 0x45])))                     // too short to be sure
        let zsh = try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh"))
        XCTAssertTrue(Signature.describe(zsh)?.hasPrefix("this is a Mac program") == true, Signature.describe(zsh) ?? "nil")
    }

    func testByteClassesAndGlyphs() {
        XCTAssertEqual(ByteClass(0), .zero)
        XCTAssertEqual(ByteClass(0x41), .text)
        XCTAssertEqual(ByteClass(0xFF), .high)
        XCTAssertEqual(ByteClass(0x0A), .other)
        XCTAssertEqual(HexLayout.glyph(0x41), "A")
        XCTAssertEqual(HexLayout.glyph(0x0A), "·")
    }

    func testRowsCoverTheFileWithoutRunningPastIt() {
        XCTAssertEqual(HexLayout.rows(from: 0, count: 3, total: 40), [0, 16, 32])
        XCTAssertEqual(HexLayout.rows(from: 17, count: 2, total: 100), [16, 32])
        XCTAssertEqual(HexLayout.rows(from: 500, count: 2, total: 40), [32])          // past the end: the last row
        XCTAssertEqual(HexLayout.rows(from: 0, count: 2, total: 0), [])
    }

    func testRowTextKeepsColumnsAligned() {
        let full = String(HexRow(data: Data(0..<16), offset: 0, highlight: nil).line.characters)
        let short = String(HexRow(data: Data([0x41, 0x42, 0x43]), offset: 0, highlight: nil).line.characters)
        XCTAssertTrue(full.hasPrefix("00000000   00 01 02 03 04 05 06 07  08 09"))
        XCTAssertEqual(full.count, short.count + 13)                    // hex padded to full width; the text column holds 3 glyphs, not 16
        XCTAssertTrue(short.hasSuffix("  ABC"))
        XCTAssertEqual(short.firstIndex(of: "A").map { short.distance(from: short.startIndex, to: $0) },
                       full.firstIndex(of: "·").map { full.distance(from: full.startIndex, to: $0) })   // text column lines up
    }

    func testFoundBytesAreHighlighted() {
        let row = HexRow(data: Data([0, 0x7f, 0x45, 0]), offset: 0, highlight: 1..<3).line
        let painted = row.runs.filter { $0.backgroundColor != nil }.map { String(row[$0.range].characters) }
        XCTAssertEqual(painted.joined(), "7f 45 ")
    }

    /// The view builds 256 coloured rows whenever it moves. Prints the time.
    func testPageOfRowsSpeed() throws {
        let zsh = try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh"))
        let start = Date()
        for row in HexLayout.rows(from: 0, count: 256, total: zsh.count) { _ = HexRow(data: zsh, offset: row, highlight: nil).line }
        let seconds = Date().timeIntervalSince(start)
        print(String(format: "256 hex rows: %.4f s", seconds))
        XCTAssertLessThan(seconds, 0.1)
    }
}

@MainActor
final class HexRenderTests: XCTestCase {
    func testHexWindowDrawsOnTheNightGround() async throws {
        let zsh = try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh"))
        let doc = AnyfileDocument(data: zsh, name: "zsh")
        let host = NSHostingView(rootView: HexPane(document: doc).frame(width: 900, height: 520))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<20 { try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded() }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let corner = try XCTUnwrap(rep.colorAt(x: 3, y: rep.pixelsHigh - 3)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(corner.brightnessComponent, 0.25)                      // night, in light mode too
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("hex.png"))
        }
    }
}
