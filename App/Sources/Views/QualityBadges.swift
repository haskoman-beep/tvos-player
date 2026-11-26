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
    /// Task 5.1: on a landscape card (no band below): always at the top trailing corner, never on the picture's
    /// bottom edge (where the title and scrim sit).
    var landscape = false
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
        let bottom = placement == .bottom && !landscape
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
        .onReceive(QualityBadgeCache.shared.stored) { ids in
            // S3: cheap test (no progress search per tile on screen), same answer as `streamCacheKey(for:) == id`.
            // P3: one batch of IDs per pass; at most one of them is this tile's key.
            guard placement != .off, let id = QualityBadgeCache.shared.match(ids, for: item, model: model) else { return }
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
/// Build 4 follow-up 2 (P3): the values are stored at once (a card appearing reads them in its `.task`), the
/// notification goes out collected (`BadgeBatch`): one pass for all results of 0.5 s, not before the focus has been
/// quiet for `BackdropRest.homeFocusQuiet` (2.1 s, b5r; no badge fade during the card lift or backdrop rest and
/// crossfade), at the latest 3 s after the
/// first result. Only the cards whose key is in the batch change state (`PosterQualityBadges.best`); rows only log.
@MainActor
final class QualityBadgeCache {
    static let shared = QualityBadgeCache()
    /// Sendet die Cache-IDs mit neuen Quellen im AppModel-Cache, gebündelt (P3).
    let stored = PassthroughSubject<Set<String>, Never>()
    private var batch = BadgeBatch(limits: BadgeBatch.Limits(focusQuiet: BackdropRest.homeFocusQuiet))
    private var flushTask: Task<Void, Never>?
    /// P3: one `ruckler` line per 10 s with passes (`Plaketten gebündelt: …`).
    private var passStats = BadgePassStats()
    /// S3 review (Minor 1): values with the number of entries they were computed from (`CachedBest`).
    private var cache: [String: CachedBest] = [:]

    /// Wave F-k R1: best values after the source list left the AppModel cache (it holds 40 titles, more tiles can be
    /// on screen), for the source cache lifetime; tiny, so a badge does not vanish while its title is not fetched again.
    private var remembered: [String: (best: BestQuality, at: Date)] = [:]
    private static let rememberLimit = 400

    private init() {}

    /// Wave F-k R2 (m2): new list stored – its best values are remembered at once (the weak cache tier may drop the
    /// list right away, the badge stays). Build 4 follow-up S3: `best` comes computed (`PreparedStreams`, parsed off
    /// the main thread) and is kept for the new list instead of clearing it, so the tile receiving `stored` parses
    /// nothing on the main thread. `entries`: length of the stored list the values belong to.
    func streamsStored(id: String, best: BestQuality?, entries: Int, at: Date, model: AppModel) {
        if let b = best {
            keep(id, CachedBest(best: b, entries: entries), model: model)
            remember(id, b, at: at)
        } else {
            cache[id] = nil
            remembered[id] = nil
        }
        queue(id)
    }

    /// Wave F-k R1: profile switch (other addons, other sources).
    func forget() {
        cache.removeAll()
        remembered.removeAll()
        batch.clear()   // P3: the waiting flush finds nothing and ends
    }

    /// P3: focus moved to another tile (via `StreamPrefetcher.focusMoved`): waiting values wait for 1 s of quiet.
    func focusMoved() { batch.focusMoved(now: Date()) }

    /// P3: the key of `item` among the sent IDs (nil = the batch does not concern this tile).
    func match(_ ids: Set<String>, for item: MetaPreview, model: AppModel) -> String? {
        ids.first { model.streamCacheKeyMatches($0, for: item) }
    }

    private func queue(_ id: String) {
        batch.add(id, now: Date())
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in await self?.flushWhenDue() }
    }

    /// Sleeps until the batch is due (the due time moves later while the focus moves), then sends it in one pass.
    private func flushWhenDue() async {
        while let due = batch.flushAt {
            let wait = due.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let flush = batch.take(now: Date()) else { continue }
            flushTask = nil
            FrameMeter.event(.badges)   // counted in the next `ruckler` line
            stored.send(flush.ids)
            if passStats.record(flush) { logPassesLater() }
            return
        }
        flushTask = nil
    }

    private func logPassesLater() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(BadgePassStats.window))
            if let line = self?.passStats.take() { RemoteLog.info("ruckler", line) }
        }
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
        if let c = cache[id] {
            if c.isCurrent(usableEntries: list.count) { return c.best }
            // S3 review (Minor 1): kept entries of an addon without answer expired on read; their DV/Atmos must not
            // stay on the tile. Computed again from what the list still offers (rare: once per lapse).
            RemoteLog.info("streams", "\(id): Plakettenwerte neu, \(c.entries - list.count) behaltene Quellen abgelaufen")
        }
        guard let b = BestQuality.from(RankedStream.rank(list)) else { return nil }
        keep(id, CachedBest(best: b, entries: list.count), model: model)
        remember(id, b, at: model.streamCache[id]?.at ?? Date())
        return b
    }

    /// Values for the list now in the AppModel cache; bounded like the source cache (entries of lists that left it go).
    private func keep(_ id: String, _ c: CachedBest, model: AppModel) {
        if cache.count >= 2 * StreamPrefetcher.cacheLimit {
            cache = cache.filter { model.cachedStreams(id: $0.key) != nil }
        }
        cache[id] = c
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
