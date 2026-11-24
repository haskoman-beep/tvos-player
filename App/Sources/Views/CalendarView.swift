import SwiftUI
import PlayerCore

/// Kalender (Spec §7a.3): Folgen der Serien aus Weiterschauen und Merkliste, gestern bis 14 Tage voraus, nach Tag.
struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var episodes: [UpcomingEpisode] = []
    @ObservedObject private var revision = UpcomingRevision.shared   // Sendezeiten kommen nachträglich (Welle C-d)
    @State private var loaded = false
    @FocusState private var tile: String?
    @FocusState private var headerFocused: Bool
    /// Kacheln sind in dieser Ansicht schon einmal erschienen (Fokus-Übergabe von der Kopfzeile nur beim ersten Mal).
    @State private var tilesShown = false

    var body: some View {
        let days = Upcoming.days(episodes, today: Date(), calendar: Upcoming.localCalendar)
        let showTiles = model.tmdb != nil && loaded && !days.isEmpty
        let firstTile = showTiles ? days.first?.items.first?.id : nil
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                // Kopfzeile mit Titel und Lade-/Hinweiszeile = festes Fokusziel der Seite (bleibt in allen Zuständen
                // dasselbe). Ohne Fokussierbares im Inhalt (Laden, Hinweis) schlösse Zurück sonst die App.
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Kalender").textRole(.pageTitle).padding(.leading, Theme.Space.edge)
                        .accessibilityAddTraits(.isHeader)
                    if model.tmdb == nil {
                        CalendarHint(text: "TMDB-Key fehlt (Einstellungen → Dienste & Schlüssel).")
                    } else if !loaded {
                        ProgressView().padding(.leading, Theme.Space.edge)
                    } else if days.isEmpty {
                        CalendarHint(text: "Keine neuen Folgen in den nächsten 14 Tagen")
                    }
                }
                .quietFocusTarget()
                .focused($headerFocused)
                if showTiles {
                    ForEach(days, id: \.label) { day in
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(day.label).textRole(.sectionTitle).padding(.leading, Theme.Space.edge)
                                .accessibilityAddTraits(.isHeader)
                            Strip(kind: .landscape) {
                                ForEach(day.items) { e in
                                    NavigationLinkish(route: .detail(e.seriesPreview), onActivate: { $0 },
                                                      label: CalendarTile(episode: e))
                                        .focused($tile, equals: e.id)
                                        .tileMenu(e.seriesPreview)   // Wave L
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Space.edgeVertical)
        }
        // A1: dunkler, ruhiger Grund wie die Bedienseiten.
        .settingsSurface()
        // Mit Kacheln führt der Weg aus der Seitenleiste auf die erste Kachel, nicht auf die Kopfzeile.
        .defaultFocus($tile, firstTile, priority: .userInitiated)
        // Fokus lag beim Laden auf der Kopfzeile: beim ersten Erscheinen der Kacheln einmal auf die erste Kachel.
        // Nur dieses eine Mal, wer später per ▲ auf die Kopfzeile geht, bleibt dort.
        .onChange(of: showTiles) { _, shown in
            guard shown, !tilesShown else { return }
            tilesShown = true
            guard let firstTile, tile == nil, headerFocused else { return }
            DispatchQueue.main.async {
                guard tile == nil, headerFocused else { return }
                tile = firstTile
                RemoteLog.info("kalender", "Fokus von der Kopfzeile auf die erste Kachel")
            }
        }
        // A-B-5: `catalogWake` also rises when a new local day began, so the window (yesterday … +14) moves along.
        .task(id: "\(model.profile.id)|\(revision.value)|\(model.catalogWake)") {
            episodes = await model.upcoming()
            loaded = true
        }
    }
}

/// Hinweis statt Kacheln (kein TMDB-Key, keine Folgen); wird hell, solange die Kopfzeile den Fokus hat.
private struct CalendarHint: View {
    let text: String
    var body: some View {
        Text(text).quietHintStyle().frame(height: 120).padding(.leading, Theme.Space.edge)
    }
}

/// Querformat-Kachel: Standbild der Folge (sonst Serienhintergrund bzw. Poster), Serie und „S2 F5 · Titel“.
struct CalendarTile: View {
    let episode: UpcomingEpisode

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: episode.still ?? episode.background ?? episode.poster, maxPixels: 900)
                .frame(width: 440, height: 248).clipped()
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: Theme.Space.xs / 2) {
                Text(episode.seriesName).textRole(.rowTitleEmphasis).lineLimit(1)
                Text(episode.label).textRole(.rowDetail).lineLimit(1)
            }
            .shadow(radius: 6).padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.s)
        }
        .frame(width: 440, height: 248)
    }
}

/// Kachel der Reihe „Heute neu“: Serie mit Folge als Label (`releaseInfo`, z. B. „S2 F5“).
struct UpcomingTodayCard: View {
    let item: MetaPreview
    var landscape = false
    /// Kartengröße aus der Darstellung (von `Strip` gesetzt, sonst 1); nur Querformat, Hochformat skaliert `PosterCard` selbst.
    @Environment(\.cardScale) private var scale

    var body: some View {
        Group {
            if landscape {
                RemoteImage(url: item.background ?? item.poster, maxPixels: 900)
                    .frame(width: 440 * scale, height: 248 * scale).clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text(item.name).textRole(.rowTitleEmphasis).shadow(radius: 6)
                            .padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.m)
                    }
            } else {
                // Hochformat wie alle Poster-Reihen: Kartengröße, Aufklappen, Scroll-Anker.
                // Die Fortschritts-Kapsel oben links würde das Folgen-Label verdecken → ausgeblendet.
                PosterCard(item: item)
                    .environment(\.hidesCardTopLabel, true)
            }
        }
        .overlay(alignment: .topLeading) {
            if let label = item.releaseInfo {
                ThemeBadge(kind: .status(nil, onImage: true), text: label).padding(Theme.Space.xs)
            }
        }
    }
}
