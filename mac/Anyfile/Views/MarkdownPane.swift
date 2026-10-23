// Markdown: edit the source, or read a styled preview built from the engine's outline.
import SwiftUI

struct MarkdownPane: View {
    @Binding var document: AnyfileDocument
    /// A heading's line number from Contents, followed in both modes.
    var jump: Jump? = nil
    var marks: [Paint] = []
    var onSelect: (Selection?) -> Void = { _ in }
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showPreview) {
                Text("Edit").tag(false)
                Text("Preview").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .padding(6)
            .accessibilityIdentifier("markdownMode")
            .onChange(of: showPreview) { _, preview in
                if preview { onSelect(nil) }                // the preview's text cannot report a selection
            }
            Divider()
            if showPreview {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(MarkdownRenderer.sections(document.text), id: \.line) { section in
                                Text(section.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(section.line)
                            }
                        }
                        .frame(maxWidth: ReadingStyle.measure)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("markdownPreview")
                    }
                    .background(Color(nsColor: Theme.paper.window))
                    .foregroundStyle(Color(nsColor: Theme.paper.label))
                    .onChange(of: jump) { _, jump in
                        if let jump { withAnimation { proxy.scrollTo(jump.target, anchor: .top) } }
                    }
                }
            } else {
                TextPane(text: $document.text, jump: jump, marks: marks, onSelect: onSelect)
            }
        }
    }
}

enum MarkdownRenderer {
    /// Headings get size and weight; everything else gets inline styling from Foundation's parser.
    /// Reading type, as in EPUB chapters.
    static let body = Font(Theme.readingFont(size: ReadingStyle.bodySize) as CTFont)

    static func render(_ source: String) -> AttributedString {
        var out = AttributedString()
        var inFence = false
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var piece: AttributedString
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            } else if inFence {
                piece = AttributedString(line)
                piece.font = .system(size: 13, design: .monospaced)
                piece.foregroundColor = Color(nsColor: Theme.paper.secondary)
            } else if let level = headingLevel(trimmed) {
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                piece = AttributedString(text)
                piece.font = Font(Theme.readingFont(size: [30, 23, 19, 17, 15, 14][level - 1], weight: .semibold) as CTFont)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                piece = AttributedString("  •  ") + inline(String(trimmed.dropFirst(2)))
                piece.font = body          // bold, italic and code come from the inline intents
            } else {
                piece = inline(line)
                piece.font = body          // bold, italic and code come from the inline intents
            }
            out += piece
            out += AttributedString("\n")
        }
        return out
    }

    /// The source split before each heading outside a code fence, each piece rendered, keyed by the
    /// 1-based line it starts on. Contents targets the same line numbers, so the preview can scroll there.
    static func sections(_ source: String) -> [(line: Int, text: AttributedString)] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var starts = [0]
        var inFence = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            else if !inFence, i > 0, headingLevel(trimmed) != nil { starts.append(i) }
        }
        return starts.enumerated().map { n, start in
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            return (start + 1, render(lines[start..<end].joined(separator: "\n")))
        }
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " ? hashes : nil
    }

    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
