import SwiftUI
import Combine
import PlayerCore

/// Detailseite: Hintergrund, Beschreibung, Abspielen (Film) bzw. Staffeln/Folgen (Serie).
struct DetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    /// Task 5.3: the detail options (`theme.detail`: layout, description, cast, badges, ratings).
    @Environment(\.theme) private var theme
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
    /// Task 1.8: the same moment on the monotonic clock (`systemUptime`) for `detail.badges`.
    @State private var appearedUptime: TimeInterval?
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
    /// Review W1: a title logo that did not load; the head falls back to poster and text title.
    @State private var failedLogo: String?
    /// Review W3: height of the scroll area (safe area), measured; 0 until the first layout.
    @State private var scrollAreaHeight: CGFloat = 0
    @State private var kinoLogged = false
    /// Review (minor): the return from the player sets the season itself and its focus target; the season
    /// change must not scroll the row to its start over that target.
    @State private var skipRowStart = false

    /// Wave W-a: "anime" and other episodic addon types count as series (`ContentKind`); an unknown type once its
    /// meta lists episodes.
    private var isSeries: Bool { ContentKind.isEpisodic(type: item.type, hasVideos: (meta?.videos?.count ?? 0) > 1) }

    var body: some View {
        let spec = layoutSpec
        ZStack(alignment: .topLeading) {
            DetailBackdrop(meta: meta?.background, tile: item.background, shades: spec.shades)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        // Review W2: the head above the backing of `lower`, which reaches up into it.
                        head(spec).zIndex(1)
                        lower(spec)
                    }
                    .padding(.vertical, Theme.Space.edgeVertical)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    guard abs(h - scrollAreaHeight) >= 1 else { return }
                    scrollAreaHeight = h
                    logKinoHead(layoutSpec)
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
        // Task 3.7 (A-A-6): badges (and the „Sofort abspielen“ pick) from the first intermediate result of the
        // search, not only after the slowest addon. Movies only; the cache path above wins when it has a state.
        .streamSearchPartials(id: imdb ?? "", loading: !isSeries && imdb != nil && best == nil) { applyPartialStreams($0) }
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
            if appeared == nil { appeared = Date(); appearedUptime = ProcessInfo.processInfo.systemUptime }
            // Welle G-a: nach dem Player neu wählen (8-h-Gedächtnis, letzte Quelle können sich geändert haben).
            if loaded, let id = imdb { updateChoice(id) }
            // Quellen schon im Cache (z. B. zweiter Besuch): Technik-Plaketten im ersten Bild, nicht erst nach dem Laden.
            let id = imdb ?? (item.id.hasPrefix("tt") ? item.id : nil)
            // Task 3.8: one ranked list for the badges and the pick.
            if best == nil, !isSeries, let id, let ranked = rankedCache(id), let b = DetailQuality.from(ranked) {
                best = b
                logFirstBadges("Technik aus Cache")
                markLoad(.tech, source: cacheSource(id))
                updateChoice(id, ranked: ranked)
            }
        }
        .task {
            guard !loaded else { return }
            let opened = appeared ?? Date()
            imdb = await model.imdbID(for: item)
            if let imdb {
                markLoad(.id)
                if !isSeries, best == nil, let ranked = rankedCache(imdb), let b = DetailQuality.from(ranked) {
                    best = b
                    logFirstBadges("Technik aus Cache")
                    markLoad(.tech, source: cacheSource(imdb))
                    updateChoice(imdb, ranked: ranked)
                } else if !isSeries, best != nil {
                    markLoad(.tech, source: cacheSource(imdb))
                } else if !isSeries, best == nil {
                    // Quellen sofort und parallel holen (Technik-Plaketten; AppModel cached sie für die Quellenliste).
                    let id = imdb
                    Task {
                        let list = await model.streams(type: "movie", id: id)
                        // Task 3.7: the final state only adds to a row built from an intermediate result (no jump).
                        let final = detailQuality(id)
                        best = best.map { $0.adding(final) } ?? final
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
            logLook()
            logKinoHead(layoutSpec)
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
            if let s = target.season, s != season {
                skipRowStart = true
                season = s
            }
            await applyFocus(target, reason: "nach dem Player")
        }
        .onChange(of: season) {
            scrollRowToStart()
            Task { await translateSeason() }
        }
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
        if let up = StartTiming.ms(appearedUptime, ProcessInfo.processInfo.systemUptime) {   // Task 1.8
            RemoteLog.metric(.detailBadges, ms: up, fields: ["quelle": source])
        }
    }

    /// Wave F-p: the TMDB text fills in while the meta loads (catalogue entries without a description), so the
    /// block reaches its height and the poster shows early.
    private var overview: String { meta?.description ?? item.description ?? extra?.overview ?? "" }

    /// Meta line, badges, tagline and description (wave F-n: measured for the poster to its left).
    /// Task 5.3: width, alignment and description lines from `detail.layout` / `detail.descriptionLines`, the
    /// ratings in `detail.ratingStyle`.
    @ViewBuilder private func infoBlock(_ spec: DetailLayoutSpec) -> some View {
        let width = CGFloat(spec.infoWidth)
        let centred = spec.alignment == .center
        VStack(alignment: centred ? .center : .leading, spacing: Theme.Space.l) {
            // Welle E-a: FSK steht in der Textzeile („2018 · 97 min · FSK 0 · Genre“), nicht als Plakette.
            MetaLine(parts: [meta?.releaseInfo ?? item.releaseInfo, meta?.runtime, certification ?? ratings?.certification,
                             meta?.genres?.prefix(3).joined(separator: ", ")])
            DetailBadges(ratings: model.ratingBadges(imdbRating: meta?.imdbRating, mdblist: ratings), tech: techBadges,
                         ratingStyle: DetailLook.ratingStyle(theme.detail.ratingStyle, layout: spec.variant),
                         centred: centred)
            // Review M3: same width cap as the description, so the poster does not change its line breaks.
            if let t = extra?.tagline {
                Text(t).italic().textRole(.rowDetail)
                    .multilineTextAlignment(centred ? .center : .leading)
                    .frame(maxWidth: width, alignment: centred ? .center : .leading)
            }
            if !overview.isEmpty { overviewButton(spec) }
        }
    }

    /// Short description; a press opens the whole text (`FullTextSheet`).
    private func overviewButton(_ spec: DetailLayoutSpec) -> some View {
        let centred = spec.alignment == .center
        let lines = DetailLook.descriptionLineLimit(theme.detail.descriptionLines, layout: spec.variant)
        return Button { showFullText = true } label: {
            FocusHighlight {
                Text(overview).font(.callout).foregroundStyle(.white).lineLimit(lines)
                    .multilineTextAlignment(centred ? .center : .leading)
            }
        }
        .buttonStyle(.plain)
        .focused($focus, equals: .overview)
        .frame(maxWidth: CGFloat(spec.infoWidth), alignment: centred ? .center : .leading)
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

    /// Task 3.7 (A-A-6): first intermediate result of this page's search: badges right away; the pick of
    /// „Sofort abspielen“ too, if there is one (no „Keine Quelle gefunden“ before the search is through).
    private func applyPartialStreams(_ list: [(addon: String, stream: StreamItem)]) {
        guard !isSeries, best == nil, let id = imdb else { return }
        // Task 3.8: parsed once for the badges and the pick.
        let ranked = RankedStream.rank(list)
        guard let q = DetailQuality.from(ranked) else { return }
        best = q
        let ms = appeared.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        RemoteLog.info("detail", "Plaketten aus Zwischenstand nach \(ms) ms (\(list.count) Quellen)")
        logFirstBadges("Technik, Zwischenstand")
        markLoad(.tech, source: "Zwischenstand, \(list.count) Quellen")
        if instantPlayOn, choice == nil, let pick = model.bestChoice(ranked: ranked, title: id) {
            RemoteLog.info("play", "Beste Wahl aus Zwischenstand: \(pick.reason.rawValue) · \(pick.addon)")
            choice = pick
        }
    }

    /// Technik-Werte aus dem Quellen-Cache (keine Abfrage); nil ohne gecachte Quellen.
    private func detailQuality(_ id: String) -> DetailQuality? {
        rankedCache(id).flatMap { DetailQuality.from($0) }
    }

    /// Task 3.8: the cached sources with their traits parsed once (badges and pick share it); nil without cache.
    private func rankedCache(_ id: String) -> [RankedStream]? {
        model.cachedStreams(id: id).map { RankedStream.rank($0) }
    }

    /// Welle G-a: Beste Wahl neu bilden (Film). `list` = eben geholte Quellen; sonst aus dem Quellen-Cache
    /// (ohne Cache bleibt der Stand, bis die Quellen da sind).
    /// Wave F-n: only with the setting „Sofort abspielen anzeigen“ (default off); off drops any earlier pick.
    /// Task 3.8: `ranked` = a list already ranked for the badges (no second parse).
    private func updateChoice(_ id: String, list: [(addon: String, stream: StreamItem)]? = nil, ranked: [RankedStream]? = nil) {
        guard instantPlayOn else {
            choice = nil
            choiceChecked = false
            return
        }
        guard let all = ranked ?? (list ?? model.cachedStreams(id: id)).map({ RankedStream.rank($0) }) else { return }
        let pick = model.bestChoice(ranked: all, title: id)
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
                    ThemeButtonLabel(BestChoice.title(c.reason, resumeText: resume.map(timeText)), symbol: "play.fill")
                    Text(detail).textRoleInRow(.rowDetail).lineLimit(1)
                }
                .frame(maxWidth: 620, alignment: .leading)
            }
            .buttonStyle(ThemeButton(.secondary))
            .focused($focus, equals: .best)
        } else if choiceChecked {
            Button(BestChoice.noSourceText) {
                markOpenedPlayback()
                RemoteLog.info("play", "Beste Wahl: keine Quelle → Quellenliste")
                navigate(.streams(model.moviePlayRequest(item, imdb: imdb, meta: meta, resumeLastSource: false)))
            }
            .buttonStyle(ThemeButton(.secondary))
        }
    }

    /// Task 5.3: a secondary button with the SF Symbol `film` (no Unicode sign).
    private func trailerButton(_ key: String) -> some View {
        Button {
            // Doppeldruck: laufende Auflösung behalten, sonst ginge der Abbruch-Griff verloren.
            guard !trailerLoading else { return }
            trailerTask = Task { await playTrailer(key) }
        } label: {
            ThemeButtonLabel(trailerLoading ? "Trailer wird geladen …" : "Trailer", symbol: "film")
        }
        .buttonStyle(ThemeButton(.secondary))
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

    /// The episodes of season `s` in order.
    private func seasonEpisodes(_ s: Int) -> [MetaVideo] {
        (meta?.videos ?? []).filter { $0.season == s }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    private var episodesAsRow: Bool { model.profile.detailExtras.episodes == .reihe }

    @ViewBuilder private func episodes(_ imdb: String) -> some View {
        if seasons.isEmpty {
            Text("Keine Folgen gefunden.").textRole(.rowDetail)
            if overview.isEmpty && extra?.trailerYouTube == nil { FocusAnchor(kind: .back) }   // N6
        } else {
            seasonBar
            let eps = seasonEpisodes(season)
            if episodesAsRow {
                episodeRow(eps, imdb: imdb)
            } else {
                episodeList(eps, imdb: imdb)
            }
        }
    }

    private var seasonBar: some View {
        // Fokus-Anheben (tileScale) plus Schatten (Radius + Versatz ≈ 25 pt) passt in Space.l; nichts wird abgeschnitten.
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.m) {
                ForEach(seasons, id: \.self) { s in
                    Button { season = s } label: {
                        // Gewählte Staffel: Haken, erbt die Vordergrundfarbe und bleibt so auch im Fokus sichtbar.
                        ThemeButtonLabel("Staffel \(s)", symbol: s == season ? "checkmark" : nil)
                    }
                    .buttonStyle(ThemeButton(.secondary, selected: s == season))
                    .accessibilityAddTraits(s == season ? .isSelected : [])
                }
            }
            .padding(.vertical, Theme.Space.l)
        }
        .scrollClipDisabled()
    }

    /// Task 5.3 (`episodes = liste`): today's list.
    private func episodeList(_ eps: [MetaVideo], imdb: String) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(eps) { v in
                episodeButton(v, imdb: imdb, isFirst: v.id == eps.first?.id) { EpisodeListLabel(data: $0) }
            }
        }
        .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
    }

    /// Task 5.3 (`episodes = reihe`, default): a horizontal row of 16:9 cards; entry and a season change scroll it
    /// to the first unwatched episode (`DetailLook.episodeRowStart`).
    private func episodeRow(_ eps: [MetaVideo], imdb: String) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.Space.l) {
                ForEach(eps) { v in
                    episodeButton(v, imdb: imdb, isFirst: v.id == eps.first?.id) { EpisodeCardLabel(data: $0) }
                }
            }
            .padding(.vertical, Theme.Focus.tileRowPadding)
        }
        .scrollClipDisabled()
        .buttonStyle(ThemeTileButtonStyle())
    }

    /// One episode: opens its source list; the first episode of a season carries `.play` (entry focus).
    private func episodeButton<L: View>(_ v: MetaVideo, imdb: String, isFirst: Bool,
                                        @ViewBuilder label: @escaping (EpisodeLabelData) -> L) -> some View {
        Button { openEpisode(v, imdb: imdb) } label: { label(episodeData(v, imdb: imdb)) }
            .focused($focus, equals: isFirst ? .play : .episode(v.id))
            .id(v.id)
    }

    private func openEpisode(_ v: MetaVideo, imdb: String) {
        let e = v.episode ?? 0
        markOpenedPlayback()
        let list = EpisodeRef.list(from: meta?.videos ?? [], includeSpecials: EpisodeRef.includesSpecials(playingSeason: season))
        navigate(.streams(PlayRequest(type: "series", id: "\(imdb):\(season):\(e)", title: "\(item.name) S\(season)E\(e)",
                                      item: progressItem(imdb), season: season, episode: e, episodes: list)))
    }

    private func episodeData(_ v: MetaVideo, imdb: String) -> EpisodeLabelData {
        let key = "\(imdb):\(season):\(v.episode ?? 0)"
        let watched = model.progress.isWatched(key)
        let entry = model.progress.entries[key]
        let started = !watched && (entry?.position ?? 0) >= 60
        return EpisodeLabelData(number: v.episode ?? 0, title: v.name ?? v.title ?? "Folge", overview: v.overview,
                                thumbnail: v.thumbnail, watched: watched, progress: started ? entry?.fraction : nil,
                                spoiler: model.profile.sources.blurUnwatchedStills && !watched)
    }

    /// Task 5.3: on a season change the row scrolls to the season's first unwatched episode (the focus stays on
    /// the season button; entry and return set their own target through `applyFocus`).
    private func scrollRowToStart() {
        if skipRowStart {
            skipRowStart = false
            return
        }
        guard isSeries, episodesAsRow, let imdb else { return }
        let s = season
        let eps = seasonEpisodes(s)
        let refs = eps.compactMap { v in v.episode.map { EpisodeRef(season: s, episode: $0) } }
        guard let start = DetailLook.episodeRowStart(refs, isWatched: { model.progress.isWatched("\(imdb):\($0.season):\($0.episode)") }),
              let v = eps.first(where: { $0.episode == start.episode }) else { return }
        scrollTarget = v.id
        scrollRequest += 1
        RemoteLog.info("detail", "Folgenreihe Staffel \(s): Start bei Folge \(start.episode)")
    }

    // MARK: Task 5.3 layout

    /// The measures of `detail.layout` (PlayerCore `DetailLook.layout`).
    private var layoutSpec: DetailLayoutSpec {
        DetailLook.layout(theme.detail.layout, contentLeading: Double(contentLeading))
    }

    private var contentLeading: CGFloat { LookMetrics.contentLeading(model.profile.themeLook.global.navigation) }

    /// What the head shows: title logo or text, and whether the poster stands next to the info block.
    /// Review W1/W4: with `titleArt = logo` the poster waits for the meta (no poster → logo jump), and a logo that
    /// fails brings poster and text title back.
    private var titleArt: DetailTitleArt {
        let logo = meta?.logo
        return DetailLook.titleArt(model.profile.detailExtras.titleArt, logo: logo, metaKnown: meta != nil || !loading,
                                   logoFailed: logo != nil && logo == failedLogo)
    }

    /// Kino: the head fills the first screen and its info sits at the bottom (movies). A series keeps room for the
    /// season bar so the episodes (entry focus) peek in below.
    /// Review W3: from the measured scroll area (safe area, tab bar), not from the screen height.
    private var kinoHeadHeight: CGFloat? {
        DetailLook.kinoHeadHeight(area: Double(scrollAreaHeight), topPadding: Double(Theme.Space.edgeVertical),
                                  bottomInset: layoutSpec.bottomInset, series: isSeries).map { CGFloat($0) }
    }

    /// One line per page with the measured kino head (device check of W3).
    private func logKinoHead(_ spec: DetailLayoutSpec) {
        guard spec.anchorsBottom, !kinoLogged, loaded, scrollAreaHeight > 0 else { return }
        kinoLogged = true
        let head = kinoHeadHeight.map { "\(Int($0))" } ?? "–"
        RemoteLog.info("detail", "Kino-Kopf: Fläche \(Int(scrollAreaHeight)) pt, Kopf \(head) pt, Serie \(isSeries ? "ja" : "nein")")
    }

    /// Title, poster with info block, and the main actions.
    @ViewBuilder private func head(_ spec: DetailLayoutSpec) -> some View {
        let centred = spec.alignment == .center
        let art = titleArt
        VStack(alignment: centred ? .center : .leading, spacing: Theme.Space.l) {
            titleView(art, spec: spec)
            // Wave F-n: the title's poster left of the info block, exactly as tall as it (PlayerCore `DetailPage`).
            HStack(alignment: .top, spacing: CGFloat(DetailPage.posterGap)) {
                if art.showsPoster, let size = DetailPage.posterSize(blockHeight: Double(infoHeight), bottomInset: overview.isEmpty ? 0 : Double(FocusHighlightMetrics.verticalPadding)) {
                    DetailPoster(item: posterItem)
                        .frame(width: CGFloat(size.width), height: CGFloat(size.height))
                        .transition(.opacity)
                        .onAppear { markLoad(.poster) }
                }
                infoBlock(spec)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        guard DetailPage.shouldUpdate(measured: Double(h), stored: Double(infoHeight)) else { return }
                        // Review M2: animated, so the poster fades in and resizes smoothly.
                        withAnimation(.easeOut(duration: 0.2)) { infoHeight = h }
                    }
            }
            actions
        }
        .frame(maxWidth: .infinity, minHeight: headMinHeight(spec), alignment: headAlignment(spec))
        .padding(.leading, CGFloat(spec.leadingInset))
        .padding(.trailing, CGFloat(spec.trailingInset))
    }

    private func headMinHeight(_ spec: DetailLayoutSpec) -> CGFloat? {
        spec.anchorsBottom ? kinoHeadHeight : nil
    }

    private func headAlignment(_ spec: DetailLayoutSpec) -> Alignment {
        if spec.alignment == .center { return spec.anchorsBottom ? .bottom : .top }
        return spec.anchorsBottom ? .bottomLeading : .topLeading
    }

    @ViewBuilder private func titleView(_ art: DetailTitleArt, spec: DetailLayoutSpec) -> some View {
        let centred = spec.alignment == .center
        // Without the poster the logo takes its room (`titleArt = logo`).
        let height: CGFloat = art.showsPoster ? 200 : 260
        let width = min(CGFloat(700), CGFloat(spec.infoWidth))
        if let logo = art.logo {
            RemoteImage(url: logo, maxPixels: 1400, fit: true,
                        onFailure: { url in
                            failedLogo = url
                            RemoteLog.info("detail", "Titel-Logo nicht geladen: Poster und Titeltext")
                        })
                .frame(maxWidth: width, maxHeight: height, alignment: centred ? .center : .leading)
                .frame(height: art.reservesLogoSlot ? height : nil, alignment: centred ? .bottom : .bottomLeading)
                .accessibilityLabel(item.name)
        } else if art.reservesLogoSlot {
            // Review W4: meta still loading: keep the logo's room so the info block does not move when it comes.
            Color.clear.frame(width: width, height: height)
        } else {
            Text(item.name).textRole(.display).accessibilityAddTraits(.isHeader)
                .multilineTextAlignment(centred ? .center : .leading)
        }
    }

    /// Loading placeholder, the movie buttons or the series trailer button.
    @ViewBuilder private var actions: some View {
        if loading {
            // N6: ohne Beschreibung sonst nichts fokussierbar (unsichtbares Ziel, danach Abspielen).
            ProgressView().quietFocusTarget(overview.isEmpty)
        } else if let imdb {
            if isSeries {
                if let k = extra?.trailerYouTube { trailerButton(k) }
            } else {
                movieButtons(imdb)
            }
        } else {
            Text("Keine IMDb-ID gefunden – Streams nicht abrufbar.").textRole(.rowDetail)
            if overview.isEmpty { FocusAnchor(kind: .back) }   // N6
        }
    }

    /// Task 5.3: „Abspielen“ is the one primary button (accent), the others secondary; SF Symbols, no Unicode.
    private func movieButtons(_ imdb: String) -> some View {
        let resume = model.progress.resumePosition(for: imdb)
        let title = resume.map { "Fortsetzen ab \(timeText($0))" } ?? "Abspielen"
        return HStack(spacing: Theme.Space.l) {
            bestChoiceCard(imdb, resume: resume)
            Button {
                markOpenedPlayback()
                navigate(.streams(model.moviePlayRequest(item, imdb: imdb, meta: meta, resumeLastSource: resume != nil)))
            } label: {
                ThemeButtonLabel(title, symbol: "play.fill")
            }
            .buttonStyle(ThemeButton(.primary))
            .focused($focus, equals: .play)
            if let k = extra?.trailerYouTube { trailerButton(k) }
        }
    }

    /// Episodes, trailer note and the TMDB extras below the head, on a backing in the background tone so text
    /// stays readable over any picture.
    @ViewBuilder private func lower(_ spec: DetailLayoutSpec) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !loading, let imdb, isSeries { episodes(imdb) }
            if let trailerNote { Text(trailerNote).textRole(.rowDetail) }
            if !loading, imdb != nil, let x = extra {
                DetailExtras(info: x, isSeries: isSeries, castWidth: spec.castWidth.map { CGFloat($0) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, contentLeading)
        .padding(.trailing, Theme.Space.edge)
        .background(alignment: .top) { if hasLower { DetailLowerBacking() } }
    }

    /// Review W2: whether `lower` shows anything (no veil over the head when it is empty).
    private var hasLower: Bool {
        (!loading && imdb != nil && (isSeries || extra != nil)) || trailerNote != nil
    }

    /// Task 5.3: one line per page with the detail options in effect (device check of the variants).
    private func logLook() {
        let d = theme.detail
        let x = model.profile.detailExtras
        let logo = meta?.logo == nil ? "ohne Logo" : "mit Logo"
        let line = "Look: \(d.layout.rawValue) · Text \(d.descriptionLines.rawValue) Zeilen · Besetzung \(d.cast.rawValue)"
            + " · Plaketten \(d.badgeStyle.rawValue) · Bewertungen \(d.ratingStyle.rawValue)"
            + " · Folgen \(x.episodes.rawValue) · Titel \(x.titleArt.rawValue) (\(logo))"
        RemoteLog.info("detail", line)
    }
}

/// Aufgelöster Trailer für den Player.
struct TrailerPlay: Identifiable {
    let id = UUID()
    let key: String
    let stream: YouTubeStream
}
