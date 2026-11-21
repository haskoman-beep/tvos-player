import Foundation
import VideoToolbox
import PlayerCore

/// Welle C-d: Quellenliste nach Sprache, Cache-Status, AV1-Dekoder und Dienst ordnen (Regeln in SourceRanking).
enum DecoderCapabilities {
    /// VideoToolbox dekodiert AV1 ('av01') in Hardware. Einmal abgefragt.
    static let av1Hardware: Bool = VTIsHardwareDecodeSupported(CMVideoCodecType(0x6176_3031))
}

extension AppModel {
    var sourceRankContext: SourceRankContext {
        SourceRankContext(audioPriority: profile.audioPriority, av1Hardware: DecoderCapabilities.av1Hardware)
    }

    /// Geordnete Quellenliste; mit „Quellen klug ordnen“ aus bleibt die Reihenfolge der Addons.
    func orderedStreams(_ list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        guard profile.sources.smartOrder, list.count > 1 else { return list }
        let ctx = sourceRankContext
        let out = SourceRanking.order(list, context: ctx)
        let moved = zip(list, out).filter { $0.0.stream.id != $0.1.stream.id }.count
        if moved > 0 {
            RemoteLog.info("streams", "Sortiert: \(moved)/\(list.count) verschoben · Sprache \(ctx.primaryLanguage ?? "-") · AV1-HW \(ctx.av1Hardware ? "ja" : "nein")")
        }
        return out
    }
}
