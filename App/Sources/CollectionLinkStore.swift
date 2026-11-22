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

    init(id: String, url: String?, format: String, summary: String, at: Date, pack: [PreviewPackEntry]? = nil) {
        self.id = id; self.url = url; self.format = format; self.summary = summary; self.at = at; self.pack = pack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .distantPast
        pack = try c.decodeIfPresent([PreviewPackEntry].self, forKey: .pack)
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
        do { data = try await URLSessionFetcher().data(from: url) } catch {
            model.lastError = "Import: Link nicht geladen (\(error))."
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

    private func importData(_ data: Data, link: String?, model: AppModel) async {
        let format = CollectionImportFormat.detect(data)
        if let problem = format.problem {
            model.lastError = "Import: \(problem)"
            RemoteLog.info("import", "Collection-Import abgelehnt: \(format.name)")
            return
        }
        var summary: String
        var pack: [PreviewPackEntry]?
        do {
            switch format {
            case .widgets, .collectionList:
                let c = try FusionKitStore.shared.importData(data, link: link)
                let collections = c.rows.compactMap { r -> MediaCollection? in
                    if case .collection(let m) = r.body { return m }
                    return nil
                }.map { PreviewPack.apply(packIndex, to: $0) }
                var s = ImportSummary.of(collections, soundVideos: await soundVideos(collections))
                s.rows = c.rows.count
                summary = s.line
            case .collections:
                let r = try NuvioImport.parse(data)
                model.importNuvio(data: data)
                let collections = r.collections.map { PreviewPack.apply(packIndex, to: $0) }
                summary = ImportSummary.of(collections, soundVideos: await soundVideos(collections)).line
            case .previewPack:
                let (entries, skipped) = try PreviewPack.parse(data)
                guard !entries.isEmpty else {
                    model.lastError = "Import: Das Preview Pack enthält keine abspielbaren Videos (mp4/mov/m3u8 über https)."
                    return
                }
                pack = entries
                let index = PreviewPack.Index(entries)
                let targets = model.profile.collections.filter { !$0.id.hasPrefix("pkg.") } + FusionKitStore.shared.importedCollections
                let sound = await soundCount(Array(Set(entries.map(\.video))))
                summary = ImportSummary.packLine(entries: entries.count, matched: PreviewPack.matches(index, in: targets), sound: sound)
                if skipped > 0 { summary += " (\(skipped) übersprungen)" }
            case .backup, .iconPack, .invalidJSON, .unknown:
                return
            }
        } catch {
            model.lastError = "Import: \(format.name) nicht lesbar (\(error))."
            return
        }
        let id = link.map { NuvioImport.stableHash("link:" + $0) } ?? NuvioImport.stableHash("code:" + String(decoding: data, as: UTF8.self))
        let entry = CollectionLink(id: id, url: link, format: format.name, summary: summary, at: Date(), pack: pack)
        if let i = links.firstIndex(where: { $0.id == id }) { links[i] = entry } else { links.append(entry) }
        persist()
        rebuildPack()
        model.lastError = nil
        model.notice = summary
        RemoteLog.info("import", "\(format.name)\(link == nil ? " (Code)" : ""): \(summary)")
    }

    // MARK: Sound probe

    /// Most videos checked per import (two small range requests each).
    static let maxProbes = 120

    private func soundVideos(_ collections: [MediaCollection]) async -> Set<String>? {
        let videos = ImportSummary.videos(collections)
        guard !videos.isEmpty, videos.count <= Self.maxProbes else { return videos.isEmpty ? [] : nil }
        await probe(videos)
        return Set(videos.filter { soundProbe[$0] == true })
    }

    private func soundCount(_ videos: [String]) async -> Int? {
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
