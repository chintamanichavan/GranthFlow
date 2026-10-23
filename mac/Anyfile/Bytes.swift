// Reading bytes: what a file's first bytes say it is, and how each byte is coloured in the hex view.
import AppKit

enum Signature {
    /// A plain sentence naming the file from its magic bytes, or nil when they mean nothing known.
    static func describe(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(16))
        func starts(_ m: [UInt8], at offset: Int = 0) -> Bool { b.count >= offset + m.count && Array(b[offset..<offset + m.count]) == m }
        if starts([0x7F, 0x45, 0x4C, 0x46]) { return "this is a Linux program" }
        if starts([0xCF, 0xFA, 0xED, 0xFE]) || starts([0xCE, 0xFA, 0xED, 0xFE]) || starts([0xFE, 0xED, 0xFA, 0xCF]) || starts([0xFE, 0xED, 0xFA, 0xCE]) {
            return "this is a Mac program"
        }
        if starts([0xCA, 0xFE, 0xBA, 0xBE]) { return "this is a Mac program for more than one kind of processor" }
        if starts([0x4D, 0x5A]) { return "this is a Windows program" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "this is a PNG image" }
        if starts([0xFF, 0xD8, 0xFF]) { return "this is a JPEG photo" }
        if starts(Array("GIF8".utf8)) { return "this is a GIF image" }
        if starts(Array("SQLite format 3".utf8)) { return "this is an SQLite database" }
        if starts([0x1F, 0x8B]) { return "this is gzip-compressed data" }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "this is a zip archive" }
        if starts(Array("%PDF".utf8)) { return "this is a PDF document" }
        if starts(Array("ftyp".utf8), at: 4) { return "this is a video or audio file (MP4 family)" }
        if starts(Array("bplist".utf8)) { return "this is a binary property list" }
        return nil
    }
}

enum ByteClass: Equatable {
    case zero, text, high, other

    init(_ b: UInt8) {
        switch b {
        case 0: self = .zero
        case 0x20..<0x7F: self = .text
        case 0xFF: self = .high
        default: self = .other
        }
    }
}

enum HexLayout {
    static let rowBytes = 16

    /// The character shown for a byte in the text column.
    static func glyph(_ b: UInt8) -> Character { (0x20..<0x7F).contains(b) ? Character(UnicodeScalar(b)) : "·" }

    /// The width of one character of the rows' 12-point mono type.
    static let characterWidth = ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width

    /// The byte in a row under a character column, in the hex or the text column; nil between bytes.
    /// A row is "00000000   " then 16 bytes of "xx " (an extra space after the eighth), then "  " and 16 glyphs.
    static func byte(atColumn c: Int) -> Int? {
        for i in 0..<rowBytes {
            let start = 11 + 3 * i + (i >= 8 ? 1 : 0)
            if c == start || c == start + 1 { return i }
        }
        let text = 11 + 3 * rowBytes + 1 + 2
        return (text..<(text + rowBytes)).contains(c) ? c - text : nil
    }

    /// The offsets of the rows that make up a page starting at `offset`.
    static func rows(from offset: Int, count: Int, total: Int) -> [Int] {
        let start = max(0, min(offset, total)) / rowBytes * rowBytes
        return Array(stride(from: start, to: min(total, start + count * rowBytes), by: rowBytes))
    }
}

/// Marks made on bytes: the bytes as hex pairs, so the mark reads the same anywhere it is shown.
enum ByteMark {
    /// At most this many bytes are spelled out in a mark; the length is kept in full in its place.
    static let shown = 64

    static func selection(of range: Range<Int>, in data: Data) -> Selection {
        let bytes = data[(data.startIndex + range.lowerBound)..<(data.startIndex + min(range.upperBound, range.lowerBound + shown))]
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ") + (range.count > shown ? " …" : "")
        let size = range.count == 1 ? "1 byte" : "\(range.count) bytes"
        return Selection(quote: hex, target: range.lowerBound, place: String(format: "0x%llx", range.lowerBound) + " · " + size)
    }

    /// How many bytes a mark covers: from its place when it says, else the hex pairs in its quote.
    static func length(of quote: String, place: String = "") -> Int {
        if let n = place.split(separator: "·").last?.split(separator: " ").first.flatMap({ Int($0) }) { return n }
        return quote.split(separator: " ").filter { $0.count == 2 && $0.allSatisfy(\.isHexDigit) }.count
    }
}
