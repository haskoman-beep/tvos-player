import Foundation

/// Welle C-d: frei wählbarer Satz Bewertungs-Icons. Die Datei liegt beim Nutzer (Adresse in den Einstellungen) und
/// wird nur zur Laufzeit geladen; im Repo liegen keine fremden Bilder.
/// Formate: `{"imdb": "https://…/imdb.png", …}` oder `[{"name": "imdb", "url": "https://…"}]`
/// (statt `name` auch `source`/`id`, statt `url` auch `icon`/`image`). Nur https-Adressen auf Rasterbilder
/// (png, jpg, jpeg, webp, heic); SVG kann tvOS nicht dekodieren.
public enum RatingIconSet {
    /// Grenzen gegen übergroße Dateien: höchstens 256 KB, 50 Einträge, 15 s Zeit.
    public static let maxBytes = 256 * 1024
    public static let maxEntries = 50
    public static let timeout: TimeInterval = 15
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]

    /// Quellnamen wie in den Bewertungen (`MDBList.scales`), mit üblichen Schreibweisen.
    static let aliases: [String: String] = [
        "rottentomatoes": "tomatoes", "rotten_tomatoes": "tomatoes", "rotten tomatoes": "tomatoes", "rt": "tomatoes", "tomatometer": "tomatoes",
        "audience": "popcorn", "rt_audience": "popcorn", "popcornmeter": "popcorn",
        "mc": "metacritic", "lb": "letterboxd", "mal": "myanimelist", "themoviedb": "tmdb",
    ]

    public static func source(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return aliases[n] ?? n
    }

    public static func parse(_ data: Data) -> [String: String] {
        guard data.count <= maxBytes, let o = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var out: [String: String] = [:]
        func add(_ name: String?, _ url: String?) {
            guard out.count < maxEntries, let name, let url, let u = URL(string: url), u.scheme == "https", u.host != nil,
                  imageExtensions.contains(u.pathExtension.lowercased()) else { return }
            let key = source(name)
            if !key.isEmpty, out[key] == nil { out[key] = url }
        }
        if let d = o as? [String: Any] {
            // Auch {"icons": {...}} bzw. {"icons": [...]}.
            if let inner = d["icons"] { return parse((try? JSONSerialization.data(withJSONObject: inner)) ?? Data()) }
            for (k, v) in d.sorted(by: { $0.key < $1.key }) { add(k, v as? String) }
        } else if let arr = o as? [[String: Any]] {
            for e in arr {
                add((e["name"] ?? e["source"] ?? e["id"]) as? String, (e["url"] ?? e["icon"] ?? e["image"]) as? String)
            }
        }
        return out
    }

    /// Nur https-Adressen gelten als Icon-Satz.
    public static func isValidSetURL(_ s: String?) -> Bool {
        guard let s, let u = URL(string: s.trimmingCharacters(in: .whitespaces)) else { return false }
        return u.scheme == "https" && u.host != nil
    }
}

/// Welle D-b (N-M3): Größe und Zeit schon während des Downloads begrenzen, nicht erst danach.
extension RatingIconSet {
    public enum DownloadError: Error, Equatable { case tooLarge, timedOut }

    /// Antwort Byte für Byte einsammeln und abbrechen, sobald sie `limit` überschreitet. Eine angekündigte Länge
    /// über der Grenze bricht sofort ab, ohne zu lesen (`expectedLength` < 0 = unbekannt).
    public static func collect<S: AsyncSequence>(_ bytes: S, expectedLength: Int64 = -1,
                                                 limit: Int = maxBytes) async throws -> Data where S.Element == UInt8 {
        if expectedLength > Int64(limit) { throw DownloadError.tooLarge }
        var out = Data()
        out.reserveCapacity(expectedLength > 0 ? Int(expectedLength) : 16 * 1024)
        for try await b in bytes {
            if out.count >= limit { throw DownloadError.tooLarge }
            out.append(b)
        }
        return out
    }

    /// Gesamtfrist für den ganzen Abruf (`URLRequest.timeoutInterval` ist nur eine Leerlaufgrenze: ein langsamer,
    /// stetiger Strom liefe sonst endlos). Nach `seconds` wird `op` abgebrochen und `timedOut` geworfen.
    public static func withDeadline<T: Sendable>(_ seconds: TimeInterval,
                                                 _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw DownloadError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw DownloadError.timedOut }
            return first
        }
    }
}
