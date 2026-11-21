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
        return out
    }

    /// Reihenfolge für Weiterschauen, Rückfall und nächste Folge: immer die kluge Ordnung, egal wie angezeigt wird.
    func autoOrderedStreams(_ list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        StreamListOrder.automatic(list, context: sourceRankContext)
    }
}
