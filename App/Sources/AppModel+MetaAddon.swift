import Foundation
import UIKit
import PlayerCore

/// Welle E-a: Metadaten-Addon des Profils (Bilder, Bewertung) und gewählte Bewertungsquellen.
/// Cinemeta bleibt die Grundlage (Folgenliste, IDs), Texte kommen aus TMDB in Profilsprache.
extension AppModel {
    /// Cinemeta und Metadaten-Addon parallel, dazu die TMDB-Übersetzung; Auswahl in `MetaImageChoice.merge`.
    func mergedMeta(type: String, imdb: String) async -> MetaDetail? {
        let client = addons, cine = Self.cinemeta
        async let base = Self.fetchMeta(client, cine, type: type, id: imdb)
        async let fromAddon = addonMeta(type: type, imdb: imdb)
        let l = await localized(imdb: imdb, series: type == "series")
        return MetaImageChoice.merge(base: await base, addon: await fromAddon, localized: l,
                                     preferAddonImages: profile.appearance.titles.addonImages)
    }

    nonisolated static func fetchMeta(_ client: AddonClient, _ addon: InstalledAddon, type: String, id: String) async -> MetaDetail? {
        try? await client.meta(addon, type: type, id: id)
    }

    /// Antwort des Metadaten-Addons (Cache 6 h, Fehler 10 min); nil ohne passendes Addon.
    /// Nacharbeit 1: höchstens `AddonMetaFetch.callerWaitSeconds` warten; die geteilte Abfrage läuft weiter
    /// und füllt den Cache für den nächsten Aufruf. Abbrüche werden nicht gemerkt.
    func addonMeta(type: String, imdb: String) async -> MetaDetail? {
        guard let a = MetaImageChoice.metadataAddon(in: profile.addons, type: type, id: imdb) else { return nil }
        let key = AddonMetaCache.key(a, type: type, id: imdb)
        if let e = AddonMetaCache.fresh(key) { return e.meta }
        let flight = AddonMetaCache.join(key, tile: false, start: addonMetaRequest(a, type: type, id: imdb))
        return await AddonMetaFetch.wait(for: flight.task, atMost: AddonMetaFetch.callerWaitSeconds)
    }

    /// Eine Abfrage beim Addon mit Protokollzeile (läuft als geteilte Aufgabe in `AddonMetaCache`).
    private func addonMetaRequest(_ a: InstalledAddon, type: String, id: String) -> @Sendable () async throws -> MetaDetail {
        let client = addons
        return {
            let m = try await client.meta(a, type: type, id: id)
            let line = "\(a.manifest.name) \(id): Poster \(m.poster == nil ? "nein" : "ja") · Hintergrund \(m.background == nil ? "nein" : "ja") · Logo \(m.logo == nil ? "nein" : "ja") · IMDb \(m.imdbRating ?? "-")"
            await MainActor.run { RemoteLog.info("meta", line) }
            return m
        }
    }

    /// Nacharbeit 1 (Nutzerentscheid): Kacheln aus TMDB-Reihen bekommen das Poster des Metadaten-Addons.
    /// Ziel: Addon und ID (die TMDB-ID selbst, falls das Addon sie bedient, sonst die IMDb-ID); nil bei Schalter aus.
    private func tileTarget(_ m: MetaPreview, imdb: String?) -> (key: String, addon: InstalledAddon, id: String)? {
        guard profile.appearance.titles.addonImages, m.id.hasPrefix("tmdb:") else { return nil }
        for id in [m.id, imdb].compactMap({ $0 }) {
            if let a = MetaImageChoice.metadataAddon(in: profile.addons, type: m.type, id: id) {
                return (AddonMetaCache.key(a, type: m.type, id: id), a, id)
            }
        }
        return nil
    }

    /// Metadaten-Addon, das eine TMDB-Kachel bedienen kann (gleiche Bedingung wie `tileTarget`): die `tmdb:`-ID
    /// direkt, sonst ein Addon für IMDb-IDs. nil bei Schalter aus oder ohne passendes Addon.
    func tileAddonURL(for m: MetaPreview) -> String? {
        guard profile.appearance.titles.addonImages, m.id.hasPrefix("tmdb:") else { return nil }
        let a = MetaImageChoice.metadataAddon(in: profile.addons, type: m.type, id: m.id)
            ?? MetaImageChoice.metadataAddon(in: profile.addons, type: m.type, id: cachedIMDbID(for: m) ?? "tt")
        return a?.manifestURL
    }

    /// Runde 2 (Minor 2): Addon-Antwort steht noch aus (Wartezeit abgelaufen) – Ergebnis dann nicht dauerhaft merken.
    func addonMetaPending(type: String, imdb: String) -> Bool {
        guard profile.appearance.titles.addonImages,
              let a = MetaImageChoice.metadataAddon(in: profile.addons, type: type, id: imdb) else { return false }
        return AddonMetaCache.fresh(AddonMetaCache.key(a, type: type, id: imdb)) == nil
    }

    /// Synchroner Cache-Treffer (kein Flackern beim Neuzeichnen); nil = TMDB-Poster zeigen.
    /// Build 8 (poster): memory first, then the disk map (`PosterURLMap`, read at start).
    func cachedTilePoster(for m: MetaPreview) -> String? {
        guard let t = tileTarget(m, imdb: cachedIMDbID(for: m)), let hit = AddonMetaCache.tileHit(t.key) else { return nil }
        if case .poster(let url) = hit { return url }
        return nil
    }

    /// Addon-Poster einer sichtbaren Kachel laden (höchstens `AddonMetaCache.tiles.limit` Abfragen zugleich).
    /// Build 8 (poster): a title the block warm-up already queued is joined at once (moved ahead of the warm-up);
    /// otherwise the 300 ms rest stays (fast scrolling sends nothing). When the tile goes, a request not yet sent is
    /// dropped; one already sent runs on and fills the cache (`FlightWaiters`).
    func loadTilePoster(for m: MetaPreview) async -> String? {
        guard tileAddonURL(for: m) != nil else { return nil }
        if let t = tileTarget(m, imdb: cachedIMDbID(for: m)), let hit = AddonMetaCache.tileHit(t.key) {
            if case .poster(let url) = hit { return url }
            return nil
        }
        let queued = tileTarget(m, imdb: cachedIMDbID(for: m)).map { AddonMetaCache.inFlight[$0.key] != nil } ?? false
        if !queued {
            // Runde 2 (Minor 1): Ruhezeit vor der Abfrage, schnelles Durchscrollen bricht hier ohne Abfrage ab.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return nil }
        }
        return await tilePoster(m)
    }

    private func tilePoster(_ m: MetaPreview) async -> String? {
        var imdb = cachedIMDbID(for: m)
        if tileTarget(m, imdb: imdb) == nil, imdb == nil { imdb = await imdbID(for: m) }
        guard !Task.isCancelled, let t = tileTarget(m, imdb: imdb) else { return nil }
        if let hit = AddonMetaCache.tileHit(t.key) {
            if case .poster(let url) = hit { return url }
            return nil
        }
        let key = t.key
        let flight = AddonMetaCache.join(key, waiter: .tile, start: addonMetaRequest(t.addon, type: m.type, id: t.id))
        let fid = flight.id
        let meta = await AddonMetaFetch.value(of: flight.task, onCancel: {
            Task { @MainActor in AddonMetaCache.leave(key, flight: fid) }
        })
        return meta?.poster.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Build 8 (poster): a page block landed (genre/studio grid): ask the addon for the posters of all its TMDB
    /// titles now, without the tiles' 300 ms rest, behind the visible tiles (low urgency), and put each poster picture
    /// into the image disk cache. One `poster` line per block (`OverlayWarmTally`).
    func warmTilePosters(_ items: [MetaPreview]) {
        guard profile.appearance.titles.addonImages, !items.isEmpty else { return }
        let ids = OverlayWarmPlan.pick(items.map(\.id), pending: AddonMetaCache.warmPending)
        guard !ids.isEmpty else { return }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let picked = ids.compactMap { byID[$0] }.filter { tileAddonURL(for: $0) != nil }
        guard !picked.isEmpty else { return }
        let neededWidth = Self.tilePosterSourceWidth(cardScale: profile.appearance.cardSize.scale)
        let profileID = profile.id
        AddonMetaCache.warmPending += picked.count
        Task { @MainActor in
            let t0 = ContinuousClock.now
            var tally = OverlayWarmTally(total: picked.count)
            await withTaskGroup(of: (OverlayWarmTally.Source, String?).self) { group in
                for m in picked {
                    group.addTask { @MainActor in await self.warmTilePoster(m, neededWidth: neededWidth) }
                }
                for await (source, poster) in group {
                    AddonMetaCache.warmPending = max(0, AddonMetaCache.warmPending - 1)
                    tally.record(source, found: poster != nil)
                }
            }
            guard profile.id == profileID else { return }
            RemoteLog.info("poster", tally.line(ms: Metric.ms(t0.duration(to: ContinuousClock.now))))
        }
    }

    /// One title of a warmed block: its addon poster (cache, disk map or a new request) and the picture on disk.
    private func warmTilePoster(_ m: MetaPreview, neededWidth: Int) async -> (OverlayWarmTally.Source, String?) {
        var imdb = cachedIMDbID(for: m)
        if tileTarget(m, imdb: imdb) == nil, imdb == nil { imdb = await imdbID(for: m) }
        guard let t = tileTarget(m, imdb: imdb) else { return (.failed, nil) }
        if let hit = AddonMetaCache.tileHit(t.key) {
            guard case .poster(let url) = hit else { return (.cache, nil) }
            await Self.warmPicture(url, neededWidth: neededWidth)
            return (.cache, url)
        }
        let flight = AddonMetaCache.join(t.key, waiter: .warm, start: addonMetaRequest(t.addon, type: m.type, id: t.id))
        guard let meta = await flight.task.value else { return (.failed, nil) }
        let poster = meta.poster.flatMap { $0.isEmpty ? nil : $0 }
        AddonMetaCache.notePosterShape(poster, id: t.id)
        if let poster { await Self.warmPicture(poster, neededWidth: neededWidth) }
        return (.network, poster)
    }

    private static func warmPicture(_ url: String, neededWidth: Int) async {
        guard let u = URL(string: url) else { return }
        await ImagePipeline.shared.warmDisk(u, neededWidth: neededWidth)
    }

    /// Source width a poster tile asks the picture service for (as `RemoteImage` with the tile's exact target).
    static func tilePosterSourceWidth(cardScale: CGFloat) -> Int {
        let tile = PosterSize.tileSize(.poster, scale: cardScale)
        let scale = UITraitCollection.current.displayScale
        let t = ImageTarget(points: tile.width, tile.height, scale: scale > 0 ? scale : 1, fit: false, stepped: false)
        return t?.neededSourceWidth ?? Int(tile.width)
    }

    /// Nacharbeit 1 (I3): Bild-/Bewertungswahl geändert → zusammengeführte Hero-Daten neu holen.
    func titleImagesChanged() {
        HeroDetailsCache.all.removeAll()
    }

    /// Ob im Profil ein Addon Metadaten liefert (Einstellungszeile „Bilder vom Metadaten-Addon“).
    var hasMetadataAddon: Bool { MetaImageChoice.hasMetadataAddon(profile.addons) }

    /// Bewertungs-Plaketten: Werte aus den Metadaten zuerst, MDBList ergänzt; nur die gewählten Quellen.
    func ratingBadges(imdbRating: String?, mdblist: ExternalRatings?) -> [RatingBadge] {
        let merged = RatingSelection.merge(meta: RatingSelection.metaValues(imdbRating: imdbRating), mdblist: mdblist)
        return RatingSelection.badges(merged, selected: profile.appearance.titles.ratingSources)
    }
}

/// Antworten des Metadaten-Addons je Addon/Typ/ID, höchstens 300 Einträge (älteste raus),
/// dazu laufende Abfragen je Schlüssel (geteilt; eine Kachel-Abfrage endet, wenn keine Kachel mehr wartet).
/// Build 8 (poster): tile and warm-up requests take their slot inside the shared request (so a tile that goes does
/// not free a slot while its request still runs); the poster addresses also go to a disk map (`PosterURLMap`).
@MainActor enum AddonMetaCache {
    struct Entry { var at: Date; var meta: MetaDetail? }
    struct Flight { var id = UUID(); var task: Task<MetaDetail?, Never>; var waiters: FlightWaiters }
    /// Build 8: who waits for a request. `.tile` and `.warm` share the tile slots (tiles first), `.pinned` (detail
    /// page, hero, episode list) asks at once.
    enum Waiter { case tile, warm, pinned }
    static var entries: [String: Entry] = [:]
    static var inFlight: [String: Flight] = [:]
    /// Build 8 (poster): 8 instead of 4 requests at once (tiles and block warm-up together). Still a cap: one
    /// AIOMetadata instance serves every tile of a page, and a block is 20 titles.
    static let tiles = AsyncLimiter(limit: 8)
    /// Build 8: warm-up titles not yet answered (`OverlayWarmPlan.maxPending`).
    static var warmPending = 0

    static func key(_ a: InstalledAddon, type: String, id: String) -> String { "\(a.manifestURL)|\(type)|\(id)" }

    /// Gültiger Eintrag: Antwort 6 h, „keine Antwort“ 10 min.
    static func fresh(_ key: String, now: Date = Date()) -> Entry? {
        guard let e = entries[key], now.timeIntervalSince(e.at) < (e.meta == nil ? 600 : 6 * 3600) else { return nil }
        return e
    }

    /// Build 8 (poster): the tile's answer from memory (a failed request counts as "no poster" for 10 min, as before),
    /// else from the disk map. nil = ask the addon.
    static func tileHit(_ key: String) -> PosterURLMap.Hit? {
        if let e = fresh(key) {
            guard let p = e.meta?.poster, !p.isEmpty else { return .noPoster }
            return .poster(p)
        }
        return posters.lookup(key)
    }

    /// Laufende Abfrage übernehmen oder starten. `.pinned` (Detailseite, Hero, Folgenliste) hält sie bis zum Ende.
    static func join(_ key: String, tile: Bool, start: @escaping @Sendable () async throws -> MetaDetail) -> Flight {
        join(key, waiter: tile ? .tile : .pinned, start: start)
    }

    static func join(_ key: String, waiter: Waiter, start: @escaping @Sendable () async throws -> MetaDetail) -> Flight {
        if var f = inFlight[key] {
            switch waiter {
            case .tile: f.waiters.join(tile: true)
            case .pinned: f.waiters.join(tile: false)
            case .warm: f.waiters.joinWarm()
            }
            inFlight[key] = f
            // A visible tile (or the detail page) joining a queued warm-up moves it ahead.
            if waiter != .warm, f.waiters.warm, !f.waiters.started { let id = f.id; Task { await tiles.promote(id) } }
            return f
        }
        let id = UUID()
        let limited = waiter != .pinned
        let urgent = waiter == .tile
        let task = Task { @MainActor () -> MetaDetail? in
            if limited {
                guard await tiles.acquire(ticket: id, urgent: urgent) else {
                    if inFlight[key]?.id == id { inFlight[key] = nil }
                    return nil
                }
                if inFlight[key]?.id == id { inFlight[key]?.waiters.markStarted() }
            }
            let outcome = await AddonMetaFetch.run(start)
            if limited { await tiles.release() }
            if inFlight[key]?.id == id { inFlight[key] = nil }
            switch outcome {
            case .meta(let m): store(key, Entry(at: Date(), meta: m)); return m
            case .failed: store(key, Entry(at: Date(), meta: nil)); return nil
            case .cancelled: return nil
            }
        }
        let waiters: FlightWaiters
        switch waiter {
        case .tile: waiters = FlightWaiters(tile: true)
        case .warm: waiters = FlightWaiters(warm: true)
        case .pinned: waiters = FlightWaiters(warm: false)
        }
        var f = Flight(id: id, task: task, waiters: waiters)
        if !limited { f.waiters.markStarted() }
        inFlight[key] = f
        return f
    }

    /// Eine Kachel wartet nicht mehr; ohne weitere Wartende wird eine noch nicht gesendete Abfrage abgebrochen.
    static func leave(_ key: String, flight: UUID) {
        guard var f = inFlight[key], f.id == flight else { return }
        if f.waiters.leaveTile() { f.task.cancel(); inFlight[key] = nil } else { inFlight[key] = f }
    }

    /// Profilwechsel: alles vergessen, laufende Abfragen abbrechen. Build 8: the disk map stays (its keys carry the
    /// addon address, so another profile's addon never matches them).
    static func reset() {
        for f in inFlight.values { f.task.cancel() }
        inFlight.removeAll(); entries.removeAll()
    }

    static func store(_ key: String, _ e: Entry) {
        if entries.count >= 300, let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key { entries[oldest] = nil }
        entries[key] = e
        // Build 8: answers go to the disk map too (failures do not).
        if let m = e.meta {
            posters.store(key, poster: m.poster, now: e.at)
            schedulePosterSave()
        }
    }

    // MARK: Build 8 (poster): disk map

    static var posters = PosterURLMap()
    private static var posterLoad: Task<PosterURLMap?, Never>?
    private static var posterSave: Task<Void, Never>?
    private static let posterFile = "kachel-poster.json"
    private static var posterFiles: FileBlobStorage {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true)
        return FileBlobStorage(directory: dir)
    }

    /// Start: read the disk map off the main thread; what this launch learned meanwhile wins.
    static func loadPosterMap() {
        guard posterLoad == nil else { return }
        let files = posterFiles, name = posterFile
        let t0 = ContinuousClock.now
        let task = Task.detached(priority: .userInitiated) { () -> PosterURLMap? in
            guard let data = files.read(name) else { return nil }
            guard let m = PosterURLMap.decode(data) else { files.remove(name); return nil }
            return m
        }
        posterLoad = task
        Task { @MainActor in
            guard let disk = await task.value else { return }
            posters.merge(disk)
            let ms = Metric.ms(t0.duration(to: ContinuousClock.now))
            RemoteLog.info("poster", "Plattenliste: \(disk.count) Kachel-Poster geladen (\(ms) ms)")
        }
    }

    /// Written 5 s after the last answer, off the main thread; not before the start read has been merged.
    private static func schedulePosterSave() {
        guard posterSave == nil else { return }
        posterSave = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            _ = await posterLoad?.value
            posterSave = nil
            guard posters.dirty, let data = posters.encoded() else { return }
            let files = posterFiles, name = posterFile
            await Task.detached(priority: .utility) { try? files.write(name, data) }.value
        }
    }

    /// Build 8 (poster, point 4): whether the addon's poster addresses carry the title id (a template could then
    /// skip the per-title request). Logged once per launch, host only (addon addresses can carry configuration).
    private static var shapeLogged = false
    static func notePosterShape(_ poster: String?, id: String) {
        guard !shapeLogged, let poster, let host = URL(string: poster)?.host else { return }
        shapeLogged = true
        let bare = id.hasPrefix("tmdb:") ? String(id.dropFirst(5)) : id
        let carries = poster.contains(bare) ? "ja" : "nein"
        RemoteLog.info("poster", "Addon-Poster von \(host) · Adresse enthält die ID: \(carries)")
    }
}
