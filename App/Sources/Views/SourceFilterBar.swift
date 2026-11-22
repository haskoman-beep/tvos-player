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
    /// True while a chip has the focus (the list's entry focus then leaves the user here).
    let onFocusChange: (Bool) -> Void
    @FocusState private var focusedChip: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                chip("Alle", id: "all", count: total, on: selected.isEmpty, action: onAll)
                ForEach(options) { o in
                    chip(o.chip.label, id: o.id, count: o.count, on: selected.contains(o.chip)) { onToggle(o.chip) }
                }
            }
            // Room for the focus lift (`Focus.tileScale`) so a focused chip is not cut.
            .padding(.vertical, Theme.Space.s)
            .padding(.horizontal, Theme.Space.xs)
        }
        .scrollClipDisabled()
        .focusSection()
        .onChange(of: focusedChip != nil) { _, on in onFocusChange(on) }
        .onDisappear { onFocusChange(false) }
    }

    private func chip(_ label: String, id: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
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
        .focused($focusedChip, equals: id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
