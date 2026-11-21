import Foundation

/// Welle C-d: frei wählbarer Satz Bewertungs-Icons. Die Datei liegt beim Nutzer (Adresse in den Einstellungen) und
/// wird nur zur Laufzeit geladen; im Repo liegen keine fremden Bilder.
/// Formate: `{"imdb": "https://…/imdb.png", …}` oder `[{"name": "imdb", "url": "https://…"}]`
/// (statt `name` auch `source`/`id`, statt `url` auch `icon`/`image`). Nur https-Adressen.
public enum RatingIconSet {
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
        guard let o = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var out: [String: String] = [:]
        func add(_ name: String?, _ url: String?) {
            guard let name, let url, let u = URL(string: url), u.scheme == "https", u.host != nil else { return }
            let key = source(name)
            if !key.isEmpty, out[key] == nil { out[key] = url }
        }
        if let d = o as? [String: Any] {
            // Auch {"icons": {...}} bzw. {"icons": [...]}.
            if let inner = d["icons"] { return parse((try? JSONSerialization.data(withJSONObject: inner)) ?? Data()) }
            for (k, v) in d { add(k, v as? String) }
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
