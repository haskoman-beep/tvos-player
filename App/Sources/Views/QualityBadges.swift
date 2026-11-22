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
    /// Wave F-k R1: row of this tile for the visible-tile prefetch; whether the card is on screen.
    @Environment(\.prefetchRow) private var prefetchRow
    @State private var onScreen = false
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
            // Wave F-k R1: badges switched on/off while the card is on screen.
            StreamPrefetcher.shared.tile(item, row: prefetchRow, visible: onScreen && placement != .off, model: model)
        }
        .onReceive(QualityBadgeCache.shared.stored) { id in
            guard placement != .off, model.streamCacheKey(for: item) == id else { return }
            withAnimation(.easeOut(duration: 0.2)) { best = QualityBadgeCache.shared.best(id: id, model: model) }
        }
        // Wave F-k R1: on screen (≥ half of the card inside the screen, both scroll views applied) → quiet source
        // prefetch, so the badge appears without focus. Fades in like above, in place (overlay, no layout change).
        .onGeometryChange(for: Bool.self) { proxy in
            TileVisibility.isOnScreen(proxy.frame(in: .global), screen: Theme.Screen.bounds)
        } action: { on in
            onScreen = on
            StreamPrefetcher.shared.tile(item, row: prefetchRow, visible: on && placement != .off, model: model)
        }
        .onDisappear { StreamPrefetcher.shared.tile(item, row: prefetchRow, visible: false, model: model) }
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

    /// Wave F-k R1: best values after the source list left the AppModel cache (it holds 40 titles, more tiles can be
    /// on screen), for the source cache lifetime; tiny, so a badge does not vanish while its title is not fetched again.
    private var remembered: [String: (best: BestQuality, at: Date)] = [:]
    private static let rememberLimit = 400

    private init() {}

    /// Wave F-k R2 (m2): new list stored – its best values are remembered at once (the weak cache tier may drop the
    /// list right away, the badge stays).
    func streamsStored(id: String, list: [(addon: String, stream: StreamItem)], at: Date) {
        cache[id] = nil
        if let b = BestQuality.from(list.map(\.stream)) { remember(id, b, at: at) } else { remembered[id] = nil }
        stored.send(id)
    }

    /// Wave F-k R1: profile switch (other addons, other sources).
    func forget() {
        cache.removeAll()
        remembered.removeAll()
    }

    /// Aus dem AppModel-Cache; danach noch bis zum Ablauf der Quellen (`RevalidationPolicy.streams`) gemerkt.
    func best(id: String, model: AppModel) -> BestQuality? {
        guard let list = model.cachedStreams(id: id), !list.isEmpty else {
            cache[id] = nil
            // A newer answer without usable sources replaces the remembered values.
            if let c = model.streamCache[id], let r = remembered[id], c.at > r.at { remembered[id] = nil }
            guard let r = remembered[id], RevalidationPolicy.streams.isUsable(storedAt: r.at) else { return nil }
            return r.best
        }
        if let b = cache[id] { return b }
        guard let b = BestQuality.from(list.map(\.stream)) else { return nil }
        if cache.count >= 2 * StreamPrefetcher.cacheLimit {
            cache = cache.filter { model.cachedStreams(id: $0.key) != nil }
        }
        cache[id] = b
        remember(id, b, at: model.streamCache[id]?.at ?? Date())
        return b
    }

    private func remember(_ id: String, _ b: BestQuality, at: Date) {
        remembered[id] = (b, at)
        guard remembered.count > Self.rememberLimit else { return }
        let drop = remembered.sorted { $0.value.at < $1.value.at }.prefix(remembered.count - Self.rememberLimit)
        for (k, _) in drop { remembered[k] = nil }
    }

    func best(for item: MetaPreview, model: AppModel) -> BestQuality? {
        model.streamCacheKey(for: item).flatMap { best(id: $0, model: model) }
    }
}

private struct PrefetchRowKey: EnvironmentKey { static let defaultValue = PrefetchRow(key: "tiles", title: "Kacheln") }

extension EnvironmentValues {
    /// Wave F-k R1: row of the poster tiles below (visible-tile prefetch).
    var prefetchRow: PrefetchRow {
        get { self[PrefetchRowKey.self] }
        set { self[PrefetchRowKey.self] = newValue }
    }
}
