import Foundation
import Testing
@testable import PlayerCore

/// Task 3.6 (A-A-1, A-A-2, A-A-14): stream rows in the shapes the common addons send (AIOStreams, Torrentio,
/// MediaFusion, Comet, Prism). All titles, groups and sizes are made up; no tokens, no hostnames.
struct TraitsRow: CustomTestStringConvertible, Sendable {
    var name: String
    var description: String
    var service: String? = nil
    var expectResolution: String?
    var expectChannels: String?
    var expectService: String?

    var testDescription: String { name.replacingOccurrences(of: "\n", with: " ⏎ ") }

    var stream: StreamItem {
        StreamItem(name: name, description: description, url: "https://example.invalid/play",
                   behaviorHints: service.map { StreamBehaviorHints(service: $0) })
    }
}

private let traitsRows: [TraitsRow] = [
    // AIOStreams (default formatter: "[TB⚡] AIOStreams …" plus emoji lines)
    TraitsRow(name: "[TB⚡] AIOStreams 2160p", description: "🎬 Film 2021\n🎥 BluRay REMUX 📺 DV HDR10\n🎧 TrueHD Atmos 7.1\n📦 58.3 GB",
              expectResolution: "2160p", expectChannels: "7.1", expectService: "TB"),
    TraitsRow(name: "[TB⚡] AIOStreams 1080p", description: "Film.2020.1080p.WEB-DL.AAC2.0.H.264-GRP\n💾 5.1 GB",
              expectResolution: "1080p", expectChannels: "2.0", expectService: "TB"),
    TraitsRow(name: "[TB⚡] AIO 2160p", description: "🎞️ WEB-DL 🎧 DDP5.1 Atmos 📦 7.1 GB",
              expectResolution: "2160p", expectChannels: "5.1", expectService: "TB"),
    TraitsRow(name: "[AD+] AIOStreams 720p", description: "Serie.S01E01.720p.HDTV.x264-GRP 🔊 2.0 📦 2.0 GB",
              expectResolution: "720p", expectChannels: "2.0", expectService: "AD"),
    TraitsRow(name: "[TB⚡] AIO", description: "🎬 Film.2021.1080p.UHD.BluRay.DDP7.1.DoVi.x265-GRP.mkv",
              expectResolution: "1080p", expectChannels: "7.1", expectService: "TB"),
    TraitsRow(name: "[PM⚡] AIOStreams 4K", description: "Film.2020.4K.WEB.DDP5.1.HDR",
              expectResolution: "2160p", expectChannels: "5.1", expectService: "PM"),
    TraitsRow(name: "[DL+] AIOStreams UHD", description: "Film.2019.UHD.BluRay.x265",
              expectResolution: "2160p", expectChannels: nil, expectService: "DL"),
    TraitsRow(name: "AIOStreams 2160p [WEB-DL] [DV]", description: "Film.2023.2160p.WEB-DL.DDP5.1.Atmos.DV.H.265-GRP",
              service: "torbox", expectResolution: "2160p", expectChannels: "5.1", expectService: "TB"),
    TraitsRow(name: "TB⚡ AIOStreams 1080p", description: "Film.2014.1080p.BluRay.DTS.5.1.x264-GRP\n📦 11.0 GB",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "TB"),
    TraitsRow(name: "⚡RD+ AIO 720p", description: "Serie.S03E02.720p.WEB-DL.DDP2.0.H.264-GRP 📦 0.9 GB",
              expectResolution: "720p", expectChannels: "2.0", expectService: "RD"),
    TraitsRow(name: "[EN⚡] AIOStreams 1080p Easynews", description: "Film.2012.1080p.WEB-DL.DD+5.1.H.264-GRP\n📦 4.5 GB",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "NZB"),
    TraitsRow(name: "[TB⚡] AIO 1080p", description: "Film.2011.1080p.BluRay.AAC2.0\n📦 7.1 GiB",
              expectResolution: "1080p", expectChannels: "2.0", expectService: "TB"),
    TraitsRow(name: "[RD+] AIOStreams", description: "Film.2021.1080p.WEB.H.264 ⏱ 5.1 Mbps 📦 3.2 GB",
              expectResolution: "1080p", expectChannels: nil, expectService: "RD"),
    TraitsRow(name: "[TB⚡] AIO 1440p", description: "Film.2022.1440p.WEB-DL.AAC2.0",
              expectResolution: "1440p", expectChannels: "2.0", expectService: "TB"),
    TraitsRow(name: "[AD+] AIO 2160p", description: "Film.2019.2160p.BluRay.REMUX.HEVC.TrueHD7.1.Atmos-GRP 📦 70.4 GB",
              expectResolution: "2160p", expectChannels: "7.1", expectService: "AD"),
    TraitsRow(name: "[TB⚡] AIO 1080p", description: "Serie.S01E03.1080p.WEB-DL.Opus5.1.AV1-GRP 📦 1.1 GB",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "TB"),
    TraitsRow(name: "[TB⏳] AIO 720p", description: "Film.2010.720p.BluRay.x264 📦 5.1 GB",
              expectResolution: "720p", expectChannels: nil, expectService: "TB"),
    TraitsRow(name: "AIOStreams 1080p", description: "Film.2008.1080p.BluRay.DD5.1.x264 📦 7.1 GB",
              service: "realdebrid", expectResolution: "1080p", expectChannels: "5.1", expectService: "RD"),
    TraitsRow(name: "Real-Debrid | AIO 1080p", description: "Film.2007.1080p.WEB.DDP5.1",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "RD"),
    TraitsRow(name: "AIOStreams 2160p [HDR10+] [DD+] [WEB-DL]", description: "Film.2024.2160p.WEB-DL.HDR10+.H.265-GRP",
              expectResolution: "2160p", expectChannels: nil, expectService: nil),
    TraitsRow(name: "[TB⚡] AIO 2160p [DV] [TRUEHD 7.1]", description: "Film.2021.2160p.BluRay.REMUX.TrueHD.7.1",
              expectResolution: "2160p", expectChannels: "7.1", expectService: "TB"),
    TraitsRow(name: "[TB⚡] AIOStreams UHD", description: "Film.2021.1080p.UHD.BluRay.x265.10bit.DDP5.1",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "TB"),
    TraitsRow(name: "[OC+] AIO", description: "Film.2003.DVDRip.XviD.AC3.5.1 💾 1.4 GB",
              expectResolution: nil, expectChannels: "5.1", expectService: "OC"),
    // Bracketed quality tags without a service
    TraitsRow(name: "1080p [WEB-DL]", description: "Film.2019.1080p.WEB-DL.DD5.1.H.264-GRP",
              expectResolution: "1080p", expectChannels: "5.1", expectService: nil),
    TraitsRow(name: "1080p [GERMAN DL]", description: "Film.2020.German.DL.1080p.BluRay.x264-GRP 💾 9.8 GB",
              expectResolution: "1080p", expectChannels: nil, expectService: nil),
    // Torrentio ("[RD+] Torrentio\n4k", description = file name, 👤 seeders, 💾 size, ⚙️ source)
    TraitsRow(name: "[RD+] Torrentio\n1080p", description: "Film.2021.1080p.UHD.BluRay.DDP7.1.DoVi.x265-GRP.mkv\n👤 52 💾 14.2 GB ⚙️ ThePirateBay",
              expectResolution: "1080p", expectChannels: "7.1", expectService: "RD"),
    TraitsRow(name: "Torrentio\n4k DV | HDR", description: "Film.2022.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-GRP\n👤 120 💾 18.4 GB ⚙️ 1337x",
              expectResolution: "2160p", expectChannels: "5.1", expectService: nil),
    TraitsRow(name: "[RD+] Torrentio\n4k", description: "Film.2018.UHD.BluRay.2160p.TrueHD.Atmos.7.1.HEVC.REMUX-GRP\n👤 33 💾 61.2 GB",
              expectResolution: "2160p", expectChannels: "7.1", expectService: "RD"),
    TraitsRow(name: "[RD download] Torrentio\n1080p", description: "Film.2017.1080p.BluRay.DTS-HD.MA.5.1.x264-GRP\n👤 18 💾 12.3 GB",
              expectResolution: "1080p", expectChannels: "5.1", expectService: nil),
    TraitsRow(name: "Torrentio\n480p", description: "Film.1999.480p.DVDRip.AC3.2.0-GRP\n👤 4 💾 700 MB",
              expectResolution: "480p", expectChannels: "2.0", expectService: nil),
    TraitsRow(name: "[RD+] Torrentio\n1080p", description: "Film.2021.MULTi.1080p.4K.Remaster.BluRay.x264-GRP\n👤 9 💾 10.5 GB",
              expectResolution: "1080p", expectChannels: nil, expectService: "RD"),
    TraitsRow(name: "Torrentio\n1080p", description: "Konzert.2019.1080p.BluRay.FLAC2.0.x264-GRP\n👤 7 💾 8.1 GB",
              expectResolution: "1080p", expectChannels: "2.0", expectService: nil),
    TraitsRow(name: "[PM+] Torrentio\n720p", description: "Serie.S05E10.720p.HDTV.x264-GRP\n👤 3 💾 350 MB",
              expectResolution: "720p", expectChannels: nil, expectService: "PM"),
    TraitsRow(name: "[RD+] Torrentio\n4k HDR", description: "Film.2020.HDR.2160p.WEB.h265-GRP\n👤 61 💾 15.6 GB",
              expectResolution: "2160p", expectChannels: nil, expectService: "RD"),
    // MediaFusion
    TraitsRow(name: "MediaFusion ElfHosted RD⚡ 4K", description: "Film 2021 2160p HDR\n💾 22.5 GB 👤 15\n🔊 DTS 5.1",
              expectResolution: "2160p", expectChannels: "5.1", expectService: "RD"),
    TraitsRow(name: "MediaFusion ElfHosted 🧲 P2P 1080p", description: "📂 Film.2016.1080p.BluRay.x264.AAC5.1-GRP\n💾 2.0 GB 👥 40",
              expectResolution: "1080p", expectChannels: "5.1", expectService: nil),
    // Comet ("[TORBOX⚡] Comet 1080p", 💿 file name, 💾 size)
    TraitsRow(name: "[TORBOX⚡] Comet 1080p", description: "💿 Film.2015.1080p.BluRay.DDP5.1.x265-GRP\n💾 6.4 GB 🔎 Indexer",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "TB"),
    TraitsRow(name: "[RD⚡] Comet 4K", description: "💿 Film.2019.2160p.UHD.BluRay.REMUX.HDR.HEVC.TrueHD.7.1-GRP\n💾 55.0 GB",
              expectResolution: "2160p", expectChannels: "7.1", expectService: "RD"),
    TraitsRow(name: "[TB⬇️] Comet 720p", description: "💿 Serie.S02E05.720p.WEB.h264-GRP\n💾 1.2 GB",
              expectResolution: "720p", expectChannels: nil, expectService: nil),
    // Prism-style formatter
    TraitsRow(name: "[TB+] Prism 🎫", description: "Film 2020 1080p WEB-DL 🎧 EAC3 5.1 💾 3.4 GB",
              expectResolution: "1080p", expectChannels: "5.1", expectService: "TB"),
]

@Test(arguments: traitsRows)
func streamTraitsTable(_ row: TraitsRow) {
    let t = StreamTraits.parse(row.stream)
    #expect(t.resolution == row.expectResolution)
    #expect(t.channels == row.expectChannels)
    #expect(t.service == row.expectService)
}

@Test func streamTraitsTableHasFortyRows() {
    #expect(traitsRows.count == 40)
}
