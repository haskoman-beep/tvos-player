import Foundation
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
    func cachedTilePoster(for m: MetaPreview) -> String? {
        guard let t = tileTarget(m, imdb: cachedIMDbID(for: m)) else { return nil }
        return AddonMetaCache.fresh(t.key)?.meta?.poster.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Addon-Poster einer sichtbaren Kachel laden (höchstens 4 Abfragen zugleich). Bricht die Kachel ab
    /// (verschwindet), wird ihre Wartestelle bzw. Abfrage abgemeldet und nichts gemerkt.
    func loadTilePoster(for m: MetaPreview) async -> String? {
        guard tileAddonURL(for: m) != nil else { return nil }
        if let p = cachedTilePoster(for: m) { return p }
        // Runde 2 (Minor 1): Ruhezeit vor dem Platz, schnelles Durchscrollen bricht hier ohne Abfrage ab.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled, await AddonMetaCache.tiles.acquire() else { return nil }
        let p = await tilePosterWithSlot(m)
        await AddonMetaCache.tiles.release()
        return p
    }

    private func tilePosterWithSlot(_ m: MetaPreview) async -> String? {
        var imdb = cachedIMDbID(for: m)
        if tileTarget(m, imdb: imdb) == nil, imdb == nil { imdb = await imdbID(for: m) }
        guard !Task.isCancelled, let t = tileTarget(m, imdb: imdb) else { return nil }
        if let e = AddonMetaCache.fresh(t.key) { return e.meta?.poster }
        let key = t.key
        let flight = AddonMetaCache.join(key, tile: true, start: addonMetaRequest(t.addon, type: m.type, id: t.id))
        let fid = flight.id
        let meta = await AddonMetaFetch.value(of: flight.task, onCancel: {
            Task { @MainActor in AddonMetaCache.leave(key, flight: fid) }
        })
        return meta?.poster.flatMap { $0.isEmpty ? nil : $0 }
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
@MainActor enum AddonMetaCache {
    struct Entry { var at: Date; var meta: MetaDetail? }
    struct Flight { var id = UUID(); var task: Task<MetaDetail?, Never>; var waiters: FlightWaiters }
    static var entries: [String: Entry] = [:]
    static var inFlight: [String: Flight] = [:]
    /// Höchstens 4 Abfragen sichtbarer Kacheln gleichzeitig.
    static let tiles = AsyncLimiter(limit: 4)

    static func key(_ a: InstalledAddon, type: String, id: String) -> String { "\(a.manifestURL)|\(type)|\(id)" }

    /// Gültiger Eintrag: Antwort 6 h, „keine Antwort“ 10 min.
    static func fresh(_ key: String, now: Date = Date()) -> Entry? {
        guard let e = entries[key], now.timeIntervalSince(e.at) < (e.meta == nil ? 600 : 6 * 3600) else { return nil }
        return e
    }

    /// Laufende Abfrage übernehmen oder starten. `tile: false` (Detailseite, Hero, Folgenliste) hält sie bis zum Ende.
    static func join(_ key: String, tile: Bool, start: @escaping @Sendable () async throws -> MetaDetail) -> Flight {
        if var f = inFlight[key] {
            f.waiters.join(tile: tile)
            inFlight[key] = f
            return f
        }
        let id = UUID()
        let task = Task { @MainActor () -> MetaDetail? in
            let outcome = await AddonMetaFetch.run(start)
            if inFlight[key]?.id == id { inFlight[key] = nil }
            switch outcome {
            case .meta(let m): store(key, Entry(at: Date(), meta: m)); return m
            case .failed: store(key, Entry(at: Date(), meta: nil)); return nil
            case .cancelled: return nil
            }
        }
        let f = Flight(id: id, task: task, waiters: FlightWaiters(tile: tile))
        inFlight[key] = f
        return f
    }

    /// Eine Kachel wartet nicht mehr; ohne weitere Wartende wird die Abfrage abgebrochen (nicht gemerkt).
    static func leave(_ key: String, flight: UUID) {
        guard var f = inFlight[key], f.id == flight else { return }
        if f.waiters.leaveTile() { f.task.cancel(); inFlight[key] = nil } else { inFlight[key] = f }
    }

    /// Profilwechsel: alles vergessen, laufende Abfragen abbrechen.
    static func reset() {
        for f in inFlight.values { f.task.cancel() }
        inFlight.removeAll(); entries.removeAll()
    }

    static func store(_ key: String, _ e: Entry) {
        if entries.count >= 300, let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key { entries[oldest] = nil }
        entries[key] = e
    }
}
