import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T8/T9/T11: the app-side decisions (status, texts, reactions, throttles, outbox notes, log
// line). Invented values only.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

private func chosen(user: String = "u1", index: Int = 1) -> NuvioState {
    var s = NuvioState()
    s.userID = user
    s.profileIndex = index
    return s
}

private func film(_ id: String = "tt0137523", position: Double = 600, duration: Double = 6000,
                  finished: Bool = false) -> WatchProgress {
    WatchProgress(id: id, item: MetaPreview(id: id, type: "movie", name: "Film"), position: position,
                  duration: duration, updated: t0, finished: finished)
}

private func episode(_ item: String = "tt0903747", season: Int = 1, number: Int = 2) -> WatchProgress {
    WatchProgress(id: "\(item):\(season):\(number)", item: MetaPreview(id: item, type: "series", name: "Serie"),
                  season: season, episode: number, position: 300, duration: 2700, updated: t0)
}

// MARK: Status

@Test func nuvioStatusFollowsSessionStateAndOutcome() {
    #expect(NuvioStatus.of(sessionUser: nil, expired: false, busy: false, state: chosen(), lastOutcome: nil,
                           profileName: nil) == .signedOut)
    #expect(NuvioStatus.of(sessionUser: nil, expired: true, busy: false, state: chosen(), lastOutcome: nil,
                           profileName: nil) == .expired)
    #expect(NuvioStatus.of(sessionUser: nil, expired: true, busy: true, state: chosen(), lastOutcome: nil,
                           profileName: nil) == .busy)
    #expect(NuvioStatus.of(sessionUser: "u1", expired: false, busy: false, state: NuvioState(), lastOutcome: nil,
                           profileName: nil) == .needsProfile)
    #expect(NuvioStatus.of(sessionUser: "u1", expired: false, busy: false, state: chosen(), lastOutcome: .ok,
                           profileName: "Anna") == .connected(profileName: "Anna"))
    #expect(NuvioStatus.of(sessionUser: "u1", expired: false, busy: false, state: chosen(), lastOutcome: .pinProtected,
                           profileName: "Anna") == .pinProtected)
    // The state still belongs to another account (reset at its next pass): the choice does not count.
    #expect(NuvioStatus.of(sessionUser: "u2", expired: false, busy: false, state: chosen(user: "u1"), lastOutcome: nil,
                           profileName: "Anna") == .needsProfile)
    // A state that never saw a pass yet (userID nil) with a chosen index counts as chosen.
    var fresh = NuvioState(); fresh.profileIndex = 2
    #expect(NuvioStatus.of(sessionUser: "u1", expired: false, busy: false, state: fresh, lastOutcome: nil,
                           profileName: nil) == .connected(profileName: nil))
}

@Test func nuvioStatusPhoneState() {
    #expect(NuvioStatus.signedOut.phone == .signedOut)
    #expect(NuvioStatus.expired.phone == .signedOut)
    #expect(NuvioStatus.busy.phone == .busy)
    #expect(NuvioStatus.needsProfile.phone == .connected(profileName: nil))
    #expect(NuvioStatus.pinProtected.phone == .connected(profileName: nil))
    #expect(NuvioStatus.connected(profileName: "Anna").phone == .connected(profileName: "Anna"))
    #expect(NuvioStatus.connected(profileName: "Anna").isSignedIn)
    #expect(!NuvioStatus.expired.isSignedIn)
    #expect(!NuvioStatus.busy.isSignedIn)
}

// MARK: Texts (plan section 4)

@Test func nuvioRowTexts() {
    #expect(NuvioTexts.rowTitle == "Nuvio-Konto")
    #expect(NuvioTexts.value(.signedOut) == "Nicht verbunden")
    #expect(NuvioTexts.value(.expired) == "Sitzung abgelaufen")
    #expect(NuvioTexts.value(.connected(profileName: "Anna")) == "Verbunden · Anna")
    #expect(NuvioTexts.value(.connected(profileName: nil)) == "Verbunden")
    #expect(NuvioTexts.value(.needsProfile) == "Nuvio-Profil wählen")
    #expect(NuvioTexts.value(.pinProtected) == "Profil ist PIN-geschützt")
    #expect(NuvioTexts.value(.busy) == "Anmeldung läuft …")
    #expect(NuvioTexts.detail(.signedOut, localProfile: "Wohnzimmer") == "Anmelden am Handy mit E-Mail und Passwort.")
    #expect(NuvioTexts.detail(.needsProfile, localProfile: "Wohnzimmer") == "Nuvio-Profil für „Wohnzimmer“ wählen.")
    #expect(NuvioTexts.detail(.pinProtected, localProfile: "Wohnzimmer") == "Nuvio-Profil für „Wohnzimmer“ wählen.")
    #expect(NuvioTexts.detail(.connected(profileName: "Anna"), localProfile: "X")
            == "Fortschritt wird abgeglichen. OK öffnet die Optionen.")
    #expect(NuvioTexts.detail(.expired, localProfile: "X") == "Bitte am Handy neu anmelden.")
    #expect(NuvioTexts.pickerText(localProfile: "Wohnzimmer")
            == "Fortschritt von „Wohnzimmer“ wird mit diesem Nuvio-Profil abgeglichen.")
}

@Test func nuvioSignInPageTexts() {
    #expect(NuvioTexts.signInSteps == ["1. QR-Code mit dem Handy scannen.",
                                        "2. Auf der Seite unter „Nuvio-Konto“ E-Mail und Passwort eingeben.",
                                        "3. Hier am Fernseher „Erlauben“ wählen."])
    #expect(NuvioTexts.signInHint.contains("verschlüsselt"))
    #expect(NuvioTexts.signInHint.contains("Das Passwort wird nicht gespeichert."))
}

@Test func nuvioStatusLine() {
    #expect(NuvioTexts.statusLine(lastSync: "12:30", waiting: 0, skipped: 0) == "Zuletzt abgeglichen: 12:30")
    #expect(NuvioTexts.statusLine(lastSync: "12:30", waiting: 3, skipped: 2)
            == "Zuletzt abgeglichen: 12:30 · 3 Änderungen warten · 2 Einträge übersprungen (unbekannte Kennung)")
    #expect(NuvioTexts.statusLine(lastSync: "12:30", waiting: 1, skipped: 1)
            == "Zuletzt abgeglichen: 12:30 · 1 Änderung wartet · 1 Eintrag übersprungen (unbekannte Kennung)")
    #expect(NuvioTexts.statusLine(lastSync: nil, waiting: 2, skipped: 0) == "Noch nicht abgeglichen · 2 Änderungen warten")
}

@Test func nuvioErrorTexts() {
    #expect(NuvioTexts.error(.offline) == "Nuvio nicht erreichbar. Bitte später erneut versuchen.")
    #expect(NuvioTexts.error(.rateLimited) == "Nuvio: zu viele Anfragen. Der Abgleich pausiert einige Minuten.")
    #expect(NuvioTexts.error(.status(403, code: "42501")) == "Nuvio lehnt die Anfrage ab (403).")
    #expect(NuvioTexts.error(.signedOut) == "Nuvio: Sitzung abgelaufen. Bitte am Handy neu anmelden.")
    #expect(NuvioTexts.error(.status(500, code: nil)) == "Nuvio: Fehler 500. Bitte später erneut versuchen.")
    // The decoding detail never reaches the screen.
    #expect(NuvioTexts.error(.decoding("tt0137523 token=abc")) == "Nuvio: Antwort nicht lesbar.")
    for t in [NuvioTexts.error(.offline), NuvioTexts.error(.status(418, code: "x")), NuvioTexts.signedOut,
              NuvioTexts.keychainFailed, NuvioTexts.otherAccount, NuvioTexts.signedIn] {
        #expect(t.hasPrefix("Nuvio") || t.hasPrefix("Von Nuvio") || t.hasPrefix("Mit Nuvio") || t.hasPrefix("Anderes Nuvio"))
    }
}

@Test func nuvioSignInErrorTexts() {
    #expect(NuvioTexts.signInError(NuvioError.status(400, code: "invalid_grant"))
            == "Nuvio: E-Mail oder Passwort stimmt nicht.")
    #expect(NuvioTexts.signInError(NuvioError.status(401, code: nil)) == "Nuvio: E-Mail oder Passwort stimmt nicht.")
    #expect(NuvioTexts.signInError(NuvioError.status(422, code: nil)) == "Nuvio: E-Mail oder Passwort stimmt nicht.")
    #expect(NuvioTexts.signInError(NuvioError.offline) == "Nuvio nicht erreichbar. Bitte später erneut versuchen.")
    #expect(NuvioTexts.signInError(NuvioError.rateLimited)
            == "Nuvio: zu viele Anfragen. Der Abgleich pausiert einige Minuten.")
    #expect(NuvioTexts.signInError(NuvioError.status(403, code: nil)) == "Nuvio lehnt die Anfrage ab (403).")
    #expect(NuvioTexts.signInError(CancellationError()) == "Nuvio nicht erreichbar. Bitte später erneut versuchen.")
}

// MARK: Reactions

@Test func nuvioReactionToOutcomes() {
    let full = NuvioSyncMode.full, push = NuvioSyncMode.pushOnly(force: true)
    #expect(NuvioPassReaction.of(.ok, mode: full, manual: false, previousCooldown: nil) == NuvioPassReaction())
    #expect(NuvioPassReaction.of(.partial, mode: full, manual: true, previousCooldown: nil) == NuvioPassReaction())
    #expect(NuvioPassReaction.of(.cancelled, mode: full, manual: true, previousCooldown: nil) == NuvioPassReaction())
    #expect(NuvioPassReaction.of(.notChosen, mode: full, manual: true, previousCooldown: nil) == NuvioPassReaction())

    let out = NuvioPassReaction.of(.signedOut, mode: push, manual: false, previousCooldown: nil)
    #expect(out.wipeSession && out.error == NuvioTexts.error(.signedOut) && !out.clearProfile)

    for o in [NuvioSyncOutcome.profileMissing, .profileReplaced] {
        let r = NuvioPassReaction.of(o, mode: full, manual: false, previousCooldown: nil)
        #expect(r.clearProfile && !r.wipeSession && r.error == nil)
    }
    #expect(NuvioPassReaction.of(.pinProtected, mode: full, manual: true, previousCooldown: nil) == NuvioPassReaction())

    let until = t0.addingTimeInterval(300)
    let first = NuvioPassReaction.of(.rateLimited(until: until), mode: push, manual: false, previousCooldown: nil)
    #expect(first.cooldownUntil == until && first.error == NuvioTexts.error(.rateLimited))
    // The same running cooldown again: no second message.
    let again = NuvioPassReaction.of(.rateLimited(until: until), mode: full, manual: false, previousCooldown: until)
    #expect(again.cooldownUntil == until && again.error == nil)
    // A press on "Jetzt abgleichen" during the cooldown says why nothing happens.
    #expect(NuvioPassReaction.of(.rateLimited(until: until), mode: full, manual: true, previousCooldown: until).error
            == NuvioTexts.error(.rateLimited))

    // Offline: only a manual pass says so; failures also on a full pass, never on a background push.
    #expect(NuvioPassReaction.of(.offline, mode: full, manual: false, previousCooldown: nil).error == nil)
    #expect(NuvioPassReaction.of(.offline, mode: full, manual: true, previousCooldown: nil).error
            == NuvioTexts.error(.offline))
    let denied = NuvioSyncOutcome.failed(.status(403, code: nil))
    #expect(NuvioPassReaction.of(denied, mode: full, manual: false, previousCooldown: nil).error
            == "Nuvio lehnt die Anfrage ab (403).")
    #expect(NuvioPassReaction.of(denied, mode: push, manual: false, previousCooldown: nil).error == nil)
}

// MARK: Modes and throttles

@Test func nuvioModeMerge() {
    let full = NuvioSyncMode.full
    #expect(NuvioSyncMode.pushOnly(force: false).merged(with: nil) == .pushOnly(force: false))
    #expect(NuvioSyncMode.pushOnly(force: false).merged(with: .pushOnly(force: true)) == .pushOnly(force: true))
    #expect(NuvioSyncMode.pushOnly(force: true).merged(with: .pushOnly(force: false)) == .pushOnly(force: true))
    #expect(NuvioSyncMode.pushOnly(force: true).merged(with: full) == full)
    #expect(full.merged(with: .pushOnly(force: false)) == full)
}

@Test func nuvioTriggerGate() {
    var g = NuvioTriggerGate(interval: NuvioTriggerGate.foreground)
    #expect(NuvioTriggerGate.foreground == 300 && NuvioTriggerGate.afterPlayback == 60)
    let r1 = g.allow(now: t0)
    #expect(r1)
    let r2 = g.allow(now: t0.addingTimeInterval(299))
    #expect(!r2)
    let r3 = g.allow(now: t0.addingTimeInterval(300))
    #expect(r3)
    // A clock that went back never blocks.
    let r4 = g.allow(now: t0)
    #expect(r4)
    g.reset()
    let r5 = g.allow(now: t0.addingTimeInterval(1))
    #expect(r5)
}

// MARK: Outbox notes from local plays

@Test func nuvioNoteLocalProgress() {
    var s = chosen()
    let r6 = s.noteLocal(film(), now: t0)
    #expect(r6)
    #expect(s.outbox.entries["tt0137523"]?.push.position == 600_000)
    #expect(s.outbox.entries["tt0137523"]?.kind == .progress)
    let r7 = s.noteLocal(episode(), now: t0)
    #expect(r7)
    #expect(s.outbox.entries["tt0903747_s1e2"]?.push.contentType == "series")
}

@Test func nuvioNoteLocalUsesTheAccountsID() {
    var s = chosen()
    s.link(NuvioIDLink(local: "tt0903747", remote: "tmdb:1396", series: true))
    let r8 = s.noteLocal(episode(), now: t0)
    #expect(r8)
    #expect(s.outbox.entries["tmdb:1396_s1e2"]?.push.videoID == "tmdb:1396:1:2")
    // A film link does not apply to the series of the same local id.
    s.link(NuvioIDLink(local: "tt0137523", remote: "tmdb:550", series: false))
    let r9 = s.noteLocal(film(), now: t0)
    #expect(r9)
    #expect(s.outbox.entries["tmdb:550"] != nil)
}

@Test func nuvioNoteLocalWatchedSendsTheEnd() {
    var s = chosen()
    let r10 = s.noteLocal(film(position: 0, finished: true), kind: .watched, now: t0)
    #expect(r10)
    #expect(s.outbox.entries["tt0137523"]?.push.position == 6_000_000)
    #expect(s.outbox.entries["tt0137523"]?.kind == .watched)
}

@Test func nuvioNoteLocalRefusesWhatCannotGoOut() {
    var s = chosen()
    let r11 = s.noteLocal(film(duration: 0), now: t0)
    #expect(!r11)                    // no known length
    let r12 = s.noteLocal(film(duration: .infinity), now: t0)
    #expect(!r12)
    let marker = WatchProgress(id: "tt0903747", item: MetaPreview(id: "tt0903747", type: "series", name: "Serie"),
                               position: 0, duration: 2700, updated: t0, finished: true)
    let r13 = s.noteLocal(marker, kind: .watched, now: t0)
    #expect(!r13)               // whole-series marker
    let r14 = s.noteLocal(film("kitsu:1"), now: t0)
    #expect(!r14)                       // id the account cannot address
    let r15 = s.noteLocal(film("yt:abc"), now: t0)
    #expect(!r15)
    #expect(s.outbox.isEmpty)
    var none = NuvioState()                                                 // no profile chosen
    let r16 = none.noteLocal(film(), now: t0)
    #expect(!r16)
    #expect(none.outbox.isEmpty)
    #expect(chosen().noteLocalAllowed(film("tmdb:550")))
}

// MARK: Log line

@Test func nuvioPassLogLine() {
    var sum = NuvioSyncSummary()
    sum.pushed = 3; sum.merged = 12; sum.deleted = 1; sum.skipped = 2; sum.staged = 5
    let line = NuvioLog.passLine(reason: "start", mode: .full, outcome: .ok, summary: sum, ms: 840)
    #expect(line == "nuvio start (voll): ok · 3 gesendet · 12 übernommen · 1 gelöscht · 2 übersprungen · 5 ohne Titel · 840 ms")
    var more = NuvioSyncSummary()
    more.bootstrapped = true; more.moreToPull = true; more.pushDropped = 1; more.pendingIDs = 4
    let l2 = NuvioLog.passLine(reason: "pause", mode: .pushOnly(force: true), outcome: .failed(.status(403, code: "x")),
                               summary: more, ms: 12)
    #expect(l2 == "nuvio pause (senden): failed 403 · 0 gesendet · 0 übernommen · 0 gelöscht · 0 übersprungen · 0 ohne Titel"
            + " · Erstabgleich · weitere Seiten · 1 verworfen · 4 Kennungen offen · 12 ms")
    #expect(NuvioLog.kind(.rateLimited(until: t0)) == "rateLimited")
    #expect(NuvioLog.kind(.failed(.decoding("tt123 secret"))) == "failed decoding")
    #expect(NuvioLog.kind(.failed(.offline)) == "failed offline")
    #expect(NuvioLog.kind(.profileReplaced) == "profileReplaced")
}
