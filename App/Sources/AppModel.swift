import SwiftUI
import PlayerCore

/// App-Zustand: Profile (persistiert), Clients, Katalog-Cache.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var stored: StoredProfiles
    @Published var lastError: String?
    @Published var notice: String?
    let store: ProfileStore
    let progressStore: ProgressStore
    /// Fortschritt des aktiven Profils.
    @Published private(set) var progress = ProgressBook()
    let addons = AddonClient()
    private var cache: [String: [MetaPreview]] = [:]

    /// Cinemeta liefert Metadaten/Folgenlisten für IMDb-IDs (kostenlos, ohne Key).
    static let cinemeta = InstalledAddon(
        manifestURL: "https://v3-cinemeta.strem.io/manifest.json",
        manifest: AddonManifest(id: "com.linvo.cinemeta", name: "Cinemeta", version: "3",
                                resources: [AddonResource(name: "meta")], types: ["movie", "series"], idPrefixes: ["tt"]))

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true)
        store = ProfileStore(directory: dir)
        stored = store.load()
        progressStore = ProgressStore(directory: dir)
        progress = progressStore.load(profile: profile.id)
    }

    // MARK: Fortschritt

    func recordProgress(_ r: PlayRequest, position: Double, duration: Double) {
        progress.record(id: r.id, item: r.item, season: r.season, episode: r.episode, position: position, duration: duration)
        do { try progressStore.save(progress, profile: profile.id) } catch { lastError = "Fortschritt nicht gespeichert: \(error)" }
    }

    var profile: Profile { stored.active ?? Profile.makeDefault() }
    var hasMultipleProfiles: Bool { stored.profiles.count > 1 }

    func update(_ change: (inout Profile) -> Void) {
        guard let i = stored.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        change(&stored.profiles[i])
        save()
    }

    func save() {
        do { try store.save(stored) } catch { lastError = "Speichern fehlgeschlagen: \(error)" }
    }

    // MARK: Profile

    func switchProfile(_ id: UUID) {
        stored.activeProfileID = id; cache.removeAll(); save()
        progress = progressStore.load(profile: id)
    }

    func addProfile(name: String) {
        let p = Profile.makeDefault(name: name)
        stored.profiles.append(p)
        switchProfile(p.id)
    }

    func deleteProfile(_ id: UUID) {
        guard stored.profiles.count > 1 else { return }
        stored.profiles.removeAll { $0.id == id }
        if stored.activeProfileID == id { stored.activeProfileID = stored.profiles.first?.id }
        save()
    }

    // MARK: Addons

    func installAddon(_ url: String) async {
        do {
            let a = try await addons.install(manifestURL: url)
            update { p in
                p.addons.removeAll { $0.manifestURL == a.manifestURL }
                p.addons.append(a)
            }
            cache.removeAll()
        } catch { lastError = "Addon nicht geladen: \(error)" }
    }

    // MARK: Import

    func importNuvio(from urlString: String) async {
        do {
            guard let url = URL(string: urlString) else { throw AddonError.invalidManifestURL(urlString) }
            importNuvio(data: try await URLSessionFetcher().data(from: url))
        } catch { lastError = "Import fehlgeschlagen: \(error)" }
    }

    func importNuvio(data: Data) {
        do {
            let r = try NuvioImport.parse(data)
            update { p in
                for c in r.collections {
                    if let i = p.collections.firstIndex(where: { $0.title == c.title }) {
                        p.collections[i].folders = NuvioImport.mergeFolders(p.collections[i].folders, c.folders)
                    } else { p.collections.append(c) }
                }
            }
        } catch { lastError = "Import fehlgeschlagen: \(error)" }
    }

    /// Fertiges Paket oder anderes Collection-Objekt ins Profil übernehmen (falls noch nicht da).
    func addCollection(_ c: MediaCollection) {
        update { p in if !p.collections.contains(where: { $0.id == c.id }) { p.collections.append(c) } }
    }

    func collection(_ id: String) -> MediaCollection? { profile.collections.first { $0.id == id } }

    // MARK: Kataloge

    var tmdb: TMDBClient? {
        guard let k = profile.apiKeys["tmdb"], !k.isEmpty else { return nil }
        return TMDBClient(apiKey: k, language: profile.language == .de ? "de-DE" : "en-US")
    }

    func items(_ source: CatalogSource) async -> [MetaPreview] {
        if case .continueWatching = source.kind { return progress.continueWatching().map(\.item) }
        if let c = cache[source.id] { return c }
        var out: [MetaPreview] = []
        do {
            switch source.kind {
            case .tmdbDiscover, .tmdbList, .tmdbCompany, .tmdbCollection:
                guard let tmdb else { return [] }
                out = try await tmdb.items(for: source)
            case .addon(let addonId, let catalogId, let type):
                guard let a = profile.addons.first(where: { $0.manifest.id == addonId }) else { return [] }
                out = try await addons.catalog(a, type: type, id: catalogId)
            case .trakt, .continueWatching, .watchlist:
                out = [] // P4
            }
        } catch { return [] }
        cache[source.id] = out
        return out
    }

    /// Streams brauchen IMDb-IDs; TMDB-Einträge werden übersetzt.
    func imdbID(for m: MetaPreview) async -> String? {
        if m.id.hasPrefix("tt") { return m.id }
        guard m.id.hasPrefix("tmdb:"), let n = Int(m.id.dropFirst(5)), let tmdb else { return nil }
        return try? await tmdb.imdbID(tmdbID: n, type: m.type == "series" ? .series : .movie)
    }

    func meta(type: String, imdb: String) async -> MetaDetail? {
        try? await addons.meta(Self.cinemeta, type: type, id: imdb)
    }

    func streams(type: String, id: String) async -> [(addon: String, stream: StreamItem)] {
        let all = await addons.streams(from: profile.addons, type: type, id: id)
        return all.flatMap { r in playableStreams(r.streams).map { (r.addon.manifest.name, $0) } }
    }

    // MARK: Handy-Eingabe

    func backupData() -> Data { (try? store.exportData(stored)) ?? Data() }

    func apply(_ commands: [PhoneCommand]) async {
        for c in commands {
            switch c {
            case .addAddon(let u): await installAddon(u)
            case .setKey(let s, let v): update { $0.apiKeys[s] = v }; cache.removeAll()
            case .importNuvioURL(let u): await importNuvio(from: u)
            case .importNuvioJSON(let d): importNuvio(data: d)
            case .addTMDBLink(let l):
                if let s = TMDBLink.source(from: l) { update { $0.home.rows.append(HomeRow(content: .list(s), style: .poster)) } }
                else { lastError = "TMDB-Link nicht erkannt: \(l)" }
            case .importBackup(let d):
                do {
                    stored = try store.importData(d); save(); cache.removeAll()
                    progress = progressStore.load(profile: profile.id)
                } catch { lastError = "Sicherung ungültig: \(error)" }
            }
        }
        if lastError == nil { notice = "\(commands.count) Eingabe(n) vom Handy übernommen." }
    }
}
