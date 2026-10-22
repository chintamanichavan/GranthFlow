// Markdown: edit the source, or read a styled preview built from the engine's outline.
import SwiftUI

struct MarkdownPane: View {
    @Binding var document: AnyfileDocument
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
            Divider()
            if showPreview {
                ScrollView {
                    Text(MarkdownRenderer.render(document.text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .accessibilityIdentifier("markdownPreview")
                }
            } else {
                TextPane(text: $document.text)
            }
        }
    }
}

enum MarkdownRenderer {
    /// Headings get size and weight; everything else gets inline styling from Foundation's parser.
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
                piece.font = .system(.body, design: .monospaced)
                piece.foregroundColor = .secondary
            } else if let level = headingLevel(trimmed) {
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                piece = AttributedString(text)
                piece.font = .system(size: [26, 21, 18, 16, 14, 13][level - 1], weight: .semibold)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                piece = AttributedString("  •  ") + inline(String(trimmed.dropFirst(2)))
            } else {
                piece = inline(line)
            }
            out += piece
            out += AttributedString("\n")
        }
        return out
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
