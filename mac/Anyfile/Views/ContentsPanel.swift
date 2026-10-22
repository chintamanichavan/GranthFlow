// The Contents card: chapters, headings or pages. Choosing one moves the pane there.
import SwiftUI

struct ContentsPanel: View {
    let entries: [ContentsEntry]
    /// The entry on show is the one whose target matches.
    let current: Int?
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Contents").font(.headline).padding([.horizontal, .top], 14)
            if entries.isEmpty {
                Text("Nothing to list in this file.")
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            ContentsRow(entry: entry, isCurrent: entry.target == current) { choose(entry.target) }
                                .accessibilityIdentifier("contents.\(entry.id)")
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentsPanel")
    }
}

struct ContentsRow: View {
    let entry: ContentsEntry
    let isCurrent: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Text(entry.title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fontWeight(entry.level == 0 ? .medium : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(entry.level) * 14 + 10)
                .padding(.trailing, 10)
                .padding(.vertical, 5)
                .background(isCurrent ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
