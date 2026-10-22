// The floating bar of five actions. The same bar, in the same place, for every kind of file.
import SwiftUI

struct ActionBar: View {
    @Binding var active: DocumentAction?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DocumentAction.allCases) { action in
                ActionButton(action: action, isActive: active == action) {
                    active = active == action ? nil : action
                }
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("actionBar")
    }
}

private struct ActionButton: View {
    let action: DocumentAction
    let isActive: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label(action.title, systemImage: action.symbol)
                .font(.callout.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!action.isBuilt)
        .opacity(action.isBuilt ? 1 : 0.4)
        .help(action.isBuilt ? action.title : "\(action.title) is not built yet")
        .accessibilityIdentifier("action.\(action.rawValue)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
