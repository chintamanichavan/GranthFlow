import XCTest
import SwiftUI
@testable import Anyfile

@MainActor
final class ReadingSettingsTests: XCTestCase {
    func testSizeStepsAndStopsAtTheEnds() {
        var s = ReadingSettings()
        XCTAssertEqual(s.larger().size, 18)
        XCTAssertEqual(s.smaller().size, 16)
        s.size = 28
        XCTAssertEqual(s.larger().size, 28)
        s.size = 13
        XCTAssertEqual(s.smaller().size, 13)
    }

    func testTheColumnGrowsWithTheText() {
        var s = ReadingSettings()
        XCTAssertEqual(s.measure, 560)                                      // the measure chosen for 17 pt
        s.size = 34 / 2 * 1.5
        XCTAssertEqual(s.measure, 560 * 1.5, accuracy: 0.01)                // same words a line at a larger size
        s.width = .wide
        XCTAssertGreaterThan(s.measure, 560 * 1.5)
        XCTAssertLessThan(ReadingSettings.Spacing.allCases.map { ReadingSettings(spacing: $0).lineHeight }.first!, 1.45)
    }

    func testEachLookHasItsOwnPaper() {
        let fixed: [ReadingSettings.Look] = [.paper, .sepia, .night]
        let papers = fixed.map { ReadingSettings(look: $0).palette.window.usingColorSpace(.sRGB)! }
        XCTAssertEqual(Set(papers.map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent)" }).count, 3)
        // Auto is the light paper in light mode and dark paper in dark mode; Paper stays light in both.
        var autoInDark = NSColor.white, paperInDark = NSColor.white
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            autoInDark = ReadingSettings(look: .auto).palette.window.usingColorSpace(.sRGB)!
            paperInDark = ReadingSettings(look: .paper).palette.window.usingColorSpace(.sRGB)!
        }
        XCTAssertLessThan(autoInDark.brightnessComponent, 0.2)
        XCTAssertGreaterThan(paperInDark.brightnessComponent, 0.9)
        XCTAssertEqual(ReadingSettings(look: .night).isDark, true)
        XCTAssertNil(ReadingSettings(look: .auto).isDark)                   // follows the Mac
        XCTAssertGreaterThan(Theme.contrastWithWhite(Theme.readingNight.window), 12)
    }

    func testMissingFieldsTakeTheirDefaults() throws {
        let s = try JSONDecoder().decode(ReadingSettings.self, from: Data(#"{"size":20}"#.utf8))
        XCTAssertEqual(s.size, 20)
        XCTAssertEqual(s.look, .auto)
        XCTAssertEqual(s.width, .normal)
    }

    func testABookKeepsItsSettingsAndNewBooksStartWithTheLatestChoice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = dir.appendingPathComponent("b.epub")
        try Data("x".utf8).write(to: book)
        let store = dir.appendingPathComponent("l.json")
        var night = ReadingSettings(look: .night)
        night.size = 21
        let lib = Library(file: store)
        lib.recordOpened(book, kind: "epub")
        lib.recordSettings(book, night)
        XCTAssertEqual(Library(file: store).entry(for: book)?.settings, night)

        let defaults = UserDefaults(suiteName: "anyfile-tests-\(UUID().uuidString)")!
        XCTAssertEqual(ReadingDefaults.load(defaults), ReadingSettings())
        ReadingDefaults.save(night, defaults)
        XCTAssertEqual(ReadingDefaults.load(defaults), night)
    }

    func testTheStyleFollowsTheSettings() {
        var s = ReadingSettings(look: .sepia)
        s.size = 22
        s.spacing = .loose
        let text = ReadingStyle.chapter("Loomings\n\nCall me Ishmael.", number: 1, title: "Loomings", settings: s)
        let body = text.attributes(at: text.length - 3, effectiveRange: nil)
        XCTAssertEqual((body[.font] as? NSFont)?.pointSize, 22)
        XCTAssertEqual((body[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple, 1.7)
        XCTAssertEqual(body[.foregroundColor] as? NSColor, Theme.sepia.label)
        let title = text.attributes(at: 10, effectiveRange: nil)
        XCTAssertEqual((title[.font] as? NSFont)?.pointSize ?? 0, 30 * 22 / 17, accuracy: 0.01)
    }

    func testTheColumnFollowsTheMeasure() {
        let tv = PaperTextView()
        tv.measure = 460
        tv.setFrameSize(NSSize(width: 1000, height: 600))
        XCTAssertEqual(tv.textContainerInset.width, 270)
        tv.measure = 700
        XCTAssertEqual(tv.textContainerInset.width, 150)                    // changing it re-centres at once
    }

    func testLooksDraw() throws {
        for (name, settings) in [("sepia", ReadingSettings(look: .sepia)), ("night", ReadingSettings(look: .night)),
                                 ("large-loose", { var s = ReadingSettings(look: .paper); s.size = 22; s.spacing = .loose; return s }())] {
            let view = ReadingText(text: "Loomings\n\n" + String(repeating: "Call me Ishmael. Some years ago, never mind how long precisely. ", count: 6),
                                   number: 1, title: "Loomings", settings: settings)
            let host = NSHostingView(rootView: view.frame(width: 760, height: 400))
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 400)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let corner = try XCTUnwrap(rep.colorAt(x: 3, y: 3)?.usingColorSpace(.sRGB))
            let paper = settings.palette.window.usingColorSpace(.sRGB)!
            XCTAssertEqual(corner.redComponent, paper.redComponent, accuracy: 0.03, name)
            if let dir = ProcessInfo.processInfo.environment["ANYFILE_SNAPSHOT_DIR"], let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("look-\(name).png"))
            }
        }
    }
}

extension ReadingSettings {
    init(spacing: Spacing) { self.init(); self.spacing = spacing }
}
