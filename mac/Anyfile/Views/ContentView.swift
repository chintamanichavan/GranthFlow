// One window per document: the content pane for its kind, with the action bar floating over it.
import SwiftUI

struct ContentView: View {
    @Binding var document: AnyfileDocument
    @Environment(\.undoManager) private var undoManager
    @State private var active: DocumentAction?

    var body: some View {
        pane
            .frame(minWidth: 640, minHeight: 480)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if let panel = activePanel {
                        panel
                            .frame(maxWidth: 620)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ActionBar(active: $active)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .animation(.snappy(duration: 0.2), value: active)
            }
            .onExitCommand { active = nil }
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

    private var activePanel: AnyView? {
        switch active {
        case .info:
            AnyView(CommandPanel(title: "Info", commands: CommandRole.infoCommands(for: document.kind),
                                 document: $document, runsImmediately: true, onApply: apply).id("info-\(document.kind)"))
        case .edit:
            AnyView(CommandPanel(title: "Edit", commands: CommandRole.editCommands(for: document.kind),
                                 document: $document, runsImmediately: false, onApply: apply).id("edit-\(document.kind)"))
        default:
            nil
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
