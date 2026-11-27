import SwiftUI
import Combine
import PlayerCore

/// Fusion-Startseiten-Kit (kit.betterer.cc): Kit-Dateien zur Laufzeit von GitHub laden (nichts davon liegt im Repo),
/// 24 h in Caches halten und die Kit-Reihen der Startseite mit der Auswahl abgleichen (FusionKitSync).
/// Einstellungen je Profil in UserDefaults (klein; das Profil-Modell bleibt unverändert).
@MainActor
final class FusionKitStore: ObservableObject {
    static let shared = FusionKitStore()
    static let maxAge: TimeInterval = 24 * 3600

    @Published private(set) var settings = FusionKitSettings()
    /// Geladene Kit-Dateien je Quellen-Schlüssel.
    @Published private(set) var contents: [String: FusionKitContent] = [:]
    /// Angebotene Kit-Dateien (GitHub-Dateiliste).
    @Published private(set) var listing: [FusionKitSource] = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var listingLoading = false
    @Published private(set) var listingError: String?

    private weak var model: AppModel?
    private var watch: AnyCancellable?
    private var syncQueued = false
    private var settingsProfile: UUID?
    /// Task 2.4: false while no settings are stored for the profile (e.g. a restored backup without kit settings):
    /// then the start page keeps its kit rows (`FusionKitSync.apply(settings: nil, layout:)`) and nothing is persisted.
    private var settingsStored = false
    /// Sichtbare Kit-Collections (ohne Trakt-Kacheln, wenn die Client ID fehlt), beim Abgleich berechnet.
    private var visible: [String: MediaCollection] = [:]
    private var loggedHidden = false
    /// Welle F-l: Bilddateien der Paket-Kacheln schon angefordert (einmal je Start).
    private var artRequested = false
    /// Laufendes Laden je Quellen-Schlüssel.
    private var inflight: [String: Task<Void, Never>] = [:]
    private let disk = FileBlobStorage(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("fusionkit"))
    /// Pasted widget exports of round 3 (read once and moved to `blobs`).
    private let pasteDisk = FileBlobStorage(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("fusionkit-paste"))

    /// App storage (Application Support if writable, always Caches): pasted widget exports live here.
    private var blobs: BlobStorage?

    private init() {}

    /// Beim App-Start: Zwischenspeicher lesen, abgleichen, veraltete gewählte Dateien im Hintergrund neu holen.
    func attach(_ model: AppModel, storage: BlobStorage) {
        self.model = model
        blobs = storage
        CollectionLinkStore.shared.ensure(model)   // wave F-o round 2: preview packs before the first sync
        // Profiländerung (Schlüssel, Layout, Profilwechsel) → abgleichen; erst danach, denn @Published meldet vor dem Setzen.
        watch = model.$stored.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.scheduleSync() }
        }
        for f in FusionKitCatalog.folders {
            if let d = disk.read(listingFile(f)) { listing += FusionKitCatalog.parseListing(d) }
        }
        sync()
        Task { await refresh() }
    }

    // MARK: Lesen (Startseite)

    func collection(_ id: String) -> MediaCollection? { visible[id] }
    /// Wave F-o round 2: all visible kit collections (preview pack matching count).
    var importedCollections: [MediaCollection] { Array(visible.values) }
    /// Welle F-l: Bildquellen der Paket-Kacheln aus allen geladenen Kit-Dateien, ungefiltert (auch Kacheln, deren
    /// Listen ohne Trakt ausgeblendet sind). Vom Nutzer gewählte Dateien zuerst, übrige nach Titel – so ist der
    /// Treffer bei Gleichstand immer derselbe. Beim Abgleich berechnet.
    private(set) var artSources: [PackageArtSource] = []
    /// Steigt mit jeder Änderung von `visible` oder `artSources` (Merker der Paket-Kachelbilder).
    private(set) var revision = 0

    /// Katalog-Dateien plus gewählte/eingetragene Quellen außerhalb des Katalogs.
    var sources: [FusionKitSource] {
        listing + settings.sources.filter { s in !listing.contains { $0.id == s.id } }
    }

    func isListed(_ id: String) -> Bool { listing.contains { $0.id == id } }

    /// Welle F-g: Name der Kit-Datei einer Kit-ID (Reihentitel, solange die Collection noch nicht da ist).
    func sourceTitle(ofID id: String) -> String? {
        guard let key = FusionImport.sourceKey(ofID: id) else { return nil }
        return sources.first { $0.id == key }?.title
    }

    /// Welle F-g: Kit-Datei nach Fehlschlag neu holen (Statuskachel „Laden fehlgeschlagen“ der Startseite).
    func retry(sourceKey key: String) async {
        ensureSettings()
        guard let src = sources.first(where: { $0.id == key }) else {
            RemoteLog.error("kit", "Erneut laden: Quelle \(key) unbekannt")
            return
        }
        RemoteLog.info("kit", "Erneut laden: \(src.title)")
        await load(src, force: true)
        sync()
    }

    // MARK: Einstellungen

    func setEnabled(_ on: Bool) {
        change { $0.enabled = on }
        if on { Task { await refresh() } }
    }

    func select(_ rowID: String, _ on: Bool, source: FusionKitSource) {
        change { $0.setSelected(rowID, on, source: source) }
    }

    /// Kit-Reihe hinzufügen bzw. wieder einblenden (Browser, Verwalter, Handy). Ist das Kit aus, geht es an, die alte
    /// Auswahl wird verworfen und nur diese Reihe kommt zurück (F-b2-Review I1). Rückgabe: verworfene Reihen-IDs.
    @discardableResult
    func choose(_ rowID: String, source: FusionKitSource) -> [String] {
        ensureSettings()
        let wasOff = !settings.enabled
        var dropped: [String] = []
        change { dropped = $0.choose(rowID, source: source) }
        if wasOff {
            RemoteLog.info("kit", "Kit eingeschaltet mit einer Reihe" + (dropped.isEmpty ? "" : ", \(dropped.count) alte Auswahl verworfen"))
            Task { await refresh() }
        }
        return dropped
    }

    func removeSource(_ id: String) {
        change { $0.removeSource(id) }
        contents[id] = nil; errors[id] = nil
        disk.remove(contentFile(id))
        pasteDisk.remove(contentFile(id))
        blobs?.remove(pasteFile(id))
    }

    /// Per Handy eingefügte Kit-URL: laden, Kit an, alle Reihen der Datei wählen. Rückgabe: Fehlertext oder nil.
    func importURL(_ url: String) async -> String? {
        let src = FusionKitCatalog.source(forURL: url)
        await load(src, force: true)
        guard let c = contents[src.id] else { return errors[src.id] ?? "nicht geladen" }
        change { $0.addAll(c, source: src) }
        RemoteLog.info("kit", "Handy-Import \(src.title): \(c.rows.count) Reihen gewählt")
        return nil
    }

    /// Wave F-o round 2: widget export already fetched (collection link) or pasted as code: keep it like a kit
    /// file and place all its rows. A pasted text gets a `paste:` source that is never fetched again.
    /// Already parsed off the main actor (`CollectionLinkStore`); `data` is kept for the next start. Pasted text
    /// cannot be fetched again, so it goes to the app storage (round 4, N2): Application Support if it is writable
    /// and always Caches as the second copy. A failed write is logged.
    func importContent(_ c: FusionKitContent, source src: FusionKitSource, data: Data) {
        contents[src.id] = c
        errors[src.id] = nil
        do {
            if isPaste(src) {
                guard let blobs else { throw CocoaError(.fileWriteUnknown) }
                try blobs.write(pasteFile(src.id), data)
            } else {
                try disk.write(contentFile(src.id), data)
            }
        } catch {
            RemoteLog.error("import", "Import: Speichern fehlgeschlagen (\(src.title), \(data.count / 1024) KB: \(error))")
        }
        change { $0.addAll(c, source: src) }
        sync()
        RemoteLog.info("kit", "Import \(src.title): \(c.rows.count) Reihen gewählt")
    }

    /// Source of a widget export: the kit source of a link, or a `paste:` source keyed by the pasted text.
    nonisolated static func source(link: String?, data: Data) -> FusionKitSource {
        link.map { FusionKitCatalog.source(forURL: $0) }
            ?? FusionKitSource(id: NuvioImport.stableHash("paste:" + String(decoding: data, as: UTF8.self)),
                               title: "Eingefügter Widget-Export", url: pastePrefix, custom: true)
    }

    private func isPaste(_ src: FusionKitSource) -> Bool { src.url.hasPrefix(Self.pastePrefix) }
    /// File-only blob of a pasted widget export (`TieredBlobStorage.fileOnlyPrefix`).
    private func pasteFile(_ key: String) -> String { TieredBlobStorage.fileOnlyPrefix + "paste-" + key + ".json" }

    /// Stored bytes of a source. A paste of an earlier build (own folder, or Caches) moves to the app storage once.
    private func stored(_ src: FusionKitSource) -> Data? {
        guard isPaste(src) else { return disk.read(contentFile(src.id)) }
        if let d = blobs?.read(pasteFile(src.id)) { return d }
        let file = contentFile(src.id)
        guard let old = pasteDisk.read(file) ?? disk.read(file) else { return nil }
        do {
            guard let blobs else { throw CocoaError(.fileWriteUnknown) }
            try blobs.write(pasteFile(src.id), old)
            pasteDisk.remove(file); disk.remove(file)
        } catch {
            RemoteLog.error("import", "Import: Speichern fehlgeschlagen (\(src.title), \(old.count / 1024) KB: \(error))")
        }
        return old
    }

    nonisolated static let pastePrefix = "paste:"

    /// Wave F-o round 2: preview packs changed; tiles are enriched again on the next sync.
    func packChanged() { sync() }

    private func change(_ f: (inout FusionKitSettings) -> Void) {
        ensureSettings()
        var s = settings
        f(&s)
        guard s != settings else { return }
        settings = s
        persist()
        sync()
    }

    private func settingsKey(_ id: UUID) -> String { Self.defaultsKey(id) }
    nonisolated static func defaultsKey(_ id: UUID) -> String { "fusionkit.\(id.uuidString)" }

    private func persist() {
        guard let id = settingsProfile, let d = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(d, forKey: settingsKey(id))
        settingsStored = true
    }

    /// Task 2.4: stored kit settings of a profile (backup) and writing them back (restore, delete).
    nonisolated static func storedSettings(_ id: UUID) -> Data? { UserDefaults.standard.data(forKey: defaultsKey(id)) }
    nonisolated static func setStoredSettings(_ d: Data?, for id: UUID) {
        if let d { UserDefaults.standard.set(d, forKey: defaultsKey(id)) }
        else { UserDefaults.standard.removeObject(forKey: defaultsKey(id)) }
    }

    /// Task 2.4: after a restore the settings of the active profile are read again.
    func profileScopeChanged() {
        settingsProfile = nil
        scheduleSync()
    }

    /// Einstellungen des aktiven Profils (nach Profilwechsel neu) samt Zwischenspeicher seiner Quellen.
    private func ensureSettings() {
        guard let model, let id = model.stored.active?.id, id != settingsProfile else { return }
        CollectionLinkStore.shared.ensure(model)
        let first = settingsProfile == nil
        settingsProfile = id
        let loaded = UserDefaults.standard.data(forKey: settingsKey(id))
            .flatMap { try? JSONDecoder().decode(FusionKitSettings.self, from: $0) }
        settingsStored = loaded != nil
        settings = loaded ?? FusionKitSettings()
        for s in settings.sources where contents[s.id] == nil {
            if let c = cached(s) { contents[s.id] = c }
        }
        if !first { Task { await refresh() } }
    }

    // MARK: Laden

    /// - Parameters:
    ///   - force: auch frische Dateien neu holen („Kit neu laden“).
    ///   - all: Katalog und alle angebotenen Dateien (Einstellungen); sonst nur Quellen gewählter Reihen bei aktivem Kit.
    func refresh(force: Bool = false, all: Bool = false) async {
        ensureSettings()
        if all { await loadListing(force: force) } else if !settings.enabled { return }
        let keys = Set(settings.selected.compactMap { FusionImport.sourceKey(ofID: $0) })
        let chosen = settings.sources.filter { all || keys.contains($0.id) }
        let list = chosen + (all ? listing.filter { s in !chosen.contains { $0.id == s.id } } : [])
        await withTaskGroup(of: Void.self) { g in
            for s in list { g.addTask { await self.load(s, force: force) } }
        }
        sync()
    }

    /// Lädt eine Kit-Datei; läuft für dieselbe Quelle schon ein Laden, wird darauf gewartet (kein zweiter Abruf).
    private func load(_ src: FusionKitSource, force: Bool) async {
        if !force, isFresh(contentFile(src.id)) {
            if contents[src.id] != nil { return }
            if let c = cached(src) { contents[src.id] = c; return }
        }
        // Pasted code has no address: only the stored copy.
        if src.url.hasPrefix(Self.pastePrefix) {
            if contents[src.id] == nil, let c = cached(src) { contents[src.id] = c }
            return
        }
        if let running = inflight[src.id] { await running.value; return }
        guard let url = URL(string: src.url) else { errors[src.id] = "URL ungültig"; return }
        let task = Task { await self.fetch(src, url: url) }
        inflight[src.id] = task
        loading.insert(src.id)
        await task.value
        inflight[src.id] = nil
        loading.remove(src.id)
    }

    private func fetch(_ src: FusionKitSource, url: URL) async {
        do {
            let data = try await URLSessionFetcher().data(from: url)
            let key = src.id, title = src.title
            let c = try await Task.detached { try FusionImport.parse(data, sourceKey: key, title: title) }.value
            contents[src.id] = c
            errors[src.id] = nil
            try? disk.write(contentFile(src.id), data)
            let w = c.warnings.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
            RemoteLog.info("kit", "\(src.title): \(c.rows.count) Reihen" + (w.isEmpty ? "" : " · \(w)"))
        } catch {
            // Netz weg oder Datei kaputt: alter Stand von der Platte, wie beim Katalog.
            if contents[src.id] == nil, let c = cached(src) { contents[src.id] = c }
            let old = contents[src.id] != nil
            errors[src.id] = "\(error)" + (old ? " (alter Stand)" : "")
            RemoteLog.error("kit", "\(src.title): \(error)" + (old ? " · alter Stand" : ""))
        }
    }

    /// Zwischengespeicherte Fassung, auch wenn sie älter als 24 h ist.
    private func cached(_ src: FusionKitSource) -> FusionKitContent? {
        stored(src).flatMap { try? FusionImport.parse($0, sourceKey: src.id, title: src.title) }
    }

    private func loadListing(force: Bool) async {
        guard !listingLoading else { return }
        if !force, !listing.isEmpty, FusionKitCatalog.folders.allSatisfy({ isFresh(listingFile($0)) }) { return }
        listingLoading = true
        defer { listingLoading = false }
        var out: [FusionKitSource] = []
        var failed: String?
        for f in FusionKitCatalog.folders {
            let file = listingFile(f)
            if !force, isFresh(file), let d = disk.read(file) { out += FusionKitCatalog.parseListing(d); continue }
            do {
                guard let url = FusionKitCatalog.listingURL(f) else { continue }
                let d = try await URLSessionFetcher().data(from: url)
                let parsed = FusionKitCatalog.parseListing(d)
                if !parsed.isEmpty { try? disk.write(file, d) }
                out += parsed
            } catch {
                failed = "\(error)"
                if let d = disk.read(file) { out += FusionKitCatalog.parseListing(d) }   // alter Stand
            }
        }
        listing = out
        listingError = failed
        if let failed { RemoteLog.error("kit", "Katalog: \(failed)") }
        else { RemoteLog.info("kit", "Katalog: \(out.count) Dateien") }
    }

    /// Welle F-l: Kit-Dateien mit Bildern für die Paket-Kacheln (Streaming-Dienste, Genres) holen – auch bei
    /// ausgeschaltetem Kit, sobald eine Paket-Reihe auf der Startseite steht. Dateiliste und Dateien kommen aus dem
    /// 24-h-Zwischenspeicher, sonst von GitHub; ohne Netz der alte Stand von der Platte.
    private func loadPackageArt() async {
        // Erst der Stand von der Platte (sofort Bilder, auch ohne Netz), dann Dateiliste und Dateien auffrischen.
        // Das Zerlegen der Dateien läuft abseits des Main Actors (die Startseite zeichnet gerade).
        let disk = self.disk
        let pending = FusionKitCatalog.packageArtSources(listing).filter { contents[$0.id] == nil }
            .map { (src: $0, file: contentFile($0.id)) }
        let parsed = await Task.detached { () -> [(String, FusionKitContent)] in
            var out: [(String, FusionKitContent)] = []
            for p in pending {
                guard let d = disk.read(p.file),
                      let c = try? FusionImport.parse(d, sourceKey: p.src.id, title: p.src.title) else { continue }
                out.append((p.src.id, c))
            }
            return out
        }.value
        for (id, c) in parsed where contents[id] == nil { contents[id] = c }
        sync()
        await loadListing(force: false)
        let list = FusionKitCatalog.packageArtSources(listing)
        await withTaskGroup(of: Void.self) { g in
            for s in list { g.addTask { await self.load(s, force: false) } }
        }
        let ok = list.filter { contents[$0.id] != nil }.count
        RemoteLog.info("kit", "Paket-Bilder: \(ok)/\(list.count) Kit-Dateien geladen")
        sync()
    }

    private func contentFile(_ key: String) -> String { key + ".json" }
    private func listingFile(_ folder: String) -> String { "listing-\(folder).json" }

    private func isFresh(_ file: String) -> Bool {
        guard let d = (try? FileManager.default.attributesOfItem(atPath: disk.url(file).path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(d) < Self.maxAge
    }

    // MARK: Abgleich mit der Startseite

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        Task { @MainActor in
            self.syncQueued = false
            self.sync()
        }
    }

    func sync() {
        guard let model else { return }
        ensureSettings()
        let traktID = model.hasTraktID, traktLogin = model.isConnected("trakt")
        var layout = model.profile.home
        var s = settings
        // b5f: addon catalog sources (widget exports) need an installed addon that serves them.
        let addons = model.profile.addons
        let r = FusionKitSync.apply(layout: &layout, settings: &s, contents: contents, traktID: traktID, traktLogin: traktLogin,
                                    addons: addons)
        let index = AddonCatalogIndex(addons)   // review L5: one index for all rows of this sync

        var vis: [String: MediaCollection] = [:]
        var hiddenTiles = 0, hiddenTilesByTrakt = 0
        // Wave F-o round 2: imported preview packs fill video and still of tiles with the same title.
        let pack = CollectionLinkStore.shared.packIndex
        for (_, c) in contents {
            for row in c.rows {
                guard case .collection(let full) = row.body else { continue }
                if let a = row.available(traktID: traktID, traktLogin: traktLogin, catalogs: index), case .collection(let v) = a.body {
                    vis[row.id] = PreviewPack.apply(pack, to: v)
                    if s.placed.contains(row.id) {
                        hiddenTiles += full.folders.count - v.folders.count
                        if case .collection(let t)? = row.available(traktID: traktID, traktLogin: traktLogin)?.body {
                            hiddenTilesByTrakt += full.folders.count - t.folders.count
                        }
                    }
                }
            }
        }
        let art = computeArtSources(settings: s)
        if vis != visible || art != artSources {
            visible = vis
            artSources = art
            revision &+= 1
            model.objectWillChange.send()   // Startseite liest die Kacheln über model.collection(_:)
        }
        if !artRequested, layout.rows.contains(where: { row in
            if case .collection(let id) = row.content { return id.hasPrefix("pkg.") }
            return false
        }) {
            artRequested = true
            Task { await loadPackageArt() }
        }

        // Task 2.4: without stored settings the kit rows stay (layout unchanged, nothing persisted).
        if !settingsStored {
            layout = FusionKitSync.apply(settings: nil, layout: model.profile.home)
        } else if s != settings { settings = s; persist() }
        if layout != model.profile.home { model.update { $0.home = layout } }
        if settingsStored, !r.added.isEmpty || !r.removed.isEmpty || !r.deselected.isEmpty || !r.parked.isEmpty {
            // Build 6 (L3): waiting rows leave with place and style ("wartet") and come back there ("an alter Stelle").
            var line = "Startseite: +\(r.added.count) −\(r.removed.count) Reihen"
            if !r.parked.isEmpty { line += " · \(r.parked.count) wartet (Platz und Stil gemerkt)" }
            if !r.restored.isEmpty { line += " · \(r.restored.count) an alter Stelle zurück" }
            if !r.deselected.isEmpty { line += " · \(r.deselected.count) im Editor entfernt → abgewählt" }
            RemoteLog.info("kit", line)
        }
        if !loggedHidden, !r.hidden.isEmpty || hiddenTiles > 0 {
            loggedHidden = true
            // Review L9: name only the reasons that apply (Trakt, addon or both).
            let rowsByTrakt = r.hidden.filter { id in
                guard let key = FusionImport.sourceKey(ofID: id), let row = contents[key]?.row(id) else { return false }
                return row.available(traktID: traktID, traktLogin: traktLogin) == nil
            }.count
            var reasons: [String] = []
            if rowsByTrakt > 0 || hiddenTilesByTrakt > 0 { reasons.append(traktID ? "Trakt-Anmeldung fehlt" : "Trakt Client ID fehlt") }
            if rowsByTrakt < r.hidden.count || hiddenTilesByTrakt < hiddenTiles { reasons.append("kein installiertes Addon mit dem Katalog") }
            let why = reasons.joined(separator: ", ")
            RemoteLog.info("kit", "\(r.hidden.count) Kit-Reihe(n) und \(hiddenTiles) Kachel(n) ausgeblendet: \(why)")
        }
    }

    /// Bildquellen aus den geladenen Kit-Dateien (`PackageArtSource.kitSources`): gewählte Dateien (Reihen bei
    /// aktivem Kit, per Handy eingetragene URLs) und die Paket-Bilddateien, keine anderen Kit-Dateien.
    private func computeArtSources(settings s: FusionKitSettings) -> [PackageArtSource] {
        var chosen = Set(s.sources.filter(\.custom).map(\.id))
        if s.enabled { chosen.formUnion(s.selected.compactMap { FusionImport.sourceKey(ofID: $0) }) }
        let titles = Dictionary(sources.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return PackageArtSource.kitSources(contents: contents, titles: titles, chosen: chosen,
                                           packFiles: Set(FusionKitCatalog.packageArtSources(listing).map(\.id)))
    }
}
