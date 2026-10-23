import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class ResumeTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-resume-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testThePlaceInAChapterIsKeptAndANewChapterStartsAtTheTop() {
        let store = dir.appendingPathComponent("l.json")
        let book = dir.appendingPathComponent("b.epub")
        try! Data("x".utf8).write(to: book)
        let lib = Library(file: store)
        lib.recordOpened(book, kind: "epub")
        lib.recordPosition(book, position: 4, total: 10)
        lib.recordAnchor(book, anchor: 5120)
        XCTAssertEqual(Library(file: store).entry(for: book)?.anchor, 5120)            // survives a relaunch
        lib.recordPosition(book, position: 4, total: 10)                                // same chapter: kept
        XCTAssertEqual(lib.entry(for: book)?.anchor, 5120)
        lib.recordPosition(book, position: 5, total: 10)                                // turned the page
        XCTAssertNil(lib.entry(for: book)?.anchor)
    }

    func testALibraryWrittenBeforeAnchorsStillLoads() throws {
        let store = dir.appendingPathComponent("old.json")
        try Data(#"[{"kind":"epub","opened":"2026-10-21T00:00:00Z","path":"/x.epub","position":3,"total":9}]"#.utf8).write(to: store)
        let entry = try XCTUnwrap(Library(file: store).entries.first)
        XCTAssertEqual(entry.position, 3)
        XCTAssertNil(entry.anchor)
    }

    /// Scrolling to a character and asking what is at the top give back the same line.
    func testScrollingToACharacterBringsItToTheTop() throws {
        let scroll = ReadingText.makePage()
        scroll.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        let tv = try XCTUnwrap(scroll.documentView as? NSTextView)
        tv.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        let body = (1...400).map { "Sentence number \($0) of a long chapter, set to wrap across the column." }.joined(separator: " ")
        tv.textStorage?.setAttributedString(ReadingStyle.chapter(body, number: 1, title: "Loomings"))
        tv.sizeToFit()
        XCTAssertEqual(ReadingPlace.topCharacter(in: tv), 0)
        let target = (tv.string as NSString).range(of: "Sentence number 200 ").location
        ReadingPlace.scroll(tv, toCharacter: target)
        let top = ReadingPlace.topCharacter(in: tv)
        XCTAssertLessThanOrEqual(top, target)                                            // the start of its line
        XCTAssertLessThan(target - top, 120, "more than a line away")
        ReadingPlace.scroll(tv, toCharacter: 10_000_000)                                 // past the end: no crash
    }
}
