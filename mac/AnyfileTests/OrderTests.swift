import XCTest
@testable import Anyfile

@MainActor
final class OrderTests: XCTestCase {
    private func entry(_ name: String, _ kind: String, opened: Double) -> LibraryEntry {
        LibraryEntry(path: "/b/\(name)", kind: kind, opened: Date(timeIntervalSince1970: opened))
    }

    private func face(_ title: String, _ author: String = "") -> ShelfFace {
        ShelfFace(art: .text(rows: []), title: title, subtitle: "", author: author, cloth: nil)
    }

    func testEachOrder() {
        let moby = entry("moby.epub", "epub", opened: 1), anna = entry("anna.epub", "epub", opened: 3)
        let notes = entry("notes.md", "markdown", opened: 2), report = entry("Report 10.pdf", "pdf", opened: 4)
        let report2 = entry("Report 9.pdf", "pdf", opened: 5)
        let all = [moby, anna, notes, report, report2]
        let faces = ["/b/moby.epub": face("Moby-Dick", "Herman Melville"), "/b/anna.epub": face("Anna Karenina", "Leo Tolstoy")]
        XCTAssertEqual(ShelfOrder.lastOpened.sorted(all, faces: faces).map(\.name), ["Report 9.pdf", "Report 10.pdf", "anna.epub", "notes.md", "moby.epub"])
        XCTAssertEqual(ShelfOrder.title.sorted(all, faces: faces).map(\.name),
                       ["anna.epub", "moby.epub", "notes.md", "Report 9.pdf", "Report 10.pdf"])            // 9 before 10, as Finder sorts
        XCTAssertEqual(ShelfOrder.author.sorted(all, faces: faces).prefix(2).map(\.name), ["moby.epub", "anna.epub"])   // Herman before Leo; authorless after
        XCTAssertEqual(ShelfOrder.kind.sorted(all, faces: faces).map { KindLabel.label(kind: $0.kind) }, ["Book", "Book", "Document", "Document", "Note"])
    }

    func testFinishedByReadingOrByTheReader() throws {
        var e = LibraryEntry(path: "/b.epub", kind: "epub", opened: Date(), position: 4, total: 10)
        XCTAssertFalse(e.isFinished)
        XCTAssertTrue(e.isUnfinished)
        e.finished = true
        XCTAssertTrue(e.isFinished)
        XCTAssertEqual(e.progressText, "Finished")
        e = LibraryEntry(path: "/b.epub", kind: "epub", opened: Date(), position: 10, total: 10)
        XCTAssertTrue(e.isFinished)
        e.finished = false                                                     // reached the last chapter, still reading it
        XCTAssertFalse(e.isFinished)
        XCTAssertEqual(e.progressText, "Chapter 10 of 10")
        XCTAssertFalse(LibraryEntry(path: "/n.md", kind: "markdown", opened: Date()).isUnfinished)   // no place, nothing to continue
    }

    func testTheFinishedShelfAndContinueReading() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let a = dir.appendingPathComponent("a.epub"), b = dir.appendingPathComponent("b.epub")
        for url in [a, b] { try Data("x".utf8).write(to: url); lib.recordOpened(url, kind: "epub") }
        lib.recordPosition(a, position: 2, total: 9)
        lib.recordPosition(b, position: 3, total: 9)
        lib.setFinished(b, true)
        XCTAssertEqual(LibrarySection.finished.entries(in: lib).map(\.name), ["b.epub"])
        XCTAssertEqual(LibrarySection.continueReading.entries(in: lib).map(\.name), ["a.epub"])
        XCTAssertEqual(Library(file: dir.appendingPathComponent("l.json")).entry(for: b)?.finished, true)
    }
}
