import SwiftUI
import PlayerCore

/// Kopfzeile der Steuerleiste: Serienname und "S01E02 · Episodentitel" (Film/Trailer: nur Titel).
/// Nur aus Daten, die der PlayRequest schon trägt; nichts wird nachgeladen.
struct PlayerHeading: Equatable {
    var title: String
    var episodeLine: String?

    init(title: String, episodeLine: String? = nil) {
        self.title = title; self.episodeLine = episodeLine
    }

    init(_ r: PlayRequest) {
        guard let s = r.season, let e = r.episode else { self.init(title: r.title); return }
        let epTitle = r.episodes.first { $0.season == s && $0.episode == e }?.title
        self.init(title: r.item.name, episodeLine: MediaLabels.episodeLine(season: s, episode: e, title: epTitle))
    }
}
