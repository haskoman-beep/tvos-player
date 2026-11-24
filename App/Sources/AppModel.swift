import SwiftUI
import PlayerCore

/// App-Zustand: Profile (persistiert), Clients, Katalog-Cache.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var stored: StoredProfiles { didSet { profileRevision &+= 1; syncRemoteLog() } }
    /// Zählt Profiländerungen (Merker der Paket-Kachelbilder, Welle F-g).
    private var profileRevision = 0
    private var packageArt = PackageArtMemo()
    @Published var lastError: String? { didSet { if let e = lastError { RemoteLog.error("fehler", e) } } }
    @Published var notice: String?
    let store: ProfileStore
    /// Task 2.2 (SEC-14): keys and sync logins also in the Keychain (stage 1: profiles keep them, format unchanged).
    /// Write rule: both (`save()`). At a normal start the profile wins; the Keychain fills gaps only on recovery.
    let secrets: SecretStore = KeychainSecretStore()
    /// What the Keychain holds per profile after the last save; `save()` writes only the differences.
    private var secretSnapshot: SecretSnapshot = [:]
    /// Task 1.3: `.unreadable` while the stored profiles cannot be read; RootView then shows ProfileRecoveryView and
    /// `save()` writes nothing until the user restores a version or starts again.
    @Published private(set) var storeState: StoreState = .ready
    enum StoreState: Equatable {
        case ready
        case unreadable(reason: String, candidates: [RecoveryCandidate])
    }
    /// Wave S round 2: „Bild & Ton“ per device (TV, HDMI, sound system); profile export and sync leave it out.
    @Published private(set) var device: DeviceSettings
    let deviceStore: DeviceSettingsStore
    let progressStore: ProgressStore
    /// Fortschritt des aktiven Profils.
    @Published private(set) var progress = ProgressBook()
    /// Task 1.3 (S-11): the progress file was unreadable (kept as .bak). The sync pull then merges in memory only;
    /// the book is saved again with the next real progress (play, tile action, chosen source).
    private var progressSaveHeld = false
    /// Wave W-a: PlayerCore reports skipped catalog items, addon notices and error subtitles through `log`.
    let addons = AddonClient(log: { cat, msg in Task { @MainActor in RemoteLog.info(cat, msg) } })
    /// Katalog-Cache: 24 h frisch, danach alter Stand sichtbar + Erneuerung im Hintergrund (AppModel+CatalogCache).
    var cache = TimedCache<[MetaPreview]>()
    var catalogRefreshing: Set<String> = []
    /// Zähler je Quelle nach einer Hintergrund-Erneuerung; Reihen laden dann neu.
    @Published var catalogRevisions: [String: Int] = [:]
    /// Erhöht beim Zurückkehren in die App, wenn Kataloge abgelaufen sind.
    @Published var catalogWake = 0
    /// Welle C-b: Plattenstand der Kataloge (AppModel+CatalogDisk).
    let catalogDisk = CatalogDiskStore()
    /// Welle F-f: laufende Reihen-Ladungen je Profil und Quelle (AppModel+HomeRows); Reihe und Vorladen teilen sie.
    var homeRowLoads: [String: Task<CatalogLoad, Never>] = [:]
    /// Task 3.1: profile epoch. `advance` on a profile switch or backup import, `bump` on a language or addon set
    /// change. A task that awaits and then writes profile data remembers `scopes.current` and checks it afterwards.
    @Published private(set) var scopes = ScopeClock(profile: UUID())

    /// Cinemeta liefert Metadaten/Folgenlisten für IMDb-IDs (kostenlos, ohne Key).
    static let cinemeta = InstalledAddon(
        manifestURL: "https://v3-cinemeta.strem.io/manifest.json",
        manifest: AddonManifest(id: "com.linvo.cinemeta", name: "Cinemeta", version: "3",
                                resources: [AddonResource(name: "meta")], types: ["movie", "series"], idPrefixes: ["tt"]))

    init() {
        RemoteLog.launch = ContinuousClock.now   // Task 1.8: origin of the start.* measuring points
        let storage = DefaultsStorage()
        // Before anything saves the profiles: the one-time move reads the old fields from profiles.json.
        let flag = DeviceSettingsStore.migratedFlagKey
        deviceStore = DeviceSettingsStore(storage: storage, isMigrated: { UserDefaults.standard.bool(forKey: flag) },
                                          markMigrated: { UserDefaults.standard.set(true, forKey: flag) })
        let dev = deviceStore.loadOrMigrate()
        device = dev.settings
        switch dev.outcome {
        case .loaded: break
        case .migrated(fromProfiles: true):
            RemoteLog.info("speicher", "Bild & Ton jetzt je Gerät: aus aktivem Profil übernommen (Ton \(dev.settings.audioShaping.logText), Bild \(dev.settings.displayMode.logText))")
        case .migrated(fromProfiles: false): RemoteLog.info("speicher", "Bild & Ton je Gerät: neu, Standardwerte")
        case .blockMissing: RemoteLog.error("speicher", "Bild & Ton: Gerätewerte fehlen, Standardwerte")
        case .blockUnreadable: RemoteLog.error("speicher", "Bild & Ton: Gerätewerte unlesbar, Standardwerte")
        }
        if let e = dev.writeError { RemoteLog.error("speicher", "Bild & Ton: Gerätewerte nicht gespeichert: \(e)") }
        store = ProfileStore(storage: storage)
        let profilesStart = ContinuousClock.now
        let loaded = store.loadResult()
        switch loaded {
        case .loaded(let s, _), .fresh(let s): stored = s
        case .unreadable: stored = .makeDefault()   // only shown behind ProfileRecoveryView, never saved
        }
        progressStore = ProgressStore(storage: storage, onPruned: { n in
            Task { @MainActor in RemoteLog.info("fortschritt", "beschnitten \(n)") }
        })
        adoptProfileLoad(loaded)
        adoptSecrets(recovery: loaded.needsSecretRecovery)   // file lost or read leniently: the Keychain fills gaps
        scopes = ScopeClock(profile: profile.id)
        let progressStart = ContinuousClock.now
        progress = loadProgress(profile.id)
        RemoteLog.metric(.startProfiles, ms: Metric.ms(profilesStart.duration(to: progressStart)),
                         fields: ["profile": "\(stored.profiles.count)",
                                  "fortschritt": "\(Metric.ms(progressStart.duration(to: ContinuousClock.now)))"], once: true)
        CollectionLinkStore.shared.attach(storage)   // wave F-o round 4: import blobs in the size-bounded storage
        FusionKitStore.shared.attach(self, storage: storage)   // Welle A e: Kit-Reihen der Startseite (AppModel+FusionKit)
        PlaybackStability.shared.attach(storage)   // Welle C-a: Netz, Ton-Route, fehlgeschlagene Quellen
        PlayerMemory.shared.attach(storage)   // Welle D-a: Spur-Wahl je Serie, TorBox-Fortschritt
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        RemoteLog.info("start", "App \(v) · \(stored.profiles.count) Profil(e) · Addons \(profile.addons.map(\.manifest.name)) · Reihen \(profile.home.rows.count) · Quelle \(profile.progressSource.rawValue)")
        observeCatalogWake()
        restoreCatalogSnapshot()
        syncRemoteLog()
    }

    // MARK: Fortschritt

    func recordProgress(_ r: PlayRequest, position: Double, duration: Double) {
        progressSaveHeld = false
        // Build 2 (2.5): same watched rule as the scrobble stop, so a close-time save cannot undo the stop's mark.
        let threshold = ProgressBook.finishedThreshold(syncConnected: Self.syncServices.contains(where: isConnected))
        progress.record(id: r.id, item: r.item, season: r.season, episode: r.episode, position: position, duration: duration,
                        finishedAt: threshold)
        if progress.isWatched(r.id), let n = r.nextRequest, let s = n.season, let e = n.episode {
            progress.recordNextUp(id: n.id, item: n.item, season: s, episode: e)
        }
        do { try saveProgressBook() } catch { lastError = "Fortschritt nicht gespeichert: \(error)" }
        scrobbleProgress(r, fraction: duration > 0 ? position / duration : 0)
    }

    /// Wave L: local change from a tile action (AppModel+SyncQueue), saved at once.
    func editProgress(_ change: (inout ProgressBook) -> Void) {
        change(&progress)
        progressSaveHeld = false
        do { try saveProgressBook() } catch { lastError = "Fortschritt nicht gespeichert: \(error)" }
    }

    /// Gewählte Quelle merken, damit Weiterschauen sie direkt startet.
    func rememberSource(_ r: PlayRequest, stream: StreamItem, addon: String) {
        progress.rememberSource(stream, addon: addon, for: r.id)
        progressSaveHeld = false
        do { try saveProgressBook() } catch { lastError = "Quelle nicht gespeichert: \(error)" }
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
    private var traktRefresh = TaskSlots<SyncToken?>()   // Task 3.1: key = profile ID

    var trakt: TraktClient? { traktClient(for: profile) }

    /// Task 3.1 (S-4): a 401 renews the token of the profile the client was made for, never of the active one.
    func traktClient(for p: Profile) -> TraktClient? {
        guard let id = p.apiKeys["trakt_id"], let sec = p.apiKeys["trakt_secret"], !id.isEmpty, !sec.isEmpty else { return nil }
        let owner = p.id
        return TraktClient(clientID: id, clientSecret: sec, onUnauthorized: { [weak self] old in await self?.refreshTrakt(after: old, profile: owner) })
    }

    var simkl: SimklClient? {
        guard let id = profile.apiKeys["simkl_id"], !id.isEmpty else { return nil }
        return SimklClient(clientID: id)
    }

    func hasClient(_ s: String) -> Bool { s == "trakt" ? trakt != nil : simkl != nil }
    func isConnected(_ s: String) -> Bool { profile.syncTokens[s] != nil && hasClient(s) }

    func disconnect(_ s: String) { update { $0.syncTokens[s] = nil }; clearCatalogCache() }

    func startLogin(_ s: String) async throws -> DeviceCode {
        if s == "trakt", let trakt { return try await trakt.deviceCode() }
        if s == "simkl", let simkl { return try await simkl.deviceCode() }
        throw APIError.notConnected
    }

    /// Einmal nachfragen; bei Erfolg wird die Anmeldung im Profil gespeichert.
    func pollLogin(_ s: String, _ code: DeviceCode) async -> DevicePoll {
        let scope = scopes.current
        let r: DevicePoll
        do {
            if s == "trakt", let trakt { r = try await trakt.poll(code) }
            else if s == "simkl", let simkl { r = try await simkl.poll(code) }
            else { return .failed(0) }
        } catch { return .pending }
        // Nur den Fall loggen (success/pending/…), nie das SyncToken mit Zugangs-/Erneuerungsschlüssel.
        RemoteLog.info("sync", "\(s) Login: \(String(describing: r).prefix(while: { $0 != "(" }))")
        if case .success(let t) = r {
            // Task 3.1: the login belongs to the profile it was started in, even after a switch.
            update(profile: scope.profile) { $0.syncTokens[s] = t }
            guard scopeStillCurrent(scope, "\(s) Login") else { return r }
            clearCatalogCache()
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

    /// Trakt-Token erneuern; nur eine Erneuerung zur Zeit je Profil (der Refresh-Token rotiert).
    /// Hat ein anderer Aufrufer `old` schon ersetzt, wird das neue Token zurückgegeben.
    /// Task 3.1 (S-4): the running renewal is bound to `scope.profile`; only callers of that profile join it, and
    /// the new token is always written into that profile by ID (active or not), as long as it still holds `cur`.
    func refreshTrakt(after old: SyncToken, profile id: UUID? = nil) async -> SyncToken? {
        let owner = id ?? profile.id, key = owner.uuidString
        if let running = traktRefresh[key] { return await running.value }
        guard let p = stored.profiles.first(where: { $0.id == owner }), let trakt = traktClient(for: p),
              let cur = p.syncTokens["trakt"] else { return nil }
        if cur != old, !cur.needsRefresh() { return cur }
        let task = Task { [weak self] () -> SyncToken? in
            do {
                let n = try await trakt.refresh(cur)
                self?.writeRenewedToken(n, replacing: cur, service: "trakt", profile: owner)
                return n
            } catch {
                RemoteLog.error("sync", "Trakt-Erneuerung fehlgeschlagen: \(error)")
                return nil
            }
        }
        let ticket = traktRefresh.begin(key, task)
        let n = await task.value
        traktRefresh.finish(key, ticket)
        return n
    }

    /// Task 3.1 (S-4): renewed token into the profile with `id`, also when another profile is active now.
    private func writeRenewedToken(_ n: SyncToken, replacing cur: SyncToken, service: String, profile id: UUID) {
        var list = stored.profiles
        guard SyncTokenWriteBack.apply(n, replacing: cur, service: service, profile: id, in: &list) else {
            RemoteLog.info("sync", "\(service): erneuertes Token nicht übernommen (abgemeldet, neu angemeldet oder Profil fort)")
            return
        }
        stored.profiles = list
        save()
        if id != profile.id { RemoteLog.info("profil", "\(service): erneuertes Token im vorigen Profil gespeichert") }
    }

    /// Task 3.1: false (and one log line) when `s` is no longer the current scope; the late result is dropped.
    func scopeStillCurrent(_ s: ProfileScope, _ what: String) -> Bool {
        guard !scopes.isCurrent(s) else { return true }
        RemoteLog.info("profil", "Ergebnis verworfen (Epoche) · \(what)")
        return false
    }

    /// Angefangenes aus dem gewählten Dienst holen und mit dem lokalen Stand zusammenführen.
    func syncRemoteProgress() async {
        await processSyncQueue()   // Wave L: send pending tile changes before pulling
        let scope = scopes.current   // Task 3.1 (S-3): the pull belongs to this profile and epoch
        let s: String
        switch profile.progressSource { case .local: return; case .trakt: s = "trakt"; case .simkl: s = "simkl" }
        guard let t = await token(s), scopeStillCurrent(scope, "\(s) Abgleich") else { return }
        do {
            let remote = s == "trakt" ? try await trakt?.playback(token: t) : try await simkl?.playback(token: t)
            guard scopeStillCurrent(scope, "\(s) Abgleich") else { return }
            let mergeStart = ContinuousClock.now
            let before = progress
            progress.merge(remote: applySyncQueue(remote ?? []))
            RemoteLog.metric(.syncMerged, ms: Metric.ms(mergeStart.duration(to: ContinuousClock.now)),
                             fields: ["eintraege": "\(remote?.count ?? 0)", "geaendert": progress == before ? "nein" : "ja"])
            RemoteLog.info("sync", "\(s): \(remote?.count ?? 0) angefangene Titel geholt")
            if progressSaveHeld { RemoteLog.info("speicher", "Fortschritt nach Abgleich nicht gespeichert: Datei war unlesbar, wartet auf nächsten Fortschritt") }
            else { try saveProgressBook() }
        } catch {
            guard scopeStillCurrent(scope, "\(s) Abgleich") else { return }
            lastError = "\(s == "trakt" ? "Trakt" : "Simkl") nicht erreichbar: \(error)"
        }
    }

    private func scrobbleProgress(_ r: PlayRequest, fraction: Double) {
        sendScrobble(scrobbler.progress(r, id: r.id, fraction: fraction))
    }

    private func sendScrobble(_ events: [ScrobbleEvent<PlayRequest>]) {
        let events = events.filter { $0.item.item.id.hasPrefix("tt") }
        let services = Self.syncServices.filter(isConnected)
        guard !events.isEmpty, !services.isEmpty else { return }
        // Build 2 (2.5): a stop from 80 % on counts as watched at the services, so locally too.
        for e in events where e.watched {
            let r = e.item
            editProgress { b in
                b.markFinished(id: r.id)
                if let n = r.nextRequest, let s = n.season, let ep = n.episode { b.recordNextUp(id: n.id, item: n.item, season: s, episode: ep) }
            }
        }
        let previous = scrobbleChain
        scrobbleChain = Task {
            await previous?.value
            for e in events {
                let r = e.item, imdb = r.item.id, pct = e.fraction * 100
                for s in services {
                    let stopID = [imdb, r.season.map(String.init), r.episode.map(String.init)].compactMap { $0 }.joined(separator: ":")
                    guard let t = await token(s) else {
                        // No token (e.g. refresh failed offline): a watched stop still must not get lost.
                        if e.watched { queueScrobbleStop(id: stopID, progress: e.fraction, service: s) }
                        continue
                    }
                    do {
                        if s == "trakt" { try await trakt?.scrobble(e.action, imdb: imdb, season: r.season, episode: r.episode, percent: pct, token: t) }
                        else { try await simkl?.scrobble(e.action, imdb: imdb, season: r.season, episode: r.episode, percent: pct, token: t) }
                    } catch {
                        RemoteLog.error("sync", "\(s) \(e.action.rawValue): \(error)")
                        // Build 2 (2.5): a lost watched stop goes to the queue and is sent later as a history entry.
                        if e.watched { queueScrobbleStop(id: stopID, progress: e.fraction, service: s) }
                    }
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
        update(profile: profile.id, change)
    }

    /// Task 3.1: change one profile by ID (a late result goes into the profile it was started for). In the active
    /// profile a new language or addon set starts a new epoch.
    func update(profile id: UUID, _ change: (inout Profile) -> Void) {
        guard let i = stored.profiles.firstIndex(where: { $0.id == id }) else { return }
        let before = stored.profiles[i]
        change(&stored.profiles[i])
        save()
        guard id == profile.id else { return }
        let after = stored.profiles[i]
        if before.addons != after.addons { addonSetChanged() }
        if before.language != after.language { languageChanged() }
    }

    /// Task 3.1 (A-A-8): addon installed, removed, moved or replaced: sources, running searches, empty pauses and
    /// addon metadata of the old set go; running tasks of the old epoch drop their results.
    func addonSetChanged() {
        scopes.bump()
        resetStreamState()
        HeroDetailsCache.all.removeAll(); AddonMetaCache.reset()
        RemoteLog.info("profil", "Addon-Satz geändert · Quellen und Metadaten verworfen")
    }

    /// Task 3.1 (A-A-12, A-B-2): texts, catalog rows and hero data in the old language go.
    private func languageChanged() {
        scopes.bump()
        clearCatalogCache()
        HeroDetailsCache.all.removeAll()
        RemoteLog.info("profil", "Sprache geändert · Texte und Kataloge neu")
    }

    /// Source cache, running searches, empty pauses and gap marks (profile switch, addon set change).
    private func resetStreamState() {
        // Quellen des vorigen Profils (andere Addons) nicht ungefiltert als Cache-Treffer liefern.
        streamCache.removeAll(); streamAddonFetchedAt.removeAll()
        // Welle D-b (M1): laufende Suchen des alten Profils vergessen (sie legen nichts mehr ab, niemand wartet neu
        // auf sie), Leer-Pausen und Lückenmerker gelten nur für das Profil, in dem sie entstanden.
        streamTasks.reset(); streamEmptyUntil.removeAll(); emptyPause = EmptyPause(); streamPartial.removeAll()
        streamTiers.removeAll()   // Wave F-k R2
        StreamSearchStatus.shared.reset(); StreamPrefetcher.shared.reset()
    }

    func save() {
        guard storeState == .ready else {
            RemoteLog.info("speicher", "Speichern übersprungen: Profile nicht lesbar, Auswahl offen")
            return
        }
        do { try store.save(stored) } catch { lastError = "Speichern fehlgeschlagen: \(error)"; return }
        mirrorSecrets()   // only after the file was written, so the Keychain never holds what the profile lacks
    }

    // MARK: Task 2.2: Keychain

    /// After a load or a replacement of the profiles. Fix round 1: normally the loaded profile is authoritative (it
    /// may hold values changed under Build 1): its secrets go into the Keychain, nothing goes back into profiles.json.
    /// `recovery` (older version restored, profile file lost or reset, profiles read leniently with a non-empty
    /// report): first fill the secrets the profiles lack from
    /// the Keychain. Nothing while the profiles are unreadable.
    private func adoptSecrets(recovery: Bool) {
        guard storeState == .ready else { return }
        var filled = 0
        if recovery {
            var list = stored.profiles
            filled = SecretMigration.fillMissing(&list, store: secrets)
            if filled > 0 { stored.profiles = list }
        }
        let copied = SecretMigration.copyIntoStore(profiles: stored.profiles, store: secrets)
        // A failed single write is retried at the next start (copyIntoStore compares with the Keychain itself).
        secretSnapshot = SecretMigration.snapshot(stored.profiles)
        RemoteLog.info("speicher", "Schlüsselbund: \(copied) Eintrag/Einträge abgeglichen" + (recovery ? ", \(filled) fehlende Wert(e) ergänzt" : ""))
        if filled > 0 { save() }
    }

    /// Write rule: changed secrets of every profile into the Keychain, removed ones and deleted profiles out.
    private func mirrorSecrets() {
        do { secretSnapshot = try SecretMigration.mirror(from: secretSnapshot, to: stored.profiles, store: secrets) }
        catch { RemoteLog.error("speicher", "Schlüsselbund nicht aktualisiert: \(error) · Profil hält die Werte weiter") }
    }

    // MARK: Task 1.3: unreadable profiles

    /// Task 2.6: the only place the app saves progress. Prunes first and keeps the pruned book in memory, so the
    /// same entries are never pruned or logged again on the next save.
    func saveProgressBook() throws {
        let small = progressStore.prune(progress)
        if small.entries.count != progress.entries.count { progress = small }
        try progressStore.save(progress, profile: profile.id)
    }

    /// Progress of a profile; an unreadable file is kept as `.bak` by ProgressStore and the book starts empty
    /// (saved only with the next progress).
    func loadProgress(_ id: UUID) -> ProgressBook {
        progressSaveHeld = false
        // Task 2.6: pruned (and logged) by the same step as every save, so the in-memory book matches the file.
        if let b = progressStore.load(profile: id) { return progressStore.prune(b) }
        progressSaveHeld = true
        RemoteLog.error("speicher", "Fortschritt unlesbar, als .bak beiseitegelegt · leeres Buch bis zum nächsten Fortschritt")
        return ProgressBook()
    }

    /// Applies a load result to `storeState` and logs it.
    private func adoptProfileLoad(_ l: ProfileLoad) {
        switch l {
        case .loaded(_, let report):
            storeState = .ready
            RemoteLog.info("speicher", report.isEmpty ? "Profile geladen · Bericht leer"
                                                      : "Profile geladen · ignoriert: \(report.ignored.joined(separator: ", "))")
        case .fresh:
            storeState = .ready
            RemoteLog.info("speicher", "Profile neu angelegt")
        case .unreadable(let reason, let candidates):
            storeState = .unreadable(reason: reason, candidates: candidates)
            RemoteLog.error("speicher", "Profile nicht lesbar: \(reason) · \(candidates.count) ältere Fassung(en) · Speichern gesperrt")
        }
    }

    /// „Erneut versuchen“. Final review: false when the profiles are still unreadable (the recovery view says so).
    @discardableResult
    func retryProfileLoad() -> Bool {
        let l = store.loadResult()
        switch l {
        case .loaded(let s, _), .fresh(let s):
            adoptProfileLoad(l)
            profilesReplaced(s, recovery: l.needsSecretRecovery)
            return true
        case .unreadable:
            adoptProfileLoad(l)
            return false
        }
    }

    /// „Diese Fassung laden“.
    func restoreProfiles(_ id: String) {
        do {
            let s = try store.restore(id)
            storeState = .ready
            RemoteLog.info("speicher", "Profile wiederhergestellt aus \(id) · \(s.profiles.count) Profil(e)")
            profilesReplaced(s, recovery: true)
        } catch { lastError = "Fassung nicht geladen: \(error)" }
    }

    /// „Neu anfangen“ (after the confirmation).
    func startFreshProfiles() {
        do {
            let s = try store.startFresh()
            storeState = .ready
            RemoteLog.info("speicher", "Profile neu angefangen · unlesbarer Stand bleibt als profiles.json.unreadable.bak")
            profilesReplaced(s, recovery: true)
        } catch { lastError = "Neu anfangen fehlgeschlagen: \(error)" }
    }

    /// After the profiles were replaced while the app runs: state of the old (default) profile goes.
    private func profilesReplaced(_ s: StoredProfiles, recovery: Bool) {
        clearCatalogCache()   // memory cache and snapshot of the stand-in default profile
        stored = s
        scopes.advance(to: profile.id)   // Task 3.1
        adoptSecrets(recovery: recovery)   // Task 2.2: a restored version gets missing keys and logins from the Keychain
        progress = loadProgress(profile.id)
        restoreCatalogSnapshot()
        Task { await syncRemoteProgress() }
    }

    /// Wave S round 2: changes a device setting (Bild & Ton) and stores it at once.
    func updateDevice(_ change: (inout DeviceSettings) -> Void) {
        change(&device)
        do { try deviceStore.save(device) } catch { lastError = "Speichern fehlgeschlagen: \(error)" }
        syncRemoteLog()
    }

    /// Task 1.5: remote log switch and receiver (device) plus the shared secret (phone page, key `playerlog`; like
    /// the atvloadly address: active profile first, else any profile) to `RemoteLog`.
    func syncRemoteLog() {
        let k = LogSignature.secretKey
        let secret = profile.apiKeys[k] ?? stored.profiles.lazy.compactMap { $0.apiKeys[k] }.first
        RemoteLog.shared.configure(enabled: device.remoteLogEnabled, receiver: device.remoteLogReceiver, secret: secret)
    }

    // MARK: Profile

    func switchProfile(_ id: UUID) {
        // Welle D-b (Mi3): das schon aktive Profil erneut wählen ändert nichts (laufende Suchen bleiben gültig).
        guard id != stored.activeProfileID else { return }
        stored.activeProfileID = id; cache.removeAll(); save()
        // Task 3.1: new epoch; late results of the old profile are dropped, its token renewal still lands in it.
        scopes.advance(to: id)
        resetStreamState()
        // Welle E-a (I3): Addon-Bilder/-Bewertungen des alten Profils nicht weiter zeigen.
        HeroDetailsCache.all.removeAll(); AddonMetaCache.reset()
        restoreCatalogSnapshot()
        progress = loadProgress(id)
        Task { await syncRemoteProgress() }
    }

    /// Task 2.4 (S-9): everything stored for a profile that is gone (deleted, or not in a restored backup): catalog
    /// files, sync queue, every block `*-<profile>.json` (progress, trackmemory, fileprogress, link packs, import-media,
    /// …) and the per-profile UserDefaults entries. Sync logins live in the profile itself (no Keychain entries yet).
    func removeProfileData(_ id: UUID) {
        removeCatalogFile(profile: id)
        removeSyncQueue(profile: id)   // Welle L
        let removed = ProfileBlocks.remove(profile: id, from: progressStore.storage)
        FusionKitStore.setStoredSettings(nil, for: id)
        CollectionLinkStore.setStoredLinks(nil, for: id)
        RemoteLog.info("speicher", "Profildaten entfernt · \(removed.count) Block/Blöcke")
    }

    func addProfile(name: String) {
        let p = Profile.makeDefault(name: name)
        stored.profiles.append(p)
        switchProfile(p.id)
    }

    func deleteProfile(_ id: UUID) {
        guard stored.profiles.count > 1 else { return }
        stored.profiles.removeAll { $0.id == id }
        removeProfileData(id)
        // Aktives Profil gelöscht: über den Profilwechsel (Cache leeren, Stand des neuen Profils lesen).
        if stored.activeProfileID == id, let next = stored.profiles.first?.id { switchProfile(next) } else { save() }
    }

    // MARK: Addons

    func installAddon(_ url: String) async {
        let scope = scopes.current
        do {
            let a = try await addons.install(manifestURL: url)
            // Task 3.1: into the profile it was asked for, even if another one is active by now.
            if scope.profile != profile.id { RemoteLog.info("profil", "Addon nach Profilwechsel ins vorige Profil übernommen") }
            update(profile: scope.profile) { p in
                p.addons.removeAll { $0.manifestURL == a.manifestURL }
                p.addons.append(a)
            }
            if scope.profile == profile.id { clearCatalogCache() } else { removeCatalogFile(profile: scope.profile) }
        } catch { lastError = "Addon nicht geladen: \(error)" }
    }

    // MARK: Import

    func importNuvio(from urlString: String) async {
        let scope = scopes.current   // Task 3.1: the import belongs to the profile it was asked for
        do {
            guard let url = URL(string: urlString) else { throw AddonError.invalidManifestURL(urlString) }
            let data = try await URLSessionFetcher().data(from: url)
            if scope.profile != profile.id { RemoteLog.info("profil", "Import nach Profilwechsel ins vorige Profil übernommen") }
            importNuvio(data: data, profile: scope.profile)
        } catch { lastError = "Import fehlgeschlagen: \(error)" }
    }

    /// `profile`: target profile by ID (Task 3.1); nil = the active one.
    func importNuvio(data: Data, profile id: UUID? = nil) {
        do { importNuvio(result: try NuvioImport.parse(data), profile: id) } catch { lastError = "Import fehlgeschlagen: \(error)" }
    }

    /// Wave F-o round 3: `refresh` (media of the last import of a stored link) → the fresh media addresses win, the
    /// user's own changes stay (`NuvioImport.refreshFolders`); nil → first import, only gaps are filled.
    func importNuvio(result r: NuvioImportResult, refresh previous: [String: FolderMedia]? = nil, profile id: UUID? = nil) {
        update(profile: id ?? profile.id) { p in
            for c in r.collections {
                if let i = p.collections.firstIndex(where: { $0.title == c.title }) {
                    p.collections[i].folders = previous.map {
                        NuvioImport.refreshFolders(p.collections[i].folders, fresh: c.folders, collection: c.title, previous: $0)
                    } ?? NuvioImport.mergeFolders(p.collections[i].folders, c.folders)
                } else { p.collections.append(c) }
            }
        }
    }

    /// Fertiges Paket oder anderes Collection-Objekt ins Profil übernehmen (falls noch nicht da).
    func addCollection(_ c: MediaCollection) {
        update { p in if !p.collections.contains(where: { $0.id == c.id }) { p.collections.append(c) } }
    }

    /// Welle F-l: Paket-Kacheln zeigen Standbild und Fokus-GIF aus einem Import des Nutzers (Nuvio/Fusion), sonst aus
    /// den Kachel-Dateien des Startseiten-Kits (zur Laufzeit geladen); Zuordnung nach Anbieter/Genre bzw. Name
    /// (`ReadyPackages.withArt`). Ohne Treffer bleibt die Symbol-Kachel. Keine Bilder aus dem Repo.
    func collection(_ id: String) -> MediaCollection? {
        guard let c = profile.collections.first(where: { $0.id == id }) else { return FusionKitStore.shared.collection(id) }
        // Wave F-o round 2: imported preview packs fill video and still of imported tiles with the same title.
        guard id.hasPrefix("pkg.") else { return CollectionLinkStore.shared.enriched(c, profileRevision: profileRevision) }
        let kit = FusionKitStore.shared
        let stamp = PackageArtMemo.Stamp(profile: profileRevision, kit: kit.revision)
        return packageArt.collection(c, stamp: stamp) { PackageArtSource.userImports(profile.collections) + kit.artSources }
    }

    // MARK: Kataloge

    var tmdb: TMDBClient? {
        guard let k = profile.apiKeys["tmdb"], !k.isEmpty else { return nil }
        return TMDBClient(apiKey: k, language: profile.language == .de ? "de-DE" : "en-US")
    }

    /// `refresh`: Cache überspringen (Hintergrund-Erneuerung, AppModel+CatalogCache).
    func items(_ source: CatalogSource, refresh: Bool = false) async -> [MetaPreview] {
        await loadItems(source, refresh: refresh).items
    }

    /// Wie `items`, sagt aber zusätzlich, ob die Abfrage fehlschlug und ob der Stand aus dem Cache kam
    /// (Welle F-f: Reihe zeigt „Laden fehlgeschlagen – erneut versuchen“, Log je Reihe).
    func loadItems(_ source: CatalogSource, refresh: Bool = false) async -> CatalogLoad {
        if case .continueWatching = source.kind { return CatalogLoad(items: progress.continueWatching().map(\.item), fromCache: true) }
        if case .upcoming = source.kind { return CatalogLoad(items: await upcomingToday()) }   // eigener 6-h-Cache (AppModel+Upcoming)
        if !refresh { await awaitCatalogSnapshot() }   // Welle C-b: Plattenstand zuerst
        if !refresh, let c = cache[source.id] { refreshCatalogIfStale(source); return CatalogLoad(items: applySyncQueue(source, c), fromCache: true) }
        let generation = cache.generation
        let started = Date()   // Welle L: ab wann dieser Abruf den bestätigten Stand der Dienste sieht
        var out: [MetaPreview] = []
        do {
            switch source.kind {
            case .tmdbDiscover, .tmdbList, .tmdbCompany, .tmdbCollection:
                guard let tmdb else { return CatalogLoad(items: []) }
                out = try await tmdb.items(for: source)
            case .addon(let addonId, let catalogId, let type):
                guard let a = profile.addons.first(where: { $0.manifest.id == addonId }) else { return CatalogLoad(items: []) }
                out = try await addons.catalog(a, type: type, id: catalogId)
            case .trakt(let user, let list):
                guard let trakt = trakt ?? traktPublic else { return CatalogLoad(items: []) }   // öffentliche Listen: Client ID reicht
                out = try await trakt.list(user: user, slug: list, token: await token("trakt"), limit: source.limit)
            case .watchlist:
                out = try await watchlistItems()
            case .continueWatching, .upcoming:
                out = []
            }
        } catch { RemoteLog.error("katalog", "\(source.title): \(error)"); return CatalogLoad(items: [], failed: true) }
        out = source.applyingLimit(out)
        RemoteLog.info("katalog", "\(source.title): \(out.count) Einträge")
        // Nach Profilwechsel/Leeren nicht mehr ablegen; leere Erneuerung überschreibt keine gefüllte Liste.
        // Welle L: eine leere Merkliste ist echt (letzter Titel entfernt) und überschreibt den alten Stand.
        var isWatchlist = false
        if case .watchlist = source.kind { isWatchlist = true }
        let keepFilled = refresh && !isWatchlist
        let stored = keepFilled ? cache.storeRefreshed(out, for: source.id, generation: generation)
                             : cache.store(out, for: source.id, generation: generation)
        scheduleCatalogSave()
        if stored, isWatchlist { noteWatchlistPull(startedAt: started) }   // Welle L
        return CatalogLoad(items: applySyncQueue(source, out))
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

    /// Welle E-a: IMDb-ID ohne Netzabfrage (IMDb-ID selbst oder schon nachgeschlagen), sonst nil.
    func cachedIMDbID(for m: MetaPreview) -> String? {
        if m.id.hasPrefix("tt") { return m.id }
        guard m.id.hasPrefix("tmdb:"), let n = Int(m.id.dropFirst(5)) else { return nil }
        return imdbCache["\(m.type):\(n)"]
    }

    /// Welle E-a: Cinemeta + Metadaten-Addon (Bilder, Bewertung) + TMDB-Texte, zusammengeführt in AppModel+MetaAddon.
    func meta(type: String, imdb: String) async -> MetaDetail? { await mergedMeta(type: type, imdb: imdb) }

    /// Task 3.1 (A-A-12, A-B-2): keyed by (IMDb ID, language), bounded, bound to the scope (a profile switch,
    /// language or addon change starts empty; a late answer of an older scope is not stored).
    private var localizedCache = ScopedCache<TextCacheKey, LocalizedMeta>(limit: 300)
    private var localizedFlights: [String: Task<SharedLookup<LocalizedMeta>, Never>] = [:]
    private var seasonCache = ScopedCache<TextCacheKey, [Int: LocalizedEpisode]>(limit: 100)

    /// TMDB in Profilsprache (Titel, Text, Poster, Logo, FSK); nil ohne TMDB-Key.
    func localized(imdb: String, series: Bool) async -> LocalizedMeta? {
        guard let tmdb else { RemoteLog.info("tmdb", "kein TMDB-Key – keine Übersetzung"); return nil }
        let scope = scopes.current
        if let c = localizedCache.value(for: TextCacheKey(imdb: imdb, language: tmdb.language), in: scope) { return c }
        // Wave F-p: the detail page asks in parallel to the meta, which asks too: one request, both wait for it.
        // Task 3.1: a request of an older epoch or another language is never joined.
        let key = "\(series ? "s" : "m"):\(imdb):\(tmdb.language):\(scope.epoch)"
        if let t = localizedFlights[key] {
            // R1/R2: joined a request that failed (timeout, network): ask once more, as the former second call did.
            // No match, no key or an unreadable answer stay as they are (no second lookup, no second log line).
            let o = await t.value
            return o.retriesOnJoin ? await fetchLocalized(imdb: imdb, series: series, tmdb: tmdb, scope: scope).value : o.value
        }
        let t = Task { await fetchLocalized(imdb: imdb, series: series, tmdb: tmdb, scope: scope) }
        localizedFlights[key] = t
        let o = await t.value
        localizedFlights[key] = nil
        return o.value
    }

    private func fetchLocalized(imdb: String, series: Bool, tmdb: TMDBClient, scope: ProfileScope) async -> SharedLookup<LocalizedMeta> {
        do {
            guard let id = try await tmdb.tmdbID(imdb: imdb, series: series) else {
                RemoteLog.info("tmdb", "\(imdb): kein TMDB-Treffer (\(series ? "tv" : "movie"))"); return .none
            }
            guard let l = try await tmdb.localized(tmdbID: id, series: series) else {
                RemoteLog.info("tmdb", "\(imdb) → \(id): Antwort unlesbar"); return .none
            }
            RemoteLog.info("tmdb", "\(imdb) → \(id) · \(tmdb.language) · Titel \(l.name ?? "-") · Text \(l.overview == nil ? "nein" : "ja") · Logo \(l.logo == nil ? "nein" : "ja") · Freigabe \(l.certification ?? "-")")
            if !localizedCache.store(l, for: TextCacheKey(imdb: imdb, language: tmdb.language), from: scope, current: scopes.current) {
                RemoteLog.info("profil", "Ergebnis verworfen (Epoche) · tmdb \(imdb)")
            }
            return .found(l)
        } catch { RemoteLog.error("tmdb", "Übersetzung \(imdb): \(error)"); return .failed }
    }

    /// Folgennamen/-texte einer Staffel in Profilsprache.
    func localizedSeason(imdb: String, season: Int) async -> [Int: LocalizedEpisode] {
        guard let tmdb else { return [:] }
        let scope = scopes.current, key = TextCacheKey(imdb: imdb, language: tmdb.language, season: season)
        if let c = seasonCache.value(for: key, in: scope) { return c }
        guard let id = await localized(imdb: imdb, series: true)?.tmdbID,
              let eps = try? await tmdb.season(tmdbID: id, season: season) else { return [:] }
        if !seasonCache.store(eps, for: key, from: scope, current: scopes.current) {
            RemoteLog.info("profil", "Ergebnis verworfen (Epoche) · Staffel \(imdb):\(season)")
        }
        return eps
    }

    /// Wave F-k R2: who asks. `.page` = detail page, source list, player, background renewal.
    enum StreamCaller { case page, focusPrefetch, visiblePrefetch }

    /// `revalidate`: Cache überspringen (Hintergrund-Erneuerung, AppModel+StreamRevalidate).
    /// Wave F-k R2 `caller`: results of the visible-tile prefetch are the weak cache tier (`StreamCacheTiers`, go
    /// first, until a page or the focus prefetch uses them); a page's own search pauses new visible-tile starts.
    func streams(type: String, id: String, revalidate: Bool = false,
                 caller: StreamCaller = .page) async -> [(addon: String, stream: StreamItem)] {
        // Detailseite holt vorab (für die Technik-Plaketten), die Quellenliste nutzt das Ergebnis.
        // Welle C-b: frisch → direkt; veraltet → sofort zeigen + im Hintergrund erneuern; abgelaufen → neu laden.
        if !revalidate, let c = streamCache[id], case let list = usableStreams(id: id, c), !list.isEmpty,
           let fresh = streamCacheHit(type: type, id: id, at: c.at, caller: caller) {
            RemoteLog.info("streams", "\(id): Cache-Treffer\(fresh ? "" : " (veraltet, Erneuerung läuft)")\(StreamPrefetcher.shared.wasPrefetched(id) ? " (vorgeladen)" : "") · \(list.count) Quellen")
            if caller != .visiblePrefetch { streamTiers.keep(id) }
            return list
        }
        // Welle D-b (M1): Profil und Stand beim Start merken; nach einem Profilwechsel kein Ergebnis des alten Profils
        // ablegen oder an einen Aufrufer geben.
        let owner = profile.id, epoch = streamTasks.currentEpoch
        if caller == .page { StreamPrefetcher.shared.pageSearchBegan() }
        defer { if caller == .page { StreamPrefetcher.shared.pageSearchEnded(self) } }
        if let t = streamTasks[id] {
            RemoteLog.info("streams", "\(id): wartet auf laufende Abfrage\(StreamPrefetcher.shared.isRunning(id) ? " (Vorladen)" : "")")
            if caller != .visiblePrefetch { streamTiers.keep(id) }
            let list = await t.value
            if caller != .visiblePrefetch { streamTiers.keep(id) }
            return profile.id == owner ? list : []
        }
        // Weak only if there is no usable strong entry to renew (R3, m-R2-1: an expired one does not count).
        streamTiers.searchStarted(id, visiblePrefetch: caller == .visiblePrefetch,
                                  hasUsableEntry: streamCache[id].map { RevalidationPolicy.streams.isUsable(storedAt: $0.at) } ?? false)
        let task = Task { () -> [(addon: String, stream: StreamItem)] in
            // Welle C-a: Zeitgrenze und Status je Addon; `failed` = Addons mit Fehler oder Zeitüberschreitung.
            let search = await searchAddons(type: type, id: id, owner: owner, epoch: epoch)
            let all = search.results
            RemoteLog.info("streams", "\(type) \(id): " + all.map { "\($0.addon.manifest.name)=\($0.streams.count)" }.joined(separator: ", "))
            guard searchStillCurrent(owner: owner, epoch: epoch) else {
                RemoteLog.info("streams", "\(id): Profil gewechselt, Ergebnis der alten Suche verworfen")
                return []
            }
            // Rohergebnis aller Addons leer (fehlgeschlagene fehlen in `all`, zählen also als leer). Bewusst vor dem
            // Filtern auf abspielbare Quellen. Task 3.7 (A-A-4): one title without sources is normal; only several
            // different titles in a row pause the prefetch (`EmptyPause`). No addon asked: does not count.
            noteSearchOutcome(id: id, raw: all, failed: search.failed)
            // Task 3.6 (A-A-9): entries, answered and failed carry the unique label per installation (`AddonIdentity`).
            let labels = AddonIdentity.labels(profile.addons)
            let label = { (a: InstalledAddon) in labels[a.instanceID] ?? a.manifest.name }
            let list = all.flatMap { r in playableStreams(r.streams).map { (label(r.addon), $0) } }
            // Welle C-b: Addons ohne Antwort behalten ihre alten Einträge; leer ersetzt keinen Stand.
            return storeStreams(id: id, fresh: list, answered: Set(all.map { label($0.addon) }), failed: search.failed)
        }
        let ticket = streamTasks.begin(id, task)
        let list = await task.value
        streamTasks.finish(id, ticket)
        return profile.id == owner ? list : []
    }

    /// Nur der Cache, ohne Abfrage: erlaubt Technik-Plaketten schon im ersten Bild der Detailseite.
    func cachedStreams(id: String) -> [(addon: String, stream: StreamItem)]? {
        guard let c = streamCache[id], RevalidationPolicy.streams.isUsable(storedAt: c.at) else { return nil }
        let list = usableStreams(id: id, c)
        return list.isEmpty ? nil : list
    }

    /// Welle C-b M-A: behaltene Einträge auch beim Lesen nach der letzten Antwort ihres Addons begrenzen.
    func usableStreams(id: String, _ c: (at: Date, list: [(addon: String, stream: StreamItem)])) -> [(addon: String, stream: StreamItem)] {
        StreamListMerge.usable(c.list, fetchedAt: streamAddonFetchedAt[id] ?? [:], storedAt: c.at,
                               maxAge: RevalidationPolicy.streams.usableFor)
    }

    /// Welle C-b: nicht privat, damit AppModel+StreamRevalidate den Stand lesen kann.
    var streamCache: [String: (at: Date, list: [(addon: String, stream: StreamItem)])] = [:]
    /// Welle D-b (M1): laufende Abfragen je ID; `reset()` beim Profilwechsel.
    var streamTasks = TaskSlots<[(addon: String, stream: StreamItem)]>()
    /// Welle D-b (M3): IDs, deren Stand lückenhaft abgelegt wurde (ein Addon ohne Antwort).
    var streamPartial: Set<String> = []
    /// Welle C-b: Abrufzeitpunkt je Addon im Stand von `streamCache[id]` (behaltene Einträge laufen nach ihm ab).
    var streamAddonFetchedAt: [String: [String: Date]] = [:]
    /// Wave F-k R2: cache entries from the visible-tile prefetch (weak tier, evicted first) and running searches
    /// started by it that no page or focus prefetch has joined yet (`StreamCacheTierMarks`).
    private(set) var streamTiers = StreamCacheTierMarks()
    /// Leeres/fehlgeschlagenes Ergebnis: bis dahin kein Vorladen dieser ID (die Detailseite fragt trotzdem).
    private(set) var streamEmptyUntil: [String: Date] = [:]
    /// Task 3.7 (A-A-4): empty searches of different titles in a row; from 3 in 60 s the prefetch pauses.
    private(set) var emptyPause = EmptyPause()
    /// Start of the prefetch pause after „alle Addons leer“ (vermutlich Ratenbegrenzung), nil = none. Only the
    /// prefetch consults it (`StreamPrefetcher.allowed`, renewals started by it), never the search of an open page.
    var streamsAllEmptyAt: Date? { emptyPause.pausedAt }

    /// Task 3.7 (A-A-4): count the raw result of a finished search (before the filter on playable sources).
    /// Hits end the streak and a running pause; every asked addon empty or failed counts as one empty title;
    /// no addon asked (none serves type/ID) counts as nothing.
    func noteSearchOutcome(id: String, raw: [(addon: InstalledAddon, streams: [StreamItem])], failed: Set<String>) {
        let now = Date()
        if raw.contains(where: { !$0.streams.isEmpty }) {
            if emptyPause.recordHit(now: now) { RemoteLog.info("prefetch", "Pause aufgehoben: \(id) hat Quellen") }
            return
        }
        guard !raw.isEmpty || !failed.isEmpty else { return }
        if emptyPause.recordEmpty(id: id, now: now) {
            RemoteLog.info("prefetch", "Vorladen pausiert \(Int(StreamPrefetcher.allEmptyPause)) s: \(EmptyPause.titles) Titel ohne Quellen in \(Int(EmptyPause.window)) s (zuletzt \(id))")
        }
    }

    /// MDBList-Bewertungen (nil ohne Key oder ohne Treffer).
    func ratings(imdb: String, series: Bool) async -> ExternalRatings? {
        guard let k = profile.apiKeys["mdblist"], !k.isEmpty else { return nil }
        return await RatingsStore.shared.ratings(imdb: imdb, series: series, apiKey: k)
    }

    // MARK: Handy-Eingabe

    /// Task 1.4: `GET /export` – all profiles without keys, sync logins and the access part of addon addresses.
    /// Task 2.4: backup version 2 (profiles, progress, kit settings, collection links, device settings). The profile
    /// keys stay at the top level, so build 249/250 and Build 1 still restore the profiles from it.
    func backupData() -> Data { (try? makeBackup(includeSecrets: false)) ?? Data() }

    /// Task 2.4: the complete backup; without secrets the profiles go through `withoutSecrets` (Task 1.4).
    func makeBackup(includeSecrets: Bool) throws -> Data {
        // Fix round 1: the plain export goes through `Backup.withoutSecrets` (profiles, URLs in progress, custom kit
        // sources and links scrubbed or left out, no remote log receiver); the sealed backup keeps everything.
        let s = stored
        var b = Backup(profiles: s, device: device)
        for p in s.profiles {
            let book: ProgressBook? = p.id == profile.id ? progress : progressStore.load(profile: p.id)
            if let book, !book.entries.isEmpty {
                b.progress[p.id] = book
            }
            if let k = FusionKitStore.storedSettings(p.id) { b.fusionKits[p.id] = k }
            if let l = CollectionLinkStore.storedLinks(p.id) { b.collectionLinks[p.id] = l }
        }
        return try (includeSecrets ? b : b.withoutSecrets()).encoded()
    }

    /// Task 2.4: everything cached for the old profile set is dropped after a restore: catalog caches, the kit and
    /// link state of the active profile. Task 3.1: a new epoch (texts, hero data, late results of running tasks),
    /// the source state of the old addon set goes (A-A-8). A running token renewal is forgotten but not cancelled:
    /// it writes its token by ID only into a profile that still holds the renewed one (S-4).
    func profileScopeChanged() {
        clearCatalogCache()
        if scopes.current.profile == profile.id { scopes.bump() } else { scopes.advance(to: profile.id) }
        resetStreamState()
        HeroDetailsCache.all.removeAll(); AddonMetaCache.reset()
        traktRefresh.reset()
        FusionKitStore.shared.profileScopeChanged()
        CollectionLinkStore.shared.profileScopeChanged(self)
    }

    /// Task 1.4: the full backup sealed under a fresh 12-character code (only after „Erlauben“ on the TV); the code is shown
    /// on the TV and never sent to the phone.
    func sealedBackup() -> (file: Data, code: String)? {
        guard storeState == .ready else { lastError = Self.backupLockedText; return nil }
        let code = BackupCrypto.makeCode()
        do {
            let plain = try makeBackup(includeSecrets: true)
            let file = try BackupCrypto(cipher: CryptoKitBackupCipher()).seal(plain, code: code)
            return (file, code)
        } catch { lastError = "Sicherung nicht verschlüsselt: \(error)"; return nil }
    }

    /// Task 1.4: opens a sealed backup with the code typed on the TV; nil (and a message) for a wrong code.
    /// Final review: on failure `data` is nil and `problem` the German reason; the phone card shows it and stays open.
    func openSealedBackup(_ file: Data, code: String) -> (data: Data?, problem: String?) {
        do { return (try BackupCrypto(cipher: CryptoKitBackupCipher()).open(file, code: code), nil) } catch {
            let problem: String
            switch error as? BackupCryptoError {
            case .some(.invalidCode): problem = "Sicherung nicht geöffnet: Der Code hat 12 Zeichen in drei Vierergruppen, zum Beispiel K7QM-2XPA-9DRT."
            case .some(.unsupportedVersion(_)): problem = "Sicherung nicht geöffnet: Sie stammt aus einer neueren Version der App."
            case .some(.unsupportedCode(_)): problem = "Sicherung nicht geöffnet: Diese Datei nutzt ein Code-Verfahren, das diese Version nicht liest. Bitte eine neue Sicherung anlegen."
            default: problem = "Sicherung nicht geöffnet: Code falsch oder Datei beschädigt. Code prüfen und erneut „Erlauben“."
            }
            return (nil, problem)
        }
    }

    static let backupLockedText = "Die Profile sind gerade nicht lesbar. Sichern und Wiederherstellen über das Handy gehen erst wieder, wenn hier eine Fassung geladen oder neu angefangen wurde."

    func apply(_ commands: [PhoneCommand]) async {
        RemoteLog.info("handy", "Befehle: " + commands.map { c -> String in
            switch c {
            case .addAddon(let u): return "addon \(URL(string: u)?.host ?? "?")"
            case .setKey(let s, _): return "key \(s)"
            case .importNuvioURL: return "nuvio-url"
            case .importNuvioJSON: return "nuvio-json"
            case .addTMDBLink(let l): return "link \(l)"
            case .importBackup: return "backup"
            case .importFusionURL: return "kit-url"
            case .moveRow, .removeRow, .deleteRow, .restoreRow, .addRow: return "startseite"
            case .setRatingIconSet: return "icon-satz"   // Welle F-a
            case .importCollectionLink(let u): return "collection-link \(URL(string: u)?.host ?? "?")"   // wave F-o round 2
            case .importCollectionCode: return "collection-code"
            case .exportSecrets: return "sicherung-verschlüsselt"
            }
        }.joined(separator: ", "))
        let noticeBefore = notice
        for c in commands {
            switch c {
            case .addAddon(let u): await installAddon(u)
            case .setKey(let s, let v):
                update { $0.apiKeys[s] = v }
                // Pi-Adresse für „App aktualisieren“ und Fern-Log-Geheimnis betreffen keine Katalog-/Quellendaten.
                if s != AtvloadlyAddress.key && s != LogSignature.secretKey { clearCatalogCache() }
            case .importNuvioURL(let u): await importNuvio(from: u)
            case .importNuvioJSON(let d): importNuvio(data: d)
            case .addTMDBLink(let l):
                if let s = TMDBLink.source(from: l) ?? TraktLink.source(from: l) { addHomeRow(.list(s), style: .poster, via: "Handy-Link") }
                else { lastError = "Link nicht erkannt: \(l)" }
            case .importBackup(let d):
                // Task 1.4: while the stored profiles are unreadable the phone restores nothing (ProfileRecoveryView decides);
                // a sealed file arrives here already opened (PhoneServer.answer).
                guard storeState == .ready else { lastError = Self.backupLockedText; continue }
                guard !BackupCrypto.isSealed(d) else { lastError = "Verschlüsselte Sicherung: bitte den Code am Fernseher eingeben."; continue }
                do {
                    let before = stored.profiles.map(\.id)
                    // Task 2.4: version 2 (with progress, kits, links, device) or an old plain profile backup.
                    let (backup, report) = try Backup.decodeReporting(d)
                    // Final review: like the load line, paths only (a backup from a newer build).
                    if !report.isEmpty { RemoteLog.info("speicher", "Import · ignoriert: \(report.ignored.joined(separator: ", "))") }
                    let (imported, expired) = backup.profiles.droppingExpiredTokens()
                    // Fix round 2: saved directly, so the cleanup below runs only after the restored profiles are
                    // stored (a failed save ends in the catch: nothing is removed).
                    try store.save(imported)
                    stored = imported
                    mirrorSecrets()   // Task 2.2 write rule also after a restore (Keychain follows the saved profiles)
                    for gone in ProfileBlocks.removedByRestore(before: before, after: imported.profiles.map(\.id)) {
                        removeProfileData(gone)
                    }
                    // Parts of version 2 overwrite only what the backup contains; a version 1 file leaves them as they are.
                    for (id, book) in backup.progress where backup.profileIDs.contains(id) {
                        try? progressStore.save(book, profile: id)
                    }
                    for (id, k) in backup.fusionKits where backup.profileIDs.contains(id) { FusionKitStore.setStoredSettings(k, for: id) }
                    for (id, l) in backup.collectionLinks where backup.profileIDs.contains(id) { CollectionLinkStore.setStoredLinks(l, for: id) }
                    // Picture and sound come back; the remote log switch and receiver stay as set on this TV (SEC-2).
                    if let dev = backup.device {
                        updateDevice { $0.audioShaping = dev.audioShaping; $0.displayMode = dev.displayMode }
                    }
                    removeCatalogFiles(profiles: before + stored.profiles.map(\.id))
                    profileScopeChanged()
                    progress = loadProgress(profile.id)
                    RemoteLog.info("speicher", "Sicherung v\(backup.backupVersion) eingespielt · \(backup.progress.count) Fortschritt, \(backup.fusionKits.count) Kits, \(backup.collectionLinks.count) Links" + (expired > 0 ? " · \(expired) abgelaufene Anmeldung(en) entfernt" : ""))
                } catch { lastError = "Sicherung ungültig: \(error)" }
            case .importFusionURL(let u): await importFusionKit(from: u)
            case .moveRow, .removeRow, .deleteRow, .restoreRow, .addRow: applyHome([c])   // Welle F-e; PhoneServer übernimmt sie sonst schon vorab
            case .setRatingIconSet(let u): setRatingIconSet(u)   // Welle F-a (Views/Settings/SourceSettingsRows.swift)
            case .importCollectionLink(let u): await CollectionLinkStore.shared.importLink(u, model: self)   // wave F-o round 2
            case .importCollectionCode(let d): await CollectionLinkStore.shared.importCode(d, model: self)
            case .exportSecrets: break   // PhoneServer.answer seals the file after „Erlauben“
            }
        }
        // An import's own result line ("Import: 3 Reihen, …") stays.
        if lastError == nil, notice == noticeBefore { notice = "\(commands.count) Eingabe(n) vom Handy übernommen." }
    }
}

// MARK: Hero (Startseite)

extension AppModel {
    /// Folien des Hero: Einträge der Hero-Quellreihe über den Reihen-Loader (gleicher Cache), höchstens 8.
    func heroItems(for row: HomeRow) async -> [MetaPreview] {
        guard case .list(let s) = row.content else { return [] }
        return Array(await homeRowItems(s).items.prefix(8))   // Welle F-f: dieselbe Ladung wie die Reihe
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

    /// Wave F-k R3 (I-R2-1): the focus rests on this title. A weak entry or running search of the visible-tile
    /// prefetch becomes strong, so later visible tiles do not push out what the detail page most likely needs next.
    func keepStream(id: String) { streamTiers.keep(id) }

    func streamCacheState(id: String) -> StreamCacheState {
        let now = Date()
        if let c = streamCache[id], RevalidationPolicy.streams.isUsable(storedAt: c.at, now: now) {
            // Welle D-b (M3): veralteter, lückenhafter Stand zählt fürs Vorladen nicht als vollständig gecacht.
            guard partialNeedsRefresh(id: id, now: now) else { return .cached }
            return streamTasks[id] != nil ? .running : .missing
        }
        if streamTasks[id] != nil { return .running }
        if let u = streamEmptyUntil[id], u > now { return .emptyRecently }
        return .missing
    }

    /// Ergebnis ablegen (`StreamCacheUpdate`): Treffer in den Cache (`RevalidationPolicy.streams`; abgelaufene raus,
    /// höchstens 40: Einträge sichtbarer Kacheln zuerst raus, dann die ältesten), Addons mit Fehler/Zeitüberschreitung
    /// behalten ihre alten Einträge, ein lückenhaftes Ergebnis ist nur kurz frisch. Leer (auch nach dem Behalten):
    /// 120 s als „leer“ merken, ein vorhandener Stand bleibt unverändert. Die Pause nach „alle Addons leer“ hebt schon das
    /// Rohergebnis mit Treffern auf (Task 3.7, `noteSearchOutcome`).
    /// Rückgabe: der abgelegte Stand (leer bei leerem Ergebnis).
    fileprivate func storeStreams(id: String, fresh: [(addon: String, stream: StreamItem)],
                                  answered: Set<String>, failed: Set<String>) -> [(addon: String, stream: StreamItem)] {
        let now = Date()
        streamEmptyUntil = streamEmptyUntil.filter { $0.value > now }
        switch StreamCacheUpdate.apply(fresh: fresh, answered: answered, failed: failed, previous: streamCache[id],
                                       previousFetchedAt: streamAddonFetchedAt[id] ?? [:], now: now) {
        case .keepPrevious:
            streamTiers.searchDropped(id)
            streamEmptyUntil[id] = now.addingTimeInterval(Self.emptyStreamsTTL)
            return []
        case let .store(at, list, fetchedAt):
            if list.count != fresh.count {
                RemoteLog.info("streams", "\(id): \(list.count - fresh.count) Quellen ohne Antwort ihres Addons aus dem alten Stand behalten")
            }
            if at != now {
                RemoteLog.info("streams", "\(id): Ergebnis lückenhaft → nur \(Int(AddonSearch.partialCacheSeconds)) s frisch")
            }
            streamEmptyUntil[id] = nil
            streamCache = streamCache.filter { RevalidationPolicy.streams.isUsable(storedAt: $0.value.at, now: now) }
            streamCache[id] = (at, list)
            // Wave F-k R2: visible-tile results are the weak tier and go first; focus/page entries are never pushed
            // out by them (`StreamCacheTiers`).
            for k in streamTiers.stored(id, storedAt: streamCache.mapValues { $0.at }, limit: StreamPrefetcher.cacheLimit) {
                streamCache[k] = nil
            }
            streamAddonFetchedAt = streamAddonFetchedAt.filter { streamCache[$0.key] != nil }
            streamAddonFetchedAt[id] = fetchedAt
            streamPartial = streamPartial.filter { streamCache[$0] != nil }
            if !failed.isEmpty { streamPartial.insert(id) } else { streamPartial.remove(id) }   // Mi1
            // Wave F-k R2 (m2): best values remembered right away, even if this entry is dropped again at once.
            QualityBadgeCache.shared.streamsStored(id: id, list: list, at: at)
            return list
        }
    }

    static let emptyStreamsTTL: TimeInterval = 120
}

// Task 8: Plaketten auf Postern – Schlüssel des Quellen-Caches für eine Kachel, ohne Netzabfrage
// (gleiche Regeln wie StreamPrefetcher.request: Film = IMDb-ID, auch aus dem TMDB-Nachschlage-Cache; Serie = angefangene
// Folge, sonst S1E1).
extension AppModel {
    func streamCacheKey(for m: MetaPreview) -> String? {
        // Wave F-k R1: one rule with the visible-tile prefetch (PlayerCore `PrefetchTarget`): film → IMDb ID,
        // series → started episode, otherwise S1E1 (before: series without progress never had a badge).
        PrefetchTarget.streamID(type: m.type, imdb: cachedIMDbID(for: m),
                                progress: m.type == "series" ? progress.latest(forItem: m.id) : nil)
    }
}
