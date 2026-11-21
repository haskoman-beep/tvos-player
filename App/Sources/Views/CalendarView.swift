import SwiftUI
import PlayerCore

/// Kalender (Spec §7a.3): Folgen der Serien aus Weiterschauen und Merkliste, gestern bis 14 Tage voraus, nach Tag.
struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var episodes: [UpcomingEpisode] = []
    @State private var loaded = false

    var body: some View {
        let days = Upcoming.days(episodes, today: Date(), calendar: Upcoming.localCalendar)
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 50) {
                Text("Kalender").font(.title2.bold()).padding(.leading, 60)
                if model.tmdb == nil {
                    CalendarHint(text: "TMDB-Key fehlt (Einstellungen → Dienste & Schlüssel).")
                } else if !loaded {
                    ProgressView().padding(.leading, 60)
                } else if days.isEmpty {
                    CalendarHint(text: "Keine neuen Folgen in den nächsten 14 Tagen")
                } else {
                    ForEach(days, id: \.label) { day in
                        VStack(alignment: .leading, spacing: 18) {
                            Text(day.label).font(.title3.bold()).padding(.leading, 60)
                            Strip {
                                ForEach(day.items) { e in
                                    NavigationLinkish(route: .detail(e.seriesPreview), onActivate: { $0 },
                                                      label: CalendarTile(episode: e))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .task(id: model.profile.id) {
            episodes = await model.upcoming()
            loaded = true
        }
    }
}

/// Hinweis statt Kacheln (kein TMDB-Key, keine Folgen). Ist zugleich das Fokusziel der Seite, sonst gäbe es
/// im Inhalt nichts Fokussierbares und Zurück schlösse die App statt in die Seitenleiste zu führen.
private struct CalendarHint: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary).frame(height: 120).padding(.leading, 60)
            .quietFocusTarget()
    }
}

extension View {
    /// Fokusziel ohne sichtbare Hervorhebung für Seiten, die nur einen Hinweis zeigen.
    /// Ohne Fokusziel im Inhalt landet der Fokus nirgends (oder bleibt in der Seitenleiste), und tvOS wertet
    /// Zurück als „App verlassen“. Mit diesem Ziel führt Zurück wie in den anderen Bereichen in die Seitenleiste.
    func quietFocusTarget() -> some View {
        Button {} label: { self.frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(QuietFocusStyle())
    }
}

/// Zeigt nur das Label: kein Fokusrahmen, kein Anheben, keine Akzentfarbe.
private struct QuietFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// Querformat-Kachel: Standbild der Folge (sonst Serienhintergrund bzw. Poster), Serie und „S2 F5 · Titel“.
struct CalendarTile: View {
    let episode: UpcomingEpisode

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: episode.still ?? episode.background ?? episode.poster, maxPixels: 900)
                .frame(width: 440, height: 248).clipped()
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.seriesName).font(.headline).lineLimit(1)
                Text(episode.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .shadow(radius: 6).padding(.horizontal, 14).padding(.bottom, 16)
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
                        Text(item.name).font(.headline).shadow(radius: 6).padding(.horizontal, 14).padding(.bottom, 24)
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
                Text(label).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule()).padding(8)
            }
        }
    }
}
