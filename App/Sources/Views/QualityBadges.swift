import SwiftUI
import Combine
import PlayerCore

// Qualitäts-Plaketten (Task 8): welche Plaketten und beste Werte liegen in PlayerCore/QualityBadges, die Form in
// `ThemeBadge` (Welle F-d: einziger Plakettentyp; Wortmarken als Text, keine Bilddateien, keine fremden Logos).

/// Kleine Plaketten am Poster (beste Auflösung, DV/HDR, Atmos) – nur aus dem Quellen-Cache, keine Netzabfrage.
/// Welle E-a: Lage nach „Qualität auf Postern“ (Standard aus). Nie unten auf dem Bild: dort tragen viele Poster
/// (Bewertungs-Poster) eine Genre-/Bewertungszeile. „Unten“ = eigener Streifen unter dem Bild (`PosterBadgeBand`).
struct PosterQualityBadges: View {
    @EnvironmentObject var model: AppModel
    let item: MetaPreview
    var scale: CGFloat = 1
    @State private var best: BestQuality?
    /// Plakettenhöhe auf Postern (§4.5: 26, unabhängig von der Kartengröße wie die Schrift darin).
    static let badgeHeight: CGFloat = ThemeBadge.TechSize.poster.height
    /// Innenabstand im Streifen unter dem Bild (oben und unten).
    static let bandPadding: CGFloat = Theme.Space.xs
    /// Höhe des Streifens unter dem Bild bei „Unten“.
    static var bandHeight: CGFloat { badgeHeight + 2 * bandPadding }
    private func row(_ badges: [QualityBadge]) -> some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(badges) { ThemeBadge($0, size: .poster, surface: .image) }
        }
    }

    /// Höchstbreite links neben dem Inhalt (aufgeklapptes Poster: Logo/Titel), als Anteil der Breite.
    static let leadingContentMaxFraction: CGFloat = 0.55

    var body: some View {
        let settings = model.profile.appearance.badges
        let placement = model.profile.appearance.titles.posterBadges
        let list = best.map { QualityBadges.poster($0, settings: settings, placement: placement) } ?? []
        let bottom = placement == .bottom
        ZStack(alignment: bottom ? .bottomLeading : .topTrailing) {
            Color.clear
            if !list.isEmpty {
                // Passt die Reihe nicht in die Posterbreite (Text-Stil), entfallen Plaketten von hinten.
                ViewThatFits(in: .horizontal) {
                    row(list)
                    row(Array(list.prefix(2)))
                    row(Array(list.prefix(1)))
                }
                .padding(bottom ? .leading : .trailing, Theme.Space.xs * scale)
                .padding(bottom ? .bottom : .top, bottom ? Self.bandPadding : topInset)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(item.id)|\(placement.rawValue)") {
            best = placement != .off ? QualityBadgeCache.shared.best(for: item, model: model) : nil
        }
        .onReceive(QualityBadgeCache.shared.stored) { id in
            guard placement != .off, model.streamCacheKey(for: item) == id else { return }
            withAnimation(.easeOut(duration: 0.2)) { best = QualityBadgeCache.shared.best(id: id, model: model) }
        }
    }

    /// Oben rechts: unter Haken bzw. Folgen-/Restzeit-Kapsel (CardStateOverlay), sonst direkt an der Kante.
    private var topInset: CGFloat {
        guard let st = model.progress.cardState(itemID: item.id) else { return 10 * scale }
        let occupied = st.watched || st.episode != nil || st.remainingSeconds != nil
        return occupied ? 56 * scale : 10 * scale
    }
}

/// Welle E-a: Streifen unter dem Posterbild für „Qualität auf Postern: Unten“. Immer da, solange die Einstellung
/// gilt (auch ohne Plaketten), damit alle Karten einer Reihe gleich hoch bleiben. Eigene View, damit nur sie
/// (nicht die ganze Karte) auf Profiländerungen reagiert.
struct PosterBadgeBand: View {
    @EnvironmentObject var model: AppModel
    /// Breite des Bildes darüber (in Reihen ist die angebotene Breite unbegrenzt).
    let width: CGFloat

    var body: some View {
        if model.profile.appearance.titles.posterBadges == .bottom {
            Theme.Palette.posterBand.frame(width: width, height: PosterQualityBadges.bandHeight)
        }
    }
}

/// Beste Werte je Quellen-Cache-ID, einmal berechnet (nicht in jedem body). `AppModel` meldet neue Quellen über
/// `streamsStored`, wartende Poster aktualisieren sich dann über `stored`.
@MainActor
final class QualityBadgeCache {
    static let shared = QualityBadgeCache()
    /// Sendet die Cache-ID, sobald neue Quellen im AppModel-Cache liegen.
    let stored = PassthroughSubject<String, Never>()
    private var cache: [String: BestQuality] = [:]

    private init() {}

    func streamsStored(id: String) {
        cache[id] = nil
        stored.send(id)
    }

    /// Nur solange die Quellen im AppModel-Cache liegen; sonst nil.
    func best(id: String, model: AppModel) -> BestQuality? {
        guard let list = model.cachedStreams(id: id), !list.isEmpty else { cache[id] = nil; return nil }
        if let b = cache[id] { return b }
        guard let b = BestQuality.from(list.map(\.stream)) else { return nil }
        if cache.count >= 2 * StreamPrefetcher.cacheLimit {
            cache = cache.filter { model.cachedStreams(id: $0.key) != nil }
        }
        cache[id] = b
        return b
    }

    func best(for item: MetaPreview, model: AppModel) -> BestQuality? {
        model.streamCacheKey(for: item).flatMap { best(id: $0, model: model) }
    }
}
