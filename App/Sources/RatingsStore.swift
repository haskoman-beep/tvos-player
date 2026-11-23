import Foundation
import PlayerCore

/// MDBList-Bewertungen mit Plattencache (24 h, „nicht gefunden“ 6 h), eine Anfrage je Titel zur Zeit,
/// nach Tageslimit 1 h Pause und alte Werte zeigen.
actor RatingsStore {
    static let shared = RatingsStore()

    private struct Entry: Codable { var storedAt: Date; var ratings: ExternalRatings? }
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<ExternalRatings?, Never>] = [:]
    private var pausedUntil: Date?
    private var loaded = false
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ratings.json")

    func ratings(imdb: String, series: Bool, apiKey: String) async -> ExternalRatings? {
        load()
        let key = "\(series ? "s" : "m"):\(imdb)"
        let old = entries[key]
        if let e = old, MDBList.isFresh(storedAt: e.storedAt, found: e.ratings != nil) { return e.ratings }
        if let p = pausedUntil, p > Date() { return old?.ratings }
        if let t = inFlight[key] { return await t.value }
        let task = Task<ExternalRatings?, Never> { await self.fetch(key: key, imdb: imdb, series: series, apiKey: apiKey, old: old?.ratings) }
        inFlight[key] = task
        let r = await task.value
        inFlight[key] = nil
        return r
    }

    private func fetch(key: String, imdb: String, series: Bool, apiKey: String, old: ExternalRatings?) async -> ExternalRatings? {
        guard let url = MDBList.url(imdb: imdb, series: series, apiKey: apiKey),
              // Task 2.3 exception (direct URLSession, not via HTTPClient in Build 2): small ratings JSON from a fixed public service, no addon address; migrate later.
              let (data, resp) = try? await URLSession.shared.data(from: url) else { return old }
        switch MDBList.parse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data) {
        case .ratings(let r):
            await MainActor.run { RemoteLog.info("bewertung", "\(imdb): \(r.values.keys.sorted().joined(separator: ",")) · Freigabe \(r.certification ?? "-")") }
            entries[key] = Entry(storedAt: Date(), ratings: r); save(); return r
        case .notFound:
            entries[key] = Entry(storedAt: Date(), ratings: nil); save(); return nil
        case .limitReached:
            pausedUntil = Date().addingTimeInterval(3600)
            await MainActor.run { RemoteLog.info("bewertung", "MDBList-Tageslimit erreicht, 1 h Pause") }
            return old
        case .failed:
            await MainActor.run { RemoteLog.error("bewertung", "MDBList-Fehler für \(imdb)") }
            return old
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([String: Entry].self, from: d) { entries = e }
    }

    private func save() {
        if entries.count > 4000 {
            for k in entries.sorted(by: { $0.value.storedAt < $1.value.storedAt }).prefix(entries.count - 4000).map(\.key) { entries[k] = nil }
        }
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: file, options: .atomic) }
    }
}
