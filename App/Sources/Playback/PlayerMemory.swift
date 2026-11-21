import SwiftUI
import PlayerCore

/// Welle D-a: Spur-Wahl je Serie/Film (`TrackMemoryBook`) und Fortschritt von Dateien ohne IMDb-ID
/// (`FileProgressBook`, TorBox). Je Profil eine Datei in der größenbegrenzten Ablage (`TieredBlobStorage`
/// über DefaultsStorage); beide Bücher kürzen sich selbst (300 bzw. 200 Einträge).
@MainActor
final class PlayerMemory: ObservableObject {
    static let shared = PlayerMemory()

    private var storage: BlobStorage?
    private var tracks: (profile: UUID, book: TrackMemoryBook)?
    private var files: (profile: UUID, book: FileProgressBook)?
    /// Erhöht bei jeder Änderung des Datei-Fortschritts (TorBox-Kacheln zeichnen dann neu).
    @Published private(set) var fileRevision = 0

    func attach(_ storage: BlobStorage) { self.storage = storage }

    // MARK: Spur-Wahl

    func trackMemory(profile: UUID, key: String) -> TrackMemory? {
        trackBook(profile).memory(for: key)
    }

    func remember(_ change: TrackMemoryChange, key: String, profile: UUID) {
        var book = trackBook(profile)
        book.update(key) { $0.apply(change) }
        tracks = (profile, book)
        save(book, name: Self.trackName(profile))
        RemoteLog.info("player", "Spur-Wahl gemerkt für \(key): \(book.memory(for: key)?.logText ?? "-")")
    }

    func clearTrackMemory(profile: UUID) {
        tracks = (profile, TrackMemoryBook())
        storage?.remove(Self.trackName(profile))
        RemoteLog.info("player", "Spur-Gedächtnis gelöscht")
    }

    func trackMemoryCount(profile: UUID) -> Int { trackBook(profile).entries.count }

    private func trackBook(_ profile: UUID) -> TrackMemoryBook {
        if let t = tracks, t.profile == profile { return t.book }
        let book = load(TrackMemoryBook.self, name: Self.trackName(profile)) ?? TrackMemoryBook()
        tracks = (profile, book)
        return book
    }

    // MARK: Datei-Fortschritt

    func fileResume(profile: UUID, key: String) -> Double? { fileBook(profile).resumePosition(for: key) }
    func fileFraction(profile: UUID, key: String) -> Double? { fileBook(profile).fraction(for: key) }
    func fileWatched(profile: UUID, key: String) -> Bool { fileBook(profile).isWatched(key) }

    func recordFile(profile: UUID, key: String, position: Double, duration: Double) {
        // Der Player meldet alle 10 s, bei Pause und beim Verlassen: jedes Mal schreiben (klein, höchstens 200 Einträge).
        var book = fileBook(profile)
        book.record(key, position: position, duration: duration)
        files = (profile, book)
        fileRevision &+= 1
        save(book, name: Self.fileName(profile))
    }

    private func fileBook(_ profile: UUID) -> FileProgressBook {
        if let f = files, f.profile == profile { return f.book }
        let book = load(FileProgressBook.self, name: Self.fileName(profile)) ?? FileProgressBook()
        files = (profile, book)
        return book
    }

    // MARK: Ablage

    static func trackName(_ p: UUID) -> String { "trackmemory-\(p.uuidString).json" }
    static func fileName(_ p: UUID) -> String { "fileprogress-\(p.uuidString).json" }

    private func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let d = storage?.read(name) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: d) } catch {
            RemoteLog.error("speicher", "\(name) nicht lesbar: \(error)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, name: String) {
        guard let storage else { return }
        do { try storage.write(name, JSONEncoder().encode(value)) } catch {
            RemoteLog.error("speicher", "\(name) nicht gespeichert: \(error)")
        }
    }
}
