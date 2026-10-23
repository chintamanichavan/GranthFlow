import XCTest
import CoreSpotlight
@testable import Anyfile

/// What Spotlight is given for each mark, and finding the mark again from a result. Nothing here
/// writes to the Spotlight index: only the reader's own store does that, and not under tests.
@MainActor
final class SpotlightTests: XCTestCase {
    func testAMarkIsFoundByItsPassageNoteAndFile() {
        let mark = Mark(path: "/b/moby.epub", kind: "epub", quote: "Call me Ishmael.", target: 1, place: "Loomings",
                        note: "He names himself at once.", colour: .pink)
        let item = SpotlightMarks.item(for: mark)
        XCTAssertEqual(item.uniqueIdentifier, mark.id.uuidString)
        XCTAssertEqual(item.domainIdentifier, SpotlightMarks.domain)
        XCTAssertEqual(item.attributeSet.title, "Call me Ishmael.")
        XCTAssertEqual(item.attributeSet.contentDescription, "He names himself at once.\nmoby.epub · Loomings")
        XCTAssertTrue(item.attributeSet.textContent?.contains("He names himself") == true)
        XCTAssertTrue(item.attributeSet.keywords?.contains("pink") == true)
        XCTAssertTrue(item.attributeSet.keywords?.contains("note") == true)
    }

    func testAPlainMarkAndALongPassage() {
        let plain = SpotlightMarks.item(for: Mark(path: "/n.md", kind: "markdown", quote: "short", target: 3, place: "Line 3"))
        XCTAssertEqual(plain.attributeSet.contentDescription, "n.md · Line 3")
        let long = SpotlightMarks.item(for: Mark(path: "/n.md", kind: "markdown", quote: String(repeating: "a", count: 200), target: 3, place: "Line 3"))
        XCTAssertEqual(long.attributeSet.title?.count, 79)                                     // shortened, with an ellipsis
    }

    func testAResultFindsItsMark() {
        let marks = [Mark(path: "/a", kind: "text", quote: "x", target: 1, place: "Line 1"), Mark(path: "/b", kind: "text", quote: "y", target: 2, place: "Line 2")]
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: marks[1].id.uuidString]
        XCTAssertEqual(SpotlightMarks.mark(for: activity, in: marks)?.quote, "y")
        XCTAssertNil(SpotlightMarks.mark(for: NSUserActivity(activityType: "something.else"), in: marks))
    }

    func testEverySaveHandsTheMarksOn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-spotlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MarkStore(file: dir.appendingPathComponent("m.json"))
        var handed: [[Mark]] = []
        store.onSave = { handed.append($0) }
        let mark = try XCTUnwrap(store.add(Selection(quote: "q", target: 1, place: "Line 1"), in: dir.appendingPathComponent("a.txt"), kind: "text"))
        store.setNote("n", for: mark)
        store.remove(store.marks[0])
        XCTAssertEqual(handed.map(\.count), [1, 1, 0])
    }
}
