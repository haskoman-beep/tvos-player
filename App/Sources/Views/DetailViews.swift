import SwiftUI
import Combine
import PlayerCore

/// Ordner einer Collection: eine Reihe pro Quelle.
struct FolderView: View {
    let folder: Folder
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(folder.title).textRole(.display).padding(.leading, Theme.Space.edge)
                    .accessibilityAddTraits(.isHeader)
                if folder.sources.isEmpty { FocusAnchor(kind: .back).padding(.leading, Theme.Space.edge) }   // N6 (Welle F-c)
                ForEach(folder.sources) { s in
                    HomeRowView(row: HomeRow(content: .list(s), style: .poster), onActivate: { $0 })
                }
            }
            .padding(.vertical, Theme.Space.edgeVertical)
        }
    }
}

struct CollectionView: View {
    @EnvironmentObject var model: AppModel
    let collectionID: String
    /// Fehlende Collection erst nach kurzer Ladezeit als fehlend werten (Fusion-Kit lädt nach; kein „Zurück“-Flackern).
    @State private var missingSettled = false
    var body: some View {
        let c = model.collection(collectionID)
        ScrollView(.vertical) {
            HomeRowView(row: HomeRow(content: .collection(id: collectionID)), onActivate: { $0 })
            // N6 (Welle F-c): leere Collection sofort, fehlende erst nach der Ladezeit.
            if c?.folders.isEmpty == true || (c == nil && missingSettled) {
                FocusAnchor(kind: .back).padding(.leading, Theme.Space.edge)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            missingSettled = true
        }
    }
}

/// Detailseite: Hintergrund, Beschreibung, Abspielen (Film) bzw. Staffeln/Folgen (Serie).
struct DetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    let item: MetaPreview
    @State private var imdb: String?
    @State private var meta: MetaDetail?
    @State private var season = 1
    @State private var loading = true
    @State private var ratings: ExternalRatings?
    /// Beste Technik-Werte über die Quellen (Qualitätszeile nach Einstellungen in `techBadges`, Welle E-a).
    @State private var best: DetailQuality?
    @State private var certification: String?
    @State private var extra: LocalizedMeta?
    @State private var trailer: TrailerPlay?
    @State private var trailerLoading = false
    @State private var trailerNote: String?
    @State private var showFullText = false
    @State private var trailerTask: Task<Void, Never>?
    /// Daten schon geladen: `.task` läuft bei jeder Rückkehr auf die Seite erneut, dann nichts neu laden/zurücksetzen.
    @State private var loaded = false
    /// Startfokus nur einmal setzen, sonst springt er bei der Rückkehr (z. B. von Folge 7 auf Folge 1).
    @State private var didInitialFocus = false
    /// Zeitpunkt des ersten Erscheinens und ob „erste Plaketten“ schon geloggt ist (Gerätemessung Addon-Antwortzeit).
    @State private var appeared: Date?
    @State private var badgesLogged = false
    /// Wave F-p: arrival times of the page's parts (one log line „Ladezeiten …“).
    @State private var timeline: DetailLoadTimeline?
    /// Welle G-a: „Sofort abspielen / Beste Wahl“ (Film): gewählte Quelle; `choiceChecked` = Quellen bekannt
    /// (dann ohne Wahl der Hinweis „Keine Quelle gefunden“). `entryFocusAt`: Zeit des Eintritts-Fokus.
    @State private var choice: BestChoice.Pick?
    @State private var choiceChecked = false
    @State private var entryFocusAt: Date?
    /// Wave F-n: measured height of the info block (meta line to description); the poster left of it takes it.
    @State private var infoHeight: CGFloat = 0
    /// Startfokus auf der Hauptaktion, nicht auf der (darüber liegenden) Beschreibung.
    enum Focus: Hashable { case play, best, episode(String), overview }
    @FocusState private var focus: Focus?
    /// Fokusziel mit Staffel (nil = Film bzw. keine Folgen) und Folgen-ID zum Hinscrollen.
    struct FocusTarget {
        var season: Int? = nil
        var focus: Focus = .play
        var video: String? = nil
    }
    /// Welle F-c (§3.2): Quellenliste/Player geöffnet; bei der Rückkehr Fokus auf „Abspielen“ bzw. die nächste
    /// ungesehene Folge (auch über die Staffelgrenze). Zähler startet die Rückkehr-Aufgabe (.task(id:)).
    @State private var openedPlayback = false
    /// Fortschritts-Stand beim Öffnen: nur wenn danach wirklich gespielt wurde (Stand geändert), springt der Fokus
    /// (Review F-c M1); sonst bleibt der System-Fokus auf der gedrückten Zeile.
    @State private var openedPlaybackStamp: Date?
    @State private var returnFocusToken = 0
    /// Rückkehr noch auszuführen; `.task(id:)` läuft bei jedem Erscheinen erneut (Review F-c I1).
    @State private var pendingReturnFocus = false
    /// Folge, zu der die Folgenliste scrollt, bevor sie den Fokus bekommt (LazyVStack legt sie sonst nicht an).
    @State private var scrollTarget: String?
    @State private var scrollRequest = 0

    /// Wave W-a: "anime" and other episodic addon types count as series (`ContentKind`); an unknown type once its
    /// meta lists episodes.
    private var isSeries: Bool { ContentKind.isEpisodic(type: item.type, hasVideos: (meta?.videos?.count ?? 0) > 1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: meta?.background ?? item.background).ignoresSafeArea().overlay(Color.black.opacity(0.55))
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        if let logo = meta?.logo {
                            RemoteImage(url: logo, maxPixels: 1400, fit: true).frame(maxWidth: 700, maxHeight: 200, alignment: .leading)
                        } else {
                            Text(item.name).textRole(.display).accessibilityAddTraits(.isHeader)
                        }
                        // Wave F-n: the title's poster left of the info block, exactly as tall as it (PlayerCore `DetailPage`).
                        HStack(alignment: .top, spacing: CGFloat(DetailPage.posterGap)) {
                            if let size = DetailPage.posterSize(blockHeight: Double(infoHeight), bottomInset: overview.isEmpty ? 0 : Double(FocusHighlightMetrics.verticalPadding)) {
                                DetailPoster(item: posterItem)
                                    .frame(width: CGFloat(size.width), height: CGFloat(size.height))
                                    .transition(.opacity)
                                    .onAppear { markLoad(.poster) }
                            }
                            infoBlock
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                                    guard DetailPage.shouldUpdate(measured: Double(h), stored: Double(infoHeight)) else { return }
                                    // Review M2: animated, so the poster fades in and resizes smoothly.
                                    withAnimation(.easeOut(duration: 0.2)) { infoHeight = h }
                                }
                        }

                        if loading {
                            // N6: ohne Beschreibung sonst nichts fokussierbar (unsichtbares Ziel, danach Abspielen).
                            ProgressView().quietFocusTarget(overview.isEmpty)
                        } else if let imdb {
                            if isSeries {
                                if let k = extra?.trailerYouTube { trailerButton(k).buttonStyle(ThemeActionButtonStyle()) }
                                episodes(imdb)
                            } else {
                                let resume = model.progress.resumePosition(for: imdb)
                                HStack(spacing: Theme.Space.l) {
                                    bestChoiceCard(imdb, resume: resume)
                                    Button(resume.map { "▶ Fortsetzen ab \(timeText($0))" } ?? "▶ Abspielen") {
                                        markOpenedPlayback()
                                        navigate(.streams(model.moviePlayRequest(item, imdb: imdb, meta: meta, resumeLastSource: resume != nil)))
                                    }
                                    .focused($focus, equals: .play)
                                    if let k = extra?.trailerYouTube { trailerButton(k) }
                                }
                                // Welle F-i: Token-Farben statt Systemknopf (der zog wieder Blau ins Label).
                                .buttonStyle(ThemeActionButtonStyle())
                            }
                            if let trailerNote { Text(trailerNote).textRole(.rowDetail) }
                            if let x = extra { DetailExtras(info: x, isSeries: isSeries) }
                        } else {
                            Text("Keine IMDb-ID gefunden – Streams nicht abrufbar.").textRole(.rowDetail)
                            if overview.isEmpty { FocusAnchor(kind: .back) }   // N6
                        }
                    }
                    .padding(.horizontal, Theme.Space.edge)
                    .padding(.vertical, Theme.Space.edgeVertical)
                }
                .onChange(of: scrollRequest) {
                    guard let id = scrollTarget else { return }
                    proxy.scrollTo(id)
                }
            }
            .defaultFocus($focus, movieMainFocus)
            // Die App-Akzentfarbe (RootView .tint) färbte Knöpfe und Text-Knöpfe hier flächig: normale tvOS-Knöpfe.
            .tint(Color?.none)
        }
        .onAppear {
            if loaded, openedPlayback {
                openedPlayback = false
                if playbackStamp != openedPlaybackStamp {
                    pendingReturnFocus = true
                    returnFocusToken += 1
                } else {
                    RemoteLog.info("fokus", "Detail: zurück ohne Wiedergabe, Fokus bleibt")
                }
            }
            if appeared == nil { appeared = Date() }
            // Welle G-a: nach dem Player neu wählen (8-h-Gedächtnis, letzte Quelle können sich geändert haben).
            if loaded, let id = imdb { updateChoice(id) }
            // Quellen schon im Cache (z. B. zweiter Besuch): Technik-Plaketten im ersten Bild, nicht erst nach dem Laden.
            let id = imdb ?? (item.id.hasPrefix("tt") ? item.id : nil)
            if best == nil, !isSeries, let id, let b = detailQuality(id) {
                best = b
                logFirstBadges("Technik aus Cache")
                markLoad(.tech, source: cacheSource(id))
                updateChoice(id)
            }
        }
        .task {
            guard !loaded else { return }
            let opened = appeared ?? Date()
            imdb = await model.imdbID(for: item)
            if let imdb {
                markLoad(.id)
                if !isSeries, best == nil, let b = detailQuality(imdb) {
                    best = b
                    logFirstBadges("Technik aus Cache")
                    markLoad(.tech, source: cacheSource(imdb))
                    updateChoice(imdb)
                } else if !isSeries, best != nil {
                    markLoad(.tech, source: cacheSource(imdb))
                } else if !isSeries, best == nil {
                    // Quellen sofort und parallel holen (Technik-Plaketten; AppModel cached sie für die Quellenliste).
                    let id = imdb
                    Task {
                        let list = await model.streams(type: "movie", id: id)
                        best = detailQuality(id)
                        updateChoice(id, list: list)
                        if !techBadges.isEmpty { logFirstBadges("Technik") }
                        markLoad(.tech, source: "neu, \(list.count) Quellen")
                        RemoteLog.info("detail", "Plaketten nach \(Int(Date().timeIntervalSince(opened) * 1000)) ms (\(list.count) Quellen)")
                    }
                }
                async let r = model.ratings(imdb: imdb, series: isSeries)
                if ContentKind.typeDecides(item.type) {
                    // Wave F-p: TMDB (age rating, cast, similar titles) no longer waits for the meta: the meta waits
                    // for its addon (up to seconds), TMDB mostly answers in a few hundred ms (build 214 log: FSK
                    // 1834 ms after entry, TMDB itself had answered after about 400 ms).
                    let series = isSeries
                    let local = Task { () -> LocalizedMeta? in
                        let l = await model.localized(imdb: imdb, series: series)
                        applyLocalized(l)
                        return l
                    }
                    meta = await model.meta(type: isSeries ? "series" : "movie", imdb: imdb)
                    markLoad(.meta)
                    _ = await local.value
                } else {
                    // Unknown addon type: the meta's episode list decides movie or series first.
                    meta = await model.meta(type: isSeries ? "series" : "movie", imdb: imdb)
                    markLoad(.meta)
                    applyLocalized(await model.localized(imdb: imdb, series: isSeries))
                }
                ratings = await r
                if certification != nil || ratings?.certification != nil
                    || !model.ratingBadges(imdbRating: meta?.imdbRating, mdblist: ratings).isEmpty {
                    logFirstBadges("Bewertungen")
                }
            }
            if Task.isCancelled { return }   // Seite verlassen: beim nächsten Erscheinen vollständig neu laden
            // Serie: Staffel der nächsten ungesehenen Folge (§3.2 „Weiter: S2 F5“), sonst der zuletzt gesehenen.
            season = playbackFocusTarget().season ?? imdb.flatMap { model.progress.latest(forItem: $0)?.season } ?? seasons.first ?? 1
            loading = false
            loaded = true
            // Während des Ladens war die Beschreibung das einzige fokussierbare Element: Fokus auf die Hauptaktion holen.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if !didInitialFocus {
                didInitialFocus = true
                entryFocusAt = Date()
                if focus == nil || focus == .overview { await applyFocus(playbackFocusTarget(), reason: "Eintritt") }
                // R1 (M6): Karte kam während des Fokus-Setzens (Ziel war noch „Abspielen“).
                if choice != nil, DetailPage.lateCardTakesFocus(setting: model.profile.player.instantPlay, isSeries: isSeries,
                                                                focusOnPlay: focus == .play,
                                                                sinceEntry: entryFocusAt.map { Date().timeIntervalSince($0) }) {
                    focus = .best
                    RemoteLog.info("fokus", "Detail Eintritt: Sofort abspielen (Karte während des Fokus-Setzens)")
                }
            }
            await translateSeason()
        }
        // Wave F-p: a part that never arrives (no TMDB key, no sources): the line comes after 10 s with „–“.
        .task {
            try? await Task.sleep(for: .milliseconds(DetailLoadTimeline.giveUpMilliseconds))
            guard !Task.isCancelled, timeline?.logged != true else { return }
            if timeline == nil { timeline = DetailLoadTimeline(title: item.name, expectsTech: !isSeries) }
            if let line = timeline?.takeLine(force: true) { RemoteLog.info("detail", line) }
        }
        .task(id: returnFocusToken) {
            guard pendingReturnFocus else { return }
            // Erst nach dem Zurück-Übergang: sonst setzt die Rückkehr-Animation den Fokus wieder auf den alten Knopf.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            // Erst hier verbrauchen (Re-Review N1): eine abgebrochene Aufgabe (alte id beim Erscheinen) lässt das
            // Flag für die neu gestartete stehen.
            pendingReturnFocus = false
            let target = playbackFocusTarget()
            if let s = target.season, s != season { season = s }
            await applyFocus(target, reason: "nach dem Player")
        }
        .onChange(of: season) { Task { await translateSeason() } }
        // Welle G-a (§3.2): Karte kommt kurz nach dem Eintritt (Quellen liefen noch): Fokus wandert mit, solange er
        // noch auf „Abspielen“ steht und der Eintritt höchstens 2 s her ist.
        .onChange(of: choice != nil) { _, has in
            guard has, DetailPage.lateCardTakesFocus(setting: model.profile.player.instantPlay, isSeries: isSeries,
                                                     focusOnPlay: focus == .play,
                                                     sinceEntry: entryFocusAt.map { Date().timeIntervalSince($0) }) else { return }
            focus = .best
            RemoteLog.info("fokus", "Detail Eintritt: Sofort abspielen (Karte nachgeladen)")
        }
        // Wave F-n: setting changed while the page is open: build or drop the card.
        .onChange(of: model.profile.player.instantPlay) { if let id = imdb { updateChoice(id) } }
        .onDisappear {
            trailerTask?.cancel()
            // Wave F-p R1: page left before all parts arrived: log what came so far (missing parts „–“), so a later
            // give-up timer on return does not count time spent elsewhere.
            if timeline == nil, appeared != nil { timeline = DetailLoadTimeline(title: item.name, expectsTech: !isSeries) }
            if let line = timeline?.takeLine(force: true) { RemoteLog.info("detail", line) }
        }
        .sheet(isPresented: $showFullText) { FullTextSheet(title: item.name, text: overview) }
        .fullScreenCover(item: $trailer) { t in
            PlayerScreen(url: t.stream.url,
                         request: PlayRequest(type: item.type, id: "trailer:\(t.key)", title: "Trailer · \(item.name)", item: item),
                         headers: t.stream.headers,
                         onEnded: { _ in trailer = nil },
                         onFallback: { reason in
                             trailer = nil
                             RemoteLog.info("trailer", "\(t.key) Wiedergabe fehlgeschlagen (\(t.stream.client)): \(reason)")
                             // Trailerio-Datei nicht abspielbar → bestehender YouTube-Weg.
                             if t.stream.client == "trailerio", YouTubeResolver.isVideoID(t.key) {
                                 trailerTask = Task { await playTrailer(t.key, useTrailerio: false) }
                             } else {
                                 trailerNote = "Trailer nicht verfügbar"
                             }
                         },
                         isTrailer: true, remoteHLS: t.stream.isHLS)
                .environmentObject(model)
        }
    }

    /// Letzte Änderung am Fortschritt dieses Titels (nil = noch nie gespielt).
    private var playbackStamp: Date? { imdb.flatMap { model.progress.latest(forItem: $0)?.updated } }

    private func markOpenedPlayback() {
        openedPlayback = true
        openedPlaybackStamp = playbackStamp
    }

    /// Fokusziel (§3.2): Film „Abspielen“; Serie die nächste ungesehene Folge nach der zuletzt gespielten
    /// (PlayerCore `EpisodeFocus`), auch in der nächsten Staffel. Die erste Folge einer Staffel trägt `.play`.
    private func playbackFocusTarget() -> FocusTarget {
        guard isSeries, let imdb else { return FocusTarget(focus: movieMainFocus) }
        let videos = meta?.videos ?? []
        let anchor = model.progress.latest(forItem: imdb).flatMap { p in
            p.season.flatMap { s in p.episode.map { EpisodeRef(season: s, episode: $0) } }
        }
        guard let t = EpisodeFocus.target(episodes: EpisodeRef.list(from: videos), anchor: anchor,
                                          isWatched: { model.progress.isWatched("\(imdb):\($0.season):\($0.episode)") })
        else { return FocusTarget() }
        let eps = videos.filter { $0.season == t.season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
        guard let v = eps.first(where: { $0.episode == t.episode }) else { return FocusTarget(season: t.season) }
        return FocusTarget(season: t.season, focus: v.id == eps.first?.id ? .play : .episode(v.id), video: v.id)
    }

    /// Fokus setzen; die Folge liegt evtl. außerhalb des angelegten Bereichs: erst hinscrollen, dann bis zu
    /// viermal nachfassen, bis der Fokus sitzt (Log „fokus“ für den Gerätetest).
    private func applyFocus(_ target: FocusTarget, reason: String) async {
        for attempt in 1...4 {
            if let id = target.video {
                scrollTarget = id
                scrollRequest += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            focus = target.focus
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if focus == target.focus {
                RemoteLog.info("fokus", "Detail \(reason): \(Self.focusName(target)) (Versuch \(attempt))")
                return
            }
        }
        RemoteLog.info("fokus", "Detail \(reason): \(Self.focusName(target)) nicht gesetzt (jetzt \(focus.map { "\($0)" } ?? "nichts"))")
    }

    private static func focusName(_ t: FocusTarget) -> String {
        guard let s = t.season else { return t.focus == .best ? "Sofort abspielen" : "Abspielen" }
        return "Staffel \(s), \(t.video ?? "erste Folge")"
    }

    /// Wave F-p: TMDB answer in the page (also when the meta is still loading).
    private func applyLocalized(_ l: LocalizedMeta?) {
        extra = l
        certification = l?.certification
        if certification != nil { logFirstBadges("Altersfreigabe") }
        markLoad(.tmdb)
    }

    /// Wave F-p: one arrival time of the page; logs „Ladezeiten …“ once all parts arrived.
    private func markLoad(_ part: DetailLoadTimeline.Part, source: String? = nil) {
        guard let at = appeared else { return }
        if timeline == nil { timeline = DetailLoadTimeline(title: item.name, expectsTech: !isSeries) }
        timeline?.mark(part, ms: Int(Date().timeIntervalSince(at) * 1000), source: source)
        if let line = timeline?.takeLine() { RemoteLog.info("detail", line) }
    }

    /// Wave F-p: tech badges from the source cache: filled by the focus prefetch or by an earlier visit.
    private func cacheSource(_ id: String) -> String {
        StreamPrefetcher.shared.wasPrefetched(id) ? "Cache, vorgeladen" : "Cache"
    }

    /// Einmal je Seite: Zeit vom Erscheinen bis zur ersten sichtbaren Plakette und deren Quelle.
    private func logFirstBadges(_ source: String) {
        guard !badgesLogged else { return }
        badgesLogged = true
        let ms = appeared.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        RemoteLog.info("detail", "erste Plaketten nach \(ms) ms (\(source))")
    }

    /// Wave F-p: the TMDB text fills in while the meta loads (catalogue entries without a description), so the
    /// block reaches its height and the poster shows early.
    private var overview: String { meta?.description ?? item.description ?? extra?.overview ?? "" }

    /// Meta line, badges, tagline and description (wave F-n: measured for the poster to its left).
    @ViewBuilder private var infoBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            // Welle E-a: FSK steht in der Textzeile („2018 · 97 min · FSK 0 · Genre“), nicht als Plakette.
            MetaLine(parts: [meta?.releaseInfo ?? item.releaseInfo, meta?.runtime, certification ?? ratings?.certification,
                             meta?.genres?.prefix(3).joined(separator: ", ")])
            InfoBadges(ratings: model.ratingBadges(imdbRating: meta?.imdbRating, mdblist: ratings), tech: techBadges)
            // Review M3: same width cap as the description, so the poster does not change its line breaks.
            if let t = extra?.tagline { Text(t).italic().textRole(.rowDetail).frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading) }
            if !overview.isEmpty {
                // Kurz halten; Klick zeigt den ganzen Text.
                Button { showFullText = true } label: { FocusHighlight { Text(overview).font(.callout).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading) } }
                    .buttonStyle(.plain)
                    .focused($focus, equals: .overview)
                    .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            }
        }
    }

    /// Wave F-n: the page's item with the meta poster as fallback when the catalogue entry has none (the tile
    /// choice addon poster, then this poster, runs in `TilePosterImage`).
    private var posterItem: MetaPreview {
        var p = item
        if p.poster?.trimmingCharacters(in: .whitespaces).isEmpty ?? true { p.poster = meta?.poster }
        return p
    }

    /// Wave F-n: „Sofort abspielen“ card shown (setting, movies only).
    private var instantPlayOn: Bool {
        DetailPage.showsInstantPlay(setting: model.profile.player.instantPlay, isSeries: isSeries)
    }

    /// Wave F-n: entry and return focus of a movie page (card only with the setting and a pick).
    private var movieMainFocus: Focus {
        DetailPage.mainAction(setting: model.profile.player.instantPlay, isSeries: isSeries, hasPick: choice != nil) == .instantPlay ? .best : .play
    }

    /// Welle E-a: eine Zeile, höchstens 5 (Auflösung, DV/HDR, Atmos, Ton + Kanäle, Remux).
    private var techBadges: [QualityBadge] {
        best.map { QualityBadges.detailRow($0, settings: model.profile.appearance.badges) } ?? []
    }

    /// Technik-Werte aus dem Quellen-Cache (keine Abfrage); nil ohne gecachte Quellen.
    private func detailQuality(_ id: String) -> DetailQuality? {
        model.cachedStreams(id: id).flatMap { DetailQuality.from($0.map(\.stream)) }
    }

    /// Welle G-a: Beste Wahl neu bilden (Film). `list` = eben geholte Quellen; sonst aus dem Quellen-Cache
    /// (ohne Cache bleibt der Stand, bis die Quellen da sind).
    /// Wave F-n: only with the setting „Sofort abspielen anzeigen“ (default off); off drops any earlier pick.
    private func updateChoice(_ id: String, list: [(addon: String, stream: StreamItem)]? = nil) {
        guard instantPlayOn else {
            choice = nil
            choiceChecked = false
            return
        }
        guard let all = list ?? model.cachedStreams(id: id) else { return }
        let pick = model.bestChoice(all, title: id)
        if pick?.stream.id != choice?.stream.id || !choiceChecked {
            RemoteLog.info("play", pick.map { "Beste Wahl bereit: \($0.reason.rawValue) · \(BestChoice.detail($0.stream, primaryLanguage: model.sourceRankContext.primaryLanguage)) · \($0.addon)" }
                ?? "Beste Wahl: keine abspielbare Quelle (\(all.count) Quellen)")
        }
        choice = pick
        choiceChecked = true
    }

    /// Welle G-a: Karte „Sofort abspielen“ (bzw. „Weiter mit letzter Quelle“) mit dem, was spielen wird; ein Druck
    /// startet die Quelle über die Quellenliste (Fehlerleiter dort unverändert), ohne Auswahl.
    /// Ohne abspielbare Quelle: „Keine Quelle gefunden – Quellen ansehen“ öffnet die Liste.
    @ViewBuilder
    private func bestChoiceCard(_ imdb: String, resume: Double?) -> some View {
        if !instantPlayOn {
            EmptyView()
        } else if let c = choice {
            let detail = BestChoice.detail(c.stream, primaryLanguage: model.sourceRankContext.primaryLanguage)
            Button {
                markOpenedPlayback()
                var r = model.moviePlayRequest(item, imdb: imdb, meta: meta, resumeLastSource: false)
                r.bestChoice = LastSource(stream: c.stream, addon: c.addon, contentID: imdb)
                RemoteLog.info("play", "Beste Wahl: \(c.reason.rawValue) · \(detail) · \(c.addon) · \(c.stream.name ?? "")")
                navigate(.streams(r))
            } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("▶ " + BestChoice.title(c.reason, resumeText: resume.map(timeText))).textRoleInRow(.rowTitleEmphasis)
                    Text(detail).textRoleInRow(.rowDetail).lineLimit(1)
                }
                .frame(maxWidth: 620, alignment: .leading)
            }
            .focused($focus, equals: .best)
        } else if choiceChecked {
            Button(BestChoice.noSourceText) {
                markOpenedPlayback()
                RemoteLog.info("play", "Beste Wahl: keine Quelle → Quellenliste")
                navigate(.streams(model.moviePlayRequest(item, imdb: imdb, meta: meta, resumeLastSource: false)))
            }
        }
    }

    private func trailerButton(_ key: String) -> some View {
        Button(trailerLoading ? "Trailer wird geladen …" : "🎬 Trailer") {
            // Doppeldruck: laufende Auflösung behalten, sonst ginge der Abbruch-Griff verloren.
            guard !trailerLoading else { return }
            trailerTask = Task { await playTrailer(key) }
        }
    }

    /// Trailer im eigenen Player: zuerst trailerio.cc (direkte Datei in Profilsprache), sonst YouTube-Adresse über Innertube;
    /// kein Wechsel in die YouTube-App.
    private func playTrailer(_ key: String, useTrailerio: Bool = true) async {
        guard !trailerLoading else { return }
        trailerLoading = true
        trailerNote = nil
        if useTrailerio, let imdb {
            let lang = model.profile.language.rawValue
            let list = await TrailerioClient().trailers(imdb: imdb, series: isSeries, language: lang, log: { line in
                Task { @MainActor in RemoteLog.info("trailer", "trailerio \(imdb) (\(lang)): \(line)") }
            })
            if Task.isCancelled { trailerLoading = false; RemoteLog.info("trailer", "\(imdb): abgebrochen"); return }
            // Profilsprache zuerst: erkennbar fremdsprachige Trailerio-Treffer hinter dem YouTube-Trailer in Profilsprache.
            if let pick = TrailerioClient.choose(list, profileLanguage: lang, youtubeKey: extra?.trailerYouTube,
                                                 youtubeLanguage: extra?.trailerYouTubeLanguage) {
                trailerLoading = false
                RemoteLog.info("trailer", "\(imdb) → trailerio · \(pick.provider) · \(pick.languageHint ?? "?") · \(pick.isHLS ? "HLS" : "MP4")")
                trailer = TrailerPlay(key: key, stream: pick.stream)
                return
            } else if !list.isEmpty {
                RemoteLog.info("trailer", "\(imdb): trailerio ohne Treffer in \(lang) → YouTube (\(extra?.trailerYouTubeLanguage ?? "?"))")
            }
        }
        RemoteLog.info("trailer", "\(key) wird aufgelöst")
        let s = await YouTubeResolver().resolve(videoID: key, log: { line in
            Task { @MainActor in RemoteLog.info("trailer", line) }
        })
        trailerLoading = false
        if Task.isCancelled { RemoteLog.info("trailer", "\(key): abgebrochen"); return }
        guard let s else {
            trailerNote = "Trailer nicht verfügbar"
            RemoteLog.info("trailer", "\(key): keine abspielbare Adresse")
            return
        }
        RemoteLog.info("trailer", "\(key) → \(s.client) · \(s.isHLS ? "HLS" : "MP4 \(s.height ?? 0)p")")
        trailer = TrailerPlay(key: key, stream: s)
    }

    private func translateSeason() async {
        guard isSeries, let imdb, meta != nil else { return }
        let s = season
        let eps = await model.localizedSeason(imdb: imdb, season: s)
        if !eps.isEmpty { meta = meta?.applying(season: s, episodes: eps) }
    }

    /// Eintrag mit IMDb-ID, damit Weiterschauen direkt Cinemeta/Streams nutzen kann.
    private func progressItem(_ imdb: String) -> MetaPreview { model.progressItem(item, imdb: imdb, meta: meta) }

    private var seasons: [Int] {
        Array(Set((meta?.videos ?? []).compactMap(\.season).filter { $0 > 0 })).sorted()
    }

    @ViewBuilder private func episodes(_ imdb: String) -> some View {
        if seasons.isEmpty {
            Text("Keine Folgen gefunden.").textRole(.rowDetail)
            if overview.isEmpty && extra?.trailerYouTube == nil { FocusAnchor(kind: .back) }   // N6
        } else {
            // Fokus-Anheben (tileScale) plus Schatten (Radius + Versatz ≈ 25 pt) passt in Space.l; nichts wird abgeschnitten.
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Space.m) {
                    ForEach(seasons, id: \.self) { s in
                        Button { season = s } label: {
                            HStack(spacing: Theme.Space.xs) {
                                // Gewählte Staffel: Haken, erbt die Vordergrundfarbe und bleibt so auch im Fokus sichtbar.
                                if s == season { Image(systemName: "checkmark") }
                                Text("Staffel \(s)")
                            }
                        }
                        .buttonStyle(ThemeActionButtonStyle(selected: s == season))
                        .accessibilityAddTraits(s == season ? .isSelected : [])
                    }
                }
                .padding(.vertical, Theme.Space.l)
            }
            .scrollClipDisabled()
            let eps = (meta?.videos ?? []).filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
            LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(eps) { v in
                    let isFirst = v.id == eps.first?.id
                    Button {
                        let e = v.episode ?? 0
                        markOpenedPlayback()
                        navigate(.streams(PlayRequest(type: "series", id: "\(imdb):\(season):\(e)", title: "\(item.name) S\(season)E\(e)",
                                                      item: progressItem(imdb), season: season, episode: e,
                                                      episodes: EpisodeRef.list(from: meta?.videos ?? []))))
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            let spoiler = model.profile.sources.blurUnwatchedStills && !model.progress.isWatched("\(imdb):\(season):\(v.episode ?? 0)")
                            RemoteImage(url: v.thumbnail, maxPixels: 560, blur: spoiler ? SpoilerStill.blurRadius : 0)
                                .frame(width: 280, height: 158).clipped()
                                .spoilerMark(spoiler)
                            // Welle F-i: Farben aus den Tokens (`textRoleInRow`, Zeilenstil), kein Systemknopf mit Akzentfarbe.
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                HStack {
                                    Text("\(v.episode ?? 0). \(v.name ?? v.title ?? "Folge")").textRoleInRow(.rowTitleEmphasis)
                                    let key = "\(imdb):\(season):\(v.episode ?? 0)"
                                    if model.progress.isWatched(key) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Tone.ok.color) }
                                    else if let p = model.progress.entries[key], p.position >= 60 {
                                        ProgressView(value: p.fraction).frame(width: 120)
                                    }
                                }
                                if let o = v.overview { Text(o).textRoleInRow(.rowDetail).lineLimit(2).multilineTextAlignment(.leading) }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                    .focused($focus, equals: isFirst ? .play : .episode(v.id))
                    .id(v.id)
                }
            }
        }
    }
}

/// Aufgelöster Trailer für den Player.
struct TrailerPlay: Identifiable {
    let id = UUID()
    let key: String
    let stream: YouTubeStream
}

/// Wave F-n: the title's poster on the detail page, left of the info block. Same picture choice as the poster tiles
/// (`TilePosterImage`: metadata addon poster when that setting is on, then the catalogue/TMDB poster, a failed address
/// is skipped; without any picture the title shows on the placeholder). Not focusable.
struct DetailPoster: View {
    let item: MetaPreview

    var body: some View {
        TilePosterImage(item: item)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

/// Wave F-n: padding of `FocusHighlight` (the detail poster ends with the description text, not its highlight).
enum FocusHighlightMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
}

/// Dezente Fokusanzeige für Text-Knöpfe (`.buttonStyle(.plain)`).
struct FocusHighlight<C: View>: View {
    @Environment(\.isFocused) private var focused
    @ViewBuilder let content: C
    var body: some View {
        content
            .padding(.horizontal, FocusHighlightMetrics.horizontalPadding).padding(.vertical, FocusHighlightMetrics.verticalPadding)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(focused ? 0.14 : 0)))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Blatt mit dem ganzen Text (Beschreibung, Biografie).
struct FullTextSheet: View {
    let title: String
    let text: String
    var body: some View {
        // tvOS scrollt nur von Fokus zu Fokus: Text in Absätze/Stücke teilen, jedes Stück fokussierbar.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(title).textRole(.pageTitle).accessibilityAddTraits(.isHeader)
                ForEach(Array(TextChunks.split(text).enumerated()), id: \.offset) { _, chunk in
                    Text(chunk).font(.body).focusable()
                }
            }
            .frame(maxWidth: 1300, alignment: .leading)
            .padding(60)
        }
    }
}

/// Quellenliste aller Addons (Reihenfolge von AIOStreams), mit Plaketten.
struct StreamListView: View {
    @EnvironmentObject var model: AppModel
    let request: PlayRequest
    /// Bei Autoplay die gerade laufende Folge.
    @State private var current: PlayRequest?
    @State private var nextNote: String?
    @State private var streams: [(addon: String, stream: StreamItem)] = []
    @State private var loading = true
    @State private var playing: StreamItem?
    /// Quellen, die in dieser Liste schon versagt haben, und Zahl der automatischen Wechsel.
    @State private var failed: Set<String> = []
    /// Welle G-a R1 (I1): Autostart (Weiterschauen bzw. Beste Wahl) nur einmal je Liste; `.task` läuft nach dem
    /// Vollbild-Player erneut, danach entscheidet allein die Rückfallleiter bzw. die Auswahl.
    @State private var autostartDone = false
    @State private var fallbacks = 0
    /// „Noch da?“-Zähler, Addon je Quelle, offene Abfrage (StillWatchingPrompt.swift).
    @State private var autoNext = AutoNextState()
    /// Welle D-b (M3): veralteter, lückenhafter Stand gezeigt, die Erneuerung läuft und wird übernommen.
    @State private var refreshingPartial = false
    /// Welle F-c (§3.2): fokussierte Quelle; Eintritt auf die zuletzt gespielte, nach einem Fehler die nächste darunter.
    @FocusState private var focusedStream: String?
    @State private var focusRequest: SourceFocusRequest?
    @State private var entryFocusDone = false
    /// Zuletzt gescheiterte Quelle (von `fallback` gesetzt, beim Schließen des Players verbraucht).
    @State private var lastFailure: String?
    /// Automatischer Wechsel geplant: dann kein Fokuswunsch nach dem Fehler (Review F-c M2; das nächste Vollbild
    /// öffnet gleich, beim Schließen gilt die Regel für die zuletzt gespielte Quelle).
    @State private var autoSwitchScheduled = false
    /// Wave F-m: player that just closed; its focus move waits for the end of the cover dismissal (`playerDismissed`).
    @State private var closedPlayer: StreamItem?
    /// Wave Q: chosen filter chips (view only, per list visit) and the parsed traits per source id.
    @State private var filter: Set<SourceFilterChip> = []
    /// Parsed traits, keyed by `traitKey` (id plus the hints the id leaves out, review Q M3).
    @State private var traitsByID: [String: StreamTraits] = [:]
    /// Review Q I3/N1: the user chose on the chip bar (pressed a chip or moved between chips): the entry focus
    /// leaves them there. Focus that tvOS puts on "Alle" by itself (loading line gone) does not count.
    @State private var filterTouched = false

    private static func traitKey(_ s: StreamItem) -> String {
        "\(s.id)|\(s.behaviorHints?.cached.map(String.init) ?? "-")|\(s.behaviorHints?.videoSize ?? -1)|\(s.behaviorHints?.filename ?? "")"
    }
    private func traits(_ s: StreamItem) -> StreamTraits { traitsByID[Self.traitKey(s)] ?? StreamTraits.parse(s) }
    private var filterOptions: [SourceFilterOption] {
        streams.count < 2 ? [] : SourceFilter.options(streams.map { traits($0.stream) }, selected: filter)
    }
    /// Rows on screen: the full list narrowed by the chips the list still offers.
    private func visibleStreams(_ options: [SourceFilterOption]) -> [(addon: String, stream: StreamItem)] {
        let active = SourceFilter.effective(filter, options: options)
        return active.isEmpty ? streams : streams.filter { SourceFilter.passes(traits($0.stream), active) }
    }
    private var visibleIDs: [String] { visibleStreams(filterOptions).map(\.stream.id) }
    /// Wave P-b: source chosen in the player's side panel and the held position it starts at (cleared on close).
    @State private var sideStart: (id: String, at: Double)?

    var body: some View {
        // Welle E-b: Addon-Name nur, wenn die Liste mehrere Addons mischt (sonst steht er schon im Text des Addons).
        let showAddon = Set(streams.map(\.addon)).count > 1
        let options = filterOptions
        let shown = visibleStreams(options)
        let shownIDs = shown.map(\.stream.id)
        // Titel als Listenkopf (scrollt mit weg) statt navigationTitle: der große tvOS-Titel lag über den Zeilen.
        ScrollViewReader { proxy in
            List {
                Section {
                    if let nextNote { Text(nextNote).foregroundStyle(.secondary) }
                    // N6: solange keine Zeile da ist, ist die Ladezeile das (unsichtbare) Fokusziel.
                    if loading { ProgressView("Quellen werden geladen …").quietFocusTarget(streams.isEmpty) }
                    if refreshingPartial { ProgressView("Fehlende Quellen werden nachgeladen …") }
                    AddonSearchStatusLine(id: (current ?? request).id)
                    if !loading && streams.isEmpty {
                        Text(model.profile.addons.isEmpty ? "Kein Addon installiert (Einstellungen → Addons)." : "Keine abspielbaren Quellen.")
                        FocusAnchor(kind: .back)   // N6: sonst nichts fokussierbar, Menu schlösse die App
                    }
                    if !options.isEmpty {
                        SourceFilterBar(options: options, selected: SourceFilter.effective(filter, options: options),
                                        total: streams.count, onAll: { setFilter([]) },
                                        onToggle: { setFilter(SourceFilter.toggle($0, in: SourceFilter.effective(filter, options: options))) },
                                        onUserMove: { filterTouched = true })
                            .listRowBackground(Color.clear)
                        if shown.isEmpty {
                            Text("Keine Quelle passt zum Filter.").foregroundStyle(.secondary)
                            Button("Filter aufheben") { clearFilterToList() }
                                .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                                .listRowBackground(Color.clear)
                        }
                    }
                    ForEach(shown, id: \.stream.id) { entry in
                        Button {
                            fallbacks = 0; AutoNextState.userInput($autoNext); autoNext.ask = nil
                            PlaybackStability.shared.timing.markTap()
                            playing = entry.stream
                        } label: {
                            StreamRow(addon: showAddon ? entry.addon : nil, stream: entry.stream).opacity(failed.contains(entry.stream.id) ? 0.4 : 1)
                                .recentlyFailedMark(entry.stream, title: (current ?? request).id)
                        }
                        // Welle F-d: Zeilenform aus den Tokens (bg.row, radius.row, weiße Fokusfläche) über die volle Breite.
                        // Welle F-i: hohe Zeilen (ganzer Formatter-Text) wachsen beim Fokus höchstens um `Focus.rowMaxGrowth`
                        // je Seite, damit sie die Nachbarzeile nicht überdecken.
                        .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity, maxFocusGrowth: Theme.Focus.rowMaxGrowth))
                        .listRowBackground(Color.clear)
                        .focused($focusedStream, equals: entry.stream.id)
                        .id(entry.stream.id)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(current?.title ?? request.title).textRole(.pageTitle).lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        // X3: „161 Quellen · 8,4 s“, sobald die Suche fertig ist.
                        if !loading && !streams.isEmpty {
                            StreamListSummaryLine(id: (current ?? request).id, count: streams.count)
                        }
                    }
                    .textCase(nil).padding(.bottom, Theme.Space.s)
                }
            }
            .task(id: focusRequest) {
                guard let r = focusRequest else { return }
                // Verbrauchen (Review F-c M4): beim nächsten Erscheinen nicht erneut setzen; neuere Anfrage bleibt.
                defer { if focusRequest?.token == r.token { focusRequest = nil } }
                // Nach dem Player: erst nach dem Schließen des Vollbilds (sonst setzt tvOS den Fokus auf die gedrückte Zeile).
                try? await Task.sleep(for: .milliseconds(r.delayMs))
                for attempt in 1...4 {
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(r.id)
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    // Review Q N2: a keep move gives way to a key press (focus now on a third row).
                    if r.keep, let f = focusedStream, f != r.id, f != r.from {
                        RemoteLog.info("fokus", "Quellenliste \(r.reason): Zeile \(r.index + 1) abgebrochen (Taste)")
                        return
                    }
                    focusedStream = r.id
                    try? await Task.sleep(for: .milliseconds(150))
                    if focusedStream == r.id {
                        RemoteLog.info("fokus", "Quellenliste \(r.reason): Zeile \(r.index + 1) (Versuch \(attempt))")
                        return
                    }
                }
                RemoteLog.info("fokus", "Quellenliste \(r.reason): Zeile \(r.index + 1) nicht gesetzt")
            }
        }
        .listStyle(.grouped)
        // Gerätefoto Build 28: farbiger Schimmer hinter der Liste (App-Akzent als Tönung der Zeilen/Glasflächen,
        // durchscheinender Hintergrund). Neutral: keine Akzent-Tönung, eigener dunkler, deckender Hintergrund.
        .tint(Color?.none)
        .settingsSurface()
        .streamSearchPartials(id: request.id, loading: loading && current == nil) { streams = model.orderedStreams($0) }
        .task {
            // Start of the push transition (the list appears as the push begins); see `autostartAfterPush`.
            let appeared = ProcessInfo.processInfo.systemUptime
            let autostart = (request.resumeLastSource || request.bestChoice != nil) && playing == nil && !autostartDone
            streams = model.orderedStreams(autostart
                ? await model.streamsForAutoplay(type: request.type, id: request.id)
                : await model.streams(type: request.type, id: request.id))
            loading = false
            if request.type == "series", request.episodes.isEmpty, let base = request.id.split(separator: ":").first {
                // Aus Weiterschauen: Folgenliste nachladen, damit die nächste Folge automatisch kommt.
                let eps = EpisodeRef.list(from: await model.meta(type: "series", imdb: String(base))?.videos ?? [])
                if current == nil { var r = request; r.episodes = eps; current = r }
            }
            // Welle G-a R1: in dieser Liste schon gescheiterte Quellen nie automatisch (die Rückfallleiter entscheidet).
            let untried = streams.filter { !failed.contains($0.stream.id) }
            let autostartNow = autostart && !Task.isCancelled
            if autostartNow { autostartDone = true }
            if autostartNow, request.resumeLastSource, playing == nil, let last = model.progress.lastSource(for: request.id) {
                // nie eine zuletzt fehlgeschlagene; Welle E-b: Wahl immer in kluger Ordnung, egal wie die Liste sortiert ist
                let pick = Self.resumeCandidate(last, in: model.autoOrderedStreams(untried), title: request.id)
                if let s = pick.stream {
                    RemoteLog.info("player", "Weiterschauen mit letzter Quelle: \(s.name ?? "") \(s.label.prefix(60))")
                    if await autostartAfterPush(since: appeared) {
                        entryFocusDone = true   // Review F-c M3: Rückkehr regelt focusAfterPlayer, nicht der Eintritt
                        playing = s
                    }
                } else {
                    nextNote = pick.note
                    RemoteLog.info("player", "Letzte Quelle nicht gefunden (\(last.fingerprint.prefix(60)))")
                }
            }
            if autostartNow, let wanted = request.bestChoice, playing == nil {
                // Welle G-a: „Sofort abspielen“: die auf der Detailseite gezeigte Quelle; fehlt sie im frischen Stand
                // oder ist sie inzwischen fehlgeschlagen, neu wählen (gleiche Regeln). Rückfall danach wie immer.
                let auto = model.autoOrderedStreams(untried)
                let same = wanted.match(in: PlaybackStability.shared.autoCandidates(auto, title: request.id))
                if let s = same ?? model.bestChoice(untried, title: request.id)?.stream {
                    RemoteLog.info("play", "Beste Wahl startet\(same == nil ? " (neu gewählt)" : ""): \(s.name ?? "") \(s.label.prefix(60))")
                    if await autostartAfterPush(since: appeared) {
                        entryFocusDone = true
                        playing = s
                    }
                } else {
                    nextNote = "Keine abspielbare Quelle gefunden – bitte wählen."
                    RemoteLog.info("play", "Beste Wahl: keine abspielbare Quelle mehr → Liste")
                }
            }
            if playing == nil { focusOnEntry() }
            // Welle D-b (M3, Nacharbeit I2): lückenhafter alter Stand → Erneuerung abwarten und nur die neuen Quellen
            // anhängen (bestehende Zeilen bleiben: Fokus, `failed`, Rückfall). Nicht, wenn inzwischen etwas spielt oder
            // startet oder die Liste schon eine andere Folge zeigt.
            if playing == nil, current == nil, model.partialNeedsRefresh(id: request.id) {
                refreshingPartial = true
                let fresh = await model.refreshedPartialStreams(type: request.type, id: request.id)
                refreshingPartial = false
                if let fresh, !Task.isCancelled, playing == nil, current == nil {
                    let added = StreamListMerge.additions(to: streams, from: fresh)
                    if !added.isEmpty {
                        streams += model.orderedStreams(added)
                        RemoteLog.info("streams", "\(request.id): \(added.count) nachgeladene Quellen an die Liste angehängt")
                    }
                }
            }
        }
        .onChange(of: streams.map { Self.traitKey($0.stream) }) { _, keys in
            // Wave Q: parse each source once (body runs on every focus move); drop gone ones. Keyed with the hints,
            // so a hints-only change re-parses and re-checks the chips too (review Q M3/N3).
            let keep = Set(keys)
            var t = traitsByID.filter { keep.contains($0.key) }
            for (k, e) in zip(keys, streams) where t[k] == nil { t[k] = StreamTraits.parse(e.stream) }
            traitsByID = t
            dropMissingChips()
        }
        .onChange(of: shownIDs) { old, new in keepFocusPosition(old: old, new: new) }
        .onChange(of: playing) { old, s in
            if s == nil, let old { closedPlayer = old; sideStart = nil }
            guard let s else { return }
            // Addon aus der Liste, sonst das bei der nächsten Folge gemerkte (sonst „Addon nicht installiert“ beim Neuauflösen).
            model.rememberSource(current ?? request, stream: s,
                                 addon: streams.first { $0.stream.id == s.id }?.addon ?? autoNext.addons[s.id] ?? "")
        }
        .fullScreenCover(item: $playing, onDismiss: playerDismissed) { s in
            if let u = s.url.flatMap(URL.init(string:)) { PlayerScreen(url: u, request: current ?? request,
                                                                             headers: s.behaviorHints?.proxyHeaders?.request ?? [:],
                                                                             onEnded: { ended(s, autoplay: $0) }, onFallback: { fallback(from: s, reason: $0) },
                                                                             onUserInput: { AutoNextState.userInput($autoNext) },
                                                                             holdsUpNext: autoNext.promptDue(model.profile),
                                                                             onSourceVerdict: { [id = (current ?? request).id] in PlaybackStability.shared.apply($0, stream: s, title: id) },
                                                                             releaseName: s.behaviorHints?.filename,
                                                                             sideLinks: sidePanelLinks(for: s),
                                                                             startOverride: sideStart?.id == s.id ? sideStart?.at : nil).environmentObject(model) }   // Wave P-b
        }
        .modifier(StillWatchingAlert(state: $autoNext, note: $nextNote) { startNext($0.next, after: $0.stream, auto: false) })
    }
}

extension StreamListView {
    /// Wave F-j round 1 (hypothesis D): with a cache hit the autostart wanted the full-screen player about 140 ms
    /// after the push, while the push transition was still running; presenting during a push can leave the tab bar
    /// in a stale state. Waits until `AutostartAfterPush.settleMs` after the list appeared (no wait if the search
    /// took longer). A fixed delay rather than a transition callback: SwiftUI offers no reliable "push finished"
    /// event, and a missed callback would block the autostart for good. False if the list disappeared (task
    /// cancelled) or a row was chosen by hand meanwhile.
    private func autostartAfterPush(since appeared: Double) async -> Bool {
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - appeared) * 1000)
        let wait = AutostartAfterPush.remainingWait(elapsedMs: elapsed)
        if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
        guard !Task.isCancelled, playing == nil else { return false }
        RemoteLog.info("nav", "Autostart nach Push (\(Int((ProcessInfo.processInfo.systemUptime - appeared) * 1000)) ms)")
        return true
    }

    /// In dieser Liste startbar: Adresse da, hier nicht gescheitert, nicht im 8-h-Gedächtnis.
    private func focusPlayable(_ id: String) -> Bool {
        guard let s = streams.first(where: { $0.stream.id == id })?.stream else { return false }
        return s.url != nil && !failed.contains(id) && !PlaybackStability.shared.isRecentlyFailed(s, title: (current ?? request).id)
    }

    /// Eintritt (§3.2): zuletzt gespielte Quelle, sonst die erste spielbare. Einmal je Liste und nur, solange der
    /// Nutzer den Fokus nicht selbst auf eine andere Zeile gelegt hat.
    func focusOnEntry() {
        guard !entryFocusDone else { return }
        entryFocusDone = true
        let ids = visibleIDs
        guard focusedStream == nil || focusedStream == ids.first else { return }
        // Review Q I3: nil also means "on the chip bar"; a chosen filter counts as the user's choice too.
        if filterTouched {
            RemoteLog.info("fokus", "Quellenliste Eintritt: Fokus bleibt bei den Filtern")
            return
        }
        let last = model.progress.lastSource(for: (current ?? request).id)?.match(in: streams)?.id
        guard let id = SourceFocus.entry(ids: ids, lastPlayed: last, isPlayable: focusPlayable) else { return }
        requestFocus(id, in: ids, reason: last == id ? "Eintritt, zuletzt gespielt" : "Eintritt", delayMs: 0)
    }

    /// Player geschlossen (§3.2): nach einem Fehler die nächste Quelle unter der gescheiterten, sonst die gespielte.
    func focusAfterPlayer(_ played: StreamItem) {
        let failure = lastFailure == played.id
        lastFailure = nil
        if failure, autoSwitchScheduled {
            autoSwitchScheduled = false
            RemoteLog.info("fokus", "Quellenliste nach Fehler: automatischer Wechsel geplant, kein Fokuswunsch")
            return
        }
        let ids = visibleIDs
        guard let id = SourceFocus.afterPlayer(ids: ids, played: played.id, failed: failure, isPlayable: focusPlayable)
        else { return }
        requestFocus(id, in: ids, reason: failure ? "nach Fehler" : "nach dem Player", delayMs: 200)
    }

    /// Wave F-m: the cover is fully gone. Build 198 scrolled to the played row while it was still being dismissed
    /// (about 90 ms before the player's onDisappear) and the tab bar followed that scroll off screen for good.
    /// The focus move now starts here; the tab-wide guard checks the bar afterwards.
    func playerDismissed() {
        TabBarGuard.shared.check(.playerClosed)
        if PostPlayRoute.flushNow() { closedPlayer = nil; return }   // wave P-a: card pick → its detail page, no focus move
        guard let old = closedPlayer else { return }
        closedPlayer = nil
        focusAfterPlayer(old)
    }

    /// Wave Q: new sources sort in while the list is shown. The focus keeps its row position instead of following
    /// its source (the list would scroll under the user's thumb). Not while a player is open or closing, or a focus
    /// move is pending: those set the focus themselves.
    /// Review Q I2: goes through the checked request path (scroll, set, verify, up to 4 tries), which logs
    /// "Platz gehalten: Zeile n (Versuch k)" only once the focus is verified there, else "nicht gesetzt". A newer
    /// batch replaces a pending keep request and measures from its target; other requests are never replaced.
    private func keepFocusPosition(old: [String], new: [String]) {
        guard playing == nil, closedPlayer == nil else { return }
        let pending = focusRequest?.keep == true ? focusRequest : nil
        guard focusRequest == nil || pending != nil else { return }
        // Pending keep move: measure from its target, unless the user has moved on (review Q N2).
        let focused = pending.flatMap { p in focusedStream == nil || focusedStream == p.from ? p.id : nil } ?? focusedStream
        guard let id = SourceFocus.keepPosition(focused: focused, old: old, new: new) else { return }
        focusRequest = SourceFocusRequest(id: id, index: new.firstIndex(of: id) ?? 0, reason: "Platz gehalten",
                                          delayMs: 0, keep: true,
                                          from: pending != nil && focused == pending?.id ? pending?.from : focused)
    }

    private func setFilter(_ chips: Set<SourceFilterChip>) {
        filter = chips
        filterTouched = true
        let names = chips.map(\.label).sorted().joined(separator: ", ")
        RemoteLog.info("quellen", "Filter \(names.isEmpty ? "aus" : names) → \(visibleIDs.count) von \(streams.count)")
    }

    /// Review Q I1: a chosen chip the current list no longer has (next episode without DV) drops out; the
    /// selection falls back to "Alle".
    private func dropMissingChips() {
        guard !filter.isEmpty else { return }
        let gone = SourceFilter.dropped(filter, options: filterOptions)
        guard !gone.isEmpty else { return }
        filter = []
        RemoteLog.info("quellen", "Filter \(gone.map(\.label).sorted().joined(separator: ", ")) fehlt in der Liste → Alle")
    }

    /// Review Q M2: "Filter aufheben" disappears with the filter, so the focus goes to the first playable row.
    private func clearFilterToList() {
        setFilter([])
        let ids = visibleIDs
        guard let id = SourceFocus.entry(ids: ids, lastPlayed: nil, isPlayable: focusPlayable) else { return }
        requestFocus(id, in: ids, reason: "Filter aufgehoben", delayMs: 0)
    }

    private func requestFocus(_ id: String, in ids: [String], reason: String, delayMs: Int) {
        focusRequest = SourceFocusRequest(id: id, index: ids.firstIndex(of: id) ?? 0, reason: reason, delayMs: delayMs)
    }

    /// Nächste Quelle (Liste in kluger Ordnung): zuerst gecachte (⚡) unterhalb, dann gecachte oberhalb, zuletzt unbekannte; nie sicher ungecachte (🎫/⏳).
    func fallbackCandidate(after i: Int, in list: [StreamItem]) -> StreamItem? {
        let order = Array(list[(i + 1)...]) + Array(list[..<i])
        let open = order.filter { !failed.contains($0.id) && $0.url != nil
            && !PlaybackStability.shared.isRecentlyFailed($0, title: (current ?? request).id) }   // Welle C-a: 8-h-Gedächtnis
        return open.first { StreamTraits.parse($0).cached == true } ?? open.first { StreamTraits.parse($0).cached == nil }
    }

    /// Wave P-b: what the player's side panel may do with this list (other source, other episode).
    func sidePanelLinks(for s: StreamItem) -> PlayerSideLinks {
        PlayerSideLinks(stream: s, addon: streams.first { $0.stream.id == s.id }?.addon ?? autoNext.addons[s.id],
                        sources: { streams }, failed: { failed },
                        switchSource: { next, held in
                            fallbacks = 0; AutoNextState.userInput($autoNext); autoNext.ask = nil
                            playing = nil
                            Task {
                                try? await Task.sleep(for: .milliseconds(900))
                                guard playing == nil else { return }
                                PlaybackStability.shared.timing.markTap()
                                sideStart = (next.id, held)
                                playing = next
                            }
                        },
                        playEpisode: { next in
                            AutoNextState.userInput($autoNext); autoNext.ask = nil
                            playing = nil
                            startNext(next, after: s, auto: false)
                        })
    }

    /// Quelle versagt → nächste noch nicht gescheiterte Quelle darunter, höchstens 3 automatische Wechsel.
    func fallback(from s: StreamItem, reason: String) {
        failed.insert(s.id)
        lastFailure = s.id
        autoSwitchScheduled = false
        playing = nil
        // Welle E-b: Rückfall in kluger Ordnung (Dekoder, Sprache, Cache), auch wenn die Liste wie das Addon sortiert ist.
        let list = model.autoOrderedStreams(streams).map(\.stream)
        guard fallbacks < 3, let i = list.firstIndex(where: { $0.id == s.id }),
              let next = fallbackCandidate(after: i, in: list) else {
            nextNote = "\(reason). Bitte eine andere Quelle wählen."
            RemoteLog.info("player", "Kein automatischer Wechsel mehr (\(fallbacks) versucht)")
            return
        }
        fallbacks += 1
        autoSwitchScheduled = true
        nextNote = "\(reason) – versuche nächste Quelle (\(fallbacks)/3) …"
        RemoteLog.info("player", "Wechsel \(fallbacks)/3 auf: \(next.name ?? "") \(next.title?.prefix(60) ?? "")")
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            // Inzwischen von Hand eine Quelle gestartet: den laufenden Player nicht ersetzen.
            guard playing == nil else { return }
            playing = next
        }
    }

    /// Folge zu Ende → nächste Folge mit gleichem Release starten (Spec §6 Player: nächste Folge).
    /// Nach N automatischen Folgen ohne Tastendruck erst „Noch da?“ fragen.
    func ended(_ stream: StreamItem, autoplay: Bool = true) {
        playing = nil
        guard autoplay, model.profile.autoplayNext, let next = (current ?? request).nextRequest else { return }
        if autoNext.promptDue(model.profile) {
            RemoteLog.info("player", "Noch da?: nach \(autoNext.counter.autoStarts) automatischen Folgen, vor \(next.title)")
            // Erst nach dem Schließen des Players zeigen (Alert während der Cover-Animation geht verloren).
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                // Inzwischen von Hand eine Quelle gestartet oder Zähler zurückgesetzt: keine veraltete Abfrage.
                guard playing == nil, autoNext.promptDue(model.profile) else { return }
                autoNext.ask = StillWatchingAsk(stream: stream, next: next)
            }
            return
        }
        // Nur der Tastendruck, der diesen Start auslöst („Klick: jetzt“, ≤ 1,5 s vorher), macht ihn zu einem von Hand.
        startNext(next, after: stream, auto: !autoNext.counter.startIsManual())
    }

    /// Quellen der nächsten Folge holen und die zum laufenden Release passende starten (Rückfall: Listenreihenfolge).
    func startNext(_ next: PlayRequest, after stream: StreamItem, auto: Bool) {
        nextNote = "Nächste Folge wird gesucht: \(next.title) …"
        let ref = autoNext.releaseProfile(stream, listAddon: streams.first { $0.stream.id == stream.id }?.addon)
        Task {
            // Welle E-b: Wahl in kluger Ordnung, angezeigt wird die Liste nach „Quellen sortieren“.
            let fetched = await model.streamsForAutoplay(type: next.type, id: next.id)
            let list = model.autoOrderedStreams(fetched)
            // Während der Suche von Hand eine Quelle gestartet: Liste und Folge so lassen, nichts ersetzen.
            guard playing == nil else { nextNote = nil; return }
            guard let s = nextEpisodeStream(PlaybackStability.shared.autoCandidates(list, title: next.id), matching: ref) else {
                nextNote = nextEpisodeStream(list, matching: ref) != nil ? "Nur zuletzt fehlgeschlagene Quellen für \(next.title) – bitte wählen."
                                                                         : "Keine Quelle für \(next.title) gefunden."; return
            }
            let addon = list.first { $0.stream.id == s.id }?.addon
            RemoteLog.info("player", "Nächste Folge: \(addon ?? "?") · \(s.name ?? "") · Nähe \(ref.score(s, addon: addon))\(s.behaviorHints?.bingeGroup == ref.bingeGroup && ref.bingeGroup != nil ? " (bingeGroup)" : "")")
            if let addon { autoNext.addons[s.id] = addon }
            if auto { autoNext.counter.autoStarted() }
            nextNote = nil
            current = next
            // Liste zeigt jetzt die Quellen dieser Folge: Auswahl von Hand und Rückfall arbeiten auf ihr.
            streams = model.orderedStreams(fetched)
            failed = []
            fallbacks = 0
            try? await Task.sleep(for: .milliseconds(800))
            guard playing == nil else { return }
            playing = s
        }
    }
}

/// Fokuswunsch der Quellenliste; jede Anfrage ist neu (`token`), auch für dieselbe Zeile.
struct SourceFocusRequest: Equatable {
    let id: String
    let index: Int
    let reason: String
    let delayMs: Int
    /// Wave Q: keep-position move while sources arrive (a newer batch may replace it).
    var keep = false
    /// Keep move: the source the focus was on when the move began (a different focus means a key press).
    var from: String? = nil
    let token = UUID()
}

/// Welle E-b: Zeile wie vom Formatter des Addons gebaut: links `name`, rechts `description`/`title`, Umbrüche und
/// Emoji bleiben. Welle F-i: ganzer Text (StreamRowText, Kürzung erst ab 12 Zeilen, Cache-Zeilen dann zuerst), die
/// Zeile wächst mit; links unter dem Namen der Cache-Zustand als Plakette („Sofort bereit“ / „Nicht gecacht“,
/// unbekannt: keine). Rechts kompakt nur die Größe (StreamListBadges). Addon-Name nur bei gemischter Liste.
struct StreamRow: View {
    @EnvironmentObject var model: AppModel
    let addon: String?
    let stream: StreamItem
    /// Fokussierte Zeile ist weiß: Texte über `textRoleInRow` dunkel, Plaketten auf der Fokus-Tönung.
    @Environment(\.isFocused) private var focused
    var body: some View {
        let text = StreamRowText(stream)
        let badges = StreamListBadges.badges(stream, mode: model.profile.sources.appBadges, settings: model.profile.appearance.badges)
        let cache = StreamListBadges.cacheBadge(stream, settings: model.profile.appearance.badges)
        HStack(alignment: .top, spacing: Theme.Space.m) {
            if !text.name.isEmpty || cache != nil {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if !text.name.isEmpty {
                        Text(text.name).textRoleInRow(.rowTitleEmphasis)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let cache { ThemeBadge(cache, size: .sources, surface: focused ? .focusedRow : .plain) }
                }
                .frame(width: 330, alignment: .leading)
            }
            // Keine Zeilengrenze: StreamRowText kürzt selbst (Cache-Zeilen zuerst); die Zeile wächst mit dem Text.
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(text.body).textRoleInRow(.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                // Wave Q: full file name, wrapped, when the formatter text does not carry it.
                if let file = text.fileName {
                    Text(file).textRoleInRow(.rowDetail).opacity(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !badges.isEmpty || addon != nil {
                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    if !badges.isEmpty {
                        HStack(spacing: Theme.Space.xs) {
                            ForEach(badges) { ThemeBadge($0, size: .sources, surface: focused ? .focusedRow : .plain) }
                        }
                    }
                    if let addon { Text(addon).textRoleInRow(.rowDetail).lineLimit(1) }
                }
                .fixedSize()
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// X3: Kopfzeile der Quellenliste „161 Quellen · 8,4 s“ (Dauer = längste Addon-Antwort der laufenden Suche).
/// Eigene View, damit nur sie dem Suchstand folgt, nicht die ganze Liste.
struct StreamListSummaryLine: View {
    @ObservedObject private var status = StreamSearchStatus.shared
    let id: String
    let count: Int

    var body: some View {
        Text(StreamListSummary.text(count: count, milliseconds: status.progress[id]?.elapsedMilliseconds))
            .textRole(.rowDetail)
    }
}

func timeText(_ s: Double) -> String {
    let t = Int(max(0, s)); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

/// Suche über TMDB (Filme + Serien).
struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var results: [MetaPreview] = []
    @State private var searching = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                TextField("Film oder Serie suchen", text: $query)
                    .onSubmit { Task { await run() } }
                    .padding(.horizontal, 60)
                if model.tmdb == nil { Text("Für die Suche fehlt der TMDB-Key (Einstellungen → Dienste).").foregroundStyle(.secondary).padding(.leading, 60) }
                if searching { ProgressView().padding(.leading, 60) }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(240), spacing: 40), count: 6), alignment: .leading, spacing: 50) {
                    ForEach(results) { m in
                        NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m))
                    }
                }
                .padding(.horizontal, 60)
            }
            .padding(.vertical, 40)
        }
        .task(id: query) {
            // Tippen entprellen: erst nach kurzer Pause suchen.
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { await run() }
        }
    }

    private func run() async {
        guard let tmdb = model.tmdb, query.count >= 2 else { results = []; return }
        searching = true
        results = (try? await tmdb.search(query)) ?? []
        searching = false
    }
}

/// Infozeile der Detailseite (§4.5): Technik gefüllt neutral, Bewertungen ohne Rahmen („IMDb 7,1“).
/// Einzeilig: passt die Zeile nicht, entfallen Bewertungen von hinten (Technik bleibt), nie Umbruch.
struct InfoBadges: View {
    /// Welle E-a: schon nach der Bewertungsauswahl gefiltert (`AppModel.ratingBadges`).
    let ratings: [RatingBadge]
    /// Höchstens 5 (`QualityBadges.detailRow`); die Altersfreigabe steht in der Textzeile darüber.
    let tech: [QualityBadge]
    static let height: CGFloat = ThemeBadge.TechSize.detail.height

    var body: some View {
        // Immer vorhandener Platzhalter hält die Zeilenhöhe, auch bevor die erste Plakette kommt.
        ZStack(alignment: .leading) {
            Color.clear.frame(height: Self.height)
            if !ratings.isEmpty || !tech.isEmpty {
                ViewThatFits(in: .horizontal) {
                    ForEach(Array((0...ratings.count).reversed()), id: \.self) { n in row(ratings: Array(ratings.prefix(n))) }
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private func row(ratings shown: [RatingBadge]) -> some View {
        HStack(spacing: Theme.Space.m) {
            if !tech.isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(tech) { ThemeBadge($0, size: .detail) }
                }
            }
            ForEach(shown) { ThemeBadge(rating: $0, brandColor: Self.brandColor($0.source)) }
        }
    }

    /// Markenfarbe des Quellennamens (nur Schrift, keine fremden Logos).
    static func brandColor(_ source: String) -> Color {
        switch source {
        case "imdb": Color(red: 0.96, green: 0.77, blue: 0.09)
        case "letterboxd": Color(red: 0.0, green: 0.88, blue: 0.33)
        case "trakt": Color(red: 0.93, green: 0.11, blue: 0.14)
        case "tmdb": Color(red: 0.0, green: 0.82, blue: 0.85)
        default: Theme.Palette.primary
        }
    }
}

/// Besetzung, ähnliche Titel und „Über“ (alles aus dem einen TMDB-Abruf).
struct DetailExtras: View {
    @Environment(\.navigate) private var navigate
    @EnvironmentObject var model: AppModel
    let info: LocalizedMeta
    let isSeries: Bool

    /// Wave F-k: vertical room of „Ähnliche Titel“ (`.card` lift of a 360 pt poster + quality strip below).
    private var similarPadding: CGFloat {
        let strip = model.profile.appearance.titles.posterBadges == .bottom ? PosterQualityBadges.bandHeight : 0
        return Theme.Focus.cardRowPadding(height: FocusHeadroom.tallest([.poster], cardScale: 1, posterExtra: strip),
                                          minimum: Theme.Focus.tileRowPadding)
    }

    /// Wave F-k: „Plaketten: Ähnliche Titel n/m mit Qualität“ (source cache, filled by the visible-tile prefetch).
    /// Once per page and count (`CollectionRowLog`, keyed by the page's titles), after the count rested 2 s.
    private func noteSimilarBadges() {
        let m = model, recs = info.recommendations
        guard !recs.isEmpty else { return }
        CollectionRowLog.noteLater(row: "badges|similar|" + recs.prefix(3).map(\.id).joined(separator: ",")) {
            let a = m.profile.appearance
            let n = recs.filter { PosterBadgeStats.hasBadges(QualityBadgeCache.shared.best(for: $0, model: m), settings: a.badges) }.count
            return PosterBadgeStats.logLine(row: "Ähnliche Titel", withQuality: n, total: recs.count, placement: a.titles.posterBadges)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !info.cast.isEmpty {
                Text("Besetzung").textRole(.sectionTitle).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    // Welle F-i: eigener Kachelstil (Anheben 1,06 ≈ 8 pt je Seite) statt `.card`; Abstand ≥ Wachsen,
                    // Rand oben/unten `Focus.tileRowPadding`, damit Kachel und Schatten nicht in „Ähnliche Titel“ ragen.
                    LazyHStack(spacing: Theme.Space.l) {
                        ForEach(info.cast) { c in
                            Button { navigate(.person(id: c.id, name: c.name)) } label: {
                                VStack(spacing: 10) {
                                    RemoteImage(url: c.photo, maxPixels: 370)
                                        .frame(width: 180, height: 180).clipShape(Circle())
                                        .overlay { if c.photo == nil { Text(String(c.name.prefix(1))).font(.title) } }
                                    Text(c.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    if let r = c.role { Text(r).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                .frame(width: 220).padding(.vertical, Theme.Space.xs)
                            }
                            .buttonStyle(ThemeTileButtonStyle())
                        }
                    }
                    .padding(.vertical, Theme.Focus.tileRowPadding)
                }
                .scrollClipDisabled()
            }
            if !info.recommendations.isEmpty {
                Text("Ähnliche Titel").textRole(.sectionTitle).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 40) {
                        ForEach(info.recommendations) { m in
                            NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m))
                                .modifier(RestPrefetch(route: .detail(m)))
                        }
                    }
                    // Wave F-k: same room for the card lift as the home rows (poster at factor 1), at least 44.
                    .padding(.vertical, similarPadding)
                }
                .scrollClipDisabled()
                // Wave F-k R1: these tiles prefetch their sources too (badge); log line per page, after 2 s of rest.
                .environment(\.prefetchRow, PrefetchRow(key: "similar", title: "Ähnliche Titel"))
                .task(id: info.recommendations.map(\.id)) { noteSimilarBadges() }
                .onReceive(QualityBadgeCache.shared.stored) { id in
                    // Wave F-k R2 (m5): only when one of these titles got its sources.
                    guard info.recommendations.contains(where: { model.streamCacheKey(for: $0) == id }) else { return }
                    noteSimilarBadges()
                }
            }
            let rows = aboutRows
            if !rows.isEmpty {
                Text("Über").textRole(.sectionTitle).accessibilityAddTraits(.isHeader)
                Button {} label: {
                    Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 14) {
                        ForEach(rows, id: \.0) { r in
                            GridRow {
                                Text(r.0).foregroundStyle(.secondary)
                                Text(r.1)
                            }
                        }
                    }
                    .font(.callout).padding(36).frame(maxWidth: 1400, alignment: .leading)
                }
                .buttonStyle(.card)
            }
        }
    }

    private var aboutRows: [(String, String)] {
        var r: [(String, String)] = []
        func add(_ k: String, _ v: String?) { if let v, !v.isEmpty { r.append((k, v)) } }
        add("Originaltitel", info.originalTitle)
        add(isSeries ? "Erstausstrahlung" : "Erschienen", info.releaseDate.flatMap(Self.germanDate))
        add(isSeries ? "Idee" : "Regie", info.creators.prefix(3).joined(separator: ", "))
        add("Drehbuch", info.writers.prefix(3).joined(separator: ", "))
        add(isSeries ? "Sender / Studio" : "Studio", info.studios.joined(separator: ", "))
        add("Land", info.countries.joined(separator: ", "))
        if let s = info.seasons { add("Umfang", "\(s) Staffel\(s == 1 ? "" : "n")" + (info.episodes.map { " · \($0) Folgen" } ?? "")) }
        add("Budget", info.budget.map(Self.money))
        add("Einspielergebnis", info.revenue.map(Self.money))
        add("Status", info.status.map(Self.statusText))
        return r
    }

    static func germanDate(_ s: String) -> String? {
        ISODate.germanDay(s)
    }

    static func money(_ v: Int) -> String {
        v >= 1_000_000 ? String(format: "%.0f Mio. $", Double(v) / 1_000_000) : "\(v) $"
    }

    static func statusText(_ s: String) -> String {
        switch s {
        case "Released": "Erschienen"
        case "Returning Series": "Läuft noch"
        case "Ended": "Beendet"
        case "Canceled": "Abgesetzt"
        case "In Production": "In Produktion"
        case "Post Production": "In Postproduktion"
        case "Planned": "Geplant"
        default: s
        }
    }
}

/// Wave F-p: a resting tile outside the home page („Ähnliche Titel“) fetches its sources like a home tile, so its
/// detail page shows the tech badges from the source cache at once.
private struct RestPrefetch: ViewModifier {
    @EnvironmentObject var model: AppModel
    let route: Route
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, f in
                if f { StreamPrefetcher.shared.requestAfterRest(route, model: model) } else { StreamPrefetcher.shared.cancelRest(route) }
            }
            // R1: the tile goes away with focus on it (page left within 350 ms): no stale request.
            .onDisappear { StreamPrefetcher.shared.cancelRest(route) }
    }
}
