// Markdown set as a page: headings, lists and code in reading type, every line tagged with its
// line in the source so a jump or a selection can be traced back.
import SwiftUI

extension NSAttributedString.Key {
    /// The 1-based line of the Markdown source a stretch of the preview came from.
    static let sourceLine = NSAttributedString.Key("anyfile.sourceLine")
}

enum MarkdownRenderer {
    /// Headings set large, lists with bullets, code in mono, inline bold, italic, code and links from
    /// Foundation's parser; reading type throughout. Fence lines are left out; every other source line
    /// becomes one line of the preview, tagged with its line number.
    static func render(_ source: String, language: String? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = Theme.readingFont(size: ReadingStyle.bodySize, language: language)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.35
        paragraph.paragraphSpacing = 4
        var inFence = false
        for (i, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let piece: NSMutableAttributedString
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            } else if inFence {
                piece = NSMutableAttributedString(string: line, attributes: [
                    .font: PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: Theme.paper.secondary])
            } else if let level = headingLevel(trimmed) {
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                let size: CGFloat = [30, 23, 19, 17, 15, 14][level - 1]
                piece = NSMutableAttributedString(string: text, attributes: [
                    .font: Theme.readingFont(size: size, weight: .semibold, language: language), .foregroundColor: Theme.paper.label])
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                piece = NSMutableAttributedString(string: "  •  ", attributes: [.font: body, .foregroundColor: Theme.paper.label])
                piece.append(inline(String(trimmed.dropFirst(2)), body: body))
            } else {
                piece = inline(line, body: body)
            }
            piece.append(NSAttributedString(string: "\n", attributes: [.font: body]))
            let all = NSRange(location: 0, length: piece.length)
            piece.addAttribute(.sourceLine, value: i + 1, range: all)
            piece.addAttribute(.paragraphStyle, value: paragraph, range: all)
            out.append(piece)
        }
        ReadingStyle.sizeDevanagari(in: out, language: language)
        return out
    }

    /// One line's inline Markdown, with bold, italic and code turned into fonts and links kept.
    static func inline(_ s: String, body: PlatformFont) -> NSMutableAttributedString {
        let parsed = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var font = body
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: body.pointSize * 0.88, weight: .regular)
            } else {
                font = font.adding(bold: intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized))
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.paper.label]
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: text, attributes: attributes))
        }
        return out
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " ? hashes : nil
    }

    /// The source line a character of the preview came from.
    static func sourceLine(at character: Int, in text: NSAttributedString) -> Int? {
        guard text.length > 0 else { return nil }
        return text.attribute(.sourceLine, at: min(max(character, 0), text.length - 1), effectiveRange: nil) as? Int
    }

    /// The first character of the preview that came from `line` or after it: where a heading's jump lands.
    static func character(forLine line: Int, in text: NSAttributedString) -> Int? {
        var found: Int?
        text.enumerateAttribute(.sourceLine, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            if let l = value as? Int, l >= line { found = range.location; stop.pointee = true }
        }
        return found
    }
}
