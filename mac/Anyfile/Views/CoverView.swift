// Draws a cover. Everything is laid out on a 120 × 168 card and scaled to the size given,
// so a cover on a shelf and a cover in the hero are the same drawing.
import SwiftUI

struct CoverView: View {
    let art: CoverArt
    static let base = CGSize(width: 120, height: 168)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.base.width, geo.size.height / Self.base.height)
            card
                .frame(width: Self.base.width, height: Self.base.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.base.width * scale, height: Self.base.height * scale, alignment: .topLeading)
        }
        .aspectRatio(Self.base.width / Self.base.height, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    @ViewBuilder private var card: some View {
        switch art {
        case let .book(title, author, cloth):
            BookCover(title: title, author: author, cloth: Color(nsColor: NSColor(hex: Cover.cloths[cloth])!),
                      ink: Color(nsColor: NSColor(hex: Cover.ink)!))
        case let .picture(image, _, _):
            PictureCover(image: image)
        case let .page(thumbnail):
            PageCover(thumbnail: thumbnail)
        case let .note(heading, rows):
            NoteCover(heading: heading, rows: rows)
        case let .text(rows):
            TextCover(rows: rows)
        case let .bytes(cells, cols, rows):
            ByteCover(cells: cells, cols: cols, rows: rows)
        }
    }
}

private struct BookCover: View {
    let title: [String], author: String, cloth: Color, ink: Color

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).fill(cloth)
            HStack(spacing: 0) {                                   // the shade of the spine
                Rectangle().fill(.black.opacity(0.16)).frame(width: 5)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 1).strokeBorder(ink.opacity(0.55), lineWidth: 0.7).padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 8))
            VStack(spacing: 2) {
                ForEach(Array(title.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 15, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Ornament().padding(.top, 14)
                Spacer()
                Text(author.uppercased()).font(.system(size: 6, weight: .medium, design: .serif)).kerning(0.6).lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(EdgeInsets(top: 24, leading: 16, bottom: 20, trailing: 12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// Three diamonds over a rule, as on the design's cloth covers.
private struct Ornament: View {
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                ForEach([3.5, 6.0, 3.5], id: \.self) { r in
                    Diamond().frame(width: r * 1.4, height: r * 2)
                }
            }
            Rectangle().frame(width: 44, height: 0.6)
        }
        .opacity(0.9)
    }
}

private struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
        }
    }
}

/// A book's own cover picture, filling the card, with the spine's shade down the left edge.
private struct PictureCover: View {
    let image: NSImage

    var body: some View {
        ZStack(alignment: .leading) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: CoverView.base.width, height: CoverView.base.height)
            LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct PageCover: View {
    let thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(.white)
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                VStack(alignment: .leading, spacing: 5) {                // an unreadable PDF still looks like a page
                    ForEach(0..<9, id: \.self) { k in
                        Capsule().fill(Color(white: 0.86)).frame(width: k % 4 == 3 ? 50 : 88, height: 2)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private struct NoteCover: View {
    let heading: String, rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(heading).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                .foregroundStyle(Color(nsColor: NSColor(hex: "#32291C")!))
                .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.hasPrefix("#") {
                    Text(row.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 7.5, weight: .semibold))
                } else if row.hasPrefix("- ") || row.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Circle().frame(width: 2.5, height: 2.5).offset(y: -1.5)
                        Text(row.dropFirst(2)).font(.system(size: 6.5))
                    }
                } else {
                    Text(row).font(.system(size: 6.5)).foregroundStyle(Color(nsColor: NSColor(hex: "#5E513E")!))
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .foregroundStyle(Color(nsColor: NSColor(hex: "#32291C")!))
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: NSColor(hex: "#FFFBEF")!)))
    }
}

private struct TextCover: View {
    let rows: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(rows.indices, id: \.self) { k in
                    Text("\(k + 1)").frame(height: 14)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 6, design: .monospaced))
            .foregroundStyle(Color(white: 0.56))
            .frame(width: 18)
            .padding(.top, 10)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: NSColor(hex: "#F3F3F6")!))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row.isEmpty ? " " : row).frame(height: 14)
                        .foregroundStyle(row.hasPrefix("#") ? Color(nsColor: Theme.library.accent) : Color(white: 0.11))
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .padding(.top, 10)
            .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private struct ByteCover: View {
    let cells: [UInt8], cols: Int, rows: Int

    var body: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4), with: .color(Color(nsColor: Theme.bytes[0])))
            let inner = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let w = inner.width / CGFloat(cols), h = inner.height / CGFloat(rows)
            let colours = Theme.bytes.map { Color(nsColor: $0) }
            for (i, v) in cells.enumerated() where v != 0 {
                let rect = CGRect(x: inner.minX + CGFloat(i % cols) * w, y: inner.minY + CGFloat(i / cols) * h, width: w, height: h)
                context.fill(Path(rect.insetBy(dx: 0.15, dy: 0.15)), with: .color(colours[Int(v)]))
            }
        }
    }
}
