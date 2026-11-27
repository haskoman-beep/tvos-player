import Foundation

/// Task 1.2: what decoding left out. Each entry is a path such as `profiles[1].appearance.accent`; the value there
/// was unreadable (unknown enum value from a newer build, wrong type, broken element) and the default took its place,
/// or the element was skipped or kept aside unread (`HomeLayout.unknownRows`, `Folder.unknownSources`).
public struct DecodeReport: Sendable, Equatable {
    public var ignored: [String]
    public init(ignored: [String] = []) { self.ignored = ignored }
    public var isEmpty: Bool { ignored.isEmpty }

    /// Fields whose loss empties a secret: API keys (the remote-log secret is one of them) and sync logins.
    public static let secretFields: Set<String> = ["apiKeys", "syncTokens"]

    /// Task 3.9: whether an ignored path runs through a secret-bearing field (`profiles[0].apiKeys`,
    /// `profiles[1].syncTokens.trakt`). Matches whole path segments (an index suffix like `[2]` aside), not substrings.
    public var touchesSecrets: Bool {
        ignored.contains { path in
            path.split(separator: ".").contains { seg in
                let name = seg.split(separator: "[", maxSplits: 1).first.map(String.init) ?? ""
                return Self.secretFields.contains(name)
            }
        }
    }
}

/// Collects the `DecodeReport` while a decoder runs; handed to the models via `decoder.userInfo[.decodeReport]`.
/// Without a box in `userInfo` the models decode just as leniently, the report is simply dropped.
public final class DecodeReportBox: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    public init() {}

    public var report: DecodeReport { lock.withLock { DecodeReport(ignored: entries) } }

    public func note(_ path: [CodingKey]) {
        let text = Self.format(path)
        lock.withLock { entries.append(text) }
    }

    /// The box in `decoder.userInfo`, or a throwaway one.
    public static func of(_ decoder: Decoder) -> DecodeReportBox {
        decoder.userInfo[.decodeReport] as? DecodeReportBox ?? DecodeReportBox()
    }

    /// `[profiles, Index 1, appearance, accent]` → `profiles[1].appearance.accent`.
    static func format(_ path: [CodingKey]) -> String {
        var out = ""
        for key in path {
            if let i = key.intValue, key.stringValue == "Index \(i)" {
                out += "[\(i)]"
            } else {
                out += (out.isEmpty ? "" : ".") + key.stringValue
            }
        }
        return out
    }
}

extension CodingUserInfoKey {
    /// Slot for the `DecodeReportBox`.
    public static let decodeReport = CodingUserInfoKey(rawValue: "PlayerCore.decodeReport")!
}

extension KeyedDecodingContainer {
    /// Missing key or `null` → `default` (silently, that is the normal case for older data). A present but unreadable
    /// value → `default`, and the path goes into the report. Never throws.
    func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key, default fallback: T, report: DecodeReportBox) -> T {
        guard contains(key) else { return fallback }
        if (try? decodeNil(forKey: key)) == true { return fallback }
        do {
            return try decode(T.self, forKey: key)
        } catch {
            report.note(codingPath + [key])
            return fallback
        }
    }
}

extension KeyedDecodingContainer {
    /// A list read element by element: an unreadable element is dropped (path in the report), the rest stays.
    /// Missing key, `null` or no list at all → `[]` (the latter reported). Never throws.
    func decodeLenientList<T: Decodable>(_ type: T.Type, forKey key: Key, report: DecodeReportBox) -> [T] {
        decodeLenient([FailableDecodable<T>].self, forKey: key, default: [], report: report).compactMap(\.value)
    }

    /// A string-keyed map read entry by entry: an unreadable entry is dropped (path `key.entry` in the report).
    func decodeLenientMap<T: Decodable>(_ type: T.Type, forKey key: Key, report: DecodeReportBox) -> [String: T] {
        decodeLenient([String: FailableDecodable<T>].self, forKey: key, default: [:], report: report)
            .compactMapValues(\.value)
    }

    /// A list read element by element where unreadable elements are kept as raw JSON (to be written back).
    func decodeSalvagedList<T: Decodable>(_ type: T.Type, forKey key: Key,
                                          report: DecodeReportBox) -> (values: [T], raw: [JSONValue]) {
        Salvaged.split(decodeLenient([Salvaged<T>].self, forKey: key, default: [], report: report))
    }
}

extension KeyedDecodingContainer {
    /// A string-keyed map read entry by entry where unreadable entries are kept as raw JSON (to be written back).
    func decodeSalvagedMap<T: Decodable>(_ type: T.Type, forKey key: Key,
                                         report: DecodeReportBox) -> (values: [String: T], raw: [String: JSONValue]) {
        var values: [String: T] = [:], raw: [String: JSONValue] = [:]
        for (k, item) in decodeLenient([String: Salvaged<T>].self, forKey: key, default: [:], report: report) {
            switch item {
            case .value(let v): values[k] = v
            case .raw(let j): raw[k] = j
            }
        }
        return (values, raw)
    }
}

// MARK: - Phase 0a.1: whole objects this build cannot read

// A whole stored object (the start page `home`, `appearance`, `look`, a device setting …) that this build cannot
// read used to fall back to its default, and the next save wrote the default over the user's data. Now its raw JSON
// is kept in a `keptUnreadable` map of the owning type (keyed by the field's coding key) and written back:
// - while the working value is still the stand-in from reading (`untouched`), the raw value goes back under its own
//   key, so the file keeps exactly what the newer build wrote;
// - once the user changed the working value, that value is written under the key and the raw value moves to the
//   sibling key `keptUnreadable` (`{"home": <raw>}`), so neither is lost and each has one fixed place.
// Reading takes a raw value from either place; the value under the key itself wins over an older copy set aside.

extension KeyedDecodingContainer {
    /// `decodeLenient` for an object or list holding user work: a present but unreadable value also goes raw into
    /// `kept[key]` (to be written back by `encodeKeeping`). Missing key or `null` → `default`, nothing kept.
    func decodeKeeping<T: Decodable>(_ type: T.Type, forKey key: Key, default fallback: T, report: DecodeReportBox,
                                     kept: inout [String: JSONValue]) -> T {
        guard contains(key) else { return fallback }
        if (try? decodeNil(forKey: key)) == true { return fallback }
        do {
            return try decode(T.self, forKey: key)
        } catch {
            report.note(codingPath + [key])
            if let raw = try? decode(JSONValue.self, forKey: key) { kept[key.stringValue] = raw }
            return fallback
        }
    }

    /// Adds the raw values set aside under `key` (see above) to `kept`; call it after the fields. Each one is still
    /// unread, so its field's path goes into the report. A copy whose field was unreadable in place as well is the
    /// older one: the value in place wins, the older copy is reported under `key` and dropped.
    func decodeKeptUnreadable(forKey key: Key, into kept: inout [String: JSONValue], report: DecodeReportBox) {
        let aside = decodeLenient([String: JSONValue].self, forKey: key, default: [:], report: report)
        for (name, raw) in aside {
            var path = codingPath
            if kept[name] == nil {
                kept[name] = raw
            } else {
                path.append(key)
            }
            path.append(SalvageKey(name))
            report.note(path)
        }
    }
}

extension KeyedEncodingContainer {
    /// Writes `value`, or, while it is `untouched` (still the stand-in from reading), the raw value kept for `key`,
    /// which is then taken out of `aside`.
    mutating func encodeKeeping<T: Encodable>(_ value: T, untouched: Bool, keeping aside: inout [String: JSONValue],
                                              forKey key: Key) throws {
        if untouched, let raw = aside.removeValue(forKey: key.stringValue) {
            try encode(raw, forKey: key)
        } else {
            try encode(value, forKey: key)
        }
    }

    /// The raw values left after the fields (their working value was changed, or this build does not know the key)
    /// go under `key`. Nothing is written when none are left, so the format stays as before.
    mutating func encodeKeptUnreadable(_ aside: [String: JSONValue], forKey key: Key) throws {
        guard !aside.isEmpty else { return }
        try encode(aside, forKey: key)
    }
}

/// Free-form key for maps written entry by entry.
struct SalvageKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedEncodingContainer {
    /// A list followed by the raw leftovers read with it (`decodeSalvagedList`).
    mutating func encodeSalvaged<T: Encodable>(_ values: [T], raw: [JSONValue], forKey key: Key) throws {
        var list = nestedUnkeyedContainer(forKey: key)
        for v in values { try list.encode(v) }
        for r in raw { try list.encode(r) }
    }

    /// A map plus the raw leftovers read with it (`decodeSalvagedMap`); a readable entry replaces a leftover of the
    /// same key. Without leftovers the map is encoded as before.
    mutating func encodeSalvaged<T: Encodable>(_ values: [String: T], raw: [String: JSONValue], forKey key: Key) throws {
        guard !raw.isEmpty else { return try encode(values, forKey: key) }
        var map = nestedContainer(keyedBy: SalvageKey.self, forKey: key)
        for (k, v) in values { try map.encode(v, forKey: SalvageKey(k)) }
        for (k, r) in raw where values[k] == nil { try map.encode(r, forKey: SalvageKey(k)) }
    }
}

/// One element of a list that may be unreadable: the value, or nil (path noted in the report).
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
        } catch {
            DecodeReportBox.of(decoder).note(decoder.codingPath)
            value = nil
        }
    }
}

/// One element of a list that may come from a newer build: the value, or its raw JSON to write back unchanged.
enum Salvaged<T: Decodable>: Decodable {
    case value(T)
    case raw(JSONValue)

    init(from decoder: Decoder) throws {
        do {
            self = .value(try T(from: decoder))
        } catch {
            self = .raw(try JSONValue(from: decoder))
            DecodeReportBox.of(decoder).note(decoder.codingPath)
        }
    }

    /// Splits a list into readable values and raw leftovers (each in its original order).
    static func split(_ items: [Salvaged<T>]) -> (values: [T], raw: [JSONValue]) {
        var values: [T] = [], raw: [JSONValue] = []
        for item in items {
            switch item {
            case .value(let v): values.append(v)
            case .raw(let j): raw.append(j)
            }
        }
        return (values, raw)
    }
}

/// Any JSON value, kept as read so it can be written back with the same content. Integers stay integers
/// (`Int64`/`UInt64`), other numbers are `Double`. Key order inside objects is not kept (JSON objects are unordered;
/// the export sorts keys anyway).
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let u = try? c.decode(UInt64.self) { self = .uint(u) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .uint(let u): try c.encode(u)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONDecoder {
    /// Decodes with a fresh `DecodeReportBox` in `userInfo` and returns what was left out.
    public func decodeReporting<T: Decodable>(_ type: T.Type, from data: Data) throws -> (value: T, report: DecodeReport) {
        let box = DecodeReportBox()
        userInfo[.decodeReport] = box
        defer { userInfo[.decodeReport] = nil }
        let value = try decode(T.self, from: data)
        return (value, box.report)
    }
}
