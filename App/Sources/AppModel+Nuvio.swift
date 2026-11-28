import Foundation
import Observation
import PlayerCore
import UIKit

/// plan_nuvio_konto T8/T9: the Nuvio account sync of the app, kept outside AppModel's stored properties (like
/// `SyncQueueHolder`). The session is device-wide (one account per TV); profile choice, cursors and outbox are per
/// local profile (`NuvioState`, file `nuvio-<profile>.json`). The session lives in memory here and in the Keychain
/// through `NuvioSessionStore`, nowhere else.
@MainActor @Observable
final class NuvioHolder {
    static let shared = NuvioHolder()

    /// The stored session; read once from the Keychain (`AppModel.nuvioSession`).
    var session: NuvioSession?
    /// The account refused a refresh: the session is gone, the row says "Sitzung abgelaufen".
    var expired = false
    /// A sign-in runs.
    var busy = false
    /// Bumped by every state save: the settings status line follows the outbox and the cursors. The states
    /// themselves are not observed, so reading one in a view body (which may fill the cache) never invalidates it.
    var revision = 0
    /// Name of the chosen account profile per local profile (from the choice or the last profile check).
    var profileNames: [UUID: String] = [:]
    /// Outcome of the last pass per local profile in this run of the app.
    var lastOutcome: [UUID: NuvioSyncOutcome] = [:]
    /// Bumped after a sign-in without a chosen profile: the settings page opens the profile picker.
    var profileRequest = 0

    @ObservationIgnored var loaded = false
    /// States per local profile, as on disk (cache).
    @ObservationIgnored var states: [UUID: NuvioState] = [:]
    /// Single-flight refresh (the refresh token rotates); key "nuvio".
    @ObservationIgnored var refresh = TaskSlots<NuvioSession?>()
    /// One pass at a time per local profile; a request while one runs is merged into one more pass.
    @ObservationIgnored var running: Set<UUID> = []
    @ObservationIgnored var again: [UUID: NuvioPassRequest] = [:]
    /// After a 429 that survived the client's retry: no Nuvio call before it (memory only).
    @ObservationIgnored var cooldownUntil: Date?
    @ObservationIgnored var foregroundGate = NuvioTriggerGate(interval: NuvioTriggerGate.foreground)
    @ObservationIgnored var playbackGate = NuvioTriggerGate(interval: NuvioTriggerGate.afterPlayback)
    @ObservationIgnored var observing = false
}

/// A requested pass: mode, whether "Jetzt abgleichen" asked for it, and the trigger for the log line.
struct NuvioPassRequest {
    var mode: NuvioSyncMode
    var manual: Bool
    var reason: String

    func merged(with other: NuvioPassRequest?) -> NuvioPassRequest {
        guard let other else { return self }
        return NuvioPassRequest(mode: mode.merged(with: other.mode), manual: manual || other.manual,
                                reason: mode == .full || other.mode != .full ? reason : other.reason)
    }
}

extension AppModel {
    private static let nuvioRefreshKey = "nuvio"

    // MARK: Session

    /// The stored session (Keychain, read once).
    var nuvioSession: NuvioSession? {
        let h = NuvioHolder.shared
        if !h.loaded {
            h.loaded = true
            h.session = NuvioSessionStore(store: secrets).load()
        }
        return h.session
    }

    /// For `NuvioSyncDependencies.currentSession` (read again before every account call of a pass).
    func currentNuvioSession() -> NuvioSession? { nuvioSession }

    /// Data client: a 401 renews the session once through `renewNuvio` (single flight).
    func nuvioClient() -> NuvioClient {
        NuvioClient(onUnauthorized: { [weak self] old in await self?.renewNuvio(after: old) ?? .unavailable })
    }

    /// One refresh at a time. A caller whose session was already replaced gets the new one. `.refused` wipes the
    /// session (state "Sitzung abgelaufen"); `.unavailable` keeps it.
    func renewNuvio(after old: NuvioSession) async -> NuvioRenewal {
        let h = NuvioHolder.shared, key = Self.nuvioRefreshKey
        if let running = h.refresh[key] {
            if let n = await running.value { return .renewed(n) }
            return nuvioSession == nil ? .refused : .unavailable
        }
        guard let cur = nuvioSession else { return .refused }
        guard cur.userID == old.userID else { return .unavailable }
        if cur != old, !cur.needsRefresh() { return .renewed(cur) }
        // The refresher has no hook of its own (a refused refresh must not ask for another refresh).
        let task = Task { [weak self] () -> NuvioSession? in
            let r = await NuvioClient().renewal(cur)
            guard let self else { return nil }
            switch r {
            case .renewed(let n):
                self.storeRenewedNuvio(n, replacing: cur)
                return n
            case .refused:
                RemoteLog.info("sync", "nuvio: Erneuerung abgelehnt, Sitzung gelöscht")
                if self.nuvioSession == cur {
                    self.wipeNuvioSession(expired: true)
                    self.lastError = NuvioTexts.expired
                }
                return nil
            case .unavailable:
                RemoteLog.info("sync", "nuvio: Erneuerung gerade nicht möglich, Sitzung bleibt")
                return nil
            }
        }
        let ticket = h.refresh.begin(key, task)
        let n = await task.value
        h.refresh.finish(key, ticket)
        if let n { return .renewed(n) }
        return nuvioSession == nil ? .refused : .unavailable
    }

    /// The renewed session goes to the Keychain before any caller uses it; only while the holder still has `cur`
    /// (a sign-out or another sign-in meanwhile wins).
    private func storeRenewedNuvio(_ n: NuvioSession, replacing cur: NuvioSession) {
        let h = NuvioHolder.shared
        guard h.session == cur else {
            RemoteLog.info("sync", "nuvio: erneuerte Sitzung nicht übernommen (abgemeldet oder neu angemeldet)")
            return
        }
        h.session = n
        do { try NuvioSessionStore(store: secrets).save(n) } catch { lastError = NuvioTexts.keychainFailed }
    }

    /// Session gone from memory and Keychain; a running refresh is forgotten.
    func wipeNuvioSession(expired: Bool) {
        let h = NuvioHolder.shared
        h.loaded = true
        h.session = nil
        h.expired = expired
        h.refresh.reset()
        do { try NuvioSessionStore(store: secrets).wipe() } catch {
            RemoteLog.error("sync", "nuvio: Sitzung im Schlüsselbund nicht gelöscht")
        }
    }

    // MARK: State per profile

    private var nuvioStateStore: NuvioStateStore { NuvioStateStore(storage: progressStore.storage) }

    func nuvioState(for id: UUID) -> NuvioState {
        let h = NuvioHolder.shared
        if let s = h.states[id] { return s }
        let s = nuvioStateStore.load(id)
        h.states[id] = s
        return s
    }

    /// False when the file was not written (the in-memory state is kept all the same).
    @discardableResult
    func saveNuvioState(_ s: NuvioState, for id: UUID) -> Bool {
        NuvioHolder.shared.states[id] = s
        NuvioHolder.shared.revision += 1
        do { try nuvioStateStore.save(s, profile: id); return true } catch {
            RemoteLog.error("sync", "nuvio: Abgleichstand nicht gespeichert")
            return false
        }
    }

    /// Profile deleted (or not in a restored backup): its state file and memory go.
    func forgetNuvioProfile(_ id: UUID) {
        let h = NuvioHolder.shared
        nuvioStateStore.remove(id)
        h.states[id] = nil; h.profileNames[id] = nil; h.lastOutcome[id] = nil; h.again[id] = nil
        h.revision += 1
    }

    /// Backup restored: the books of `ids` were replaced, so their next pass pulls from scratch (choice and outbox
    /// stay).
    func resetNuvioCursors(for ids: [UUID]) {
        let h = NuvioHolder.shared
        for id in ids {
            h.states[id] = nil
            var s = nuvioState(for: id)
            guard s.userID != nil || s.profileIndex != nil else { continue }
            s.resetCursors()
            saveNuvioState(s, for: id)
            h.lastOutcome[id] = nil
        }
        if !ids.isEmpty { RemoteLog.info("sync", "nuvio: Abgleichstand von \(ids.count) Profil(en) zurückgesetzt (Sicherung)") }
    }

    // MARK: Status

    var nuvioStatus: NuvioStatus {
        let h = NuvioHolder.shared, id = profile.id
        _ = h.revision
        return NuvioStatus.of(sessionUser: nuvioSession?.userID, expired: h.expired, busy: h.busy,
                              state: nuvioState(for: id), lastOutcome: h.lastOutcome[id], profileName: h.profileNames[id])
    }

    var phoneNuvioState: PhoneNuvioState { nuvioStatus.phone }

    /// "Zuletzt abgeglichen: … · n Änderungen warten · n Einträge übersprungen (unbekannte Kennung)".
    var nuvioStatusLine: String {
        _ = NuvioHolder.shared.revision
        let s = nuvioState(for: profile.id)
        let time = s.lastPullAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
        return NuvioTexts.statusLine(lastSync: time, waiting: s.outbox.entries.count, skipped: s.skipped)
    }

    // MARK: Sign-in, profile choice, sign-out

    /// T8: from the phone page (after „Erlauben“). The two values stay parameters: they go into the sign-in request
    /// and end with this call; nothing keeps or logs them.
    func nuvioSignIn(email: PhoneSecret, password: PhoneSecret) async {
        let h = NuvioHolder.shared
        guard !h.busy else { RemoteLog.info("sync", "nuvio Anmeldung: läuft schon"); return }
        h.busy = true
        notice = NuvioTexts.signInRunning
        let session: NuvioSession
        do {
            session = try await NuvioClient().signIn(email: email.value, password: password.value)
        } catch {
            h.busy = false
            notice = nil
            lastError = NuvioTexts.signInError(error)
            RemoteLog.info("sync", "nuvio Anmeldung: " + ((error as? NuvioError).map { NuvioLog.kind(.failed($0)) } ?? "abgebrochen"))
            return
        }
        h.busy = false
        h.loaded = true
        h.session = session
        h.expired = false
        h.refresh.reset()
        h.cooldownUntil = nil
        var kept = true
        do { try NuvioSessionStore(store: secrets).save(session) } catch { kept = false }
        // Another account than the one this profile was synced with: choice and cursors start over (tombstones stay).
        let id = profile.id
        var st = nuvioState(for: id)
        var other = false
        if let user = st.userID, user != session.userID {
            st.resetForAccount(session.userID)
            other = true
        } else if st.userID == nil {
            st.userID = session.userID
        }
        saveNuvioState(st, for: id)
        h.lastOutcome[id] = nil
        if other { h.profileNames[id] = nil }
        notice = other ? NuvioTexts.otherAccount : NuvioTexts.signedIn
        if !kept { lastError = NuvioTexts.keychainFailed }
        RemoteLog.info("sync", "nuvio Anmeldung: ok" + (other ? " · anderes Konto, Stand zurückgesetzt" : ""))
        if st.profileIndex != nil { await syncNuvio(.full, reason: "anmeldung") }
        else { h.profileRequest += 1 }
    }

    /// The account's profiles for the picker; nil (and a message) when they cannot be read.
    func nuvioProfiles() async -> [NuvioProfile]? {
        guard let s = nuvioSession else { return nil }
        do { return try await nuvioClient().profiles(s) } catch {
            let e = error as? NuvioError ?? .offline
            if case .signedOut = e, nuvioSession == s { wipeNuvioSession(expired: true) }
            lastError = NuvioTexts.error(e)
            return nil
        }
    }

    /// The picker: links the active local profile to `p` and syncs. A PIN profile cannot be chosen (D3).
    func chooseNuvioProfile(_ p: NuvioProfile) {
        guard !p.pinEnabled, let session = nuvioSession else { return }
        let h = NuvioHolder.shared, id = profile.id
        var st = nuvioState(for: id)
        if st.userID != session.userID { st.resetForAccount(session.userID) }
        st.choose(p)
        saveNuvioState(st, for: id)
        h.profileNames[id] = p.name
        h.lastOutcome[id] = nil
        RemoteLog.info("einstellung", "nuvio: Profil \(p.profileIndex) gewählt")
        Task { await syncNuvio(.full, reason: "profilwahl") }
    }

    /// „Abmelden“: the session goes at once (memory, Keychain) and every outbox is emptied; then the server is told,
    /// best effort. Profile choices and pulled progress stay.
    func nuvioSignOut() async {
        let h = NuvioHolder.shared
        let old = nuvioSession
        wipeNuvioSession(expired: false)
        var ids = Set(stored.profiles.map(\.id))
        ids.formUnion(h.states.keys)
        for id in ids {
            var st = nuvioState(for: id)
            guard !st.outbox.isEmpty else { continue }
            st.outbox.removeAll()
            saveNuvioState(st, for: id)
        }
        h.lastOutcome.removeAll()
        h.again.removeAll()
        notice = NuvioTexts.signedOut
        RemoteLog.info("einstellung", "nuvio: abgemeldet")
        guard let old else { return }
        do { try await NuvioClient().signOut(old) } catch {
            RemoteLog.info("sync", "nuvio Abmelden am Server: " + ((error as? NuvioError).map { NuvioLog.kind(.failed($0)) } ?? "abgebrochen"))
        }
    }

    // MARK: Passes

    /// T9: one pass for the active profile. While one runs for it, the request is merged into one more pass. A
    /// pass whose profile is no longer active when it ends does not touch the active one (its outbox waits on disk).
    func syncNuvio(_ mode: NuvioSyncMode = .full, reason: String, manual: Bool = false) async {
        let h = NuvioHolder.shared, owner = profile.id
        guard nuvioSession != nil else { return }
        if mode == .full { _ = h.foregroundGate.allow(now: Date()) }
        let request = NuvioPassRequest(mode: mode, manual: manual, reason: reason)
        guard !h.running.contains(owner) else {
            h.again[owner] = request.merged(with: h.again[owner])
            return
        }
        h.running.insert(owner)
        var next: NuvioPassRequest? = request
        while let job = next {
            guard profile.id == owner, nuvioSession != nil else { break }
            await nuvioPass(job, owner: owner)
            next = h.again.removeValue(forKey: owner)
        }
        h.running.remove(owner)
        h.again[owner] = nil
    }

    private func nuvioPass(_ job: NuvioPassRequest, owner: UUID) async {
        let h = NuvioHolder.shared
        guard let session = nuvioSession else { return }
        let start = ContinuousClock.now
        let previousCooldown = h.cooldownUntil
        let r = await NuvioSync.run(job.mode, session: session, book: progress, state: nuvioState(for: owner),
                                    cooldownUntil: previousCooldown, using: nuvioDependencies())
        let ms = Metric.ms(start.duration(to: ContinuousClock.now))
        let reaction = NuvioPassReaction.of(r.outcome, mode: job.mode, manual: job.manual, previousCooldown: previousCooldown)
        // Device-wide parts, whatever profile is active now.
        if let until = reaction.cooldownUntil { h.cooldownUntil = until }
        if reaction.wipeSession, nuvioSession != nil { wipeNuvioSession(expired: true) }
        let quiet = job.mode != .full && r.outcome == .ok && r.summary.pushed == 0 && r.summary.pushDropped == 0
        if !quiet {
            RemoteLog.info("sync", NuvioLog.passLine(reason: job.reason, mode: job.mode, outcome: r.outcome, summary: r.summary, ms: ms))
            // T11: the same pass as a measuring line (counts only).
            RemoteLog.metric(.syncNuvio, ms: ms, fields: ["modus": job.mode == .full ? "voll" : "senden",
                                                          "ergebnis": NuvioLog.kind(r.outcome),
                                                          "gesendet": "\(r.summary.pushed)", "uebernommen": "\(r.summary.merged)",
                                                          "geloescht": "\(r.summary.deleted)"])
        }
        if let e = reaction.error, lastError != e { lastError = e }
        // Profile parts only onto the profile the pass belongs to, and only while it is active.
        guard profile.id == owner else {
            RemoteLog.info("profil", "Ergebnis verworfen (Profil) · nuvio")
            return
        }
        // A push pass that found nothing due (most calls while playing) changed nothing: no write.
        if quiet, r.changes.isEmpty, !reaction.clearProfile { return }
        var live = nuvioState(for: owner)
        let replay = replayNuvio(r.changes, state: &live)
        guard replay.applied.applied else {
            RemoteLog.info("sync", "nuvio: Ergebnis verworfen (Stand inzwischen geändert)")
            return
        }
        // The book is on its way to disk (or held): only then the state with its cursors.
        guard replay.bookSaved else { return }
        if reaction.clearProfile { live.clearProfile(); h.profileNames[owner] = nil }
        saveNuvioState(live, for: owner)
        if r.outcome != .cancelled { h.lastOutcome[owner] = r.outcome }
        if let p = r.profile, !p.name.isEmpty { h.profileNames[owner] = p.name }
    }

    /// The closures of a pass. Lookups run on the main actor (AppModel); the clock is the wall clock.
    private func nuvioDependencies() -> NuvioSyncDependencies {
        NuvioSyncDependencies(api: nuvioClient(),
                              imdbID: { [weak self] p in await self?.nuvioIMDbLookup(for: p) ?? .unavailable },
                              meta: { [weak self] p in await self?.nuvioMeta(for: p) },
                              now: { Date() },
                              currentSession: { [weak self] in await self?.currentNuvioSession() })
    }

    /// Title and artwork for a nameless pulled row: Cinemeta/metadata addon for `tt` ids; a `tmdb:N` title only once
    /// its IMDb id is known. nil: the row stays staged and is tried again.
    func nuvioMeta(for m: MetaPreview) async -> MetaPreview? {
        var imdb: String? = m.id.hasPrefix("tt") ? m.id : nil
        if imdb == nil, case .found(let id) = await nuvioIMDbLookup(for: m) { imdb = id }
        guard let imdb, let d = await meta(type: m.type, imdb: imdb), !d.name.isEmpty else { return nil }
        return MetaPreview(id: m.id, type: m.type, name: d.name, poster: d.poster, background: d.background, logo: d.logo)
    }

    // MARK: Triggers

    /// App start: the session from the Keychain and the foreground trigger (at most one full pass per 5 min).
    func observeNuvio() {
        let h = NuvioHolder.shared
        _ = nuvioSession
        guard !h.observing else { return }
        h.observing = true
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                   queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.nuvioSession != nil,
                      NuvioHolder.shared.foregroundGate.allow(now: Date()) else { return }
                Task { await self.syncNuvio(.full, reason: "vordergrund") }
            }
        }
    }

    /// Local play (recordProgress, every few seconds): queue it and push when the outbox is due (60 s).
    func nuvioNoteProgress(_ id: String) {
        guard nuvioNote(id, kind: nil) else { return }
        Task { await syncNuvio(.pushOnly(force: false), reason: "fortschritt") }
    }

    /// Pause or stop: push at once (also when Trakt/Simkl are not connected).
    func nuvioPushNow(reason: String) {
        guard nuvioSession != nil else { return }
        Task { await syncNuvio(.pushOnly(force: true), reason: reason) }
    }

    /// End of playback: a full pass (pull too) at most once per minute, else a push.
    func nuvioAfterPlayback() {
        guard nuvioSession != nil else { return }
        let full = NuvioHolder.shared.playbackGate.allow(now: Date())
        Task { await syncNuvio(full ? .full : .pushOnly(force: true), reason: "stopp") }
    }

    /// A8: the app marked a title watched (stop from 80 %, tile action). Without a known length nothing can go out:
    /// counted in the log.
    func nuvioNoteWatched(_ id: String) {
        guard nuvioNote(id, kind: .watched) else { return }
        Task { await syncNuvio(.pushOnly(force: true), reason: "gesehen") }
    }

    /// Queues the local entry `id` of the active profile. Never called for pulled entries.
    @discardableResult
    private func nuvioNote(_ id: String, kind: NuvioOutbox.Kind?) -> Bool {
        guard nuvioSession != nil, let e = progress.entries[id] else { return false }
        let owner = profile.id
        var st = nuvioState(for: owner)
        let k = kind ?? (e.finished ? .watched : .progress)
        let before = st.outbox.keys
        guard st.noteLocal(e, kind: k, now: Date()) else {
            if k == .watched, st.noteLocalAllowed(e) { RemoteLog.info("sync", "nuvio: gesehen ohne Laufzeit · 1 übersprungen") }
            return false
        }
        // A new title or a "watched" goes to disk at once; a newer position of a queued title (every few seconds
        // while playing) stays in memory until the next pass stores the state (at most 60 s, at once on pause/stop).
        if k == .watched || st.outbox.keys != before { saveNuvioState(st, for: owner) }
        else { NuvioHolder.shared.states[owner] = st }
        return true
    }

    /// T9: a local removal the next pulls must not undo (`perform` in AppModel+SyncQueue).
    func nuvioTombstone(_ itemIDs: [String], kind: NuvioTombstone.Kind) {
        guard nuvioSession != nil else { return }
        let owner = profile.id
        var st = nuvioState(for: owner)
        guard st.profileIndex != nil else { return }
        let now = Date()
        for id in Set(itemIDs) where !id.isEmpty { st.tombstone(itemID: id, kind: kind, at: now) }
        saveNuvioState(st, for: owner)
    }
}
