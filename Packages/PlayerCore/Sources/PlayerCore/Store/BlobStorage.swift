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
