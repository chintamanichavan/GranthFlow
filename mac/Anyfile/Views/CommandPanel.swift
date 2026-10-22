// A card above the action bar: pick a command, type its arguments, run it, read the output.
// Info shows the commands that read; Edit shows the ones that change the file.
import SwiftUI

struct CommandPanel: View {
    let title: String
    let commands: [CommandInfo]
    @Binding var document: AnyfileDocument
    /// Info runs a command as soon as it is picked when it needs no arguments; Edit never does.
    let runsImmediately: Bool
    let onApply: (RunResult) -> Void

    @State private var selected: String = ""
    @State private var argsText: String = ""
    @State private var lastResult: RunResult?

    private var selectedInfo: CommandInfo? { commands.first { $0.name == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                Picker("Command", selection: $selected) {
                    ForEach(commands) { c in Text(c.name).tag(c.name) }
                }
                .labelsHidden()
                .frame(width: 170)
                .accessibilityIdentifier("commandPicker")

                TextField(selectedInfo?.usage.isEmpty == false ? selectedInfo!.usage : "no arguments", text: $argsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(selectedInfo?.usage.isEmpty ?? true)
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
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(lastResult?.succeeded == false ? Color.red : Color.primary)
                    .padding(8)
                    .accessibilityIdentifier("outputText")
            }
            .frame(minHeight: 80, maxHeight: 220)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .onAppear {
            if selectedInfo == nil { selected = commands.first?.name ?? "" }
            runIfImmediate()
        }
        .onChange(of: selected) { _, _ in
            argsText = ""
            lastResult = nil
            runIfImmediate()
        }
    }

    private var outputText: String {
        guard let r = lastResult else {
            return runsImmediately ? "Type the arguments and press Run." : "Nothing changes until you press Run. Undo with ⌘Z."
        }
        var s = r.output
        if !r.errorText.isEmpty { s += (s.isEmpty ? "" : "\n") + r.errorText }
        return s.isEmpty ? "(no output)" : s
    }

    private func runIfImmediate() {
        if runsImmediately, selectedInfo?.usage.isEmpty == true { run() }
    }

    private func run() {
        guard selectedInfo != nil else { return }
        let result = Engine.run(selected, args: Engine.splitArguments(argsText), on: document.data, name: document.name, kind: document.kind)
        lastResult = result
        onApply(result)
    }
}
