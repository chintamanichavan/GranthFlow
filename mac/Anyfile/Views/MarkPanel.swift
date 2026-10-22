// The Mark card: pressing Mark keeps the selected passage; the card lists this file's marks.
import SwiftUI

struct MarkPanel: View {
    let marks: [Mark]
    /// One line above the list: what just happened, or what to do to make a mark.
    let status: String
    let choose: (Mark) -> Void
    let remove: (Mark) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Marks").font(.headline)
                Spacer()
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("markStatus")
            }
            if marks.isEmpty {
                Text("Nothing marked in this file yet.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(marks) { mark in
                            MarkRow(mark: mark, choose: { choose(mark) }, remove: { remove(mark) })
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
    }
}

struct MarkRow: View {
    let mark: Mark
    let choose: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: Theme.mark)).frame(width: 3)
            Button(action: choose) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("“\(mark.quote)”").font(.system(size: 14, design: .serif)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(mark.place).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
                .help("Remove this mark")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mark.\(mark.quote.prefix(24))")
    }
}
