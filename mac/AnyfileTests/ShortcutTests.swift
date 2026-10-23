import XCTest
@testable import Anyfile

@MainActor
final class ShortcutTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-shortcuts-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testTheCurrentBookIsTheOnePartWayThrough() throws {
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        XCTAssertNil(ShortcutWork.currentBook(in: lib))
        let a = dir.appendingPathComponent("a.epub"), b = dir.appendingPathComponent("b.epub")
        for url in [a, b] { try Data("x".utf8).write(to: url) }
        lib.recordOpened(a, kind: "epub", at: Date(timeIntervalSince1970: 1))
        lib.recordOpened(b, kind: "epub", at: Date(timeIntervalSince1970: 2))
        lib.recordPosition(a, position: 3, total: 9)
        XCTAssertEqual(ShortcutWork.currentBook(in: lib)?.name, "a.epub")                       // b was opened later but not read
    }

    func testMarksAsMarkdownGroupedAndFiltered() throws {
        let store = MarkStore(file: dir.appendingPathComponent("m.json"))
        store.add(Selection(quote: "Call me Ishmael.", target: 1, place: "Loomings"), in: URL(fileURLWithPath: "/b/moby.epub"), kind: "epub",
                  at: Date(timeIntervalSince1970: 1))
        store.add(Selection(quote: "Happy families", target: 1, place: "Part One"), in: URL(fileURLWithPath: "/b/anna.epub"), kind: "epub",
                  at: Date(timeIntervalSince1970: 2))
        let titles = ["/b/moby.epub": ("Moby-Dick", "Herman Melville"), "/b/anna.epub": ("Anna Karenina", "Leo Tolstoy")]
        let title: (String) -> (title: String, author: String) = { titles[$0] ?? ("?", "") }
        let all = ShortcutWork.marksText(store, title: title)
        XCTAssertTrue(all.hasPrefix("# Anna Karenina"))                                         // the newest file first
        XCTAssertTrue(all.contains("# Moby-Dick") && all.contains("> Call me Ishmael."))
        XCTAssertTrue(all.contains("\n---\n"))
        let one = ShortcutWork.marksText(store, matching: "moby", title: title)
        XCTAssertTrue(one.contains("Call me Ishmael.") && !one.contains("Happy families"))
        XCTAssertTrue(ShortcutWork.marksText(store, matching: "anna.epub", title: title).contains("Happy families"))   // the file name works too
        XCTAssertEqual(ShortcutWork.marksText(store, matching: "nothing like it", title: title), "")
    }

    func testABooksHeadingComesFromTheFile() throws {
        let url = dir.appendingPathComponent("tiny.epub")
        try Fixtures.epub.write(to: url)
        XCTAssertEqual(ShortcutWork.heading(of: url.path).title, "Tiny Book")
        XCTAssertEqual(ShortcutWork.heading(of: "/x/notes.md").title, "notes")
    }

    /// Shortcuts finds the actions through metadata Xcode extracts at build time.
    func testTheAppCarriesItsShortcutActions() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = Set((json["actions"] as? [String: Any])?.keys.map { $0 } ?? [])
        XCTAssertEqual(actions, ["OpenCurrentBook", "GetMarks", "AddToLibrary"])
    }
}
