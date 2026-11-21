import Foundation
import Testing
@testable import PlayerCore

@Test func parsesRemuxTraits() {
    let s = StreamItem(name: "[TB⚡] AIOStreams 2160p", description: "Breaking.Bad.S01E02.2160p.DV.HDR.TrueHD.Atmos 🇩🇪 🇬🇧 💾 45.2 GB", url: "https://x/y.mkv")
    let t = StreamTraits.parse(s)
    #expect(t.resolution == "2160p")
    #expect(t.hdr == ["DV", "HDR"])
    #expect(t.audio == ["Atmos", "TrueHD"])
    #expect(t.languages == ["de", "en"])
    #expect(t.sizeBytes == 45_200_000_000)
    #expect(t.cached == true)
}

@Test func cachedFlags() {
    #expect(StreamTraits.parse(StreamItem(name: "[TB⏳] 1080p")).cached == false)
    #expect(StreamTraits.parse(StreamItem(name: "[TB download] 1080p")).cached == false)
    #expect(StreamTraits.parse(StreamItem(name: "Usenet 1080p")).cached == nil)
}

@Test func tokenDoesNotMatchInsideWords() {
    let t = StreamTraits.parse(StreamItem(description: "Movie.DVDRip.x264.DDP5.1"))
    #expect(t.hdr.isEmpty)
    #expect(t.audio == ["DD+"])
}

@Test func playableFilterKeepsOrder() {
    let a = StreamItem(name: "a", url: "https://a/1.mkv")
    let b = StreamItem(name: "b", infoHash: "abc")
    let c = StreamItem(name: "c", url: "nicht eine url")
    let d = StreamItem(name: "d", url: "http://d/2.mp4")
    #expect(playableStreams([a, b, c, d]) == [a, d])
}

@Test func preferredAudioTrackPicksGermanThenEnglish() {
    let tracks = [AudioTrackInfo(id: 0, language: "jpn"), AudioTrackInfo(id: 1, language: "eng", channels: 6),
                  AudioTrackInfo(id: 2, language: "ger", channels: 2), AudioTrackInfo(id: 3, language: "deu", channels: 6)]
    #expect(preferredAudioTrack(tracks, priority: ["de", "en", "orig"])?.id == 3)
    #expect(preferredAudioTrack(Array(tracks.prefix(2)), priority: ["de", "en", "orig"])?.id == 1)
    #expect(preferredAudioTrack([tracks[0]], priority: ["de", "en", "orig"])?.id == 0)
    #expect(preferredAudioTrack([], priority: ["de"]) == nil)
}
