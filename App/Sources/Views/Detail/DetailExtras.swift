import SwiftUI
import Combine
import PlayerCore

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
                                .tileMenu(m)   // Wave L
                        }
                    }
                    // Wave F-k: same room for the card lift as the home rows (poster at factor 1), at least 44.
                    .padding(.vertical, similarPadding)
                }
                .scrollClipDisabled()
                // Wave F-k R1: these tiles prefetch their sources too (badge); log line per page, after 2 s of rest.
                .environment(\.prefetchRow, PrefetchRow(key: "similar", title: "Ähnliche Titel"))
                .task(id: info.recommendations.map(\.id)) { noteSimilarBadges() }
                .onReceive(QualityBadgeCache.shared.stored) { ids in
                    // Wave F-k R2 (m5): only when one of these titles got its sources (P3: batched IDs).
                    guard info.recommendations.contains(where: { QualityBadgeCache.shared.match(ids, for: $0, model: model) != nil }) else { return }
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
