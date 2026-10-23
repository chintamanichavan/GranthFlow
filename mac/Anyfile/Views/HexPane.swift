// Bytes on the night ground of a program's cover: a line saying what the file is, rows of hex
// coloured by what each byte is, and down the right a map of the whole file to move through it.
import SwiftUI

struct HexPane: View {
    let document: AnyfileDocument
    /// A byte offset from Find.
    var jump: Jump? = nil
    /// Marks in this file, painted in their colours.
    var marks: [Mark] = []
    var onSelect: (Selection?) -> Void = { _ in }
    @State private var offset: Int = 0
    /// Bytes chosen by clicking, and Shift-clicking to extend; Mark keeps them.
    @State private var selection: Range<Int>?
    @State private var anchor: Int?
    @State private var jumpText: String = "0x0"
    /// Rows drawn at a time; the strip and the offset field move the window over the file.
    private let pageRows = 256

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(rows, id: \.self) { row in
                                HexRow(data: document.data, offset: row, highlight: highlighted, paints: paints) { byte, extend in
                                    choose(byte, extend: extend)
                                }
                                .id(row)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("hexText")
                    }
                    .onChange(of: offset) { _, new in proxy.scrollTo(Self.rowStart(of: new), anchor: .top) }
                }
            }
            ByteStrip(data: document.data, offset: offset, shown: pageRows * HexLayout.rowBytes) { go(to: $0) }
                .frame(width: 30)
                .padding(.vertical, 14)
                .padding(.trailing, 12)
        }
        .background(Color(nsColor: Theme.night.window))
        .foregroundStyle(Color(nsColor: Theme.night.label))
        .onChange(of: jump) { _, jump in
            if let jump { go(to: jump.target) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: Theme.mark)).frame(width: 3, height: 18)
            Text(Signature.describe(document.data).map { "File signature: \($0)." } ?? "No known signature: these are raw bytes.")
                .font(.callout)
                .accessibilityIdentifier("hexSignature")
            Spacer()
            TextField("0x0", text: $jumpText)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 90)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(nsColor: Theme.night.hairline), in: RoundedRectangle(cornerRadius: 6))
                .onSubmit(jumpToTypedOffset)
                .accessibilityIdentifier("hexOffsetField")
            Text("of \(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))")
                .font(.caption).foregroundStyle(Color(nsColor: Theme.night.secondary))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    /// The page of rows around the current offset.
    private var rows: [Int] {
        let start = max(0, Self.rowStart(of: offset) - (pageRows / 4) * HexLayout.rowBytes)
        return HexLayout.rows(from: start, count: pageRows, total: document.data.count)
    }

    /// Marks in their colours, then the selection on top.
    private var paints: [BytePaint] {
        var out = marks.compactMap { m -> BytePaint? in
            let n = ByteMark.length(of: m.quote, place: m.place)
            return n > 0 ? BytePaint(range: m.target..<(m.target + n), colour: m.colour.paint) : nil
        }
        if let selection { out.append(BytePaint(range: selection, colour: .selectedContentBackgroundColor)) }
        return out
    }

    /// A click picks a byte; a Shift-click extends the selection from the first byte picked.
    private func choose(_ byte: Int?, extend: Bool) {
        guard let byte, byte < document.data.count else {
            selection = nil
            anchor = nil
            return onSelect(nil)
        }
        if extend, let anchor {
            selection = min(anchor, byte)..<(max(anchor, byte) + 1)
        } else {
            anchor = byte
            selection = byte..<(byte + 1)
        }
        if let selection { onSelect(ByteMark.selection(of: selection, in: document.data)) }
    }

    /// The bytes Find matched, painted like a mark.
    private var highlighted: Range<Int>? {
        guard let jump, let q = jump.query else { return nil }
        let length = Find.hexBytes(q)?.count ?? q.utf8.count
        return jump.target..<(jump.target + length)
    }

    /// The start of the 16-byte row holding an offset, so the match is on the first row shown.
    static func rowStart(of offset: Int) -> Int { max(0, offset) / 16 * 16 }

    private func go(to target: Int) {
        offset = max(0, min(target, max(0, document.data.count - 1)))
        jumpText = String(format: "0x%llx", offset)
    }

    private func jumpToTypedOffset() {
        let s = jumpText.trimmingCharacters(in: .whitespaces)
        let v = s.lowercased().hasPrefix("0x") ? Int(s.dropFirst(2), radix: 16) : Int(s)
        if let v, v >= 0, v < max(1, document.data.count) { go(to: v) }
    }
}

/// A run of bytes painted in a colour: a mark, or the selection.
struct BytePaint: Equatable {
    let range: Range<Int>
    let colour: NSColor
}

struct HexRow: View {
    let data: Data
    let offset: Int
    let highlight: Range<Int>?
    var paints: [BytePaint] = []
    /// Called with the byte clicked (nil for a click between bytes) and whether Shift was down.
    var tap: ((Int?, Bool) -> Void)? = nil

    var body: some View {
        Text(line).font(.system(size: 12, design: .monospaced))
            .onTapGesture(coordinateSpace: .local) { point in
                let column = Int(point.x / HexLayout.characterWidth)
                let shift = NSEvent.modifierFlags.contains(.shift)
                tap?(HexLayout.byte(atColumn: column).map { offset + $0 }, shift)
            }
    }

    /// The paint over a byte: Find's match, else the last paint that covers it.
    private func paint(at index: Int) -> NSColor? {
        if let highlight, highlight.contains(index) { return Theme.mark }
        return paints.last { $0.range.contains(index) }?.colour
    }

    var line: AttributedString {
        let end = min(offset + HexLayout.rowBytes, data.count)
        let bytes = data[data.startIndex + offset ..< data.startIndex + end]
        var out = AttributedString(String(format: "%08llx   ", offset))
        out.foregroundColor = Color(nsColor: Theme.night.tertiary)
        var text = AttributedString("  ")
        for (i, b) in bytes.enumerated() {
            var hex = AttributedString(String(format: "%02x", b) + (i == 7 ? "  " : " "))
            var glyph = AttributedString(String(HexLayout.glyph(b)))
            let colour = Self.colour(ByteClass(b))
            hex.foregroundColor = colour
            glyph.foregroundColor = colour
            if let paint = paint(at: offset + i) {
                hex.backgroundColor = Color(nsColor: paint).opacity(0.85)
                hex.foregroundColor = Color(nsColor: Theme.night.window)
                glyph.backgroundColor = Color(nsColor: paint).opacity(0.85)
                glyph.foregroundColor = Color(nsColor: Theme.night.window)
            }
            out += hex
            text += glyph
        }
        out += AttributedString(String(repeating: "   ", count: HexLayout.rowBytes - bytes.count) + (bytes.count <= 8 ? " " : ""))
        return out + text
    }

    static func colour(_ c: ByteClass) -> Color {
        switch c {
        case .zero: Color(nsColor: Theme.night.tertiary)
        case .text: Color(nsColor: Theme.bytes[4])
        case .high: Color(nsColor: Theme.bytes[5])
        case .other: Color(nsColor: Theme.bytes[3])
        }
    }
}

/// The whole file as a column of colour, with the part on show outlined. Click to go there.
private struct ByteStrip: View {
    let data: Data
    let offset: Int
    let shown: Int
    let go: (Int) -> Void
    @State private var cells: [UInt8] = []

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !cells.isEmpty else { return }
                let h = size.height / CGFloat(cells.count)
                for (i, v) in cells.enumerated() {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(i) * h, width: size.width, height: h + 0.5)),
                                 with: .color(Color(nsColor: Theme.bytes[Int(v)])))
                }
                let total = CGFloat(max(1, data.count))
                let top = CGFloat(offset) / total * size.height
                let height = max(4, CGFloat(shown) / total * size.height)
                context.stroke(Path(roundedRect: CGRect(x: 1, y: top, width: size.width - 2, height: min(height, size.height - top)), cornerRadius: 3),
                               with: .color(.white), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { point in go(Int(point.y / max(1, geo.size.height) * CGFloat(data.count))) }
            .help("A map of the whole file. Click to go there.")
            .accessibilityIdentifier("byteStrip")
        }
        .task(id: data.count) {
            let d = data
            cells = await Task.detached(priority: .utility) { Cover.byteMap(d, cells: 160) }.value
        }
    }
}
