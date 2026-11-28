import Foundation

// Nuvio account sync, T10: collections and addons of the account through one preview (plan section 1.10, addendum
// A1, A2, A5, A6, A7, A9, owner decision D2). Everything here is pure: the app fetches, calls `plan`, shows the
// preview, and on "Übernehmen" calls `applyAddons` / `mergeCollections` and records the origin. Nothing is ever
// written back to the account. Addon addresses can carry access keys: they are kept in memory for the install only,
// `description` of every type here shows names and hosts, never an address or the account user id.

// MARK: - Account source

/// Which account and which account profile an import reads (A2). The user id is kept only as a short hash: the
/// pseudo-link ends up in the stored link list (part of the sealed backup) and the namespaced collection ids end up
/// in `profiles.json` (part of every backup), so the raw id must not be in either.
public struct NuvioAccountSource: Equatable, Sendable, CustomStringConvertible {
    /// `NuvioImport.stableHash` of the account user id.
    public let userKey: String
    /// Chosen account profile (1…6): collections are per profile.
    public let profileIndex: Int
    /// Account profile the addons are read from: 1 when the chosen profile `usesPrimaryAddons`.
    public let addonProfileIndex: Int

    public init(userID: String, profileIndex: Int, usesPrimaryAddons: Bool) {
        userKey = NuvioImport.stableHash("nuvio-user:" + userID)
        self.profileIndex = profileIndex
        addonProfileIndex = usesPrimaryAddons ? 1 : profileIndex
    }

    /// Stable pseudo-link of the collection import (A2): a second load is the refresh of the stored entry.
    public var link: String { NuvioAccountImport.linkPrefix + "\(userKey):\(profileIndex)" }

    /// Namespaced local id of an account collection (A1).
    public func collectionID(_ accountCollectionID: String) -> String {
        "nuvio:\(userKey):\(profileIndex):\(accountCollectionID)"
    }

    /// Origin tag of addons read for this source (an addon imported from profile 2 is not "removed" on profile 3).
    public var addonSource: String { "\(userKey):\(addonProfileIndex)" }

    public var description: String { "NuvioAccountSource(profileIndex: \(profileIndex), addons: \(addonProfileIndex))" }
}

// MARK: - Origin marker (A7)

/// What came from the account, per local profile: blob `nuvioimport-<profile uuid>.json` next to the Nuvio state.
/// `ProfileBlocks.belongs` matches the name, so it goes with its profile; it is not part of `Profile`, `profiles.json`
/// or `Backup`. Only addon instance ids (hashes) and collection ids, no address.
public struct NuvioImportOrigin: Codable, Equatable, Sendable {
    public struct AddonMark: Codable, Hashable, Sendable {
        /// `AddonIdentity.instanceID` of the installed addon.
        public var instanceID: String
        /// `NuvioAccountSource.addonSource` it was read from.
        public var source: String
        public init(instanceID: String, source: String) { self.instanceID = instanceID; self.source = source }
    }

    public struct CollectionMark: Codable, Hashable, Sendable {
        /// `NuvioAccountSource.collectionID` of the account collection.
        public var accountID: String
        /// Id of the local collection it was merged into (the namespaced id, or the id of a title match).
        public var localID: String
        /// Title as last imported (a local title equal to it may follow a rename on the account).
        public var title: String
        public init(accountID: String, localID: String, title: String) {
            self.accountID = accountID; self.localID = localID; self.title = title
        }
    }

    public var addons: [AddonMark] = []
    public var collections: [CollectionMark] = []

    public init(addons: [AddonMark] = [], collections: [CollectionMark] = []) {
        self.addons = addons; self.collections = collections
    }

    enum CodingKeys: String, CodingKey { case addons, collections }

    /// Lenient: an unreadable mark is dropped alone, an unreadable list is empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addons = ((try? c.decodeIfPresent([Lossy<AddonMark>].self, forKey: .addons)) ?? nil)?.compactMap(\.value) ?? []
        collections = ((try? c.decodeIfPresent([Lossy<CollectionMark>].self, forKey: .collections)) ?? nil)?
            .compactMap(\.value) ?? []
    }

    public func isMarked(_ instanceID: String) -> Bool { addons.contains { $0.instanceID == instanceID } }

    /// Marks addons installed from `source` (one mark per instance id; the newest source wins).
    public mutating func noteAddons(_ instanceIDs: [String], source: String) {
        for id in instanceIDs {
            addons.removeAll { $0.instanceID == id }
            addons.append(AddonMark(instanceID: id, source: source))
        }
    }

    public mutating func forgetAddons(_ instanceIDs: Set<String>) { addons.removeAll { instanceIDs.contains($0.instanceID) } }

    /// Marks of addons that are no longer installed go (removed by hand: never offered again).
    public mutating func prune(installed: Set<String>) { addons.removeAll { !installed.contains($0.instanceID) } }

    /// `prune(installed:)` against the installed addons (both forms of each identity). True when a mark went.
    @discardableResult
    public mutating func prune(installedAddons: [InstalledAddon]) -> Bool {
        let before = addons.count
        prune(installed: Set(installedAddons.flatMap(NuvioAccountImport.identities)))
        return addons.count != before
    }

    /// An addon removed by hand (review 3, finding 6): its mark goes at once, so the same addon installed again by
    /// hand later is the user's own and never offered under "am Konto entfernt". True when a mark went.
    @discardableResult
    public mutating func forget(_ addon: InstalledAddon) -> Bool {
        let before = addons.count
        forgetAddons(NuvioAccountImport.identities(addon))
        return addons.count != before
    }

    /// Adds or replaces the marks by `accountID`.
    public mutating func noteCollections(_ marks: [CollectionMark]) {
        for m in marks {
            collections.removeAll { $0.accountID == m.accountID }
            collections.append(m)
        }
    }
}

/// Reads and writes `nuvioimport-<profile uuid>.json`.
public struct NuvioImportOriginStore: Sendable {
    public let storage: BlobStorage
    public init(storage: BlobStorage) { self.storage = storage }

    public static func name(_ profile: UUID) -> String { "nuvioimport-\(profile.uuidString).json" }

    /// Missing or unreadable: empty (nothing is offered for removal then, which is the safe side).
    public func load(_ profile: UUID) -> NuvioImportOrigin {
        guard let d = storage.read(Self.name(profile)) else { return NuvioImportOrigin() }
        return (try? JSONDecoder().decode(NuvioImportOrigin.self, from: d)) ?? NuvioImportOrigin()
    }

    public func save(_ o: NuvioImportOrigin, profile: UUID) throws {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        try storage.write(Self.name(profile), try e.encode(o))
    }

    public func remove(_ profile: UUID) { storage.remove(Self.name(profile)) }
}

// MARK: - Preview

public struct NuvioImportPreview: Equatable, Sendable, CustomStringConvertible {
    public enum AddonStatus: Equatable, Sendable {
        /// Not installed: offered, chosen by default.
        case new
        /// Same `AddonIdentity.instanceID` is installed.
        case installed
        /// Only the public manifest address matches an installed addon (A5): offered in addition, not chosen.
        case otherConfiguration(localName: String)
        /// The address is not an addon address.
        case invalidAddress
        /// The manifest could not be loaded for the preview: not installable in this pass.
        case manifestUnavailable
    }

    /// One enabled addon row of the account, in account `sort_order`.
    public struct AccountAddon: Equatable, Sendable, Identifiable, CustomStringConvertible {
        public var id: String { instanceID }
        public let instanceID: String
        public let name: String
        public let host: String
        /// Full address for the install; never shown, never logged.
        public let url: String
        public let status: AddonStatus
        /// Name of the earlier addon with the same `manifest.id` (A6): collection catalog sources resolve to that one.
        public let sharesManifestIDWith: String?

        public var installable: Bool {
            switch status {
            case .new, .otherConfiguration: true
            case .installed, .invalidAddress, .manifestUnavailable: false
            }
        }
        public var chosenByDefault: Bool { status == .new }
        public var description: String { "AccountAddon(\(name), \(host), \(status))" }
    }

    /// An installed addon with the account origin marker (D2).
    public struct LocalAddon: Equatable, Sendable, Identifiable {
        public var id: String { instanceID }
        public let instanceID: String
        public let name: String
        public let host: String
    }

    public enum CollectionStatus: Equatable, Sendable {
        case new
        /// Matched by id (namespaced id or origin mark), the import changes it.
        case update
        /// Matched by id, the import would change nothing.
        case unchanged
        /// No id match; a local collection with the same title (e.g. from a pasted code) takes it (A1).
        case matchedByTitle
    }

    public struct AccountCollection: Equatable, Sendable, Identifiable {
        public var id: String { accountID }
        public let accountID: String
        /// Title the collection has (or gets) locally.
        public let title: String
        public let localID: String?
        public let status: CollectionStatus
        public let folders: Int
    }

    /// Enabled account addons in account order.
    public var addons: [AccountAddon]
    /// Imported earlier, no longer on the account (D2): removal only by the user's choice.
    public var removedOnAccount: [LocalAddon]
    /// Imported earlier, now disabled on the account (D2): shown, never offered for removal.
    public var disabledOnAccount: [LocalAddon]
    /// Disabled account rows that are not imported (and not installed here).
    public var disabledSkipped: Int
    public var collections: [AccountCollection]

    /// The account brings nothing new: no new addon, nothing removed, every collection unchanged. Addons in another
    /// configuration are optional extras and do not count; an addon whose manifest did not load does.
    public var nothingToDo: Bool {
        !addons.contains { $0.status == .new || $0.status == .manifestUnavailable }
            && removedOnAccount.isEmpty
            && !collections.contains { $0.status != .unchanged }
    }

    /// Collections that "Übernehmen" changes.
    public var collectionsToImport: Bool { collections.contains { $0.status != .unchanged } }

    public var description: String {
        "NuvioImportPreview(addons: \(addons.count), removed: \(removedOnAccount.count), "
            + "disabled: \(disabledOnAccount.count), collections: \(collections.count))"
    }
}

// MARK: - Planning and applying

/// Result of merging account collections into the local list.
public struct NuvioCollectionMerge: Equatable, Sendable {
    /// The new local collection list (existing order kept, new ones appended).
    public var collections: [MediaCollection]
    /// The account collections as they are stored locally (local id and title): for the media snapshot and the
    /// result line of the link store.
    public var imported: [MediaCollection]
    public var marks: [NuvioImportOrigin.CollectionMark]
    public var items: [NuvioImportPreview.AccountCollection]
}

public enum NuvioAccountImport {
    public static let linkPrefix = "nuvio-account:"

    public static func isAccountLink(_ link: String?) -> Bool { link?.hasPrefix(linkPrefix) ?? false }

    /// The account profile an import may read for a local profile (review 3, finding 7): the chosen index, only
    /// while the state belongs to the session's account (a state of another account counts as no choice).
    public static func chosenIndex(sessionUser: String, state: NuvioState) -> Int? {
        guard state.userID == sessionUser else { return nil }
        return state.profileIndex
    }

    /// The pseudo-link (A2) of the account entry that can be loaded now; nil when signed out or no profile of the
    /// session's account is chosen. A preview is applied and a stored entry refreshed only while this matches its
    /// link (review 3, findings 7 and 8).
    public static func currentLink(sessionUser: String?, state: NuvioState) -> String? {
        guard let user = sessionUser, let index = chosenIndex(sessionUser: user, state: state) else { return nil }
        return NuvioAccountSource(userID: user, profileIndex: index, usesPrimaryAddons: false).link
    }

    /// "Alle aktualisieren" (review 3, finding 8): stored links in order without the account entries that are not
    /// `current` (signed out, another account or account profile), and how many were left out.
    public static func refreshable(_ links: [String], current: String?) -> (links: [String], skipped: Int) {
        let kept = links.filter { !isAccountLink($0) || $0 == current }
        return (kept, links.count - kept.count)
    }

    /// The notice after "Alle aktualisieren" with `skipped` account entries left out: appended to the result line
    /// of the other links when they set one (`notice` differs from `before`), else alone. nil: leave it as it is.
    public static func skippedNotice(_ skipped: Int, notice: String?, before: String?) -> String? {
        guard skipped > 0 else { return nil }
        let text = (skipped == 1 ? "1 Nuvio-Konto-Eintrag" : "\(skipped) Nuvio-Konto-Einträge")
            + " übersprungen (nicht angemeldet oder anderes Konto/Profil)."
        if let n = notice, !n.isEmpty, n != before { return n + " · " + text }
        return text
    }

    /// The account profile addons are read from: 1 when the chosen profile shares the primary addons (plan 7.9).
    public static func addonProfileIndex(chosen: Int, profiles: [NuvioProfile]) -> Int {
        profiles.first { $0.profileIndex == chosen }?.usesPrimaryAddons == true ? 1 : chosen
    }

    /// Host of an addon address for display (no user info, path or query); "?" when unreadable.
    public static func host(_ url: String) -> String {
        guard let base = AddonClient.parseManifest(url)?.base, let h = URL(string: base)?.host, !h.isEmpty else { return "?" }
        return h.lowercased()
    }

    /// Enabled account rows in `sort_order` (stable), one per instance id (the first wins).
    static func enabledRows(_ rows: [NuvioAddon]) -> [NuvioAddon] {
        var seen = Set<String>()
        return rows.enumerated()
            .sorted { ($0.element.sortOrder, $0.offset) < ($1.element.sortOrder, $1.offset) }
            .map(\.element)
            .filter { $0.enabled && seen.insert(AddonIdentity.instanceID(manifestURL: $0.url)).inserted }
    }

    /// Both forms of a local addon's identity (stored and derived), so an explicitly set id does not hide a match.
    static func identities(_ a: InstalledAddon) -> Set<String> {
        [a.instanceID, AddonIdentity.instanceID(manifestURL: a.manifestURL)]
    }

    /// Local addon with the same instance id.
    static func installed(_ instanceID: String, in local: [InstalledAddon]) -> InstalledAddon? {
        local.first { identities($0).contains(instanceID) }
    }

    /// Local addon whose public manifest address equals the row's (A5), when no instance id matched.
    static func samePublicAddress(_ url: String, in local: [InstalledAddon]) -> InstalledAddon? {
        let p = AddonAccess.publicManifestURL(url)
        guard !p.isEmpty else { return nil }
        return local.first { AddonAccess.publicManifestURL($0.manifestURL) == p }
    }

    /// Account rows whose manifest the app loads for the preview: enabled, readable address, not installed.
    public static func candidates(localAddons: [InstalledAddon], accountAddons: [NuvioAddon]) -> [NuvioAddon] {
        enabledRows(accountAddons).filter { r in
            AddonClient.parseManifest(r.url) != nil
                && installed(AddonIdentity.instanceID(manifestURL: r.url), in: localAddons) == nil
        }
    }

    /// The whole preview. `manifests`: instance id → manifest loaded for a candidate (nil = not loaded at all: no
    /// "manifest unavailable" status and no shared-id check for account entries; a missing key in a non-nil map =
    /// the load failed). `previousMedia`: media snapshot of the stored account link (nil = first import), as the
    /// link store's refresh path uses it.
    public static func plan(localAddons: [InstalledAddon], localCollections: [MediaCollection],
                            source: NuvioAccountSource, accountAddons: [NuvioAddon], accountCollections: [MediaCollection],
                            origin: NuvioImportOrigin, manifests: [String: AddonManifest]? = nil,
                            previousMedia: [String: FolderMedia]? = nil) -> NuvioImportPreview {
        // Addons in account order.
        struct Row { var instanceID: String; var row: NuvioAddon; var status: NuvioImportPreview.AddonStatus; var manifestID: String? }
        var rows: [Row] = []
        for r in enabledRows(accountAddons) {
            let id = AddonIdentity.instanceID(manifestURL: r.url)
            if AddonClient.parseManifest(r.url) == nil {
                rows.append(Row(instanceID: id, row: r, status: .invalidAddress, manifestID: nil))
            } else if let a = installed(id, in: localAddons) {
                rows.append(Row(instanceID: id, row: r, status: .installed, manifestID: a.manifest.id))
            } else {
                let m = manifests?[id]
                var status: NuvioImportPreview.AddonStatus = .new
                if let other = samePublicAddress(r.url, in: localAddons) { status = .otherConfiguration(localName: other.manifest.name) }
                if manifests != nil, m == nil { status = .manifestUnavailable }
                rows.append(Row(instanceID: id, row: r, status: status, manifestID: m?.id))
            }
        }
        // A6: catalog sources resolve to the first addon with a manifest id (installed order, then appended ones).
        var firstByManifest: [String: (instanceID: String, name: String)] = [:]
        for a in localAddons where firstByManifest[a.manifest.id] == nil {
            firstByManifest[a.manifest.id] = (a.instanceID, a.manifest.name)
        }
        for r in rows where r.status != .installed {
            guard let mid = r.manifestID, firstByManifest[mid] == nil, let m = manifests?[r.instanceID] else { continue }
            firstByManifest[mid] = (r.instanceID, displayName(r.row, manifest: m))
        }
        let addons = rows.map { r -> NuvioImportPreview.AccountAddon in
            var shares: String?
            if let mid = r.manifestID, let first = firstByManifest[mid] {
                let own = installed(r.instanceID, in: localAddons).map(identities) ?? [r.instanceID]
                if !own.contains(first.instanceID) { shares = first.name }
            }
            return .init(instanceID: r.instanceID, name: displayName(r.row, manifest: manifests?[r.instanceID]),
                         host: host(r.row.url), url: r.row.url, status: r.status, sharesManifestIDWith: shares)
        }

        // D2: earlier imports of this source.
        var onAccount: [String: Bool] = [:]   // instance id → enabled (any row of the id enabled)
        for r in accountAddons {
            let id = AddonIdentity.instanceID(manifestURL: r.url)
            onAccount[id] = (onAccount[id] ?? false) || r.enabled
        }
        var removed: [NuvioImportPreview.LocalAddon] = []
        var disabled: [NuvioImportPreview.LocalAddon] = []
        var reported = Set<String>()
        for mark in origin.addons where mark.source == source.addonSource && reported.insert(mark.instanceID).inserted {
            guard let a = installed(mark.instanceID, in: localAddons) else { continue }
            let item = NuvioImportPreview.LocalAddon(instanceID: mark.instanceID, name: a.manifest.name, host: host(a.manifestURL))
            switch onAccount[mark.instanceID] {
            case nil: removed.append(item)
            case false?: disabled.append(item)
            case true?: break
            }
        }
        let skipped = Set(accountAddons.filter { !$0.enabled }.map { AddonIdentity.instanceID(manifestURL: $0.url) })
            .filter { onAccount[$0] == false && installed($0, in: localAddons) == nil }.count

        let merge = mergeCollections(local: localCollections, fresh: accountCollections, source: source, origin: origin,
                                     previous: previousMedia)
        return NuvioImportPreview(addons: addons, removedOnAccount: removed, disabledOnAccount: disabled,
                                  disabledSkipped: skipped, collections: merge.items)
    }

    static func displayName(_ r: NuvioAddon, manifest: AddonManifest?) -> String {
        if let n = r.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        if let n = manifest?.name, !n.isEmpty { return n }
        return host(r.url)
    }

    /// The local addon list after "Übernehmen": `remove` (instance ids, only ones the user chose) go, `install`
    /// (manifests loaded for the preview, in account order) are appended unless their instance id is installed by
    /// now. Nothing is reordered. Returns the instance ids that were added.
    public static func applyAddons(_ local: [InstalledAddon], install: [InstalledAddon],
                                   remove: Set<String>) -> (addons: [InstalledAddon], added: [String]) {
        var out = local.filter { identities($0).isDisjoint(with: remove) }
        var added: [String] = []
        for a in install {
            let id = a.instanceID
            guard installed(id, in: out) == nil else { continue }
            out.append(a)
            added.append(id)
        }
        return (out, added)
    }

    /// Merges the account collections (A1): by id first (the namespaced id, or the local id an origin mark names),
    /// then by title (an earlier pasted-code import of the same collection is taken over, not duplicated, and is
    /// reported as `matchedByTitle`), else appended under the namespaced id. A matched collection keeps its local
    /// id; its title follows an account rename only while the local title is still the one last imported. Folders
    /// merge as the link store does: with `previous` (refresh) the fresh media addresses win unless the user changed
    /// them (`NuvioImport.refreshFolders`), without it only gaps are filled (`NuvioImport.mergeFolders`).
    public static func mergeCollections(local: [MediaCollection], fresh: [MediaCollection], source: NuvioAccountSource,
                                        origin: NuvioImportOrigin,
                                        previous: [String: FolderMedia]?) -> NuvioCollectionMerge {
        var out = local
        var claimed = Set<Int>()
        var usedIDs = Set<String>()
        var imported: [MediaCollection] = []
        var marks: [NuvioImportOrigin.CollectionMark] = []
        var items: [NuvioImportPreview.AccountCollection] = []
        let markByID = Dictionary(origin.collections.map { ($0.accountID, $0) }) { a, _ in a }

        for c in fresh {
            var accountID = source.collectionID(c.id)
            if !usedIDs.insert(accountID).inserted {
                accountID += ":" + NuvioImport.stableHash(c.title)
                usedIDs.insert(accountID)
            }
            let mark = markByID[accountID]
            var index: Int?
            var byTitle = false
            if let m = mark, let i = out.indices.first(where: { !claimed.contains($0) && out[$0].id == m.localID }) {
                index = i
            } else if let i = out.indices.first(where: { !claimed.contains($0) && out[$0].id == accountID }) {
                index = i
            } else if let i = out.indices.first(where: { !claimed.contains($0) && out[$0].title == c.title }) {
                index = i
                byTitle = true
            }
            guard let i = index else {
                let added = MediaCollection(id: accountID, title: c.title, folders: NuvioImport.mergeFolders([], c.folders))
                out.append(added)
                claimed.insert(out.count - 1)
                imported.append(MediaCollection(id: accountID, title: c.title, folders: c.folders))
                marks.append(.init(accountID: accountID, localID: accountID, title: c.title))
                items.append(.init(accountID: accountID, title: c.title, localID: nil, status: .new, folders: c.folders.count))
                continue
            }
            claimed.insert(i)
            let before = out[i]
            let oldTitle = before.title
            var title = oldTitle
            if !byTitle, let m = mark, m.title == oldTitle, c.title != oldTitle,
               !out.indices.contains(where: { $0 != i && out[$0].title == c.title }) {
                title = c.title   // renamed on the account, untouched here
            }
            out[i].folders = previous.map {
                NuvioImport.refreshFolders(before.folders, fresh: c.folders, collection: oldTitle, previous: $0)
            } ?? NuvioImport.mergeFolders(before.folders, c.folders)
            out[i].title = title
            imported.append(MediaCollection(id: before.id, title: title, folders: c.folders))
            marks.append(.init(accountID: accountID, localID: before.id, title: title))
            let status: NuvioImportPreview.CollectionStatus = byTitle ? .matchedByTitle : (out[i] == before ? .unchanged : .update)
            items.append(.init(accountID: accountID, title: title, localID: before.id, status: status,
                               folders: c.folders.count))
        }
        return NuvioCollectionMerge(collections: out, imported: imported, marks: marks, items: items)
    }

    // MARK: Texts

    /// German line for a failed account call (plan section 4); never an address, id or token.
    public static func errorText(_ e: Error) -> String {
        switch e {
        case NuvioError.signedOut: return "Nuvio: Sitzung abgelaufen. Bitte am Handy neu anmelden."
        case NuvioError.rateLimited: return "Nuvio: zu viele Anfragen. Der Abgleich pausiert einige Minuten."
        case NuvioError.status(403, _): return "Nuvio lehnt die Anfrage ab (403)."
        case NuvioError.status(let s, _): return "Nuvio antwortet mit Fehler \(s)."
        case NuvioError.decoding: return "Nuvio: Antwort unlesbar."
        case is DecodingError: return "Import: Collections des Nuvio-Kontos nicht lesbar."
        default: return "Nuvio nicht erreichbar. Bitte später erneut versuchen."
        }
    }
}
