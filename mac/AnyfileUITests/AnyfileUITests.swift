import XCTest

final class AnyfileUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Launches the app directly on a temp file via `--open`, bypassing the Open panel.
    private func launch(_ contents: Data, as name: String) -> XCUIApplication {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-ui-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try! contents.write(to: url)
        let app = XCUIApplication()
        app.launchArguments = ["--open", url.path]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// SwiftUI text reports through `value` for multi-line content and `label` otherwise.
    private func text(of e: XCUIElement) -> String {
        let v = e.value as? String ?? ""
        return v.isEmpty ? e.label : v
    }

    /// Opens Info or Edit on the action bar, then picks and runs a command in its card.
    private func runCommand(_ app: XCUIApplication, _ name: String, args: String, in action: String) {
        let button = element(app, "action.\(action)")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        let picker = element(app, "commandPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        app.menuItems[name].firstMatch.click()
        let field = element(app, "argsField")
        if !args.isEmpty {
            field.click()
            field.typeKey("a", modifierFlags: .command)
            field.typeText(args)
        }
        element(app, "runButton").click()
    }

    func testTextFileOpensAndCountRuns() {
        let app = launch(Data("alpha\nbeta\ngamma\n".utf8), as: "notes.txt")
        let editor = element(app, "textEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue((editor.value as? String ?? "").contains("alpha"))
        XCTAssertTrue(text(of: element(app, "kindLabel")).contains("text"))
        runCommand(app, "count", args: "", in: "info")
        let output = element(app, "outputText")
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: output).contains("lines:      3"), text(of: output))
    }

    func testReplaceCommandUpdatesEditor() {
        let app = launch(Data("alpha\nbeta\n".utf8), as: "notes.txt")
        XCTAssertTrue(element(app, "textEditor").waitForExistence(timeout: 10))
        runCommand(app, "replace", args: "alpha ALPHA", in: "edit")
        let editor = element(app, "textEditor")
        let updated = NSPredicate(format: "value CONTAINS %@", "ALPHA")
        expectation(for: updated, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(text(of: element(app, "outputText")).contains("replaced 1"))
    }

    func testActionBarHasFiveActionsAndInfoShowsSummary() {
        let app = launch(Data("alpha\nbeta\n".utf8), as: "notes.txt")
        XCTAssertTrue(element(app, "actionBar").waitForExistence(timeout: 10))
        for id in ["contents", "find", "edit", "mark", "info"] {
            XCTAssertTrue(element(app, "action.\(id)").exists, id)
        }
        XCTAssertFalse(element(app, "commandPicker").exists)        // no card until an action is chosen
        element(app, "action.info").click()
        let output = element(app, "outputText")
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: output).contains("text"), text(of: output))   // info ran without pressing Run
        element(app, "action.info").click()
        XCTAssertTrue(element(app, "commandPicker").waitForNonExistence(timeout: 5))
    }

    func testMarkdownPreviewToggle() {
        let app = launch(Data("# Title\n\n- item\n".utf8), as: "doc.md")
        let mode = element(app, "markdownMode")
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        let preview = mode.radioButtons["Preview"].exists ? mode.radioButtons["Preview"] : app.descendants(matching: .any)["Preview"].firstMatch
        preview.click()
        let rendered = element(app, "markdownPreview")
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: rendered).contains("Title"), text(of: rendered))
        XCTAssertTrue(text(of: rendered).contains("item"))
    }

    func testMarkdownContentsJumpsToHeading() {
        let body = (1...80).map { "line \($0)" }.joined(separator: "\n")
        let app = launch(Data("# Top\n\(body)\n## Bottom\nlast\n".utf8), as: "long.md")
        let editor = element(app, "textEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        element(app, "action.contents").click()
        let bottom = app.buttons["Bottom"].firstMatch
        XCTAssertTrue(bottom.waitForExistence(timeout: 5))
        bottom.click()
        app.typeText("X")                                   // the jump selected the heading line and focused the editor
        let replaced = NSPredicate(format: "value CONTAINS %@ AND NOT (value CONTAINS %@)", "line 80\nX\nlast", "## Bottom")
        expectation(for: replaced, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
    }

    func testContentsDisabledForPlainText() {
        let app = launch(Data("alpha\n".utf8), as: "notes.txt")
        XCTAssertTrue(element(app, "actionBar").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "action.contents").isEnabled)
        XCTAssertTrue(element(app, "action.info").isEnabled)
    }

    func testPdfOpensAndExtractedTextShows() {
        let pdf = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 300 200] >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj
        4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
        5 0 obj << /Length 44 >>
        stream
        BT /F1 18 Tf 20 150 Td (Hello PDF World) Tj ET
        endstream
        endobj
        trailer << /Root 1 0 R >>
        """
        let app = launch(Data(pdf.utf8), as: "tiny.pdf")
        XCTAssertTrue(element(app, "pdfView").waitForExistence(timeout: 10))
        element(app, "pdfTextToggle").click()
        let text = element(app, "pdfText")
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(self.text(of: text).contains("Hello PDF World"), self.text(of: text))
    }

    func testBinaryShowsHex() {
        let app = launch(Data([0x7f, 0x45, 0x4c, 0x46, 0x00, 0x01]), as: "blob.bin")
        let hex = element(app, "hexText")
        XCTAssertTrue(hex.waitForExistence(timeout: 10))
        XCTAssertTrue(text(of: hex).contains("7f 45 4c 46 00 01"), text(of: hex))
    }

    func testEpubShowsChaptersAndSwitchesText() {
        let app = launch(tinyEpub(), as: "book.epub")
        let reading = element(app, "epubText")
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        XCTAssertTrue(text(of: element(app, "kindLabel")).contains("epub"))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Hello book & reader."), evaluatedWith: reading)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(element(app, "contentsPanel").exists)          // chapters stay out of the way until asked for
        element(app, "action.contents").click()
        XCTAssertTrue(element(app, "contentsPanel").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Opening"].exists)
        app.buttons["Second Heading"].firstMatch.click()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Closing words."), evaluatedWith: reading)
        waitForExpectations(timeout: 5)
    }

    func testEpubReplaceUpdatesReadingText() {
        let app = launch(tinyEpub(), as: "book.epub")
        let reading = element(app, "epubText")
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        runCommand(app, "replace", args: "Hello Goodbye", in: "edit")
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Goodbye book"), evaluatedWith: reading)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(text(of: element(app, "outputText")).contains("chapter 1: 1 replacement"))
    }

    /// The same two-chapter book as the unit tests, as an uncompressed zip written by hand.
    /// (The UI test bundle cannot see the app's test fixtures, so the few lines are repeated here.)
    private func tinyEpub() -> Data {
        let files: [(String, String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
            ("OPS/book.opf", "<package version=\"3.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>Tiny Book</dc:title></metadata>"
                + "<manifest><item id=\"a\" href=\"a.xhtml\"/><item id=\"b\" href=\"b.xhtml\"/><item id=\"n\" href=\"nav.xhtml\" properties=\"nav\"/></manifest>"
                + "<spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>"),
            ("OPS/a.xhtml", "<html><body><h1>First</h1><p>Hello book &amp; reader.</p></body></html>"),
            ("OPS/b.xhtml", "<html><body><h1>Second Heading</h1><p>Closing words.</p></body></html>"),
            ("OPS/nav.xhtml", "<html><body><nav><ol><li><a href=\"a.xhtml\">Opening</a></li></ol></nav></body></html>"),
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
