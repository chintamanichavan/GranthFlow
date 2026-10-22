import XCTest
@testable import Anyfile

/// The tests run inside the app, so Bundle.main is the built Anyfile.app.
final class IconTests: XCTestCase {
    /// The app is called GranthFlow wherever people see it; its code and folders keep the name Anyfile.
    func testTheAppIsCalledGranthFlow() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "GranthFlow")
        XCTAssertEqual(Bundle.main.bundleURL.lastPathComponent, "GranthFlow.app")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "local.granthflow.app")
    }

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

/// The Xcode project takes in the whole src folder, which also holds the granthflow web app.
/// Its files are excluded one by one, so a new one added there must be excluded too; this catches it.
final class BundleTests: XCTestCase {
    func testNoWebAppFilesInTheMacApp() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        let names = try FileManager.default.contentsOfDirectory(atPath: resources.path)
        let strays = names.filter { ["py", "js", "css", "html"].contains(($0 as NSString).pathExtension) }
        XCTAssertEqual(strays, [], "add these to the src exceptions in project.pbxproj")
    }
}
