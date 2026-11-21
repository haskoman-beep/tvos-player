import Foundation
import Testing
@testable import PlayerCore

private func st(_ name: String, _ desc: String, file: String? = nil, binge: String? = nil, url: String? = nil) -> StreamItem {
    let hints = (file != nil || binge != nil) ? StreamBehaviorHints(bingeGroup: binge, filename: file) : nil
    return StreamItem(name: name, description: desc, url: url ?? "https://x/\(name.hashValue)/\(desc.hashValue)/\(file ?? "")",
                      behaviorHints: hints)
}

@Test func releaseNameGroupAndPattern() {
    #expect(ReleaseName.group("Show.S01E01.Pilot.1080p.WEB-DL.DDP5.1.H.264-NTb.mkv") == "ntb")
    #expect(ReleaseName.group("Show S01E01 1080p WEB-DL") == nil)            // „DL“ ist keine Gruppe
    #expect(ReleaseName.group("Show.S01E01.2160p.BluRay.REMUX-FraMeSToR.mkv") == "framestor")
    let a = ReleaseName.pattern("Show.S01E01.Pilot.1080p.WEB-DL.DDP5.1.H.264-NTb.mkv")
    let b = ReleaseName.pattern("Show.S01E02.The.Next.One.1080p.WEB-DL.DDP5.1.H.264-NTb.mkv")
    #expect(a != nil && a == b)                                            // Folgentitel fällt heraus
    #expect(ReleaseName.pattern("Show.S01E02.German.DL.1080p.WEB.h264-GRP.mkv") == "german.dl.1080p.web.h264-grp")
    #expect(ReleaseName.pattern("Film.2023.1080p.mkv") == nil)              // ohne Folgenkennung kein Muster
}

@Test func releaseNameFromDescriptionAndService() {
    let s = StreamItem(name: "[TB⚡] AIOStreams", description: "1080p WEB-DL\n📁 Show.S02E03.720p.HDTV.x264-ABC.mkv",
                       url: "https://x/a")
    #expect(ReleaseName.releaseName(s) == "Show.S02E03.720p.HDTV.x264-ABC.mkv")
    #expect(ReleaseName.service(s) == "TB")
    #expect(ReleaseName.service(StreamItem(name: "[RD+] Torrentio 4k")) == "RD")
    #expect(ReleaseName.service(StreamItem(name: "AIO 1080p WEB-DL")) == nil)  // WEB-DL ist kein Dienst
    #expect(ReleaseName.service(StreamItem(name: "TorBox 1080p")) == "TB")
}

@Test func nextEpisodeKeepsBingeGroupFirst() {
    let now = st("[TB⚡] A", "⚡ 1080p", file: "Show.S01E01.1080p.WEB-DL-NTb.mkv", binge: "g2")
    let ref = ReleaseProfile(stream: now, addon: "AIO")
    let list: [(addon: String, stream: StreamItem)] = [
        ("AIO", st("[TB⚡] A", "⚡ 1080p", file: "Show.S01E02.1080p.WEB-DL-NTb.mkv", binge: "g1")),
        ("AIO", st("[TB⚡] A", "⚡ 2160p", file: "Show.S01E02.2160p.WEB-DL-OTHER.mkv", binge: "g2")),
    ]
    #expect(nextEpisodeStream(list, matching: ref)?.behaviorHints?.bingeGroup == "g2")
}

@Test func nextEpisodePrefersSameReleaseOverListOrder() {
    let now = st("[TB⚡] AIO", "⚡ 1080p DV 🇩🇪", file: "Show.S01E01.Pilot.German.DL.DV.1080p.WEB.h265-GRP.mkv")
    let ref = ReleaseProfile(stream: now, addon: "AIO")
    let first = st("[TB⚡] AIO", "⚡ 2160p HDR10 🇬🇧", file: "Show.S01E02.2160p.WEB.HDR10.h265-XYZ.mkv")
    let same = st("[TB⚡] AIO", "⚡ 1080p DV 🇩🇪", file: "Show.S01E02.Zwei.German.DL.DV.1080p.WEB.h265-GRP.mkv")
    let list: [(addon: String, stream: StreamItem)] = [("AIO", first), ("AIO", same)]
    #expect(nextEpisodeStream(list, matching: ref)?.id == same.id)
    #expect(ref.score(same, addon: "AIO") > ref.score(first, addon: "AIO"))
}

@Test func nextEpisodeMatchesTraitsWithoutFilename() {
    // Keine Dateinamen: Auflösung, HDR, Sprache und Dienst entscheiden.
    let ref = ReleaseProfile(stream: st("[RD+] Torrentio", "⚡ 2160p DV Atmos 🇩🇪"), addon: "Torrentio")
    let list: [(addon: String, stream: StreamItem)] = [
        ("AIO", st("[TB⚡] AIO", "⚡ 1080p 🇬🇧")),
        ("Torrentio", st("[RD+] Torrentio", "⚡ 2160p DV Atmos 🇩🇪")),
    ]
    #expect(nextEpisodeStream(list, matching: ref)?.name == "[RD+] Torrentio")
}

@Test func nextEpisodeFallsBackToListOrderAndSkipsUncached() {
    let ref = ReleaseProfile(stream: StreamItem(name: "x", url: "https://x/0"), addon: nil)
    let unc = st("[TB⏳] AIO", "⏳ 2160p")
    let a = st("A", "⚡ 1080p"), b = st("B", "⚡ 720p")
    // Nichts gemeinsam → erste Quelle der bestehenden Sortierung (ungecachte übersprungen).
    #expect(nextEpisodeStream([("AIO", unc), ("AIO", a), ("AIO", b)], matching: ref)?.id == a.id)
    #expect(nextEpisodeStream([("AIO", unc), ("AIO", a)], matching: nil)?.id == a.id)
    // Nur ungecachte: dann doch die.
    #expect(nextEpisodeStream([("AIO", unc)], matching: ref)?.id == unc.id)
    // Nicht abspielbar (kein http) fällt raus; leer → nil.
    #expect(nextEpisodeStream([("AIO", StreamItem(name: "t", infoHash: "h"))], matching: ref) == nil)
    #expect(nextEpisodeStream([], matching: ref) == nil)
}

@Test func nextEpisodeDoesNotPreferUncachedSameRelease() {
    let ref = ReleaseProfile(stream: st("[TB⚡] AIO", "⚡ 1080p", file: "Show.S01E01.1080p.WEB-DL-NTb.mkv"), addon: "AIO")
    let uncSame = st("[TB⏳] AIO", "⏳ 1080p", file: "Show.S01E02.1080p.WEB-DL-NTb.mkv")
    let ready = st("[TB⚡] AIO", "⚡ 720p", file: "Show.S01E02.720p.HDTV-ABC.mkv")
    #expect(nextEpisodeStream([("AIO", uncSame), ("AIO", ready)], matching: ref)?.id == ready.id)
}

@Test func stillWatchingCounter() {
    var c = StillWatchingCounter()
    #expect(!c.promptDue(limit: 3))
    c.autoStarted(); c.autoStarted()
    #expect(!c.promptDue(limit: 3) && c.promptDue(limit: 2))
    c.autoStarted()
    #expect(c.promptDue(limit: 3) && !c.promptDue(limit: 5) && !c.promptDue(limit: 0))
    let changed = c.userInput()
    #expect(changed)
    #expect(c.autoStarts == 0 && !c.promptDue(limit: 2))
    let again = c.userInput()
    #expect(!again)   // schon 0: keine Änderung (kein unnötiges Neuzeichnen)
    #expect(StillWatchingCounter.choices.contains(StillWatchingCounter.defaultLimit))
}

@Test func profileStillWatchingDefaultsAndRoundTrip() throws {
    let old = #"{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","name":"Alt"}"#
    let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
    #expect(p.stillWatchingAfter == 3)
    var q = p; q.stillWatchingAfter = 0
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(q))
    #expect(back.stillWatchingAfter == 0)
}
