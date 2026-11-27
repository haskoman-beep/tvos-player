import Foundation
import PlayerCore

/// Build 8: TMDB company searches of studio tiles and TMDB logos of known studios / networks, kept on disk
/// (Caches/Player/Studios, PlayerCore `CompanySearchCache`), so a studio page opens without a search the next time.
@MainActor
final class CompanySearchStore {
    static let shared = CompanySearchStore()

    private let files: FileBlobStorage
    private var cache: CompanySearchCache?
    /// Running searches / logo lookups by key (two opens share one request).
    private var running: [String: Task<CompanySearchCache.Lookup?, Never>] = [:]

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true).appendingPathComponent("Studios", isDirectory: true)
        files = FileBlobStorage(directory: dir)
    }

    private var loaded: CompanySearchCache {
        if let cache { return cache }
        let c = CompanySearchCache.decode(files.read(CompanySearchCache.fileName))
        cache = c
        return c
    }

    func lookup(_ key: String) -> CompanySearchCache.Lookup? { loaded.lookup(key) }

    private func store(_ key: String, _ found: StudioLogo?) {
        var c = loaded
        c.store(key, found)
        cache = c
        if let d = c.encoded() { try? files.write(CompanySearchCache.fileName, d) }
    }

    /// The company of `query` (exact folded name), cached; nil when the search failed (not remembered).
    func search(_ query: String, key: String, tmdb: TMDBClient?) async -> CompanySearchCache.Lookup? {
        if let hit = lookup(key) { return hit }
        guard let tmdb else { return nil }
        if let t = running[key] { return await t.value }
        let t = Task<CompanySearchCache.Lookup?, Never> { @MainActor in
            let started = Date()
            do {
                let found = CompanySearchCache.exactMatch(try await tmdb.searchCompany(query), title: query)
                self.store(key, found)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                RemoteLog.info("genre", "Studio-Suche \(query): " + (found.map { "TMDB \($0.id ?? 0)" } ?? "kein genauer Treffer") + " (\(ms) ms)")
                return found.map { .found($0) } ?? .miss
            } catch {
                RemoteLog.error("genre", "Studio-Suche \(query) fehlgeschlagen: \(error)")
                return nil
            }
        }
        running[key] = t
        let r = await t.value
        running[key] = nil
        return r
    }

    /// TMDB logo of a table studio / network (`/company|network/{id}/images`), cached; nil = none or failed.
    func logo(_ studio: StudioLogo, tmdb: TMDBClient?) async -> String? {
        guard let key = CompanySearchCache.logoKey(studio) else { return nil }
        if let hit = lookup(key) {
            if case .found(let s) = hit { return s.logo }
            return nil
        }
        guard let tmdb else { return nil }
        if let t = running[key] {
            if case .found(let s)? = await t.value { return s.logo }
            return nil
        }
        let t = Task<CompanySearchCache.Lookup?, Never> { @MainActor in
            do {
                let l = try await tmdb.studioLogo(studio)
                self.store(key, l.map { StudioLogo(name: studio.name, logo: $0, id: nil, kind: studio.kind) })
                return l.map { .found(StudioLogo(name: studio.name, logo: $0)) } ?? .miss
            } catch {
                return nil   // failed: asked again on the next open
            }
        }
        running[key] = t
        let r = await t.value
        running[key] = nil
        if case .found(let s)? = r { return s.logo }
        return nil
    }
}
