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
    /// Sichtbare Kit-Collections (ohne Trakt-Kacheln, wenn die Client ID fehlt), beim Abgleich berechnet.
    private var visible: [String: MediaCollection] = [:]
    private var loggedHidden = false
    /// Laufendes Laden je Quellen-Schlüssel.
    private var inflight: [String: Task<Void, Never>] = [:]
    private let disk = FileBlobStorage(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("fusionkit"))

    private init() {}

    /// Beim App-Start: Zwischenspeicher lesen, abgleichen, veraltete gewählte Dateien im Hintergrund neu holen.
    func attach(_ model: AppModel) {
        self.model = model
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

    /// Katalog-Dateien plus gewählte/eingetragene Quellen außerhalb des Katalogs.
    var sources: [FusionKitSource] {
        listing + settings.sources.filter { s in !listing.contains { $0.id == s.id } }
    }

    func isListed(_ id: String) -> Bool { listing.contains { $0.id == id } }

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

    private func change(_ f: (inout FusionKitSettings) -> Void) {
        ensureSettings()
        var s = settings
        f(&s)
        guard s != settings else { return }
        settings = s
        persist()
        sync()
    }

    private func settingsKey(_ id: UUID) -> String { "fusionkit.\(id.uuidString)" }

    private func persist() {
        guard let id = settingsProfile, let d = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(d, forKey: settingsKey(id))
    }

    /// Einstellungen des aktiven Profils (nach Profilwechsel neu) samt Zwischenspeicher seiner Quellen.
    private func ensureSettings() {
        guard let id = model?.stored.active?.id, id != settingsProfile else { return }
        let first = settingsProfile == nil
        settingsProfile = id
        settings = UserDefaults.standard.data(forKey: settingsKey(id))
            .flatMap { try? JSONDecoder().decode(FusionKitSettings.self, from: $0) } ?? FusionKitSettings()
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
        disk.read(contentFile(src.id)).flatMap { try? FusionImport.parse($0, sourceKey: src.id, title: src.title) }
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
        let r = FusionKitSync.apply(layout: &layout, settings: &s, contents: contents, traktID: traktID, traktLogin: traktLogin)

        var vis: [String: MediaCollection] = [:]
        var hiddenTiles = 0
        for (_, c) in contents {
            for row in c.rows {
                guard case .collection(let full) = row.body else { continue }
                if let a = row.available(traktID: traktID, traktLogin: traktLogin), case .collection(let v) = a.body {
                    vis[row.id] = v
                    if s.placed.contains(row.id) { hiddenTiles += full.folders.count - v.folders.count }
                }
            }
        }
        if vis != visible {
            visible = vis
            model.objectWillChange.send()   // Startseite liest die Kacheln über model.collection(_:)
        }

        if s != settings { settings = s; persist() }
        if layout != model.profile.home { model.update { $0.home = layout } }
        if !r.added.isEmpty || !r.removed.isEmpty || !r.deselected.isEmpty {
            RemoteLog.info("kit", "Startseite: +\(r.added.count) −\(r.removed.count) Reihen" + (r.deselected.isEmpty ? "" : " · \(r.deselected.count) im Editor entfernt → abgewählt"))
        }
        if !loggedHidden, !r.hidden.isEmpty || hiddenTiles > 0 {
            loggedHidden = true
            let why = traktID ? "Trakt-Anmeldung fehlt" : "Trakt Client ID fehlt"
            RemoteLog.info("kit", "\(r.hidden.count) Kit-Reihe(n) und \(hiddenTiles) Kachel(n) ausgeblendet: \(why)")
        }
    }
}
