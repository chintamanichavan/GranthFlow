// Every file has a face. A cover is made from the file's own contents: a book's own cover
// picture (or its title and author on cloth when it has none), a PDF's first page, a note's
// first lines, or, for a program, a map of its bytes.
import Foundation
import ImageIO
import PDFKit

enum CoverArt {
    case book(title: [String], author: String, cloth: Int)     // cloth: index into Cover.cloths
    /// A book that comes with its own cover. The title and author are kept for the caption.
    case picture(NSImage, title: String, author: String)
    case page(thumbnail: NSImage?)
    case note(heading: String, rows: [String])
    case text(rows: [String])
    case bytes(cells: [UInt8], cols: Int, rows: Int)          // cells: indexes into Theme.bytes
}

enum Cover {
    /// Book cloths: deep colours that light ink reads well on. The first is Moby-Dick's in the design.
    static let cloths = ["#1B2F63", "#6E1E24", "#1F4A3A", "#7A4E16", "#4A2A5E", "#2E3A48"]
    static let ink = "#F1E4C6"
    static let mapCols = 30, mapRows = 42

    static func art(for data: Data, name: String, kind: String) -> CoverArt {
        switch kind {
        case "epub":
            let meta = Engine.run("meta", args: [], on: data, name: name, kind: kind).output
            let title = field("title", in: meta) ?? stem(name)
            let author = field("creator", in: meta) ?? ""
            if let picture = bookCover(data, name: name) { return .picture(picture, title: title, author: author) }
            return .book(title: titleLines(title), author: author, cloth: Int(stableHash(title) % UInt64(cloths.count)))
        case "pdf":
            return .page(thumbnail: PDFDocument(data: data)?.page(at: 0).map(pageImage))
        case "markdown":
            let lines = String(decoding: data.prefix(16_384), as: UTF8.self).split(separator: "\n").map(String.init)
            let headingIndex = lines.firstIndex { MarkdownRenderer.headingLevel($0.trimmingCharacters(in: .whitespaces)) == 1 }
            let heading = headingIndex.map { lines[$0].drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) } ?? stem(name)
            let rest = lines.enumerated().filter { $0.offset != headingIndex }.map(\.element)
            return .note(heading: heading, rows: Array(rest.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(8)))
        case "text":
            let lines = String(decoding: data.prefix(4096), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            return .text(rows: lines.prefix(9).map { String($0.prefix(28)) })
        default:
            return .bytes(cells: byteMap(data), cols: mapCols, rows: mapRows)
        }
    }

    /// Covers are drawn at most this tall: a shelf cover is about 210 points, twice that on Retina.
    static let pictureHeight = 600

    /// The book's own cover image, read at shelf size. A 2.4 MB JPEG is decoded straight to a
    /// 600-pixel image instead of being held at full size for every book on the shelf.
    static func bookCover(_ data: Data, name: String) -> NSImage? {
        let path = Engine.run("cover", args: [], on: data, name: name, kind: "epub")
        guard path.succeeded, !path.output.isEmpty else { return nil }
        let bytes = Engine.run("cat", args: [path.output.trimmingCharacters(in: .newlines)], on: data, name: name, kind: "epub")
        guard bytes.succeeded, let source = CGImageSourceCreateWithData(bytes.outputData as CFData, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: pictureHeight] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The picture's average colour as "#RRGGBB", so the hero behind a cover can take its colour.
    static func averageHex(_ image: NSImage) -> String? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))       // the scaler averages every pixel into one
        NSGraphicsContext.restoreGraphicsState()
        guard let c = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    /// The page at the cover's width, from the top, on white: a landscape page shows its upper part
    /// as a page would, instead of floating small in the middle of the cover.
    static func pageImage(_ page: PDFPage) -> NSImage {
        let size = NSSize(width: 240, height: 336)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let box = page.bounds(for: .cropBox)
            guard box.width > 0, let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let scale = size.width / box.width
            ctx.translateBy(x: 0, y: size.height - box.height * scale)
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .cropBox, to: ctx)
            return true
        }
    }

    /// One cell per block of the file, row by row. Files smaller than the grid fill only the top cells.
    static func byteMap(_ data: Data, cells: Int = mapCols * mapRows) -> [UInt8] {
        guard !data.isEmpty else { return [] }
        let block = max(1, (data.count + cells - 1) / cells)
        return data.withUnsafeBytes { raw -> [UInt8] in
            let bytes = raw.bindMemory(to: UInt8.self)
            return stride(from: 0, to: bytes.count, by: block).map { start in
                classify(bytes[start..<min(start + block, bytes.count)])
            }
        }
    }

    /// The colour of one block: 0 empty, 4 text, and 1-3, 5, 6 by rising entropy (6 is compressed or random).
    /// Long blocks are sampled at up to 4096 evenly spaced bytes; that keeps a 50 MB file quick.
    static func classify(_ block: Slice<UnsafeBufferPointer<UInt8>>) -> UInt8 {
        let step = max(1, block.count / 4096)
        var counts = [Int](repeating: 0, count: 256)
        var n = 0, zeros = 0, printable = 0
        var i = block.startIndex
        while i < block.endIndex {
            let b = block[i]
            counts[Int(b)] += 1
            n += 1
            if b == 0 { zeros += 1 }
            if (b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D || b == 0x09 { printable += 1 }
            i += step
        }
        if zeros * 10 >= n * 9 { return 0 }
        if printable * 100 >= n * 85 { return 4 }
        var entropy = 0.0, seen = 0
        for c in counts where c > 0 {
            let p = Double(c) / Double(n)
            entropy -= p * log2(p)
            seen += 1
        }
        // Short samples under-count entropy (512 random bytes measure about 7.6 bits, not 8);
        // the Miller–Madow correction adds back the expected shortfall.
        entropy = min(8, entropy + Double(seen - 1) / (2 * Double(n) * log(2)))
        // A block of n bytes can show at most log2(n) bits, so small blocks are judged against that.
        let fraction = entropy / min(8, log2(Double(max(n, 2))))
        switch fraction {
        case ..<0.25: return 1
        case ..<0.55: return 2
        case ..<0.8: return 3
        case ..<0.95: return 5
        default: return 6
        }
    }

    /// FNV-1a. String.hashValue changes between launches, and a cover must not.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    /// A title broken into at most three short lines, as on the spine-side of a cloth cover.
    static func titleLines(_ title: String, width: Int = 12) -> [String] {
        var lines: [String] = []
        for word in title.split(separator: " ").map(String.init) {
            if let last = lines.last, last.count + 1 + word.count <= width { lines[lines.count - 1] = last + " " + word }
            else { lines.append(word) }
        }
        if lines.count > 3 { lines = Array(lines.prefix(3)); lines[2] += "…" }
        return lines.isEmpty ? [title] : lines
    }

    /// "key: value" from the engine's `meta` output.
    static func field(_ key: String, in meta: String) -> String? {
        for line in meta.split(separator: "\n") where line.lowercased().hasPrefix(key + ":") {
            let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }
}
