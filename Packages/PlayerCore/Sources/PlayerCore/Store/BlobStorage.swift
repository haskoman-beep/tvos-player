import Foundation

/// Ablage für benannte Datenblöcke. tvOS erlaubt kein dauerhaftes Schreiben in Application Support/Documents,
/// daher liefert die App dort eine UserDefaults-Ablage; Tests und Linux nutzen Dateien.
public protocol BlobStorage: Sendable {
    func read(_ name: String) -> Data?
    func write(_ name: String, _ data: Data) throws
    func remove(_ name: String)
}

public struct FileBlobStorage: BlobStorage {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
    public func read(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }
    public func write(_ name: String, _ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(name), options: .atomic)
    }
    public func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }
}

/// Task 1.3: one stored copy of a blob (UserDefaults entry or a file in one folder), for the recovery list.
public struct BlobCopy: Sendable, Equatable {
    /// Where it lies: "UserDefaults" or the folder (e.g. "Caches").
    public let source: String
    public let data: Data
    /// File modification date; nil for a UserDefaults entry.
    public let modified: Date?
    public init(source: String, data: Data, modified: Date?) { self.source = source; self.data = data; self.modified = modified }
}

/// Task 1.3: storages that keep several copies of one blob list them all (`read` returns only the preferred one).
public protocol BlobCopies: Sendable {
    func copies(_ name: String) -> [BlobCopy]
}

extension FileBlobStorage: BlobCopies {
    public func modificationDate(_ name: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(name).path)[.modificationDate]) as? Date
    }
    public func copies(_ name: String) -> [BlobCopy] {
        guard let d = read(name) else { return [] }
        return [BlobCopy(source: directory.lastPathComponent, data: d, modified: modificationDate(name))]
    }
}
