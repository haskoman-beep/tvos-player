import Foundation

/// Task 1.2: what decoding left out. Each entry is a path such as `profiles[1].appearance.accent`; the value there
/// was unreadable (unknown enum value from a newer build, wrong type, broken element) and the default took its place,
/// or the element was skipped or kept aside unread (`HomeLayout.unknownRows`, `Folder.unknownSources`).
public struct DecodeReport: Sendable, Equatable {
    public var ignored: [String]
    public init(ignored: [String] = []) { self.ignored = ignored }
    public var isEmpty: Bool { ignored.isEmpty }
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
