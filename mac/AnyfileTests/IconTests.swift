import XCTest
@testable import Anyfile

/// The tests run inside the app, so Bundle.main is the built Anyfile.app.
final class IconTests: XCTestCase {
    func testTheAppNamesItsIcon() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
    }

    func testTheIconIsBuiltIntoTheApp() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appendingPathComponent("AppIcon.icns").path))
        let icon = try XCTUnwrap(NSImage(named: "AppIcon"))
        let largest = icon.representations.map(\.pixelsWide).max() ?? 0
        XCTAssertGreaterThanOrEqual(largest, 1024, "the Dock and Finder need the 1024-pixel image")
    }
}
