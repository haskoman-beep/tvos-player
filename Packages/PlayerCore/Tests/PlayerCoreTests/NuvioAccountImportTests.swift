import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T10: preview and merge of account addons and collections (A1, A2, A5, A6, A7, A9, D2).
// Invented values only.

private let user = "00000000-0000-4000-8000-000000000001"
private let profileID = UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!

private func manifest(_ id: String, _ name: String) -> AddonManifest {
    AddonManifest(id: id, name: name, version: "1", resources: [], types: ["movie"])
}

private func local(_ url: String, _ id: String, _ name: String) -> InstalledAddon {
    InstalledAddon(manifestURL: url, manifest: manifest(id, name))
}

private func row(_ url: String, _ name: String? = nil, enabled: Bool = true, order: Int = 0) -> NuvioAddon {
    NuvioAddon(profileID: 1, url: url, name: name, enabled: enabled, sortOrder: order)
}

private func iid(_ url: String) -> String { AddonIdentity.instanceID(manifestURL: url) }

private func collection(_ id: String, _ title: String, folders: [(String, [String])]) -> MediaCollection {
    MediaCollection(id: id, title: title, folders: folders.map { f in
        Folder(id: "f." + f.0, title: f.0, sources: f.1.map {
            CatalogSource(id: $0, title: $0, kind: .addon(addonId: "a.b", catalogId: $0, type: "movie"), mediaType: .movie)
        })
    })
}

private let src = NuvioAccountSource(userID: user, profileIndex: 2, usesPrimaryAddons: false)

private func plan(local la: [InstalledAddon] = [], collections lc: [MediaCollection] = [], account aa: [NuvioAddon] = [],
                  accountCollections ac: [MediaCollection] = [], origin: NuvioImportOrigin = NuvioImportOrigin(),
                  manifests: [String: AddonManifest]? = nil, previous: [String: FolderMedia]? = nil,
                  source: NuvioAccountSource = src) -> NuvioImportPreview {
    NuvioAccountImport.plan(localAddons: la, localCollections: lc, source: source, accountAddons: aa,
                            accountCollections: ac, origin: origin, manifests: manifests, previousMedia: previous)
}

private final class MemoryBlobs: BlobStorage, @unchecked Sendable {
    private var blobs: [String: Data] = [:]
    private let lock = NSLock()
    func read(_ name: String) -> Data? { lock.withLock { blobs[name] } }
    func write(_ name: String, _ data: Data) throws { lock.withLock { blobs[name] = data } }
    func remove(_ name: String) { _ = lock.withLock { blobs.removeValue(forKey: name) } }
}

// MARK: Source, links, ids (A1, A2)

@Test func nuvioAccountSourceHidesUserID() {
    #expect(src.link.hasPrefix("nuvio-account:") && src.link.hasSuffix(":2"))
    #expect(!src.link.contains(user) && !src.collectionID("c1").contains(user))
    #expect(src.collectionID("c1").hasPrefix("nuvio:") && src.collectionID("c1").hasSuffix(":2:c1"))
    // Stable over calls, different per account and per profile.
    #expect(NuvioAccountSource(userID: user, profileIndex: 2, usesPrimaryAddons: false).link == src.link)
    #expect(NuvioAccountSource(userID: "other", profileIndex: 2, usesPrimaryAddons: false).link != src.link)
    #expect(NuvioAccountSource(userID: user, profileIndex: 3, usesPrimaryAddons: false).link != src.link)
    #expect(NuvioAccountImport.isAccountLink(src.link))
    #expect(!NuvioAccountImport.isAccountLink("https://example.org/x.json") && !NuvioAccountImport.isAccountLink(nil))
    #expect(!"\(src)".contains(src.userKey))
}

@Test func nuvioAccountUsesPrimaryAddons() throws {
    let profiles = try JSONDecoder().decode([NuvioProfile].self, from: Data(#"""
    [{"profile_index":1,"name":"Main","uses_primary_addons":false},
     {"profile_index":2,"name":"Kids","uses_primary_addons":true},
     {"profile_index":3,"name":"Own","uses_primary_addons":false}]
    """#.utf8))
    #expect(NuvioAccountImport.addonProfileIndex(chosen: 2, profiles: profiles) == 1)
    #expect(NuvioAccountImport.addonProfileIndex(chosen: 3, profiles: profiles) == 3)
    #expect(NuvioAccountImport.addonProfileIndex(chosen: 4, profiles: profiles) == 4)
    let shared = NuvioAccountSource(userID: user, profileIndex: 2, usesPrimaryAddons: true)
    #expect(shared.addonProfileIndex == 1 && shared.profileIndex == 2)
    // Collections stay per profile; addon origin is the primary profile.
    #expect(shared.link == src.link && shared.collectionID("c") == src.collectionID("c"))
    #expect(shared.addonSource != src.addonSource)
    #expect(shared.addonSource == NuvioAccountSource(userID: user, profileIndex: 1, usesPrimaryAddons: false).addonSource)
}

// MARK: Addons (A5, A6, D2)

@Test func nuvioAccountEmpty() {
    let p = plan(local: [local("https://a.example.org/manifest.json", "a", "A")])
    #expect(p.addons.isEmpty && p.collections.isEmpty && p.removedOnAccount.isEmpty && p.disabledOnAccount.isEmpty)
    #expect(p.disabledSkipped == 0 && p.nothingToDo && !p.collectionsToImport)
}

@Test func nuvioAccountAddonsNewInstalledInOrder() {
    let installedURL = "https://a.example.org/manifest.json"
    let newURL = "https://b.example.org/KEY0123456789abcdefghij/manifest.json"
    let p = plan(local: [local(installedURL, "a", "A")],
                 account: [row(newURL, "B", order: 1), row(installedURL + "/", order: 0), row("ftp://nope", order: 2)])
    #expect(p.addons.map(\.status) == [.installed, .new, .invalidAddress])
    #expect(p.addons[0].name == "a.example.org")   // no name on the row, no manifest: host
    #expect(p.addons[1].name == "B" && p.addons[1].host == "b.example.org")
    #expect(p.addons[1].chosenByDefault && p.addons[1].installable)
    #expect(!p.addons[0].installable && !p.addons[2].installable)
    #expect(!p.nothingToDo)
    // No address in any description.
    #expect(!"\(p)".contains("KEY0123") && !"\(p.addons[1])".contains("KEY0123"))
}

@Test func nuvioAccountCandidatesAndManifestFailure() {
    let installedURL = "https://a.example.org/manifest.json"
    let newURL = "https://b.example.org/manifest.json"
    let downURL = "https://c.example.org/manifest.json"
    let la = [local(installedURL, "a", "A")]
    let aa = [row(installedURL), row(newURL, order: 1), row(downURL, order: 2), row("not a url", order: 3),
              row("https://d.example.org/manifest.json", enabled: false, order: 4)]
    #expect(NuvioAccountImport.candidates(localAddons: la, accountAddons: aa).map(\.url) == [newURL, downURL])
    let p = plan(local: la, account: aa, manifests: [iid(newURL): manifest("b", "Bee")])
    #expect(p.addons.map(\.status) == [.installed, .new, .manifestUnavailable, .invalidAddress])
    #expect(p.addons[1].name == "Bee")   // manifest name when the row has none
    #expect(!p.addons[2].installable)
    #expect(!p.nothingToDo)   // retry needed
}

@Test func nuvioAccountOtherConfiguration() {
    // Same host and public path, other configuration in the query: not the same installation (A5).
    let mine = "https://cfg.example.org/manifest.json?v=mine"
    let theirs = "https://cfg.example.org/manifest.json?v=theirs"
    let p = plan(local: [local(mine, "cfg", "Config")], account: [row(theirs, "Config")],
                 manifests: [iid(theirs): manifest("cfg", "Config")])
    #expect(p.addons.map(\.status) == [.otherConfiguration(localName: "Config")])
    #expect(p.addons[0].installable && !p.addons[0].chosenByDefault)
    #expect(p.addons[0].sharesManifestIDWith == "Config")   // A6: catalogs resolve to the installed one
    #expect(p.nothingToDo)   // optional extra only
    // Applying installs it in addition; the existing one stays first.
    let fetched = local(theirs, "cfg", "Config")
    let r = NuvioAccountImport.applyAddons([local(mine, "cfg", "Config")], install: [fetched], remove: [])
    #expect(r.addons.map(\.manifestURL) == [mine, theirs] && r.added == [iid(theirs)])
}

@Test func nuvioAccountSharedManifestIDAmongNewAddons() {
    let one = "https://one.example.org/manifest.json"
    let two = "https://two.example.org/manifest.json"
    let three = "https://three.example.org/manifest.json"
    let p = plan(local: [local("https://x.example.org/manifest.json", "x", "X")],
                 account: [row(one, "One"), row(two, "Two", order: 1), row(three, "Three", order: 2)],
                 manifests: [iid(one): manifest("same", "One"), iid(two): manifest("same", "Two"),
                             iid(three): manifest("x", "Three")])
    #expect(p.addons.map(\.sharesManifestIDWith) == [nil, "One", "X"])
}

@Test func nuvioAccountInstalledAddonSharingLocalManifestID() {
    let a1 = "https://a1.example.org/manifest.json"
    let a2 = "https://a2.example.org/manifest.json"
    let p = plan(local: [local(a1, "m", "First"), local(a2, "m", "Second")], account: [row(a2), row(a1, order: 1)])
    #expect(p.addons.map(\.status) == [.installed, .installed])
    #expect(p.addons.map(\.sharesManifestIDWith) == ["First", nil])
}

@Test func nuvioAccountDuplicateRowsAndDisabled() {
    let u = "https://a.example.org/manifest.json"
    let p = plan(account: [row(u, "A"), row(u + "?", "A again", order: 1),
                           row("https://off.example.org/manifest.json", enabled: false, order: 2)])
    #expect(p.addons.count == 1 && p.addons[0].name == "A")
    #expect(p.disabledSkipped == 1 && p.disabledOnAccount.isEmpty)
}

@Test func nuvioAccountRemovedAndDisabledOnAccount() {
    let kept = "https://kept.example.org/manifest.json"
    let gone = "https://gone.example.org/manifest.json"
    let off = "https://off.example.org/manifest.json"
    let mine = "https://mine.example.org/manifest.json"
    let otherSource = "https://elsewhere.example.org/manifest.json"
    let uninstalled = "https://uninstalled.example.org/manifest.json"
    var origin = NuvioImportOrigin()
    origin.noteAddons([iid(kept), iid(gone), iid(off), iid(uninstalled)], source: src.addonSource)
    origin.noteAddons([iid(otherSource)], source: "other:1")
    let la = [local(kept, "k", "Kept"), local(gone, "g", "Gone"), local(off, "o", "Off"), local(mine, "m", "Mine"),
              local(otherSource, "e", "Elsewhere")]
    let p = plan(local: la, account: [row(kept), row(off, enabled: false, order: 1)], origin: origin)
    #expect(p.removedOnAccount.map(\.name) == ["Gone"])          // marker, not on the account
    #expect(p.removedOnAccount[0].host == "gone.example.org")
    #expect(p.disabledOnAccount.map(\.name) == ["Off"])          // marker, disabled: shown, not offered
    #expect(p.disabledSkipped == 0)                              // the disabled one is an earlier import
    #expect(p.addons.map(\.status) == [.installed])
    // "Mine" (user installed) and "Elsewhere" (another account profile) are never offered.
    #expect(!p.removedOnAccount.contains { $0.name == "Mine" || $0.name == "Elsewhere" })
    #expect(!p.nothingToDo)
    // Nothing goes without the choice; the chosen one goes, nothing else moves.
    #expect(NuvioAccountImport.applyAddons(la, install: [], remove: []).addons == la)
    let r = NuvioAccountImport.applyAddons(la, install: [], remove: [iid(gone)])
    #expect(r.addons.map(\.manifest.name) == ["Kept", "Off", "Mine", "Elsewhere"] && r.added.isEmpty)
}

@Test func nuvioAccountApplyAppendsInAccountOrderWithoutDuplicates() {
    let a = local("https://a.example.org/manifest.json", "a", "A")
    let b = local("https://b.example.org/manifest.json", "b", "B")
    let c = local("https://c.example.org/manifest.json", "c", "C")
    let r = NuvioAccountImport.applyAddons([a], install: [c, b, a, c], remove: [])
    #expect(r.addons.map(\.manifest.name) == ["A", "C", "B"])
    #expect(r.added == [c.instanceID, b.instanceID])
}

// MARK: Origin marker (A7)

@Test func nuvioImportOriginRoundTripAndPrune() throws {
    let blobs = MemoryBlobs()
    let store = NuvioImportOriginStore(storage: blobs)
    #expect(store.load(profileID) == NuvioImportOrigin())
    var o = NuvioImportOrigin()
    o.noteAddons(["addon-1", "addon-2"], source: "u:1")
    o.noteAddons(["addon-1"], source: "u:2")
    o.noteCollections([.init(accountID: "nuvio:u:1:c", localID: "x", title: "T")])
    o.noteCollections([.init(accountID: "nuvio:u:1:c", localID: "x", title: "T2")])
    #expect(o.addons == [.init(instanceID: "addon-2", source: "u:1"), .init(instanceID: "addon-1", source: "u:2")])
    #expect(o.collections.count == 1 && o.collections[0].title == "T2")
    try store.save(o, profile: profileID)
    #expect(store.load(profileID) == o)
    #expect(ProfileBlocks.belongs(NuvioImportOriginStore.name(profileID), to: profileID))
    #expect(NuvioImportOriginStore.name(profileID) != NuvioStateStore.name(profileID))
    o.prune(installed: ["addon-1"])
    #expect(o.addons.map(\.instanceID) == ["addon-1"] && o.isMarked("addon-1") && !o.isMarked("addon-2"))
    o.forgetAddons(["addon-1"])
    #expect(o.addons.isEmpty)
    // Lenient: one bad mark is dropped alone, garbage is empty.
    try blobs.write(NuvioImportOriginStore.name(profileID), Data(#"""
    {"addons":[{"instanceID":"addon-9","source":"u:1"},{"instanceID":5}],"collections":"kaputt","neu":1}
    """#.utf8))
    let l = store.load(profileID)
    #expect(l.addons.map(\.instanceID) == ["addon-9"] && l.collections.isEmpty)
    try blobs.write(NuvioImportOriginStore.name(profileID), Data("kaputt".utf8))
    #expect(store.load(profileID) == NuvioImportOrigin())
}

// MARK: Collections (A1)

@Test func nuvioAccountCollectionsNewThenUnchanged() {
    let fresh = [collection("c1", "Weekend", folders: [("Sci-Fi", ["top"])])]
    let first = NuvioAccountImport.mergeCollections(local: [], fresh: fresh, source: src, origin: NuvioImportOrigin(),
                                                    previous: nil)
    #expect(first.items.map(\.status) == [.new])
    #expect(first.collections.map(\.id) == [src.collectionID("c1")])
    #expect(first.imported.map(\.id) == [src.collectionID("c1")])
    var origin = NuvioImportOrigin()
    origin.noteCollections(first.marks)
    // Second load of the unchanged account: nothing to do.
    let p = plan(collections: first.collections, accountCollections: fresh, origin: origin,
                 previous: NuvioImport.media(of: first.imported))
    #expect(p.collections.map(\.status) == [.unchanged] && p.nothingToDo && !p.collectionsToImport)
    let again = NuvioAccountImport.mergeCollections(local: first.collections, fresh: fresh, source: src, origin: origin,
                                                    previous: [:])
    #expect(again.collections == first.collections)
}

@Test func nuvioAccountUnchangedAddonsAndCollectionsSecondLoad() {
    let u = "https://a.example.org/manifest.json"
    let fresh = [collection("c1", "Weekend", folders: [("Sci-Fi", ["top"])])]
    var origin = NuvioImportOrigin()
    let m = NuvioAccountImport.mergeCollections(local: [], fresh: fresh, source: src, origin: origin, previous: nil)
    origin.noteCollections(m.marks)
    origin.noteAddons([iid(u)], source: src.addonSource)
    let p = plan(local: [local(u, "a", "A")], collections: m.collections, account: [row(u, "A")],
                 accountCollections: fresh, origin: origin, manifests: [:], previous: [:])
    #expect(p.addons.map(\.status) == [.installed] && p.removedOnAccount.isEmpty && p.nothingToDo)
}

@Test func nuvioAccountCollectionUpdateAddsSources() {
    let id = src.collectionID("c1")
    let localC = [collection(id, "Weekend", folders: [("Sci-Fi", ["top"])])]
    let fresh = [collection("c1", "Weekend", folders: [("Sci-Fi", ["top", "new"]), ("Drama", ["d"])])]
    let r = NuvioAccountImport.mergeCollections(local: localC, fresh: fresh, source: src, origin: NuvioImportOrigin(),
                                                previous: nil)
    #expect(r.items.map(\.status) == [.update] && r.items[0].localID == id)
    #expect(r.collections.count == 1 && r.collections[0].folders.map(\.title) == ["Sci-Fi", "Drama"])
    #expect(r.collections[0].folders[0].sources.map(\.id) == ["top", "new"])
}

@Test func nuvioAccountRenameOnEitherSideNoDuplicate() {
    var origin = NuvioImportOrigin()
    let first = NuvioAccountImport.mergeCollections(local: [], fresh: [collection("c1", "Weekend", folders: [("F", ["a"])])],
                                                    source: src, origin: origin, previous: nil)
    origin.noteCollections(first.marks)
    // Renamed on the account, untouched here: the local title follows.
    let renamedRemote = NuvioAccountImport.mergeCollections(
        local: first.collections, fresh: [collection("c1", "Wochenende", folders: [("F", ["a"])])],
        source: src, origin: origin, previous: [:])
    #expect(renamedRemote.collections.map(\.title) == ["Wochenende"])
    #expect(renamedRemote.collections.count == 1 && renamedRemote.items.map(\.status) == [.update])
    // Renamed here: the local title stays, even when the account renames too.
    var mine = first.collections
    mine[0].title = "Meine Auswahl"
    for t in ["Weekend", "Wochenende"] {
        let r = NuvioAccountImport.mergeCollections(local: mine, fresh: [collection("c1", t, folders: [("F", ["a"])])],
                                                    source: src, origin: origin, previous: [:])
        #expect(r.collections.map(\.title) == ["Meine Auswahl"] && r.items.map(\.status) == [.unchanged])
        #expect(r.imported.map(\.title) == ["Meine Auswahl"])
    }
}

@Test func nuvioAccountCollectionMatchedByTitleFromPastedCode() {
    // An earlier pasted-code import kept the export's own id.
    let pasted = collection("c1", "Weekend", folders: [("F", ["a"])])
    let other = collection("mine", "Eigene", folders: [])
    let fresh = [collection("c1", "Weekend", folders: [("F", ["a", "b"])])]
    let p = plan(collections: [other, pasted], accountCollections: fresh)
    #expect(p.collections.map(\.status) == [.matchedByTitle] && p.collections[0].localID == "c1")
    #expect(!p.nothingToDo)
    let r = NuvioAccountImport.mergeCollections(local: [other, pasted], fresh: fresh, source: src,
                                                origin: NuvioImportOrigin(), previous: nil)
    #expect(r.collections.map(\.id) == ["mine", "c1"])   // no duplicate, local id kept, order kept
    #expect(r.collections[1].folders[0].sources.map(\.id) == ["a", "b"])
    #expect(r.marks == [.init(accountID: src.collectionID("c1"), localID: "c1", title: "Weekend")])
    // Next load matches by id through the mark, also after a local rename.
    var origin = NuvioImportOrigin()
    origin.noteCollections(r.marks)
    var renamed = r.collections
    renamed[1].title = "Neu benannt"
    let next = NuvioAccountImport.mergeCollections(local: renamed, fresh: fresh, source: src, origin: origin, previous: [:])
    #expect(next.items.map(\.status) == [.unchanged] && next.collections.count == 2)
}

@Test func nuvioAccountCollectionsAppendedAndOneLocalTakenOnce() {
    let existing = collection("x", "Same", folders: [])
    let fresh = [collection("c1", "Same", folders: [("A", ["a"])]), collection("c2", "Other", folders: [("B", ["b"])])]
    let r = NuvioAccountImport.mergeCollections(local: [existing], fresh: fresh, source: src, origin: NuvioImportOrigin(),
                                                previous: nil)
    #expect(r.items.map(\.status) == [.matchedByTitle, .new])
    #expect(r.collections.map(\.id) == ["x", src.collectionID("c2")])
    // Two account collections with the same id get distinct local ids.
    let dup = NuvioAccountImport.mergeCollections(
        local: [], fresh: [collection("c1", "One", folders: []), collection("c1", "Two", folders: [])],
        source: src, origin: NuvioImportOrigin(), previous: nil)
    #expect(Set(dup.collections.map(\.id)).count == 2)
}

@Test func nuvioAccountRefreshTakesFreshMediaUnlessChangedHere() {
    let id = src.collectionID("c1")
    var f = Folder(id: "f", title: "F", coverImage: "https://img.example.org/old.jpg", sources: [])
    let localC = [MediaCollection(id: id, title: "W", folders: [f])]
    f.coverImage = "https://img.example.org/new.jpg"
    let fresh = [MediaCollection(id: "c1", title: "W", folders: [f])]
    let snapshot = ["W|F": FolderMedia(Folder(id: "f", title: "F", coverImage: "https://img.example.org/old.jpg", sources: []))]
    let refreshed = NuvioAccountImport.mergeCollections(local: localC, fresh: fresh, source: src,
                                                        origin: NuvioImportOrigin(), previous: snapshot)
    #expect(refreshed.collections[0].folders[0].coverImage == "https://img.example.org/new.jpg")
    #expect(refreshed.items.map(\.status) == [.update])
    // First import (no snapshot): only gaps are filled.
    let first = NuvioAccountImport.mergeCollections(local: localC, fresh: fresh, source: src,
                                                    origin: NuvioImportOrigin(), previous: nil)
    #expect(first.collections[0].folders[0].coverImage == "https://img.example.org/old.jpg")
    #expect(first.items.map(\.status) == [.unchanged])
}

@Test func nuvioAccountCollectionsFromClientBytes() throws {
    // The account collection bytes feed the existing parser and are detected as a collection export.
    let wrapped = try fixture("nuvio-collections.json")
    let data = try NuvioPayload.collections(wrapped)
    #expect(CollectionImportFormat.detect(data) == .collections)
    let r = try NuvioImport.parse(data)
    #expect(r.collections.map(\.id) == ["collection-1"])
    let p = plan(accountCollections: r.collections)
    #expect(p.collections.map(\.title) == ["Weekend Picks"] && p.collections[0].accountID == src.collectionID("collection-1"))
    #expect(p.collections[0].folders == 1)
    #expect(r.pendingAddonSources.map(\.id) == ["addon:com.example.catalog:movie:top"])
}

// MARK: Texts

@Test func nuvioAccountErrorTexts() {
    #expect(NuvioAccountImport.errorText(NuvioError.signedOut) == "Nuvio: Sitzung abgelaufen. Bitte am Handy neu anmelden.")
    #expect(NuvioAccountImport.errorText(NuvioError.status(403, code: "42501")) == "Nuvio lehnt die Anfrage ab (403).")
    #expect(NuvioAccountImport.errorText(NuvioError.status(500, code: nil)) == "Nuvio antwortet mit Fehler 500.")
    #expect(NuvioAccountImport.errorText(NuvioError.offline) == "Nuvio nicht erreichbar. Bitte später erneut versuchen.")
    #expect(NuvioAccountImport.errorText(NuvioError.rateLimited).hasPrefix("Nuvio: zu viele Anfragen"))
    #expect(NuvioAccountImport.errorText(NuvioError.decoding("addons")) == "Nuvio: Antwort unlesbar.")
}
