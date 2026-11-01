// How reading text is set: a centred column of serif type on paper, with the chapter's
// number and title above it, as in the design's reading window.
import SwiftUI

enum ReadingStyle {
    /// The widest the column grows; wider lines are hard to follow back to their start.
    static let measure: CGFloat = 560      // about 75 characters of 17-point New York
    static let bodySize: CGFloat = 17

    /// A chapter as it is shown: "CHAPTER n" and the title, centred, then the text.
    static func chapter(_ text: String, number: Int?, title: String?, language: String? = nil,
                        settings: ReadingSettings = ReadingSettings()) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let title = title?.trimmingCharacters(in: .whitespaces) ?? ""
        let scale = CGFloat(settings.size) / bodySize               // the label and title grow with the text
        let palette = settings.palette
        if let number {
            out.append(line("CHAPTER \(number)", font: .systemFont(ofSize: max(10, 11 * scale), weight: .semibold), color: palette.secondary,
                            align: .center, kern: 1.6, after: (title.isEmpty ? 28 : 8) * scale))
        }
        if !title.isEmpty {
            out.append(line(title, font: Theme.readingFont(size: 30 * scale, language: language), color: palette.label,
                            align: .center, after: 30 * scale))
        }
        out.append(body(dropLeadingTitle(text, title: title), language: language, settings: settings))
        sizeDevanagari(in: out, language: language)
        return out
    }

    /// Body text: serif, generous leading, a little space between paragraphs.
    static func body(_ text: String, language: String? = nil, settings: ReadingSettings = ReadingSettings()) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = settings.lineHeight
        p.paragraphSpacing = 10 * CGFloat(settings.size) / bodySize
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: Theme.readingFont(size: CGFloat(settings.size), language: language), .foregroundColor: settings.palette.label,
            .paragraphStyle: p,
        ])
        sizeDevanagari(in: out, language: language)
        return out
    }

    /// Gives each run of Devanagari its own book face, a little larger than the Latin around it,
    /// at the size and weight of the text it sits in. Joiners stay inside the run, so conjuncts hold.
    static func sizeDevanagari(in text: NSMutableAttributedString, language: String?) {
        let ns = text.string as NSString
        let runs = try! NSRegularExpression(pattern: "[\\u0900-\\u097F\\uA8E0-\\uA8FF\\u1CD0-\\u1CFF\\u200C\\u200D]+")
        for match in runs.matches(in: text.string, range: NSRange(location: 0, length: ns.length)) {
            guard let base = text.attribute(.font, at: match.range.location, effectiveRange: nil) as? PlatformFont else { continue }
            let bold = base.isBold
            text.addAttribute(.font, value: Theme.devanagariFont(size: base.pointSize, weight: bold ? .bold : .regular, language: language),
                              range: match.range)
        }
    }

    /// Chapters usually begin with their own heading; it is already shown as the title.
    static func dropLeadingTitle(_ text: String, title: String) -> String {
        guard !title.isEmpty else { return text }
        let rest = text[(text.firstIndex { !$0.isWhitespace } ?? text.endIndex)...]
        let end = rest.firstIndex(of: "\n") ?? rest.endIndex
        guard rest[..<end].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(title) == .orderedSame else { return text }
        return String(rest[end...].drop(while: \.isNewline))
    }

    /// The side inset that keeps the column at most `measure` wide and at least 32 points from the edge.
    static func sideInset(forWidth width: CGFloat, measure: CGFloat = measure) -> CGFloat { max(32, (width - measure) / 2) }

    private static func line(_ s: String, font: PlatformFont, color: PlatformColor, align: NSTextAlignment, kern: CGFloat = 0, after: CGFloat) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.paragraphSpacing = after
        return NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p, .kern: kern])
    }
}
