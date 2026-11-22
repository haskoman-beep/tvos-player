import Foundation
import Testing
@testable import PlayerCore

// Wave F-o: focus videos on package tiles (import, fixed source, priority, sound, disk cache, studios package).

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

@Test func fixedSourceFillsOnlyGaps() {
    let plain = PackageFixedArt.apply(ReadyPackages.streamingDE)
    #expect(art(plain, "pkg.streaming-de.8")?.focusVideo == "https://cdn.xperience-app.com/covers/default/streaming_services.netflix.focus.mp4?v=7")
    #expect(art(plain, "pkg.streaming-de.531")?.focusVideo?.contains("paramount_plus") == true)
    // Services the export does not have stay without video; streaming stills come from imports/kit only.
    for id in ["pkg.streaming-de.30", "pkg.streaming-de.298", "pkg.streaming-de.304"] { #expect(art(plain, id)?.focusVideo == nil, "\(id)") }
    #expect(plain.folders.allSatisfy { $0.coverImage == nil })
    #expect(PackageArtStats(folders: plain.folders)?.logLine(row: "Streaming-Dienste") == "Paket-Bilder: Streaming-Dienste 0/8 mit Bild, 0 mit GIF, 5 mit Video")
    // Imports win: own GIF or own video stays, and no fixed video is added on top of a GIF.
    var own = ReadyPackages.streamingDE
    own.folders[0].focusGif = "https://example.com/own.gif"
    own.folders[1].focusVideo = "https://example.com/own.mp4"
    let kept = PackageFixedArt.apply(own)
    #expect(kept.folders[0].focusVideo == nil && kept.folders[0].focusGif == "https://example.com/own.gif")
    #expect(kept.folders[1].focusVideo == "https://example.com/own.mp4")
    // Genres: the export has nothing.
    #expect(PackageFixedArt.apply(ReadyPackages.genreCollection) == ReadyPackages.genreCollection)
    // Foreign collections are untouched.
    let foreign = MediaCollection(id: "nuvio.c", title: "C", folders: [Folder(id: "x", title: "Netflix", sources: [])])
    #expect(PackageFixedArt.apply(foreign) == foreign)
}

@Test func studiosPackage() {
    let c = ReadyPackages.studioCollection
    #expect(c.id == "pkg.studios" && c.title == "Studios")
    #expect(c.folders.count == ReadyPackages.studios.count && c.folders.count == 18)
    for name in ["Pixar", "Disney Animation", "Marvel Studios", "Lucasfilm", "Paramount"] {
        #expect(c.folders.contains { $0.title == name }, "\(name)")
    }
    let ids = c.folders.map(\.id) + c.folders.flatMap { $0.sources.map(\.id) }
    #expect(Set(ids).count == ids.count)
    let pixar = art(c, "pkg.studios.3")
    #expect(pixar?.title == "Pixar" && pixar?.sources.count == 3)
    guard case .tmdbDiscover(let f) = pixar?.sources.first?.kind else { Issue.record("kind"); return }
    #expect(f["with_companies"] == "3" && f["sort_by"] == "popularity.desc")
    #expect(art(c, "pkg.studios.420")?.sources.contains { $0.mediaType == .series } == true)
    #expect(art(c, "pkg.studios.34")?.sources.first.map { s in
        if case .tmdbDiscover(let f) = s.kind { return f["with_companies"] == "34|5" } else { return false }
    } == true)
    for f in c.folders {
        #expect(ReadyPackages.isPackageFolder(f.id))
        #expect(ReadyPackages.tileStyle(forFolderID: f.id)?.symbol == "film", "\(f.id)")
        #expect(ReadyPackages.artNames(forFolderID: f.id)?.first == ReadyPackages.normalizedArtName(f.title))
    }
    // Every studio gets still and video from the fixed source, without a second title over the still.
    let filled = PackageFixedArt.apply(c)
    #expect(filled.folders.allSatisfy { $0.focusVideo?.hasSuffix(".focus.mp4?v=7") == true && $0.coverImage?.hasSuffix(".webp?v=7") == true })
    #expect(filled.folders.allSatisfy { !$0.showsTitleOverImage })
    #expect(art(filled, "pkg.studios.3")?.focusVideo == "https://cdn.xperience-app.com/covers/default/studios.pixar.focus.mp4?v=7")
    #expect(art(filled, "pkg.studios.3")?.coverImage == "https://cdn.xperience-app.com/covers/default/studios.pixar.webp?v=7")
    #expect(PackageArtStats(folders: filled.folders)?.logLine(row: "Studios") == "Paket-Bilder: Studios 18/18 mit Bild, 0 mit GIF, 18 mit Video")
}

@Test func studioTilesTakeImportArtByCompanyAndName() {
    let imported = MediaCollection(id: "nuvio.s", title: "Studios", folders: [
        Folder(id: "i1", title: "Marvel", coverImage: "https://example.com/marvel.webp",
               sources: [CatalogSource(id: "s1", title: "s1", kind: .tmdbCompany(id: "420"), mediaType: .movie)],
               focusVideo: "https://example.com/marvel.mp4"),
        Folder(id: "i2", title: "Irgendwas", coverImage: "https://example.com/sony.webp",
               sources: [CatalogSource(id: "s2", title: "s2", kind: .tmdbCompany(id: "5"), mediaType: .movie)]),
        Folder(id: "i3", title: "Walt Disney Animation Studios", coverImage: "https://example.com/wdas.webp", sources: []),
    ])
    var memo = PackageArtMemo()
    let out = memo.collection(ReadyPackages.studioCollection, stamp: .init(profile: 1, kit: 1)) {
        PackageArtSource.userImports([imported])
    }
    #expect(art(out, "pkg.studios.420")?.coverImage == "https://example.com/marvel.webp")
    #expect(art(out, "pkg.studios.420")?.focusVideo == "https://example.com/marvel.mp4")
    #expect(art(out, "pkg.studios.34")?.coverImage == "https://example.com/sony.webp")
    // Import still without animation: the fixed video is added.
    #expect(art(out, "pkg.studios.34")?.focusVideo?.contains("studios.sony") == true)
    #expect(art(out, "pkg.studios.6125")?.coverImage == "https://example.com/wdas.webp")
    // The rest comes from the fixed source.
    #expect(art(out, "pkg.studios.3")?.coverImage?.contains("studios.pixar") == true)
}

@Test func memoAppliesFixedSource() {
    var memo = PackageArtMemo()
    let out = memo.collection(ReadyPackages.streamingDE, stamp: .init(profile: 1, kit: 1)) { [] }
    #expect(art(out, "pkg.streaming-de.8")?.focusVideo?.contains("streaming_services.netflix") == true)
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
    // Old file always goes; then the least recently used until 50 MB fit.
    #expect(FocusVideoCachePlan.evict(entries, now: now) == ["old", "a"])
    #expect(FocusVideoCachePlan.evict(Array(entries.dropFirst().prefix(2)), now: now).isEmpty)
    #expect(FocusVideoCachePlan.maxBytes == 50 * mb)
    let n = FocusVideoCachePlan.fileName(for: "https://example.com/a.focus.mp4?v=7")
    #expect(n.hasSuffix(".mp4") && n == FocusVideoCachePlan.fileName(for: "https://example.com/a.focus.mp4?v=7"))
    #expect(n != FocusVideoCachePlan.fileName(for: "https://example.com/b.focus.mp4?v=7"))
}

@Test func tileAnimationSoundDefaultsOff() throws {
    let a = try JSONDecoder().decode(Appearance.self, from: Data(#"{"navigation":"top"}"#.utf8))
    #expect(a.tileAnimationSound == false && a.navigation == .top)
    var on = Appearance()
    on.tileAnimationSound = true
    #expect(try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(on)).tileAnimationSound)
}
