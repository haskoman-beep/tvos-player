import Foundation
import PlayerCore

/// One stored collection import (wave F-o round 2): a link (re-fetched by "Aktualisieren") or pasted code.
struct CollectionLink: Codable, Hashable, Identifiable {
    var id: String
    /// nil for pasted code (cannot be refreshed).
    var url: String?
    var format: String
    var summary: String
    var at: Date
    /// Entries of a preview pack (matched to tiles by title at display time).
    var pack: [PreviewPackEntry]?
    /// Collection export: media addresses of the last import (a refresh keeps only the user's own changes).
    var media: [String: FolderMedia]?

    init(id: String, url: String?, format: String, summary: String, at: Date, pack: [PreviewPackEntry]? = nil,
         media: [String: FolderMedia]? = nil) {
        self.id = id; self.url = url; self.format = format; self.summary = summary; self.at = at; self.pack = pack
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .distantPast
        pack = try c.decodeIfPresent([PreviewPackEntry].self, forKey: .pack)
        media = try c.decodeIfPresent([String: FolderMedia].self, forKey: .media)
    }
}

/// Collection imports by link or code: fetches, detects the format (`CollectionImportFormat`), hands widget exports
/// to `FusionKitStore`, collection exports to `AppModel.importNuvio`, and keeps preview packs itself. Links are
/// stored per profile in UserDefaults (small; the profile model stays unchanged). Nothing of it is bundled.
@MainActor
final class CollectionLinkStore: ObservableObject {
    static let shared = CollectionLinkStore()

    @Published private(set) var links: [CollectionLink] = []
    @Published private(set) var busy = false
    /// Title lookup of all stored preview packs (earlier links win on equal titles).
    private(set) var packIndex = PreviewPack.Index([])
    /// Rises with every pack change (memo of enriched profile collections).
    private(set) var packRevision = 0

    private var profile: UUID?
    private weak var model: AppModel?
    private var memo: [String: (stamp: [Int], c: MediaCollection)] = [:]
    /// Video address → has a sound track (probed once per start).
    private var soundProbe: [String: Bool] = [:]
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // MARK: Profile

    private func key(_ id: UUID) -> String { "collectionlinks.\(id.uuidString)" }

    /// Links of the active profile (re-read after a profile switch).
    func ensure(_ model: AppModel) {
        self.model = model
        guard let id = model.stored.active?.id, id != profile else { return }
        profile = id
        links = UserDefaults.standard.data(forKey: key(id)).flatMap { try? JSONDecoder().decode([CollectionLink].self, from: $0) } ?? []
        rebuildPack()
    }

    private func persist() {
        guard let profile, let d = try? JSONEncoder().encode(links) else { return }
        UserDefaults.standard.set(d, forKey: key(profile))
    }

    private func rebuildPack() {
        let index = PreviewPack.Index(links.flatMap { $0.pack ?? [] })
        guard index != packIndex else { return }
        packIndex = index
        packRevision &+= 1
        memo = [:]
        FusionKitStore.shared.packChanged()
        model?.objectWillChange.send()
    }

    /// A profile collection with the preview packs applied (memoised per collection).
    func enriched(_ c: MediaCollection, profileRevision: Int) -> MediaCollection {
        guard !packIndex.isEmpty else { return c }
        let stamp = [profileRevision, packRevision]
        if let m = memo[c.id], m.stamp == stamp { return m.c }
        let out = PreviewPack.apply(packIndex, to: c)
        memo[c.id] = (stamp, out)
        return out
    }

    // MARK: Import

    /// Largest body of a link (same as the phone page).
    nonisolated static let maxLinkBytes = HTTPRequest.maxBody
    nonisolated static let linkTimeout: TimeInterval = 20
    /// Most stored imports per profile (they live in UserDefaults).
    static let maxLinks = 30

    private enum LinkError: Error { case http(Int), tooLarge }

    /// Parsed once, off the main actor.
    private enum Parsed: Sendable {
        case widgets(FusionKitContent, FusionKitSource)
        case collections(NuvioImportResult)
        case pack([PreviewPackEntry], skipped: Int)
    }

    private let linkSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = CollectionLinkStore.linkTimeout
        cfg.timeoutIntervalForResource = CollectionLinkStore.linkTimeout
        return URLSession(configuration: cfg)
    }()

    /// Link from the TV field or the phone page: fetch, detect, import, keep the link.
    func importLink(_ raw: String, model: AppModel) async {
        ensure(model)
        let u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: u), url.scheme == "https" || url.scheme == "http", url.host != nil else {
            model.lastError = "Import: Link ungültig (\(u))."
            return
        }
        busy = true
        defer { busy = false }
        RemoteLog.info("import", "Collection-Link: \(url.host ?? "?")")
        let data: Data
        do { data = try await Self.fetch(url, session: linkSession) } catch {
            model.lastError = "Import: Link nicht geladen (\(Self.describe(error)))."
            return
        }
        await importData(data, link: u, model: model)
    }

    /// Pasted code from the phone page.
    func importCode(_ data: Data, model: AppModel) async {
        ensure(model)
        busy = true
        defer { busy = false }
        await importData(data, link: nil, model: model)
    }

    /// "Aktualisieren": fetch one stored link again.
    func refresh(_ id: String, model: AppModel) async {
        guard let u = links.first(where: { $0.id == id })?.url else { return }
        await importLink(u, model: model)
    }

    func refreshAll(model: AppModel) async {
        for u in links.compactMap(\.url) { await importLink(u, model: model) }
    }

    /// Forget a link. Imported rows stay on the start page (they are removed there); a pack stops enriching.
    func remove(_ id: String) {
        links.removeAll { $0.id == id }
        persist()
        rebuildPack()
    }

    /// Body of a link, at most `maxLinkBytes` (a wrong link to a video or archive is stopped early).
    private nonisolated static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        let (bytes, resp) = try await session.bytes(from: url)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            bytes.task.cancel()
            throw LinkError.http(http.statusCode)
        }
        if resp.expectedContentLength > Int64(maxLinkBytes) { bytes.task.cancel(); throw LinkError.tooLarge }
        var out = Data()
        if resp.expectedContentLength > 0 { out.reserveCapacity(Int(resp.expectedContentLength)) }
        for try await b in bytes {
            out.append(b)
            if out.count > maxLinkBytes { bytes.task.cancel(); throw LinkError.tooLarge }
        }
        return out
    }

    /// Plain German reason of a failed fetch.
    private nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case LinkError.http(let code): return "HTTP \(code)"
        case LinkError.tooLarge: return "Datei größer als 8 MB – ist es wirklich ein JSON-Export?"
        default:
            switch (error as? URLError)?.code {
            case .notConnectedToInternet?, .networkConnectionLost?: return "kein Netz"
            case .timedOut?: return "Zeitüberschreitung"
            case .cannotFindHost?, .dnsLookupFailed?: return "Server nicht gefunden"
            case .secureConnectionFailed?, .serverCertificateUntrusted?: return "sichere Verbindung fehlgeschlagen"
            case let c?: return "Netzfehler \(c.rawValue)"
            case nil: return "unbekannter Fehler"
            }
        }
    }

    /// Detects and parses in one pass (off the main actor).
    private nonisolated static func parse(_ data: Data, link: String?) -> (CollectionImportFormat, Result<Parsed, Error>) {
        let format = CollectionImportFormat.detect(data)
        let r = Result<Parsed, Error> {
            switch format {
            case .widgets, .collectionList:
                let src = FusionKitStore.source(link: link, data: data)
                return .widgets(try FusionImport.parse(data, sourceKey: src.id, title: src.title), src)
            case .collections: return .collections(try NuvioImport.parse(data))
            case .previewPack:
                let (entries, skipped) = try PreviewPack.parse(data)
                return .pack(entries, skipped: skipped)
            case .backup, .iconPack, .invalidJSON, .unknown: throw LinkError.http(0)
            }
        }
        return (format, r)
    }

    private func importData(_ data: Data, link: String?, model: AppModel) async {
        let (format, result) = await Task.detached(priority: .userInitiated) { Self.parse(data, link: link) }.value
        if let problem = format.problem {
            model.lastError = "Import: \(problem)"
            RemoteLog.info("import", "Collection-Import abgelehnt: \(format.name)")
            return
        }
        let parsed: Parsed
        switch result {
        case .success(let p): parsed = p
        case .failure:
            model.lastError = "Import: \(format.name) nicht lesbar (Aufbau unbekannt oder unvollständig)."
            return
        }
        let id = link.map { NuvioImport.stableHash("link:" + $0) } ?? NuvioImport.stableHash("code:" + String(decoding: data, as: UTF8.self))
        let previous = links.first { $0.id == id }
        var pack: [PreviewPackEntry]?
        var media: [String: FolderMedia]?
        /// Collections whose videos are probed for a sound track, or the pack's videos.
        var probe: [String] = []
        var line: (Int?) -> String
        switch parsed {
        case .widgets(let c, let src):
            FusionKitStore.shared.importContent(c, source: src, data: data)
            let collections = c.rows.compactMap { r -> MediaCollection? in
                if case .collection(let m) = r.body { return m }
                return nil
            }.map { PreviewPack.apply(packIndex, to: $0) }
            probe = ImportSummary.videos(collections)
            let base = ImportSummary.of(collections)
            line = { n in var s = base; s.rows = c.rows.count; s.sound = n; return s.line }
        case .collections(let r):
            // A refresh of a stored link takes the fresh media addresses (I4); a first import only fills gaps.
            model.importNuvio(result: r, refresh: previous.map { $0.media ?? [:] })
            media = NuvioImport.media(of: r.collections)
            let collections = r.collections.map { PreviewPack.apply(packIndex, to: $0) }
            probe = ImportSummary.videos(collections)
            let base = ImportSummary.of(collections)
            line = { n in var s = base; s.sound = n; return s.line }
        case .pack(let entries, let skipped):
            guard !entries.isEmpty else {
                model.lastError = "Import: Das Preview Pack enthält keine abspielbaren Videos (mp4/mov/m3u8 über https)."
                return
            }
            pack = entries
            let index = PreviewPack.Index(entries)
            let targets = model.profile.collections.filter { !$0.id.hasPrefix("pkg.") } + FusionKitStore.shared.importedCollections
            let matched = PreviewPack.matches(index, in: targets)
            var seen = Set<String>()
            probe = entries.map(\.video).filter { seen.insert($0).inserted }
            line = { n in ImportSummary.packLine(entries: entries.count, matched: matched, sound: n) + (skipped > 0 ? " (\(skipped) übersprungen)" : "") }
        }
        if previous == nil, links.count >= Self.maxLinks, let oldest = links.min(by: { $0.at < $1.at }) {
            links.removeAll { $0.id == oldest.id }   // keep UserDefaults small
        }
        var entry = CollectionLink(id: id, url: link, format: format.name, summary: line(nil), at: Date(), pack: pack, media: media)
        store(entry)
        model.lastError = nil
        model.notice = entry.summary
        RemoteLog.info("import", "\(format.name)\(link == nil ? " (Code)" : ""): \(entry.summary)")
        // The sound count follows (range requests can take a while; the rows are already there).
        guard let sound = await soundCount(probe) else { return }
        let first = entry.summary
        entry.summary = line(sound)
        if links.contains(where: { $0.id == id }) { store(entry) }
        if model.notice == first { model.notice = entry.summary }
        RemoteLog.info("import", "\(format.name): \(sound) mit Ton")
    }

    private func store(_ entry: CollectionLink) {
        if let i = links.firstIndex(where: { $0.id == entry.id }) { links[i] = entry } else { links.append(entry) }
        persist()
        rebuildPack()
    }

    // MARK: Sound probe

    /// Most videos checked per import (two small range requests each).
    static let maxProbes = 120

    private func soundCount(_ videos: [String]) async -> Int? {
        guard !videos.isEmpty else { return 0 }
        guard videos.count <= Self.maxProbes else { return nil }
        await probe(videos)
        return videos.filter { soundProbe[$0] == true }.count
    }

    /// Reads the start and the end of each file (range requests) and looks for a sound track.
    private func probe(_ videos: [String]) async {
        let todo = videos.filter { soundProbe[$0] == nil && !FocusVideoURL.isStream($0) }
        let session = self.session
        // Six at a time.
        for start in stride(from: 0, to: todo.count, by: 6) {
            let chunk = Array(todo[start..<min(start + 6, todo.count)])
            let results = await withTaskGroup(of: (String, Bool).self) { g -> [(String, Bool)] in
                for v in chunk {
                    guard let url = URL(string: v) else { continue }
                    g.addTask { (v, await Self.hasSound(url, session: session)) }
                }
                var out: [(String, Bool)] = []
                for await r in g { out.append(r) }
                return out
            }
            for (v, s) in results { soundProbe[v] = s }
        }
    }

    private nonisolated static func hasSound(_ url: URL, session: URLSession) async -> Bool {
        if let head = await range(url, "bytes=0-\(Mp4Probe.headBytes - 1)", limit: Mp4Probe.headBytes, session: session),
           Mp4Probe.hasSoundTrack(head) { return true }
        if let tail = await range(url, "bytes=-\(Mp4Probe.tailBytes)", limit: Mp4Probe.tailBytes, session: session) {
            return Mp4Probe.hasSoundTrack(tail)
        }
        return false
    }

    /// Bytes of a range request; a server that ignores the range (200) is read only up to `limit`.
    private nonisolated static func range(_ url: URL, _ range: String, limit: Int, session: URLSession) async -> [UInt8]? {
        var req = URLRequest(url: url)
        req.setValue(range, forHTTPHeaderField: "Range")
        guard let answer = try? await session.bytes(for: req) else { return nil }
        let bytes = answer.0
        guard let http = answer.1 as? HTTPURLResponse else { bytes.task.cancel(); return nil }
        // A full answer to a tail request would be the start of the file, not its end.
        if http.statusCode == 200, range.hasPrefix("bytes=-") { bytes.task.cancel(); return nil }
        guard http.statusCode == 206 || http.statusCode == 200 else { bytes.task.cancel(); return nil }
        var out: [UInt8] = []
        out.reserveCapacity(limit)
        do {
            for try await b in bytes {
                out.append(b)
                if out.count >= limit { break }
            }
        } catch { return out.isEmpty ? nil : out }
        bytes.task.cancel()
        return out
    }
}
