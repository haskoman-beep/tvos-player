import Foundation
import PlayerCore

/// tvOS: Application Support/Documents sind nicht dauerhaft beschreibbar (Code 513).
/// Daher UserDefaults (bleibt erhalten, ~1 MB Grenze) mit LZFSE-Kompression,
/// zusätzlich Kopie in Caches (darf das System löschen, hilft aber bei großen Daten).
struct DefaultsStorage: BlobStorage {
    static let limit = 900_000
    let caches = FileBlobStorage(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Player", isDirectory: true))

    func key(_ name: String) -> String { "blob." + name }

    func read(_ name: String) -> Data? {
        if let z = UserDefaults.standard.data(forKey: key(name)),
           let d = try? (z as NSData).decompressed(using: .lzfse) as Data { return d }
        return caches.read(name)
    }

    func write(_ name: String, _ data: Data) throws {
        try? caches.write(name, data)
        let z = try (data as NSData).compressed(using: .lzfse) as Data
        guard z.count < Self.limit else { throw StorageFull(bytes: z.count) }
        UserDefaults.standard.set(z, forKey: key(name))
    }

    func remove(_ name: String) {
        UserDefaults.standard.removeObject(forKey: key(name)); caches.remove(name)
    }

    struct StorageFull: Error, CustomStringConvertible {
        let bytes: Int
        var description: String { "Daten zu groß für den Apple-TV-Speicher (\(bytes / 1000) KB komprimiert)" }
    }
}
