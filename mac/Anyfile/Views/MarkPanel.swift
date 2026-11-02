// The Mark card: pressing Mark keeps the selected passage; the card lists this file's marks.
import SwiftUI

struct MarkPanel: View {
    let marks: [Mark]
    /// One line above the list: what just happened, or what to do to make a mark.
    let status: String
    let choose: (Mark) -> Void
    let remove: (Mark) -> Void
    var setNote: (Mark, String) -> Void = { _, _ in }
    var setColour: (Mark, MarkColour) -> Void = { _, _ in }
    /// Saves this file's marks as Markdown; nil hides the button.
    var export: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Marks").font(.headline)
                Spacer()
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("markStatus")
                if let export, !marks.isEmpty {
                    Button("Export…", action: export)
                        .help("Save these marks and notes as a Markdown file")
                        .accessibilityIdentifier("exportMarks")
                }
            }
            if marks.isEmpty {
                Text("Nothing marked in this file yet.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(marks) { mark in
                            MarkRow(mark: mark, choose: { choose(mark) }, remove: { remove(mark) }, setNote: { setNote(mark, $0) },
                                    setColour: { setColour(mark, $0) })
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
    }
}
