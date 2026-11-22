import Foundation

/// Welle E-a: Bilder und Bewertungen vom Metadaten-Addon des Profils.
/// Cinemeta bleibt die Grundlage (Folgenliste, IDs); das Metadaten-Addon liefert Poster/Hintergrund/Logo
/// (z. B. dort eingerichtete Bewertungs-Poster) vor den TMDB-Bildern, Texte kommen weiter aus TMDB in Profilsprache.
public enum MetaImageChoice {
    /// Erstes installiertes Addon mit Metadaten für Typ und ID (Reihenfolge der Addon-Liste); Cinemeta selbst zählt nicht.
    /// Wave W-a: an addon that names its ID prefixes for `meta` (or AIOMetadata) wins over one that takes every ID
    /// (an aggregator's `meta` without prefixes only serves its own items). Within each group the list order counts.
    public static func metadataAddon(in addons: [InstalledAddon], type: String, id: String) -> InstalledAddon? {
        let candidates = addons.filter {
            $0.manifest.id != "com.linvo.cinemeta" && $0.manifest.supports("meta", type: type, id: id)
        }
        return candidates.first { namesMetaPrefixes($0.manifest, type: type) || KnownAddon.isAIOMetadata($0.manifest) }
            ?? candidates.first
    }

    /// Wave W-a: whether a `meta` resource for `type` lists ID prefixes (its own or the manifest's), i.e. the addon
    /// says which IDs it serves instead of taking every ID.
    static func namesMetaPrefixes(_ m: AddonManifest, type: String) -> Bool {
        m.resources.contains { r in
            guard r.name == "meta", (r.types ?? m.types).contains(type) else { return false }
            return !((r.idPrefixes ?? m.idPrefixes) ?? []).isEmpty
        }
    }

    /// Ob ein Addon im Profil Metadaten für IMDb-IDs liefert (für die Einstellungszeile), wie `metadataAddon`:
    /// ID-Präfixe der Ressource, sonst des Manifests; ohne Präfixe gilt jede ID. Reine `tmdb:`-Addons zählen nicht.
    public static func hasMetadataAddon(_ addons: [InstalledAddon]) -> Bool {
        addons.contains { a in
            a.manifest.id != "com.linvo.cinemeta" && a.manifest.resources.contains { r in
                guard r.name == "meta" else { return false }
                guard let p = r.idPrefixes ?? a.manifest.idPrefixes, !p.isEmpty else { return true }
                return p.contains { "tt".hasPrefix($0) || $0.hasPrefix("tt") }
            }
        }
    }

    /// Ein Bild wählen: Addon zuerst (wenn gewünscht und vorhanden), dann TMDB, dann die Grundlage.
    public static func pick(addon: String?, tmdb: String?, base: String?, preferAddon: Bool) -> String? {
        let a = addon.flatMap { $0.isEmpty ? nil : $0 }
        if preferAddon, let a { return a }
        return tmdb ?? base ?? a
    }

    /// Zusammenführen: `base` (Cinemeta, sonst das Addon selbst), TMDB-Übersetzung für Texte, Bilder nach `pick`.
    /// Hintergrund wie bisher: vorhandener zuerst (Cinemeta), TMDB nur als Ersatz – außer das Addon liefert einen.
    /// `imdbRating`: Addon zuerst, sonst Cinemeta.
    public static func merge(base: MetaDetail?, addon: MetaDetail?, localized l: LocalizedMeta?, preferAddonImages: Bool) -> MetaDetail? {
        guard var m = base ?? addon else { return nil }
        let useAddon = preferAddonImages && addon != nil
        if let l {
            m.name = l.name ?? m.name
            m.description = l.overview ?? m.description
            if let g = l.genres, !g.isEmpty { m.genres = g }
        }
        m.poster = pick(addon: addon?.poster, tmdb: l?.poster, base: base?.poster, preferAddon: useAddon)
        m.logo = pick(addon: addon?.logo, tmdb: l?.logo, base: base?.logo, preferAddon: useAddon)
        m.background = pick(addon: addon?.background, tmdb: base?.background ?? l?.background, base: nil, preferAddon: useAddon)
        m.imdbRating = addon?.imdbRating ?? base?.imdbRating
        return m
    }
}
