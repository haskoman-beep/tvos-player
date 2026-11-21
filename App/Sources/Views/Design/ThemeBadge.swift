import SwiftUI
import PlayerCore

/// Plaketten nach der Formregel §4.5: eine Information, eine Form.
/// - Technik: gefüllt neutral (Weiß 18 %), weißer Text, `radius.badge`, Höhe je Einsatzort.
/// - Bewertung: ohne Rahmen, Markenname in Markenfarbe + Zahl in Weiß („IMDb 7,1“).
/// - Status: Kapsel, auf Bildern Schwarz 65 %, auf Flächen in Zustandsfarbe.
/// - Meta ist keine Plakette, sondern Text (`MetaLine`).
/// Plakettenreihen brechen nie um; was nicht passt, fällt nach Priorität weg (Welle E).
/// Name `ThemeBadge`, weil `Badge` in DetailViews.swift schon vergeben ist.
struct ThemeBadge: View {
    /// Höhe einer Technik-Plakette je Einsatzort.
    enum TechSize {
        case detail, sources, poster

        var height: CGFloat {
            switch self {
            case .detail: 34
            case .sources: 30
            case .poster: 26
            }
        }
    }

    enum Kind {
        /// Technik: 4K, DV, Atmos, „TrueHD 7.1“, Remux.
        case tech(TechSize)
        /// Bewertung: Markenname in Markenfarbe, Wert weiß.
        case rating(brand: String, brandColor: Color)
        /// Status-Kapsel. `onImage`: auf Postern/Bildern (Schwarz 65 %); sonst Fläche in Zustandsfarbe.
        case status(Theme.Tone?, onImage: Bool)
    }

    let kind: Kind
    let text: String
    /// Optionales Symbol vor dem Text (Status „⚡ sofort“, „✓ Gesehen“).
    var symbol: String? = nil
    /// Gesprochener Text, wenn der sichtbare abgekürzt ist („DV“ → „Dolby Vision“).
    var spokenText: String? = nil

    var body: some View {
        content
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .tech(let size):
            label
                .font(Theme.TextRole.badge.font)
                .foregroundStyle(Theme.Palette.primary)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: size.height)
                .background(Theme.Palette.badgeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
        case .rating(let brand, let brandColor):
            HStack(spacing: Theme.Space.xs) {
                Text(brand).foregroundStyle(brandColor)
                Text(text).foregroundStyle(Theme.Palette.primary).monospacedDigit()
            }
            .font(Theme.TextRole.badge.font)
        case .status(let tone, let onImage):
            label
                .font(Theme.TextRole.badge.font)
                .foregroundStyle(onImage ? Theme.Palette.primary : (tone?.textColor ?? Theme.Palette.primary))
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xs / 2)
                .background(statusFill(tone: tone, onImage: onImage), in: Capsule())
        }
    }

    @ViewBuilder private var label: some View {
        if let symbol {
            HStack(spacing: Theme.Space.xs / 2) {
                Image(systemName: symbol)
                Text(text)
            }
        } else {
            Text(text)
        }
    }

    private func statusFill(tone: Theme.Tone?, onImage: Bool) -> Color {
        if onImage { return Theme.Palette.badgeOnImage }
        return tone.map { $0.color.opacity(0.22) } ?? Theme.Palette.badgeFill
    }

    private var accessibilityText: String {
        switch kind {
        case .rating(let brand, _): DesignText.accessibilityLabel([brand, spokenText ?? text])
        default: spokenText ?? text
        }
    }
}

/// Meta-Zeile als reiner Text in `rowDetail` mit „ · “ („2018 · 97 min · FSK 0 · Animation“).
struct MetaLine: View {
    let parts: [String?]

    var body: some View {
        let text = DesignText.metaLine(parts)
        if !text.isEmpty {
            Text(text)
                .textRole(.rowDetail)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(DesignText.accessibilityLabel(parts))
        }
    }
}

#Preview("Plaketten") {
    VStack(alignment: .leading, spacing: Theme.Space.l) {
        HStack(spacing: Theme.Space.xs) {
            ThemeBadge(kind: .tech(.detail), text: "4K")
            ThemeBadge(kind: .tech(.detail), text: "DV", spokenText: "Dolby Vision")
            ThemeBadge(kind: .tech(.detail), text: "Atmos", spokenText: "Dolby Atmos")
            ThemeBadge(kind: .tech(.sources), text: "TrueHD 7.1")
            ThemeBadge(kind: .tech(.poster), text: "Remux")
        }
        HStack(spacing: Theme.Space.m) {
            ThemeBadge(kind: .rating(brand: "IMDb", brandColor: .yellow), text: DesignText.decimal(7.1))
            ThemeBadge(kind: .rating(brand: "RT", brandColor: .red), text: "63 %")
        }
        HStack(spacing: Theme.Space.xs) {
            ThemeBadge(kind: .status(nil, onImage: true), text: "noch 97 min")
            ThemeBadge(kind: .status(.ok, onImage: false), text: "sofort", symbol: "bolt.fill")
            ThemeBadge(kind: .status(nil, onImage: false), text: "Gesehen", symbol: "checkmark")
        }
        MetaLine(parts: ["2018", "97 min", "FSK 0", "Animation"])
    }
    .padding(.horizontal, Theme.Space.edge)
    .padding(.vertical, Theme.Space.edgeVertical)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .settingsSurface()
}
