import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class DevanagariTests: XCTestCase {
    /// The fonts Core Text actually draws each run of the text in.
    private func fonts(_ text: String, _ font: NSFont) -> [String] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return (CTLineGetGlyphRuns(line) as! [CTRun]).map {
            CTFontCopyPostScriptName((CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String
        }
    }

    func testDevanagariIsSetInABookFaceNotTheInterfaceFont() {
        let used = fonts("Book ग्रंथ", Theme.readingFont(size: 17, language: "hi"))
        XCTAssertEqual(used.count, 2, "\(used)")
        XCTAssertTrue(used[0].contains("NewYork"), used[0])
        XCTAssertEqual(used[1], "ITFDevanagari-Book")
    }

    func testDevanagariRunsAreSetALittleLargerToMatchTheLatin() {
        let s = ReadingStyle.body("Book ग्रंथ book", language: "mr")
        let latin = s.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        var range = NSRange()
        let deva = s.attribute(.font, at: 5, effectiveRange: &range) as! NSFont
        XCTAssertEqual(latin.pointSize, ReadingStyle.bodySize)
        XCTAssertEqual(deva.fontName, "ITFDevanagariMarathi-Book")
        XCTAssertEqual(deva.pointSize, ReadingStyle.bodySize * Theme.devanagariScale, accuracy: 0.01)
        XCTAssertEqual((s.string as NSString).substring(with: range), "ग्रंथ")              // the whole word, conjunct and all
        XCTAssertEqual(fonts("ग्रंथ", deva), ["ITFDevanagariMarathi-Book"])
    }

    func testMarathiBooksGetTheMarathiForms() {
        XCTAssertEqual(fonts("लिहिणे", Theme.readingFont(size: 17, language: "mr")), ["ITFDevanagariMarathi-Book"])
        XCTAssertEqual(fonts("लिहिणे", Theme.readingFont(size: 17, weight: .semibold, language: "mr-IN")), ["ITFDevanagariMarathi-Medium"])
        XCTAssertEqual(fonts("ग्रंथ", Theme.readingFont(size: 30, weight: .bold, language: "mr")), ["ITFDevanagariMarathi-Bold"])
    }

    func testLanguageComesFromTheBookThenTheMac() {
        XCTAssertTrue(Theme.isMarathi("mr"))
        XCTAssertFalse(Theme.isMarathi("en-US", preferred: ["mr-IN"]))               // the book says English
        XCTAssertTrue(Theme.isMarathi(nil, preferred: ["en-US", "mr-IN"]))            // no language: the Mac's
        XCTAssertFalse(Theme.isMarathi("", preferred: ["en-GB"]))
    }

    func testAChapterCarriesItsLanguageToEveryRun() {
        let s = ReadingStyle.chapter("स्वराज्य हा माझा जन्मसिद्ध हक्क आहे.", number: 1, title: "पहिला", language: "mr")
        var faces = Set<String>()
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, range, _ in
            let font = value as! NSFont
            faces.formUnion(fonts((s.string as NSString).substring(with: range), font))
        }
        XCTAssertTrue(faces.allSatisfy { $0.hasPrefix("ITFDevanagariMarathi") || $0.contains("SF") || $0.contains("NewYork") }, "\(faces)")
        XCTAssertTrue(faces.contains("ITFDevanagariMarathi-Book"), "\(faces)")
    }

    func testAMarathiPageDraws() throws {
        let text = "पहिला\n\nस्वराज्य हा माझा जन्मसिद्ध हक्क आहे आणि तो मी मिळवणारच. ग्रंथ हे गुरु आहेत; ते आपल्याला विचार करायला शिकवतात. " +
                   "Some English in the same paragraph, to see the two scripts side by side."
        let view = ReadingText(text: text, number: 1, title: "पहिला", language: "mr")
        let host = NSHostingView(rootView: view.frame(width: 760, height: 420))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("marathi.png"))
        }
    }
}
