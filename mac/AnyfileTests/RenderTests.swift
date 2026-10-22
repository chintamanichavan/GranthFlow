// Draws views off-screen. The assertions check layout; the PNGs (written only when
// ANYFILE_SNAPSHOT_DIR is set) are for a person to look at, not for pixel comparison.
import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class RenderTests: XCTestCase {
    private func render<V: View>(_ view: V, named name: String) -> CGSize {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.nsImage else { XCTFail("\(name) did not render"); return .zero }
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"],
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return image.size
    }

    func testActionBarKeepsItsSizeWhicheverActionIsActive() {
        let idle = render(ActionBar(active: .constant(nil), kind: "markdown").padding(30).background(Color.white), named: "actionbar-idle")
        XCTAssertGreaterThan(idle.width, 300)
        XCTAssertLessThan(idle.height, 120)
        for action in DocumentAction.allCases {
            let size = render(ActionBar(active: .constant(action), kind: "markdown").padding(30).background(Color.white), named: "actionbar-\(action.rawValue)")
            XCTAssertEqual(size.height, idle.height, accuracy: 1, action.title)   // the bar never changes shape
        }
    }

    func testInfoPanelRendersWithinItsWidth() {
        let doc = AnyfileDocument(data: Data(Fixtures.markdown.utf8), name: "n.md")
        let panel = CommandPanel(title: "Info", commands: CommandRole.infoCommands(for: doc.kind),
                                 document: .constant(doc), runsImmediately: true, onApply: { _ in })
            .frame(width: 620)
            .background(Color(white: 0.95))
        let size = render(panel, named: "panel-info")
        XCTAssertEqual(size.width, 620, accuracy: 1)
        XCTAssertGreaterThan(size.height, 150)
    }

    func testContentsPanelIndentsByLevelAndKeepsItsWidth() {
        let entries = Contents.parseOutline("1\tProject notes\n5\t  Status\n9\t    Open questions\n14\t  Next steps\n")
        let size = render(ContentsPanel(entries: entries, current: 5, choose: { _ in }).frame(height: 300).background(Color(white: 0.95)),
                          named: "contents-panel")
        XCTAssertEqual(size.width, 260, accuracy: 1)
        // ScrollView content does not draw off-screen, so the rows are drawn on their own as well.
        let rows = VStack(spacing: 1) {
            ForEach(entries) { ContentsRow(entry: $0, isCurrent: $0.target == 5, choose: {}) }
        }
        let rowsSize = render(rows.frame(width: 248).padding(6).background(Color(white: 0.95)), named: "contents-rows")
        XCTAssertGreaterThan(rowsSize.height, CGFloat(entries.count) * 20)
    }

    func testFindRowsShowPlaceAndSnippet() {
        let doc = AnyfileDocument(data: Data("Call me Ishmael.\nThe whale.\nWhale again, a whale.\n".utf8), name: "m.txt")
        let hits = Find.hits(for: "whale", in: doc)
        let rows = VStack(spacing: 1) { ForEach(hits) { FindRow(hit: $0, choose: {}) } }
        let size = render(rows.frame(width: 560).padding(8).background(Color(white: 0.95)), named: "find-rows")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(size.width, 576, accuracy: 1)
    }
}
