import Foundation
import PlayerCore

/// App-Ablage: kleine Blöcke LZFSE-komprimiert in UserDefaults (dauerhaft, Profile mit festem Vorbehalt),
/// große nur als Datei (Regeln in `TieredBlobStorage`). tvOS bricht die App ab, wenn die UserDefaults-Domäne
/// ~1 MB übersteigt. Dateien: Application Support, falls dort wirklich schreibbar (tvOS verweigert es oft
/// mit Code 513), und immer Caches/Player als zweite Kopie (darf das System bei Platzmangel leeren).
struct DefaultsStorage: BlobStorage {
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
                                   })
        let m = tiered.migrate()
        if !m.moved.isEmpty || !m.failed.isEmpty {
            RemoteLog.info("speicher", "Migration: verschoben \(m.moved) · behalten \(m.kept) · fehlgeschlagen \(m.failed)")
        }
        RemoteLog.info("speicher", Self.summary(tiered: tiered, filesIn: supportOK ? "Application Support + Caches" : "Caches"))
        if tiered.read(TieredBlobStorage.profileName) == nil { RemoteLog.error("speicher", "Profile fehlen – Standard angelegt") }
    }

    func read(_ name: String) -> Data? { tiered.read(name) }
    func write(_ name: String, _ data: Data) throws { try tiered.write(name, data) }
    func remove(_ name: String) { tiered.remove(name) }

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
