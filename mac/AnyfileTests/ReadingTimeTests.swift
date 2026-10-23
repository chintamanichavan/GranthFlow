import XCTest
@testable import Anyfile

@MainActor
final class ReadingTimeTests: XCTestCase {
    func testWordsAreCountedInEnglishAndMarathi() {
        XCTAssertEqual(ReadingTime.words(in: "Call me  Ishmael.\n\nSome years ago"[...]), 6)
        XCTAssertEqual(ReadingTime.words(in: "माझे नाव इश्माएल आहे."[...]), 4)
        XCTAssertEqual(ReadingTime.words(in: "   "[...]), 0)
        XCTAssertEqual(ReadingTime.words(in: "one two three four", from: 4), 3)          // from a character on
        XCTAssertEqual(ReadingTime.words(in: "one", from: 99), 0)
    }

    func testPhrases() {
        XCTAssertEqual(ReadingTime.phrase(wordsLeft: 1380, wordsPerMinute: 230), "6 min left in chapter")
        XCTAssertEqual(ReadingTime.phrase(wordsLeft: 100, wordsPerMinute: 230), "Less than a minute left in chapter")
        XCTAssertEqual(ReadingTime.phrase(wordsLeft: 230 * 125, wordsPerMinute: 230), "2 h 5 min left in chapter")
    }

    func testSpeedLearnsFromReadingButNotFromSkimmingOrAbsence() {
        var s = ReadingSpeed()
        XCTAssertTrue(s.observe(words: 300, seconds: 60))                    // 300 wpm
        XCTAssertEqual(s.wordsPerMinute, 230 + 0.2 * 70, accuracy: 1e-9)
        let before = s.wordsPerMinute
        XCTAssertFalse(s.observe(words: 3000, seconds: 30))                  // 6000 wpm: skimming
        XCTAssertFalse(s.observe(words: 50, seconds: 1200))                  // twenty minutes: walked away
        XCTAssertFalse(s.observe(words: 5, seconds: 2))                      // too short to judge
        XCTAssertEqual(s.wordsPerMinute, before)
    }

    func testTheClockTimesStretchesWithinAChapterOnly() {
        let defaults = UserDefaults(suiteName: "anyfile-tests-\(UUID().uuidString)")!
        let clock = ReadingClock(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 0)
        clock.place(book: "b", chapter: 1, wordsLeft: 1000, at: t0)
        clock.place(book: "b", chapter: 1, wordsLeft: 700, at: t0.addingTimeInterval(60))     // 300 words in a minute
        XCTAssertEqual(clock.speed.wordsPerMinute, 244, accuracy: 1e-9)
        XCTAssertEqual(ReadingClock(defaults: defaults).speed.wordsPerMinute, 244, accuracy: 1e-9)   // kept
        clock.place(book: "b", chapter: 2, wordsLeft: 100, at: t0.addingTimeInterval(120))   // another chapter: not a stretch
        XCTAssertEqual(clock.speed.wordsPerMinute, 244, accuracy: 1e-9)
    }

    func testWordsLeftAreClearedWithTheChapter() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-time-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = dir.appendingPathComponent("b.epub")
        try Data("x".utf8).write(to: book)
        let lib = Library(file: dir.appendingPathComponent("l.json"))
        lib.recordOpened(book, kind: "epub")
        lib.recordPosition(book, position: 2, total: 9)
        lib.recordAnchor(book, anchor: 40, wordsLeft: 1200)
        XCTAssertEqual(lib.entry(for: book)?.wordsLeft, 1200)
        lib.recordPosition(book, position: 3, total: 9)
        XCTAssertNil(lib.entry(for: book)?.wordsLeft)
    }

    /// Words left are counted after every pause in scrolling. Prints the time for a long chapter.
    func testWordCountSpeedOnALongChapter() {
        let chapter = String(repeating: "It was the best of times, it was the worst of times, it was the age of wisdom. ", count: 4000)
        let start = Date()
        let n = ReadingTime.words(in: chapter, from: 0)
        let seconds = Date().timeIntervalSince(start)
        print(String(format: "words left in a %d KB chapter: %.4f s", chapter.utf8.count / 1024, seconds))
        XCTAssertEqual(n, 4000 * 18)                                        // 18 words in the sentence
        XCTAssertLessThan(seconds, 0.1)
    }
}
