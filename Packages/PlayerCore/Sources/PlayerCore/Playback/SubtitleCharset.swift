import Foundation

/// Zeichensatz von Addon-Untertiteln erkennen und nach UTF-8 umwandeln (Welle D-a).
///
/// Reihenfolge: BOM (UTF-8, UTF-16 LE/BE) → gültiges UTF-8 → UTF-16 ohne BOM (Nullbytes) → CP1252
/// (umfasst ISO-8859-1 für alle druckbaren Zeichen). Danach werden doppelt kodierte Zeichen repariert
/// („Ã¤“ → „ä“, „â€ž“ → „„“): Folgen, die als UTF-8-Bytes gelesen in CP1252 angezeigt wurden.
/// Ergebnis ist immer UTF-8 ohne BOM.
public enum SubtitleCharset {
    public enum Source: String, Sendable, Equatable {
        case utf8, utf8BOM, utf16LE, utf16BE, cp1252
    }

    public struct Decoded: Sendable, Equatable {
        public var text: String
        public var source: Source
        /// Reparierte doppelt kodierte Zeichen.
        public var repaired: Int
        public var utf8Data: Data { Data(text.utf8) }
        public var logText: String { "\(source.rawValue)\(repaired > 0 ? " · \(repaired) Zeichen repariert" : "")" }
    }

    /// Erkennen, umwandeln, reparieren.
    public static func decode(_ data: Data) -> Decoded {
        let bytes = [UInt8](data)
        let (raw, source) = detect(bytes)
        let (fixed, n) = repairMojibake(raw)
        return Decoded(text: fixed, source: source, repaired: n)
    }

    /// Nur die Erkennung und Umwandlung (ohne Reparatur).
    static func detect(_ b: [UInt8]) -> (String, Source) {
        if b.starts(with: [0xEF, 0xBB, 0xBF]) {
            let rest = Array(b.dropFirst(3))
            return (decodeUTF8(rest) ?? decodeCP1252(rest), .utf8BOM)
        }
        if b.starts(with: [0xFF, 0xFE]) { return (decodeUTF16(Array(b.dropFirst(2)), littleEndian: true), .utf16LE) }
        if b.starts(with: [0xFE, 0xFF]) { return (decodeUTF16(Array(b.dropFirst(2)), littleEndian: false), .utf16BE) }
        if let le = utf16WithoutBOM(b) { return (decodeUTF16(b, littleEndian: le), le ? .utf16LE : .utf16BE) }
        if let s = decodeUTF8(b) { return (s, .utf8) }
        return (decodeCP1252(b), .cp1252)
    }

    // MARK: UTF-8

    /// Streng: nil bei jeder ungültigen Folge.
    static func decodeUTF8(_ bytes: [UInt8]) -> String? {
        var scalars = String.UnicodeScalarView()
        var it = bytes.makeIterator()
        var codec = UTF8()
        while true {
            switch codec.decode(&it) {
            case .scalarValue(let s): scalars.append(s)
            case .emptyInput: return String(scalars)
            case .error: return nil
            }
        }
    }

    // MARK: UTF-16

    /// Ohne BOM: viele Nullbytes an ungeraden (LE) bzw. geraden (BE) Stellen in den ersten 400 Bytes.
    static func utf16WithoutBOM(_ b: [UInt8]) -> Bool? {
        let head = Array(b.prefix(400))
        guard head.count >= 8 else { return nil }
        var evenZero = 0, oddZero = 0
        for (i, x) in head.enumerated() where x == 0 { if i % 2 == 0 { evenZero += 1 } else { oddZero += 1 } }
        let half = head.count / 2
        if oddZero * 10 >= half * 3, evenZero * 10 < half { return true }
        if evenZero * 10 >= half * 3, oddZero * 10 < half { return false }
        return nil
    }

    static func decodeUTF16(_ b: [UInt8], littleEndian: Bool) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(b.count / 2)
        var i = 0
        while i + 1 < b.count {
            units.append(littleEndian ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : UInt16(b[i]) << 8 | UInt16(b[i + 1]))
            i += 2
        }
        // Kaputte Ersatzpaare werden zu U+FFFD statt die Datei zu verwerfen.
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: CP1252 / ISO-8859-1

    /// CP1252 0x80–0x9F; nicht belegte Stellen (0x81, 0x8D, 0x8F, 0x90, 0x9D) bleiben wie in ISO-8859-1.
    static let cp1252High: [UInt32] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
    ]
    /// Umkehrung für die Reparatur: Zeichen → CP1252-Byte.
    static let cp1252Reverse: [UInt32: UInt8] = {
        var m: [UInt32: UInt8] = [:]
        for (i, v) in cp1252High.enumerated() { m[v] = UInt8(0x80 + i) }
        return m
    }()

    static func decodeCP1252(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(bytes.count)
        for x in bytes {
            let v: UInt32 = (0x80...0x9F).contains(x) ? cp1252High[Int(x) - 0x80] : UInt32(x)
            if let s = Unicode.Scalar(v) { scalars.append(s) }
        }
        return String(scalars)
    }

    static func cp1252Byte(_ s: Unicode.Scalar) -> UInt8? {
        let v = s.value
        if v < 0x80 || (0xA0...0xFF).contains(v) { return UInt8(v) }
        return cp1252Reverse[v]
    }

    // MARK: Doppelt kodiert

    /// Ersetzt Folgen aus Startbyte (0xC2–0xF4) und passenden Folgebytes (0x80–0xBF), jeweils als CP1252-Zeichen
    /// gelesen, durch das eigentliche Zeichen. Einzelne „Ä“, „Ö“, „ß“ im richtigen Text bleiben stehen,
    /// weil ihnen kein Folgebyte-Zeichen folgt.
    static func repairMojibake(_ text: String) -> (String, Int) {
        let scalars = Array(text.unicodeScalars)
        // Schnell raus: ohne mögliches Startbyte nichts zu tun.
        guard scalars.contains(where: { (0xC2...0xF4).contains($0.value) }) else { return (text, 0) }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(scalars.count)
        var fixed = 0
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if let lead = cp1252Byte(s), let need = continuationCount(lead), i + need < scalars.count {
                var seq = [lead]
                for k in 1...need {
                    guard let c = cp1252Byte(scalars[i + k]), (0x80...0xBF).contains(c) else { break }
                    seq.append(c)
                }
                if seq.count == need + 1, let decoded = decodeUTF8(seq), let one = decoded.unicodeScalars.first,
                   decoded.unicodeScalars.count == 1 {
                    out.append(one); fixed += 1; i += need + 1; continue
                }
            }
            out.append(s); i += 1
        }
        return fixed > 0 ? (String(out), fixed) : (text, 0)
    }

    /// Anzahl der Folgebytes eines UTF-8-Startbytes (2-, 3-, 4-Byte-Folgen); nil = kein Startbyte.
    static func continuationCount(_ lead: UInt8) -> Int? {
        switch lead {
        case 0xC2...0xDF: 1
        case 0xE0...0xEF: 2
        case 0xF0...0xF4: 3
        default: nil
        }
    }
}
