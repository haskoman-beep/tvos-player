import Foundation

public struct StoredProfiles: Codable, Sendable, Equatable {
    public static let currentSchema = 1
    public var schemaVersion: Int
    public var profiles: [Profile]
    public var activeProfileID: UUID?

    public init(schemaVersion: Int = StoredProfiles.currentSchema, profiles: [Profile], activeProfileID: UUID? = nil) {
        self.schemaVersion = schemaVersion; self.profiles = profiles; self.activeProfileID = activeProfileID
    }

    public static func makeDefault() -> StoredProfiles {
        let p = Profile.makeDefault()
        return StoredProfiles(profiles: [p], activeProfileID: p.id)
    }

    public var active: Profile? { profiles.first { $0.id == activeProfileID } ?? profiles.first }
}

public enum StoreError: Error, Equatable { case newerSchema(Int), empty }

/// Alle Profile in einer JSON-Datei, atomar geschrieben. Kaputte Dateien werden als `.bak` beiseitegelegt.
public final class ProfileStore: @unchecked Sendable {
    public let fileURL: URL
    public var backupURL: URL { fileURL.appendingPathExtension("bak") }

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("profiles.json")
    }

    public func load() -> StoredProfiles {
        guard let data = try? Data(contentsOf: fileURL) else { return .makeDefault() }
        if let s = try? Self.decode(data) { return s }
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        return .makeDefault()
    }

    public func save(_ s: StoredProfiles) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try exportData(s).write(to: fileURL, options: .atomic)
    }

    public func exportData(_ s: StoredProfiles) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(s)
    }

    public func importData(_ data: Data) throws -> StoredProfiles { try Self.decode(data) }

    static func decode(_ data: Data) throws -> StoredProfiles {
        let s = try JSONDecoder().decode(StoredProfiles.self, from: data)
        if s.schemaVersion > StoredProfiles.currentSchema { throw StoreError.newerSchema(s.schemaVersion) }
        if s.profiles.isEmpty { throw StoreError.empty }
        return s
    }
}
