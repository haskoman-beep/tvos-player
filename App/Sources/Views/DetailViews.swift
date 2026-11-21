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
                    InfoBadges(ratings: ratings, tech: tech)
                    Text(meta?.description ?? item.description ?? "").frame(maxWidth: 1100, alignment: .leading)

                    if loading {
                        ProgressView()
                    } else if let imdb {
                        if isSeries { episodes(imdb) } else {
                            let resume = model.progress.resumePosition(for: imdb)
                            Button(resume.map { "▶ Fortsetzen ab \(timeText($0))" } ?? "▶ Abspielen") {
                                navigate(.streams(PlayRequest(type: "movie", id: imdb, title: item.name, item: progressItem(imdb), runtimeMinutes: parseRuntimeMinutes(meta?.runtime),
                                                              resumeLastSource: resume != nil)))
                            }
                        }
                    } else {
                        Text("Keine IMDb-ID gefunden – Streams nicht abrufbar.").foregroundStyle(.secondary)
                    }
                }
                .padding(80)
            }
        }
        .task {
            imdb = await model.imdbID(for: item)
            if let imdb {
                async let r = model.ratings(imdb: imdb, series: isSeries)
                meta = await model.meta(type: isSeries ? "series" : "movie", imdb: imdb)
                ratings = await r
                if !isSeries {
                    let id = imdb
                    Task { tech = TechBadges.summary(await model.streams(type: "movie", id: id).map(\.stream)) }
                }
            }
            season = imdb.flatMap { model.progress.latest(forItem: $0)?.season } ?? seasons.first ?? 1
            loading = false
        }
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
                }
            }
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
        List {
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
        }
        .navigationTitle(request.title)
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
                                                                             onEnded: { ended(s) }, onFallback: { fallback(from: s, reason: $0) }).environmentObject(model) }
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
    func ended(_ stream: StreamItem) {
        playing = nil
        guard model.profile.autoplayNext, let next = (current ?? request).nextRequest else { return }
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
struct InfoBadges: View {
    let ratings: ExternalRatings?
    let tech: [String]

    var body: some View {
        let rated = ratings.map(MDBList.badges) ?? []
        if !rated.isEmpty || !tech.isEmpty || ratings?.certification != nil {
            HStack(spacing: 14) {
                ForEach(tech, id: \.self) { t in
                    Text(t).font(.caption.weight(.bold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                }
                if let c = ratings?.certification {
                    Text(c).font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.6), lineWidth: 2))
                }
                ForEach(rated) { b in
                    HStack(spacing: 6) {
                        Text(b.label).font(.caption.weight(.heavy)).foregroundStyle(labelColor(b.source))
                        Text(b.text).font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(scoreColor(b.score).opacity(0.8), lineWidth: 2))
                }
            }
            .transition(.opacity)
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
