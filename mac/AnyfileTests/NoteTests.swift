import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class NoteTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-notes-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testANoteIsKeptTrimmedAndCanBeCleared() throws {
        let store = dir.appendingPathComponent("m.json")
        let marks = MarkStore(file: store)
        let mark = try XCTUnwrap(marks.add(Selection(quote: "Call me Ishmael.", target: 1, place: "Loomings"),
                                           in: dir.appendingPathComponent("b.epub"), kind: "epub"))
        marks.setNote("  The narrator names himself at once.\n", for: mark)
        XCTAssertEqual(MarkStore(file: store).marks.first?.note, "The narrator names himself at once.")
        marks.setNote("   ", for: marks.marks[0])
        XCTAssertEqual(MarkStore(file: store).marks.first?.note, "")
        marks.setNote("lost", for: Mark(path: "/gone", kind: "text", quote: "x", target: 1, place: "Line 1"))   // not a kept mark
        XCTAssertEqual(marks.marks.count, 1)
    }

    func testMarksSavedBeforeNotesStillLoad() throws {
        let store = dir.appendingPathComponent("old.json")
        let old = #"[{"created":"2026-10-21T00:00:00Z","id":"6F1D1D3E-6E2B-4C5B-9A61-1A2B3C4D5E6F","kind":"epub","#
            + #""path":"/b.epub","place":"Loomings","quote":"Call me Ishmael.","target":1}]"#
        try Data(old.utf8).write(to: store)
        let mark = try XCTUnwrap(MarkStore(file: store).marks.first)
        XCTAssertEqual(mark.quote, "Call me Ishmael.")
        XCTAssertEqual(mark.note, "")
    }

    func testARowWithANoteDraws() throws {
        let mark = Mark(path: "/b.epub", kind: "epub", quote: "Call me Ishmael.", target: 1, place: "Loomings",
                        note: "The narrator names himself at once, and never his full name.")
        let row = MarkRow(mark: mark, caption: "moby.epub  ·  Loomings", choose: {}, remove: {})
        let renderer = ImageRenderer(content: row.frame(width: 520).padding(12).background(Color.white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.height, 70)                                    // quote, caption and note
        if let out = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("mark-note.png"))
        }
    }
}
