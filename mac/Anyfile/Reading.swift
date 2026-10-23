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

/// Where reading is in a text view, as a character, and back again.
enum ReadingPlace {
    /// The first character at the top of the visible part of the text.
    static func topCharacter(in tv: NSTextView) -> Int {
        guard let lm = tv.layoutManager, let tc = tv.textContainer, tv.textStorage?.length ?? 0 > 0 else { return 0 }
        // A point just inside the top-left of what is visible, in the text container's coordinates.
        let point = NSPoint(x: 2, y: tv.visibleRect.minY - tv.textContainerOrigin.y + 2)
        let glyph = lm.glyphIndex(for: point, in: tc)
        return lm.characterIndexForGlyph(at: glyph)
    }

    /// Scrolls so the line holding `character` is at the top.
    static func scroll(_ tv: NSTextView, toCharacter character: Int) {
        guard let lm = tv.layoutManager else { return }
        let length = tv.textStorage?.length ?? 0
        guard length > 0 else { return }
        let c = min(max(character, 0), length - 1)
        lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: c + 1))
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: c, length: 1), actualCharacterRange: nil)
        let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        tv.scroll(NSPoint(x: 0, y: max(0, line.minY + tv.textContainerOrigin.y - 2)))
    }
}

/// A text view that keeps its column centred and no wider than the reading measure, and turns
/// pages from the keyboard: the arrow keys, or Space, which scrolls and turns once the end is in view.
final class PaperTextView: NSTextView {
    var onTurn: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch (event.keyCode, plain) {
        case (124, true): onTurn?(1)                                       // →
        case (123, true): onTurn?(-1)                                      // ←
        case (49, true) where Self.atEnd(visibleRect, bounds): onTurn?(1)  // Space at the end of the chapter
        case (49, true): scrollPageDown(nil)                               // Space elsewhere: down a screen, as in Books
        default: super.keyDown(with: event)
        }
    }

    /// True when the bottom of the text is in view.
    static func atEnd(_ visible: NSRect, _ bounds: NSRect) -> Bool { visible.maxY >= bounds.maxY - 2 }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = ReadingStyle.sideInset(forWidth: newSize.width)
        if textContainerInset.width != inset { textContainerInset = NSSize(width: inset, height: 48) }
    }
}

enum Highlights {
    /// Paints every occurrence of each marked quote with the mark colour. Temporary attributes,
    /// so the highlight is drawn but never becomes part of the text.
    static func apply(_ quotes: [String], to tv: NSTextView) {
        guard let lm = tv.layoutManager else { return }
        let ns = tv.string as NSString
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ns.length))
        for quote in quotes where !quote.isEmpty {
            for r in ranges(of: quote, in: ns) {
                lm.addTemporaryAttribute(.backgroundColor, value: Theme.mark.withAlphaComponent(0.7), forCharacterRange: r)
            }
        }
    }

    static func ranges(of quote: String, in ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: quote, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = NSMaxRange(r)
        }
        return out
    }

    /// The 1-based line holding a UTF-16 offset.
    static func line(at location: Int, in ns: NSString) -> Int {
        var line = 1
        for i in 0..<min(location, ns.length) where ns.character(at: i) == 0x0A { line += 1 }
        return line
    }
}

/// AppKit reports selection and page changes even when the app made them itself, which happens
/// while SwiftUI is updating a view; writing SwiftUI state then is "modifying state during view
/// update". Reports go through here, so they arrive on the next turn of the run loop instead.
enum Later {
    static func report(_ deliver: @escaping () -> Void) { DispatchQueue.main.async(execute: deliver) }
}
