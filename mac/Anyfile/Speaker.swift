// Reading aloud with the system's voices: from the selection or the top of the page, the word being
// spoken highlighted in the text and kept in view. The voice follows the text's language; Marathi
// falls back to a Hindi voice, which reads Devanagari, when no Marathi voice is installed.
import AppKit
import AVFoundation
import NaturalLanguage
import Observation

/// The text view a window is showing, so the window can read it aloud. Panes set it as they appear.
final class TextViewHandle {
    weak var textView: NSTextView?
}

@MainActor @Observable
final class Speaker: NSObject {
    enum State { case idle, speaking, paused }

    private(set) var state = State.idle
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private weak var textView: NSTextView?
    @ObservationIgnored private var start = 0
    @ObservationIgnored private var spoken: NSRange?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Starts reading `tv` aloud, from its selection or else the top of what is on screen.
    func speak(_ tv: NSTextView, language: String?) {
        stop()
        let text = tv.string
        let from = Self.startingPoint(selection: tv.selectedRange(), top: ReadingPlace.topCharacter(in: tv), length: (text as NSString).length)
        guard let utterance = Self.utterance(for: text, from: from, language: language) else { return }
        textView = tv
        start = from
        state = .speaking
        synthesizer.speak(utterance)
    }

    func pauseOrResume() {
        switch state {
        case .speaking: if synthesizer.pauseSpeaking(at: .word) { state = .paused }
        case .paused: if synthesizer.continueSpeaking() { state = .speaking }
        case .idle: break
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        unpaint()
        state = .idle
        textView = nil
    }

    // MARK: The parts that can be checked without a sound

    /// The selection when there is one, else the first character on screen.
    nonisolated static func startingPoint(selection: NSRange, top: Int, length: Int) -> Int {
        let from = selection.length > 0 ? selection.location : top
        return min(max(from, 0), max(length - 1, 0))
    }

    nonisolated static func utterance(for text: String, from: Int, language: String?) -> AVSpeechUtterance? {
        let ns = text as NSString
        guard from < ns.length else { return nil }
        let rest = ns.substring(from: from)
        guard !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let u = AVSpeechUtterance(string: rest)
        u.voice = voice(for: language ?? detectedLanguage(of: rest), among: AVSpeechSynthesisVoice.speechVoices())
        return u
    }

    /// The best installed voice for a language: the exact language, else Hindi for Marathi (both are
    /// written in Devanagari), else nil, which leaves the system's own voice.
    nonisolated static func voice(for language: String?, among voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        guard let language, !language.isEmpty else { return nil }
        let base = String(language.lowercased().prefix(while: { $0 != "-" && $0 != "_" }))
        func best(_ code: String) -> AVSpeechSynthesisVoice? {
            voices.filter { $0.language.lowercased().hasPrefix(code) }.max { $0.quality.rawValue < $1.quality.rawValue }
        }
        return best(base) ?? (base == "mr" ? best("hi") : nil)
    }

    /// The language a stretch of text is in, for files that do not say.
    nonisolated static func detectedLanguage(of text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(2000)))
        return r.dominantLanguage?.rawValue
    }

    /// A word the synthesizer is speaking, as a range in the whole text it started partway into.
    nonisolated static func wordInText(_ word: NSRange, start: Int) -> NSRange {
        NSRange(location: word.location + start, length: word.length)
    }

    // MARK: Highlighting

    fileprivate func paint(_ word: NSRange) {
        guard let tv = textView, let lm = tv.layoutManager, NSMaxRange(word) <= (tv.string as NSString).length else { return }
        unpaint()
        lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, forCharacterRange: word)
        lm.addTemporaryAttribute(.underlineColor, value: NSColor.controlAccentColor, forCharacterRange: word)
        spoken = word
        tv.scrollRangeToVisible(word)
    }

    private func unpaint() {
        guard let tv = textView, let lm = tv.layoutManager, let spoken, NSMaxRange(spoken) <= (tv.string as NSString).length else { return }
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: spoken)
        lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: spoken)
        self.spoken = nil
    }

    fileprivate func finished() {
        unpaint()
        state = .idle
        textView = nil
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.paint(Speaker.wordInText(range, start: self.start)) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
