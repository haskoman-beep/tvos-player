import Foundation

/// Wave W-a: lenient field decoding for addon responses. Addons send numbers as text and text as numbers
/// (`releaseInfo: 2019`, `season: "1"`); a field with an unexpected type or `null` becomes nil instead of failing
/// the whole object. Lists skip entries that cannot be read and count them.
enum LenientJSON {
    /// A JSON number as text: whole numbers without a fraction ("2019", not "2019.0"), others as Swift prints them.
    static func text(_ d: Double) -> String? {
        guard d.isFinite else { return nil }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    /// Whole number from text (" 12 ", "3.0"); nil for anything else.
    static func int(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = Int(t) { return i }
        guard let d = Double(t) else { return nil }
        return int(d)
    }

    /// Whole number from a JSON number; nil for fractions, infinity or values beyond Int.
    static func int(_ d: Double) -> Int? {
        guard d.isFinite, d == d.rounded(), abs(d) < 1e15 else { return nil }
        return Int(d)
    }
}

/// One list entry: the value, or nil when it could not be read (never throws, so the list survives).
struct LenientElement<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// Text; a JSON number becomes text ("2019", "6.3"). Missing, `null`, booleans, objects and arrays → nil.
    func lenientString(_ key: Key) -> String? {
        if let s = (try? decodeIfPresent(String.self, forKey: key)) ?? nil { return s }
        if let i = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return String(i) }
        if let d = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return LenientJSON.text(d) }
        return nil
    }

    /// Text without surrounding blanks; empty text → nil.
    func lenientNonEmpty(_ key: Key) -> String? {
        guard let s = lenientString(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// Whole number; text like "1" or a JSON 1.0 counts. Fractions, other types and `null` → nil.
    func lenientInt(_ key: Key) -> Int? {
        if let i = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return i }
        if let d = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return LenientJSON.int(d) }
        if let s = (try? decodeIfPresent(String.self, forKey: key)) ?? nil { return LenientJSON.int(s) }
        return nil
    }

    /// Truth value; also "true"/"false", "1"/"0" and the numbers 1/0. Anything else → nil.
    func lenientBool(_ key: Key) -> Bool? {
        if let b = (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil { return b }
        if let i = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return i == 0 ? false : i == 1 ? true : nil }
        switch ((try? decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    /// List of texts; numbers inside become text, other entries are dropped. A single text counts as a list of one.
    func lenientStrings(_ key: Key) -> [String]? {
        if let list = (try? decodeIfPresent([LenientElement<LenientText>].self, forKey: key)) ?? nil {
            return list.compactMap { $0.value?.text }
        }
        return lenientString(key).map { [$0] }
    }

    /// List whose unreadable entries are skipped; `skipped` counts them. nil when the key is missing or no list.
    func lenientList<T: Decodable>(_ type: T.Type, _ key: Key) -> (items: [T], skipped: Int)? {
        guard let list = (try? decodeIfPresent([LenientElement<T>].self, forKey: key)) ?? nil else { return nil }
        let items = list.compactMap(\.value)
        return (items, list.count - items.count)
    }
}

/// A list entry that may be text or a number (`options: ["Action", 2019]`).
struct LenientText: Decodable {
    var text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s; return }
        if let i = try? c.decode(Int.self) { text = String(i); return }
        if let d = try? c.decode(Double.self), let t = LenientJSON.text(d) { text = t; return }
        throw DecodingError.typeMismatch(String.self, .init(codingPath: c.codingPath, debugDescription: "no text"))
    }
}
