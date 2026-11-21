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
                            Button("▶ Abspielen") { navigate(.streams(type: "movie", id: imdb, title: item.name)) }
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
            season = seasons.first ?? 1
            loading = false
        }
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
                        navigate(.streams(type: "series", id: "\(imdb):\(season):\(v.episode ?? 0)", title: "\(item.name) S\(season)E\(v.episode ?? 0)"))
                    } label: {
                        HStack(spacing: 24) {
                            RemoteImage(url: v.thumbnail).frame(width: 280, height: 158).clipped()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(v.episode ?? 0). \(v.name ?? v.title ?? "Folge")").font(.headline)
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
    let type: String
    let id: String
    let title: String
    @State private var streams: [(addon: String, stream: StreamItem)] = []
    @State private var loading = true
    @State private var playing: StreamItem?

    var body: some View {
        List {
            if loading { ProgressView("Quellen werden geladen …") }
            if !loading && streams.isEmpty {
                Text(model.profile.addons.isEmpty ? "Kein Addon installiert (Einstellungen → Addons)." : "Keine abspielbaren Quellen.")
            }
            ForEach(streams, id: \.stream.id) { entry in
                Button { playing = entry.stream } label: { StreamRow(addon: entry.addon, stream: entry.stream) }
            }
        }
        .navigationTitle(title)
        .task {
            streams = await model.streams(type: type, id: id)
            loading = false
        }
        .fullScreenCover(item: $playing) { s in
            if let u = s.url.flatMap(URL.init(string:)) { PlayerScreen(url: u, title: title).environmentObject(model) }
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
