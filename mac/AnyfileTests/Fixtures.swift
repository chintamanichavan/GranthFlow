// Small files the tests build on the fly; nothing is read from the repository.
import Foundation

enum Fixtures {
    static let tinyPdf = """
    %PDF-1.4
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 300 200] >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj
    4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
    5 0 obj << /Length 44 >>
    stream
    BT /F1 18 Tf 20 150 Td (Hello PDF World) Tj ET
    endstream
    endobj
    6 0 obj << /Title (Tiny Test) >> endobj
    trailer << /Root 1 0 R /Info 6 0 R >>
    """

    static let markdown = "# Title\n\nIntro with **bold**.\n\n## Status\n\nold body\n"
    static let text = "alpha\nbeta\ngamma\n"
    static let binary = Data([0x7f, 0x45, 0x4c, 0x46, 0x00, 0x01, 0x68, 0x65, 0x6c, 0x6c, 0x6f])

    /// A two-chapter EPUB. The first chapter is named by the contents file, the second by its own heading.
    static let epub: Data = zip([
        ("mimetype", "application/epub+zip"),
        ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
        ("OPS/book.opf", """
            <package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <metadata><dc:title>Tiny Book</dc:title><dc:creator>Tester</dc:creator></metadata>
            <manifest><item id="a" href="a.xhtml"/><item id="b" href="b.xhtml"/><item id="n" href="nav.xhtml" properties="nav"/></manifest>
            <spine><itemref idref="a"/><itemref idref="b"/></spine></package>
            """),
        ("OPS/a.xhtml", "<html><head><title>a</title></head><body><h1>First</h1><p>Hello   book &amp; reader.</p></body></html>"),
        ("OPS/b.xhtml", "<html><body><h1>Second Heading</h1><p>Closing words.</p></body></html>"),
        ("OPS/nav.xhtml", "<html><body><nav><ol><li><a href=\"a.xhtml\">Opening</a></li></ol></nav></body></html>"),
    ])

    /// An uncompressed zip written by hand, so the engine's reader is tested against bytes it did not produce.
    static func zip(_ files: [(name: String, content: String)]) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }
        var body: [UInt8] = [], directory: [UInt8] = []
        for file in files {
            let name = Array(file.name.utf8), content = Array(file.content.utf8)
            // version, flags, method 0 (stored), time, date 1980-01-01, crc, sizes, name length, extra length
            let fields = le16(10) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(Int(crc32(content)))
                + le32(content.count) + le32(content.count) + le16(name.count) + le16(0)
            directory += [0x50, 0x4B, 0x01, 0x02] + le16(20) + fields + le16(0) + le16(0) + le16(0) + le32(0) + le32(body.count) + name
            body += [0x50, 0x4B, 0x03, 0x04] + fields + name + content
        }
        let end = [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(files.count) + le16(files.count)
            + le32(directory.count) + le32(body.count) + le16(0)
        return Data(body + directory + end)
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }

    /// Writes contents to a fresh temp directory and returns the file URL.
    static func write(_ data: Data, as name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }
}
