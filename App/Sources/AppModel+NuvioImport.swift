import Foundation
import PlayerCore

// Nuvio account sync, T10: collections and addons of the account through one preview. All decisions are in
// PlayerCore (`NuvioAccountImport`); this file only fetches, keeps the preview for the page and applies the choice.
// Nothing is written to the account. Addon addresses are never logged or shown (name and host only).

/// State of the account import page (`NuvioImportPage`). One preview at a time.
@MainActor
final class NuvioImportStore: ObservableObject {
    static let shared = NuvioImportStore()

    enum Phase: Equatable {
        case idle
        case loading
        /// No stored session.
        case signedOut
        /// No account profile chosen for the local profile, or the choice no longer matches the account (A3).
        case noProfile
        case failed(String)
        case ready
        case applying
        case done(String)
    }

    /// What the preview was built from (A9: the local profile is taken once, here).
    struct Pending {
        let profile: UUID
        let source: NuvioAccountSource
        /// Collection bytes of the account, for `CollectionLinkStore.importAccount`.
        let collections: Data
        /// Manifests loaded for the preview, by instance id: "Übernehmen" installs exactly these.
        let fetched: [String: InstalledAddon]
    }

    @Published var phase: Phase = .idle
    @Published var preview: NuvioImportPreview?
    /// Instance ids of account addons to install.
    @Published var install: Set<String> = []
    /// Instance ids of "am Konto entfernt" addons to remove here (empty unless the user picks them, D2).
    @Published var remove: Set<String> = []
    @Published var takeCollections = true
    var pending: Pending?

    private init() {}

    var busy: Bool { phase == .loading || phase == .applying }

    func reset() {
        preview = nil; pending = nil; install = []; remove = []; takeCollections = true
    }
}

extension AppModel {
    /// Texts of this file (plan section 4 where it has one).
    enum NuvioImportText {
        static let signedOut = "Nicht verbunden. Anmelden am Handy mit E-Mail und Passwort."
        static let profileChanged = "Profil gewechselt: Die Vorschau gehört zu einem anderen Profil. Nichts wurde übernommen."
        static let scopeChanged = "Profil oder Einstellungen wurden währenddessen geändert. Bitte erneut laden."
        static let noCollections = "Import: Im Nuvio-Profil sind keine Collections."
        static let otherLink = "Import: Dieser Eintrag gehört zu einem anderen Nuvio-Konto oder -Profil."
        static let accountChanged = "Nuvio-Konto oder -Profil wurde währenddessen geändert. Nichts wurde übernommen."
        static func noProfile(_ name: String) -> String { "Nuvio-Profil für „\(name)“ wählen." }
    }

    /// Entry point of the settings row: loads addons and collections of the chosen account profile and builds the
    /// preview in `NuvioImportStore.shared`. Without a session or a chosen profile it only reports that state.
    func nuvioImportPreview() async {
        let ui = NuvioImportStore.shared
        guard !ui.busy else { return }
        ui.reset()
        ui.phase = .loading
        let target = profile.id   // A9
        let scope = scopes.current
        let context: NuvioImportContext
        switch await nuvioImportContext(target) {
        case .failure(let f): ui.phase = f.phase; return
        case .success(let c): context = c
        }
        do {
            let rows = try await context.client.addons(profile: context.source.addonProfileIndex, context.session)
            let data = try await context.client.collections(profile: context.source.profileIndex, context.session)
            let parsed = try NuvioImport.parse(data)
            guard scopeStillCurrent(scope, "Nuvio-Import") else { ui.phase = .failed(NuvioImportText.scopeChanged); return }
            let candidates = NuvioAccountImport.candidates(localAddons: profile.addons, accountAddons: rows)
            let fetched = await nuvioLoadManifests(candidates)
            guard scopeStillCurrent(scope, "Nuvio-Import") else { ui.phase = .failed(NuvioImportText.scopeChanged); return }
            let previous = CollectionLinkStore.shared.accountSnapshot(context.source.link, model: self)
            // Review 3, finding 6: marks of addons no longer installed (removed by hand, restore) go first.
            let originStore = NuvioImportOriginStore(storage: progressStore.storage)
            var origin = originStore.load(target)
            if origin.prune(installedAddons: profile.addons) { nuvioSaveOrigin(origin, originStore, target) }
            let preview = NuvioAccountImport.plan(
                localAddons: profile.addons, localCollections: profile.collections, source: context.source,
                accountAddons: rows, accountCollections: parsed.collections, origin: origin,
                manifests: fetched.mapValues(\.manifest), previousMedia: previous)
            ui.pending = NuvioImportStore.Pending(profile: target, source: context.source, collections: data, fetched: fetched)
            ui.preview = preview
            ui.install = Set(preview.addons.filter(\.chosenByDefault).map(\.instanceID))
            ui.takeCollections = preview.collectionsToImport
            ui.phase = .ready
            RemoteLog.info("nuvio", "Import-Vorschau: \(preview.addons.count) Addons, \(fetched.count) Manifeste, "
                + "\(preview.removedOnAccount.count) am Konto entfernt, \(preview.collections.count) Collections")
        } catch {
            ui.phase = .failed(NuvioAccountImport.errorText(error))
            RemoteLog.info("nuvio", "Import-Vorschau fehlgeschlagen: \(Self.nuvioImportLogReason(error))")
        }
    }

    /// "Übernehmen": installs the chosen addons (appended, in account order), removes only the chosen "am Konto
    /// entfernt" ones, records the origin (A7), then merges the collections through the link store (A1, A2).
    /// After a profile switch nothing is applied (A9).
    func nuvioImportApply() async {
        let ui = NuvioImportStore.shared
        guard ui.phase == .ready, let pending = ui.pending, let preview = ui.preview else { return }
        guard profile.id == pending.profile, scopes.current.profile == pending.profile else {
            ui.phase = .failed(NuvioImportText.profileChanged)
            RemoteLog.info("nuvio", "Import nicht übernommen: Profil gewechselt")
            return
        }
        // Review 3, finding 7: the preview belongs to one account and account profile; signed out or changed
        // meanwhile, nothing is applied.
        guard NuvioAccountImport.currentLink(sessionUser: nuvioSession?.userID,
                                             state: nuvioState(for: pending.profile)) == pending.source.link else {
            ui.phase = .failed(NuvioImportText.accountChanged)
            RemoteLog.info("nuvio", "Import nicht übernommen: Konto oder Konto-Profil gewechselt")
            return
        }
        ui.phase = .applying
        let target = pending.profile
        let install = preview.addons.filter { $0.installable && ui.install.contains($0.instanceID) }
            .compactMap { pending.fetched[$0.instanceID] }
        let remove = Set(preview.removedOnAccount.map(\.instanceID)).intersection(ui.remove)
        var added: [String] = []
        if !install.isEmpty || !remove.isEmpty {
            update(profile: target) { p in
                let r = NuvioAccountImport.applyAddons(p.addons, install: install, remove: remove)
                p.addons = r.addons
                added = r.added
            }
            clearCatalogCache()
        }
        let originStore = NuvioImportOriginStore(storage: progressStore.storage)
        var origin = originStore.load(target)
        origin.noteAddons(added, source: pending.source.addonSource)
        origin.forgetAddons(remove)
        if let p = stored.profiles.first(where: { $0.id == target }) {
            origin.prune(installed: Set(p.addons.flatMap { [$0.instanceID, AddonIdentity.instanceID(manifestURL: $0.manifestURL)] }))
        }
        nuvioSaveOrigin(origin, originStore, target)
        var parts: [String] = []
        if !added.isEmpty { parts.append(added.count == 1 ? "1 Addon installiert" : "\(added.count) Addons installiert") }
        if !remove.isEmpty { parts.append(remove.count == 1 ? "1 Addon entfernt" : "\(remove.count) Addons entfernt") }
        RemoteLog.info("nuvio", "Import übernommen: \(added.count) Addons installiert, \(remove.count) entfernt")
        if ui.takeCollections, preview.collectionsToImport {
            lastError = nil
            notice = nil
            await nuvioImportCollections(pending.collections, source: pending.source, profile: target)
            if let e = lastError { parts.append(e) } else if let n = notice { parts.append("Collections: " + n) }
        }
        ui.phase = .done(parts.isEmpty ? "Nichts übernommen." : parts.joined(separator: " · "))
    }

    /// "Aktualisieren" of the stored account entry in the import list: collections only, straight through the
    /// refresh path (no addon changes). An entry of another account or account profile is not loaded.
    func nuvioRefreshAccountCollections(link: String) async {
        let target = profile.id
        let context: NuvioImportContext
        switch await nuvioImportContext(target) {
        case .failure(let f):
            switch f.phase {
            case .signedOut: lastError = "Import: " + NuvioImportText.signedOut
            case .noProfile: lastError = "Import: " + NuvioImportText.noProfile(profile.name)
            case .failed(let text): lastError = text.hasPrefix("Import") ? text : "Import: " + text
            default: break
            }
            return
        case .success(let c): context = c
        }
        guard context.source.link == link else { lastError = NuvioImportText.otherLink; return }
        do {
            let data = try await context.client.collections(profile: context.source.profileIndex, context.session)
            guard profile.id == target else { lastError = "Import: " + NuvioImportText.profileChanged; return }
            await nuvioImportCollections(data, source: context.source, profile: target)
        } catch {
            let text = NuvioAccountImport.errorText(error)
            lastError = text.hasPrefix("Import") ? text : "Import: " + text
        }
    }

    // MARK: Pieces

    struct NuvioImportContext {
        let session: NuvioSession
        let source: NuvioAccountSource
        let client: NuvioClient
    }

    /// Session, chosen profile (checked against a fresh profile list, A3) and client, or the page state to show.
    private func nuvioImportContext(_ target: UUID) async -> Result<NuvioImportContext, NuvioImportFailure> {
        // Session, state and renewal are the shared ones of `AppModel+Nuvio` (single-flight refresh), so an import
        // and a sync pass never race over the rotating refresh token.
        guard var session = nuvioSession else { return .failure(.init(.signedOut)) }
        let state = nuvioState(for: target)
        // Review 3, finding 7: a choice made for another account does not count.
        guard let index = NuvioAccountImport.chosenIndex(sessionUser: session.userID, state: state) else {
            return .failure(.init(.noProfile))
        }
        let client = nuvioClient()
        if session.needsRefresh() {
            switch await renewNuvio(after: session) {
            case .renewed(let fresh): session = fresh
            case .refused: return .failure(.init(.failed(NuvioAccountImport.errorText(NuvioError.signedOut))))
            case .unavailable: break   // the 401 path tries once more
            }
        }
        do {
            let profiles = try await client.profiles(session)
            guard case .ok(let p) = state.matches(profiles) else { return .failure(.init(.noProfile)) }
            let source = NuvioAccountSource(userID: session.userID, profileIndex: index,
                                            usesPrimaryAddons: p?.usesPrimaryAddons ?? false)
            return .success(NuvioImportContext(session: session, source: source, client: client))
        } catch {
            RemoteLog.info("nuvio", "Import: Profile nicht geladen: \(Self.nuvioImportLogReason(error))")
            return .failure(.init(.failed(NuvioAccountImport.errorText(error))))
        }
    }

    struct NuvioImportFailure: Error {
        let phase: NuvioImportStore.Phase
        init(_ phase: NuvioImportStore.Phase) { self.phase = phase }
    }

    /// Manifests of the candidates, all at once (a handful of addons). A failed load is left out: the preview shows
    /// "Manifest nicht geladen" for it. No address in the log.
    private func nuvioLoadManifests(_ rows: [NuvioAddon]) async -> [String: InstalledAddon] {
        guard !rows.isEmpty else { return [:] }
        let client = addons
        let loaded: [String: InstalledAddon] = await withTaskGroup(of: (String, InstalledAddon?).self) { group in
            for r in rows {
                let url = r.url
                group.addTask { (AddonIdentity.instanceID(manifestURL: url), try? await client.install(manifestURL: url)) }
            }
            var out: [String: InstalledAddon] = [:]
            for await (id, a) in group { if let a { out[id] = a } }
            return out
        }
        if loaded.count < rows.count {
            RemoteLog.info("nuvio", "Import: \(rows.count - loaded.count) von \(rows.count) Manifesten nicht geladen")
        }
        return loaded
    }

    /// Collections through the link store's refresh path, merged id first (A1) into `target`.
    private func nuvioImportCollections(_ data: Data, source: NuvioAccountSource, profile target: UUID) async {
        guard let parsed = try? NuvioImport.parse(data) else {
            lastError = NuvioAccountImport.errorText(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")))
            return
        }
        guard !parsed.collections.isEmpty else { lastError = nil; notice = NuvioImportText.noCollections; return }
        await CollectionLinkStore.shared.importAccount(data, link: source.link, model: self) { [self] fresh, previous in
            nuvioMergeAccountCollections(fresh, previous: previous, source: source, profile: target)
        }
    }

    private func nuvioMergeAccountCollections(_ fresh: NuvioImportResult, previous: [String: FolderMedia]?,
                                              source: NuvioAccountSource, profile target: UUID) -> NuvioImportResult {
        let originStore = NuvioImportOriginStore(storage: progressStore.storage)
        var origin = originStore.load(target)
        var merged: NuvioCollectionMerge?
        update(profile: target) { p in
            let m = NuvioAccountImport.mergeCollections(local: p.collections, fresh: fresh.collections, source: source,
                                                        origin: origin, previous: previous)
            p.collections = m.collections
            merged = m
        }
        guard let m = merged else { return fresh }
        origin.noteCollections(m.marks)
        nuvioSaveOrigin(origin, originStore, target)
        let byTitle = m.items.filter { $0.status == .matchedByTitle }.count
        RemoteLog.info("nuvio", "Import: \(m.items.count) Collections, \(byTitle) über den Titel zugeordnet")
        var out = fresh
        out.collections = m.imported
        return out
    }

    /// Review 3, finding 6: an addon removed by hand (addon settings) loses its account mark at once, so the same
    /// addon installed again by hand is never offered under "am Konto entfernt".
    func nuvioForgetAddonOrigin(_ addon: InstalledAddon) {
        let target = profile.id
        let originStore = NuvioImportOriginStore(storage: progressStore.storage)
        var origin = originStore.load(target)
        guard origin.forget(addon) else { return }
        nuvioSaveOrigin(origin, originStore, target)
    }

    private func nuvioSaveOrigin(_ o: NuvioImportOrigin, _ store: NuvioImportOriginStore, _ target: UUID) {
        do { try store.save(o, profile: target) } catch {
            RemoteLog.error("nuvio", "Import: Herkunft nicht gespeichert")
        }
    }

    /// Kind of failure for the log only (status and short code, never a body, address or id).
    private static func nuvioImportLogReason(_ e: Error) -> String {
        switch e {
        case NuvioError.status(let s, _): return "HTTP \(s)"
        case let n as NuvioError: return "\(n)"
        case is DecodingError: return "Collections unlesbar"
        default: return "Netz"
        }
    }
}
