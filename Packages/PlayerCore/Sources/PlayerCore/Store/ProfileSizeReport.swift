import Foundation

/// Build 5 device test 1 (profiles.json 24.0 KB → 19.4 KB between two sessions, cause unknown from the log): bytes
/// per top-level key of one profile as the store writes it, and a line naming the keys that shrank between two saves.
/// The next device log then says which part of a profile got smaller (addons, collections, rows, look …).
public enum ProfileSizeReport {
    /// Bytes per top-level JSON key of `p` (same encoder as `ProfileStore.save`). Empty when encoding fails.
    public static func sections(_ p: Profile) -> [String: Int] {
        guard let data = try? JSONEncoder().encode(p),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (key, value) in object {
            let piece = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data()
            out[key] = piece.count
        }
        return out
    }

    /// Smallest change per key that a line names (smaller ones are tokens, dates, single values).
    public static let minimumDelta = 256

    /// "Profil <name>: −4,6 KB · addons 12,0 → 7,5 KB, collections …" for the keys that shrank by at least
    /// `minimumDelta`; nil when none did. Keys that grew are not listed (a new look, a new row is no loss).
    public static func shrinkLine(name: String, before: [String: Int], after: [String: Int]) -> String? {
        var parts: [String] = []
        for key in before.keys.sorted() {
            let old = before[key] ?? 0, new = after[key] ?? 0
            guard old - new >= minimumDelta else { continue }
            parts.append(new == 0 ? "\(key) \(kb(old)) → fehlt" : "\(key) \(kb(old)) → \(kb(new))")
        }
        guard !parts.isEmpty else { return nil }
        let total = before.values.reduce(0, +) - after.values.reduce(0, +)
        return "Profil \(name) kleiner geworden (\(total >= 0 ? "−" : "+")\(kb(abs(total)))): " + parts.joined(separator: ", ")
    }

    /// "addons 12,0 KB · collections 3,1 KB …", largest first (load line).
    public static func summary(_ sections: [String: Int], top: Int = 6) -> String {
        sections.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(top).map { "\($0.key) \(kb($0.value))" }.joined(separator: " · ")
    }

    static func kb(_ bytes: Int) -> String {
        let v = (Double(bytes) / 1024 * 10).rounded() / 10
        return String(format: "%.1f KB", v).replacingOccurrences(of: ".", with: ",")
    }
}
