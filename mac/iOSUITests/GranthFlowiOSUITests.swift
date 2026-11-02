// GranthFlow on iPhone, driven by taps: marking a passage, writing a note on it, and finding it
// again from the library. Each test starts on its own file, library and marks.
import UIKit
import XCTest

final class GranthFlowiOSUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Launches the app on a temp file via `--open`, with a library and marks of its own.
    private func launch(_ contents: Data, as name: String) -> XCUIApplication {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("granthflow-ui-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try! contents.write(to: url)
        let app = XCUIApplication()
        app.launchArguments = ["--open", url.path, "--library", dir.appendingPathComponent("library.json").path,
                               "--marks", dir.appendingPathComponent("marks.json").path]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Selects the word at a point, then chooses Mark from the menu over it. Text views select a word
    /// on a double tap; PDFView on a long press.
    private func mark(_ app: XCUIApplication, at point: XCUICoordinate, longPress: Bool = false) {
        if longPress { point.press(forDuration: 1) } else { point.doubleTap() }
        let mark = app.menuItems["Mark"].exists ? app.menuItems["Mark"] : app.buttons["Mark"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5), app.debugDescription)
        mark.tap()
    }

    func testAPassageMarkedInAPreviewTakesANoteAndOpensFromTheLibrary() {
        let app = launch(Data("Ishmael speaks first.\n\nSome years ago.\n".utf8), as: "note.md")
        let preview = app.segmentedControls.buttons["Preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        let page = element(app, "paperText")
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        mark(app, at: page.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 110)))      // "Some", on line 3

        element(app, "marksButton").tap()
        XCTAssertTrue(element(app, "mark.Some").waitForExistence(timeout: 5), app.debugDescription)
        element(app, "addNote").tap()
        let field = element(app, "noteField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("The narrator names himself.")
        app.buttons["Done"].tap()                                          // leaving the field keeps the note
        app.navigationBars.buttons["Library"].tap()

        element(app, "sectionMenu").tap()
        app.buttons["Marks"].tap()
        let row = element(app, "mark.Some")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The narrator names himself."].exists)
        row.staticTexts["note.md  ·  Line 3"].tap()
        XCTAssertTrue(element(app, "paperText").waitForExistence(timeout: 10))     // back in the preview, where the mark is
    }

    func testAPassageCanBeMarkedInABook() {
        let app = launch(tinyEpub(), as: "book.epub")
        let page = element(app, "paperText")
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        mark(app, at: page.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 135)))     // "Hello", under the title
        element(app, "marksButton").tap()
        XCTAssertTrue(element(app, "mark.Hello").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["First"].exists)                     // the place is the chapter's title
    }

    func testAPdfPassageCanBeMarked() {
        let app = launch(onePagePdf(), as: "report.pdf")
        let pdf = element(app, "pdfView")
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        let line = pdf.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Quarterly'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        mark(app, at: line.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), longPress: true)      // "held", mid-line
        element(app, "marksButton").tap()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(element(app, "mark.Quarterly").exists)              // the word pressed, not the line's first
    }

    func testFindInABookGoesToTheChapter() {
        let app = launch(tinyEpub(), as: "find.epub")
        let page = element(app, "paperText")
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        element(app, "findButton").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("CLOSING")                                          // any case
        let hit = element(app, "hit.0")
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        XCTAssertTrue(hit.staticTexts["Second Heading"].exists)            // the hit's place is its chapter
        hit.tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Closing words."), evaluatedWith: page)
        waitForExpectations(timeout: 5)
    }

    func testSearchEveryFileFindsAndOpens() {
        let app = launch(Data("Ishmael speaks first.\n\nSome years ago, a whale.\n".utf8), as: "sea.md")
        XCTAssertTrue(app.segmentedControls.buttons["Edit"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Library"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("whale")
        let hit = element(app, "searchHit.sea.md.0")
        XCTAssertTrue(hit.waitForExistence(timeout: 10))
        XCTAssertTrue(hit.staticTexts["Line 3"].exists)
        hit.tap()
        XCTAssertTrue(element(app, "paperText").waitForExistence(timeout: 10))   // the note opens in its preview, at the line
    }

    func testABookCanBeReadAloudAndStopped() {
        let app = launch(tinyEpub(), as: "aloud.epub")
        XCTAssertTrue(element(app, "paperText").waitForExistence(timeout: 10))
        element(app, "readAloud").tap()
        let stop = element(app, "stopReading")
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "pauseReading").exists)
        stop.tap()
        XCTAssertTrue(element(app, "readAloud").waitForExistence(timeout: 5))
    }

    /// One page with one large line, near its top left.
    private func onePagePdf() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { context in
            context.beginPage()
            ("Quarterly costs held flat." as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 30)])
        }
    }

    private func tinyEpub() -> Data {
        let files: [(String, String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
            ("OPS/book.opf", "<package version=\"3.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>Tiny Book</dc:title></metadata>"
                + "<manifest><item id=\"a\" href=\"a.xhtml\"/><item id=\"b\" href=\"b.xhtml\"/><item id=\"n\" href=\"nav.xhtml\" properties=\"nav\"/></manifest>"
                + "<spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>"),
            ("OPS/a.xhtml", "<html><body><h1>First</h1><p>Hello book &amp; reader.</p></body></html>"),
            ("OPS/b.xhtml", "<html><body><h1>Second Heading</h1><p>Closing words.</p></body></html>"),
            ("OPS/nav.xhtml", "<html><body><nav><ol><li><a href=\"a.xhtml\">First</a></li></ol></nav></body></html>"),
        ]
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }
        func crc32(_ bytes: [UInt8]) -> Int {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
            }
            return Int(~crc)
        }
        var body: [UInt8] = [], directory: [UInt8] = []
        for (fileName, fileContent) in files {
            let name = Array(fileName.utf8), content = Array(fileContent.utf8)
            let fields = le16(10) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(crc32(content))
                + le32(content.count) + le32(content.count) + le16(name.count) + le16(0)
            directory += [0x50, 0x4B, 0x01, 0x02] + le16(20) + fields + le16(0) + le16(0) + le16(0) + le32(0) + le32(body.count) + name
            body += [0x50, 0x4B, 0x03, 0x04] + fields + name + content
        }
        let end = [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(files.count) + le16(files.count)
            + le32(directory.count) + le32(body.count) + le16(0)
        return Data(body + directory + end)
    }
}
