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
