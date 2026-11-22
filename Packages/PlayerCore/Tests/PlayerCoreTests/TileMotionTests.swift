import Foundation
import Testing
@testable import PlayerCore

// Wave F-o: focus videos on tiles (import, priority, sound, disk cache). Round 2: imports only (widget export,
// preview pack, collection export); fixtures are synthetic with example.invalid addresses.

private func art(_ c: MediaCollection, _ id: String) -> Folder? { c.folders.first { $0.id == id } }

@Test func oldFolderJSONDecodesWithoutFocusVideo() throws {
    let json = #"{"id":"a","title":"A","sources":[],"focusGif":"g"}"#
    let f = try JSONDecoder().decode(Folder.self, from: Data(json.utf8))
    #expect(f.focusVideo == nil && f.heroVideo == nil && f.focusGif == "g")
    // Round trip keeps the new fields.
    var g = f
    g.focusVideo = "https://example.com/v.mp4"
    let back = try JSONDecoder().decode(Folder.self, from: JSONEncoder().encode(g))
    #expect(back.focusVideo == "https://example.com/v.mp4")
}

@Test func focusVideoAddressRules() {
    #expect(FocusVideoURL.playable("https://example.com/a.focus.mp4?v=7") == "https://example.com/a.focus.mp4?v=7")
    #expect(FocusVideoURL.playable("https://example.com/a.MOV") != nil)
    #expect(FocusVideoURL.playable("https://example.com/live/a.m3u8") != nil)
    #expect(FocusVideoURL.playable("https://example.com/a.focus.webm?v=7") == nil)
    #expect(FocusVideoURL.playable("http://example.com/a.mp4") == nil)
    #expect(FocusVideoURL.playable("https://example.com/a.gif") == nil)
    #expect(FocusVideoURL.playable("") == nil && FocusVideoURL.playable(nil) == nil)
    #expect(FocusVideoURL.isStream("https://example.com/live/a.m3u8"))
    #expect(!FocusVideoURL.isStream("https://example.com/a.mp4"))
}

@Test func nuvioImportReadsFocusVideo() throws {
    let json = #"""
    [{"id":"c","title":"Streaming","folders":[
      {"id":"f1","title":"N","coverImageUrl":"c1","focusGifUrl":"g1","focusGifEnabled":true,
       "focusVideoUrl":"https://example.com/n.focus.mp4?v=7","focusVideoWebmUrl":"https://example.com/n.focus.webm?v=7",
       "heroVideoUrl":"https://example.com/n.hero.mp4"},
      {"id":"f2","title":"P","coverImageUrl":"c2","focusGifUrl":"g2","focusGifEnabled":false,
       "focusVideoUrl":"https://example.com/p.focus.mp4"},
      {"id":"f3","title":"W","coverImageUrl":"c3","focusVideoWebmUrl":"https://example.com/w.focus.webm"},
      {"id":"f4","title":"H","coverImageUrl":"c4","focusVideoUrl":"http://example.com/h.mp4"}]}]
    """#
    let folders = try NuvioImport.parse(Data(json.utf8)).collections.first?.folders ?? []
    let f1 = folders.first { $0.id == "f1" }
    #expect(f1?.focusVideo == "https://example.com/n.focus.mp4?v=7")
    #expect(f1?.heroVideo == "https://example.com/n.hero.mp4")
    // `focusGifEnabled: false` switches the video off too.
    #expect(folders.first { $0.id == "f2" }?.focusVideo == nil)
    // WebM only or plain http: no video.
    #expect(folders.first { $0.id == "f3" }?.focusVideo == nil)
    #expect(folders.first { $0.id == "f4" }?.focusVideo == nil)
}

@Test func nuvioFixtureKeepsItsFocusVideos() throws {
    let r = try NuvioImport.parse(fixture("nuvio.json"))
    let videos = r.collections.flatMap(\.folders).filter { $0.focusVideo != nil }
    // 85 tiles of the export have a video; merging duplicates by title leaves 55.
    #expect(videos.count == 55)
    #expect(videos.allSatisfy { $0.focusVideo!.hasSuffix(".focus.mp4?v=7") })
    let netflix = r.collections.first { $0.title == "Streaming" }?.folders.first { $0.title == "Netflix" }
    #expect(netflix?.focusVideo == "https://example.com/covers/default/streaming_services.netflix.focus.mp4?v=7")
}

@Test func mergeFoldersFillsMissingVideo() {
    let a = Folder(id: "a", title: "N", sources: [])
    let b = Folder(id: "b", title: "N", sources: [], focusVideo: "https://example.com/n.mp4", heroVideo: "https://example.com/h.mp4")
    let merged = NuvioImport.mergeFolders([a], [b])
    #expect(merged.count == 1 && merged[0].focusVideo == "https://example.com/n.mp4" && merged[0].heroVideo == "https://example.com/h.mp4")
    let kept = NuvioImport.mergeFolders([Folder(id: "a", title: "N", sources: [], focusVideo: "https://example.com/own.mp4")], [b])
    #expect(kept[0].focusVideo == "https://example.com/own.mp4")
}

@Test func tileMotionPriority() {
    let both = Folder(id: "x", title: "X", sources: [], focusGif: "https://example.com/x.gif", focusVideo: "https://example.com/x.mp4")
    #expect(TileMotion.of(both) == .video("https://example.com/x.mp4"))
    let webm = Folder(id: "x", title: "X", sources: [], focusGif: "https://example.com/x.gif", focusVideo: "https://example.com/x.webm")
    #expect(TileMotion.of(webm) == .gif("https://example.com/x.gif"))
    #expect(TileMotion.of(Folder(id: "x", title: "X", sources: [], focusGif: "")) == .still)
    #expect(TileMotion.of(Folder(id: "x", title: "X", sources: [])) == .still)
}

@Test func withArtTakesVideoAndPrefersSourcesWithVideo() {
    func tile(_ title: String, _ cover: String, gif: String? = nil, video: String? = nil) -> Folder {
        Folder(id: "t.\(title)", title: title, coverImage: cover, sources: [], focusGif: gif, focusVideo: video)
    }
    let gifOnly = PackageArtSource(id: "g", folders: [tile("Netflix", "https://example.com/g.jpg", gif: "https://example.com/g.gif")], origin: .kit)
    let withVideo = PackageArtSource(id: "v", folders: [tile("Netflix", "https://example.com/v.jpg", video: "https://example.com/v.mp4")], origin: .kit)
    let out = ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [gifOnly, withVideo])
    #expect(art(out, "pkg.streaming-de.8")?.coverImage == "https://example.com/v.jpg")
    #expect(art(out, "pkg.streaming-de.8")?.focusVideo == "https://example.com/v.mp4")
    let stats = PackageArtStats(folders: out.folders)
    #expect(stats?.logLine(row: "Streaming-Dienste") == "Paket-Bilder: Streaming-Dienste 1/8 mit Bild, 0 mit GIF, 1 mit Video")
}

@Test func packageTilesHaveNoBuiltInVideo() {
    // Round 2: no fixed source; without imports the package tiles stay stills.
    var memo = PackageArtMemo()
    for c in ReadyPackages.all {
        let out = memo.collection(c, stamp: .init(profile: 1, kit: 1)) { [] }
        #expect(out.folders.allSatisfy { $0.focusVideo == nil && $0.coverImage == nil }, "\(c.id)")
    }
    #expect(!ReadyPackages.all.contains { $0.id == "pkg.studios" })
}

@Test func focusVideoSoundRules() {
    #expect(FocusVideoAudio.audible(setting: true, hasAudioTrack: true, mainPlayback: false, loopsDone: 0))
    #expect(!FocusVideoAudio.audible(setting: false, hasAudioTrack: true, mainPlayback: false, loopsDone: 0))
    #expect(!FocusVideoAudio.audible(setting: true, hasAudioTrack: false, mainPlayback: false, loopsDone: 0))
    #expect(!FocusVideoAudio.audible(setting: true, hasAudioTrack: true, mainPlayback: true, loopsDone: 0))
    // Once per focus: the second pass is silent.
    #expect(!FocusVideoAudio.audible(setting: true, hasAudioTrack: true, mainPlayback: false, loopsDone: 1))
    #expect(FocusVideoAudio.targetVolume == 0.6)
    let up = FocusVideoAudio.ramp(from: 0, to: 0.6, steps: 4)
    #expect(up.count == 4 && abs(up[0] - 0.15) < 1e-6 && up.last == 0.6)
    #expect(FocusVideoAudio.ramp(from: 0.6, to: 0, steps: 3).last == 0)
    #expect(FocusVideoAudio.ramp(from: 0, to: 1, steps: 0) == [1])
}

@Test func focusVideoCacheEviction() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let mb: Int64 = 1 << 20
    let entries = [
        FocusVideoCachePlan.Entry(name: "old", bytes: 1 * mb, used: now.addingTimeInterval(-8 * 24 * 3600)),
        FocusVideoCachePlan.Entry(name: "a", bytes: 20 * mb, used: now.addingTimeInterval(-300)),
        FocusVideoCachePlan.Entry(name: "b", bytes: 20 * mb, used: now.addingTimeInterval(-200)),
        FocusVideoCachePlan.Entry(name: "c", bytes: 20 * mb, used: now.addingTimeInterval(-100)),
    ]
    let silent = FocusVideoCachePlan.Pot.silent, sound = FocusVideoCachePlan.Pot.sound
    // Old file always goes; then the least recently used until the pot fits.
    #expect(FocusVideoCachePlan.evict(entries, now: now, maxBytes: silent.maxBytes) == ["old", "a"])
    #expect(FocusVideoCachePlan.evict(entries, now: now, maxBytes: sound.maxBytes) == ["old"])
    let n = FocusVideoCachePlan.fileName(for: "https://example.invalid/a.focus.mp4?v=7")
    #expect(n.hasSuffix(".mp4") && n == FocusVideoCachePlan.fileName(for: "https://example.invalid/a.focus.mp4?v=7"))
    #expect(n != FocusVideoCachePlan.fileName(for: "https://example.invalid/b.focus.mp4?v=7"))
    #expect(FocusVideoCachePlan.fileName(for: "https://example.invalid/g.MP4").hasSuffix(".mp4"))
}

@Test func focusVideoCacheCaps() {
    let mib: Int64 = 1 << 20
    #expect(FocusVideoCachePlan.Pot.silent.maxBytes == 50 * mib && FocusVideoCachePlan.Pot.silent.maxFileBytes == 20 * mib)
    #expect(FocusVideoCachePlan.Pot.sound.maxBytes == 150 * mib && FocusVideoCachePlan.Pot.sound.maxFileBytes == 30 * mib)
    #expect(FocusVideoCachePlan.maxDownloadBytes == 30 * mib)
    // A 20.1 MiB studio intro with sound fits the sound pot, the same size without sound does not.
    let mp4: [UInt8] = [0, 0, 0, 0x20] + Array("ftypisom".utf8)
    let intro: Int64 = 21_091_511
    #expect(FocusVideoCachePlan.check(contentType: "application/octet-stream", head: mp4, bytes: intro, hasSound: true) == .ok(.sound))
    #expect(FocusVideoCachePlan.check(contentType: "application/octet-stream", head: mp4, bytes: intro, hasSound: false) == .tooLarge)
    #expect(FocusVideoCachePlan.check(contentType: "video/mp4", head: mp4, bytes: 31 * mib, hasSound: true) == .tooLarge)
}

@Test func tileAnimationSoundDefaultsOff() throws {
    let a = try JSONDecoder().decode(Appearance.self, from: Data(#"{"navigation":"top"}"#.utf8))
    #expect(a.tileAnimationSound == false && a.navigation == .top)
    var on = Appearance()
    on.tileAnimationSound = true
    #expect(try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(on)).tileAnimationSound)
}

// Round 1 (I1): only a real video body goes into the cache.
@Test func focusVideoBodyCheck() {
    let mp4: [UInt8] = [0, 0, 0, 0x20] + Array("ftypisom".utf8)
    let html = Array("<!DOCTYPE html><html>".utf8)
    let kb: Int64 = 1 << 10
    func check(_ type: String?, _ head: [UInt8], _ bytes: Int64) -> FocusVideoCachePlan.Check {
        FocusVideoCachePlan.check(contentType: type, head: head, bytes: bytes, hasSound: false)
    }
    #expect(check("video/mp4", mp4, 120 * kb) == .ok(.silent))
    // ftyp box wins over a wrong type (raw file hosts send octet-stream).
    #expect(check("application/octet-stream", mp4, 120 * kb) == .ok(.silent))
    // QuickTime file starting with another box, but labelled as video.
    #expect(check("video/quicktime; charset=binary", Array("\0\0\0\u{8}wide".utf8), 120 * kb) == .ok(.silent))
    // Captive portal / error page with 200.
    #expect(check("text/html; charset=utf-8", html, 120 * kb) == .notVideo("text/html"))
    #expect(check(nil, html, 120 * kb) == .notVideo("ohne Typ"))
    #expect(check("video/mp4", mp4, 1 * kb) == .tooSmall)
    #expect(check("video/mp4", mp4, 21 << 20) == .tooLarge)
    #expect(FocusVideoCachePlan.retryAfterPlaybackFailure == 1800)
}

/// Synthetic box bytes: `hdlr` boxes with the given handler types, padded with filler.
private func boxes(_ handlers: [String]) -> [UInt8] {
    var b: [UInt8] = [0, 0, 0, 0x20]
    b.append(contentsOf: Array("ftypisom".utf8))
    b.append(contentsOf: [UInt8](repeating: 0, count: 20))
    for h in handlers {
        let size: [UInt8] = [0, 0, 0, 0x21]
        b.append(contentsOf: size)
        b.append(contentsOf: Array("hdlr".utf8))
        b.append(contentsOf: [UInt8](repeating: 0, count: 8))
        b.append(contentsOf: Array(h.utf8))
        b.append(contentsOf: [UInt8](repeating: 0x2e, count: 13))
    }
    return b
}

@Test func mp4ProbeFindsSoundTrack() {
    #expect(Mp4Probe.hasFtyp(boxes([])))
    #expect(Mp4Probe.handlers(boxes(["vide", "soun"])) == ["vide", "soun"])
    #expect(Mp4Probe.hasSoundTrack(boxes(["vide", "soun"])))
    #expect(!Mp4Probe.hasSoundTrack(boxes(["vide"])))
    #expect(!Mp4Probe.hasSoundTrack(Array("hdlr".utf8)))
    #expect(!Mp4Probe.hasSoundTrack([]))
}

// Round 2: the sound fades out after about 12 s, or at the end of a shorter first pass.
@Test func focusVideoFadeOutSchedule() {
    // Short brand sting (6 s): short fade, finished before the loop boundary.
    let sting = FocusVideoAudio.fadeOutPlan(duration: 6)
    #expect(sting == .init(start: 6 - FocusVideoAudio.fadeOut - FocusVideoAudio.endMargin, length: FocusVideoAudio.fadeOut))
    #expect(sting!.start + sting!.length < 6)
    // Long studio intro (41 s): cap at 12 s with a slow fade.
    #expect(FocusVideoAudio.fadeOutPlan(duration: 41) == .init(start: 12, length: 1))
    #expect(FocusVideoAudio.soundCap == 12)
    // Just above the cap: the cap fade would run into the boundary, so the end of the pass decides.
    let edge = FocusVideoAudio.fadeOutPlan(duration: 12.5)!
    #expect(edge.start + edge.length < 12.5)
    // Unknown duration (stream): the cap.
    #expect(FocusVideoAudio.fadeOutPlan(duration: .nan) == .init(start: 12, length: 1))
    #expect(FocusVideoAudio.fadeOutPlan(duration: .infinity) == .init(start: 12, length: 1))
    // Too short for a fade: muted at the boundary instead.
    #expect(FocusVideoAudio.fadeOutPlan(duration: 0.2) == nil)
}

// Round 2: import formats, preview pack matching, result line.
@Test func collectionImportDetectsFormats() {
    func f(_ s: String) -> CollectionImportFormat { CollectionImportFormat.detect(Data(s.utf8)) }
    #expect(f(#"{"exportType":"fusionWidgets","widgets":[]}"#) == .widgets)
    #expect(f(#"{"widgets":[{"title":"A"}]}"#) == .widgets)
    #expect(f(#"[{"name":"A","backgroundImageURL":"https://example.invalid/a.jpg","dataSources":[]}]"#) == .collectionList)
    #expect(f(#"[{"id":"1","title":"Netflix","videoURL":"https://example.invalid/n.mp4","backgroundURL":"https://example.invalid/n.jpg"}]"#) == .previewPack)
    #expect(f(#"[{"title":"Streaming","folders":[]}]"#) == .collections)
    #expect(f(#"{"profiles":[]}"#) == .backup)
    #expect(f(#"[{"id":"x","url":"https://example.invalid/i.png"}]"#) == .iconPack)
    #expect(f("[{\"title\":") == .invalidJSON)
    #expect(f("hallo") == .invalidJSON)
    #expect(f(#"{"a":1}"#) == .unknown && f("[]") == .unknown && f("[1,2]") == .unknown)
    #expect(CollectionImportFormat.previewPack.problem == nil)
    #expect(CollectionImportFormat.invalidJSON.problem?.contains("JSON") == true)
    #expect(CollectionImportFormat.unknown.problem?.contains("nicht erkannt") == true)
}

@Test func previewPackMatchesByTitle() throws {
    #expect(PreviewPack.key(" Disney+ ") == "disney" && PreviewPack.key("Apple  TV") == "appletv")
    #expect(PreviewPack.key("Amélie") == "amelie" && PreviewPack.key("NETFLIX") == PreviewPack.key("netflix"))
    let json = #"""
    [{"id":"1","title":"Netflix","videoURL":"https://example.invalid/n.mp4","backgroundURL":"https://example.invalid/n.jpg"},
     {"id":"2","title":"Disney+","videoURL":"https://example.invalid/d.mp4"},
     {"id":"3","title":"Twin","videoURL":"https://example.invalid/t1.mp4"},
     {"id":"4","title":"twin","videoURL":"https://example.invalid/t2.mp4"},
     {"id":"5","title":"Same","videoURL":"https://example.invalid/s.mp4"},
     {"id":"6","title":"same ","videoURL":"https://example.invalid/s.mp4"},
     {"id":"7","title":"Web","videoURL":"https://example.invalid/w.webm"},
     {"id":"8","videoURL":"https://example.invalid/x.mp4"}]
    """#
    let (entries, skipped) = try PreviewPack.parse(Data(json.utf8))
    #expect(entries.count == 6 && skipped == 2)
    let index = PreviewPack.Index(entries)
    // Equal titles: the first entry wins.
    #expect(index.entry(forTitle: "Twin")?.video == "https://example.invalid/t1.mp4")
    #expect(index.entry(forTitle: "SAME")?.video == "https://example.invalid/s.mp4")
    let c = MediaCollection(id: "c", title: "Dienste", folders: [
        Folder(id: "a", title: "netflix ", sources: []),
        Folder(id: "b", title: "Disney +", coverImage: "https://example.invalid/own.jpg", sources: []),
        Folder(id: "c", title: "Twin", sources: []),
        Folder(id: "d", title: "Own", sources: [], focusVideo: "https://example.invalid/own.mp4"),
    ])
    let out = PreviewPack.apply(index, to: c)
    #expect(art(out, "a")?.focusVideo == "https://example.invalid/n.mp4" && art(out, "a")?.coverImage == "https://example.invalid/n.jpg")
    // Own still kept, video added.
    #expect(art(out, "b")?.coverImage == "https://example.invalid/own.jpg" && art(out, "b")?.focusVideo == "https://example.invalid/d.mp4")
    #expect(art(out, "c")?.focusVideo == "https://example.invalid/t1.mp4" && art(out, "d")?.focusVideo == "https://example.invalid/own.mp4")
    #expect(PreviewPack.matches(index, in: [c]) == 3)
    #expect(PreviewPack.apply(PreviewPack.Index([]), to: c) == c)
}

@Test func importSummaryCounts() {
    let c1 = MediaCollection(id: "1", title: "A", folders: [
        Folder(id: "a", title: "A", sources: [], focusVideo: "https://example.invalid/a.mp4"),
        Folder(id: "b", title: "B", sources: [], focusVideo: "https://example.invalid/b.mp4"),
        Folder(id: "c", title: "C", sources: [], focusVideo: "https://example.invalid/c.webm"),
    ])
    let c2 = MediaCollection(id: "2", title: "B", folders: [Folder(id: "d", title: "D", sources: [], focusVideo: "https://example.invalid/a.mp4")])
    let s = ImportSummary.of([c1, c2])
    #expect(s == ImportSummary(rows: 2, tiles: 4, video: 3, sound: nil))
    #expect(s.line == "Import: 2 Reihen, 4 Kacheln, 3 mit Video")
    #expect(ImportSummary.videos([c1, c2]) == ["https://example.invalid/a.mp4", "https://example.invalid/b.mp4"])
    let t = ImportSummary.of([c1, c2], soundVideos: ["https://example.invalid/a.mp4"])
    #expect(t.line == "Import: 2 Reihen, 4 Kacheln, 3 mit Video, 2 mit Ton")
    #expect(ImportSummary(rows: 1, tiles: 1, video: 0).line == "Import: 1 Reihe, 1 Kachel, 0 mit Video")
    #expect(ImportSummary.packLine(entries: 84, matched: 12, sound: 39) == "Preview Pack: 84 Videos, 12 Kacheln zugeordnet, 39 mit Ton")
}

@Test func widgetExportKeepsMotionFields() throws {
    let json = #"""
    {"exportType":"fusionWidgets","widgets":[{"id":"collection.S","title":"Dienste","type":"collection.row",
     "dataSource":{"kind":"collection","payload":{"items":[
      {"id":"A","title":"Netflix","imageURL":"https://example.invalid/n.jpg","videoURL":"https://example.invalid/n.mp4",
       "dataSources":[{"kind":"tmdbDiscover","payload":{"type":"movie","sortBy":"popularity.desc"}}]},
      {"id":"B","title":"Prime","imageURL":"https://example.invalid/p.jpg","focusGifURL":"https://example.invalid/p.gif",
       "focusVideoUrl":"https://example.invalid/p.webm",
       "dataSources":[{"kind":"tmdbDiscover","payload":{"type":"movie","sortBy":"popularity.desc"}}]}]}}}]}
    """#
    #expect(CollectionImportFormat.detect(Data(json.utf8)) == .widgets)
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "s")
    let folders = c.rows.compactMap { r -> [Folder]? in if case .collection(let m) = r.body { return m.folders }; return nil }.flatMap { $0 }
    #expect(folders.first { $0.title == "Netflix" }?.focusVideo == "https://example.invalid/n.mp4")
    let prime = folders.first { $0.title == "Prime" }
    #expect(prime?.focusVideo == nil && prime?.focusGif == "https://example.invalid/p.gif")
    #expect(prime.map(TileMotion.of) == .gif("https://example.invalid/p.gif"))
}

// Round 3 (I3): exact title first, so a service and a studio of the same brand keep their own videos.
@Test func previewPackExactTitleBeforeCoarseKey() {
    let index = PreviewPack.Index([
        PreviewPackEntry(title: "Paramount+", video: "https://example.invalid/service.mp4"),
        PreviewPackEntry(title: "Paramount", video: "https://example.invalid/studio.mp4"),
        PreviewPackEntry(title: "Disney", video: "https://example.invalid/disney.mp4"),
    ])
    #expect(index.entry(forTitle: "Paramount+")?.video == "https://example.invalid/service.mp4")
    #expect(index.entry(forTitle: " paramount ")?.video == "https://example.invalid/studio.mp4")
    #expect(index.entry(forTitle: "PARAMOUNT +")?.video == "https://example.invalid/service.mp4")
    // No exact entry: the coarse key ("disney") finds the first entry with that key.
    #expect(index.entry(forTitle: "Disney+")?.video == "https://example.invalid/disney.mp4")
    #expect(index.entry(forTitle: "Paramount Pictures") == nil)
}

// Round 3 (I4): "Aktualisieren" takes the fresh media addresses and keeps only the user's own changes.
@Test func refreshReplacesMediaKeepsUserEdits() {
    func f(_ t: String, cover: String?, video: String?) -> Folder {
        Folder(id: "x." + t, title: t, coverImage: cover, sources: [], focusVideo: video)
    }
    let first = [f("N", cover: "https://example.invalid/n7.jpg", video: "https://example.invalid/n.focus.mp4?v=7"),
                 f("P", cover: "https://example.invalid/p7.jpg", video: "https://example.invalid/p.focus.mp4?v=7")]
    let snapshot = NuvioImport.media(of: [MediaCollection(id: "c", title: "Dienste", folders: first)])
    var current = first
    current[1].coverImage = "https://example.invalid/my-own.jpg"   // the user's own still
    let fresh = [f("N", cover: "https://example.invalid/n8.jpg", video: "https://example.invalid/n.focus.mp4?v=8"),
                 f("P", cover: "https://example.invalid/p8.jpg", video: "https://example.invalid/p.focus.mp4?v=8"),
                 f("Q", cover: "https://example.invalid/q.jpg", video: nil)]
    let out = NuvioImport.refreshFolders(current, fresh: fresh, collection: "Dienste", previous: snapshot)
    #expect(out.count == 3)
    #expect(out[0].focusVideo == "https://example.invalid/n.focus.mp4?v=8" && out[0].coverImage == "https://example.invalid/n8.jpg")
    #expect(out[1].focusVideo == "https://example.invalid/p.focus.mp4?v=8" && out[1].coverImage == "https://example.invalid/my-own.jpg")
    #expect(out[2].title == "Q")
    // Without a snapshot (link stored before round 3) the fresh export wins.
    #expect(NuvioImport.refreshFolders(current, fresh: fresh, collection: "Dienste", previous: [:])[1].coverImage == "https://example.invalid/p8.jpg")
    // A plain first import still only fills gaps.
    #expect(NuvioImport.mergeFolders(current, fresh)[0].focusVideo == "https://example.invalid/n.focus.mp4?v=7")
}
