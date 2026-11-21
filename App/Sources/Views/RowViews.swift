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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if row.style != .hero {
                Text(title).font(.title3.bold()).padding(.leading, 60)
            }
            content
                .disabled(!interactive)
        }
        .task(id: row.content.key + (row.content == .list(.continueWatching) ? "\(model.progress.entries.count)-\(model.progress.continueWatching().first?.updated.timeIntervalSince1970 ?? 0)" : "")) {
            guard case .list(let s) = row.content else { return }
            items = await model.items(s); loaded = true
        }
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
                Text(row.content == .list(.continueWatching) ? "Noch nichts angefangen." : model.tmdb == nil ? "TMDB-Key fehlt (Einstellungen)" : "Keine Einträge")
                    .foregroundStyle(.secondary).padding(.leading, 60).frame(height: 120)
            } else {
                Strip {
                    ForEach(Array((row.style == .top10 ? Array(items.prefix(10)) : items).enumerated()), id: \.element.id) { i, m in
                        card(route(for: m)) {
                            switch row.style {
                            case .hero: HeroCard(item: m)
                            case .landscape: LandscapeCard(item: m)
                            case .top10: Top10Card(item: m, rank: i + 1)
                            default: PosterCard(item: m)
                            }
                        }
                    }
                }
            }
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
    static let defaultValue: (Route) -> Void = { _ in }
}

extension EnvironmentValues {
    var navigate: (Route) -> Void {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}

struct Strip<C: View>: View {
    @ViewBuilder let content: C
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 40) { content }
                .padding(.horizontal, 60).padding(.vertical, 30)
        }
    }
}

struct RemoteImage: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let img = phase.image { img.resizable().scaledToFill() } else { Color.white.opacity(0.08) }
        }
    }
}

struct PosterCard: View {
    let item: MetaPreview
    var body: some View {
        RemoteImage(url: item.poster)
            .frame(width: 240, height: 360).clipped()
            .overlay(alignment: .bottomLeading) {
                if item.poster == nil { Text(item.name).font(.caption).padding(10) }
            }
    }
}

struct LandscapeCard: View {
    let item: MetaPreview
    var body: some View {
        RemoteImage(url: item.background ?? item.poster)
            .frame(width: 440, height: 248).clipped()
            .overlay(alignment: .bottomLeading) {
                Text(item.name).font(.headline).shadow(radius: 6).padding(14)
            }
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
    var body: some View {
        HStack(alignment: .bottom, spacing: -30) {
            Text("\(rank)").font(.system(size: 220, weight: .black)).foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 8)
            PosterCard(item: item)
        }
    }
}

struct FolderTile: View {
    let folder: Folder
    let logoStyle: Bool
    var body: some View {
        if logoStyle {
            ZStack {
                Color.white.opacity(0.08)
                if let l = folder.logo { RemoteImage(url: l).scaledToFit().padding(30) } else { Text(folder.title).font(.headline) }
            }
            .frame(width: 320, height: 180)
        } else {
            RemoteImage(url: folder.coverImage ?? folder.backdrop)
                .frame(width: 440, height: 248).clipped()
                .overlay(alignment: .bottomLeading) {
                    if folder.coverImage == nil { Text(folder.title).font(.headline).padding(14) }
                }
        }
    }
}
