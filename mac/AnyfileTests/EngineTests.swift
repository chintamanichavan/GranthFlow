import XCTest
@testable import Anyfile

final class EngineTests: XCTestCase {
    func testDetectKindUsesMagicThenExtensionThenContent() {
        XCTAssertEqual(Engine.detectKind(of: Data("%PDF-1.4\n".utf8), name: "x.bin"), "pdf")
        XCTAssertEqual(Engine.detectKind(of: Data("# hi".utf8), name: "notes.md"), "markdown")
        XCTAssertEqual(Engine.detectKind(of: Data("plain".utf8), name: "a.txt"), "text")
        XCTAssertEqual(Engine.detectKind(of: Data("plain".utf8), name: "noext"), "text")
        XCTAssertEqual(Engine.detectKind(of: Fixtures.binary, name: "a.dat"), "binary")
        XCTAssertEqual(Engine.detectKind(of: Fixtures.epub, name: "book.epub"), "epub")
        XCTAssertEqual(Engine.detectKind(of: Fixtures.epub, name: "noext"), "epub")
        XCTAssertEqual(Engine.detectKind(of: Fixtures.zip([("a.txt", "x")]), name: "plain.zip"), "binary")
    }

    func testCommandsPerKindIncludeOwnAndCommon() {
        let md = Engine.commands(for: "markdown").map(\.name)
        XCTAssertTrue(md.contains("outline") && md.contains("replace") && md.contains("hex"))
        XCTAssertEqual(md.first, "render")
        let pdf = Engine.commands(for: "pdf").map(\.name)
        XCTAssertTrue(pdf.contains("set-meta") && pdf.contains("add-page") && pdf.contains("info"))
        XCTAssertFalse(pdf.contains("outline"))
        XCTAssertFalse(Engine.commands(for: "binary").map(\.name).contains("grep"))
    }

    func testTextReplaceReturnsChangedBytes() {
        let r = Engine.run("replace", args: ["beta", "BETA"], on: Data(Fixtures.text.utf8), name: "a.txt", kind: "text")
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.output, "replaced 1 occurrence\n")
        XCTAssertEqual(r.changedData.map { String(decoding: $0, as: UTF8.self) }, "alpha\nBETA\ngamma\n")
    }

    func testReadOnlyCommandLeavesDataUnchanged() {
        let r = Engine.run("lines", args: ["2"], on: Data(Fixtures.text.utf8), name: "a.txt", kind: "text")
        XCTAssertEqual(r.output, "2\tbeta\n")
        XCTAssertNil(r.changedData)
    }

    func testPdfSetMetaThenMetaOnResult() {
        let pdf = Data(Fixtures.tinyPdf.utf8)
        let set = Engine.run("set-meta", args: ["Title", "Edited"], on: pdf, name: "t.pdf", kind: "pdf")
        XCTAssertTrue(set.succeeded, set.errorText)
        guard let changed = set.changedData else { return XCTFail("no data returned") }
        XCTAssertTrue(changed.count > pdf.count)                   // incremental update appended
        XCTAssertEqual(changed.prefix(pdf.count), pdf)             // original bytes intact
        let meta = Engine.run("meta", args: [], on: changed, name: "t.pdf", kind: "pdf")
        XCTAssertTrue(meta.output.contains("Title: Edited"))
        let text = Engine.run("text", args: [], on: changed, name: "t.pdf", kind: "pdf")
        XCTAssertEqual(text.output, "Hello PDF World\n")
    }

    func testMarkdownSectionCommands() {
        let md = Data(Fixtures.markdown.utf8)
        XCTAssertEqual(Engine.run("outline", args: [], on: md, name: "n.md", kind: "markdown").output, "1\tTitle\n5\t  Status\n")
        let r = Engine.run("replace-section", args: ["Status", "new body"], on: md, name: "n.md", kind: "markdown")
        XCTAssertTrue(r.succeeded)
        XCTAssertTrue(String(decoding: r.changedData ?? Data(), as: UTF8.self).contains("## Status\n\nnew body\n"))
    }

    func testFixtureCrcMatchesStandardCheckValue() {
        XCTAssertEqual(Fixtures.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testEpubCommandsListed() {
        let names = Engine.commands(for: "epub").map(\.name)
        XCTAssertEqual(names.first, "text")
        XCTAssertTrue(names.contains("chapters") && names.contains("set-meta") && names.contains("replace") && names.contains("hex"))
        XCTAssertFalse(names.contains("add-page"))
    }

    func testEpubReadCommands() {
        let run = { (cmd: String, args: [String]) in Engine.run(cmd, args: args, on: Fixtures.epub, name: "b.epub", kind: "epub") }
        XCTAssertEqual(run("chapters", []).output, "1\tOpening\tOPS/a.xhtml\n2\tSecond Heading\tOPS/b.xhtml\n")
        XCTAssertEqual(run("text", ["1"]).output, "First\n\nHello book & reader.\n")
        XCTAssertEqual(run("meta", []).output, "title: Tiny Book\ncreator: Tester\n")
        XCTAssertTrue(run("info", []).output.contains("epub:       version 3.0, 2 chapters, 6 files"))
        XCTAssertNil(run("text", []).changedData)
        let missing = run("text", ["9"])
        XCTAssertEqual(missing.status, .error)
        XCTAssertTrue(missing.errorText.contains("no chapter 9"))
    }

    func testEpubReplaceAndSetMetaReturnAReadableBook() {
        let replaced = Engine.run("replace", args: ["Closing", "Final"], on: Fixtures.epub, name: "b.epub", kind: "epub")
        XCTAssertTrue(replaced.succeeded, replaced.errorText)
        guard let book = replaced.changedData else { return XCTFail("no data returned") }
        XCTAssertEqual(Engine.run("text", args: ["2"], on: book, name: "b.epub", kind: "epub").output, "Second Heading\n\nFinal words.\n")
        XCTAssertEqual(Engine.run("text", args: ["1"], on: book, name: "b.epub", kind: "epub").output, "First\n\nHello book & reader.\n")
        XCTAssertEqual(Engine.detectKind(of: book, name: "noext"), "epub")     // mimetype entry still leads the archive

        let renamed = Engine.run("set-meta", args: ["title", "New Name"], on: book, name: "b.epub", kind: "epub")
        XCTAssertTrue(renamed.succeeded, renamed.errorText)
        let meta = Engine.run("meta", args: [], on: renamed.changedData ?? Data(), name: "b.epub", kind: "epub")
        XCTAssertEqual(meta.output, "title: New Name\ncreator: Tester\n")

        let none = Engine.run("replace", args: ["absent", "x"], on: Fixtures.epub, name: "b.epub", kind: "epub")
        XCTAssertEqual(none.status, .error)
        XCTAssertNil(none.changedData)
    }

    func testStatusCodes() {
        let data = Data(Fixtures.text.utf8)
        XCTAssertEqual(Engine.run("nope", args: [], on: data, name: "a.txt", kind: "text").status, .unknown)
        XCTAssertEqual(Engine.run("replace", args: ["only-one"], on: data, name: "a.txt", kind: "text").status, .badUsage)
        let err = Engine.run("replace", args: ["zzz", "y"], on: data, name: "a.txt", kind: "text")
        XCTAssertEqual(err.status, .error)
        XCTAssertTrue(err.errorText.contains("no match"))
        XCTAssertNil(err.changedData)
    }

    func testOutFlagIsStrippedSoNothingLeaksToDisk() {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-should-not-exist-\(UUID().uuidString).txt")
        let r = Engine.run("text", args: ["--out", target.path], on: Data(Fixtures.tinyPdf.utf8), name: "t.pdf", kind: "pdf")
        XCTAssertEqual(r.output, "Hello PDF World\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testSplitArguments() {
        XCTAssertEqual(Engine.splitArguments(""), [])
        XCTAssertEqual(Engine.splitArguments("  a   b "), ["a", "b"])
        XCTAssertEqual(Engine.splitArguments("Title \"My Doc\" 'x y' f\\ g"), ["Title", "My Doc", "x y", "f g"])
        XCTAssertEqual(Engine.splitArguments("\"\" tail"), ["", "tail"])
        XCTAssertEqual(Engine.splitArguments("a\\nb"), ["anb"])   // shell-style: backslash only escapes
    }
}
