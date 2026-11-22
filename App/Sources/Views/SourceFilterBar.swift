import PlayerCore
import SwiftUI

/// Wave Q: chip row above the source list ("Alle", then only the qualities and features the list offers, each
/// with its count). Pure view: the selection lives in StreamListView, the rules in `SourceFilter` (PlayerCore).
struct SourceFilterBar: View {
    let options: [SourceFilterOption]
    let selected: Set<SourceFilterChip>
    let total: Int
    let onAll: () -> Void
    let onToggle: (SourceFilterChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                chip("Alle", count: total, on: selected.isEmpty, action: onAll)
                ForEach(options) { o in
                    chip(o.chip.label, count: o.count, on: selected.contains(o.chip)) { onToggle(o.chip) }
                }
            }
            // Room for the focus lift (`Focus.tileScale`) so a focused chip is not cut.
            .padding(.vertical, Theme.Space.s)
            .padding(.horizontal, Theme.Space.xs)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private func chip(_ label: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                if on { Image(systemName: "checkmark") }
                Text(label)
                Text("\(count)").opacity(0.6)
            }
            .font(Theme.TextRole.rowDetail.font)
            .lineLimit(1)
        }
        .buttonStyle(ThemeActionButtonStyle(selected: on))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
