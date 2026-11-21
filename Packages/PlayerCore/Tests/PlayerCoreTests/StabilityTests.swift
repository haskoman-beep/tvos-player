import Foundation
import Testing
@testable import PlayerCore

// Welle C-a: Lade-Wächter, Routenwechsel, Startzeiten, fehlgeschlagene Links, Quellensuche mit Zeitgrenze.

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

// MARK: Lade-Wächter

@Test func watchdogStartFiresWithoutProgress() {
    var w = LoadWatchdog()
    let o = LoadWatchdog.Observation(starting: true, progressMark: "connecting")
    #expect(call(&w) { $0.observe(o, now: at(0)) == nil})
    #expect(call(&w) { $0.observe(o, now: at(29)) == nil})
    #expect(call(&w) { $0.observe(o, now: at(30)) == .start})
    // Danach beginnt die Uhr von vorn: kein zweiter Treffer im nächsten Takt.
    #expect(call(&w) { $0.observe(o, now: at(31)) == nil})
}

@Test func watchdogSlowButProgressingStartRuns() {
    var w = LoadWatchdog()
    var verdicts: [LoadWatchdog.Verdict] = []
    for s in stride(from: 0.0, through: 110, by: 1) {
        // Alle 20 s ein neuer Schritt: nie 30 s ohne Fortschritt.
        let o = LoadWatchdog.Observation(starting: true, progressMark: "step\(Int(s) / 20)")
        if let v = w.observe(o, now: at(s)) { verdicts.append(v) }
    }
    #expect(verdicts.isEmpty)
    // Harte Grenze insgesamt.
    #expect(call(&w) { $0.observe(LoadWatchdog.Observation(starting: true, progressMark: "step6"), now: at(120)) == .start})
}

@Test func watchdogStallAndSeekLimits() {
    var w = LoadWatchdog()
    let stall = LoadWatchdog.Observation(buffering: true)
    #expect(call(&w) { $0.observe(stall, now: at(0)) == nil})
    #expect(call(&w) { $0.observe(stall, now: at(24)) == nil})
    #expect(call(&w) { $0.observe(stall, now: at(25)) == .stall})

    var s = LoadWatchdog()
    let seek = LoadWatchdog.Observation(seeking: true)
    #expect(call(&s) { $0.observe(seek, now: at(0)) == nil})
    #expect(call(&s) { $0.observe(seek, now: at(24)) == nil})
    #expect(call(&s) { $0.observe(seek, now: at(25)) == .seek})
}

@Test func watchdogSuspendResetsClocks() {
    var w = LoadWatchdog()
    let stall = LoadWatchdog.Observation(buffering: true)
    _ = w.observe(stall, now: at(0))
    _ = w.observe(stall, now: at(20))
    // Hintergrund / Neuaufbau ausstehend: ausgesetzt.
    #expect(call(&w) { $0.observe(LoadWatchdog.Observation(buffering: true, suspended: true), now: at(22)) == nil})
    #expect(w.phase == .idle)
    // Zurück: Uhr beginnt neu, 25 s ab jetzt.
    #expect(call(&w) { $0.observe(stall, now: at(23)) == nil})
    #expect(call(&w) { $0.observe(stall, now: at(47)) == nil})
    #expect(call(&w) { $0.observe(stall, now: at(48)) == .stall})
}

@Test func watchdogIdleWhenPlayingOrPaused() {
    var w = LoadWatchdog()
    for s in 0..<200 { #expect(call(&w) { $0.observe(LoadWatchdog.Observation(), now: at(Double(s))) == nil }) }
    #expect(w.phase == .idle)
}

@Test func watchdogPhaseChangeRestartsClock() {
    var w = LoadWatchdog()
    _ = w.observe(LoadWatchdog.Observation(starting: true), now: at(0))
    _ = w.observe(LoadWatchdog.Observation(starting: true), now: at(25))
    // Start fertig, gleich ein Sprung: Sprung-Uhr ab hier.
    #expect(call(&w) { $0.observe(LoadWatchdog.Observation(seeking: true), now: at(26)) == nil})
    #expect(call(&w) { $0.observe(LoadWatchdog.Observation(seeking: true), now: at(50)) == nil})
    #expect(call(&w) { $0.observe(LoadWatchdog.Observation(seeking: true), now: at(51)) == .seek})
}

@Test func watchdogVerdictIsTimeoutForLadder() {
    for v in [LoadWatchdog.Verdict.start, .stall, .seek] {
        #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: v.kind)) == .timeout)
    }
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: LoadWatchdog.Verdict.start.kind)
    #expect(call(&p) { $0.next(for: f).1 == .retrySame(delay: 2)})
    #expect(call(&p) { $0.next(for: f).1 == .nextSource})
}

// MARK: Offline und Routenwechsel in der Leiter

@Test func offlineWaitsAndDoesNotCount() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "vodSourceFailed", domain: "NSURLErrorDomain", code: -1009)
    let ctx = RecoveryContext(offline: true)
    for _ in 0..<6 {
        let (cls, step) = p.next(for: f, context: ctx)
        #expect(cls == .offline)
        if case .waitForNetwork(let m) = step { #expect(m.contains("Netz")) } else { Issue.record("muss warten: \(step)") }
    }
    #expect(p.total == 0)
    #expect(call(&p) { $0.networkRestored() == .retrySame(delay: 1)})
    // Zeitüberschreitung des Wächters ohne Netz: auch warten, nicht weiterschalten.
    #expect(call(&p) { $0.next(for: PlaybackFailure(kind: LoadWatchdog.Verdict.stall.kind), context: ctx).0 == .offline})
    // Drosselung bleibt Drosselung.
    #expect(call(&p) { $0.next(for: PlaybackFailure(kind: "sourceRateLimited"), context: ctx).0 == .rateLimited})
}

@Test func routeChangeReloadsOnceThenNormal() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: "audioBridgeProducedNoOutput")
    let (cls, step) = p.next(for: f, context: RecoveryContext(routeChangedRecently: true))
    #expect(cls == .routeChange)
    #expect(step == .retrySame(delay: 1))
    // Wechsel verbraucht: wieder normale Einordnung (Format → nächste Quelle).
    #expect(call(&p) { $0.next(for: f).1 == .nextSource})
    // Speicher voll ist nie eine Routenfolge.
    #expect(PlaybackErrorClassifier.classify(PlaybackFailure(kind: "storageExhausted"),
                                             context: RecoveryContext(routeChangedRecently: true)) == .storage)
}

@Test func routeWindowRules() {
    var r = RouteChangeWindow()
    r.note(reasonRaw: RouteChangeWindow.ignoredReasonRaw, at: at(0))
    #expect(call(&r) { $0.consume(now: at(1), afterFirstFrame: true) == false})
    r.note(reasonRaw: 1, at: at(10))
    #expect(call(&r) { $0.consume(now: at(12), afterFirstFrame: false) == false})   // vor dem ersten Bild zählt es nicht
    #expect(call(&r) { $0.consume(now: at(15), afterFirstFrame: true) == true})
    #expect(call(&r) { $0.consume(now: at(16), afterFirstFrame: true) == false})    // nur einmal
    r.note(reasonRaw: nil, at: at(30))                                   // Unterbrechung der Tonsitzung
    #expect(call(&r) { $0.consume(now: at(41), afterFirstFrame: true) == false})    // Fenster vorbei
}

// MARK: Startzeiten

@Test func startTimingLogsOnce() {
    var s = StartTiming()
    s.markTap(at(0))
    s.markResolved(at(1.2))
    s.markFirstFrame(at(3.5))
    s.markFirstFrame(at(4))
    let line = s.markPlaying(at(3.7))
    #expect(line == "Startzeit: Auswahl→Link 1200 ms · Link→Bild 2300 ms · Bild→spielt 200 ms · gesamt 3700 ms")
    #expect(call(&s) { $0.markPlaying(at(5)) == nil})
}

@Test func startTimingWithoutTapOrOldTap() {
    var s = StartTiming()
    s.markTap(at(0))
    s.markResolved(at(500))   // Druck zu alt
    let line = s.markPlaying(at(502)) ?? ""
    #expect(line.contains("ohne Tastendruck"))
    #expect(line.contains("Link→Bild 2000 ms"))
    var none = StartTiming()
    #expect(call(&none) { $0.markPlaying(at(1)) == nil})
}

// MARK: Fehlgeschlagene Links

private func stream(_ name: String, file: String? = nil, hash: String? = nil, url: String = "https://x/token") -> StreamItem {
    StreamItem(name: name, title: "t", url: url, infoHash: hash,
               behaviorHints: file.map { StreamBehaviorHints(filename: $0) })
}

@Test func failedKeyIgnoresURL() {
    let a = stream("A", file: "Film.mkv", url: "https://debrid/abc?token=1")
    let b = stream("A", file: "Film.mkv", url: "https://debrid/xyz?token=2")
    #expect(FailedLinkBook.key(for: a) == FailedLinkBook.key(for: b))
    #expect(!FailedLinkBook.key(for: a).contains("token"))
    #expect(FailedLinkBook.key(for: stream("B", hash: "ABC")) == FailedLinkBook.key(for: stream("C", hash: "abc")))
    #expect(FailedLinkBook.key(for: stream("A", file: "x.mkv")) != FailedLinkBook.key(for: stream("A", file: "y.mkv")))
}

@Test func failedBookExpiresAndLimits() {
    var b = FailedLinkBook()
    let s = stream("A", file: "a.mkv")
    b.noteFailure(s, title: "tt1", now: at(0))
    #expect(b.isRecentlyFailed(s, title: "tt1", now: at(3600)))
    #expect(!b.isRecentlyFailed(s, title: "tt2", now: at(3600)))
    #expect(!b.isRecentlyFailed(s, title: "tt1", now: at(8 * 3600)))
    for i in 0..<10 { b.noteFailure(stream("S\(i)", file: "\(i).mkv"), title: "tt1", now: at(Double(10 + i))) }
    #expect(b.entries["tt1"]?.count == FailedLinkBook.perTitle)
    #expect(b.isRecentlyFailed(stream("S9", file: "9.mkv"), title: "tt1", now: at(100)))
    #expect(!b.isRecentlyFailed(stream("S0", file: "0.mkv"), title: "tt1", now: at(100)))
    for i in 0..<70 { b.noteFailure(s, title: "t\(i)", now: at(Double(100 + i))) }
    #expect(b.entries.count == FailedLinkBook.maxTitles)
    #expect(b.entries["t69"] != nil && b.entries["t0"] == nil)
}

@Test func failedBookHealthyAndFilter() {
    var b = FailedLinkBook()
    let bad = stream("A", file: "a.mkv"), good = stream("B", file: "b.mkv")
    b.noteFailure(bad, title: "tt1", now: at(0))
    #expect(b.excludingFailed([bad, good], title: "tt1", now: at(10)) == [good])
    #expect(call(&b) { $0.noteHealthy(bad, title: "tt1")})
    #expect(b.entries.isEmpty)
    #expect(!call(&b) { $0.noteHealthy(bad, title: "tt1") })
}

@Test func failedBookRemembersOnlySourceFaults() {
    #expect(FailedLinkBook.remembers(.linkExpired))
    #expect(FailedLinkBook.remembers(.unsupported))
    #expect(!FailedLinkBook.remembers(.timeout))
    #expect(!FailedLinkBook.remembers(.network))
    #expect(!FailedLinkBook.remembers(.offline))
    #expect(!FailedLinkBook.remembers(.rateLimited))
    #expect(!FailedLinkBook.remembers(.routeChange))
}

@Test func failedBookPersists() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("failed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let storage = FileBlobStorage(directory: dir)
    var b = FailedLinkBook()
    b.noteFailure(stream("A", file: "a.mkv"), title: "tt1", now: Date())
    b.noteFailure(stream("B", file: "b.mkv"), title: "tt2", now: Date().addingTimeInterval(-9 * 3600))
    try b.save(to: storage)
    let back = FailedLinkBook.load(from: storage)
    #expect(back.isRecentlyFailed(stream("A", file: "a.mkv"), title: "tt1"))
    #expect(back.entries["tt2"] == nil)   // beim Laden aufgeräumt
    #expect(FailedLinkBook.load(from: FileBlobStorage(directory: dir.appendingPathComponent("leer"))).entries.isEmpty)
}

// MARK: Quellensuche mit Zeitgrenze

private struct ScriptedHTTP: HTTPFetching {
    /// Host → (Verzögerung in s, Antwort oder Fehler-Status).
    var routes: [String: (delay: Double, body: String?, status: Int)]
    func data(from url: URL) async throws -> Data {
        guard let r = routes[url.host ?? ""] else { throw AddonError.http(404) }
        try await Task.sleep(nanoseconds: UInt64(r.delay * 1_000_000_000))
        guard let body = r.body else { throw AddonError.http(r.status) }
        return Data(body.utf8)
    }
}

private func streamAddon(_ host: String, _ name: String) -> InstalledAddon {
    InstalledAddon(manifestURL: "https://\(host)/manifest.json",
                   manifest: AddonManifest(id: host, name: name, version: "1", resources: [AddonResource(name: "stream")],
                                           types: ["movie"], idPrefixes: ["tt"]))
}

private actor Updates {
    var list: [AddonSearchProgress] = []
    func add(_ p: AddonSearchProgress) { list.append(p) }
}

@Test func searchTimeoutAndStatusPerAddon() async {
    let http = ScriptedHTTP(routes: [
        "fast": (0.05, #"{"streams":[{"name":"F","url":"https://f/1"}]}"#, 200),
        "slow": (5, #"{"streams":[{"name":"S","url":"https://s/1"}]}"#, 200),
        "bad": (0.1, nil, 503),
    ])
    let addons = [streamAddon("slow", "Langsam"), streamAddon("fast", "Schnell"), streamAddon("bad", "Kaputt")]
    let updates = Updates()
    let clock = ContinuousClock.now
    let result = await AddonClient(http: http).streams(from: addons, type: "movie", id: "tt1", timeout: 3) { await updates.add($0) }
    let elapsed = ContinuousClock.now - clock
    #expect(elapsed < .seconds(4.5))
    #expect(result.map(\.addon.manifest.name) == ["Schnell"])
    let list = await updates.list
    #expect(list.count == 4)   // Anfang + je Addon
    #expect(list.first?.statuses.allSatisfy { $0.state == .loading } == true)
    // Das schnelle Addon ist zuerst fertig, seine Treffer sind sofort da.
    #expect(list[1].results.map(\.addon.manifest.name) == ["Schnell"])
    #expect(list[1].runningSummary == "Addons 1/3 fertig")
    let final = list.last!
    #expect(final.isComplete && final.runningSummary == nil)
    #expect(final.statuses.map(\.state) == [.timedOut, .ok(count: 1), .failed(reason: "HTTP 503")])
    #expect(final.logText.contains("Langsam=Zeitüberschreitung"))
}

@Test func searchSkipsUnsupportedAddons() async {
    let catalogOnly = InstalledAddon(manifestURL: "https://c/manifest.json",
                                     manifest: AddonManifest(id: "c", name: "Katalog", version: "1",
                                                             resources: [AddonResource(name: "catalog")], types: ["movie"]))
    let updates = Updates()
    let r = await AddonClient(http: ScriptedHTTP(routes: [:])).streams(from: [catalogOnly], type: "movie", id: "tt1",
                                                                       timeout: 1) { await updates.add($0) }
    #expect(r.isEmpty)
    #expect(await updates.list.last?.statuses.isEmpty == true)
}

@Test func describeErrorsWithoutAddress() {
    #expect(AddonSearch.describe(AddonError.http(429)) == "HTTP 429")
    #expect(AddonSearch.describe(NSError(domain: "NSURLErrorDomain", code: -1009)) == "keine Verbindung")
    #expect(AddonSearch.describe(AddonError.invalidManifestURL("https://host/secret")) == "Adresse ungültig")
    #expect(AddonSearch.clamp(0) == 3 && AddonSearch.clamp(500) == 120)
}

@Test func profileAddonTimeoutDefaultsForOldBackups() throws {
    let old = #"{"id":"\#(UUID().uuidString)","name":"Alt"}"#
    let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
    #expect(p.addonTimeout == AddonSearch.defaultTimeout)
    var q = p; q.addonTimeout = 30
    let back = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(q))
    #expect(back.addonTimeout == 30)
}

/// Mutierender Aufruf außerhalb des #expect-Makros (es zerlegt Ausdrücke in unveränderliche Werte).
private func call<S, R>(_ x: inout S, _ f: (inout S) -> R) -> R { f(&x) }

@Test func failedBookAppliesVerdicts() {
    var b = FailedLinkBook()
    let s = stream("A", file: "a.mkv")
    #expect(!call(&b) { $0.apply(.failed(.timeout), stream: s, title: "tt1") })
    #expect(!call(&b) { $0.apply(.failed(.offline), stream: s, title: "tt1") })
    #expect(b.entries.isEmpty)
    #expect(call(&b) { $0.apply(.failed(.linkExpired), stream: s, title: "tt1") })
    #expect(b.isRecentlyFailed(s, title: "tt1"))
    #expect(call(&b) { $0.apply(.healthy, stream: s, title: "tt1") })
    #expect(call(&b) { $0.apply(.placeholder, stream: s, title: "tt2") })
    #expect(b.isRecentlyFailed(s, title: "tt2") && !b.isRecentlyFailed(s, title: "tt1"))
}

@Test func startTimingTapBelongsToOneStart() {
    var s = StartTiming()
    s.markTap(at(0))
    s.markResolved(at(1))
    _ = call(&s) { $0.markPlaying(at(3)) }
    s.markResolved(at(60))   // nächste Folge automatisch
    #expect(call(&s) { $0.markPlaying(at(62)) }?.contains("ohne Tastendruck") == true)
}

// MARK: Nacharbeiten (Review C-a)

@Test func watchdogLimitsAboveDiskCacheFallback() {
    let p = DiskCachePolicy()
    // Der Plattencache leitet nach Lesegrenze + Ursprung-Leerlauf selbst auf den direkten Link um; erst danach der Wächter.
    #expect(LoadWatchdog.seekLimit > p.readerHardLimit + p.originIdleTimeout)
    #expect(LoadWatchdog.stallLimit > p.readerHardLimit + p.originIdleTimeout)
    #expect(LoadWatchdog.startLimit > p.probeHardLimit + p.originIdleTimeout)
}

@Test func deadStartOnlyWithoutFirstFrame() {
    let k = LoadWatchdog.Verdict.start.kind
    #expect(SourceVerdict.forNextSource(.timeout, failureKind: k, reachedFirstFrame: false) == .deadStart)
    #expect(SourceVerdict.forNextSource(.timeout, failureKind: LoadWatchdog.Verdict.stall.kind, reachedFirstFrame: true) == .failed(.timeout))
    #expect(SourceVerdict.forNextSource(.timeout, failureKind: "vodSourceTimedOut", reachedFirstFrame: false) == .failed(.timeout))
    #expect(SourceVerdict.forNextSource(.linkExpired, failureKind: nil, reachedFirstFrame: false) == .failed(.linkExpired))
    var b = FailedLinkBook()
    #expect(call(&b) { $0.apply(.deadStart, stream: stream("A", file: "a.mkv"), title: "tt1") })
    #expect(b.isRecentlyFailed(stream("A", file: "a.mkv"), title: "tt1"))
}

@Test func secondRouteChangeUsesBaseClass() {
    var p = RecoveryPlanner()
    let f = PlaybackFailure(kind: LoadWatchdog.Verdict.stall.kind)
    let ctx = RecoveryContext(routeChangedRecently: true)
    #expect(call(&p) { $0.next(for: f, context: ctx) } .0 == .routeChange)
    let (cls, step) = call(&p) { $0.next(for: f, context: ctx) }
    #expect(cls == .timeout)
    #expect(step == .retrySame(delay: 2))
}

@Test func partialSearchAndCancel() async {
    var prog = AddonSearchProgress(addons: [(index: 0, addon: streamAddon("a", "A")), (index: 1, addon: streamAddon("b", "B"))])
    prog.finish(index: 0, addon: streamAddon("a", "A"), outcome: .streams([]), milliseconds: 5)
    #expect(!prog.isPartial)
    prog.finish(index: 1, addon: streamAddon("b", "B"), outcome: .timedOut, milliseconds: 5)
    #expect(prog.isPartial)
    // Abgebrochener Aufrufer: keine Zeitüberschreitung, sondern „abgebrochen“.
    let t = Task { await AddonSearch.withDeadline(5) { try await Task.sleep(nanoseconds: 3_000_000_000); return 1 } }
    t.cancel()
    let r = await t.value
    if case .some(.failure(let e)) = r { #expect(AddonSearch.describe(e) == "abgebrochen") } else { Issue.record("erwartet Abbruch: \(String(describing: r))") }
    #expect(AddonSearch.nearestChoice(14) == 15 && AddonSearch.nearestChoice(100) == 45 && AddonSearch.nearestChoice(12) == 12)
}
