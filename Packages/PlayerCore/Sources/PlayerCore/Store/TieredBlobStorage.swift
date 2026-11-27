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
///   Application Support und Caches); beim Lesen gewinnt die jüngste Kopie (Phase 0a.1: by sequence number, below).
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
/// - Phase 0a.1: which copy is current no longer depends on the clock. Every write of a blob gets a sequence number
///   one above the highest one known for it. Each folder keeps a sidecar file `<name>.seq`, UserDefaults a record
///   `seq.<key>`; both hold stamps "sequence number + fingerprint (length, FNV-1a) of the payload". Sidecar/record are
///   written BEFORE the payload, with the stamp of the payload being replaced as a second entry, so an interrupted
///   write still ranks the old payload correctly. Rules (`rank`, `beats`):
///   1. A copy (file or UserDefaults entry) whose fingerprint matches any stamp of the blob anywhere ranks as the
///      highest such stamp (verified). Equal bytes are the same state, wherever the stamp lies.
///   2. A copy that matches no stamp but lies next to a sidecar/record was written by someone who did not stamp it
///      (an older build after a downgrade, or the record write was lost): it ranks one above its own stamps.
///   3. A copy without any stamp is a legacy copy: rank 0.
///   4. The highest rank wins. On equal rank between verified copies the UserDefaults entry wins, then the folder
///      order. On equal rank with an unverified copy involved the dates decide (UserDefaults: `rev.<key>`, file:
///      modification date; equal dates → same order): for rank 0 this is exactly the Phase 0a rule.
///   Phase 0a's date revision `rev.<key>` is still written (older builds read it) but only rule 4 uses it.
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
    /// Phase 0a.1: kept for older builds and as the tie-break of rule 4 only.
    func revisionKey(_ name: String) -> String { "rev." + storeKey(name) }

    func revision(_ name: String) -> Date? {
        guard let d = defaults.data(forKey: revisionKey(name)), d.count == 8 else { return nil }
        let bits = d.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
    }

    func setRevision(_ name: String, _ date: Date) {
        withUnsafeBytes(of: date.timeIntervalSinceReferenceDate.bitPattern) { defaults.set(Data($0), forKey: revisionKey(name)) }
    }

    /// Removes the UserDefaults copy together with its revision. Phase 0a.1: the sequence record stays (it keeps the
    /// highest sequence number known and still vouches for file copies with the same bytes).
    func dropDefaults(_ name: String) {
        defaults.remove(forKey: storeKey(name))
        defaults.remove(forKey: revisionKey(name))
    }

    // MARK: Phase 0a.1: sequence numbers instead of dates

    /// Suffix of the sidecar file next to each payload file (`progress-x.json.seq`). It does not end in `.json` or
    /// `.bak`, so `ProfileBlocks.belongs` never takes it for a profile block.
    public static let sidecarSuffix = ".seq"
    /// Prefix of the sequence record in UserDefaults (`seq.blob.<name>`, `seq.profilegen.1`): no `blob.` prefix, so
    /// `migrate()`, `defaultsSizes()` and the budget never see it. 25 or 49 bytes per blob.
    public static let sequencePrefix = "seq."
    static func sidecarName(_ name: String) -> String { name + sidecarSuffix }
    func sequenceKey(_ name: String) -> String { Self.sequencePrefix + storeKey(name) }

    /// Length plus 64-bit FNV-1a of a payload. Not cryptographic: it only tells whether the bytes next to a stamp are
    /// the ones the stamp was written for.
    struct Fingerprint: Equatable, Sendable {
        let count: UInt64
        let hash: UInt64
    }

    /// "The payload with this fingerprint is the state with sequence number `seq`."
    struct Stamp: Equatable, Sendable {
        let seq: UInt64
        let print: Fingerprint
    }

    static func fingerprint(_ data: Data) -> Fingerprint {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for b in raw { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        }
        return Fingerprint(count: UInt64(data.count), hash: h)
    }

    static let stampFormat: UInt8 = 1

    /// Format byte, then 24 bytes per stamp (seq, length, hash; little endian). First stamp = the write it belongs to.
    static func encodeStamps(_ stamps: [Stamp]) -> Data {
        var out: [UInt8] = [stampFormat]
        for s in stamps {
            for v in [s.seq, s.print.count, s.print.hash] {
                for i in 0..<8 { out.append(UInt8(truncatingIfNeeded: v >> UInt64(8 * i))) }
            }
        }
        return Data(out)
    }

    /// nil for a missing or unreadable sidecar/record (treated as absent).
    static func decodeStamps(_ data: Data?) -> [Stamp]? {
        guard let data else { return nil }
        let b = [UInt8](data)
        guard b.count >= 25, (b.count - 1) % 24 == 0, b[0] == stampFormat else { return nil }
        func word(_ at: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(b[at + i]) << UInt64(8 * i) }
            return v
        }
        return stride(from: 1, to: b.count, by: 24).map { o in
            Stamp(seq: word(o), print: Fingerprint(count: word(o + 8), hash: word(o + 16)))
        }
    }

    static func next(_ seq: UInt64) -> UInt64 { seq == .max ? seq : seq + 1 }

    /// One readable copy of a blob, ranked.
    struct Candidate {
        enum Place: Equatable { case defaults, folder(Int) }
        let place: Place
        let data: Data
        /// `seq` = rank (rules 1–3), `print` = fingerprint of `data`.
        let stamp: Stamp
        /// Rule 1 with a rank above 0.
        let verified: Bool
        /// UserDefaults: `rev.<key>`; file: modification date; `.distantPast` when missing.
        let date: Date
    }

    /// Everything stored for one blob name, ranked.
    struct Snapshot {
        /// UserDefaults copy first (if decodable), then the folders in order.
        var candidates: [Candidate] = []
        /// Highest sequence number known for the name (stamps and ranks); the next write gets one more.
        var highest: UInt64 = 0
        /// Any sidecar or record exists (the name is no longer pure legacy).
        var hasStamps = false
        var winner: Candidate? { TieredBlobStorage.best(candidates) }
        var bestFile: Candidate? { TieredBlobStorage.best(candidates.filter { $0.place != .defaults }) }
        var defaultsCopy: Candidate? { candidates.first { $0.place == .defaults } }
    }

    /// Rule 4: `a` is strictly better than `b` (on a full tie the earlier one, UserDefaults then folder order, stays).
    static func beats(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.stamp.seq != b.stamp.seq { return a.stamp.seq > b.stamp.seq }
        if !(a.verified && b.verified), a.date != b.date { return a.date > b.date }
        return false
    }

    static func best(_ candidates: [Candidate]) -> Candidate? {
        var top: Candidate?
        for c in candidates {
            if let t = top { if beats(c, t) { top = c } } else { top = c }
        }
        return top
    }

    /// Rules 1–3 for one copy. `own` = the sidecar next to it (record for the UserDefaults copy), `known` = all stamps.
    func rank(_ data: Data, own: [Stamp]?, known: [Stamp], place: Candidate.Place, date: Date) -> Candidate {
        let p = Self.fingerprint(data)
        let seq: UInt64
        let verified: Bool
        if let s = known.filter({ $0.print == p }).map(\.seq).max() {
            seq = s; verified = s > 0
        } else if let top = own?.map(\.seq).max() {
            seq = Self.next(top); verified = false
        } else {
            seq = 0; verified = false
        }
        return Candidate(place: place, data: data, stamp: Stamp(seq: seq, print: p), verified: verified, date: date)
    }

    /// Reads every copy, sidecar and the record of `name` (all `directories`, also one that is not writable now).
    func evaluate(_ name: String) -> Snapshot {
        let record = Self.decodeStamps(defaults.data(forKey: sequenceKey(name)))
        let payloads = directories.map { $0.read(name) }
        let sidecars = directories.map { Self.decodeStamps($0.read(Self.sidecarName(name))) }
        let known = (record ?? []) + sidecars.compactMap { $0 }.flatMap { $0 }
        var snap = Snapshot()
        snap.hasStamps = !known.isEmpty
        if let z = defaults.data(forKey: storeKey(name)), let d = decompress(z) {
            snap.candidates.append(rank(d, own: record, known: known, place: .defaults, date: revision(name) ?? .distantPast))
        }
        for (i, dir) in directories.enumerated() {
            guard let d = payloads[i] else { continue }
            snap.candidates.append(rank(d, own: sidecars[i], known: known, place: .folder(i),
                                        date: dir.modificationDate(name) ?? .distantPast))
        }
        snap.highest = max(known.map(\.seq).max() ?? 0, snap.candidates.map(\.stamp.seq).max() ?? 0)
        return snap
    }

    /// The UserDefaults copy, but only while it is the winning copy (Phase 0a.1 rules). A UserDefaults write can pass
    /// the read-back check and still never reach the disk (app killed, cfprefsd refusing); the entry found at the next
    /// start then carries an older sequence number than the files.
    func currentDefaults(_ name: String) -> Data? {
        guard let w = evaluate(name).winner, w.place == .defaults else { return nil }
        return w.data
    }

    public func read(_ name: String) -> Data? {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
        return evaluate(name).winner?.data
    }

    /// Diagnosis for the device log: blocks whose UserDefaults copy a newer file has overtaken AND that differ from
    /// that file (a lost UserDefaults write). Call before `migrate()`, which removes such entries.
    /// Review of Phase 0a: set once the entries written by older builds (no revision) were taken over.
    public static let adoptedKey = "rev.adopted"

    /// First start after the update from a build without revisions: until then the UserDefaults copy always won. Such
    /// entries are taken over once as the current state (an old file in Application Support must not win over them).
    /// After that, an entry without a revision gives way to a file. Called by `migrate()` and `overtakenDefaults()`.
    ///
    /// Phase 0a.1: taking over = a sequence record with number 1 for the entry's bytes (above every legacy file, rank
    /// 0), no longer a date from the clock. Only names without any stamp are touched (pure legacy); a name this build
    /// wrote already is decided by its sequence numbers. That makes it repeatable: an interrupted run leaves names with
    /// a record (skipped next time) and names without (taken over next time); a second run or a lost flag finds no
    /// pure-legacy entry left that this build had seen. The flag is written last. The date revision is still set for
    /// older builds (a downgrade then keeps the entry too).
    func adoptLegacyDefaults() {
        guard defaults.data(forKey: Self.adoptedKey) == nil else { return }
        let names = defaults.keys(withPrefix: Self.prefix).map { String($0.dropFirst(Self.prefix.count)) }
            + Self.generationKeys.keys
        for n in names where revision(n) == nil {
            guard let z = defaults.data(forKey: storeKey(n)), let d = decompress(z), !evaluate(n).hasStamps else { continue }
            defaults.set(Self.encodeStamps([Stamp(seq: 1, print: Self.fingerprint(d))]), forKey: sequenceKey(n))
            setRevision(n, max(Date(), (newestFileDate(n) ?? .distantPast).addingTimeInterval(0.001)))
        }
        defaults.set(Data([1]), forKey: Self.adoptedKey)
    }

    public func overtakenDefaults() -> [String] {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
        adoptLegacyDefaults()
        let names = defaults.keys(withPrefix: Self.prefix).map { String($0.dropFirst(Self.prefix.count)) }
            + Self.generationKeys.keys
        return names.filter { n in
            let s = evaluate(n)
            guard let copy = s.defaultsCopy, let w = s.winner, w.place != .defaults else { return false }
            return s.bestFile?.data != copy.data
        }.sorted()
    }

    /// Phase 0b: writes come from the save queue's thread and from the main thread. Phase 0a.1: one lock for the whole
    /// process around read, write, remove and migrate. A write evaluates the stamps, takes the next sequence number
    /// and writes sidecars, files and UserDefaults in one step: two interleaved writes of one name could otherwise
    /// both take the same number, or write payload and sidecar crosswise (the older data would then rank as foreign,
    /// i.e. newer). It also keeps budget check and set together (two blocks passing the check at once). Never held
    /// while calling back into public API (not recursive).
    private static let storeLock = NSLock()

    public func write(_ name: String, _ data: Data) throws {
        let z = compress(data)
        let k = storeKey(name)
        Self.storeLock.lock()
        let snap = evaluate(name)
        let stamp = Stamp(seq: Self.next(snap.highest), print: Self.fingerprint(data))
        let fileOK = writeFiles(name, data, stamp: stamp, snapshot: snap)
        var kept = false
        if let z, fitsDefaults(name, bytes: z.count) {
            // Record first, copy second: if the copy never lands, the old copy still matches the record's second stamp.
            let old = snap.defaultsCopy.map { [$0.stamp] } ?? []
            defaults.set(Self.encodeStamps([stamp] + old), forKey: sequenceKey(name))
            defaults.set(z, forKey: k)
            if defaults.data(forKey: k) == z {
                // Date revision only for older builds (and rule 4): no file took this write, the copy must still rank
                // above every older file there.
                let newest = newestFileDate(name)
                setRevision(name, fileOK ? newest ?? Date() : max(Date(), (newest ?? .distantPast).addingTimeInterval(0.001)))
                kept = true
            } else {
                dropDefaults(name)   // Schreiben nicht angekommen: nur Datei gilt
            }
        } else {
            dropDefaults(name)
            // The record also vouches for the file copies (a sidecar tvOS removed from Caches, a folder that missed it).
            defaults.set(Self.encodeStamps([stamp]), forKey: sequenceKey(name))
        }
        if Self.profileFamily.contains(name) { trimProfileFamily() }
        Self.storeLock.unlock()
        if kept { return }
        if name == Self.profileName { onProfilesFileOnly?(z?.count ?? data.count) }
        // Only when a file really holds it (otherwise nothing was saved and StorageFull follows).
        if fileOK, Self.isProgress(name) { onProgressFileOnly?(name) }
        guard fileOK else { throw StorageFull(bytes: data.count) }
    }

    public func remove(_ name: String) {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
        dropDefaults(name)
        // Payloads before their sidecars: an interrupted remove leaves stamped copies or stamps without copies, never
        // an unstamped (legacy) copy of a blob that has stamps elsewhere.
        for dir in directories { dir.remove(name) }
        for dir in directories { dir.remove(Self.sidecarName(name)) }
        defaults.remove(forKey: sequenceKey(name))
    }

    /// Phase 0a.1: into every folder that takes it, sidecar first (new stamp plus the stamp of the payload it
    /// replaces), payload second. A folder whose sidecar cannot be written gets no payload either (it keeps its old,
    /// correctly ranked state). True when at least one folder holds the payload.
    func writeFiles(_ name: String, _ data: Data, stamp: Stamp, snapshot: Snapshot) -> Bool {
        var ok = false
        for dir in writeDirectories {
            var stamps = [stamp]
            if let i = directories.firstIndex(where: { $0.directory == dir.directory }),
               let old = snapshot.candidates.first(where: { $0.place == .folder(i) }) {
                stamps.append(old.stamp)
            }
            guard (try? dir.write(Self.sidecarName(name), Self.encodeStamps(stamps))) != nil else { continue }
            if (try? dir.write(name, data)) != nil { ok = true }
        }
        return ok
    }

    /// In jeden Ordner schreiben, der es annimmt (Caches als zweite Kopie); true, wenn mindestens einer klappte.
    /// Phase 0a.1: with the next sequence number (for `migrate()` and `trimProfileFamily()`; the caller holds the lock).
    @discardableResult
    func writeFile(_ name: String, _ data: Data) -> Bool {
        let snap = evaluate(name)
        let stamp = Stamp(seq: Self.next(snap.highest), print: Self.fingerprint(data))
        let ok = writeFiles(name, data, stamp: stamp, snapshot: snap)
        let old = snap.defaultsCopy.map { [$0.stamp] } ?? []
        defaults.set(Self.encodeStamps([stamp] + old), forKey: sequenceKey(name))
        return ok
    }

    /// Best file copy over all folders (rules 1–4 among the files only).
    func newestFile(_ name: String) -> Data? {
        evaluate(name).bestFile?.data
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
            // Phase 0a.1: a current copy goes to the files unless the best file holds it already (a file with equal
            // bytes but a lower rank than another file would lose once the copy is gone).
            let s = evaluate(n)
            if let w = s.winner, w.place == .defaults, s.bestFile?.data != w.data { writeFile(n, w.data) }
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
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
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
