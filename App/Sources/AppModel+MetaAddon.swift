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
    func addonMeta(type: String, imdb: String) async -> MetaDetail? {
        guard let a = MetaImageChoice.metadataAddon(in: profile.addons, type: type, id: imdb) else { return nil }
        let key = "\(a.manifestURL)|\(type)|\(imdb)"
        let now = Date()
        if let e = AddonMetaCache.entries[key], now.timeIntervalSince(e.at) < (e.meta == nil ? 600 : 6 * 3600) { return e.meta }
        let m = try? await addons.meta(a, type: type, id: imdb)
        AddonMetaCache.store(key, AddonMetaCache.Entry(at: now, meta: m))
        RemoteLog.info("meta", "\(a.manifest.name) \(imdb): " + (m.map {
            "Poster \($0.poster == nil ? "nein" : "ja") · Hintergrund \($0.background == nil ? "nein" : "ja") · Logo \($0.logo == nil ? "nein" : "ja") · IMDb \($0.imdbRating ?? "-")"
        } ?? "keine Antwort"))
        return m
    }

    /// Ob im Profil ein Addon Metadaten liefert (Einstellungszeile „Bilder vom Metadaten-Addon“).
    var hasMetadataAddon: Bool { MetaImageChoice.hasMetadataAddon(profile.addons) }

    /// Bewertungs-Plaketten: Werte aus den Metadaten zuerst, MDBList ergänzt; nur die gewählten Quellen.
    func ratingBadges(imdbRating: String?, mdblist: ExternalRatings?) -> [RatingBadge] {
        let merged = RatingSelection.merge(meta: RatingSelection.metaValues(imdbRating: imdbRating), mdblist: mdblist)
        return RatingSelection.badges(merged, selected: profile.appearance.titles.ratingSources)
    }
}

/// Antworten des Metadaten-Addons je Addon/Typ/ID, höchstens 300 Einträge (älteste raus).
@MainActor enum AddonMetaCache {
    struct Entry { var at: Date; var meta: MetaDetail? }
    static var entries: [String: Entry] = [:]

    static func store(_ key: String, _ e: Entry) {
        if entries.count >= 300, let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key { entries[oldest] = nil }
        entries[key] = e
    }
}
