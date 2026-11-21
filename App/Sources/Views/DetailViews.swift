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

    private var isSeries: Bool { item.type == "series" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: meta?.background ?? item.background).ignoresSafeArea().overlay(Color.black.opacity(0.55))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    if let logo = meta?.logo {
                        RemoteImage(url: logo).scaledToFit().frame(maxWidth: 700, maxHeight: 200, alignment: .leading)
                    } else {
                        Text(item.name).font(.system(size: 70, weight: .heavy))
                    }
                    Text([meta?.releaseInfo ?? item.releaseInfo, meta?.runtime, meta?.genres?.prefix(3).joined(separator: ", ")]
                        .compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    Text(meta?.description ?? item.description ?? "").frame(maxWidth: 1100, alignment: .leading)

                    if loading {
                        ProgressView()
                    } else if let imdb {
                        if isSeries { episodes(imdb) } else {
                            let resume = model.progress.resumePosition(for: imdb)
                            Button(resume.map { "▶ Fortsetzen ab \(timeText($0))" } ?? "▶ Abspielen") {
                                navigate(.streams(PlayRequest(type: "movie", id: imdb, title: item.name, item: progressItem(imdb))))
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
            if let imdb { meta = await model.meta(type: isSeries ? "series" : "movie", imdb: imdb) }
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
                            RemoteImage(url: v.thumbnail).frame(width: 280, height: 158).clipped()
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

    var body: some View {
        List {
            if let nextNote { Text(nextNote).foregroundStyle(.secondary) }
            if loading { ProgressView("Quellen werden geladen …") }
            if !loading && streams.isEmpty {
                Text(model.profile.addons.isEmpty ? "Kein Addon installiert (Einstellungen → Addons)." : "Keine abspielbaren Quellen.")
            }
            ForEach(streams, id: \.stream.id) { entry in
                Button { playing = entry.stream } label: { StreamRow(addon: entry.addon, stream: entry.stream) }
            }
        }
        .navigationTitle(request.title)
        .task {
            streams = await model.streams(type: request.type, id: request.id)
            loading = false
        }
        .fullScreenCover(item: $playing) { s in
            if let u = s.url.flatMap(URL.init(string:)) { PlayerScreen(url: u, request: current ?? request, onEnded: { ended(s) }).environmentObject(model) }
        }
    }
}

extension StreamListView {
    /// Folge zu Ende → nächste Folge mit gleicher bingeGroup starten (Spec §6 Player: nächste Folge).
    func ended(_ stream: StreamItem) {
        playing = nil
        guard let next = (current ?? request).nextRequest else { return }
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
                ForEach(t.audio, id: \.self) { Badge($0, .gray) }
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
