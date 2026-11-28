import Foundation

// Nuvio account sync, T8/T9/T11: the app-side decisions that need no UI and no I/O, so they are tested here (the app
// target builds only on CI): the settings status, the German texts of plan section 4, what a pass outcome does, the
// trigger throttles, outbox notes from local plays and the one log line per pass.

/// What the settings row (and the phone page) shows.
public enum NuvioStatus: Equatable, Sendable {
    case signedOut
    /// The account refused the session at a refresh (password changed, signed out elsewhere); the session is gone.
    case expired
    /// A sign-in runs.
    case busy
    /// Signed in, no Nuvio profile for this local profile (never chosen, gone or replaced on the account, A3).
    case needsProfile
    /// The chosen profile got a PIN (D3): sync stopped until another profile is chosen.
    case pinProtected
    /// `profileName`: from the last profile check or the choice; nil until known.
    case connected(profileName: String?)

    /// `sessionUser`: the stored session's account (nil: no session). `lastOutcome`: of the last pass of this local
    /// profile in this run of the app.
    public static func of(sessionUser: String?, expired: Bool, busy: Bool, state: NuvioState,
                          lastOutcome: NuvioSyncOutcome?, profileName: String?) -> NuvioStatus {
        if busy { return .busy }
        guard let user = sessionUser else { return expired ? .expired : .signedOut }
        // A state of another account is reset by its next pass; its choice does not count meanwhile.
        if let owner = state.userID, owner != user { return .needsProfile }
        guard state.profileIndex != nil else { return .needsProfile }
        if lastOutcome == .pinProtected { return .pinProtected }
        return .connected(profileName: profileName)
    }

    /// A session exists (whatever the profile choice).
    public var isSignedIn: Bool {
        switch self {
        case .needsProfile, .pinProtected, .connected: true
        case .signedOut, .expired, .busy: false
        }
    }

    /// The phone page's form disappears once a session exists.
    public var phone: PhoneNuvioState {
        switch self {
        case .signedOut, .expired: .signedOut
        case .busy: .busy
        case .needsProfile, .pinProtected: .connected(profileName: nil)
        case .connected(let name): .connected(profileName: name)
        }
    }
}

/// The German texts (plan section 4). Nothing here carries an address, id or token.
public enum NuvioTexts {
    public static let rowTitle = "Nuvio-Konto"
    public static let signIn = "Anmelden"
    public static let syncNow = "Jetzt abgleichen"
    public static let changeProfile = "Nuvio-Profil ändern"
    public static let chooseProfile = "Nuvio-Profil wählen"
    public static let pinProtected = "Profil ist PIN-geschützt"
    public static let pinDetail = "Mit PIN geschützt, hier nicht wählbar."
    public static let signOutVerb = "Abmelden"
    public static let signOutTitle = "Von Nuvio abmelden?"
    public static let signOutMessage = "Fortschritt wird nicht mehr abgeglichen. Was schon auf diesem Gerät ist, bleibt."
    public static let signOutHint = "Meldet dich möglicherweise auch auf anderen Geräten bei Nuvio ab."

    public static let signInRunning = "Anmeldung läuft …"
    public static let signedIn = "Mit Nuvio verbunden."
    public static let wrongCredentials = "Nuvio: E-Mail oder Passwort stimmt nicht."
    public static let unreachable = "Nuvio nicht erreichbar. Bitte später erneut versuchen."
    public static let rateLimited = "Nuvio: zu viele Anfragen. Der Abgleich pausiert einige Minuten."
    public static let forbidden = "Nuvio lehnt die Anfrage ab (403)."
    public static let expired = "Nuvio: Sitzung abgelaufen. Bitte am Handy neu anmelden."
    public static let keychainFailed = "Nuvio: Anmeldung konnte nicht gespeichert werden. Nach dem nächsten Start ist eine neue Anmeldung nötig."
    public static let signedOut = "Von Nuvio abgemeldet."
    public static let otherAccount = "Anderes Nuvio-Konto: Profilzuordnung und Abgleichstand wurden zurückgesetzt."

    /// The steps next to the QR code on the TV.
    public static let signInSteps = [
        "1. QR-Code mit dem Handy scannen.",
        "2. Auf der Seite unter „Nuvio-Konto“ E-Mail und Passwort eingeben.",
        "3. Hier am Fernseher „Erlauben“ wählen.",
    ]
    /// Under the steps. Plan section 4 still names the cleartext transport; since T1b the phone encrypts both values,
    /// so the hint says that (the phone page's wording).
    public static let signInHint = PhoneInputPage.nuvioHintText

    public static func value(_ s: NuvioStatus) -> String {
        switch s {
        case .signedOut: "Nicht verbunden"
        case .expired: "Sitzung abgelaufen"
        case .busy: signInRunning
        case .needsProfile: chooseProfile
        case .pinProtected: pinProtected
        case .connected(let name?) where !name.isEmpty: "Verbunden · \(name)"
        case .connected: "Verbunden"
        }
    }

    public static func detail(_ s: NuvioStatus, localProfile: String) -> String {
        switch s {
        case .signedOut: "Anmelden am Handy mit E-Mail und Passwort."
        case .expired: "Bitte am Handy neu anmelden."
        case .busy: signInRunning
        case .needsProfile, .pinProtected: "Nuvio-Profil für „\(localProfile)“ wählen."
        case .connected: "Fortschritt wird abgeglichen. OK öffnet die Optionen."
        }
    }

    public static func pickerText(localProfile: String) -> String {
        "Fortschritt von „\(localProfile)“ wird mit diesem Nuvio-Profil abgeglichen."
    }

    /// `lastSync`: the formatted time of the last finished pull (nil: none yet). Zero counts are left out.
    public static func statusLine(lastSync: String?, waiting: Int, skipped: Int) -> String {
        var parts = [lastSync.map { "Zuletzt abgeglichen: \($0)" } ?? "Noch nicht abgeglichen"]
        if waiting > 0 { parts.append(waiting == 1 ? "1 Änderung wartet" : "\(waiting) Änderungen warten") }
        if skipped > 0 {
            parts.append((skipped == 1 ? "1 Eintrag" : "\(skipped) Einträge") + " übersprungen (unbekannte Kennung)")
        }
        return parts.joined(separator: " · ")
    }

    /// The user text of a failed account call (starts with "Nuvio"; never the decoding detail or an error code).
    public static func error(_ e: NuvioError) -> String {
        switch e {
        case .signedOut: expired
        case .rateLimited: rateLimited
        case .offline: unreachable
        case .status(403, _): forbidden
        case .status(let s, _): "Nuvio: Fehler \(s). Bitte später erneut versuchen."
        case .decoding: "Nuvio: Antwort nicht lesbar."
        }
    }

    /// Sign-in: 400/401/422 is the account's answer to wrong credentials.
    public static func signInError(_ e: Error) -> String {
        guard let n = e as? NuvioError else { return unreachable }
        if case .status(let s, _) = n, [400, 401, 422].contains(s) { return wrongCredentials }
        return error(n)
    }
}

/// What the app does after a pass (plan sections 1.4, 1.7; A3, D3). The profile parts are applied only when the
/// pass result was replayed onto the live state.
public struct NuvioPassReaction: Equatable, Sendable {
    /// The session is gone on the server: wipe it (state "Sitzung abgelaufen").
    public var wipeSession = false
    /// The chosen profile is gone or another one now (A3): back to "Nuvio-Profil wählen".
    public var clearProfile = false
    /// Keep in memory; no Nuvio call before it.
    public var cooldownUntil: Date?
    /// For `lastError` (starts with "Nuvio").
    public var error: String?

    public init(wipeSession: Bool = false, clearProfile: Bool = false, cooldownUntil: Date? = nil, error: String? = nil) {
        self.wipeSession = wipeSession; self.clearProfile = clearProfile; self.cooldownUntil = cooldownUntil
        self.error = error
    }

    /// `manual`: "Jetzt abgleichen". Background passes stay quiet when offline; push-only passes (play, pause,
    /// stop) never raise an error except a lost session or a new rate limit, so playback is not interrupted by
    /// messages that the next foreground pass repeats anyway.
    public static func of(_ o: NuvioSyncOutcome, mode: NuvioSyncMode, manual: Bool, previousCooldown: Date?) -> NuvioPassReaction {
        switch o {
        case .ok, .partial, .notChosen, .pinProtected, .cancelled:
            return NuvioPassReaction()
        case .signedOut:
            return NuvioPassReaction(wipeSession: true, error: NuvioTexts.error(.signedOut))
        case .profileMissing, .profileReplaced:
            return NuvioPassReaction(clearProfile: true)
        case .rateLimited(let until):
            return NuvioPassReaction(cooldownUntil: until,
                                     error: manual || previousCooldown != until ? NuvioTexts.error(.rateLimited) : nil)
        case .offline:
            return NuvioPassReaction(error: manual ? NuvioTexts.error(.offline) : nil)
        case .failed(let e):
            return NuvioPassReaction(error: manual || mode == .full ? NuvioTexts.error(e) : nil)
        }
    }
}

extension NuvioPassReaction {
    /// A push pass (play, pause, stop) that found nothing to do: no log line, no write.
    public static func isQuiet(mode: NuvioSyncMode, outcome: NuvioSyncOutcome, summary: NuvioSyncSummary) -> Bool {
        mode != .full && outcome == .ok && summary.pushed == 0 && summary.pushDropped == 0
    }

    /// The reaction of a pass whose session was replaced meanwhile (signed out, or in again; review 3, findings 2
    /// and 3): nothing but the cooldown, which is about the server, not the account. No wipe of the newer session,
    /// no message about the old one.
    public var forReplacedSession: NuvioPassReaction { NuvioPassReaction(cooldownUntil: cooldownUntil) }

    /// The state to store after the replay (review 3, finding 5). With the book on its way to disk: the replayed
    /// state. Without it (book file held or not written) the cursors must not pass the book, so the live state from
    /// before the replay is kept, and only the profile reaction (A3: back to "Nuvio-Profil wählen") goes onto it.
    /// nil: nothing to store.
    public func stateToStore(before: NuvioState, replayed: NuvioState, bookSaved: Bool) -> NuvioState? {
        var s: NuvioState
        if bookSaved { s = replayed } else if clearProfile { s = before } else { return nil }
        if clearProfile { s.clearProfile() }
        return s
    }
}

/// What the app does with a finished pass (review 3, findings 2, 3, 5).
public enum NuvioPassFate: Equatable, Sendable {
    /// Signed out or signed in again while it ran: nothing of it is used (no replay, no save, no wipe, no status).
    case dropSession
    /// Another local profile is active by now: only the device-wide parts (cooldown, wipe, message).
    case otherProfile
    /// A quiet push pass that changed nothing: no write.
    case nothing
    /// Replay onto the live state, store, set the status.
    case replay

    /// `sameSession`: the session epoch is the one the pass started with (a renewal keeps it).
    public static func of(sameSession: Bool, ownerActive: Bool, quiet: Bool, changed: Bool,
                          clearProfile: Bool) -> NuvioPassFate {
        guard sameSession else { return .dropSession }
        guard ownerActive else { return .otherProfile }
        if quiet, !changed, !clearProfile { return .nothing }
        return .replay
    }
}

/// Which passes may start, per local profile (review 3, findings 1 and 9a). Checked synchronously when a trigger
/// asks, so two triggers at the same moment (app start: "didBecomeActive" and the start sync) give one pass.
/// - A foreground pass (foreground, app start, profile switch) at most once per `foreground`; every full pass that
///   starts counts.
/// - A non-forced push pass (progress while playing) only when the outbox is due, and at most once per
///   `NuvioOutbox.interval` whatever the last pass ended with (a stop at the profile check records no push attempt,
///   so the outbox throttle alone would let every progress report ask the account again).
/// - No push pass at all while the profile's last outcome was `.pinProtected` (D3: sync stops), until the profile is
///   chosen again (`reset`) or a full pass (manual, foreground, after playback) ends otherwise.
/// A clock that went back never blocks.
public struct NuvioPassGate: Equatable, Sendable {
    public static let foreground: TimeInterval = NuvioTriggerGate.foreground
    public static let push: TimeInterval = NuvioOutbox.interval

    public private(set) var lastFull: [UUID: Date] = [:]
    public private(set) var lastPass: [UUID: Date] = [:]
    public private(set) var stopped: Set<UUID> = []

    public init() {}

    /// True (and remembers the start) when the pass may run. `foreground`: a trigger the foreground interval
    /// applies to; `outboxDue`: `NuvioOutbox.isDue(now:force: false)` of the profile (read for non-forced pushes).
    public mutating func admit(_ mode: NuvioSyncMode, profile: UUID, now: Date, manual: Bool = false,
                               foreground: Bool = false, outboxDue: Bool = true) -> Bool {
        switch mode {
        case .full:
            if foreground, !manual, Self.within(lastFull[profile], Self.foreground, now) { return false }
            lastFull[profile] = now
        case .pushOnly(let force):
            if stopped.contains(profile), !manual { return false }
            if !force, !manual, !outboxDue || Self.within(lastPass[profile], Self.push, now) { return false }
        }
        lastPass[profile] = now
        return true
    }

    /// The outcome of a pass of `profile` whose result was used.
    public mutating func finished(_ outcome: NuvioSyncOutcome, profile: UUID) {
        switch outcome {
        case .pinProtected: stopped.insert(profile)
        case .ok, .partial, .notChosen, .profileMissing, .profileReplaced: stopped.remove(profile)
        case .signedOut, .rateLimited, .offline, .failed, .cancelled: break
        }
    }

    /// Profile chosen again, cursors reset (restore) or profile gone: everything of it starts over.
    public mutating func reset(_ profile: UUID) {
        lastFull[profile] = nil; lastPass[profile] = nil; stopped.remove(profile)
    }

    /// Sign-out.
    public mutating func removeAll() { self = NuvioPassGate() }

    static func within(_ last: Date?, _ interval: TimeInterval, _ now: Date) -> Bool {
        guard let last else { return false }
        let gap = now.timeIntervalSince(last)
        return gap >= 0 && gap < interval
    }
}

extension NuvioIDLookup {
    /// The answer for a failed TMDB lookup (review 3, finding 4). `TMDBClient` fetches through
    /// `HTTPClientFetcher`, which throws `AddonError.http(status)` for a non-2xx answer: a 404 means TMDB has no such
    /// title (counted as `notFound`); everything else (offline, 401 for a bad key, 429, 5xx) is `unavailable`.
    public static func of(error: Error) -> NuvioIDLookup {
        switch error {
        case AddonError.http(404), APIError.status(404): .notFound
        default: .unavailable
        }
    }
}

extension NuvioSyncMode {
    /// Two requests for one pass: a full pass covers a push; `force` wins.
    public func merged(with other: NuvioSyncMode?) -> NuvioSyncMode {
        switch (self, other) {
        case (_, nil): self
        case (.full, _), (_, .full?): .full
        case (.pushOnly(let a), .pushOnly(let b)?): .pushOnly(force: a || b)
        }
    }
}

/// At most one trigger per `interval` (foreground pull: 5 min, pull after playback: 60 s). A clock that went back
/// never blocks.
public struct NuvioTriggerGate: Equatable, Sendable {
    public static let foreground: TimeInterval = 300
    public static let afterPlayback: TimeInterval = 60

    public let interval: TimeInterval
    public private(set) var last: Date?

    public init(interval: TimeInterval) { self.interval = interval }

    /// True (and remembers `now`) when the trigger may run.
    public mutating func allow(now: Date) -> Bool {
        if let last {
            let gap = now.timeIntervalSince(last)
            if gap >= 0, gap < interval { return false }
        }
        last = now
        return true
    }

    public mutating func reset() { last = nil }
}

extension NuvioState {
    /// The local entry may go to the account: a profile is chosen and the title has an id the account knows
    /// (`tt…` or `tmdb:N`; addon-only ids stay local).
    public func noteLocalAllowed(_ e: WatchProgress) -> Bool {
        guard profileIndex != nil else { return false }
        switch NuvioMapping.remoteID(e.item.id) {
        case .imdb, .tmdb: return true
        case .other: return false
        }
    }

    /// T9: queues a local play (or a local "watched", A8) for the account under the account's form of the id. False
    /// when it cannot go out: no profile, an id the account does not know, no known length, a whole-series marker.
    /// Only local plays come here, never pulled entries (plan section 1.6).
    @discardableResult
    public mutating func noteLocal(_ e: WatchProgress, kind: NuvioOutbox.Kind = .progress, now: Date) -> Bool {
        guard noteLocalAllowed(e) else { return false }
        let series = e.season != nil || ContentKind.isEpisodic(type: e.item.type)
        guard let p = NuvioMapping.push(e, contentID: remoteID(local: e.item.id, series: series)) else { return false }
        outbox.note(p, kind: kind, now: now)
        return true
    }

    /// A local removal ("Aus Weiterschauen entfernen", "als ungesehen") that later pulls must not undo (A4).
    /// Review 3, finding 9b: recorded whenever a Nuvio profile is chosen, with or without a session, so a removal
    /// made while signed out or expired still holds after the next sign-in. False (nothing recorded): none chosen.
    @discardableResult
    public mutating func noteRemoval(_ itemIDs: [String], kind: NuvioTombstone.Kind, now: Date) -> Bool {
        guard profileIndex != nil else { return false }
        for id in Set(itemIDs) where !id.isEmpty { tombstone(itemID: id, kind: kind, at: now) }
        return true
    }
}

/// The one log line per pass: reason, mode, outcome kind and counts; never ids, tokens or names.
public enum NuvioLog {
    public static func kind(_ o: NuvioSyncOutcome) -> String {
        switch o {
        case .ok: "ok"
        case .partial: "partial"
        case .notChosen: "notChosen"
        case .profileMissing: "profileMissing"
        case .profileReplaced: "profileReplaced"
        case .pinProtected: "pinProtected"
        case .signedOut: "signedOut"
        case .rateLimited: "rateLimited"
        case .offline: "offline"
        case .cancelled: "cancelled"
        case .failed(let e):
            switch e {
            case .status(let s, _): "failed \(s)"
            case .decoding: "failed decoding"
            case .offline: "failed offline"
            case .rateLimited: "failed rateLimited"
            case .signedOut: "failed signedOut"
            }
        }
    }

    public static func passLine(reason: String, mode: NuvioSyncMode, outcome: NuvioSyncOutcome,
                                summary s: NuvioSyncSummary, ms: Int) -> String {
        let m = mode == .full ? "voll" : "senden"
        var parts = ["nuvio \(reason) (\(m)): \(kind(outcome))", "\(s.pushed) gesendet", "\(s.merged) übernommen",
                     "\(s.deleted) gelöscht", "\(s.skipped) übersprungen", "\(s.staged) ohne Titel"]
        if s.bootstrapped { parts.append("Erstabgleich") }
        if s.moreToPull { parts.append("weitere Seiten") }
        if s.pushDropped > 0 { parts.append("\(s.pushDropped) verworfen") }
        if s.pendingIDs > 0 { parts.append("\(s.pendingIDs) Kennungen offen") }
        if s.snapshotCapped { parts.append("Schnappschuss voll") }
        parts.append("\(max(0, ms)) ms")
        return parts.joined(separator: " · ")
    }
}
