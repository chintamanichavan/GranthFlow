// How reading text is set: a centred column of serif type on paper, with the chapter's
// number and title above it, as in the design's reading window.
import AppKit

enum ReadingStyle {
    /// The widest the column grows; wider lines are hard to follow back to their start.
    static let measure: CGFloat = 560      // about 75 characters of 17-point New York
    static let bodySize: CGFloat = 17

    /// A chapter as it is shown: "CHAPTER n" and the title, centred, then the text.
    static func chapter(_ text: String, number: Int?, title: String?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let title = title?.trimmingCharacters(in: .whitespaces) ?? ""
        if let number {
            out.append(line("CHAPTER \(number)", font: .systemFont(ofSize: 11, weight: .semibold), color: Theme.paper.secondary,
                            align: .center, kern: 1.6, after: title.isEmpty ? 28 : 8))
        }
        if !title.isEmpty {
            out.append(line(title, font: Theme.readingFont(size: 30), color: Theme.paper.label, align: .center, after: 30))
        }
        out.append(body(dropLeadingTitle(text, title: title)))
        return out
    }

    /// Body text: serif, generous leading, a little space between paragraphs.
    static func body(_ text: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.45
        p.paragraphSpacing = 10
        return NSAttributedString(string: text, attributes: [
            .font: Theme.readingFont(size: bodySize), .foregroundColor: Theme.paper.label, .paragraphStyle: p,
        ])
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
    static func sideInset(forWidth width: CGFloat) -> CGFloat { max(32, (width - measure) / 2) }

    private static func line(_ s: String, font: NSFont, color: NSColor, align: NSTextAlignment, kern: CGFloat = 0, after: CGFloat) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.paragraphSpacing = after
        return NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p, .kern: kern])
    }
}

/// A text view that keeps its column centred and no wider than the reading measure.
final class PaperTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = ReadingStyle.sideInset(forWidth: newSize.width)
        if textContainerInset.width != inset { textContainerInset = NSSize(width: inset, height: 48) }
    }
}
