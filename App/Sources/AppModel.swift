import SwiftUI
import PlayerCore

/// App-Zustand: Profile (persistiert), Clients, Katalog-Cache.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var stored: StoredProfiles
    @Published var lastError: String? { didSet { if let e = lastError { RemoteLog.error("fehler", e) } } }
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
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        RemoteLog.info("start", "App \(v) · \(stored.profiles.count) Profil(e) · Addons \(profile.addons.map(\.manifest.name)) · Reihen \(profile.home.rows.count) · Quelle \(profile.progressSource.rawValue)")
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

    /// Gewählte Quelle merken, damit Weiterschauen sie direkt startet.
    func rememberSource(_ r: PlayRequest, stream: StreamItem, addon: String) {
        progress.rememberSource(stream, addon: addon, for: r.id)
        do { try progressStore.save(progress, profile: profile.id) } catch { lastError = "Quelle nicht gespeichert: \(error)" }
    }

    /// Player wird verlassen: Trakt/Simkl bekommen den letzten Stand.
    func endPlayback(_ r: PlayRequest) {
        sendScrobble(scrobbler.end(id: r.id))
    }

    /// Player pausiert: Trakt/Simkl bekommen `pause`; der nächste Fortschritt schickt wieder `start`.
    func scrobblePause(_ r: PlayRequest) {
        guard Self.syncServices.contains(where: isConnected) else { return }
        sendScrobble(scrobbler.pause(id: r.id))
    }

    // MARK: Trakt / Simkl

    static let syncServices = ["trakt", "simkl"]
    private var scrobbler = ScrobbleTracker<PlayRequest>(finishedAt: ProgressBook.finishedAt)
    /// Scrobbles laufen nacheinander, damit stop/start/pause in der richtigen Reihenfolge ankommen.
    private var scrobbleChain: Task<Void, Never>?
    /// Laufende Trakt-Erneuerung; gleichzeitige Aufrufer warten auf dieselbe.
    private var traktRefresh: Task<SyncToken?, Never>?

    var trakt: TraktClient? {
        guard let id = profile.apiKeys["trakt_id"], let sec = profile.apiKeys["trakt_secret"], !id.isEmpty, !sec.isEmpty else { return nil }
        return TraktClient(clientID: id, clientSecret: sec, onUnauthorized: { [weak self] old in await self?.refreshTrakt(after: old) })
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
        RemoteLog.info("sync", "\(s) Login: \(r)".replacingOccurrences(of: #"accessToken: \"[^\"]*\""#, with: "accessToken: …", options: .regularExpression))
        if case .success(let t) = r {
            update { $0.syncTokens[s] = t }
            cache.removeAll()
            await syncRemoteProgress()
        }
        return r
    }

    /// Gültige Anmeldung, Trakt-Token wird rechtzeitig erneuert.
    func token(_ s: String) async -> SyncToken? {
        guard hasClient(s), let t = profile.syncTokens[s] else { return nil }
        if s == "trakt", t.needsRefresh() { return await refreshTrakt(after: t) ?? t }
        return t
    }

    /// Trakt-Token erneuern; nur eine Erneuerung zur Zeit (der Refresh-Token rotiert).
    /// Hat ein anderer Aufrufer `old` schon ersetzt, wird das neue Token zurückgegeben.
    func refreshTrakt(after old: SyncToken) async -> SyncToken? {
        if let running = traktRefresh { return await running.value }
        guard let trakt, let cur = profile.syncTokens["trakt"] else { return nil }
        if cur != old, !cur.needsRefresh() { return cur }
        let profileID = profile.id
        let task = Task { [weak self] () -> SyncToken? in
            defer { self?.traktRefresh = nil }
            do {
                let n = try await trakt.refresh(cur)
                if self?.profile.id == profileID { self?.update { $0.syncTokens["trakt"] = n } }
                return n
            } catch {
                RemoteLog.error("sync", "Trakt-Erneuerung fehlgeschlagen: \(error)")
                return nil
            }
        }
        traktRefresh = task
        return await task.value
    }

    /// Angefangenes aus dem gewählten Dienst holen und mit dem lokalen Stand zusammenführen.
    func syncRemoteProgress() async {
        let s: String
        switch profile.progressSource { case .local: return; case .trakt: s = "trakt"; case .simkl: s = "simkl" }
        guard let t = await token(s) else { return }
        do {
            let remote = s == "trakt" ? try await trakt?.playback(token: t) : try await simkl?.playback(token: t)
            progress.merge(remote: remote ?? [])
            RemoteLog.info("sync", "\(s): \(remote?.count ?? 0) angefangene Titel geholt")
            try progressStore.save(progress, profile: profile.id)
        } catch { lastError = "\(s == "trakt" ? "Trakt" : "Simkl") nicht erreichbar: \(error)" }
    }

    private func scrobbleProgress(_ r: PlayRequest, fraction: Double) {
        sendScrobble(scrobbler.progress(r, id: r.id, fraction: fraction))
    }

    private func sendScrobble(_ events: [ScrobbleEvent<PlayRequest>]) {
        let events = events.filter { $0.item.item.id.hasPrefix("tt") }
        let services = Self.syncServices.filter(isConnected)
        guard !events.isEmpty, !services.isEmpty else { return }
        let previous = scrobbleChain
        scrobbleChain = Task {
            await previous?.value
            for e in events {
                let r = e.item, imdb = r.item.id, pct = e.fraction * 100
                for s in services {
                    guard let t = await token(s) else { continue }
                    do {
                        if s == "trakt" { try await trakt?.scrobble(e.action, imdb: imdb, season: r.season, episode: r.episode, percent: pct, token: t) }
                        else { try await simkl?.scrobble(e.action, imdb: imdb, season: r.season, episode: r.episode, percent: pct, token: t) }
                    } catch { RemoteLog.error("sync", "\(s) \(e.action.rawValue): \(error)") }
                }
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
        if case .upcoming = source.kind { return await upcomingToday() }   // eigener 6-h-Cache (AppModel+Upcoming)
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
            case .continueWatching, .upcoming:
                out = []
            }
        } catch { RemoteLog.error("katalog", "\(source.title): \(error)"); return [] }
        RemoteLog.info("katalog", "\(source.title): \(out.count) Einträge")
        cache[source.id] = out
        return out
    }

    /// Streams brauchen IMDb-IDs; TMDB-Einträge werden übersetzt.
    func imdbID(for m: MetaPreview) async -> String? {
        if m.id.hasPrefix("tt") { return m.id }
        guard m.id.hasPrefix("tmdb:"), let n = Int(m.id.dropFirst(5)), let tmdb else { return nil }
        let key = "\(m.type):\(n)"
        if let c = imdbCache[key] { return c }
        let id = try? await tmdb.imdbID(tmdbID: n, type: m.type == "series" ? .series : .movie)
        if let id { imdbCache[key] = id }
        return id
    }

    /// TMDB-ID → IMDb-ID (ändert sich nicht; spart die Nachfrage bei jedem Vorladen/Öffnen).
    private var imdbCache: [String: String] = [:]

    func meta(type: String, imdb: String) async -> MetaDetail? {
        guard var m = try? await addons.meta(Self.cinemeta, type: type, id: imdb) else { return nil }
        if let l = await localized(imdb: imdb, series: type == "series") { m = m.applying(l) }
        return m
    }

    private var localizedCache: [String: LocalizedMeta] = [:]
    private var seasonCache: [String: [Int: LocalizedEpisode]] = [:]

    /// TMDB in Profilsprache (Titel, Text, Poster, Logo, FSK); nil ohne TMDB-Key.
    func localized(imdb: String, series: Bool) async -> LocalizedMeta? {
        if let c = localizedCache[imdb] { return c }
        guard let tmdb else { RemoteLog.info("tmdb", "kein TMDB-Key – keine Übersetzung"); return nil }
        do {
            guard let id = try await tmdb.tmdbID(imdb: imdb, series: series) else {
                RemoteLog.info("tmdb", "\(imdb): kein TMDB-Treffer (\(series ? "tv" : "movie"))"); return nil
            }
            guard let l = try await tmdb.localized(tmdbID: id, series: series) else {
                RemoteLog.info("tmdb", "\(imdb) → \(id): Antwort unlesbar"); return nil
            }
            RemoteLog.info("tmdb", "\(imdb) → \(id) · \(tmdb.language) · Titel \(l.name ?? "-") · Text \(l.overview == nil ? "nein" : "ja") · Logo \(l.logo == nil ? "nein" : "ja") · Freigabe \(l.certification ?? "-")")
            localizedCache[imdb] = l
            return l
        } catch { RemoteLog.error("tmdb", "Übersetzung \(imdb): \(error)"); return nil }
    }

    /// Folgennamen/-texte einer Staffel in Profilsprache.
    func localizedSeason(imdb: String, season: Int) async -> [Int: LocalizedEpisode] {
        let key = "\(imdb):\(season)"
        if let c = seasonCache[key] { return c }
        guard let tmdb, let id = await localized(imdb: imdb, series: true)?.tmdbID,
              let eps = try? await tmdb.season(tmdbID: id, season: season) else { return [:] }
        seasonCache[key] = eps
        return eps
    }

    func streams(type: String, id: String) async -> [(addon: String, stream: StreamItem)] {
        // Kurzer Cache: Detailseite holt vorab (für die Technik-Plaketten), die Quellenliste nutzt das Ergebnis.
        if let c = streamCache[id], Date().timeIntervalSince(c.at) < 600 {   // 10 min
            RemoteLog.info("streams", "\(id): Cache-Treffer\(StreamPrefetcher.shared.wasPrefetched(id) ? " (vorgeladen)" : "") · \(c.list.count) Quellen")
            return c.list
        }
        if let t = streamTasks[id] {
            RemoteLog.info("streams", "\(id): wartet auf laufende Abfrage\(StreamPrefetcher.shared.isRunning(id) ? " (Vorladen)" : "")")
            return await t.value
        }
        let task = Task { () -> [(addon: String, stream: StreamItem)] in
            let all = await addons.streams(from: profile.addons, type: type, id: id)
            RemoteLog.info("streams", "\(type) \(id): " + all.map { "\($0.addon.manifest.name)=\($0.streams.count)" }.joined(separator: ", "))
            return all.flatMap { r in playableStreams(r.streams).map { (r.addon.manifest.name, $0) } }
        }
        streamTasks[id] = task
        let list = await task.value
        streamTasks[id] = nil
        storeStreams(id: id, list: list, addonCount: profile.addons.count)
        return list
    }

    /// Nur der Cache, ohne Abfrage: erlaubt Technik-Plaketten schon im ersten Bild der Detailseite.
    func cachedStreams(id: String) -> [(addon: String, stream: StreamItem)]? {
        guard let c = streamCache[id], Date().timeIntervalSince(c.at) < 600 else { return nil }
        return c.list
    }

    private var streamCache: [String: (at: Date, list: [(addon: String, stream: StreamItem)])] = [:]
    private var streamTasks: [String: Task<[(addon: String, stream: StreamItem)], Never>] = [:]
    /// Leeres/fehlgeschlagenes Ergebnis: bis dahin kein Vorladen dieser ID (die Detailseite fragt trotzdem).
    private var streamEmptyUntil: [String: Date] = [:]
    /// Letztes Ergebnis, bei dem alle Addons leer blieben (vermutlich Ratenbegrenzung): Vorladen pausiert.
    private(set) var streamsAllEmptyAt: Date?

    /// MDBList-Bewertungen (nil ohne Key oder ohne Treffer).
    func ratings(imdb: String, series: Bool) async -> ExternalRatings? {
        guard let k = profile.apiKeys["mdblist"], !k.isEmpty else { return nil }
        return await RatingsStore.shared.ratings(imdb: imdb, series: series, apiKey: k)
    }

    // MARK: Handy-Eingabe

    func backupData() -> Data { (try? store.exportData(stored)) ?? Data() }

    func apply(_ commands: [PhoneCommand]) async {
        RemoteLog.info("handy", "Befehle: " + commands.map { c -> String in
            switch c {
            case .addAddon(let u): return "addon \(URL(string: u)?.host ?? "?")"
            case .setKey(let s, _): return "key \(s)"
            case .importNuvioURL: return "nuvio-url"
            case .importNuvioJSON: return "nuvio-json"
            case .addTMDBLink(let l): return "link \(l)"
            case .importBackup: return "backup"
            }
        }.joined(separator: ", "))
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

// MARK: Hero (Startseite)

extension AppModel {
    /// Folien des Hero: Einträge der Hero-Quellreihe über den Reihen-Loader (gleicher Cache), höchstens 8.
    func heroItems(for row: HomeRow) async -> [MetaPreview] {
        guard case .list(let s) = row.content else { return [] }
        return Array(await items(s).prefix(8))
    }

    /// Eintrag mit IMDb-ID, damit Weiterschauen direkt Cinemeta/Streams nutzen kann.
    func progressItem(_ m: MetaPreview, imdb: String, meta: MetaDetail?) -> MetaPreview {
        MetaPreview(id: imdb, type: m.type, name: m.name, poster: meta?.poster ?? m.poster,
                    background: meta?.background ?? m.background, logo: meta?.logo, description: meta?.description ?? m.description,
                    releaseInfo: meta?.releaseInfo ?? m.releaseInfo, imdbRating: m.imdbRating)
    }

    func moviePlayRequest(_ m: MetaPreview, imdb: String, meta: MetaDetail?, resumeLastSource: Bool) -> PlayRequest {
        PlayRequest(type: "movie", id: imdb, title: m.name, item: progressItem(m, imdb: imdb, meta: meta),
                    runtimeMinutes: parseRuntimeMinutes(meta?.runtime), resumeLastSource: resumeLastSource)
    }

    /// „Abspielen“ im Hero, wie Weiterschauen: Film mit gemerkter Quelle (sonst Quellenliste),
    /// Serie mit der nächsten offenen Folge, sonst S1F1. Metadaten/Folgen werden erst hier geladen.
    func quickPlayRequest(for m: MetaPreview) async -> PlayRequest? {
        guard let imdb = await imdbID(for: m) else { return nil }
        let series = m.type == "series"
        let detail = await self.meta(type: series ? "series" : "movie", imdb: imdb)
        guard series else { return moviePlayRequest(m, imdb: imdb, meta: detail, resumeLastSource: true) }
        let eps = EpisodeRef.list(from: detail?.videos ?? [])
        let n = progress.nextOpenEpisode(seriesID: imdb, in: eps)
        return PlayRequest(type: "series", id: "\(imdb):\(n.season):\(n.episode)", title: "\(m.name) S\(n.season)E\(n.episode)",
                           item: progressItem(m, imdb: imdb, meta: detail), season: n.season, episode: n.episode,
                           episodes: eps, resumeLastSource: true)
    }
}

// Task 7: Zustand des Quellen-Caches für das Vorladen (StreamPrefetcher) – liest die privaten Caches oben.
extension AppModel {
    enum StreamCacheState { case cached, running, emptyRecently, missing }

    func streamCacheState(id: String) -> StreamCacheState {
        let now = Date()
        if let c = streamCache[id], now.timeIntervalSince(c.at) < 600 { return .cached }
        if streamTasks[id] != nil { return .running }
        if let u = streamEmptyUntil[id], u > now { return .emptyRecently }
        return .missing
    }

    /// Ergebnis ablegen: Treffer in den 10-min-Cache (abgelaufene raus, höchstens 40, älteste zuerst raus),
    /// leere Ergebnisse 120 s als „leer“ merken; alle Addons leer → Vorladen pausiert (Ratenbegrenzung).
    fileprivate func storeStreams(id: String, list: [(addon: String, stream: StreamItem)], addonCount: Int) {
        let now = Date()
        streamEmptyUntil = streamEmptyUntil.filter { $0.value > now }
        if list.isEmpty {
            streamEmptyUntil[id] = now.addingTimeInterval(Self.emptyStreamsTTL)
            if addonCount > 0 { streamsAllEmptyAt = now }
            return
        }
        streamEmptyUntil[id] = nil
        streamCache = streamCache.filter { now.timeIntervalSince($0.value.at) < 600 }
        streamCache[id] = (now, list)
        if streamCache.count > Self.streamCacheLimit {
            let drop = streamCache.sorted { $0.value.at < $1.value.at }.prefix(streamCache.count - Self.streamCacheLimit)
            for (k, _) in drop { streamCache[k] = nil }
        }
    }

    static let streamCacheLimit = 40
    static let emptyStreamsTTL: TimeInterval = 120
}
