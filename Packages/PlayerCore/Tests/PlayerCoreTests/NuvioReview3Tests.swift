import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PlayerCore

// Nuvio account sync, review 3 of the app part: the decisions moved into PlayerCore (pass gate, pass fate, state to
// store, TMDB 404, removal tombstones, local plays, import account checks, origin marks). Invented values only.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
private let a = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
private let b = UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!

private func chosen(user: String = "u1", index: Int = 1) -> NuvioState {
    var s = NuvioState()
    s.userID = user
    s.profileIndex = index
    return s
}

// MARK: Finding 1: push passes per interval, none while PIN-protected

@Test func nuvioGatePushOnlyOncePerIntervalWhateverTheOutcome() {
    var g = NuvioPassGate()
    do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0); #expect(ok) }
    // The pass stopped at the profile check (offline, failed): no push attempt in the outbox, still no new pass.
    g.finished(.offline, profile: a)
    for s in [5.0, 30, 59] { do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0.addingTimeInterval(s)); #expect(!ok) } }
    // Per profile.
    do { let ok = g.admit(.pushOnly(force: false), profile: b, now: t0.addingTimeInterval(5)); #expect(ok) }
    do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0.addingTimeInterval(60)); #expect(ok) }
    // Nothing due in the outbox: no pass, and nothing remembered.
    do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0.addingTimeInterval(200), outboxDue: false); #expect(!ok) }
    do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0.addingTimeInterval(201)); #expect(ok) }
    // Pause and stop push at once.
    do { let ok = g.admit(.pushOnly(force: true), profile: a, now: t0.addingTimeInterval(202)); #expect(ok) }
    // A clock that went back never blocks.
    do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0); #expect(ok) }
}

@Test func nuvioGateStopsPushPassesWhilePinProtected() {
    var g = NuvioPassGate()
    do { let ok = g.admit(.full, profile: a, now: t0); #expect(ok) }
    g.finished(.pinProtected, profile: a)
    // D3: no push pass at all, forced or not, however much later.
    do { let ok = g.admit(.pushOnly(force: false), profile: a, now: t0.addingTimeInterval(3600)); #expect(!ok) }
    do { let ok = g.admit(.pushOnly(force: true), profile: a, now: t0.addingTimeInterval(3600)); #expect(!ok) }
    do { let ok = g.admit(.pushOnly(force: true), profile: b, now: t0.addingTimeInterval(3600)); #expect(ok) }
    // Errors of later full passes do not lift it; a manual pass runs and its outcome decides.
    g.finished(.offline, profile: a)
    do { let ok = g.admit(.pushOnly(force: true), profile: a, now: t0.addingTimeInterval(3601)); #expect(!ok) }
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(3602), manual: true); #expect(ok) }
    g.finished(.ok, profile: a)
    do { let ok = g.admit(.pushOnly(force: true), profile: a, now: t0.addingTimeInterval(3603)); #expect(ok) }
    // Choosing a profile again lifts it as well.
    g.finished(.pinProtected, profile: a)
    g.reset(a)
    do { let ok = g.admit(.pushOnly(force: true), profile: a, now: t0.addingTimeInterval(3604)); #expect(ok) }
    g.finished(.pinProtected, profile: a)
    g.removeAll()
    do { let ok = g.admit(.pushOnly(force: true), profile: a, now: t0.addingTimeInterval(3605)); #expect(ok) }
}

// MARK: Finding 9a: one full pass at launch

@Test func nuvioGateGivesOneForegroundPassForTwoTriggers() {
    var g = NuvioPassGate()
    // didBecomeActive and the start sync at launch.
    do { let ok = g.admit(.full, profile: a, now: t0, foreground: true); #expect(ok) }
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(1), foreground: true); #expect(!ok) }
    // Another local profile (a switch) has its own.
    do { let ok = g.admit(.full, profile: b, now: t0.addingTimeInterval(2), foreground: true); #expect(ok) }
    // Other full passes (sign-in, profile choice, after playback, manual) are not held back, and they count.
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(100)); #expect(ok) }
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(399), foreground: true); #expect(!ok) }
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(400), foreground: true); #expect(ok) }
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(401), manual: true, foreground: true); #expect(ok) }
    // A restore resets the profile: its pass runs.
    g.reset(a)
    do { let ok = g.admit(.full, profile: a, now: t0.addingTimeInterval(402), foreground: true); #expect(ok) }
}

// MARK: Findings 2, 3, 5: what a finished pass does

@Test func nuvioPassFateDropsAPassOfAReplacedSession() {
    #expect(NuvioPassFate.of(sameSession: false, ownerActive: true, quiet: false, changed: true, clearProfile: true)
            == .dropSession)
    #expect(NuvioPassFate.of(sameSession: true, ownerActive: false, quiet: false, changed: true, clearProfile: false)
            == .otherProfile)
    #expect(NuvioPassFate.of(sameSession: true, ownerActive: true, quiet: true, changed: false, clearProfile: false)
            == .nothing)
    #expect(NuvioPassFate.of(sameSession: true, ownerActive: true, quiet: true, changed: true, clearProfile: false)
            == .replay)
    #expect(NuvioPassFate.of(sameSession: true, ownerActive: true, quiet: false, changed: false, clearProfile: false)
            == .replay)
    // The signed-out pass of an old session neither wipes the new one nor reports; the cooldown stays.
    let until = t0.addingTimeInterval(300)
    let wipe = NuvioPassReaction.of(.signedOut, mode: .full, manual: true, previousCooldown: nil)
    #expect(wipe.wipeSession && wipe.forReplacedSession == NuvioPassReaction())
    let limited = NuvioPassReaction.of(.rateLimited(until: until), mode: .full, manual: true, previousCooldown: nil)
    #expect(limited.forReplacedSession == NuvioPassReaction(cooldownUntil: until))
}

@Test func nuvioPassQuietOnlyForAPushPassThatSentNothing() {
    var s = NuvioSyncSummary()
    #expect(NuvioPassReaction.isQuiet(mode: .pushOnly(force: false), outcome: .ok, summary: s))
    #expect(!NuvioPassReaction.isQuiet(mode: .full, outcome: .ok, summary: s))
    #expect(!NuvioPassReaction.isQuiet(mode: .pushOnly(force: true), outcome: .pinProtected, summary: s))
    s.pushed = 1
    #expect(!NuvioPassReaction.isQuiet(mode: .pushOnly(force: true), outcome: .ok, summary: s))
}

@Test func nuvioStateToStoreKeepsTheProfileReactionWithoutTheBook() {
    var before = chosen()
    before.progressCursor = 5
    var replayed = before
    replayed.progressCursor = 9
    let clear = NuvioPassReaction(clearProfile: true)
    // Book saved: the replayed state (with the reaction).
    #expect(NuvioPassReaction().stateToStore(before: before, replayed: replayed, bookSaved: true) == replayed)
    let saved = clear.stateToStore(before: before, replayed: replayed, bookSaved: true)
    #expect(saved?.profileIndex == nil && saved?.progressCursor == 9)
    // Book not saved: no cursor past the book, but A3 still goes back to "Nuvio-Profil wählen".
    #expect(NuvioPassReaction().stateToStore(before: before, replayed: replayed, bookSaved: false) == nil)
    let held = clear.stateToStore(before: before, replayed: replayed, bookSaved: false)
    #expect(held?.profileIndex == nil && held?.progressCursor == 5 && held?.userID == "u1")
}

// MARK: Finding 4: a TMDB 404 is "not found"

private struct StatusClient: HTTPClient {
    let status: Int
    func data(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) async throws -> (Data, HTTPURLResponse) {
        (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func nuvioTMDB404IsNotFound() async {
    for (status, expected) in [(404, NuvioIDLookup.notFound), (401, .unavailable), (429, .unavailable), (503, .unavailable)] {
        let tmdb = TMDBClient(apiKey: "k", http: HTTPClientFetcher(client: StatusClient(status: status)))
        do {
            _ = try await tmdb.imdbID(tmdbID: 1, type: .movie)
            Issue.record("no error for \(status)")
        } catch {
            // What really arrives: the fetcher's error, not the sync clients' `APIError`.
            #expect(error as? AddonError == .http(status))
            #expect(NuvioIDLookup.of(error: error) == expected)
        }
    }
    #expect(NuvioIDLookup.of(error: URLError(.notConnectedToInternet)) == .unavailable)
    #expect(NuvioIDLookup.of(error: APIError.status(404)) == .notFound)
}

// MARK: Finding 9b: removals while signed out

@Test func nuvioRemovalTombstonesNeedOnlyAChosenProfile() {
    var none = NuvioState()
    let noted = none.noteRemoval(["tt1"], kind: .removedFromContinue, now: t0)
    #expect(!noted && none.tombstones.isEmpty)
    // The state of a signed-out device keeps its choice: the removal is recorded and filters the next pull.
    var s = chosen()
    let recorded = s.noteRemoval(["tt0137523", "tt0137523", ""], kind: .removedFromContinue, now: t0)
    #expect(recorded)
    #expect(s.tombstones.map(\.itemID) == ["tt0137523"])
    let pulled = NuvioProgressEntry(id: "tt0137523", item: MetaPreview(id: "tt0137523", type: "movie", name: "Film"),
                                    position: 60, duration: 6000, updated: t0.addingTimeInterval(-60))
    #expect(s.filterPulled([pulled]).isEmpty)
}

// MARK: Finding 9c: a refused local report is not queued

@Test func progressRecordSaysWhenItTookTheReport() {
    var book = ProgressBook()
    let item = MetaPreview(id: "tt0137523", type: "movie", name: "Film")
    let took = book.record(id: "tt0137523", item: item, position: 600, duration: 6000, now: t0)
    #expect(took)
    // Unusable report: refused, entry unchanged.
    let before = book.entries["tt0137523"]
    let tookNaN = book.record(id: "tt0137523", item: item, position: .nan, duration: 6000, now: t0.addingTimeInterval(5))
    #expect(!tookNaN)
    #expect(book.entries["tt0137523"] == before)
    // A watched entry (e.g. pulled from the account) and a short local play: refused, it stays as pulled.
    book.markFinished(id: "tt0137523")
    let watched = book.entries["tt0137523"]
    let tookShort = book.record(id: "tt0137523", item: item, position: 30, duration: 6000, now: t0.addingTimeInterval(10))
    #expect(!tookShort)
    #expect(book.entries["tt0137523"] == watched)
}

// MARK: Findings 7, 8: the account of an import

@Test func nuvioImportChecksTheAccountOfTheState() {
    #expect(NuvioAccountImport.chosenIndex(sessionUser: "u1", state: chosen(index: 3)) == 3)
    #expect(NuvioAccountImport.chosenIndex(sessionUser: "u2", state: chosen(index: 3)) == nil)
    var noUser = NuvioState()
    noUser.profileIndex = 2
    #expect(NuvioAccountImport.chosenIndex(sessionUser: "u1", state: noUser) == nil)
    let link = NuvioAccountSource(userID: "u1", profileIndex: 3, usesPrimaryAddons: true).link
    #expect(NuvioAccountImport.currentLink(sessionUser: "u1", state: chosen(index: 3)) == link)
    #expect(NuvioAccountImport.currentLink(sessionUser: nil, state: chosen(index: 3)) == nil)
    #expect(NuvioAccountImport.currentLink(sessionUser: "u2", state: chosen(index: 3)) == nil)
    #expect(NuvioAccountImport.currentLink(sessionUser: "u1", state: chosen(index: 4)) != link)
    #expect(NuvioAccountImport.currentLink(sessionUser: "u1", state: NuvioState()) == nil)
}

@Test func nuvioRefreshAllSkipsStaleAccountEntries() {
    let mine = NuvioAccountSource(userID: "u1", profileIndex: 1, usesPrimaryAddons: false).link
    let other = NuvioAccountSource(userID: "u2", profileIndex: 1, usesPrimaryAddons: false).link
    let links = ["https://example.org/a.json", other, mine, "https://example.org/b.json"]
    let r = NuvioAccountImport.refreshable(links, current: mine)
    #expect(r.links == ["https://example.org/a.json", mine, "https://example.org/b.json"] && r.skipped == 1)
    let out = NuvioAccountImport.refreshable(links, current: nil)
    #expect(out.links == ["https://example.org/a.json", "https://example.org/b.json"] && out.skipped == 2)
    // The notice never replaces the other links' result line.
    #expect(NuvioAccountImport.skippedNotice(0, notice: "x", before: nil) == nil)
    #expect(NuvioAccountImport.skippedNotice(1, notice: "3 Reihen", before: "alt")
            == "3 Reihen · 1 Nuvio-Konto-Eintrag übersprungen (nicht angemeldet oder anderes Konto/Profil).")
    #expect(NuvioAccountImport.skippedNotice(2, notice: "alt", before: "alt")
            == "2 Nuvio-Konto-Einträge übersprungen (nicht angemeldet oder anderes Konto/Profil).")
}

// MARK: Finding 6: origin marks of addons removed by hand

@Test func nuvioOriginForgetsAnAddonRemovedByHand() {
    let url = "https://addon.example.org/abc/manifest.json"
    let addon = InstalledAddon(manifestURL: url, manifest: AddonManifest(id: "org.example", name: "Beispiel", version: "1",
                                                                                 resources: [], types: ["movie"]))
    var o = NuvioImportOrigin()
    o.noteAddons([AddonIdentity.instanceID(manifestURL: url)], source: "s")
    let forgot = o.forget(addon)
    #expect(forgot && o.addons.isEmpty)
    let again = o.forget(addon)
    #expect(!again)
    // Pruned against installed addons at the start of a preview.
    o.noteAddons([AddonIdentity.instanceID(manifestURL: url), "gone"], source: "s")
    let pruned = o.prune(installedAddons: [addon])
    #expect(pruned && o.addons.map(\.instanceID) == [AddonIdentity.instanceID(manifestURL: url)])
    let prunedAgain = o.prune(installedAddons: [addon])
    #expect(!prunedAgain)
}
