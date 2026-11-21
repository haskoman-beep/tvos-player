import Foundation

/// Schlüssel-Wert-Ablage für kleine Blöcke (in der App: UserDefaults). Tests nutzen `MemoryKeyValueBlobs`.
public protocol KeyValueBlobs: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
    func remove(forKey key: String)
    /// Alle Schlüssel mit diesem Präfix (für Migration und Größenrechnung).
    func keys(withPrefix prefix: String) -> [String]
}

/// Absturzschutz für tvOS: Die UserDefaults-Domäne darf insgesamt nicht über ~1 MB wachsen
/// (sonst SIGABRT beim Start). Kleine Blöcke bleiben dort (dauerhaft), große gehen nur in Dateien.
///
/// Regeln:
/// - Jeder Schreibvorgang landet als Datei im ersten beschreibbaren Ordner (`directories`, z. B.
///   Application Support vor Caches); Kopien in den anderen Ordnern werden entfernt.
/// - Zusätzlich in UserDefaults nur, wenn der komprimierte Block unter `limit(name)` bleibt und die Summe
///   aller Blöcke dort `budget` nicht überschreitet; sonst wird der Defaults-Eintrag gelöscht.
/// - Lesen: Defaults-Eintrag zuerst (jeder Schreibvorgang hält ihn aktuell oder löscht ihn), sonst die erste Datei.
public struct TieredBlobStorage: BlobStorage {
    public static let prefix = "blob."
    /// Normale Blöcke: höchstens 16 KB komprimiert in UserDefaults.
    public static let smallLimit = 16 * 1024
    /// Profile (Einstellungen, Schlüssel) sind wichtig genug für mehr Platz – Caches darf tvOS leeren.
    public static let profileLimit = 128 * 1024
    /// Summe aller Blöcke in UserDefaults – weit unter der ~1-MB-Grenze von tvOS.
    public static let budget = 256 * 1024

    public let defaults: KeyValueBlobs
    public let directories: [FileBlobStorage]
    let compress: @Sendable (Data) -> Data?
    let decompress: @Sendable (Data) -> Data?

    public init(defaults: KeyValueBlobs, directories: [FileBlobStorage],
                compress: @escaping @Sendable (Data) -> Data? = { $0 },
                decompress: @escaping @Sendable (Data) -> Data? = { $0 }) {
        self.defaults = defaults; self.directories = directories
        self.compress = compress; self.decompress = decompress
    }

    /// Höchstgröße (komprimiert) eines Blocks in UserDefaults; 0 = nur Datei.
    public static func limit(_ name: String) -> Int {
        if name.hasSuffix(".bak") { return 0 }
        if name == "profiles.json" { return profileLimit }
        return smallLimit
    }

    func key(_ name: String) -> String { Self.prefix + name }

    public func read(_ name: String) -> Data? {
        if let z = defaults.data(forKey: key(name)), let d = decompress(z) { return d }
        for dir in directories { if let d = dir.read(name) { return d } }
        return nil
    }

    public func write(_ name: String, _ data: Data) throws {
        let fileOK = writeFile(name, data)
        let z = compress(data)
        if let z, fitsDefaults(name, bytes: z.count) {
            defaults.set(z, forKey: key(name))
            return
        }
        guard fileOK else { throw StorageFull(bytes: z?.count ?? data.count) }
        defaults.remove(forKey: key(name))
    }

    public func remove(_ name: String) {
        defaults.remove(forKey: key(name))
        for dir in directories { dir.remove(name) }
    }

    /// In den ersten Ordner schreiben, der es annimmt; ältere Kopien anderswo löschen.
    @discardableResult
    func writeFile(_ name: String, _ data: Data) -> Bool {
        for (i, dir) in directories.enumerated() {
            guard (try? dir.write(name, data)) != nil else { continue }
            for (j, other) in directories.enumerated() where j != i { other.remove(name) }
            return true
        }
        return false
    }

    func fitsDefaults(_ name: String, bytes: Int) -> Bool {
        guard bytes <= Self.limit(name) else { return false }
        let others = defaults.keys(withPrefix: Self.prefix).filter { $0 != key(name) }
            .reduce(0) { $0 + (defaults.data(forKey: $1)?.count ?? 0) }
        return others + bytes <= Self.budget
    }

    /// Bytes aller Blöcke in UserDefaults, je Name.
    public func defaultsSizes() -> [String: Int] {
        var out: [String: Int] = [:]
        for k in defaults.keys(withPrefix: Self.prefix) { out[String(k.dropFirst(Self.prefix.count))] = defaults.data(forKey: k)?.count ?? 0 }
        return out
    }

    public struct Migration: Equatable, Sendable {
        public var moved: [String] = []
        public var kept: [String] = []
        /// Ließ sich nicht verschieben (keine Datei schreibbar) – bleibt vorerst in UserDefaults.
        public var failed: [String] = []
    }

    /// Einmalig beim Start: zu große oder überzählige Blöcke aus UserDefaults in Dateien verschieben
    /// (lesen → Datei → Gegenprobe → aus Defaults löschen). Profile haben Vorrang, sonst kleinste zuerst.
    @discardableResult
    public func migrate() -> Migration {
        var m = Migration()
        let sizes = defaultsSizes()
        let order = sizes.keys.sorted { a, b in
            let pa = a == "profiles.json", pb = b == "profiles.json"
            if pa != pb { return pa }
            return sizes[a]! != sizes[b]! ? sizes[a]! < sizes[b]! : a < b
        }
        var total = 0
        for name in order {
            let bytes = sizes[name]!
            if bytes <= Self.limit(name), total + bytes <= Self.budget {
                total += bytes; m.kept.append(name); continue
            }
            let z = defaults.data(forKey: key(name)) ?? Data()
            // Nicht entpackbar: Rohdaten beiseitelegen statt verwerfen.
            let (fileName, payload) = decompress(z).map { (name, $0) } ?? (name + ".defaults-raw", z)
            if writeFile(fileName, payload), directories.contains(where: { $0.read(fileName) == payload }) {
                defaults.remove(forKey: key(name)); m.moved.append(name)
            } else {
                m.failed.append(name)
            }
        }
        return m
    }

    public struct StorageFull: Error, CustomStringConvertible {
        public let bytes: Int
        public var description: String { "Daten zu groß für den Apple-TV-Speicher (\(bytes / 1000) KB) und keine Datei schreibbar" }
    }
}

/// Ordner, in den sich wirklich atomar schreiben lässt (tvOS verweigert Application Support teils mit Code 513).
public extension FileBlobStorage {
    var isWritable: Bool {
        let probe = ".probe-" + UUID().uuidString
        guard (try? write(probe, Data("ok".utf8))) != nil else { return false }
        let ok = read(probe) == Data("ok".utf8)
        remove(probe)
        return ok
    }
}

/// UserDefaults-Ersatz im Speicher (Tests, Vorschau).
public final class MemoryKeyValueBlobs: KeyValueBlobs, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    public init(_ values: [String: Data] = [:]) { self.values = values }
    public func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    public func set(_ data: Data, forKey key: String) { lock.withLock { values[key] = data } }
    public func remove(forKey key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    public func keys(withPrefix prefix: String) -> [String] { lock.withLock { values.keys.filter { $0.hasPrefix(prefix) } } }
}
