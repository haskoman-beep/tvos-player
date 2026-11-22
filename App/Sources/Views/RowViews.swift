import SwiftUI
import PlayerCore

/// Eine Startseiten-Reihe im gewählten Stil.
/// `onActivate` bekommt das Ziel und gibt zurück, ob navigiert werden soll (nil = Klick verschlucken).
struct HomeRowView: View {
    @EnvironmentObject var model: AppModel
    let row: HomeRow
    let onActivate: (Route) -> Route?
    /// Welle F-b2: Kontextmenü der Startseite (langer Druck auf eine Kachel), nil = keins.
    var menu: HomeRowMenu? = nil
    /// Wave F-j: focus enters (true) or leaves (false) this row; set only for the first row of the home page.
    var onFocusInside: ((Bool) -> Void)? = nil
    @State private var items: [MetaPreview] = []
    @State private var loaded = false
    /// Welle F-f: letzte Ladung schlug fehl (Statuskachel „erneut versuchen“).
    @State private var failed = false
    /// Erhöht durch „erneut versuchen“: startet die Ladung neu.
    @State private var retry = 0
    /// Welle F-f: fokussierter Platzhalter bzw. Statuskachel (0); nach dem Laden geht der Fokus an dieselbe Stelle.
    @FocusState private var focusedPlaceholder: Int?
    /// Startseite mit Hero: fokussierte Kachel meldet sich (nil außerhalb der Startseite).
    @Environment(HomeFocus.self) private var homeFocus: HomeFocus?
    @FocusState private var focusedRoute: Route?
    /// Welle C-b (#19): Fokus-Gedächtnis je Reihe (nil außerhalb der Startseite).
    @Environment(\.homeRowFocusMemory) private var focusMemory
    /// Welle C-d: nachgezogene Sendezeiten (TVmaze) → Reihe „Heute neu“ lädt aus dem Kalender-Cache neu.
    @ObservedObject private var upcomingRevision = UpcomingRevision.shared
    /// Welle F-g: Kit-Ladefehler und laufende Ladungen (Statuskachel der Kit-Collections).
    @ObservedObject private var kit = FusionKitStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if row.style != .hero {
                Text(title).textRole(.sectionTitle).padding(.leading, Theme.Space.edge)
                    .accessibilityAddTraits(.isHeader)
            }
            content
                .focusSection()
                .defaultFocus($focusedRoute, rememberedRoute, priority: .userInitiated)
        }
        .task(id: row.content.key + (row.content == .list(.continueWatching) ? "\(model.progress.entries.count)-\(model.progress.continueWatching().first?.updated.timeIntervalSince1970 ?? 0)" : "") + model.catalogStamp(row.content)
               + (row.content == .list(.upcoming) ? "|r\(upcomingRevision.value)" : "") + "|t\(retry)") {
            guard case .list(let s) = row.content else { return }
            // Welle F-f: geteilte Ladung (AppModel+HomeRows), läuft beim Wegscrollen weiter.
            let r = await model.homeRowItems(s)
            guard !Task.isCancelled else { return }   // abgebrochen (neue Ladung folgt): kein „Keine Einträge“-Flackern
            let placeholder = focusedPlaceholder
            items = r.items; failed = r.failed; loaded = true
            // Fokus lag auf einem Platzhalter: an dieselbe Stelle der fertigen Reihe (bzw. auf die Statuskachel).
            // Erst im nächsten Durchlauf: dann gibt es die Karten schon.
            if let placeholder {
                let p = phase
                var found: Route?
                if case .items = p { found = route(for: displayed[p.focusAfterLoad(placeholder: placeholder)]) }
                let target = found, slot = p.focusAfterLoad(placeholder: placeholder)
                DispatchQueue.main.async {
                    if let target { focusedRoute = target } else { focusedPlaceholder = slot }
                }
            }
        }
        .onChange(of: focusedRoute != nil || focusedPlaceholder != nil) { _, f in onFocusInside?(f) }
        .onAppear { if focusedRoute != nil || focusedPlaceholder != nil { onFocusInside?(true) } }
        .onDisappear { onFocusInside?(false) }
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
        case .collection(let id): model.collection(id)?.title ?? kit.sourceTitle(ofID: id) ?? "Collection"
        }
    }

    /// Welle F-g: Phase der Collection-Reihe (Kit-Datei lädt, schlug fehl, leer, Kacheln).
    private func collectionPhase(_ id: String, _ c: MediaCollection?) -> CollectionRowPhase {
        CollectionRowPhase.of(collectionID: id, folders: c?.folders, kitErrors: kit.errors, kitLoading: kit.loading)
    }

    /// Welle F-f: Phase der Listen-Reihe (jede Phase hat ein Fokusziel, PlayerCore `HomeRowPhase`).
    private var phase: HomeRowPhase { HomeRowPhase(loaded: loaded, failed: failed, count: displayed.count) }

    /// Gezeigte Einträge (Top 10: höchstens zehn).
    private var displayed: [MetaPreview] { row.style == .top10 ? Array(items.prefix(10)) : items }

    @ViewBuilder private var content: some View {
        switch row.content {
        case .collection(let id):
            let c = model.collection(id)
            let p = collectionPhase(id, c)
            switch p {
            case .tiles:
                let folders = c?.folders ?? []
                let line = CollectionArtStats(folders: folders, logoStyle: row.style == .logoTiles).logLine(title: title)
                Strip {
                    ForEach(folders) { f in
                        card(.folder(f)) { FolderTile(folder: f, logoStyle: row.style == .logoTiles) }
                    }
                }
                .task(id: line) { CollectionRowLog.note(row: row.id.uuidString, line: line) }
            case .failed(let key):
                // Welle F-g: Kit-Datei schlug fehl: erreichbare Statuskachel statt ewiger Platzhalter; OK lädt neu.
                Strip {
                    statusTile(p.statusText ?? "", retry: true) {
                        focusedPlaceholder = 0
                        Task { await FusionKitStore.shared.retry(sourceKey: key) }
                    }
                }
                .task(id: "failed|\(key)") { CollectionRowLog.note(row: row.id.uuidString, line: "Collection \(title): Laden fehlgeschlagen") }
            case .empty:
                Strip { statusTile(p.statusText ?? "Keine Einträge", retry: false) }
            case .loading:
                // Fusion-Kit lädt die Collection noch nach: fokussierbare Platzhalter statt leerer Reihe.
                placeholders
            }
        case .list:
            switch phase {
            case .loading:
                placeholders
            case .empty, .failed:
                Strip { statusTile(phase.statusText(empty: emptyText) ?? emptyText, retry: phase == .failed) }
            case .items:
                Strip(expands: row.style == .poster) {
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { i, m in
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

    /// Kachelform der Reihe; „Heute neu“ im Hero-Stil zeigt Querformat-Karten (UpcomingTodayCard).
    private var tileKind: TileKind {
        if row.content == .list(.upcoming), row.style == .hero { return .landscape }
        return PosterSize.kind(for: row.style)
    }

    /// Welle F-f: ladende Reihe, fokussierbare Platzhalter in Endgröße (Höhe springt beim Eintreffen nicht).
    /// Das Kontextmenü gilt auch hier (eine hängende Reihe lässt sich ausblenden oder löschen).
    private var placeholders: some View {
        let n = PosterSize.placeholderCount(for: model.profile.appearance.cardSize, style: row.style)
        return Strip(expands: row.style == .poster) {
            ForEach(0..<n, id: \.self) { i in
                Button {} label: { TilePlaceholder(kind: tileKind, rank: row.style == .top10 ? i + 1 : nil) }
                    .buttonStyle(.card)
                    .focused($focusedPlaceholder, equals: i)
                    .homeRowMenu(menu)
                    .accessibilityLabel("\(title), lädt")
            }
        }
    }

    /// Welle F-f: leere oder fehlgeschlagene Reihe bleibt erreichbar: eine Kachel in Reihenhöhe mit dem Grund;
    /// bei Fehlschlag lädt OK neu.
    /// `action`: eigener Neuversuch (Kit-Collection, Welle F-g); sonst lädt die Listen-Reihe neu.
    private func statusTile(_ text: String, retry canRetry: Bool, action: (() -> Void)? = nil) -> some View {
        Button {
            guard canRetry else { return }
            RemoteLog.info("home", "Reihe erneut laden: \(title)")
            if let action { action(); return }
            loaded = false; failed = false; retry += 1
            focusedPlaceholder = 0
        } label: {
            TileStatus(kind: tileKind, text: text, symbol: canRetry ? "arrow.clockwise" : nil)
        }
        .buttonStyle(.card)
        .focused($focusedPlaceholder, equals: 0)
        .homeRowMenu(menu)
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
            .homeRowMenu(menu)
    }
}

/// Welle F-g: eine Logzeile je Collection-Reihe („Collection <titel>: <n> Kacheln, Bilder <n>, GIF <n>“), erneut nur,
/// wenn sich der Stand ändert (LazyVStack baut Reihen beim Scrollen ab und wieder auf).
@MainActor
enum CollectionRowLog {
    private static var last: [String: String] = [:]

    static func note(row: String, line: String) {
        guard last[row] != line else { return }
        last[row] = line
        RemoteLog.info("home", line)
    }
}

/// Wie NavigationLink, aber das Ziel kann verschluckt werden (`onActivate` gibt nil zurück).
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
            LazyHStack(spacing: Theme.Space.m * s) { content }
                .scrollTargetLayout()
                .padding(.vertical, Theme.Space.l * s)
        }
        // Rand 80 (§4.3): Reihentitel, Hero-Info und erste Kachel starten auf einer Linie.
        .contentMargins(.leading, Theme.Space.edge, for: .scrollContent)
        // Platz rechts, damit auch die letzten Karten aufgeklappt (640·s) an den linken Rand rücken können.
        .contentMargins(.trailing, expand ? max(Theme.Space.edge, 1920 - Theme.Space.edge - 640 * s) : Theme.Space.edge,
                        for: .scrollContent)
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
        let w = Theme.Tile.width(.poster, scale), h = Theme.Tile.height(.poster, scale)
        // Welle E-a: Plaketten nie unten auf dem Bild; bei „Unten“ sitzen sie im Streifen darunter (PosterBadgeBand).
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                TilePosterImage(item: item)
                    .frame(width: w, height: h).clipped()
                if expanded { ExpandedPoster(item: item).transition(.opacity) }
            }
            .frame(width: (expanded ? h * 16 / 9 : w), height: h, alignment: .leading).clipped()
            .overlay(alignment: .bottomLeading) {
                if item.poster == nil && !expanded { Text(item.name).font(.caption).padding(10) }
            }
            .overlay { CardStateOverlay(itemID: item.id) }
            PosterBadgeBand(width: expanded ? h * 16 / 9 : w)
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
        let size = Theme.Tile.size(.landscape, scale)
        RemoteImage(url: item.background ?? item.poster, maxPixels: 900)
            .frame(width: size.width, height: size.height).clipped()
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
            RemoteImage(url: item.background ?? item.poster)
                .frame(width: Theme.Tile.width(.hero, 1), height: Theme.Tile.height(.hero, 1)).clipped()
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(item.name).textRole(.display)
                if let d = item.description { Text(d).lineLimit(2).frame(maxWidth: 1000, alignment: .leading) }
                MetaLine(parts: [item.releaseInfo, DesignText.decimal(parsing: item.imdbRating).map { "★ \($0)" }])
            }
            .padding(Theme.Space.xl)
        }
        .frame(width: Theme.Tile.width(.hero, 1), height: Theme.Tile.height(.hero, 1))
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
    /// Fokus der umgebenden Karte (Fokus-GIF, Welle F-g).
    @Environment(\.isFocused) private var focused
    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(folder.title)
    }

    @ViewBuilder private var content: some View {
        if folder.coverImage == nil && folder.backdrop == nil && folder.logo == nil,
           let style = ReadyPackages.tileStyle(forFolderID: folder.id) {
            // Welle F-g: eigene Paket-Kachel ohne Bild aus dem Netz (Farbverlauf + SF Symbol + deutscher Titel).
            let kind: TileKind = logoStyle ? .logo : .landscape
            ZStack {
                Theme.Tile.packageGradient(style.tone)
                VStack(spacing: 14 * scale) {
                    Image(systemName: style.symbol).font(.system(size: 64 * scale, weight: .semibold))
                    Text(folder.title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(Theme.Palette.primary)
                .padding(.horizontal, 20 * scale)
            }
            .frame(width: Theme.Tile.width(kind, scale), height: Theme.Tile.height(kind, scale))
        } else if logoStyle {
            ZStack {
                Color.white.opacity(0.08)
                if let l = folder.logo { RemoteImage(url: l, maxPixels: 800, fit: true).padding(30 * scale) } else { Text(folder.title).font(.headline) }
            }
            .frame(width: Theme.Tile.width(.logo, scale), height: Theme.Tile.height(.logo, scale))
        } else {
            RemoteImage(url: folder.coverImage ?? folder.backdrop)
                .frame(width: Theme.Tile.width(.landscape, scale), height: Theme.Tile.height(.landscape, scale)).clipped()
                // Welle F-g: bewegtes Fokusbild über dem Standbild (nur auf der fokussierten Kachel).
                .overlay { if let g = folder.focusGif { FocusGIF(url: g, focused: focused) } }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    // Paket-Kacheln zeigen immer den deutschen Titel, auch mit importiertem Bild.
                    if folder.coverImage == nil || folder.showsTitleOverImage || ReadyPackages.isPackageFolder(folder.id) { Text(folder.title).font(.headline).shadow(radius: 4).padding(14) }
                }
        }
    }
}

/// Welle F-f: Platzhalter einer ladenden Reihe in Endgröße (gleiche Maße wie die Karte, Poster mit Plakettenstreifen,
/// Top 10 mit Rangziffer), damit die Reihe beim Eintreffen der Einträge nicht springt.
struct TilePlaceholder: View {
    let kind: TileKind
    var rank: Int? = nil
    @Environment(\.cardScale) private var scale

    var body: some View {
        if let rank {
            HStack(alignment: .bottom, spacing: -30 * scale) {
                Text("\(rank)").font(.system(size: 220 * scale, weight: .black)).foregroundStyle(.white.opacity(0.25))
                tile
            }
        } else {
            tile
        }
    }

    private var tile: some View {
        let size = Theme.Tile.size(kind, scale)
        return VStack(spacing: 0) {
            Theme.Tile.placeholder.frame(width: size.width, height: size.height)
            if kind == .poster { PosterBadgeBand(width: size.width) }
        }
        .accessibilityHidden(true)
    }
}

/// Welle F-f: Statuskachel einer leeren oder fehlgeschlagenen Reihe (Reihenhöhe wie die Karten, mindestens 440 breit,
/// damit der Text auch bei kleinen Postern in wenige Zeilen passt).
struct TileStatus: View {
    let kind: TileKind
    let text: String
    var symbol: String? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.cardScale) private var scale

    var body: some View {
        let size = Theme.Tile.size(kind, scale)
        // Poster: Streifen für Plaketten „Unten“ mitzählen (PosterBadgeBand), sonst springt die Reihe.
        let band = kind == .poster && model.profile.appearance.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        let height = size.height + band
        VStack(spacing: Theme.Space.s) {
            if let symbol { Image(systemName: symbol).font(.title3) }
            Text(text).textRole(.rowDetail).multilineTextAlignment(.center).lineLimit(3)
        }
        .padding(Theme.Space.m)
        .frame(width: max(size.width, Theme.Tile.width(.landscape, 1)), height: height)
        .background(Theme.Tile.placeholder)
        .accessibilityElement(children: .combine)
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
                let top = DesignText.metaLine([st.episode, st.remainingSeconds.map { "noch \(max(1, Int($0 / 60))) min" }])
                if !top.isEmpty && !hidesTopLabel {
                    ThemeBadge(kind: .status(nil, onImage: true), text: top).padding(Theme.Space.xs)
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
