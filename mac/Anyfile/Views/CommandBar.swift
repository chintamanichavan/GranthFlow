// Pick a command, type its arguments, run it, read the output. Everything the CLI can do.
import SwiftUI

struct CommandBar: View {
    @Binding var document: AnyfileDocument
    @Binding var lastResult: RunResult?
    let onApply: (RunResult) -> Void

    @State private var selected: String = "info"
    @State private var argsText: String = ""

    private var commands: [CommandInfo] { Engine.commands(for: document.kind) }
    private var selectedInfo: CommandInfo? { commands.first { $0.name == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Command", selection: $selected) {
                    ForEach(commands) { c in Text(c.name).tag(c.name) }
                }
                .frame(width: 200)
                .accessibilityIdentifier("commandPicker")

                TextField(selectedInfo?.usage.isEmpty == false ? selectedInfo!.usage : "no arguments", text: $argsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(run)
                    .accessibilityIdentifier("argsField")

                Button("Run", action: run)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("runButton")
            }
            if let info = selectedInfo {
                Text(info.help).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(lastResult?.succeeded == false ? Color.red : Color.primary)
                    .accessibilityIdentifier("outputText")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))
        }
        .padding(10)
        .onChange(of: document.kind) { _, _ in
            if !commands.contains(where: { $0.name == selected }) { selected = "info" }
        }
    }

    private var outputText: String {
        guard let r = lastResult else { return "Choose a command and press Run. Output appears here." }
        var s = r.output
        if !r.errorText.isEmpty { s += (s.isEmpty ? "" : "\n") + r.errorText }
        return s.isEmpty ? "(no output)" : s
    }

    private func run() {
        let result = Engine.run(selected, args: Engine.splitArguments(argsText), on: document.data, name: document.name, kind: document.kind)
        lastResult = result
        onApply(result)
    }
}
