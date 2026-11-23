import Foundation
import VideoToolbox
import PlayerCore

/// Welle C-d: Quellenliste nach Sprache, Cache-Status, AV1-Dekoder und Dienst ordnen (Regeln in SourceRanking).
/// Welle E-b: Anzeige „Wie Addon“ (Standard) oder „Smart (App)“, Dubletten raus; die automatische Wahl nutzt
/// immer die kluge Ordnung (`StreamListOrder`).
enum DecoderCapabilities {
    /// VideoToolbox dekodiert AV1 ('av01') in Hardware. Einmal abgefragt.
    static let av1Hardware: Bool = VTIsHardwareDecodeSupported(CMVideoCodecType(0x6176_3031))
}

extension AppModel {
    var sourceRankContext: SourceRankContext {
        SourceRankContext(audioPriority: profile.audioPriority, av1Hardware: DecoderCapabilities.av1Hardware)
    }

    /// Angezeigte Quellenliste: ohne Dubletten, Reihenfolge nach „Quellen sortieren“.
    func orderedStreams(_ list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        let started = ContinuousClock.now   // Task 1.8: streams.order
        let mode = profile.sources.order
        let ctx = sourceRankContext
        let unique = StreamDedupe.unique(list)   // einmal berechnet, auch für die Log-Zeile (Review E-b M3)
        let out = StreamListOrder.ordered(unique, mode: mode, context: ctx)
        if unique.count < list.count {
            RemoteLog.info("streams", "Dubletten entfernt: \(list.count - unique.count) von \(list.count)")
        }
        if mode == .smart {
            let moved = zip(unique, out).filter { $0.0.stream.id != $0.1.stream.id }.count
            if moved > 0 {
                RemoteLog.info("streams", "Sortiert: \(moved)/\(out.count) verschoben · Sprache \(ctx.primaryLanguage ?? "-") · AV1-HW \(ctx.av1Hardware ? "ja" : "nein")")
            }
        }
        if !list.isEmpty {
            RemoteLog.metric(.streamsOrder, ms: Metric.ms(started.duration(to: ContinuousClock.now)),
                             fields: ["quellen": "\(list.count)", "modus": mode.rawValue])
        }
        return out
    }

    /// Welle G-a: „Sofort abspielen / Beste Wahl“ (Regeln in PlayerCore `BestChoice`): letzte Quelle, sonst die beste
    /// der klugen Ordnung, nie eine im 8-h-Gedächtnis.
    func bestChoice(_ list: [(addon: String, stream: StreamItem)], title: String) -> BestChoice.Pick? {
        let stability = PlaybackStability.shared
        let last = progress.lastSource(for: title).flatMap { $0.contentID == title ? $0 : nil }
        return BestChoice.pick(list, context: sourceRankContext, last: last,
                               isFailed: { stability.isRecentlyFailed($0, title: title) })
    }

    /// Reihenfolge für Weiterschauen, Rückfall und nächste Folge: immer die kluge Ordnung, egal wie angezeigt wird.
    func autoOrderedStreams(_ list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        StreamListOrder.automatic(list, context: sourceRankContext)
    }
}
