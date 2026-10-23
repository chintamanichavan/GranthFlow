// How long the rest of a chapter will take: the words left, divided by the reader's own speed,
// learned as they read. The speed lives in UserDefaults (a plain plist) as words per minute.
import Foundation

enum ReadingTime {
    /// Words in a stretch of text. Devanagari, like English, puts spaces between words.
    static func words(in text: Substring) -> Int {
        var count = 0, inWord = false
        for ch in text.unicodeScalars {
            let space = CharacterSet.whitespacesAndNewlines.contains(ch)
            if !space && !inWord { count += 1 }
            inWord = !space
        }
        return count
    }

    static func words(in text: String, from character: Int) -> Int {
        let ns = text as NSString
        let start = min(max(character, 0), ns.length)
        return words(in: Substring(ns.substring(from: start)))
    }

    /// "6 min left in chapter", "1 min left in chapter", "Less than a minute left in chapter".
    static func phrase(wordsLeft: Int, wordsPerMinute: Double) -> String {
        let minutes = Double(wordsLeft) / max(wordsPerMinute, 1)
        if minutes < 1 { return "Less than a minute left in chapter" }
        let whole = Int(minutes.rounded())
        return whole >= 90 ? "\(whole / 60) h \(whole % 60) min left in chapter" : "\(whole) min left in chapter"
    }
}

/// The reader's speed in words per minute, adjusted a little by each stretch of reading.
struct ReadingSpeed {
    static let typical = 230.0
    /// Stretches outside these bounds are skimming, or the reader walking away, not reading.
    static let plausible = 60.0...900.0
    static let shortest: TimeInterval = 8, longest: TimeInterval = 600

    private(set) var wordsPerMinute: Double

    init(wordsPerMinute: Double = Self.typical) { self.wordsPerMinute = wordsPerMinute }

    /// Takes in one stretch: `words` read in `seconds`. Returns whether it counted.
    @discardableResult
    mutating func observe(words: Int, seconds: TimeInterval) -> Bool {
        guard words > 0, seconds >= Self.shortest, seconds <= Self.longest else { return false }
        let rate = Double(words) / (seconds / 60)
        guard Self.plausible.contains(rate) else { return false }
        wordsPerMinute += 0.2 * (rate - wordsPerMinute)          // moves a fifth of the way, so one odd stretch cannot swing it
        return true
    }
}

/// The speed kept between launches, and the last place, so the next stretch can be measured.
@MainActor
final class ReadingClock {
    static let shared = ReadingClock(defaults: .standard)
    private let defaults: UserDefaults
    private static let key = "readingWordsPerMinute"
    private var last: (book: String, chapter: Int, wordsLeft: Int, at: Date)?

    private(set) var speed: ReadingSpeed

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.key)
        speed = ReadingSpeed(wordsPerMinute: saved > 0 ? saved : ReadingSpeed.typical)
    }

    /// A new reading place. Moving on through the same chapter is a stretch of reading.
    func place(book: String, chapter: Int, wordsLeft: Int, at date: Date = Date()) {
        if let last, last.book == book, last.chapter == chapter, last.wordsLeft > wordsLeft,
           speed.observe(words: last.wordsLeft - wordsLeft, seconds: date.timeIntervalSince(last.at)) {
            defaults.set(speed.wordsPerMinute, forKey: Self.key)
        }
        last = (book, chapter, wordsLeft, date)
    }
}
