import SwiftUI
import PlayerCore

/// Eine Startseiten-Reihe im gewählten Stil.
/// `onActivate` bekommt das Ziel und gibt zurück, ob navigiert werden soll (nil = Klick verschlucken).
struct HomeRowView: View {
    @EnvironmentObject var model: AppModel
    let row: HomeRow
    let onActivate: (Route) -> Route?
    let onLongPress: () -> Void
    var interactive = true
    @State private var items: [MetaPreview] = []
    @State private var loaded = false
    /// Startseite mit Hero: fokussierte Kachel meldet sich (nil außerhalb der Startseite).
    @Environment(HomeFocus.self) private var homeFocus: HomeFocus?
    @FocusState private var focusedRoute: Route?
    /// Welle C-b (#19): Fokus-Gedächtnis je Reihe (nil außerhalb der Startseite).
    @Environment(\.homeRowFocusMemory) private var focusMemory
    /// Welle C-d: nachgezogene Sendezeiten (TVmaze) → Reihe „Heute neu“ lädt aus dem Kalender-Cache neu.
    @ObservedObject private var upcomingRevision = UpcomingRevision.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if row.style != .hero {
                Text(title).font(.title3.bold()).padding(.leading, 60)
            }
            content
                .disabled(!interactive)
                .focusSection()
                .defaultFocus($focusedRoute, rememberedRoute, priority: .userInitiated)
        }
        .task(id: row.content.key + (row.content == .list(.continueWatching) ? "\(model.progress.entries.count)-\(model.progress.continueWatching().first?.updated.timeIntervalSince1970 ?? 0)" : "") + model.catalogStamp(row.content)
               + (row.content == .list(.upcoming) ? "|r\(upcomingRevision.value)" : "")) {
            guard case .list(let s) = row.content else { return }
            items = await model.items(s); loaded = true
        }
        .onChange(of: focusedRoute) { _, r in
            guard let r, focusMemory?.state.covered != true else { return }   // verdeckte Startseite: nichts merken
            focusMemory?.state.record(row: row.id.uuidString, item: r.heroPreview.id)
            MainThreadWatchdog.note("Fokus \(r.heroPreview.id)")
            if let homeFocus { homeFocus.set(r.heroPreview) { StreamPrefetcher.shared.request(r, model: model) } }
        }
    }

    private var emptyText: String {
        if row.content == .list(.continueWatching) { return "Noch nichts angefangen." }
        if model.tmdb == nil { return "TMDB-Key fehlt (Einstellungen)" }
        if row.content == .list(.upcoming) { return "Heute keine neuen Folgen." }
        return "Keine Einträge"
    }

    private var title: String {
        switch row.content {
        case .list(let s): s.title
        case .collection(let id): model.collection(id)?.title ?? "Collection"
        }
    }

    @ViewBuilder private var content: some View {
        switch row.content {
        case .collection(let id):
            let folders = model.collection(id)?.folders ?? []
            Strip {
                ForEach(folders) { f in
                    card(.folder(f)) { FolderTile(folder: f, logoStyle: row.style == .logoTiles) }
                }
            }
        case .list:
            if loaded && items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary).padding(.leading, 60).frame(height: 120)
            } else {
                Strip(expands: row.style == .poster) {
                    ForEach(Array((row.style == .top10 ? Array(items.prefix(10)) : items).enumerated()), id: \.element.id) { i, m in
                        card(route(for: m)) {
                            if row.content == .list(.upcoming) {
                                UpcomingTodayCard(item: m, landscape: row.style == .landscape || row.style == .hero)
                            } else {
                                switch row.style {
                                case .hero: HeroCard(item: m)
                                case .landscape: LandscapeCard(item: m).equatable()
                                case .top10: Top10Card(item: m, rank: i + 1).equatable()
                                default: PosterCard(item: m).equatable()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Zuletzt fokussierte Kachel dieser Reihe, sofern noch vorhanden (sonst entscheidet die Fokus-Engine).
    private var rememberedRoute: Route? {
        guard let id = focusMemory?.state.remembered(row: row.id.uuidString) else { return nil }
        switch row.content {
        case .collection(let c):
            return model.collection(c)?.folders.first { "folder:\($0.id)" == id }.map { Route.folder($0) }
        case .list:
            return items.first { $0.id == id }.map(route(for:))
        }
    }

    /// Weiterschauen mit gemerkter Quelle → direkt abspielen, sonst Detailseite.
    private func route(for m: MetaPreview) -> Route {
        guard row.content == .list(.continueWatching),
              let e = model.progress.continueWatching().first(where: { $0.item.id == m.id }),
              model.progress.lastSource(for: e.id) != nil else { return .detail(m) }
        let title = e.season.map { "\(m.name) S\($0)E\(e.episode ?? 0)" } ?? m.name
        return .streams(PlayRequest(type: e.season == nil ? "movie" : "series", id: e.id, title: title, item: m,
                                    season: e.season, episode: e.episode, resumeLastSource: true))
    }

    private func card<L: View>(_ route: Route, @ViewBuilder label: () -> L) -> some View {
        NavigationLinkish(route: route, onActivate: onActivate, label: label())
            .focused($focusedRoute, equals: route)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in onLongPress() })
    }
}

/// Wie NavigationLink, aber das Ziel kann verschluckt werden (nach langem Druck).
struct NavigationLinkish<L: View>: View {
    let route: Route
    let onActivate: (Route) -> Route?
    let label: L
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button { if let r = onActivate(route) { navigate(r) } } label: { label }
            .buttonStyle(.card)
    }
}

private struct NavigateKey: EnvironmentKey {
    /// Ohne gesetztes Ziel: nichts tun, aber im Log sichtbar machen (Diagnose für verlorene Umgebung).
    static let defaultValue: (Route) -> Void = { r in
        Task { @MainActor in RemoteLog.info("nav", "kein Navigationsziel für \(r.logName)") }
    }
}

extension EnvironmentValues {
    var navigate: (Route) -> Void {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}

struct Strip<C: View>: View {
    @EnvironmentObject var model: AppModel
    /// Nur Posterreihen klappen auf (und bekommen den Platz am Reihenende).
    var expands = false
    @ViewBuilder let content: C
    /// Aufklappende Poster ändern die Reihenbreite: die Reihe bleibt am fokussierten Element verankert.
    @State private var anchorID: String?
    var body: some View {
        let a = model.profile.appearance
        let s = a.cardSize.scale
        let expand = a.expandPosters && expands
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 40 * s) { content }
                .scrollTargetLayout()
                .padding(.vertical, 30 * s)
        }
        .contentMargins(.leading, 60, for: .scrollContent)
        // Platz rechts, damit auch die letzten Karten aufgeklappt (640·s) an den linken Rand rücken können.
        .contentMargins(.trailing, expand ? max(60, 1920 - 60 - 640 * s) : 60, for: .scrollContent)
        .scrollPosition(id: $anchorID, anchor: .leading)
        .environment(\.cardScale, s)
        .environment(\.expandPosters, expand)
        // Ohne eigene Animation: läuft in der Transaktion des Aufklappens mit, damit nur eine Bewegung entsteht.
        .environment(\.anchorFocusedCard, { id in
            guard anchorID != id else { return }
            anchorID = id
        })
    }
}


struct PosterCard: View {
    let item: MetaPreview
    @Environment(\.isFocused) private var focused
    @Environment(\.cardScale) private var scale
    @Environment(\.expandPosters) private var expandable
    @Environment(\.anchorFocusedCard) private var anchor
    /// Fokus + 350 ms Ruhe → Querformat mit Hintergrund und Logo.
    @State private var expanded = false

    var body: some View {
        let h = 360 * scale
        // Welle E-a: Plaketten nie unten auf dem Bild; bei „Unten“ sitzen sie im Streifen darunter (PosterBadgeBand).
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RemoteImage(url: item.poster)
                    .frame(width: 240 * scale, height: h).clipped()
                if expanded { ExpandedPoster(item: item).transition(.opacity) }
            }
            .frame(width: (expanded ? h * 16 / 9 : 240 * scale), height: h, alignment: .leading).clipped()
            .overlay(alignment: .bottomLeading) {
                if item.poster == nil && !expanded { Text(item.name).font(.caption).padding(10) }
            }
            .overlay { CardStateOverlay(itemID: item.id) }
            PosterBadgeBand(width: expanded ? h * 16 / 9 : 240 * scale, scale: scale)
        }
        .overlay { PosterQualityBadges(item: item, scale: scale) }
        .task(id: focused && expandable) {
            guard focused && expandable else {
                if expanded { withAnimation(.easeInOut(duration: 0.25)) { expanded = false } }
                return
            }
            // Schnelles Durchscrollen bricht hier ab: kein Aufklappen, keine Bildanforderung.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            // Verankern nur zusammen mit dem Aufklappen: schnelles Durchscrollen löst kein Programm-Scrollen aus.
            withAnimation(.easeInOut(duration: 0.25)) { expanded = true; anchor(item.id) }
        }
    }
}

/// Aufgeklappter Inhalt: Hintergrundbild (Größe nach Anzeige, ImageTarget) + Logo (oder Titel). Existiert erst nach der Ruhezeit,
/// deshalb wird das Bild auch erst dann angefordert.
private struct ExpandedPoster: View {
    let item: MetaPreview
    @Environment(\.displayScale) private var displayScale
    @Environment(\.heroBackdropShared) private var heroShared
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                // Mit Hero: gleiche Variante wie der Vollbild-Hintergrund (gleiche Adresse), ein Download, ein Bitmap.
                // Ohne Hero: nach gezeichneter Größe.
                RemoteImage(url: item.background ?? item.poster, fixedTarget: heroShared ? .fullScreen(scale: displayScale) : nil)
                    .frame(width: g.size.width, height: g.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .bottom, endPoint: .center)
                Group {
                    // Breite begrenzt (rechts bleibt Platz für Bild und Plaketten oben rechts).
                    let maxW = g.size.width * PosterQualityBadges.leadingContentMaxFraction
                    if let logo = item.logo {
                        RemoteImage(url: logo, maxPixels: 600, fit: true)
                            .frame(maxWidth: maxW, maxHeight: g.size.height * 0.3, alignment: .bottomLeading)
                    } else {
                        Text(item.name).font(.headline).lineLimit(2).shadow(radius: 6)
                            .frame(maxWidth: maxW, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 26)
            }
        }
    }
}

struct LandscapeCard: View {
    let item: MetaPreview
    @Environment(\.cardScale) private var scale
    var body: some View {
        RemoteImage(url: item.background ?? item.poster, maxPixels: 900)
            .frame(width: 440 * scale, height: 248 * scale).clipped()
            .overlay(alignment: .bottomLeading) {
                Text(item.name).font(.headline).shadow(radius: 6).padding(.horizontal, 14).padding(.bottom, 24)
            }
            .overlay { CardStateOverlay(itemID: item.id) }
    }
}

struct HeroCard: View {
    let item: MetaPreview
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.background ?? item.poster).frame(width: 1600, height: 620).clipped()
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 12) {
                Text(item.name).font(.system(size: 64, weight: .heavy))
                if let d = item.description { Text(d).lineLimit(2).frame(maxWidth: 1000, alignment: .leading) }
                Text([item.releaseInfo, item.imdbRating.map { "★ \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            .padding(50)
        }
        .frame(width: 1600, height: 620)
    }
}

struct Top10Card: View {
    let item: MetaPreview
    let rank: Int
    @Environment(\.cardScale) private var scale
    var body: some View {
        HStack(alignment: .bottom, spacing: -30 * scale) {
            Text("\(rank)").font(.system(size: 220 * scale, weight: .black)).foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 8)
            PosterCard(item: item)
        }
    }
}

struct FolderTile: View {
    let folder: Folder
    let logoStyle: Bool
    @Environment(\.cardScale) private var scale
    var body: some View {
        if logoStyle {
            ZStack {
                Color.white.opacity(0.08)
                if let l = folder.logo { RemoteImage(url: l, maxPixels: 800, fit: true).padding(30 * scale) } else { Text(folder.title).font(.headline) }
            }
            .frame(width: 320 * scale, height: 180 * scale)
        } else {
            RemoteImage(url: folder.coverImage ?? folder.backdrop)
                .frame(width: 440 * scale, height: 248 * scale).clipped()
                .overlay(alignment: .bottomLeading) {
                    if folder.coverImage == nil || folder.showsTitleOverImage { Text(folder.title).font(.headline).shadow(radius: 4).padding(14) }
                }
        }
    }
}

/// Kachelzustand: Haken (gesehen), Folge + Restzeit oben, Fortschrittsbalken unten.
struct CardStateOverlay: View {
    @EnvironmentObject var model: AppModel
    let itemID: String
    /// „Heute neu“ zeigt oben links sein eigenes Folgen-Label; dann entfällt hier die obere Kapsel.
    @Environment(\.hidesCardTopLabel) private var hidesTopLabel

    var body: some View {
        if let st = model.progress.cardState(itemID: itemID) {
            ZStack {
                if st.watched {
                    Image(systemName: "checkmark.circle.fill").font(.title3)
                        .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                        .shadow(radius: 4).padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                let top = [st.episode, st.remainingSeconds.map { "noch \(max(1, Int($0 / 60))) min" }].compactMap { $0 }.joined(separator: " · ")
                if !top.isEmpty && !hidesTopLabel {
                    Text(top).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: Capsule()).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if let f = st.fraction, f > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.white).frame(width: g.size.width * min(1, f))
                        }
                    }
                    .frame(height: 6).padding(.horizontal, 10).padding(.bottom, 10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Kartengröße und Aufklappen (Umgebung, von `Strip` gesetzt)

private struct CardScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
/// Außerhalb der Startseiten-Reihen (Detail, Person) klappt nichts auf.
private struct ExpandPostersKey: EnvironmentKey { static let defaultValue = false }
private struct AnchorFocusedCardKey: EnvironmentKey { static let defaultValue: (String) -> Void = { _ in } }
private struct HidesCardTopLabelKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// `appearance.cardSize.scale` für die Kartenmaße.
    var cardScale: CGFloat {
        get { self[CardScaleKey.self] }
        set { self[CardScaleKey.self] = newValue }
    }
    var expandPosters: Bool {
        get { self[ExpandPostersKey.self] }
        set { self[ExpandPostersKey.self] = newValue }
    }
    /// Fokussierte, aufklappbare Karte meldet ihre ID; die Reihe verankert die Scrollposition daran.
    var anchorFocusedCard: (String) -> Void {
        get { self[AnchorFocusedCardKey.self] }
        set { self[AnchorFocusedCardKey.self] = newValue }
    }
    /// Blendet in `CardStateOverlay` die Folgen/Restzeit-Kapsel oben links aus (Haken und Balken bleiben).
    var hidesCardTopLabel: Bool {
        get { self[HidesCardTopLabelKey.self] }
        set { self[HidesCardTopLabelKey.self] = newValue }
    }
}
