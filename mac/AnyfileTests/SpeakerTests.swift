import XCTest
import AVFoundation
@testable import Anyfile

/// Reading aloud, tested without making a sound: what is spoken, from where, in which voice.
final class SpeakerTests: XCTestCase {
    private let voices = AVSpeechSynthesisVoice.speechVoices()

    func testTheVoiceFollowsTheLanguage() throws {
        let english = try XCTUnwrap(Speaker.voice(for: "en-US", among: voices))
        XCTAssertTrue(english.language.hasPrefix("en"))
        XCTAssertNil(Speaker.voice(for: "xx", among: voices))                       // no such voice: the system's own
        XCTAssertNil(Speaker.voice(for: nil, among: voices))
        XCTAssertNil(Speaker.voice(for: "en", among: []))
    }

    func testMarathiFallsBackToAHindiVoiceWhenNoneIsInstalled() throws {
        let marathi = voices.filter { $0.language.hasPrefix("mr") }
        let chosen = Speaker.voice(for: "mr", among: voices)
        if marathi.isEmpty {
            try XCTSkipIf(!voices.contains { $0.language.hasPrefix("hi") }, "no Hindi voice on this Mac either")
            XCTAssertTrue(chosen?.language.hasPrefix("hi") == true, chosen?.language ?? "nil")   // Devanagari, read by a Hindi voice
        } else {
            XCTAssertTrue(chosen?.language.hasPrefix("mr") == true)
        }
    }

    func testReadingStartsAtTheSelectionElseTheTopOfThePage() {
        XCTAssertEqual(Speaker.startingPoint(selection: NSRange(location: 40, length: 5), top: 10, length: 100), 40)
        XCTAssertEqual(Speaker.startingPoint(selection: NSRange(location: 40, length: 0), top: 10, length: 100), 10)
        XCTAssertEqual(Speaker.startingPoint(selection: NSRange(location: 0, length: 0), top: 500, length: 100), 99)
    }

    func testTheUtteranceIsTheTextFromThatPoint() throws {
        let u = try XCTUnwrap(Speaker.utterance(for: "Loomings\n\nCall me Ishmael.", from: 10, language: "en"))
        XCTAssertEqual(u.speechString, "Call me Ishmael.")
        XCTAssertTrue(u.voice?.language.hasPrefix("en") == true)
        XCTAssertNil(Speaker.utterance(for: "text   \n\n", from: 4, language: "en"))      // nothing left but space
        XCTAssertNil(Speaker.utterance(for: "short", from: 9, language: "en"))
    }

    func testFilesThatDoNotSayTheirLanguageAreRecognised() {
        XCTAssertEqual(Speaker.detectedLanguage(of: "Call me Ishmael. Some years ago, never mind how long precisely."), "en")
        let marathi = Speaker.detectedLanguage(of: "स्वराज्य हा माझा जन्मसिद्ध हक्क आहे आणि तो मी मिळवणारच.")
        XCTAssertTrue(marathi == "mr" || marathi == "hi", marathi ?? "nil")
    }

    func testSpokenWordsMapBackOntoThePage() {
        XCTAssertEqual(Speaker.wordInText(NSRange(location: 5, length: 3), start: 10), NSRange(location: 15, length: 3))
    }
}
