import Foundation
import Network
import PlayerCore

// Plattencache für den laufenden Film (Welle B-d).
//
// Die Engine bekommt statt der Quelladresse `http://127.0.0.1:<Port>/c/<Token>/media.<ext>`. Der Proxy
// holt die Datei in Blöcken (4 MiB, Range-Anfragen) beim Ursprung, legt sie unter Caches/DiskCache/<Token>/
// ab und bedient die Range-Anfragen der Engine von dort. Vor der Leseposition lädt er bis zu 1 GB voraus.
// Logik (Blockplan, Range-Mathematik, Verdrängung, Platzgrenzen) in PlayerCore/Playback/DiskCache.swift.
//
// Fail open: jede Störung führt zur direkten Adresse – vor dem Start (route liefert die Quelladresse),
// beim ersten Block einer Anfrage (307 auf den Ursprung) und nach wiederholten Abruffehlern (ganze Sitzung
// leitet um). Nur ein Film zur Zeit; Schließen des Players oder der nächste Start räumt die Dateien weg.

private func cacheLog(_ s: String) { Task { @MainActor in RemoteLog.info("cache", s) } }
private func cacheError(_ s: String) { Task { @MainActor in RemoteLog.error("cache", s) } }
/// Fehler kurz fürs Log (URLSession-Fehler tragen sonst die ganze Adresse mit).
private func short(_ e: Error) -> String {
    if let d = e as? DiskCacheError { return d.description }
    let n = e as NSError
    return n.domain == NSURLErrorDomain ? "Netzfehler \(n.code)" : "\(e)"
}

enum DiskCacheError: Error, CustomStringConvertible {
    case noRangeSupport(Int)
    case badAnswer(String)
    case notEligible(String)
    case throttled(Int)
    /// Leser hat auf einen laufenden Vorlauf-Block gewartet, bis die Lesergrenze ablief.
    case readerDeadline(Int)

    var description: String {
        switch self {
        case .noRangeSupport(let s): "Ursprung ohne Range-Antwort (Status \(s))"
        case .badAnswer(let s): "unerwartete Antwort (\(s))"
        case .notEligible(let t): "kein Dateityp für den Cache (\(t))"
        case .throttled(let s): "Ursprung drosselt (Status \(s))"
        case .readerDeadline(let s): "Vorlauf-Block nicht in \(s) s"
        }
    }
}

/// Einmal-Schalter für Rückrufe aus mehreren Quellen (Bereit, Fehler, Zeitgrenze).
private final class DiskCacheOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func fire() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

// MARK: - Abruf beim Ursprung

/// Range-Abrufe über URLSession mit eigenem Delegate: Antworten ohne 206 werden sofort abgebrochen
/// (sonst lädt ein Ursprung, der Range ignoriert, die ganze Datei in den Speicher), ebenso Körper,
/// die länger sind als angefragt.
final class DiskCacheOriginFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Answer: Sendable {
        let status: Int
        let contentRange: HTTPContentRange?
        let contentType: String?
        let data: Data
    }

    private final class Pending {
        let continuation: CheckedContinuation<Answer, Error>
        let limit: Int
        var data = Data()
        var status = 0
        var contentRange: HTTPContentRange?
        var contentType: String?
        var refused = false
        init(continuation: CheckedContinuation<Answer, Error>, limit: Int) { self.continuation = continuation; self.limit = limit }
    }

    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var session: URLSession!

    init(timeout: TimeInterval) {
        super.init()
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpMaximumConnectionsPerHost = 4
        c.timeoutIntervalForRequest = timeout
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        // Task 2.3 exception (direct URLSession, not via HTTPClient in Build 2): PERMANENT exception: streaming proxy for the player (delegate session, unbounded media bodies).
        session = URLSession(configuration: c, delegate: self, delegateQueue: q)
    }

    /// `idle`: Leerlauf-Grenze (URLRequest). `hardLimit`: Grenze für den ganzen Abruf, nil = keine (Vorlauf).
    func fetch(_ url: URL, headers: [String: String], range: ClosedRange<Int64>, idle: TimeInterval,
               hardLimit: TimeInterval?) async throws -> Answer {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: idle)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.dataTask(with: req)
        let limit = Int(range.count)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (k: CheckedContinuation<Answer, Error>) in
                lock.withLock { pending[task.taskIdentifier] = Pending(continuation: k, limit: limit) }
                task.resume()
                // Harte Grenze für den ganzen Abruf (timeoutInterval zählt nur Leerlauf).
                if let hardLimit {
                    DispatchQueue.global().asyncAfter(deadline: .now() + hardLimit) { [weak task] in task?.cancel() }
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func entry(_ id: Int) -> Pending? { lock.withLock { pending[id] } }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let p = entry(dataTask.taskIdentifier) else { completionHandler(.cancel); return }
        let http = response as? HTTPURLResponse
        p.status = http?.statusCode ?? 0
        p.contentRange = HTTPContentRange.parse(http?.value(forHTTPHeaderField: "Content-Range"))
        p.contentType = http?.value(forHTTPHeaderField: "Content-Type")
        if p.status == 206 { completionHandler(.allow) } else { p.refused = true; completionHandler(.cancel) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let p = entry(dataTask.taskIdentifier) else { return }
        p.data.append(data)
        if p.data.count > p.limit { p.refused = true; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let p = lock.withLock({ pending.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let error, !p.refused {
            p.continuation.resume(throwing: error)
        } else {
            p.continuation.resume(returning: Answer(status: p.status, contentRange: p.contentRange,
                                                    contentType: p.contentType, data: p.data))
        }
    }
}

// MARK: - Sitzung (ein Film)

actor DiskCacheSession {
    nonisolated let token: String
    nonisolated let origin: URL
    nonisolated let plan: DiskCacheBlockPlan
    nonisolated let contentType: String
    nonisolated let fileName: String
    private let headers: [String: String]
    private let dir: URL
    private let policy: DiskCachePolicy
    private let fetcher: DiskCacheOriginFetcher
    private let budget: Int64
    private var index: DiskCacheIndex
    private var inflight: [Int: Task<Data, Error>] = [:]
    /// Erzeugung je laufendem Abruf (`inflight[i]`), damit nur der eigene Abruf seinen Eintrag entfernt.
    private var inflightGen: [Int: Int] = [:]
    private var fetchGeneration = 0
    private var prefetchCount = 0
    private var prefetchPausedUntil = Date.distantPast
    private var readPosition: Int64 = 0
    private var failures = 0
    /// Gleichzeitige Vorlauf-Abrufe; sinkt, wenn der Ursprung drosselt (429/503).
    private var parallel: Int
    /// Blöcke, auf die gerade ein Leser wartet: ein laufender Vorlauf-Abruf wiederholt dann nicht mehr.
    private var readerWaiting: [Int: Int] = [:]
    /// Laufende Abrufe für einen wartenden Leser (kein Vorlauf): solange startet kein neuer Vorlauf.
    private var readerFetches = 0
    /// Gemessene Geschwindigkeit des Ursprungs (gleitendes Mittel).
    private var rate = DiskCacheRate()
    private var closed = false
    private var writeProblemLogged = false
    private(set) var passthrough = false
    private(set) var stats = DiskCacheStats()

    private init(token: String, origin: URL, headers: [String: String], dir: URL, plan: DiskCacheBlockPlan,
                 contentType: String, fileName: String, budget: Int64, policy: DiskCachePolicy, fetcher: DiskCacheOriginFetcher) {
        self.token = token; self.origin = origin; self.headers = headers; self.dir = dir; self.plan = plan
        self.contentType = contentType; self.fileName = fileName; self.budget = budget; self.policy = policy
        self.fetcher = fetcher
        parallel = max(1, policy.parallelPrefetches)
        index = DiskCacheIndex(plan: plan)
    }

    /// Erster Block als Probe: Größe aus `Content-Range`, Range-Unterstützung, Inhaltstyp.
    static func open(token: String, origin: URL, headers: [String: String], decision: DiskCacheSource.Decision,
                     budget: Int64, dir: URL, policy: DiskCachePolicy, fetcher: DiskCacheOriginFetcher) async throws -> DiskCacheSession {
        let a = try await fetcher.fetch(origin, headers: headers, range: 0...(policy.blockSize - 1),
                                      idle: policy.originIdleTimeout, hardLimit: policy.probeHardLimit)
        guard a.status == 206, let cr = a.contentRange, let total = cr.total, total > 0,
              cr.range == 0...(min(policy.blockSize, total) - 1) else {
            throw DiskCacheError.noRangeSupport(a.status)
        }
        let type = DiskCacheHTTP.safeContentType(a.contentType)
        let lowered = type.lowercased()
        if lowered.contains("mpegurl") || lowered.contains("dash+xml") || lowered.hasPrefix("text/") {
            throw DiskCacheError.notEligible(type)
        }
        if decision == .checkContentType, !DiskCacheSource.contentTypeAllowed(type) { throw DiskCacheError.notEligible(type) }
        let plan = DiskCacheBlockPlan(blockSize: policy.blockSize, totalLength: total)
        guard Int64(a.data.count) == plan.length(of: 0) else { throw DiskCacheError.badAnswer("\(a.data.count) Bytes für Block 0") }
        let s = DiskCacheSession(token: token, origin: origin, headers: headers, dir: dir, plan: plan, contentType: type,
                                 fileName: DiskCacheSource.proxyFileName(for: origin, contentType: type), budget: budget,
                                 policy: policy, fetcher: fetcher)
        await s.adopt(0, a.data)
        return s
    }

    private func adopt(_ block: Int, _ data: Data) {
        stats.misses += 1
        stats.originBytes += Int64(data.count)
        store(block, data)
    }

    private var aheadBytes: Int64 { policy.readAhead(budget: budget) }
    private func fileURL(_ block: Int) -> URL { dir.appendingPathComponent("b\(block)") }

    /// Daten eines Blocks: von der Platte, aus einem laufenden Abruf oder frisch vom Ursprung.
    func block(_ i: Int) async throws -> Data {
        let started = Date()
        if index.contains(i) {
            if let d = readBlockFile(i) { stats.hits += 1; return d }
            // Datei fehlt (tvOS darf Caches/ leeren) oder ist kaputt: neu holen.
            index.remove(i)
        }
        if let t = inflight[i] {
            readerWaiting[i, default: 0] += 1
            defer {
                readerWaiting[i, default: 1] -= 1
                if readerWaiting[i] == 0 { readerWaiting[i] = nil }
                pump()
            }
            // Auf den laufenden Vorlauf warten, aber nur bis zur Lesergrenze; der Vorlauf läuft weiter.
            let left = policy.readerHardLimit - Date().timeIntervalSince(started)
            do { return try await Self.value(of: t, within: max(0.5, left)) }
            catch {
                // Nur bei echter Fristüberschreitung ganz umleiten; ein schneller Fehler des Vorlaufs kostet ein 307.
                if case DiskCacheError.readerDeadline = error { readerGoesDirect() }
                throw error
            }
        }
        stats.misses += 1
        do { return try await startFetch(i, prefetch: false).value }
        catch {
            // Lesergrenze gerissen: die Engine liest ab jetzt direkt (307), der Vorlauf soll ihr nicht Bandbreite nehmen.
            if Date().timeIntervalSince(started) >= policy.readerHardLimit - 0.5 { readerGoesDirect() }
            throw error
        }
    }

    /// Leser bekommt ein 307 nach Warten auf den Vorlauf oder gerissener Lesergrenze: ganze Sitzung leitet um,
    /// alle laufenden Abrufe werden abgebrochen (keine Konkurrenz zum direkten Strom der Engine; auch der Block,
    /// auf den der Leser gewartet hat: er bekommt ohnehin das 307).
    private func readerGoesDirect() {
        guard !closed, !passthrough else { return }
        passthrough = true
        for t in inflight.values { t.cancel() }
        cacheLog("Plattencache: Leser direkt, Vorlauf gestoppt")
    }

    /// Eine Anfrage beginnt hier (große Anfragen verschieben die Leseposition, kleine Proben nicht).
    func beginRead(at position: Int64) {
        readPosition = position
        pump()
    }

    func noteRead(_ position: Int64, bytes: Int, movesPosition: Bool) {
        stats.servedBytes += Int64(bytes)
        guard movesPosition else { return }
        let old = plan.block(at: readPosition)
        readPosition = position
        if plan.block(at: position) != old { pump() }
    }

    func close() {
        closed = true
        for t in inflight.values { t.cancel() }
        inflight.removeAll()
        inflightGen.removeAll()
        index.removeAll()
        try? FileManager.default.removeItem(at: dir)
    }

    /// Ergebnis eines Abruf-Tasks, höchstens `seconds` lang (der Task selbst wird nicht abgebrochen).
    /// Wettlauf über einen Einmal-Schalter (keine Task-Gruppe: die wartete auf `t.value`, das auf Abbruch nicht reagiert).
    private static func value(of t: Task<Data, Error>, within seconds: TimeInterval) async throws -> Data {
        let once = DiskCacheOnce()
        return try await withCheckedThrowingContinuation { (k: CheckedContinuation<Data, Error>) in
            let timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.fire() { k.resume(throwing: DiskCacheError.readerDeadline(Int(seconds.rounded()))) }
            }
            Task {
                let r = await t.result
                if once.fire() { timer.cancel(); k.resume(with: r) }
            }
        }
    }

    private func startFetch(_ i: Int, prefetch: Bool) -> Task<Data, Error> {
        if prefetch { prefetchCount += 1 } else { readerFetches += 1 }
        // Laufende Abrufe (einschließlich dieses) beim Start: teilt die Messung der Geschwindigkeit.
        let running = prefetchCount + readerFetches
        fetchGeneration &+= 1
        let gen = fetchGeneration
        let t = Task { try await self.fetchBlock(i, prefetch: prefetch, concurrent: running, gen: gen) }
        inflight[i] = t
        inflightGen[i] = gen
        return t
    }

    private func fetchBlock(_ i: Int, prefetch: Bool, concurrent: Int, gen: Int) async throws -> Data {
        defer {
            // Nur den eigenen Eintrag entfernen (ein abgebrochener alter Abruf darf einen neueren nicht austragen).
            if inflightGen[i] == gen { inflight[i] = nil; inflightGen[i] = nil }
            if prefetch { prefetchCount -= 1 } else { readerFetches -= 1 }
            pump()
        }
        let r = plan.range(of: i)
        var lastError: Error = DiskCacheError.badAnswer("kein Versuch")
        let attempts = max(1, prefetch ? policy.prefetchAttempts : policy.readerAttempts)
        for attempt in 0..<attempts {
            if closed || Task.isCancelled { throw CancellationError() }
            if passthrough, prefetch { throw CancellationError() }
            // Wartet die Engine auf diesen Block, kein zweiter Versuch: lieber gleich 307 als die Lesegrenze reißen.
            if attempt > 0, readerWaiting[i] != nil { break }
            do {
                let t0 = Date()
                let a = try await fetcher.fetch(origin, headers: headers, range: r, idle: policy.originIdleTimeout,
                                                hardLimit: prefetch ? nil : policy.readerHardLimit)
                if DiskCachePolicy.isThrottle(status: a.status) { throw DiskCacheError.throttled(a.status) }
                guard a.status == 206, a.contentRange?.range == r, a.contentRange?.total == plan.totalLength,
                      Int64(a.data.count) == Int64(r.count) else {
                    throw DiskCacheError.badAnswer("Status \(a.status), \(a.data.count) Bytes")
                }
                stats.originBytes += Int64(a.data.count)
                if prefetch { stats.prefetched += 1 }
                failures = 0
                store(i, a.data)
                // Größte Zahl laufender Abrufe am Anfang oder Ende (der erste einer Vorlauf-Runde sieht beim Start nur sich).
                noteRate(bytes: Int64(a.data.count), seconds: Date().timeIntervalSince(t0),
                         concurrent: max(concurrent, prefetchCount + readerFetches))
                return a.data
            } catch {
                lastError = error
                if closed || Task.isCancelled { throw error }
                if case DiskCacheError.throttled = error { break }
                if attempt + 1 < attempts { try? await Task.sleep(nanoseconds: 400_000_000) }
            }
        }
        if prefetch { prefetchPausedUntil = Date().addingTimeInterval(5) }
        // Drosselung: erst weniger parallel abrufen; erst bei einem einzigen Abruf zählt sie als Fehler.
        if case DiskCacheError.throttled(let st) = lastError, parallel > 1 {
            parallel -= 1
            cacheLog("Ursprung drosselt (Status \(st)) → Vorlauf mit \(parallel) Abruf(en)")
            throw lastError
        }
        failures += 1
        if failures >= policy.failuresUntilPassthrough, !passthrough {
            passthrough = true
            cacheError("Ursprung antwortet nicht verlässlich (\(short(lastError))) → Umleitung auf die direkte Adresse")
        }
        throw lastError
    }

    /// Geschwindigkeit nachführen: zu langsam → erst weniger parallel, bei einem Abruf Umleitung (fail open).
    private func noteRate(bytes: Int64, seconds: TimeInterval, concurrent: Int) {
        policy.record(&rate, bytes: bytes, seconds: seconds, concurrent: concurrent)
        let perBlock = rate.secondsPerBlock(policy.blockSize).map { String(format: "%.1f s je Block", $0) } ?? "?"
        switch policy.slowAction(rate: rate, parallel: parallel) {
        case .none:
            break
        case .lowerParallel:
            parallel -= 1
            rate = DiskCacheRate()
            cacheLog("Ursprung langsam (\(perBlock)) → Vorlauf mit \(parallel) Abruf(en)")
        case .passthrough:
            guard !passthrough else { return }
            passthrough = true
            cacheError("Ursprung zu langsam für den Cache (\(perBlock)) → Umleitung auf die direkte Adresse")
        }
    }

    private func readBlockFile(_ i: Int) -> Data? {
        guard let d = try? Data(contentsOf: fileURL(i)), Int64(d.count) == plan.length(of: i) else { return nil }
        return d
    }

    /// Block auf die Platte (wenn Platz bleibt), danach verdrängen bis zum Budget.
    private func store(_ i: Int, _ data: Data) {
        guard !closed else { return }
        let free = DiskCacheProxy.freeBytes(near: dir)
        if DiskCacheBudget.mayWrite(blockBytes: Int64(data.count), freeBytes: free, reserve: policy.reserveFreeBytes) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: fileURL(i), options: .atomic)
                index.insert(i)
            } catch {
                noteNotWritten("Schreiben fehlgeschlagen: \(short(error))")
            }
        } else {
            noteNotWritten("zu wenig freier Platz")
        }
        let victims = index.evictionVictims(budgetBytes: budget, readPosition: readPosition, aheadBytes: aheadBytes,
                                            backWindowBytes: policy.backWindowBytes, protected: Set(inflight.keys))
        for b in victims {
            try? FileManager.default.removeItem(at: fileURL(b))
            index.remove(b)
            stats.evicted += 1
        }
    }

    /// Nicht gespeichert: Daten gehen trotzdem an die Engine; Vorlauf ruht 30 s (sonst holt er denselben Block endlos).
    private func noteNotWritten(_ why: String) {
        stats.notWritten += 1
        prefetchPausedUntil = Date().addingTimeInterval(30)
        if !writeProblemLogged { writeProblemLogged = true; cacheError("Block nicht gespeichert (\(why))") }
    }

    /// Vorlauf: fehlende Blöcke ab der Leseposition, höchstens `parallelPrefetches` gleichzeitig.
    private func pump() {
        // Wartet ein Leser (eigener Abruf oder auf einen Vorlauf-Block), keinen neuen Vorlauf starten.
        guard !closed, !passthrough, Date() >= prefetchPausedUntil, readerWaiting.isEmpty, readerFetches == 0 else { return }
        while prefetchCount < parallel,
              let b = index.nextPrefetch(readPosition: readPosition, aheadBytes: aheadBytes, excluding: Set(inflight.keys)) {
            _ = startFetch(b, prefetch: true)
        }
    }
}

// MARK: - Proxy (lokaler HTTP-Server)

actor DiskCacheProxy {
    static let shared = DiskCacheProxy()

    nonisolated private let policy = DiskCachePolicy()
    private let fetcher: DiskCacheOriginFetcher
    nonisolated private let queue = DispatchQueue(label: "player.diskcache.net")
    private var listener: NWListener?
    /// Zuletzt benutzter Port: nach einem Neustart des Listeners zuerst derselbe (die Engine kennt die alte Adresse).
    private var lastPort: NWEndpoint.Port?
    /// Port in der Adresse, die die Engine für die laufende Sitzung bekommen hat.
    private var sessionPort: UInt16?
    /// Laufender Listener-Start: ein zweiter Aufruf wartet darauf, statt parallel einen zweiten zu starten.
    private var listenerStart: Task<UInt16?, Never>?
    private var session: DiskCacheSession?
    /// Quellen, die in dieser App-Sitzung schon am Cache gescheitert sind: direkt.
    private var failedOrigins: Set<URL> = []

    private init() { fetcher = DiskCacheOriginFetcher(timeout: DiskCachePolicy().originIdleTimeout) }

    static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DiskCache", isDirectory: true)
    }

    /// Beim App-Start: Reste einer früheren Sitzung (Absturz, beendete App) entfernen. Im Hintergrund.
    nonisolated static func cleanupAtLaunch() {
        Task.detached(priority: .background) { removeStale(keeping: nil) }
    }

    nonisolated static func removeStale(keeping token: String?) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for u in items where u.lastPathComponent != token { try? fm.removeItem(at: u) }
    }

    /// Freier Platz auf dem Datenträger von Caches/ (nil = unbekannt → Cache bleibt aus).
    nonisolated static func freeBytes(near url: URL) -> Int64? {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let probe = fm.fileExists(atPath: url.path) ? url : base
        if let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityKey]), let n = v.volumeAvailableCapacity {
            return Int64(n)
        }
        if let attrs = try? fm.attributesOfFileSystem(forPath: base.path), let n = attrs[.systemFreeSize] as? NSNumber {
            return n.int64Value
        }
        return nil
    }

    /// Adresse für die Engine. Ohne Einstellung, bei HLS/DASH, ohne Platz oder bei jedem Fehler die Quelladresse.
    /// `session` = Token der Cache-Sitzung (zum Schließen), nil = direkt. `reuse`: Token, das derselbe Player schon
    /// hat (Neuladen nach Fehler) – nur dann wird eine laufende Sitzung weiterbenutzt, nie die eines geschlossenen Players.
    func route(_ url: URL, headers: [String: String], settings: DiskCacheSettings?,
               nativeHLS: Bool, reuse: String?) async -> (url: URL, session: String?) {
        guard let settings, settings.enabled else { return (url, nil) }
        if DiskCacheSource.needsCredentials(url, headers: headers) {
            cacheLog("Plattencache umgangen (Quelle mit Anmeldung)")
            return (url, nil)
        }
        let decision = DiskCacheSource.decide(url, nativeHLS: nativeHLS)
        if case .bypass(let why) = decision {
            cacheLog("Plattencache umgangen (\(why))")
            return (url, nil)
        }
        if failedOrigins.contains(url) {
            cacheLog("Quelle schon einmal am Plattencache gescheitert → direkte Adresse")
            return (url, nil)
        }
        if let s = session, s.origin == url, s.token == reuse {
            if await s.passthrough { return (url, nil) }
            guard let port = await ensureListener() else {
                cacheError("Lokaler Proxy startet nicht → direkte Adresse")
                return (url, nil)
            }
            cacheLog("Plattencache: laufende Sitzung weiter")
            sessionPort = port
            return (proxyURL(s, port: port), s.token)
        }
        if let old = session { session = nil; await old.close() }
        Self.removeStale(keeping: nil)
        let budget = DiskCacheBudget.limit(settingBytes: settings.limitBytes, freeBytes: Self.freeBytes(near: Self.root),
                                           ownBytes: 0, reserve: policy.reserveFreeBytes)
        guard budget >= policy.minimumBudgetBytes else {
            cacheLog("Plattencache aus: zu wenig freier Platz (Budget \(budget / 1_000_000) MB)")
            return (url, nil)
        }
        let token = UUID().uuidString
        do {
            let s = try await DiskCacheSession.open(token: token, origin: url, headers: headers, decision: decision, budget: budget,
                                                    dir: Self.root.appendingPathComponent(token, isDirectory: true),
                                                    policy: policy, fetcher: fetcher)
            // Während der Probe kam eine andere Sitzung dazu (sollte nicht passieren): die ältere schließen.
            if let other = session { await other.close() }
            session = s
            // Listener erst jetzt (nach der Probe): ein Schließen des vorigen Players dazwischen stoppt ihn nicht mehr.
            guard let port = await ensureListener(), session === s else {
                cacheError("Lokaler Proxy startet nicht → direkte Adresse")
                if session === s { session = nil }
                await s.close()
                return (url, nil)
            }
            cacheLog("Plattencache an · \(s.plan.totalLength / 1_000_000) MB · Budget \(budget / 1_000_000) MB · "
                     + "\(s.contentType) · \(url.host ?? "?")")
            sessionPort = port
            return (proxyURL(s, port: port), token)
        } catch {
            // Task 3.5 (W-A-7): the player closed during the probe (task cancelled, URL error −999). That says
            // nothing about the source: no entry in `failedOrigins`, the next start tries the cache again.
            let cancelled = Task.isCancelled || error is CancellationError
                || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled)
            if !cancelled { failedOrigins.insert(url) }
            try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(token, isDirectory: true))
            if cancelled {
                cacheLog("Plattencache-Probe abgebrochen (\(short(error))) → direkte Adresse, Quelle nicht gesperrt")
            } else {
                cacheLog("Plattencache nicht möglich (\(short(error))) → direkte Adresse")
            }
            return (url, nil)
        }
    }

    /// Sitzung schließen und Dateien löschen (Player zu). Tut nichts, wenn inzwischen eine andere läuft.
    func close(_ token: String) async {
        guard let s = session, s.token == token else { return }
        session = nil
        sessionPort = nil
        let stats = await s.stats
        await s.close()
        listener?.cancel(); listener = nil
        cacheLog("Plattencache geschlossen · \(stats.summary)")
    }

    /// Laden über den Proxy scheiterte: Sitzung weg, diese Quelle ab jetzt direkt.
    func giveUp(_ url: URL, token: String) async {
        failedOrigins.insert(url)
        await close(token)
    }

    /// Vor dem Neuladen an derselben Stelle (recover): läuft die Sitzung und hört der Listener noch auf dem
    /// Port aus der Adresse der Engine? false → der Aufrufer lädt über `load()` neu (route liefert dann eine
    /// gültige Adresse oder die direkte).
    func ensureServing(_ token: String) async -> Bool {
        guard currentSession(token: token) != nil, let want = sessionPort else { return false }
        let port = await ensureListener()
        guard port == want else {
            cacheLog("Lokaler Proxy auf neuem Port (\(port.map(String.init) ?? "keiner")) → Neuladen über route")
            return false
        }
        return true
    }

    private func proxyURL(_ s: DiskCacheSession, port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)/c/\(s.token)/\(s.fileName)")!
    }

    private func currentSession(token: String) -> DiskCacheSession? {
        guard let s = session, s.token == token else { return nil }
        return s
    }

    // MARK: Listener

    /// Läuft der Listener (nach Ruhezustand kann er tot sein), sonst neu auf 127.0.0.1 mit freiem Port.
    private func ensureListener() async -> UInt16? {
        if let l = listener, case .ready = l.state, let p = l.port?.rawValue, p != 0 { return p }
        if let running = listenerStart { return await running.value }
        listener?.cancel(); listener = nil
        let t = Task { await self.startListenerPreferringLastPort() }
        listenerStart = t
        let p = await t.value
        listenerStart = nil
        return p
    }

    private func startListenerPreferringLastPort() async -> UInt16? {
        if let last = lastPort, let p = await startListener(port: last) { return p }
        return await startListener(port: .any)
    }

    private func startListener(port: NWEndpoint.Port) async -> UInt16? {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        let l: NWListener
        do { l = try NWListener(using: params) } catch {
            cacheError("Listener: \(short(error))")
            return nil
        }
        let once = DiskCacheOnce()
        let q = queue
        let ready: Bool = await withCheckedContinuation { (k: CheckedContinuation<Bool, Never>) in
            l.stateUpdateHandler = { [weak self] st in
                switch st {
                case .ready:
                    if once.fire() { k.resume(returning: true) }
                case .failed(_):
                    if once.fire() { k.resume(returning: false) }
                    Task { await self?.listenerEnded(l, failed: true) }
                case .cancelled:
                    if once.fire() { k.resume(returning: false) }
                    // Rückrufe lösen (sie halten den Listener und den Proxy).
                    l.stateUpdateHandler = nil
                    l.newConnectionHandler = nil
                    Task { await self?.listenerEnded(l, failed: false) }
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: q)
            q.asyncAfter(deadline: .now() + 3) { if once.fire() { k.resume(returning: false) } }
        }
        guard ready, let p = l.port?.rawValue, p != 0 else { l.cancel(); return nil }
        listener = l
        lastPort = l.port
        return p
    }

    /// Listener fiel aus (z. B. im Hintergrund): bei offener Sitzung gleich neu, möglichst auf demselben Port.
    private func listenerEnded(_ l: NWListener, failed: Bool) async {
        guard listener === l else { return }
        listener = nil
        l.cancel()
        guard failed, session != nil else { return }
        let p = await ensureListener()
        cacheLog(p == sessionPort ? "Lokaler Proxy neu gestartet (gleicher Port)"
                                  : "Lokaler Proxy neu gestartet (Port \(p.map(String.init) ?? "keiner"))")
    }

    // MARK: Verbindungen

    nonisolated private func accept(_ c: NWConnection) {
        c.stateUpdateHandler = { st in
            switch st {
            case .failed(_): c.cancel()
            case .cancelled: c.stateUpdateHandler = nil
            default: break
            }
        }
        c.start(queue: queue)
        Task { await self.serve(c) }
    }

    nonisolated private func serve(_ c: NWConnection) async {
        guard Self.isLoopback(c.endpoint) else { c.cancel(); return }
        // Kommt die Anfrage nicht in 10 s, Verbindung schließen (das beendet auch das Warten auf Daten).
        let got = DiskCacheOnce()
        queue.asyncAfter(deadline: .now() + 10) { if got.fire() { c.cancel() } }
        let request = await Self.readRequest(c)
        guard got.fire(), let request else { c.cancel(); return }
        guard request.method == "GET" || request.method == "HEAD" else {
            await Self.finish(c, DiskCacheHTTP.plainHead(status: 405)); return
        }
        guard let token = DiskCacheHTTP.token(fromPath: request.path), let s = await currentSession(token: token) else {
            await Self.finish(c, DiskCacheHTTP.plainHead(status: 404)); return
        }
        let redirect = DiskCacheHTTP.plainHead(status: 307, headers: [("Location", s.origin.absoluteString)])
        if await s.passthrough { await Self.finish(c, redirect); return }

        let plan = s.plan, total = plan.totalLength
        let want = HTTPByteRangeRequest.parse(request.headers["range"], total: total)
        let bytes: ClosedRange<Int64>
        switch want {
        case .unsatisfiable:
            await Self.finish(c, DiskCacheHTTP.plainHead(status: 416, headers: [("Content-Range", "bytes */\(total)")])); return
        case .full: bytes = 0...(total - 1)
        case .partial(let r): bytes = r
        }
        let head = DiskCacheHTTP.mediaHead(status: want == .full ? 200 : 206, contentType: s.contentType,
                                           range: want == .full ? nil : bytes, total: total)
        if request.method == "HEAD" { await Self.finish(c, head); return }

        // Kleine Proben (Dateiende, 1 Byte) verschieben die Leseposition nicht.
        let moves = Int64(bytes.count) >= policy.blockSize
        if moves { await s.beginRead(at: bytes.lowerBound) }
        // Erster Block vor dem Kopf: scheitert er, Umleitung auf den Ursprung (fail open).
        let firstBlock = plan.block(at: bytes.lowerBound), lastBlock = plan.block(at: bytes.upperBound)
        var pending: Data
        do { pending = try await s.block(firstBlock) } catch {
            cacheError("Block \(firstBlock) nicht verfügbar (\(short(error))) → Umleitung auf die Quelle")
            await Self.finish(c, redirect); return
        }
        do {
            try await Self.send(c, Data(head.utf8))
            let chunk = 512 * 1024
            for b in firstBlock...lastBlock {
                let d: Data
                if b == firstBlock { d = pending; pending = Data() } else { d = try await s.block(b) }
                guard let slice = plan.slice(of: b, within: bytes) else { break }
                let base = plan.range(of: b).lowerBound
                var off = slice.lowerBound
                while off < slice.upperBound {
                    let end = min(off + chunk, slice.upperBound)
                    try await Self.send(c, d.subdata(in: (d.startIndex + off)..<(d.startIndex + end)))
                    await s.noteRead(base + Int64(end), bytes: end - off, movesPosition: moves)
                    off = end
                }
            }
            await Self.finish(c, nil)
        } catch {
            // Engine hat die Verbindung geschlossen (Sprung) oder der Ursprung fiel aus: Verbindung zu,
            // die Engine verbindet neu.
            c.cancel()
        }
    }

    nonisolated private static func isLoopback(_ e: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = e else { return false }
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback || (a.asIPv4?.isLoopback ?? false)
        case .name(let n, _): return n == "localhost" || n == "127.0.0.1"
        @unknown default: return false
        }
    }

    nonisolated private static func readRequest(_ c: NWConnection) async -> HTTPRequest? {
        var buf = Data()
        while buf.count <= 64 * 1024 {
            guard let chunk = await receive(c) else { return nil }
            buf.append(chunk)
            switch HTTPRequest.parse(buf) {
            case .complete(let r): return r
            case .incomplete: continue
            default: return nil
            }
        }
        return nil
    }

    /// nil = Verbindung zu, Fehler oder leere Lieferung. Leer ohne Ende zählt als Ende: sonst liefe
    /// `readRequest` ohne neue Daten im Kreis; der Aufrufer schließt die Verbindung dann.
    nonisolated private static func receive(_ c: NWConnection) async -> Data? {
        await withCheckedContinuation { (k: CheckedContinuation<Data?, Never>) in
            c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                if let data, !data.isEmpty { k.resume(returning: data) } else { k.resume(returning: nil) }
            }
        }
    }

    nonisolated private static func send(_ c: NWConnection, _ d: Data) async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            c.send(content: d, completion: .contentProcessed { e in
                if let e { k.resume(throwing: e) } else { k.resume() }
            })
        }
    }

    /// Letzte Daten (oder nur das Ende) senden, dann schließen.
    nonisolated private static func finish(_ c: NWConnection, _ head: String?) async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            c.send(content: head.map { Data($0.utf8) }, contentContext: .finalMessage, isComplete: true,
                   completion: .contentProcessed { _ in k.resume() })
        }
        c.cancel()
    }
}
