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
        let storage = DefaultsStorage()
        store = ProfileStore(storage: storage)
        stored = store.load()
        progressStore = ProgressStore(storage: storage)
        progress = progressStore.load(profile: profile.id)
    }

    // MARK: Fortschritt

    func recordProgress(_ r: PlayRequest, position: Double, duration: Double) {
        progress.record(id: r.id, item: r.item, season: r.season, episode: r.episode, position: position, duration: duration)
        if progress.isWatched(r.id), let n = r.nextRequest, let s = n.season, let e = n.episode {
            progress.recordNextUp(id: n.id, item: n.item, season: s, episode: e)
        }
        do { try progressStore.save(progress, profile: profile.id) } catch { lastError = "Fortschritt nicht gespeichert: \(error)" }
        scrobbleProgress(r, fraction: duration > 0 ? position / duration : 0)
    }

    /// Player wird verlassen: Trakt/Simkl bekommen den letzten Stand.
    func endPlayback(_ r: PlayRequest) {
        guard let s = scrobbling, s.request.id == r.id else { return }
        scrobbling = nil
        sendScrobble(.stop, s.request, fraction: s.fraction)
    }

    // MARK: Trakt / Simkl

    static let syncServices = ["trakt", "simkl"]
    private var scrobbling: (request: PlayRequest, fraction: Double)?

    var trakt: TraktClient? {
        guard let id = profile.apiKeys["trakt_id"], let sec = profile.apiKeys["trakt_secret"], !id.isEmpty, !sec.isEmpty else { return nil }
        return TraktClient(clientID: id, clientSecret: sec)
    }

    var simkl: SimklClient? {
        guard let id = profile.apiKeys["simkl_id"], !id.isEmpty else { return nil }
        return SimklClient(clientID: id)
    }

    func hasClient(_ s: String) -> Bool { s == "trakt" ? trakt != nil : simkl != nil }
    func isConnected(_ s: String) -> Bool { profile.syncTokens[s] != nil && hasClient(s) }

    func disconnect(_ s: String) { update { $0.syncTokens[s] = nil }; cache.removeAll() }

    func startLogin(_ s: String) async throws -> DeviceCode {
        if s == "trakt", let trakt { return try await trakt.deviceCode() }
        if s == "simkl", let simkl { return try await simkl.deviceCode() }
        throw APIError.notConnected
    }

    /// Einmal nachfragen; bei Erfolg wird die Anmeldung im Profil gespeichert.
    func pollLogin(_ s: String, _ code: DeviceCode) async -> DevicePoll {
        let r: DevicePoll
        do {
            if s == "trakt", let trakt { r = try await trakt.poll(code) }
            else if s == "simkl", let simkl { r = try await simkl.poll(code) }
            else { return .failed(0) }
        } catch { return .pending }
        if case .success(let t) = r {
            update { $0.syncTokens[s] = t }
            cache.removeAll()
            await syncRemoteProgress()
        }
        return r
    }

    /// Gültige Anmeldung, Trakt-Token wird rechtzeitig erneuert.
    func token(_ s: String) async -> SyncToken? {
        guard hasClient(s), var t = profile.syncTokens[s] else { return nil }
        if s == "trakt", t.needsRefresh(), let trakt, let n = try? await trakt.refresh(t) {
            t = n; update { $0.syncTokens[s] = n }
        }
        return t
    }

    /// Angefangenes aus dem gewählten Dienst holen und mit dem lokalen Stand zusammenführen.
    func syncRemoteProgress() async {
        let s: String
        switch profile.progressSource { case .local: return; case .trakt: s = "trakt"; case .simkl: s = "simkl" }
        guard let t = await token(s) else { return }
        do {
            let remote = s == "trakt" ? try await trakt?.playback(token: t) : try await simkl?.playback(token: t)
            progress.merge(remote: remote ?? [])
            try progressStore.save(progress, profile: profile.id)
        } catch { lastError = "\(s == "trakt" ? "Trakt" : "Simkl") nicht erreichbar: \(error)" }
    }

    private func scrobbleProgress(_ r: PlayRequest, fraction: Double) {
        if let s = scrobbling, s.request.id != r.id { sendScrobble(.stop, s.request, fraction: s.fraction); scrobbling = nil }
        if scrobbling == nil { sendScrobble(.start, r, fraction: fraction) }
        scrobbling = (r, fraction)
        if fraction >= ProgressBook.finishedAt { sendScrobble(.stop, r, fraction: fraction); scrobbling = nil }
    }

    private func sendScrobble(_ a: ScrobbleAction, _ r: PlayRequest, fraction: Double) {
        let imdb = r.item.id
        guard imdb.hasPrefix("tt") else { return }
        let services = Self.syncServices.filter(isConnected)
        guard !services.isEmpty else { return }
        Task {
            for s in services {
                guard let t = await token(s) else { continue }
                if s == "trakt" { try? await trakt?.scrobble(a, imdb: imdb, season: r.season, episode: r.episode, percent: fraction * 100, token: t) }
                else { try? await simkl?.scrobble(a, imdb: imdb, season: r.season, episode: r.episode, percent: fraction * 100, token: t) }
            }
        }
    }

    private func watchlistItems() async throws -> [MetaPreview] {
        var order = Self.syncServices
        if profile.progressSource == .simkl { order.reverse() }
        for s in order {
            guard let t = await token(s) else { continue }
            if s == "trakt", let trakt { return try await trakt.watchlist(token: t) }
            if s == "simkl", let simkl { return try await simkl.watchlist(token: t) }
        }
        return []
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
        Task { await syncRemoteProgress() }
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
            case .trakt(let user, let list):
                guard let trakt else { return [] }
                out = try await trakt.list(user: user, slug: list, token: await token("trakt"))
            case .watchlist:
                out = try await watchlistItems()
            case .continueWatching:
                out = []
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
                if let s = TMDBLink.source(from: l) ?? TraktLink.source(from: l) { update { $0.home.rows.append(HomeRow(content: .list(s), style: .poster)) } }
                else { lastError = "Link nicht erkannt: \(l)" }
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
