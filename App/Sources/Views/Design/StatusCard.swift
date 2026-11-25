import SwiftUI
import PlayerCore

/// Kopfkarte einer Kategorie (§4.6): `bg.row`, `radius.row`, links Initiale oder Symbol, daneben Titel und
/// Untertitel, rechts 2–3 Kennzahlen, optional ein Aktionsknopf. Gegen den „mageren“ Eindruck leerer Kategorien.
/// Die Karte selbst ist kein Fokusziel; nur der Aktionsknopf ist fokussierbar.
struct StatusCard: View {
    /// Linkes Zeichen der Karte.
    enum Leading {
        /// Initiale im Kreis (z. B. Profil „I“).
        case initial(String, Color)
        /// Gefülltes Symbol im Kreis.
        case symbol(String, Color)
    }

    /// Kennzahl rechts. Mit `tone` bekommt sie Zustandsfarbe und -symbol (Farbe nie allein, A5).
    struct Metric: Hashable {
        let text: String
        var tone: Theme.Tone? = nil
    }

    struct Action {
        let title: String
        var symbol: String? = nil
        let perform: () -> Void
    }

    let leading: Leading
    let title: String
    var subtitle: String? = nil
    var metrics: [Metric] = []
    var action: Action? = nil

    /// Höchstens 3 Kennzahlen (§4.6).
    private var shownMetrics: [Metric] { Array(metrics.filter { !$0.text.isEmpty }.prefix(3)) }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                leadingMark
                VStack(alignment: .leading, spacing: Theme.Space.xs / 2) {
                    Text(title).textRole(.rowTitleEmphasis).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).textRole(.rowDetail).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.l)
                VStack(alignment: .trailing, spacing: Theme.Space.xs / 2) {
                    ForEach(Array(shownMetrics.enumerated()), id: \.offset) { metricView($0.element) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            if let action {
                Button(action: action.perform) {
                    if let symbol = action.symbol {
                        Label(action.title, systemImage: symbol)
                    } else {
                        Text(action.title)
                    }
                }
                .accessibilityLabel(action.title)
                // Build 4 device test (phone page): system buttons take the root tint into the focused label.
                .buttonStyle(ThemeActionButtonStyle())
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
        .background(Theme.Palette.row, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    @ViewBuilder private var leadingMark: some View {
        switch leading {
        case .initial(let text, let color):
            Text(String(text.prefix(1)).uppercased())
                .font(Theme.TextRole.sectionTitle.font)
                .modifier(StatusMarkCircle(color: color))
        case .symbol(let name, let color):
            Image(systemName: name)
                .symbolVariant(.fill)
                .font(.system(size: Theme.Layout.iconSize, weight: .semibold))
                .modifier(StatusMarkCircle(color: color))
        }
    }

    @ViewBuilder private func metricView(_ m: Metric) -> some View {
        if let tone = m.tone {
            Label(m.text, systemImage: tone.symbol)
                .font(Theme.TextRole.rowDetail.font)
                .foregroundStyle(tone.textColor)
                .monospacedDigit()
                .lineLimit(1)
        } else {
            Text(m.text).textRole(.rowDetail).monospacedDigit().lineLimit(1)
        }
    }

    private var accessibilityText: String {
        DesignText.accessibilityLabel([title, subtitle] + shownMetrics.map { m -> String? in
            m.tone.map { "\($0.accessibilityName): \(m.text)" } ?? m.text
        })
    }
}

/// Circle behind the leading mark of a `StatusCard`. Task 4.5 review M3: the neutral category tint follows the
/// runtime theme like `IconTile` (`color.raised`, symbol `color.primary`), lifted by 14 % of `color.primary` so the
/// circle stands out from the card (`bg.row`) on every background tone. Any other colour keeps the coloured circle
/// with the white symbol.
private struct StatusMarkCircle: ViewModifier {
    let color: Color
    @Environment(\.theme) private var theme

    private var isNeutral: Bool { Theme.CategoryTint.isNeutral(color) }

    func body(content: Content) -> some View {
        let size: CGFloat = Theme.Layout.statusMark
        content
            .foregroundStyle(isNeutral ? theme.color.primary : Color.white)
            .frame(width: size, height: size)
            .background { fill }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var fill: some View {
        if isNeutral {
            Circle()
                .fill(theme.color.raised)
                .overlay { Circle().fill(theme.color.primary.opacity(0.14)) }
        } else {
            Circle().fill(color)
        }
    }
}

#Preview("Statuskarte") {
    VStack(alignment: .leading, spacing: Theme.Space.m) {
        StatusCard(leading: .initial("Ich", Theme.CategoryTint.profile.color), title: "Ich", subtitle: "aktives Profil",
                   metrics: [.init(text: DesignText.metaLine(["3 Addons", "24 Reihen"])), .init(text: "Fortschritt: Trakt")])
        StatusCard(leading: .symbol("puzzlepiece.extension", Theme.CategoryTint.addons.color), title: "Addons",
                   subtitle: "3 Addons",
                   metrics: [.init(text: "Verbunden", tone: .ok), .init(text: "Schlüssel fehlt", tone: .warn)],
                   action: .init(title: "Am Handy", symbol: "qrcode") {})
    }
    .padding(.horizontal, Theme.Space.edge)
    .padding(.vertical, Theme.Space.edgeVertical)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .settingsSurface()
}
