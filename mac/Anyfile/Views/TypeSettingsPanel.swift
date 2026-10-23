// The Aa panel: text size, line spacing, column width and theme for the book on show.
import SwiftUI

struct TypeSettingsPanel: View {
    @Binding var settings: ReadingSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { settings = settings.smaller() } label: { Text("A").font(.system(size: 13, design: .serif)).frame(width: 44, height: 28) }
                    .disabled(settings.size <= ReadingSettings.sizes.lowerBound)
                    .accessibilityIdentifier("textSmaller")
                Text("\(Int(settings.size)) pt").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("textSize")
                Button { settings = settings.larger() } label: { Text("A").font(.system(size: 21, design: .serif)).frame(width: 44, height: 28) }
                    .disabled(settings.size >= ReadingSettings.sizes.upperBound)
                    .accessibilityIdentifier("textLarger")
            }
            row("Line spacing") {
                Picker("Line spacing", selection: $settings.spacing) {
                    Text("Tight").tag(ReadingSettings.Spacing.tight)
                    Text("Normal").tag(ReadingSettings.Spacing.normal)
                    Text("Loose").tag(ReadingSettings.Spacing.loose)
                }
            }
            row("Column") {
                Picker("Column", selection: $settings.width) {
                    Text("Narrow").tag(ReadingSettings.Width.narrow)
                    Text("Normal").tag(ReadingSettings.Width.normal)
                    Text("Wide").tag(ReadingSettings.Width.wide)
                }
            }
            HStack(spacing: 14) {
                ForEach(ReadingSettings.Look.allCases, id: \.self) { look in LookSwatch(look: look, chosen: settings.look == look) { settings.look = look } }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 280)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content().pickerStyle(.segmented).labelsHidden()
        }
    }
}

private struct LookSwatch: View {
    let look: ReadingSettings.Look
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 5) {
                ZStack {
                    if look == .auto {
                        // Half light paper, half dark: it follows the Mac's appearance.
                        Circle().fill(Color(nsColor: Theme.fixedPaper.window))
                        Circle().trim(from: 0.25, to: 0.75).fill(Color(nsColor: Theme.readingNight.window)).rotationEffect(.degrees(180))
                    } else {
                        Circle().fill(Color(nsColor: ReadingSettings(look: look).palette.window))
                    }
                    Text("Aa").font(.system(size: 12, design: .serif))
                        .foregroundStyle(Color(nsColor: look == .night ? Theme.readingNight.label : Theme.fixedPaper.label))
                }
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(chosen ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: chosen ? 2.5 : 1))
                Text(look.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("look.\(look.rawValue)")
    }
}

extension ReadingSettings {
    init(look: Look) { self.init(); self.look = look }
}
