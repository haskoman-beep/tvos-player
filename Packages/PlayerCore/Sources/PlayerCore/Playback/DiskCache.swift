import Foundation

// Plattencache für den laufenden Film: reine Logik (Blockplan, Range-Mathematik, Verdrängung, Platzgrenzen,
// Kopfzeilen). Der Netzteil (lokaler HTTP-Server, Abruf beim Ursprung) liegt in der App
// (App/Sources/Playback/DiskCacheProxy.swift).

// MARK: - Range / Content-Range

/// Ergebnis einer `Range`-Kopfzeile gegen eine bekannte Dateigröße.
public enum HTTPByteRangeRequest: Equatable, Sendable {
    /// Keine (oder nicht verstandene) Range: ganze Datei, Antwort 200.
    case full
    /// Antwort 206 mit diesen Bytes (beide Enden einschließlich, schon auf die Größe geklemmt).
    case partial(ClosedRange<Int64>)
    /// Antwort 416 (`Content-Range: bytes */total`).
    case unsatisfiable

    /// Liest `bytes=a-b`, `bytes=a-` und `bytes=-n` (RFC 9110 §14.1.2). Mehrere Bereiche: nur der erste zählt.
    /// Eine syntaktisch kaputte Kopfzeile wird ignoriert (→ `.full`), wie es der Standard erlaubt.
    public static func parse(_ header: String?, total: Int64) -> HTTPByteRangeRequest {
        guard let header else { return .full }
        let h = header.trimmingCharacters(in: .whitespaces)
        guard h.lowercased().hasPrefix("bytes=") else { return .full }
        let spec = h.dropFirst(6).split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard let dash = spec.firstIndex(of: "-") else { return .full }
        let a = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let b = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if a.isEmpty {
            // Suffix: die letzten n Bytes.
            guard let n = Int64(b), n >= 0 else { return .full }
            guard n > 0, total > 0 else { return .unsatisfiable }
            return .partial(max(0, total - n)...(total - 1))
        }
        guard let start = Int64(a), start >= 0 else { return .full }
        var end = total - 1
        if !b.isEmpty {
            guard let e = Int64(b), e >= start else { return .full }
            end = min(e, total - 1)
        }
        guard start < total else { return .unsatisfiable }
        return .partial(start...end)
    }
}

/// `Content-Range: bytes first-last/total` (oder `bytes */total`, `…/*`).
public struct HTTPContentRange: Equatable, Sendable {
    /// nil bei `bytes */total` (Antwort auf eine unerfüllbare Anfrage).
    public var range: ClosedRange<Int64>?
    /// nil bei `/*` (Größe unbekannt).
    public var total: Int64?

    public init(range: ClosedRange<Int64>?, total: Int64?) { self.range = range; self.total = total }

    public static func parse(_ value: String?) -> HTTPContentRange? {
        guard let value else { return nil }
        let v = value.trimmingCharacters(in: .whitespaces)
        guard v.lowercased().hasPrefix("bytes") else { return nil }
        let rest = v.dropFirst(5).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        var total: Int64?
        if parts[1] != "*" {
            guard let t = Int64(parts[1]), t >= 0 else { return nil }
            total = t
        }
        if parts[0] == "*" {
            guard total != nil else { return nil }
            return HTTPContentRange(range: nil, total: total)
        }
        let se = parts[0].split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard se.count == 2, let s = Int64(se[0]), let e = Int64(se[1]), s >= 0, e >= s else { return nil }
        if let total, e >= total { return nil }
        return HTTPContentRange(range: s...e, total: total)
    }

    public var headerValue: String {
        let t = total.map(String.init) ?? "*"
        guard let range else { return "bytes */\(t)" }
        return "bytes \(range.lowerBound)-\(range.upperBound)/\(t)"
    }
}

// MARK: - Blockplan

/// Teilt eine Datei bekannter Größe in gleich große Blöcke (der letzte ist kürzer).
public struct DiskCacheBlockPlan: Equatable, Sendable {
    public let blockSize: Int64
    public let totalLength: Int64

    public init(blockSize: Int64, totalLength: Int64) {
        precondition(blockSize > 0 && totalLength >= 0)
        self.blockSize = blockSize; self.totalLength = totalLength
    }

    public var blockCount: Int { totalLength == 0 ? 0 : Int((totalLength + blockSize - 1) / blockSize) }

    /// Block, in dem das Byte liegt (auf den gültigen Bereich geklemmt).
    public func block(at offset: Int64) -> Int {
        guard blockCount > 0 else { return 0 }
        return Int(min(max(0, offset), totalLength - 1) / blockSize)
    }

    /// Bytes des Blocks (einschließlich).
    public func range(of block: Int) -> ClosedRange<Int64> {
        let s = Int64(block) * blockSize
        return s...(min(s + blockSize, totalLength) - 1)
    }

    public func length(of block: Int) -> Int64 { Int64(range(of: block).count) }

    /// Blöcke, die einen Bytebereich abdecken.
    public func blocks(covering r: ClosedRange<Int64>) -> ClosedRange<Int> { block(at: r.lowerBound)...block(at: r.upperBound) }

    /// Teil eines Blocks, der in einem Bytebereich liegt, als Versatz im Block (für das Ausschneiden).
    public func slice(of block: Int, within r: ClosedRange<Int64>) -> Range<Int>? {
        let br = range(of: block)
        let lo = max(br.lowerBound, r.lowerBound), hi = min(br.upperBound, r.upperBound)
        guard lo <= hi else { return nil }
        return Int(lo - br.lowerBound)..<Int(hi - br.lowerBound + 1)
    }
}

// MARK: - Regeln

/// Feste Größen des Caches.
public struct DiskCachePolicy: Equatable, Sendable {
    public var blockSize: Int64 = 4 * 1024 * 1024
    /// Vorlauf ab der Leseposition (höchstens die Hälfte des Budgets).
    public var readAheadBytes: Int64 = 1024 * 1024 * 1024
    /// So viel hinter der Leseposition bleibt bevorzugt liegen (Rückspulen).
    public var backWindowBytes: Int64 = 512 * 1024 * 1024
    /// Gleichzeitige Vorlauf-Abrufe beim Ursprung (der Leser kommt zusätzlich).
    public var parallelPrefetches = 2
    /// Nie weniger freien Platz auf dem Gerät lassen.
    public var reserveFreeBytes: Int64 = 2_000_000_000
    /// Darunter lohnt sich der Cache nicht: direkt abspielen.
    public var minimumBudgetBytes: Int64 = 64 * 1024 * 1024
    /// Fehlgeschlagene Abrufe in Folge, ab denen die Sitzung nur noch auf den Ursprung umleitet.
    public var failuresUntilPassthrough = 3
    /// Leerlauf-Grenze je Abruf beim Ursprung (keine Daten so lange → Abbruch).
    public var originIdleTimeout: TimeInterval = 6
    /// Harte Grenze für einen Block, auf den die Engine wartet (eigener Abruf oder Warten auf den Vorlauf):
    /// danach 307 bzw. Verbindung zu – klar unter der 20-s-Lesegrenze der Engine.
    public var readerHardLimit: TimeInterval = 14
    /// Harte Grenze für die Probe (Block 0) vor dem Start.
    public var probeHardLimit: TimeInterval = 13
    /// Versuche je Block: Vorlauf darf wiederholen (ohne harte Grenze, nur Leerlauf), der Leser nicht.
    public var prefetchAttempts = 2
    public var readerAttempts = 1
    /// Braucht ein Block im gleitenden Mittel länger, ist der Ursprung zu langsam: erst weniger parallel,
    /// bei einem Abruf Umleitung auf die direkte Adresse.
    public var slowBlockSeconds: TimeInterval = 10
    /// Messungen, bevor die Geschwindigkeit zählt.
    public var minimumRateSamples = 2

    /// Ursprung drosselt (429/503): weniger parallele Abrufe statt Fehler zählen.
    public static func isThrottle(status: Int) -> Bool { status == 429 || status == 503 }

    public init() {}

    /// Was bei der gemessenen Geschwindigkeit zu tun ist.
    public func slowAction(rate: DiskCacheRate, parallel: Int) -> DiskCacheSlowAction {
        guard rate.samples >= minimumRateSamples, let s = rate.secondsPerBlock(blockSize), s > slowBlockSeconds else { return .none }
        return parallel > 1 ? .lowerParallel : .passthrough
    }

    /// Vorlauf für ein Budget: nie mehr als die Hälfte, mindestens ein Block.
    public func readAhead(budget: Int64) -> Int64 { max(blockSize, min(readAheadBytes, budget / 2)) }
}

public enum DiskCacheSlowAction: Equatable, Sendable { case none, lowerParallel, passthrough }

/// Gleitendes Mittel der Abrufdauer je Byte (über die Zeit gemittelt, nicht über die Rate: ein schneller
/// Ausreißer kippt ein langsames Mittel nicht sofort).
public struct DiskCacheRate: Equatable, Sendable {
    public private(set) var secondsPerByte: Double?
    public private(set) var samples = 0
    public var alpha = 0.3

    public init() {}

    public var bytesPerSecond: Double? { secondsPerByte.flatMap { $0 > 0 ? 1 / $0 : nil } }

    public mutating func note(bytes: Int64, seconds: TimeInterval) {
        guard bytes > 0 else { return }
        let v = max(seconds, 0) / Double(bytes)
        secondsPerByte = secondsPerByte.map { $0 + alpha * (v - $0) } ?? v
        samples += 1
    }

    public func secondsPerBlock(_ blockSize: Int64) -> Double? { secondsPerByte.map { $0 * Double(blockSize) } }
}

/// Wie viel der Cache belegen darf.
public enum DiskCacheBudget {
    /// Grenze = min(Einstellung, freier Platz + eigene Belegung − Reserve), nie negativ. `free` nil (unbekannt) = 0.
    public static func limit(settingBytes: Int64, freeBytes: Int64?, ownBytes: Int64, reserve: Int64) -> Int64 {
        guard let freeBytes else { return 0 }
        return max(0, min(settingBytes, freeBytes + ownBytes - reserve))
    }

    /// Ein neuer Block darf auf die Platte, wenn danach noch die Reserve frei bleibt.
    public static func mayWrite(blockBytes: Int64, freeBytes: Int64?, reserve: Int64) -> Bool {
        guard let freeBytes else { return false }
        return freeBytes - blockBytes >= reserve
    }
}

// MARK: - Index

/// Welche Blöcke auf der Platte liegen; Vorlauf-Wahl und Verdrängung nach der Leseposition.
public struct DiskCacheIndex: Equatable, Sendable {
    public let plan: DiskCacheBlockPlan
    public private(set) var cached: Set<Int> = []

    public init(plan: DiskCacheBlockPlan) { self.plan = plan }

    public var cachedBytes: Int64 { cached.reduce(0) { $0 + plan.length(of: $1) } }
    public func contains(_ block: Int) -> Bool { cached.contains(block) }
    public mutating func insert(_ block: Int) { if block >= 0, block < plan.blockCount { cached.insert(block) } }
    public mutating func remove(_ block: Int) { cached.remove(block) }
    public mutating func removeAll() { cached.removeAll() }

    /// Nächster fehlender Block im Vorlauf-Fenster ab der Leseposition (nächster zuerst), oder nil.
    public func nextPrefetch(readPosition: Int64, aheadBytes: Int64, excluding busy: Set<Int>) -> Int? {
        guard plan.blockCount > 0, aheadBytes > 0 else { return nil }
        let first = plan.block(at: readPosition)
        let last = plan.block(at: readPosition + aheadBytes - 1)
        for b in first...last where !cached.contains(b) && !busy.contains(b) { return b }
        return nil
    }

    /// Blöcke, die weg müssen, damit `budgetBytes` reicht (ohne sie schon zu entfernen). Reihenfolge:
    /// 1. weit hinter der Leseposition (außerhalb `backWindow`), 2. weit voraus (außerhalb `ahead`),
    /// 3. hinter der Leseposition im Fenster, 4. voraus im Fenster – jeweils der fernste zuerst.
    /// Der Block an der Leseposition und `protected` (laufende Abrufe) bleiben.
    public func evictionVictims(budgetBytes: Int64, readPosition: Int64, aheadBytes: Int64, backWindowBytes: Int64,
                                protected: Set<Int> = []) -> [Int] {
        var excess = cachedBytes - budgetBytes
        guard excess > 0 else { return [] }
        let r = plan.block(at: readPosition)
        let aheadBlocks = Int((aheadBytes + plan.blockSize - 1) / plan.blockSize)
        let backBlocks = Int((backWindowBytes + plan.blockSize - 1) / plan.blockSize)
        func tier(_ b: Int) -> Int {
            if b < r { return r - b > backBlocks ? 0 : 2 }
            return b - r >= aheadBlocks ? 1 : 3
        }
        let candidates = cached.filter { $0 != r && !protected.contains($0) }.sorted { x, y in
            let tx = tier(x), ty = tier(y)
            if tx != ty { return tx < ty }
            let dx = abs(x - r), dy = abs(y - r)
            return dx != dy ? dx > dy : x < y
        }
        var out: [Int] = []
        for b in candidates where excess > 0 {
            out.append(b); excess -= plan.length(of: b)
        }
        return out
    }
}

// MARK: - Quelle

/// Ob eine Quelle durch den Cache darf. HLS/DASH und unbekannte Adressen gehen direkt.
public enum DiskCacheSource {
    public enum Decision: Equatable, Sendable {
        case cache
        /// Kein bekannter Dateityp in der Adresse: nach dem Inhaltstyp der ersten Antwort entscheiden.
        case checkContentType
        case bypass(String)
    }

    public static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "webm", "avi", "ts", "m2ts", "mpg", "mpeg", "wmv", "flv"]
    static let streamingExtensions: Set<String> = ["m3u8", "m3u", "mpd", "ism", "isml"]

    /// Quelle mit Anmeldung (Kopfzeilen oder Benutzer in der Adresse): Cache umgehen – ein 307-Rückfall auf
    /// einen anderen Host verlöre die Anmeldedaten (die Engine verwirft sie bei Host-Wechsel).
    public static func needsCredentials(_ url: URL, headers: [String: String]) -> Bool {
        if url.user != nil || url.password != nil { return true }
        let secret: Set<String> = ["authorization", "cookie", "proxy-authorization",
                                   "x-emby-token", "x-emby-authorization", "x-mediabrowser-token"]
        return headers.keys.contains { secret.contains($0.lowercased()) }
    }

    public static func decide(_ url: URL, nativeHLS: Bool) -> Decision {
        if nativeHLS { return .bypass("HLS") }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .bypass("kein http") }
        let host = (url.host ?? "").lowercased()
        if host.isEmpty || host == "localhost" || host == "127.0.0.1" || host == "::1" { return .bypass("lokal") }
        let ext = url.pathExtension.lowercased()
        if streamingExtensions.contains(ext) { return .bypass("HLS/DASH") }
        if videoExtensions.contains(ext) { return .cache }
        return .checkContentType
    }

    /// Inhaltstyp einer Datei, die gepuffert werden darf (kein Playlist-/Manifest-/Text-Typ).
    public static func contentTypeAllowed(_ type: String?) -> Bool {
        let t = (type ?? "").lowercased()
        if t.contains("mpegurl") || t.contains("dash+xml") || t.hasPrefix("text/") || t.contains("json") || t.contains("html") { return false }
        return t.hasPrefix("video/") || t.contains("octet-stream") || t.contains("matroska") || t == "application/mp4"
    }

    /// Dateiname im Proxy-Pfad: nur die Endung bleibt (die Engine kann daran den Typ erkennen),
    /// der echte Name nicht (öffentliches Log). Unbekannt → nach dem Inhaltstyp, sonst ohne Endung.
    public static func proxyFileName(for url: URL, contentType: String?) -> String {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return "media.\(ext)" }
        let t = (contentType ?? "").lowercased()
        if t.contains("matroska") { return "media.mkv" }
        if t.contains("mp4") { return "media.mp4" }
        if t.contains("webm") { return "media.webm" }
        if t.contains("mp2t") { return "media.ts" }
        return "media"
    }
}

// MARK: - HTTP-Antworten des Proxys

public enum DiskCacheHTTP {
    /// Kopfzeilen-Wert ohne Zeilenumbrüche (gegen Header-Injektion aus Ursprungsantworten); leer → nil.
    public static func safeHeaderValue(_ v: String?) -> String? {
        guard let v else { return nil }
        let clean = String(v.unicodeScalars.filter { $0 != "\r" && $0 != "\n" && $0 != "\0" })
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : clean
    }

    /// Inhaltstyp für die Antwort an die Engine, Rückfall `application/octet-stream`.
    public static func safeContentType(_ v: String?) -> String { safeHeaderValue(v) ?? "application/octet-stream" }

    /// Kopf einer Antwort mit Körper (200/206). `range` nil = ganze Datei.
    public static func mediaHead(status: Int, contentType: String, range: ClosedRange<Int64>?, total: Int64,
                                 headOnly: Bool = false) -> String {
        let length = range.map { Int64($0.count) } ?? total
        var h = "HTTP/1.1 \(status) \(reason(status))\r\n"
        h += "Content-Type: \(safeContentType(contentType))\r\n"
        h += "Content-Length: \(length)\r\n"
        h += "Accept-Ranges: bytes\r\n"
        if let range { h += "Content-Range: \(HTTPContentRange(range: range, total: total).headerValue)\r\n" }
        h += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return h
    }

    /// Antwort ohne Körper (307 Umleitung, 404, 416 …).
    public static func plainHead(status: Int, headers: [(String, String)] = []) -> String {
        var h = "HTTP/1.1 \(status) \(reason(status))\r\nContent-Length: 0\r\n"
        for (k, v) in headers { if let v = safeHeaderValue(v) { h += "\(k): \(v)\r\n" } }
        h += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return h
    }

    /// Zielpfad `/c/<token>/<name>` → Token, sonst nil.
    public static func token(fromPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "c" else { return nil }
        return String(parts[1])
    }

    static func reason(_ s: Int) -> String {
        [200: "OK", 206: "Partial Content", 307: "Temporary Redirect", 400: "Bad Request", 404: "Not Found",
         405: "Method Not Allowed", 416: "Range Not Satisfiable", 502: "Bad Gateway"][s] ?? "OK"
    }
}

/// Zähler einer Sitzung (für die Log-Zeile beim Schließen).
public struct DiskCacheStats: Equatable, Sendable {
    public var hits = 0
    public var misses = 0
    public var prefetched = 0
    public var evicted = 0
    public var originBytes: Int64 = 0
    public var servedBytes: Int64 = 0
    public var notWritten = 0

    public init() {}

    public var summary: String {
        let mb: (Int64) -> String = { String(format: "%.0f MB", Double($0) / 1_000_000) }
        return "Treffer \(hits) · Abrufe \(misses) · Vorlauf \(prefetched) · verdrängt \(evicted)"
            + (notWritten > 0 ? " · nicht gespeichert \(notWritten)" : "")
            + " · vom Ursprung \(mb(originBytes)) · ausgeliefert \(mb(servedBytes))"
    }
}
