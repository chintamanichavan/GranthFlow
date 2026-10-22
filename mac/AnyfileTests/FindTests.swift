import XCTest
@testable import Anyfile

final class FindTests: XCTestCase {
    func testFindIsAvailableForEveryKind() {
        for kind in ["pdf", "epub", "markdown", "text", "binary"] {
            XCTAssertNil(DocumentAction.find.unavailableReason(for: kind), kind)
        }
    }

    func testTextHitsAreLinesCaseInsensitive() {
        let doc = AnyfileDocument(data: Data("Alpha\nbeta\nALPHABET soup\n".utf8), name: "a.txt")
        let hits = Find.hits(for: "alpha", in: doc)
        XCTAssertEqual(hits.map(\.target), [1, 3])
        XCTAssertEqual(hits.map(\.place), ["Line 1", "Line 3"])
        XCTAssertEqual(hits.map(\.snippet), ["Alpha", "ALPHABET soup"])
        XCTAssertEqual(hits.map(\.id), [0, 1])
        XCTAssertEqual(Find.hits(for: "", in: doc), [])
        XCTAssertEqual(Find.hits(for: "zeta", in: doc), [])
    }

    func testHitsStopAtTheLimit() {
        let text = String(repeating: "x\n", count: Find.limit + 50)
        XCTAssertEqual(Find.lines("x", in: text, place: { "\($0)" }).count, Find.limit)
    }

    func testSnippetCentresLongLines() {
        let line = String(repeating: "a", count: 100) + "NEEDLE" + String(repeating: "b", count: 100)
        let s = Find.snippet(line, around: line.range(of: "NEEDLE")!)
        XCTAssertTrue(s.hasPrefix("…") && s.hasSuffix("…"))
        XCTAssertTrue(s.contains("NEEDLE"))
        XCTAssertLessThanOrEqual(s.count, 90)
        XCTAssertEqual(Find.snippet("  short  ", around: "  short  ".range(of: "short")!), "short")
    }

    func testEpubHitsNameTheChapter() {
        let doc = AnyfileDocument(data: Fixtures.epub, name: "b.epub")
        let hits = Find.hits(for: "closing", in: doc)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.target, 2)
        XCTAssertEqual(hits.first?.place, "Second Heading")
        XCTAssertEqual(hits.first?.snippet, "Closing words.")
        let both = Find.hits(for: "e", in: doc)
        XCTAssertEqual(Set(both.map(\.target)), [1, 2])
        XCTAssertEqual(both.map(\.id), Array(0..<both.count))     // ids stay unique across chapters
    }

    func testSplitBookFollowsChapterNumbers() {
        let out = "== 1. One ==\n\nfirst\n== 3. looks like a header ==\n\n== 2.  ==\n\nsecond\n"
        let texts = Find.splitBook(out)
        XCTAssertEqual(texts.keys.sorted(), [1, 2])
        XCTAssertTrue(texts[1]!.contains("first") && texts[1]!.contains("== 3. looks like a header =="))   // out of order: kept as text
        XCTAssertTrue(texts[2]!.contains("second"))
        XCTAssertEqual(Find.splitBook(""), [:])
    }

    /// The Find card searches off the main thread, so engine calls must not share state.
    func testEpubSearchesAgreeWhenRunConcurrently() {
        let doc = AnyfileDocument(data: Fixtures.epub, name: "b.epub")
        let expected = Find.hits(for: "e", in: doc)
        let results = UnsafeMutableBufferPointer<[FindHit]>.allocate(capacity: 8)
        results.initialize(repeating: [])
        defer { results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: 8) { i in results[i] = Find.hits(for: "e", in: doc) }
        for r in results { XCTAssertEqual(r, expected) }
    }

    func testPdfHitsComeFromPdfKit() {
        let doc = AnyfileDocument(data: Data(Fixtures.tinyPdf.utf8), name: "t.pdf")
        let hits = Find.hits(for: "world", in: doc)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.target, 0)
        XCTAssertEqual(hits.first?.place, "Page 1")
        XCTAssertTrue(hits.first?.snippet.contains("World") == true, hits.first?.snippet ?? "")
        XCTAssertEqual(Find.pdf("x", in: nil), [])
    }

    func testHexQueriesNeedPairsOrPrefix() {
        XCTAssertEqual(Find.hexBytes("7f 45 4c 46"), [0x7f, 0x45, 0x4c, 0x46])
        XCTAssertEqual(Find.hexBytes("0x7F454c"), [0x7f, 0x45, 0x4c])
        XCTAssertNil(Find.hexBytes("cafe"))          // a word, even though it is hex
        XCTAssertNil(Find.hexBytes("7f"))            // one pair could be a word too
        XCTAssertNil(Find.hexBytes("7f 4"))
        XCTAssertNil(Find.hexBytes("0x7f4"))
        XCTAssertNil(Find.hexBytes("zz yy"))
        XCTAssertNil(Find.hexBytes("0x"))
    }

    func testBinaryHitsAreOffsets() {
        let data = Data([0x00, 0x7f, 0x45, 0x4c, 0x46, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x7f, 0x45])
        let doc = AnyfileDocument(data: data, name: "a.bin")
        XCTAssertEqual(Find.hits(for: "7f 45", in: doc).map(\.target), [1, 10])
        XCTAssertEqual(Find.hits(for: "hello", in: doc).map(\.target), [5])
        XCTAssertEqual(Find.hits(for: "hello", in: doc).first?.place, "0x5")
        XCTAssertEqual(Find.hits(for: "7f 45", in: doc).last?.snippet, "7f 45")      // cut at the end of the file
        XCTAssertEqual(Find.bytes("longer than the file", in: Data([1])), [])
        XCTAssertEqual(Find.bytes("ll", in: data[5...]).map(\.target), [2])         // offsets count from the slice start
    }

    func testFindSelectsTheQueryWithinTheLine() {
        let text = "one\nTwo words here\nthree"
        XCTAssertEqual(TextPane.selection(for: Jump(target: 2, serial: 1, query: "words"), in: text), NSRange(location: 8, length: 5))
        XCTAssertEqual(TextPane.selection(for: Jump(target: 2, serial: 1, query: "WORDS"), in: text), NSRange(location: 8, length: 5))
        XCTAssertEqual(TextPane.selection(for: Jump(target: 2, serial: 1, query: "absent"), in: text), NSRange(location: 4, length: 14))
        XCTAssertEqual(TextPane.selection(for: Jump(target: 3, serial: 1), in: text), NSRange(location: 19, length: 5))
        XCTAssertEqual(TextPane.selection(for: Jump(target: 1, serial: 1, query: "three"), in: text), NSRange(location: 0, length: 3))   // only on its line
    }

    func testHexRowStart() {
        XCTAssertEqual(HexPane.rowStart(of: 0), 0)
        XCTAssertEqual(HexPane.rowStart(of: 31), 16)
        XCTAssertEqual(HexPane.rowStart(of: 32), 32)
        XCTAssertEqual(HexPane.rowStart(of: -3), 0)
    }

    /// Find runs after each pause in typing, so it has to be quick on a big file. Prints the time.
    func testFindSpeedOnAnEightMegabyteText() {
        let line = "The quick brown fox jumps over the lazy dog while the whale sings.\n"
        let text = String(repeating: line, count: 8_000_000 / line.utf8.count)
        let doc = AnyfileDocument(data: Data(text.utf8), name: "big.txt")
        for (query, expected) in [("whale", Find.limit), ("nothing like this", 0)] {
            let start = Date()
            let hits = Find.hits(for: query, in: doc)
            let seconds = Date().timeIntervalSince(start)
            print(String(format: "find '%@' in %.1f MB: %d hits in %.3f s", query, Double(doc.data.count) / 1e6, hits.count, seconds))
            XCTAssertEqual(hits.count, expected)
            XCTAssertLessThan(seconds, 0.25)    // measured 0.003 s and 0.021 s
        }
    }

    /// EPUB search asks the engine for each chapter in turn. Prints the time for a Moby-Dick-sized book.
    func testFindSpeedOnABookOf135Chapters() {
        let paragraph = String(repeating: "Call me Ishmael. Some years ago, never mind how long precisely. ", count: 160)
        var files: [(name: String, content: String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
        ]
        let ids = (1...135).map { "c\($0)" }
        files.append(("OPS/book.opf", "<package version=\"3.0\"><metadata/><manifest>"
            + ids.map { "<item id=\"\($0)\" href=\"\($0).xhtml\"/>" }.joined()
            + "</manifest><spine>" + ids.map { "<itemref idref=\"\($0)\"/>" }.joined() + "</spine></package>"))
        for (i, id) in ids.enumerated() {
            files.append(("OPS/\(id).xhtml", "<html><body><h1>Chapter \(i + 1)</h1><p>\(paragraph)\(i == 99 ? " the white whale " : "")</p></body></html>"))
        }
        let doc = AnyfileDocument(data: Fixtures.zip(files), name: "moby.epub")
        let start = Date()
        let hits = Find.hits(for: "white whale", in: doc)
        let seconds = Date().timeIntervalSince(start)
        print(String(format: "find in %d-chapter epub (%.1f MB): %d hits in %.3f s", ids.count, Double(doc.data.count) / 1e6, hits.count, seconds))
        XCTAssertEqual(hits.map(\.target), [100])
    }
}
