// One window per document: the content pane for its kind on top, the command bar below.
import SwiftUI

struct ContentView: View {
    @Binding var document: AnyfileDocument
    @Environment(\.undoManager) private var undoManager
    @State private var lastResult: RunResult?

    var body: some View {
        VSplitView {
            pane
                .frame(minHeight: 240)
            CommandBar(document: $document, lastResult: $lastResult, onApply: apply)
                .frame(minHeight: 150, idealHeight: 200)
        }
        .frame(minWidth: 640, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("\(document.kind)  ·  \(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kindLabel")
            }
        }
    }

    @ViewBuilder private var pane: some View {
        switch document.kind {
        case "pdf": PdfPane(document: document)
        case "epub": EpubPane(document: document)
        case "markdown": MarkdownPane(document: $document)
        case "text": TextPane(text: $document.text)
        default: HexPane(document: document)
        }
    }

    /// Replaces the document bytes with a command's result, with undo.
    private func apply(_ result: RunResult) {
        guard let changed = result.changedData else { return }
        let before = document.data
        document.data = changed
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            self.document.data = before
        }
        undoManager?.setActionName("Run \(result.output.split(separator: " ").first ?? "command")")
    }
}

/// NSUndoManager needs an object target; the real state lives in the SwiftUI binding.
final class UndoProxy: NSObject { static let shared = UndoProxy() }
