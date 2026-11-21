import SwiftUI
import PlayerCore

/// Ordner einer Collection: eine Reihe pro Quelle.
struct FolderView: View {
    let folder: Folder
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 50) {
                Text(folder.title).font(.largeTitle.bold()).padding(.leading, 60)
                ForEach(folder.sources) { s in
                    HomeRowView(row: HomeRow(content: .list(s), style: .poster), onActivate: { $0 }, onLongPress: {})
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
            HomeRowView(row: HomeRow(content: .collection(id: collectionID)), onActivate: { $0 }, onLongPress: {})
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
    @State private var tech: [String] = []
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
    /// Startfokus auf der Hauptaktion, nicht auf der (darüber liegenden) Beschreibung.
    enum Focus: Hashable { case play, episode(String), overview }
    @FocusState private var focus: Focus?

    private var isSeries: Bool { item.type == "series" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: meta?.background ?? item.background, maxPixels: 1920).ignoresSafeArea().overlay(Color.black.opacity(0.55))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    if let logo = meta?.logo {
                        RemoteImage(url: logo, maxPixels: 1400, fit: true).frame(maxWidth: 700, maxHeight: 200, alignment: .leading)
                    } else {
                        Text(item.name).font(.system(size: 70, weight: .heavy))
                    }
                    Text([meta?.releaseInfo ?? item.releaseInfo, meta?.runtime, meta?.genres?.prefix(3).joined(separator: ", ")]
                        .compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    InfoBadges(ratings: ratings, tech: tech, certification: certification ?? ratings?.certification)
                    if let t = extra?.tagline { Text(t).italic().foregroundStyle(.secondary) }
                    if !overview.isEmpty {
                        // Kurz halten; Klick zeigt den ganzen Text.
                        Button { showFullText = true } label: { FocusHighlight { Text(overview).font(.callout).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading) } }
                            .buttonStyle(.plain)
                            .focused($focus, equals: .overview)
                            .frame(maxWidth: 1100, alignment: .leading)
                    }

                    if loading {
                        ProgressView()
                    } else if let imdb {
                        if isSeries {
                            if let k = extra?.trailerYouTube { trailerButton(k) }
                            episodes(imdb)
                        } else {
                            let resume = model.progress.resumePosition(for: imdb)
                            HStack(spacing: 30) {
                                Button(resume.map { "▶ Fortsetzen ab \(timeText($0))" } ?? "▶ Abspielen") {
                                    navigate(.streams(PlayRequest(type: "movie", id: imdb, title: item.name, item: progressItem(imdb), runtimeMinutes: parseRuntimeMinutes(meta?.runtime),
                                                                  resumeLastSource: resume != nil)))
                                }
                                .focused($focus, equals: .play)
                                if let k = extra?.trailerYouTube { trailerButton(k) }
                            }
                        }
                        if let trailerNote { Text(trailerNote).foregroundStyle(.secondary) }
                        if let x = extra { DetailExtras(info: x, isSeries: isSeries) }
                    } else {
                        Text("Keine IMDb-ID gefunden – Streams nicht abrufbar.").foregroundStyle(.secondary)
                    }
                }
                .padding(80)
            }
            .defaultFocus($focus, .play)
            // Die App-Akzentfarbe (RootView .tint) färbte Knöpfe und Text-Knöpfe hier flächig: normale tvOS-Knöpfe.
            .tint(Color?.none)
        }
        .task {
            guard !loaded else { return }
            let opened = Date()
            imdb = await model.imdbID(for: item)
            if let imdb {
                if !isSeries {
                    // Quellen sofort und parallel holen (Technik-Plaketten; AppModel cached sie für die Quellenliste).
                    let id = imdb
                    Task {
                        let list = await model.streams(type: "movie", id: id)
                        tech = TechBadges.summary(list.map(\.stream))
                        RemoteLog.info("detail", "Plaketten nach \(Int(Date().timeIntervalSince(opened) * 1000)) ms (\(list.count) Quellen)")
                    }
                }
                async let r = model.ratings(imdb: imdb, series: isSeries)
                meta = await model.meta(type: isSeries ? "series" : "movie", imdb: imdb)
                extra = await model.localized(imdb: imdb, series: isSeries)
                certification = extra?.certification
                ratings = await r
            }
            if Task.isCancelled { return }   // Seite verlassen: beim nächsten Erscheinen vollständig neu laden
            season = imdb.flatMap { model.progress.latest(forItem: $0)?.season } ?? seasons.first ?? 1
            loading = false
            loaded = true
            // Während des Ladens war die Beschreibung das einzige fokussierbare Element: Fokus auf die Hauptaktion holen.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if !didInitialFocus {
                didInitialFocus = true
                if focus == nil || focus == .overview { focus = .play }
            }
            await translateSeason()
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
                             trailerNote = "Trailer nicht verfügbar"
                             RemoteLog.info("trailer", "\(t.key) Wiedergabe fehlgeschlagen: \(reason)")
                         },
                         isTrailer: true, remoteHLS: t.stream.isHLS)
                .environmentObject(model)
        }
    }

    private var overview: String { meta?.description ?? item.description ?? "" }

    private func trailerButton(_ key: String) -> some View {
        Button(trailerLoading ? "Trailer wird geladen …" : "🎬 Trailer") {
            // Doppeldruck: laufende Auflösung behalten, sonst ginge der Abbruch-Griff verloren.
            guard !trailerLoading else { return }
            trailerTask = Task { await playTrailer(key) }
        }
    }

    /// Trailer im eigenen Player (YouTube-Adresse über Innertube auflösen); kein Wechsel in die YouTube-App.
    private func playTrailer(_ key: String) async {
        guard !trailerLoading else { return }
        trailerLoading = true
        trailerNote = nil
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
    private func progressItem(_ imdb: String) -> MetaPreview {
        MetaPreview(id: imdb, type: item.type, name: item.name, poster: meta?.poster ?? item.poster,
                    background: meta?.background ?? item.background, logo: meta?.logo, description: meta?.description ?? item.description,
                    releaseInfo: meta?.releaseInfo ?? item.releaseInfo, imdbRating: item.imdbRating)
    }

    private var seasons: [Int] {
        Array(Set((meta?.videos ?? []).compactMap(\.season).filter { $0 > 0 })).sorted()
    }

    @ViewBuilder private func episodes(_ imdb: String) -> some View {
        if seasons.isEmpty {
            Text("Keine Folgen gefunden.").foregroundStyle(.secondary)
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
                        navigate(.streams(PlayRequest(type: "series", id: "\(imdb):\(season):\(e)", title: "\(item.name) S\(season)E\(e)",
                                                      item: progressItem(imdb), season: season, episode: e,
                                                      episodes: EpisodeRef.list(from: meta?.videos ?? []))))
                    } label: {
                        HStack(spacing: 24) {
                            RemoteImage(url: v.thumbnail, maxPixels: 560).frame(width: 280, height: 158).clipped()
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

    var body: some View {
        // Titel als Listenkopf (scrollt mit weg) statt navigationTitle: der große tvOS-Titel lag über den Zeilen.
        List {
            Section {
                if let nextNote { Text(nextNote).foregroundStyle(.secondary) }
                if loading { ProgressView("Quellen werden geladen …") }
                if !loading && streams.isEmpty {
                    Text(model.profile.addons.isEmpty ? "Kein Addon installiert (Einstellungen → Addons)." : "Keine abspielbaren Quellen.")
                }
                ForEach(streams, id: \.stream.id) { entry in
                    Button { fallbacks = 0; playing = entry.stream } label: {
                        StreamRow(addon: entry.addon, stream: entry.stream).opacity(failed.contains(entry.stream.id) ? 0.4 : 1)
                    }
                }
            } header: {
                Text(current?.title ?? request.title).font(.title2.bold()).foregroundStyle(.primary)
                    .textCase(nil).lineLimit(2).padding(.bottom, 10)
            }
        }
        .listStyle(.grouped)
        .task {
            streams = await model.streams(type: request.type, id: request.id)
            loading = false
            if request.type == "series", request.episodes.isEmpty, let base = request.id.split(separator: ":").first {
                // Aus Weiterschauen: Folgenliste nachladen, damit die nächste Folge automatisch kommt.
                let eps = EpisodeRef.list(from: await model.meta(type: "series", imdb: String(base))?.videos ?? [])
                if current == nil { var r = request; r.episodes = eps; current = r }
            }
            if request.resumeLastSource, playing == nil, let last = model.progress.lastSource(for: request.id) {
                if let s = last.match(in: streams) {
                    RemoteLog.info("player", "Weiterschauen mit letzter Quelle: \(s.name ?? "") \(s.label.prefix(60))")
                    playing = s
                } else {
                    nextNote = "Letzte Quelle nicht mehr verfügbar – bitte wählen."
                    RemoteLog.info("player", "Letzte Quelle nicht gefunden (\(last.fingerprint.prefix(60)))")
                }
            }
        }
        .onChange(of: playing) { _, s in
            guard let s else { return }
            model.rememberSource(current ?? request, stream: s, addon: streams.first { $0.stream.id == s.id }?.addon ?? "")
        }
        .fullScreenCover(item: $playing) { s in
            if let u = s.url.flatMap(URL.init(string:)) { PlayerScreen(url: u, request: current ?? request,
                                                                             headers: s.behaviorHints?.proxyHeaders?.request ?? [:],
                                                                             onEnded: { ended(s, autoplay: $0) }, onFallback: { fallback(from: s, reason: $0) }).environmentObject(model) }
        }
    }
}

extension StreamListView {
    /// Nächste Quelle: zuerst gecachte (⚡) unterhalb, dann gecachte oberhalb, zuletzt unbekannte; nie sicher ungecachte (🎫/⏳).
    func fallbackCandidate(after i: Int, in list: [StreamItem]) -> StreamItem? {
        let order = Array(list[(i + 1)...]) + Array(list[..<i])
        let open = order.filter { !failed.contains($0.id) && $0.url != nil }
        return open.first { StreamTraits.parse($0).cached == true } ?? open.first { StreamTraits.parse($0).cached == nil }
    }

    /// Quelle versagt → nächste noch nicht gescheiterte Quelle darunter, höchstens 3 automatische Wechsel.
    func fallback(from s: StreamItem, reason: String) {
        failed.insert(s.id)
        playing = nil
        let list = streams.map(\.stream)
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
            playing = next
        }
    }

    /// Folge zu Ende → nächste Folge mit gleicher bingeGroup starten (Spec §6 Player: nächste Folge).
    func ended(_ stream: StreamItem, autoplay: Bool = true) {
        playing = nil
        guard autoplay, model.profile.autoplayNext, let next = (current ?? request).nextRequest else { return }
        nextNote = "Nächste Folge wird gesucht: \(next.title) …"
        Task {
            let list = await model.streams(type: next.type, id: next.id).map(\.stream)
            guard let s = nextEpisodeStream(list, bingeGroup: stream.behaviorHints?.bingeGroup) else {
                nextNote = "Keine Quelle für \(next.title) gefunden."; return
            }
            nextNote = nil
            current = next
            try? await Task.sleep(for: .milliseconds(800))
            playing = s
        }
    }
}

struct StreamRow: View {
    let addon: String
    let stream: StreamItem
    var body: some View {
        let t = StreamTraits.parse(stream)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let r = t.resolution { Badge(r, .blue) }
                ForEach(t.hdr, id: \.self) { Badge($0, $0 == "DV" ? .purple : .orange) }
                if let s = t.source { Badge(s, s == "REMUX" ? .indigo : .gray) }
                if let c = t.videoCodec { Badge(t.tenBit ? "\(c) 10-bit" : c, .gray) }
                ForEach(t.audio, id: \.self) { Badge($0, .gray) }
                if let ch = t.channels { Badge(ch, .gray) }
                ForEach(t.languages, id: \.self) { Badge($0.uppercased(), .teal) }
                if let s = t.sizeBytes { Badge(ByteCountFormatter.string(fromByteCount: s, countStyle: .file), .gray) }
                if t.cached == true { Badge("⚡ sofort", .green) } else if t.cached == false { Badge("lädt erst", .red) }
                Spacer()
                Text(addon).font(.caption).foregroundStyle(.secondary)
            }
            Text(stream.label.isEmpty ? (stream.name ?? "") : stream.label).font(.caption).lineLimit(2).foregroundStyle(.secondary)
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

/// Infozeile der Detailseite: Technik gefüllt, Bewertungen/Freigabe mit Rahmen (Zwei-Stil-Regel nach Swiftfin).
/// Alle Plaketten einzeilig, gleich hoch; passt die Zeile nicht, bricht sie um (FlowLayout), statt abzuschneiden.
struct InfoBadges: View {
    let ratings: ExternalRatings?
    let tech: [String]
    var certification: String?
    static let height: CGFloat = 44

    var body: some View {
        let rated = ratings.map(MDBList.badges) ?? []
        // Immer vorhandener Platzhalter hält die Zeilenhöhe, auch bevor die erste Plakette kommt.
        ZStack(alignment: .leading) {
          Color.clear.frame(height: Self.height)
          if !rated.isEmpty || !tech.isEmpty || certification != nil {
            FlowLayout(spacing: 14, lineSpacing: 14) {
                ForEach(tech, id: \.self) { t in
                    Text(t).foregroundStyle(.black)
                        .modifier(BadgeShape())
                        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                }
                if let c = certification {
                    Text(c)
                        .modifier(BadgeShape())
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.6), lineWidth: 2))
                }
                ForEach(rated) { b in
                    HStack(spacing: 6) {
                        Text(b.label).foregroundStyle(labelColor(b.source))
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
        let p = s.split(separator: "-")
        return p.count == 3 ? "\(p[2]).\(p[1]).\(p[0])" : s
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
