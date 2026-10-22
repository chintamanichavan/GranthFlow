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
        let idle = render(ActionBar(active: .constant(nil)).padding(30).background(Color.white), named: "actionbar-idle")
        XCTAssertGreaterThan(idle.width, 300)
        XCTAssertLessThan(idle.height, 120)
        for action in DocumentAction.allCases {
            let size = render(ActionBar(active: .constant(action)).padding(30).background(Color.white), named: "actionbar-\(action.rawValue)")
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
}
