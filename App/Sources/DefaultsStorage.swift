import Foundation
import PlayerCore

/// App-Ablage: kleine Blöcke LZFSE-komprimiert in UserDefaults (dauerhaft, Profile mit festem Vorbehalt),
/// große nur als Datei (Regeln in `TieredBlobStorage`). tvOS bricht die App ab, wenn die UserDefaults-Domäne
/// ~1 MB übersteigt. Dateien: Application Support, falls dort wirklich schreibbar (tvOS verweigert es oft
/// mit Code 513), und immer Caches/Player als zweite Kopie (darf das System bei Platzmangel leeren).
struct DefaultsStorage: BlobStorage, BlobCopies, BlobNames, BlobCandidates {
    let tiered: TieredBlobStorage

    /// Baut die Ablage, verschiebt einmalig zu große Alt-Einträge und loggt die Defaults-Größe.
    @MainActor init() {
        let fm = FileManager.default
        let support = FileBlobStorage(directory: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true))
        let caches = FileBlobStorage(directory: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true))
        let supportOK = support.isWritable
        // Lesen immer aus beiden Ordnern, schreiben nur in die beschreibbaren.
        tiered = TieredBlobStorage(defaults: UserDefaultsBlobs(), directories: [support, caches],
                                   writeDirectories: [support, caches].filter { $0.directory == caches.directory || supportOK },
                                   compress: { try? ($0 as NSData).compressed(using: .lzfse) as Data },
                                   decompress: { try? ($0 as NSData).decompressed(using: .lzfse) as Data },
                                   onProfilesFileOnly: { bytes in
                                       Task { @MainActor in
                                           RemoteLog.error("speicher", "Profile nur als Datei gespeichert (\(DefaultsStorage.kb(bytes)), nicht in UserDefaults)")
                                       }
                                   },
                                   onProgressFileOnly: { name in
                                       // Task 2.6 (S-10): once per app run, visible under System › Diagnose (LogRing).
                                       Task { @MainActor in
                                           guard !DefaultsStorage.progressFileOnlyReported else { return }
                                           DefaultsStorage.progressFileOnlyReported = true
                                           RemoteLog.error("speicher", "Fortschritt nur als Datei gespeichert (\(name), nicht in UserDefaults) · Caches kann tvOS leeren")
                                       }
                                   })
        // Phase 0a: a UserDefaults copy older than its file means a UserDefaults write was lost (the file wins now).
        let overtaken = tiered.overtakenDefaults()
        if !overtaken.isEmpty { RemoteLog.error("speicher", "UserDefaults-Kopie älter als Datei, Datei gilt: \(overtaken)") }
        let m = tiered.migrate()
        if !m.moved.isEmpty || !m.failed.isEmpty {
            RemoteLog.info("speicher", "Migration: verschoben \(m.moved) · behalten \(m.kept) · fehlgeschlagen \(m.failed)")
        }
        RemoteLog.info("speicher", Self.summary(tiered: tiered, filesIn: supportOK ? "Application Support + Caches" : "Caches"))
        if tiered.read(TieredBlobStorage.profileName) == nil { RemoteLog.error("speicher", "Profile fehlen – Standard angelegt") }
    }

    /// Task 2.6: the "Fortschritt nur als Datei" line was already logged in this run.
    @MainActor static var progressFileOnlyReported = false

    func read(_ name: String) -> Data? { tiered.read(name) }
    func write(_ name: String, _ data: Data) throws { try tiered.write(name, data) }
    func remove(_ name: String) { tiered.remove(name) }
    /// Task 1.3: every copy (UserDefaults, Application Support, Caches) for the profile recovery list.
    func copies(_ name: String) -> [BlobCopy] { tiered.copies(name) }
    /// Task 2.4: every block name (UserDefaults and files), for deleting a profile's blocks.
    func blobNames() -> [String] { tiered.blobNames() }
    /// Phase 0a.1: every distinct readable copy, best first; `ProgressStore.load` falls back to the next one when
    /// the best copy is damaged. Without this forward the fallback never runs in the app.
    func rankedPayloads(_ name: String) -> [Data] { tiered.rankedPayloads(name) }

    /// Gesamtgröße der App-Domäne in UserDefaults (binäre Plist wie bei cfprefsd) plus die Blöcke einzeln.
    static func summary(tiered: TieredBlobStorage, filesIn: String) -> String {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        let total = (try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0).count) ?? 0
        let blobs = tiered.defaultsSizes().sorted { $0.value > $1.value }
            .map { "\($0.key) \(kb($0.value))" }.joined(separator: ", ")
        return "Defaults \(kb(total)) (\(domain.count) Schlüssel) · Blöcke: \(blobs.isEmpty ? "keine" : blobs) · Dateien in \(filesIn)"
    }

    static func kb(_ b: Int) -> String { String(format: "%.1f KB", Double(b) / 1024) }
}

/// UserDefaults als Schlüssel-Wert-Ablage für `TieredBlobStorage`.
struct UserDefaultsBlobs: KeyValueBlobs {
    func data(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
    func set(_ data: Data, forKey key: String) { UserDefaults.standard.set(data, forKey: key) }
    func remove(forKey key: String) { UserDefaults.standard.removeObject(forKey: key) }
    func keys(withPrefix prefix: String) -> [String] {
        guard let id = Bundle.main.bundleIdentifier, let d = UserDefaults.standard.persistentDomain(forName: id) else { return [] }
        return d.keys.filter { $0.hasPrefix(prefix) }
    }
}
