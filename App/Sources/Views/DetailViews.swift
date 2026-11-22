import SwiftUI
import PlayerCore

/// Ordner einer Collection: eine Reihe pro Quelle.
struct FolderView: View {
    let folder: Folder
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 50) {
                Text(folder.title).font(.largeTitle.bold()).padding(.leading, 60)
                if folder.sources.isEmpty { FocusAnchor(kind: .back).padding(.leading, 60) }   // N6 (Welle F-c)
                ForEach(folder.sources) { s in
                    HomeRowView(row: HomeRow(content: .list(s), style: .poster), onActivate: { $0 })
                }
            }
            .padding(.vertical, 40)
        }
    }
}

struct CollectionView: View {
    @EnvironmentObject var model: AppModel
    let collectionID: String
    var body: some View {
        ScrollView(.vertical) {
            HomeRowView(row: HomeRow(content: .collection(id: collectionID)), onActivate: { $0 })
            if model.collection(collectionID)?.folders.isEmpty ?? true {
                FocusAnchor(kind: .back).padding(.leading, 60)   // N6 (Welle F-c): leere oder fehlende Collection
            }
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
    /// Startfokus auf der Hauptaktion, nicht auf der (darüber liegenden) Beschreibung.
    enum Focus: Hashable { case play, episode(String), overview }
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
    @State private var returnFocusToken = 0
    /// Folge, zu der die Folgenliste scrollt, bevor sie den Fokus bekommt (LazyVStack legt sie sonst nicht an).
    @State private var scrollTarget: String?
    @State private var scrollRequest = 0

    private var isSeries: Bool { item.type == "series" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: meta?.background ?? item.background).ignoresSafeArea().overlay(Color.black.opacity(0.55))
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) {
                        if let logo = meta?.logo {
                            RemoteImage(url: logo, maxPixels: 1400, fit: true).frame(maxWidth: 700, maxHeight: 200, alignment: .leading)
                        } else {
                            Text(item.name).font(.system(size: 70, weight: .heavy))
                        }
                        // Welle E-a: FSK steht in der Textzeile („2018 · 97 min · FSK 0 · Genre“), nicht als Plakette.
                        Text([meta?.releaseInfo ?? item.releaseInfo, meta?.runtime, certification ?? ratings?.certification,
                              meta?.genres?.prefix(3).joined(separator: ", ")]
                            .compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                        InfoBadges(ratings: model.ratingBadges(imdbRating: meta?.imdbRating, mdblist: ratings), tech: techBadges)
                        if let t = extra?.tagline { Text(t).italic().foregroundStyle(.secondary) }
                        if !overview.isEmpty {
                            // Kurz halten; Klick zeigt den ganzen Text.
                            Button { showFullText = true } label: { FocusHighlight { Text(overview).font(.callout).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading) } }
                                .buttonStyle(.plain)
                                .focused($focus, equals: .overview)
                                .frame(maxWidth: 1100, alignment: .leading)
                        }

                        if loading {
                            // N6: ohne Beschreibung sonst nichts fokussierbar (unsichtbares Ziel, danach Abspielen).
                            ProgressView().quietFocusTarget(overview.isEmpty)
                        } else if let imdb {
                            if isSeries {
                                if let k = extra?.trailerYouTube { trailerButton(k) }
                                episodes(imdb)
                            } else {
                                let resume = model.progress.resumePosition(for: imdb)
                                HStack(spacing: 30) {
                                    Button(resume.map { "▶ Fortsetzen ab \(timeText($0))" } ?? "▶ Abspielen") {
                                        openedPlayback = true
                                        navigate(.streams(model.moviePlayRequest(item, imdb: imdb, meta: meta, resumeLastSource: resume != nil)))
                                    }
                                    .focused($focus, equals: .play)
                                    if let k = extra?.trailerYouTube { trailerButton(k) }
                                }
                            }
                            if let trailerNote { Text(trailerNote).foregroundStyle(.secondary) }
                            if let x = extra { DetailExtras(info: x, isSeries: isSeries) }
                        } else {
                            Text("Keine IMDb-ID gefunden – Streams nicht abrufbar.").foregroundStyle(.secondary)
                            if overview.isEmpty { FocusAnchor(kind: .back) }   // N6
                        }
                    }
                    .padding(80)
                }
                .onChange(of: scrollRequest) {
                    guard let id = scrollTarget else { return }
                    proxy.scrollTo(id)
                }
            }
            .defaultFocus($focus, .play)
            // Die App-Akzentfarbe (RootView .tint) färbte Knöpfe und Text-Knöpfe hier flächig: normale tvOS-Knöpfe.
            .tint(Color?.none)
        }
        .onAppear {
            if loaded, openedPlayback {
                openedPlayback = false
                returnFocusToken += 1
            }
            if appeared == nil { appeared = Date() }
            // Quellen schon im Cache (z. B. zweiter Besuch): Technik-Plaketten im ersten Bild, nicht erst nach dem Laden.
            let id = imdb ?? (item.id.hasPrefix("tt") ? item.id : nil)
            if best == nil, !isSeries, let id, let b = detailQuality(id) {
                best = b
                logFirstBadges("Technik aus Cache")
            }
        }
        .task {
            guard !loaded else { return }
            let opened = appeared ?? Date()
            imdb = await model.imdbID(for: item)
            if let imdb {
                if !isSeries, best == nil, let b = detailQuality(imdb) {
                    best = b
                    logFirstBadges("Technik aus Cache")
                } else if !isSeries, best == nil {
                    // Quellen sofort und parallel holen (Technik-Plaketten; AppModel cached sie für die Quellenliste).
                    let id = imdb
                    Task {
                        let list = await model.streams(type: "movie", id: id)
                        best = detailQuality(id)
                        if !techBadges.isEmpty { logFirstBadges("Technik") }
                        RemoteLog.info("detail", "Plaketten nach \(Int(Date().timeIntervalSince(opened) * 1000)) ms (\(list.count) Quellen)")
                    }
                }
                async let r = model.ratings(imdb: imdb, series: isSeries)
                meta = await model.meta(type: isSeries ? "series" : "movie", imdb: imdb)
                extra = await model.localized(imdb: imdb, series: isSeries)
                certification = extra?.certification
                if certification != nil { logFirstBadges("Altersfreigabe") }
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
                if focus == nil || focus == .overview { await applyFocus(playbackFocusTarget(), reason: "Eintritt") }
            }
            await translateSeason()
        }
        .task(id: returnFocusToken) {
            guard returnFocusToken > 0 else { return }
            // Erst nach dem Zurück-Übergang: sonst setzt die Rückkehr-Animation den Fokus wieder auf den alten Knopf.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let target = playbackFocusTarget()
            if let s = target.season, s != season { season = s }
            await applyFocus(target, reason: "nach dem Player")
        }
        .onChange(of: season) { Task { await translateSeason() } }
        .onDisappear { trailerTask?.cancel() }
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

    /// Fokusziel (§3.2): Film „Abspielen“; Serie die nächste ungesehene Folge nach der zuletzt gespielten
    /// (PlayerCore `EpisodeFocus`), auch in der nächsten Staffel. Die erste Folge einer Staffel trägt `.play`.
    private func playbackFocusTarget() -> FocusTarget {
        guard isSeries, let imdb else { return FocusTarget() }
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
        guard let s = t.season else { return "Abspielen" }
        return "Staffel \(s), \(t.video ?? "erste Folge")"
    }

    /// Einmal je Seite: Zeit vom Erscheinen bis zur ersten sichtbaren Plakette und deren Quelle.
    private func logFirstBadges(_ source: String) {
        guard !badgesLogged else { return }
        badgesLogged = true
        let ms = appeared.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        RemoteLog.info("detail", "erste Plaketten nach \(ms) ms (\(source))")
    }

    private var overview: String { meta?.description ?? item.description ?? "" }

    /// Welle E-a: eine Zeile, höchstens 5 (Auflösung, DV/HDR, Atmos, Ton + Kanäle, Remux).
    private var techBadges: [QualityBadge] {
        best.map { QualityBadges.detailRow($0, settings: model.profile.appearance.badges) } ?? []
    }

    /// Technik-Werte aus dem Quellen-Cache (keine Abfrage); nil ohne gecachte Quellen.
    private func detailQuality(_ id: String) -> DetailQuality? {
        model.cachedStreams(id: id).flatMap { DetailQuality.from($0.map(\.stream)) }
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
            Text("Keine Folgen gefunden.").foregroundStyle(.secondary)
            if overview.isEmpty && extra?.trailerYouTube == nil { FocusAnchor(kind: .back) }   // N6
        } else {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(seasons, id: \.self) { s in
                        Button("Staffel \(s)") { season = s }
                            .background(s == season ? Color.white.opacity(0.2) : .clear, in: Capsule())
                    }
                }
            }
            let eps = (meta?.videos ?? []).filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(eps) { v in
                    let isFirst = v.id == eps.first?.id
                    Button {
                        let e = v.episode ?? 0
                        openedPlayback = true
                        navigate(.streams(PlayRequest(type: "series", id: "\(imdb):\(season):\(e)", title: "\(item.name) S\(season)E\(e)",
                                                      item: progressItem(imdb), season: season, episode: e,
                                                      episodes: EpisodeRef.list(from: meta?.videos ?? []))))
                    } label: {
                        HStack(spacing: 24) {
                            let spoiler = model.profile.sources.blurUnwatchedStills && !model.progress.isWatched("\(imdb):\(season):\(v.episode ?? 0)")
                            RemoteImage(url: v.thumbnail, maxPixels: 560, blur: spoiler ? SpoilerStill.blurRadius : 0)
                                .frame(width: 280, height: 158).clipped()
                                .spoilerMark(spoiler)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(v.episode ?? 0). \(v.name ?? v.title ?? "Folge")").font(.headline)
                                    let key = "\(imdb):\(season):\(v.episode ?? 0)"
                                    if model.progress.isWatched(key) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                    else if let p = model.progress.entries[key], p.position >= 60 {
                                        ProgressView(value: p.fraction).frame(width: 120)
                                    }
                                }
                                if let o = v.overview { Text(o).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                    }
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

/// Dezente Fokusanzeige für Text-Knöpfe (`.buttonStyle(.plain)`).
struct FocusHighlight<C: View>: View {
    @Environment(\.isFocused) private var focused
    @ViewBuilder let content: C
    var body: some View {
        content
            .padding(.horizontal, 16).padding(.vertical, 10)
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
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.title2.bold())
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

    var body: some View {
        // Welle E-b: Addon-Name nur, wenn die Liste mehrere Addons mischt (sonst steht er schon im Text des Addons).
        let showAddon = Set(streams.map(\.addon)).count > 1
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
                    ForEach(streams, id: \.stream.id) { entry in
                        Button {
                            fallbacks = 0; AutoNextState.userInput($autoNext); autoNext.ask = nil
                            PlaybackStability.shared.timing.markTap()
                            playing = entry.stream
                        } label: {
                            StreamRow(addon: showAddon ? entry.addon : nil, stream: entry.stream).opacity(failed.contains(entry.stream.id) ? 0.4 : 1)
                                .recentlyFailedMark(entry.stream, title: (current ?? request).id)
                        }
                        .focused($focusedStream, equals: entry.stream.id)
                        .id(entry.stream.id)
                    }
                } header: {
                    Text(current?.title ?? request.title).font(.title2.bold()).foregroundStyle(.primary)
                        .textCase(nil).lineLimit(2).padding(.bottom, 10)
                }
            }
            .task(id: focusRequest) {
                guard let r = focusRequest else { return }
                // Nach dem Player: erst nach dem Schließen des Vollbilds (sonst setzt tvOS den Fokus auf die gedrückte Zeile).
                try? await Task.sleep(for: .milliseconds(r.delayMs))
                for attempt in 1...4 {
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(r.id)
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
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
        .background(Color(white: 0.07).ignoresSafeArea())
        .streamSearchPartials(id: request.id, loading: loading && current == nil) { streams = model.orderedStreams($0) }
        .task {
            streams = model.orderedStreams(request.resumeLastSource && playing == nil
                ? await model.streamsForAutoplay(type: request.type, id: request.id)
                : await model.streams(type: request.type, id: request.id))
            loading = false
            if request.type == "series", request.episodes.isEmpty, let base = request.id.split(separator: ":").first {
                // Aus Weiterschauen: Folgenliste nachladen, damit die nächste Folge automatisch kommt.
                let eps = EpisodeRef.list(from: await model.meta(type: "series", imdb: String(base))?.videos ?? [])
                if current == nil { var r = request; r.episodes = eps; current = r }
            }
            if request.resumeLastSource, playing == nil, let last = model.progress.lastSource(for: request.id) {
                // nie eine zuletzt fehlgeschlagene; Welle E-b: Wahl immer in kluger Ordnung, egal wie die Liste sortiert ist
                let pick = Self.resumeCandidate(last, in: model.autoOrderedStreams(streams), title: request.id)
                if let s = pick.stream {
                    RemoteLog.info("player", "Weiterschauen mit letzter Quelle: \(s.name ?? "") \(s.label.prefix(60))")
                    playing = s
                } else {
                    nextNote = pick.note
                    RemoteLog.info("player", "Letzte Quelle nicht gefunden (\(last.fingerprint.prefix(60)))")
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
        .onChange(of: playing) { old, s in
            if s == nil, let old { focusAfterPlayer(old) }
            guard let s else { return }
            // Addon aus der Liste, sonst das bei der nächsten Folge gemerkte (sonst „Addon nicht installiert“ beim Neuauflösen).
            model.rememberSource(current ?? request, stream: s,
                                 addon: streams.first { $0.stream.id == s.id }?.addon ?? autoNext.addons[s.id] ?? "")
        }
        .fullScreenCover(item: $playing) { s in
            if let u = s.url.flatMap(URL.init(string:)) { PlayerScreen(url: u, request: current ?? request,
                                                                             headers: s.behaviorHints?.proxyHeaders?.request ?? [:],
                                                                             onEnded: { ended(s, autoplay: $0) }, onFallback: { fallback(from: s, reason: $0) },
                                                                             onUserInput: { AutoNextState.userInput($autoNext) },
                                                                             holdsUpNext: autoNext.promptDue(model.profile),
                                                                             onSourceVerdict: { [id = (current ?? request).id] in PlaybackStability.shared.apply($0, stream: s, title: id) },
                                                                             releaseName: s.behaviorHints?.filename).environmentObject(model) }
        }
        .modifier(StillWatchingAlert(state: $autoNext, note: $nextNote) { startNext($0.next, after: $0.stream, auto: false) })
    }
}

extension StreamListView {
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
        let ids = streams.map(\.stream.id)
        guard focusedStream == nil || focusedStream == ids.first else { return }
        let last = model.progress.lastSource(for: (current ?? request).id)?.match(in: streams)?.id
        guard let id = SourceFocus.entry(ids: ids, lastPlayed: last, isPlayable: focusPlayable) else { return }
        requestFocus(id, in: ids, reason: last == id ? "Eintritt, zuletzt gespielt" : "Eintritt", delayMs: 0)
    }

    /// Player geschlossen (§3.2): nach einem Fehler die nächste Quelle unter der gescheiterten, sonst die gespielte.
    func focusAfterPlayer(_ played: StreamItem) {
        let failure = lastFailure == played.id
        lastFailure = nil
        let ids = streams.map(\.stream.id)
        guard let id = SourceFocus.afterPlayer(ids: ids, played: played.id, failed: failure, isPlayable: focusPlayable)
        else { return }
        requestFocus(id, in: ids, reason: failure ? "nach Fehler" : "nach dem Player", delayMs: 400)
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

    /// Quelle versagt → nächste noch nicht gescheiterte Quelle darunter, höchstens 3 automatische Wechsel.
    func fallback(from s: StreamItem, reason: String) {
        failed.insert(s.id)
        lastFailure = s.id
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
    let token = UUID()
}

/// Welle E-b: Zeile wie vom Formatter des Addons gebaut: links `name`, rechts `description`/`title`, Umbrüche und
/// Emoji bleiben, je höchstens 4 Zeilen (StreamRowText). App-Plaketten nur kompakt („sofort“, Größe) und nur, wenn
/// der Addon-Text sie nicht schon zeigt (StreamListBadges). Addon-Name nur bei gemischter Liste (`addon` nicht nil).
struct StreamRow: View {
    @EnvironmentObject var model: AppModel
    let addon: String?
    let stream: StreamItem
    /// Fokussierte Zeile ist weiß: dann dunkle Schrift und dunkles Glas, sonst weiß auf hellem Glas.
    @Environment(\.isFocused) private var focused
    var body: some View {
        let text = StreamRowText(stream)
        let badges = StreamListBadges.badges(stream, mode: model.profile.sources.appBadges, settings: model.profile.appearance.badges)
        let primary = focused ? Color.black : Color.white
        let secondary = focused ? Color.black.opacity(0.65) : Color.white.opacity(0.65)
        HStack(alignment: .top, spacing: 28) {
            if !text.name.isEmpty {
                Text(text.name).font(.caption.bold()).foregroundStyle(primary)
                    .lineLimit(StreamRowText.maxLines).frame(width: 330, alignment: .leading)
            }
            Text(text.body).font(.caption).foregroundStyle(secondary)
                .lineLimit(StreamRowText.maxLines).frame(maxWidth: .infinity, alignment: .leading)
            if !badges.isEmpty || addon != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if !badges.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(badges) { QualityBadgeView(badge: $0, height: 38, surface: focused ? .light : .dark) }
                        }
                    }
                    if let addon { Text(addon).font(.caption2).foregroundStyle(secondary).lineLimit(1) }
                }
                .fixedSize()
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    init(_ text: String, _ color: Color) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 4).background(color.opacity(0.7), in: Capsule())
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

/// Infozeile der Detailseite: Technik als Glas-Plaketten, Bewertungen mit Rahmen (Zwei-Stil-Regel).
/// Alle Plaketten einzeilig, gleich hoch; passt die Zeile nicht, bricht sie um (FlowLayout), statt abzuschneiden.
struct InfoBadges: View {
    /// Welle E-a: schon nach der Bewertungsauswahl gefiltert (`AppModel.ratingBadges`).
    let ratings: [RatingBadge]
    /// Höchstens 5 (`QualityBadges.detailRow`); die Altersfreigabe steht in der Textzeile darüber.
    let tech: [QualityBadge]
    static let height: CGFloat = 44

    var body: some View {
        let rated = ratings
        // Immer vorhandener Platzhalter hält die Zeilenhöhe, auch bevor die erste Plakette kommt.
        ZStack(alignment: .leading) {
          Color.clear.frame(height: Self.height)
          if !rated.isEmpty || !tech.isEmpty {
            FlowLayout(spacing: 14, lineSpacing: 14) {
                // Neutrales Glas wie in der Quellenliste (Task 8); Bewertungen behalten ihre Markenfarben.
                // Technik zuerst: sie passt immer in die erste Zeile, nur gewählte Bewertungen können umbrechen.
                ForEach(tech) { QualityBadgeView(badge: $0, height: Self.height, surface: .dark) }
                ForEach(rated) { b in
                    HStack(spacing: 6) {
                        RatingIconLabel(source: b.source) { Text(b.label).foregroundStyle(labelColor(b.source)) }
                        Text(b.text)
                    }
                    .modifier(BadgeShape())
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(scoreColor(b.score).opacity(0.8), lineWidth: 2))
                }
            }
            .frame(maxWidth: 1400, alignment: .leading)
            .transition(.opacity)
          }
        }
    }

    /// Einheitliche Schrift, Höhe und Innenabstand; nie umbrechen.
    struct BadgeShape: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .frame(height: InfoBadges.height)
        }
    }

    private func labelColor(_ source: String) -> Color {
        switch source {
        case "imdb": Color(red: 0.96, green: 0.77, blue: 0.09)
        case "letterboxd": Color(red: 0.0, green: 0.88, blue: 0.33)
        case "trakt": Color(red: 0.93, green: 0.11, blue: 0.14)
        case "tmdb": Color(red: 0.0, green: 0.82, blue: 0.85)
        default: .white
        }
    }

    private func scoreColor(_ s: Double) -> Color {
        s >= 70 ? .green : s >= 50 ? .yellow : .red
    }
}

/// Besetzung, ähnliche Titel und „Über“ (alles aus dem einen TMDB-Abruf).
struct DetailExtras: View {
    @Environment(\.navigate) private var navigate
    let info: LocalizedMeta
    let isSeries: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            if !info.cast.isEmpty {
                Text("Besetzung").font(.title3.bold())
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 36) {
                        ForEach(info.cast) { c in
                            Button { navigate(.person(id: c.id, name: c.name)) } label: {
                                VStack(spacing: 10) {
                                    RemoteImage(url: c.photo, maxPixels: 370)
                                        .frame(width: 180, height: 180).clipShape(Circle())
                                        .overlay { if c.photo == nil { Text(String(c.name.prefix(1))).font(.title) } }
                                    Text(c.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    if let r = c.role { Text(r).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                .frame(width: 220).padding(.vertical, 14)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
            if !info.recommendations.isEmpty {
                Text("Ähnliche Titel").font(.title3.bold())
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 40) {
                        ForEach(info.recommendations) { m in
                            NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m))
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
            let rows = aboutRows
            if !rows.isEmpty {
                Text("Über").font(.title3.bold())
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

/// Zeilen-Umbruch-Layout: Kinder in ihrer Idealgröße nebeneinander, bei Platzmangel in die nächste Zeile.
struct FlowLayout: Layout {
    var spacing: CGFloat = 14
    var lineSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { r in r.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, r.count - 1)) }.max() ?? 0
        let height = rows.map { r in r.map(\.size.height).max() ?? 0 }.reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            let h = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for e in row {
                subviews[e.index].place(at: CGPoint(x: x, y: y + (h - e.size.height) / 2), proposal: ProposedViewSize(e.size))
                x += e.size.width + spacing
            }
            y += h + lineSpacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].isEmpty, x + spacing + size.width > width {
                rows.append([]); x = 0
            }
            x += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].append((i, size))
        }
        return rows.filter { !$0.isEmpty }
    }
}
