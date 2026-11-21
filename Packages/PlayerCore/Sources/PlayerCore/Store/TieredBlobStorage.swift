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
/// - Jeder Schreibvorgang landet als Datei in JEDEM beschreibbaren Ordner (`directories`, z. B.
///   Application Support und Caches); beim Lesen gewinnt die jüngste Kopie (Änderungsdatum).
/// - Profile (`profiles.json`) haben in UserDefaults einen festen Vorbehalt von `profileLimit`:
///   sie passen immer, solange sie darunter bleiben – Caches darf tvOS leeren, Profile dürfen nie nur dort liegen.
/// - Andere Blöcke nur bis `smallLimit` je Block und zusammen höchstens `budget - profileLimit`.
/// - Nach dem Schreiben in UserDefaults wird gegengelesen; weicht der Wert ab, wird der Eintrag gelöscht.
/// - Lesen: Defaults-Eintrag zuerst (jeder Schreibvorgang hält ihn aktuell oder löscht ihn), sonst die jüngste Datei.
public struct TieredBlobStorage: BlobStorage {
    public static let prefix = "blob."
    public static let profileName = "profiles.json"
    /// Normale Blöcke: höchstens 96 KB komprimiert in UserDefaults (sofern das Restbudget reicht).
    public static let smallLimit = 96 * 1024
    /// Fester Vorbehalt für die Profile (Einstellungen, Schlüssel).
    public static let profileLimit = 512 * 1024
    /// Summe aller Blöcke in UserDefaults – unter der ~1-MB-Grenze von tvOS.
    public static let budget = 640 * 1024
    /// Was alle anderen Blöcke zusammen belegen dürfen.
    public static var othersBudget: Int { budget - profileLimit }

    public let defaults: KeyValueBlobs
    /// Gelesen wird immer aus allen Ordnern (auch einem, der gerade nicht beschreibbar ist).
    public let directories: [FileBlobStorage]
    /// Geschrieben wird nur hierhin (Standard: alle `directories`).
    public let writeDirectories: [FileBlobStorage]
    let compress: @Sendable (Data) -> Data?
    let decompress: @Sendable (Data) -> Data?
    /// Meldung, wenn die Profile nur noch als Datei liegen (komprimierte Bytes).
    let onProfilesFileOnly: (@Sendable (Int) -> Void)?

    public init(defaults: KeyValueBlobs, directories: [FileBlobStorage], writeDirectories: [FileBlobStorage]? = nil,
                compress: @escaping @Sendable (Data) -> Data? = { $0 },
                decompress: @escaping @Sendable (Data) -> Data? = { $0 },
                onProfilesFileOnly: (@Sendable (Int) -> Void)? = nil) {
        self.defaults = defaults; self.directories = directories
        self.writeDirectories = writeDirectories ?? directories
        self.compress = compress; self.decompress = decompress
        self.onProfilesFileOnly = onProfilesFileOnly
    }

    /// Höchstgröße (komprimiert) eines Blocks in UserDefaults; 0 = nur Datei.
    public static func limit(_ name: String) -> Int {
        if name.hasSuffix(".bak") { return 0 }
        if name == profileName { return profileLimit }
        return smallLimit
    }

    func key(_ name: String) -> String { Self.prefix + name }

    public func read(_ name: String) -> Data? {
        if let z = defaults.data(forKey: key(name)), let d = decompress(z) { return d }
        return newestFile(name)
    }

    public func write(_ name: String, _ data: Data) throws {
        let fileOK = writeFile(name, data)
        let z = compress(data)
        if let z, fitsDefaults(name, bytes: z.count) {
            defaults.set(z, forKey: key(name))
            if defaults.data(forKey: key(name)) == z { return }
            defaults.remove(forKey: key(name))   // Schreiben nicht angekommen: nur Datei gilt
        } else {
            defaults.remove(forKey: key(name))
        }
        if name == Self.profileName { onProfilesFileOnly?(z?.count ?? data.count) }
        guard fileOK else { throw StorageFull(bytes: data.count) }
    }

    public func remove(_ name: String) {
        defaults.remove(forKey: key(name))
        for dir in directories { dir.remove(name) }
    }

    /// In jeden Ordner schreiben, der es annimmt (Caches als zweite Kopie); true, wenn mindestens einer klappte.
    @discardableResult
    func writeFile(_ name: String, _ data: Data) -> Bool {
        var ok = false
        for dir in writeDirectories where (try? dir.write(name, data)) != nil { ok = true }
        return ok
    }

    /// Jüngste Kopie über alle Ordner (Änderungsdatum); bei Gleichstand der erste Ordner.
    func newestFile(_ name: String) -> Data? {
        var best: (data: Data, date: Date)?
        for dir in directories {
            guard let d = dir.read(name) else { continue }
            let date = (try? FileManager.default.attributesOfItem(atPath: dir.url(name).path)[.modificationDate] as? Date) ?? .distantPast
            if best == nil || date > best!.date { best = (d, date) }
        }
        return best?.data
    }

    func fitsDefaults(_ name: String, bytes: Int) -> Bool {
        guard bytes <= Self.limit(name) else { return false }
        if name == Self.profileName { return true }   // eigener Vorbehalt
        let others = defaults.keys(withPrefix: Self.prefix)
            .filter { $0 != key(name) && $0 != key(Self.profileName) }
            .reduce(0) { $0 + (defaults.data(forKey: $1)?.count ?? 0) }
        return others + bytes <= Self.othersBudget
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
    /// (lesen → Datei → Gegenprobe → aus Defaults löschen). Profile bleiben, solange sie unter ihrem
    /// Vorbehalt liegen; von den übrigen werden die kleinsten zuerst behalten.
    @discardableResult
    public func migrate() -> Migration {
        var m = Migration()
        let sizes = defaultsSizes()
        let order = sizes.keys.sorted { a, b in sizes[a]! != sizes[b]! ? sizes[a]! < sizes[b]! : a < b }
        var others = 0
        for name in order {
            let bytes = sizes[name]!
            if name == Self.profileName, bytes <= Self.profileLimit { m.kept.append(name); continue }
            if name != Self.profileName, bytes <= Self.limit(name), others + bytes <= Self.othersBudget {
                others += bytes; m.kept.append(name); continue
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
        m.kept.sort { ($0 == Self.profileName ? 0 : 1, $0) < ($1 == Self.profileName ? 0 : 1, $1) }
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
    /// Test: Schreibvorgänge kommen nicht an (wie ein verweigerndes cfprefsd).
    public var dropsWrites = false
    public init(_ values: [String: Data] = [:]) { self.values = values }
    public func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    public func set(_ data: Data, forKey key: String) { lock.withLock { if !dropsWrites { values[key] = data } } }
    public func remove(forKey key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    public func keys(withPrefix prefix: String) -> [String] { lock.withLock { values.keys.filter { $0.hasPrefix(prefix) } } }
}
