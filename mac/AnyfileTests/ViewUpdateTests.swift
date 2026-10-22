import XCTest
import SwiftUI
@testable import Anyfile

/// SwiftUI warns "Modifying state during view update" when AppKit reports a change the app made
/// itself while updating a view. Reports must arrive afterwards, never during the call that caused them.
@MainActor
final class ViewUpdateTests: XCTestCase {
    func testTextSelectionIsReportedAfterTheChangeNotDuringIt() async {
        var reports: [Selection?] = []
        let coordinator = TextPane.Coordinator(text: .constant("one\ntwo"))
        coordinator.onSelect = { reports.append($0) }
        let tv = NSTextView()
        tv.string = "one\ntwo"
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: tv))
        XCTAssertTrue(reports.isEmpty, "reported while the change was still being made")
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first??.quote, "two")
        XCTAssertEqual(reports.first??.target, 2)
    }

    func testReadingSelectionIsReportedAfterTheChange() async {
        var reports: [String?] = []
        let coordinator = ReadingText.Coordinator()
        coordinator.onSelect = { reports.append($0) }
        let tv = NSTextView()
        tv.string = "Call me Ishmael."
        tv.setSelectedRange(NSRange(location: 8, length: 7))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: tv))
        XCTAssertTrue(reports.isEmpty)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(reports, ["Ishmael"])
    }
}
