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
/// - Wave S round 3: the device settings (`device-settings.json`, under 1 KB) get the same treatment with a reserve
///   of `deviceLimit`, outside the shared budget of the other blocks.
/// - Task 1.3: the last two good profile versions (`profiles.json.1`, `.2`) and their dates (`profiles.json.dates`)
///   live under their own keys `profilegen.*` (no `blob.` prefix: `migrate()` and the budget of the other blocks
///   never see them) INSIDE the profile reserve: main block + generations ≤ `profileLimit`, generations together
///   ≤ `generationsLimit`. Priority: main block, then `.1`, then `.2`, then the dates; what does not fit lies only in
///   the files (same file rules as every block).
/// - Andere Blöcke nur bis `smallLimit` je Block und zusammen höchstens `budget - profileLimit - deviceLimit`.
/// - Nach dem Schreiben in UserDefaults wird gegengelesen; weicht der Wert ab, wird der Eintrag gelöscht.
/// - Lesen: Defaults-Eintrag nur, solange keine Datei jünger ist als seine Revision (`rev.<Schlüssel>`), sonst die
///   jüngste Datei. Phase 0a: ein Defaults-Schreibvorgang kann verloren gehen, obwohl das Gegenlesen stimmte.
public struct TieredBlobStorage: BlobStorage {
    public static let prefix = "blob."
    public static let profileName = "profiles.json"
    /// Wave S round 3: device settings (Bild & Ton); reserved like the profiles (`DeviceSettingsStore.name`).
    public static let deviceName = "device-settings.json"
    /// Reserve for the device settings in UserDefaults.
    public static let deviceLimit = 8 * 1024
    /// Blocks with their own reserve: they always fit while under their limit and `migrate()` keeps them.
    public static func isReserved(_ name: String) -> Bool { name == profileName || name == deviceName }
    /// Normale Blöcke: höchstens 96 KB komprimiert in UserDefaults (sofern das Restbudget reicht).
    public static let smallLimit = 96 * 1024
    /// Fester Vorbehalt für die Profile (Einstellungen, Schlüssel).
    public static let profileLimit = 512 * 1024
    /// Summe aller Blöcke in UserDefaults – unter der ~1-MB-Grenze von tvOS.
    public static let budget = 640 * 1024
    /// Was alle anderen Blöcke zusammen belegen dürfen. Task 1.3: minus the device reserve, so that all reserves
    /// together stay within `budget` (before: 512 + 8 + 128 KB = 648 KB in the worst case).
    public static var othersBudget: Int { budget - profileLimit - deviceLimit }
    /// Task 1.3: the profile generations and their dates, each under its own UserDefaults key (no `blob.` prefix).
    public static let generationKeys: [String: String] = [
        profileName + ".1": "profilegen.1", profileName + ".2": "profilegen.2", profileName + ".dates": "profilegen.dates",
    ]
    /// Priority inside the profile reserve (first = keeps its place).
    static let profileFamily = [profileName, profileName + ".1", profileName + ".2", profileName + ".dates"]
    /// Task 1.3: what the generations (with their dates) may take of the profile reserve together.
    public static let generationsLimit = 192 * 1024
    public static func isGeneration(_ name: String) -> Bool { generationKeys[name] != nil }
    /// Blobs with this name prefix are kept as files only, whatever their size (import data that may be large and
    /// that the app can rebuild or do without). They never count against the UserDefaults budget.
    public static let fileOnlyPrefix = "import-"

    public let defaults: KeyValueBlobs
    /// Gelesen wird immer aus allen Ordnern (auch einem, der gerade nicht beschreibbar ist).
    public let directories: [FileBlobStorage]
    /// Geschrieben wird nur hierhin (Standard: alle `directories`).
    public let writeDirectories: [FileBlobStorage]
    let compress: @Sendable (Data) -> Data?
    let decompress: @Sendable (Data) -> Data?
    /// Meldung, wenn die Profile nur noch als Datei liegen (komprimierte Bytes).
    let onProfilesFileOnly: (@Sendable (Int) -> Void)?
    /// Task 2.6 (S-10): a progress block (`progress-<Profil>.json`) no longer fits into UserDefaults (its name).
    let onProgressFileOnly: (@Sendable (String) -> Void)?

    public init(defaults: KeyValueBlobs, directories: [FileBlobStorage], writeDirectories: [FileBlobStorage]? = nil,
                compress: @escaping @Sendable (Data) -> Data? = { $0 },
                decompress: @escaping @Sendable (Data) -> Data? = { $0 },
                onProfilesFileOnly: (@Sendable (Int) -> Void)? = nil,
                onProgressFileOnly: (@Sendable (String) -> Void)? = nil) {
        self.defaults = defaults; self.directories = directories
        self.writeDirectories = writeDirectories ?? directories
        self.compress = compress; self.decompress = decompress
        self.onProfilesFileOnly = onProfilesFileOnly
        self.onProgressFileOnly = onProgressFileOnly
    }

    /// Task 2.6: `progress-<Profil>.json` (not its `.bak`, not `fileprogress-…`).
    public static func isProgress(_ name: String) -> Bool { name.hasPrefix("progress-") && name.hasSuffix(".json") }

    /// Höchstgröße (komprimiert) eines Blocks in UserDefaults; 0 = nur Datei.
    public static func limit(_ name: String) -> Int {
        if name.hasSuffix(".bak") || name.hasPrefix(fileOnlyPrefix) { return 0 }
        if name == profileName { return profileLimit }
        if isGeneration(name) { return generationsLimit }
        if name == deviceName { return deviceLimit }
        return smallLimit
    }

    func key(_ name: String) -> String { Self.prefix + name }
    /// Key in UserDefaults: own key for the generations, `blob.<name>` for everything else.
    func storeKey(_ name: String) -> String { Self.generationKeys[name] ?? key(name) }

    /// Phase 0a: revision of the UserDefaults copy = date of the newest file at the moment that copy was written.
    func revisionKey(_ name: String) -> String { "rev." + storeKey(name) }

    func revision(_ name: String) -> Date? {
        guard let d = defaults.data(forKey: revisionKey(name)), d.count == 8 else { return nil }
        let bits = d.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
    }

    func setRevision(_ name: String, _ date: Date) {
        withUnsafeBytes(of: date.timeIntervalSinceReferenceDate.bitPattern) { defaults.set(Data($0), forKey: revisionKey(name)) }
    }

    /// Removes the UserDefaults copy together with its revision.
    func dropDefaults(_ name: String) {
        defaults.remove(forKey: storeKey(name))
        defaults.remove(forKey: revisionKey(name))
    }

    /// The UserDefaults copy, but only while no file is newer than it. A UserDefaults write can pass the read-back
    /// check and still never reach the disk (app killed, cfprefsd refusing); the entry found at the next start is
    /// then older than the files. An entry without a revision (older app version) proves nothing and gives way too.
    func currentDefaults(_ name: String) -> Data? {
        guard let z = defaults.data(forKey: storeKey(name)), let d = decompress(z) else { return nil }
        guard let fileDate = newestFileDate(name) else { return d }
        guard let rev = revision(name), rev >= fileDate else { return nil }
        return d
    }

    public func read(_ name: String) -> Data? {
        currentDefaults(name) ?? newestFile(name)
    }

    /// Diagnosis for the device log: blocks whose UserDefaults copy a newer file has overtaken AND that differ from
    /// that file (a lost UserDefaults write). Call before `migrate()`, which removes such entries.
    /// Review of Phase 0a: set once the entries written by older builds (no revision) were taken over.
    public static let adoptedKey = "rev.adopted"

    /// First start after the update: until now the UserDefaults copy always won, and no entry has a revision. They
    /// are taken over once as the current state (an old file in Application Support must not win over them). After
    /// that, an entry without a revision gives way to a file. Called by `migrate()` and `overtakenDefaults()`.
    func adoptLegacyDefaults() {
        guard defaults.data(forKey: Self.adoptedKey) == nil else { return }
        let names = defaults.keys(withPrefix: Self.prefix).map { String($0.dropFirst(Self.prefix.count)) }
            + Self.generationKeys.keys
        for n in names where defaults.data(forKey: storeKey(n)) != nil && revision(n) == nil {
            setRevision(n, max(Date(), (newestFileDate(n) ?? .distantPast).addingTimeInterval(0.001)))
        }
        defaults.set(Data([1]), forKey: Self.adoptedKey)
    }

    public func overtakenDefaults() -> [String] {
        adoptLegacyDefaults()
        let names = defaults.keys(withPrefix: Self.prefix).map { String($0.dropFirst(Self.prefix.count)) }
            + Self.generationKeys.keys
        return names.filter { n in
            guard let z = defaults.data(forKey: storeKey(n)), let d = decompress(z) else { return false }
            return currentDefaults(n) == nil && newestFile(n) != d
        }.sorted()
    }

    public func write(_ name: String, _ data: Data) throws {
        let fileOK = writeFile(name, data)
        let z = compress(data)
        let k = storeKey(name)
        let family = Self.profileFamily.contains(name)
        defer { if family { trimProfileFamily() } }
        if let z, fitsDefaults(name, bytes: z.count) {
            defaults.set(z, forKey: k)
            if defaults.data(forKey: k) == z {
                // No file took this write: the copy must still rank above every older file.
                let newest = newestFileDate(name)
                setRevision(name, fileOK ? newest ?? Date() : max(Date(), (newest ?? .distantPast).addingTimeInterval(0.001)))
                return
            }
            dropDefaults(name)   // Schreiben nicht angekommen: nur Datei gilt
        } else {
            dropDefaults(name)
        }
        if name == Self.profileName { onProfilesFileOnly?(z?.count ?? data.count) }
        // Only when a file really holds it (otherwise nothing was saved and StorageFull follows).
        if fileOK, Self.isProgress(name) { onProgressFileOnly?(name) }
        guard fileOK else { throw StorageFull(bytes: data.count) }
    }

    public func remove(_ name: String) {
        dropDefaults(name)
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
            let date = dir.modificationDate(name) ?? .distantPast
            if best == nil || date > best!.date { best = (d, date) }
        }
        return best?.data
    }

    /// Date of the newest file copy over all folders; nil when no folder has the blob.
    func newestFileDate(_ name: String) -> Date? {
        directories.compactMap { $0.modificationDate(name) }.max()
    }

    func fitsDefaults(_ name: String, bytes: Int) -> Bool {
        guard bytes <= Self.limit(name) else { return false }
        if Self.isGeneration(name) { return generationFits(name, bytes: bytes) }
        if Self.isReserved(name) { return true }   // eigener Vorbehalt
        let others = defaults.keys(withPrefix: Self.prefix)
            .filter { $0 != key(name) && !Self.isReserved(String($0.dropFirst(Self.prefix.count))) }
            .reduce(0) { $0 + (defaults.data(forKey: $1)?.count ?? 0) }
        return others + bytes <= Self.othersBudget
    }

    /// Task 1.3: a generation fits when the blocks before it in `profileFamily` leave room for it (the ones after it
    /// give way in `trimProfileFamily`).
    func generationFits(_ name: String, bytes: Int) -> Bool {
        var all = 0, gens = 0
        for n in Self.profileFamily {
            if n == name { break }
            let s = defaults.data(forKey: storeKey(n))?.count ?? 0
            all += s
            if n != Self.profileName { gens += s }
        }
        return all + bytes <= Self.profileLimit && gens + bytes <= Self.generationsLimit
    }

    /// Task 1.3: after every write of the main block or a generation, generations that no longer fit next to the
    /// blocks before them leave UserDefaults (`.2` before `.1`). They stay readable from the files; if no file has
    /// them yet, one is written first.
    func trimProfileFamily() {
        var all = 0, gens = 0
        for n in Self.profileFamily {
            let k = storeKey(n)
            guard let z = defaults.data(forKey: k) else { continue }
            if n == Self.profileName { all += z.count; continue }
            if all + z.count <= Self.profileLimit, gens + z.count <= Self.generationsLimit {
                all += z.count; gens += z.count; continue
            }
            // Phase 0a: a copy that a newer file has overtaken is dropped, never written over that file.
            if let d = currentDefaults(n), !directories.contains(where: { $0.read(n) == d }) { writeFile(n, d) }
            dropDefaults(n)
        }
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
        adoptLegacyDefaults()
        var m = Migration()
        let sizes = defaultsSizes()
        let order = sizes.keys.sorted { a, b in sizes[a]! != sizes[b]! ? sizes[a]! < sizes[b]! : a < b }
        var others = 0
        for name in order {
            let bytes = sizes[name]!
            if Self.isReserved(name), bytes <= Self.limit(name) { m.kept.append(name); continue }
            if !Self.isReserved(name), bytes <= Self.limit(name), others + bytes <= Self.othersBudget {
                others += bytes; m.kept.append(name); continue
            }
            let z = defaults.data(forKey: key(name)) ?? Data()
            // Phase 0a: readable, but a newer file exists: the file stays, only the stale entry goes.
            if decompress(z) != nil, currentDefaults(name) == nil { dropDefaults(name); m.moved.append(name); continue }
            // Nicht entpackbar: Rohdaten beiseitelegen statt verwerfen.
            let (fileName, payload) = decompress(z).map { (name, $0) } ?? (name + ".defaults-raw", z)
            if writeFile(fileName, payload), directories.contains(where: { $0.read(fileName) == payload }) {
                dropDefaults(name); m.moved.append(name)
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

public extension BlobStorage {
    /// One-time moves: writes every blob that is not stored yet and returns the names that could not be written.
    /// A blob that already exists is left alone (it may be newer than the copy being moved). The caller removes
    /// the old copy only if the result is empty.
    func adoptMissing(_ blobs: [(name: String, data: Data)]) -> [String] {
        var failed: [String] = []
        for b in blobs where read(b.name) == nil {
            if (try? write(b.name, b.data)) == nil || read(b.name) != b.data { failed.append(b.name) }
        }
        return failed
    }
}

/// Task 1.3: every copy of a blob (UserDefaults entry first, then each folder) for the recovery list.
extension TieredBlobStorage: BlobCopies {
    public func copies(_ name: String) -> [BlobCopy] {
        var out: [BlobCopy] = []
        if let z = defaults.data(forKey: storeKey(name)), let d = decompress(z) {
            out.append(BlobCopy(source: "UserDefaults", data: d, modified: nil))
        }
        for dir in directories {
            guard let d = dir.read(name) else { continue }
            // App folders are ".../Application Support/Player" and ".../Caches/Player": name the parent.
            let folder = dir.directory.lastPathComponent == "Player" ? dir.directory.deletingLastPathComponent() : dir.directory
            out.append(BlobCopy(source: folder.lastPathComponent, data: d, modified: dir.modificationDate(name)))
        }
        return out
    }
}
