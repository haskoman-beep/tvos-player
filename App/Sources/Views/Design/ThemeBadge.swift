import SwiftUI
import PlayerCore

/// Plaketten nach der Formregel §4.5: eine Information, eine Form. Einziger Plakettentyp der App (Welle F-d:
/// ersetzt `QualityBadgeView`, `QualityLogo` und `BadgeSurface`; `Badge` ist nur noch ein Altname darauf).
/// - Technik: gefüllt neutral (Weiß 18 %), weißer Text bzw. einfarbige Wortmarke, `radius.badge`, Höhe je Einsatzort.
/// - Bewertung: ohne Rahmen, Markenname in Markenfarbe + Zahl in Weiß („IMDb 7,1“).
/// - Status: Kapsel, auf Bildern Schwarz 65 %, auf Flächen in Zustandsfarbe.
/// - Meta ist keine Plakette, sondern Text (`MetaLine`).
/// Plakettenreihen brechen nie um; was nicht passt, fällt nach Priorität weg (Welle E).
/// Jede Plakette spricht einen eigenen Text (A7): `spokenText`, sonst der sichtbare.
struct ThemeBadge: View {
    /// Höhe und Schrift einer Technik-Plakette je Einsatzort.
    enum TechSize {
        case detail, sources, poster

        var height: CGFloat {
            switch self {
            case .detail: 34
            case .sources: 30
            case .poster: 26
            }
        }

        /// Plakettenschrift (`badge`); auf Postern eine Stufe kleiner, damit sie in die 26er-Höhe passt.
        var font: Font {
            switch self {
            case .detail, .sources: Theme.TextRole.badge.font
            case .poster: .caption2.bold()
            }
        }
    }

    /// Untergrund der Plakette: bestimmt Fläche und Schrift (Technik und Status).
    enum Surface {
        /// Dunkle Fläche (Detailseite, Quellenliste, Panels).
        case plain
        /// Fokussierte, weiße Zeile: dunkle Schrift auf dunkler Tönung.
        case focusedRow
        /// Auf einem Bild (Poster): Schwarz 65 %, damit helle Bildstellen nicht durchscheinen.
        case image
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
    /// Optionales Symbol vor dem Text (Status „⚡ Sofort bereit“, „✓ Gesehen“).
    var symbol: String? = nil
    /// Gesprochener Text, wenn der sichtbare abgekürzt ist („DV“ → „Dolby Vision“).
    var spokenText: String? = nil
    /// Bewertung: gesprochener Markenname, wenn der sichtbare ein Zeichen ist („🍅“ → „Rotten Tomatoes“).
    var spokenBrand: String? = nil
    /// Untergrund (Technik und Status).
    var surface: Surface = .plain
    /// Technik als Wortmarke (Plakettenstil „Logo“): fetter, Großbuchstaben, gleiche Fläche.
    var wordmark = false
    /// Bewertung: Quelle für das Icon aus dem gewählten Icon-Satz (`RatingIconLabel`); ohne Icon der Markenname.
    var iconSource: String? = nil

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
                .font(size.font)
                .fontWeight(wordmark ? .heavy : nil)
                .foregroundStyle(surface == .focusedRow ? Theme.Palette.primaryOnFocus : Theme.Palette.primary)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: size.height)
                .background(techFill, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
        case .rating(let brand, let brandColor):
            HStack(spacing: Theme.Space.xs) {
                if let iconSource {
                    RatingIconLabel(source: iconSource) { Text(brand).foregroundStyle(brandColor) }
                } else {
                    Text(brand).foregroundStyle(brandColor)
                }
                Text(text).foregroundStyle(Theme.Palette.primary).monospacedDigit()
            }
            .font(Theme.TextRole.badge.font)
        case .status(let tone, let onImage):
            label
                .font(onImage ? TechSize.poster.font : Theme.TextRole.badge.font)
                .foregroundStyle(statusForeground(tone: tone, onImage: onImage))
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

    private var techFill: Color {
        switch surface {
        case .plain: Theme.Palette.badgeFill
        case .focusedRow: Theme.Palette.badgeFillOnFocus
        case .image: Theme.Palette.badgeOnImage
        }
    }

    private func statusForeground(tone: Theme.Tone?, onImage: Bool) -> Color {
        if onImage { return Theme.Palette.primary }
        if surface == .focusedRow { return Theme.Palette.primaryOnFocus }
        return tone?.textColor ?? Theme.Palette.primary
    }

    private func statusFill(tone: Theme.Tone?, onImage: Bool) -> Color {
        if onImage { return Theme.Palette.badgeOnImage }
        // Auf der weißen Fokuszeile deckend in Zustandsfarbe mit dunkler Schrift (Tönung wäre dort kaum sichtbar).
        if surface == .focusedRow { return tone?.color ?? Theme.Palette.badgeFillOnFocus }
        return tone.map { $0.color.opacity(0.22) } ?? Theme.Palette.badgeFill
    }

    private var accessibilityText: String {
        switch kind {
        case .rating(let brand, _): DesignText.accessibilityLabel([spokenBrand ?? brand, spokenText ?? text])
        default: spokenText ?? text
        }
    }
}

extension ThemeBadge {
    /// Plakette aus dem PlayerCore-Modell: Cache-Zustand als Status-Kapsel, alles andere als Technik.
    init(_ badge: QualityBadge, size: TechSize, surface: Surface = .plain) {
        switch badge.tone {
        case .neutral:
            self.init(kind: .tech(size), text: badge.logo?.wordmark ?? badge.text, spokenText: badge.spokenText,
                      surface: surface, wordmark: badge.logo != nil)
        case .ready:
            self.init(kind: .status(.ok, onImage: surface == .image), text: badge.displayText, symbol: "bolt.fill",
                      spokenText: badge.spokenText, surface: surface)
        case .pending:
            self.init(kind: .status(.warn, onImage: surface == .image), text: badge.displayText,
                      spokenText: badge.spokenText, surface: surface)
        }
    }

    /// Bewertung aus dem PlayerCore-Modell (Wert mit Komma, VoiceOver „IMDb 7,1“).
    init(rating: RatingBadge, brandColor: Color) {
        self.init(kind: .rating(brand: rating.label, brandColor: brandColor), text: rating.displayValue,
                  spokenText: rating.displayValue.replacingOccurrences(of: "\u{00A0}", with: " "),
                  spokenBrand: rating.spokenSource, iconSource: rating.source)
    }
}

/// Altname für die Kurz-Plaketten der Spurliste im Player („Forced“, „SDH“). Zeichnet eine Technik-Plakette;
/// die Farbe wird nicht mehr genutzt (Formregel §4.5). Bleibt, damit die Player-Dateien unberührt bleiben.
struct Badge: View {
    let text: String
    init(_ text: String, _ color: Color) { self.text = text }
    var body: some View { ThemeBadge(kind: .tech(.sources), text: text) }
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
            ThemeBadge(kind: .status(.ok, onImage: false), text: "Sofort bereit", symbol: "bolt.fill")
            ThemeBadge(kind: .status(nil, onImage: false), text: "Gesehen", symbol: "checkmark")
        }
        MetaLine(parts: ["2018", "97 min", "FSK 0", "Animation"])
    }
    .padding(.horizontal, Theme.Space.edge)
    .padding(.vertical, Theme.Space.edgeVertical)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .settingsSurface()
}
