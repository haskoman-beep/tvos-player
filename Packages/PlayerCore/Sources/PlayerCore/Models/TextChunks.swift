import Foundation

/// Langer Text in fokussierbare Stücke (tvOS scrollt nur von Fokus zu Fokus).
public enum TextChunks {
    /// Absätze; Absätze über `maxLength` an Satzgrenzen weiter geteilt (ein Satz allein bleibt ganz).
    public static func split(_ text: String, maxLength: Int = 400) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { p -> [String] in
                guard p.count > maxLength else { return [p] }
                var out: [String] = []
                var cur = ""
                for s in sentences(p) {
                    if !cur.isEmpty, cur.count + 1 + s.count > maxLength { out.append(cur); cur = s }
                    else { cur = cur.isEmpty ? s : cur + " " + s }
                }
                if !cur.isEmpty { out.append(cur) }
                return out
            }
    }

    /// Sätze: Schnitt nach ". ", "! ", "? ".
    static func sentences(_ p: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var prev: Character?
        for ch in p {
            if ch == " ", let pr = prev, ".!?".contains(pr) {
                out.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
            prev = ch
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
