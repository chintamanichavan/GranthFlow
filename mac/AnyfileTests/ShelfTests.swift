import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class ShelfTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-shelf-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ data: Data, _ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    func testBookFaceUsesTheBooksOwnTitle() {
        let url = write(Fixtures.epub, "tiny.epub")
        let face = Shelf.face(for: LibraryEntry(path: url.path, kind: "epub", opened: Date(), position: 1, total: 2))
        XCTAssertEqual(face?.title, "Tiny Book")
        XCTAssertEqual(face?.author, "Tester")
        XCTAssertEqual(face?.subtitle, "Book · Chapter 1 of 2")
        XCTAssertNotNil(face?.cloth)
    }

    func testOtherFacesUseNameKindAndSize() {
        let url = write(Data([0x7f, 0x45, 0x4c, 0x46, 0, 0, 0, 0]), "firmware")
        let face = Shelf.face(for: LibraryEntry(path: url.path, kind: "binary", opened: Date()))
        XCTAssertEqual(face?.title, "firmware")
        XCTAssertEqual(face?.subtitle, "Program · 8 bytes")
        XCTAssertNil(face?.cloth)
        XCTAssertNil(Shelf.face(for: LibraryEntry(path: dir.appendingPathComponent("missing").path, kind: "text", opened: Date())))
    }

    func testSectionsFilterByKind() {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let kinds = ["a.epub": "epub", "b.pdf": "pdf", "c.md": "markdown", "d.txt": "text", "e.bin": "binary"]
        for (i, (name, kind)) in kinds.sorted(by: { $0.key < $1.key }).enumerated() {
            lib.recordOpened(write(Data("x".utf8), name), kind: kind, at: Date(timeIntervalSince1970: Double(i)))
        }
        lib.recordPosition(dir.appendingPathComponent("a.epub"), position: 1, total: 3)
        XCTAssertEqual(LibrarySection.library.entries(in: lib).count, 5)
        XCTAssertEqual(LibrarySection.continueReading.entries(in: lib).map(\.name), ["a.epub"])
        XCTAssertEqual(LibrarySection.books.entries(in: lib).map(\.name), ["a.epub"])
        XCTAssertEqual(LibrarySection.documents.entries(in: lib).map(\.name), ["b.pdf"])
        XCTAssertEqual(LibrarySection.notes.entries(in: lib).map(\.name), ["d.txt", "c.md"])
        XCTAssertEqual(LibrarySection.other.entries(in: lib).map(\.name), ["e.bin"])
        let all = Set(LibrarySection.allCases.filter { $0 != .library && $0 != .continueReading }.flatMap { $0.entries(in: lib).map(\.name) })
        XCTAssertEqual(all.count, 5)                                    // every kind lands on exactly one shelf
    }

    /// Draws the whole library window with real files, for a person to look at.
    func testLibraryWindowDraws() async throws {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        let book = write(Fixtures.epub, "Tiny Book.epub")
        lib.recordOpened(book, kind: "epub", at: Date(timeIntervalSince1970: 10))
        lib.recordPosition(book, position: 1, total: 2)
        lib.recordOpened(write(Data(Fixtures.tinyPdf.utf8), "Report.pdf"), kind: "pdf", at: Date(timeIntervalSince1970: 9))
        lib.recordOpened(write(Data("# Project notes\n\nReader and editor both work.\n\n## Status\n- Books open\n".utf8), "notes.md"), kind: "markdown", at: Date(timeIntervalSince1970: 8))
        lib.recordOpened(write(Data("# server settings\nhost=localhost\nport=8080\n".utf8), "server.conf"), kind: "text", at: Date(timeIntervalSince1970: 7))
        lib.recordOpened(write(try Data(contentsOf: URL(fileURLWithPath: "/bin/zsh")), "zsh"), kind: "binary", at: Date(timeIntervalSince1970: 6))

        let host = NSHostingView(rootView: LibraryView(library: lib).frame(width: 1100, height: 760))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<40 {                                              // faces load off the main thread
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        XCTAssertEqual(rep.pixelsWide, Int(1100 * (window.backingScaleFactor)))
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("library.png"))
        }
    }
}
