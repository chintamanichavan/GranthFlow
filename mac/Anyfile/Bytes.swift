// Reading bytes: what a file's first bytes say it is, and how each byte is coloured in the hex view.
import Foundation

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

    /// The offsets of the rows that make up a page starting at `offset`.
    static func rows(from offset: Int, count: Int, total: Int) -> [Int] {
        let start = max(0, min(offset, total)) / rowBytes * rowBytes
        return Array(stride(from: start, to: min(total, start + count * rowBytes), by: rowBytes))
    }
}
