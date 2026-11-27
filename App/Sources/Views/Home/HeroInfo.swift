import SwiftUI
import PlayerCore

/// Zusatzdaten der Info-Ebene (Logo, Laufzeit, FSK, Genre, Text, Bewertungen).
struct HeroDetails {
    var logo: String?
    var runtime: String?
    var certification: String?
    var overview: String?
    var ratings: ExternalRatings?
    /// Welle E-a: IMDb-Wertung aus den Metadaten (Addon/Cinemeta), geht MDBList vor.
    var imdbRating: String?
    /// Task 5.2: first genre of the metadata (meta line of `heroInfo` standard and detailed).
    var genre: String?
}

/// Je Titel einmal laden (die Quellen sind ohnehin gecacht, das spart die Wege dorthin).
/// Task 3.1: bound to the profile scope (profile, language, addon set) and bounded; a late load of an older scope
/// is not stored.
@MainActor enum HeroDetailsCache {
    static var all = ScopedCache<String, HeroDetails>(limit: 200)
}

/// Task 5.2: how one hero info is drawn (level parts, title mode, sizes); built by the hero variant.
struct HeroInfoStyle: Equatable {
    /// Parts below the logo (`HeroInfoParts.of` / `.collapsed`).
    var parts: HeroInfoParts
    /// `heroTitle`: logo from the metadata (else the name) or always the name.
    var title: LookHeroTitle
    var logoHeight: CGFloat
    var spacing: CGFloat
    /// Width of the overview and the title text.
    var width: CGFloat
    /// Lines of the overview: 2, or 1 in the collapsed info when the two lines leave the tallest row no room
    /// (`HeroInfoCollapse.Layout.overviewLines`, user decision 26.11.).
    var overviewLines: Int = 2
}

/// Logo (sonst Name) und je nach `heroInfo` Metazeile Jahr · Laufzeit · FSK · Genre, Bewertungen, Beschreibung in
/// 2 Zeilen und Plaketten.
struct HeroInfo: View {
    @Environment(AppModel.self) var model
    let item: MetaPreview
    let style: HeroInfoStyle
    @State private var details: HeroDetails?
    @State private var detailsID: String?

    private var current: HeroDetails? { detailsID == item.id ? details : nil }

    var body: some View {
        let d = current
        VStack(alignment: .leading, spacing: style.spacing) {
            HeroTitle(item: item, logo: d?.logo ?? item.logo, loaded: d != nil, style: style)
            if style.parts.meta {
                // Meta ist Text, keine Plakette (§4.5): „2018 · 1 h 37 min · FSK 0 · Drama“.
                MetaLine(parts: [item.releaseInfo, d?.runtime, d?.certification, d?.genre])
                    .frame(height: HeroMetrics.metaLineHeight, alignment: .leading)
            }
            if style.parts.ratings {
                InfoBadges(ratings: d.map { model.ratingBadges(imdbRating: $0.imdbRating, mdblist: $0.ratings) } ?? [],
                           tech: [])
                    .frame(height: InfoBadges.height, alignment: .leading)
            }
            if style.parts.overview {
                Text(d?.overview ?? item.description ?? "").font(.callout).lineLimit(style.overviewLines)
                    .frame(maxWidth: style.width, alignment: .leading)
            }
            if style.parts.badges {
                HeroQualityBadges(item: item)
            }
        }
        // Build 6 (redraw): one flattened layer, one shadow. Without the group SwiftUI draws the shadow for every
        // part of the stack (logo, meta line, badges, overview) as its own offscreen blur, again on every frame of
        // the 0.3 s hero crossfade. Same look: the parts do not overlap, so their shadows only meet in the gaps.
        .compositingGroup()
        .shadow(color: .black.opacity(0.6), radius: 8)
        .animation(.easeInOut(duration: 0.3), value: item.id)
        .animation(.easeInOut(duration: 0.3), value: detailsID)
        // Task 3.1: a new profile scope (language, addon set) loads the details again.
        .task(id: "\(item.id)|\(model.scopes.current.epoch)") { await load() }
    }

    private func load() async {
        let id = item.id, scope = model.scopes.current
        if let c = HeroDetailsCache.all.value(for: id, in: scope) { details = c; detailsID = id; return }
        guard let imdb = await model.imdbID(for: item) else {
            guard !Task.isCancelled, model.scopeStillCurrent(scope, "Hero \(id)") else { return }
            HeroDetailsCache.all.store(HeroDetails(), for: id, from: scope, current: model.scopes.current)
            details = HeroDetails(); detailsID = id
            return
        }
        let series = item.type == "series"
        async let r = model.ratings(imdb: imdb, series: series)
        let meta = await model.meta(type: series ? "series" : "movie", imdb: imdb)
        let loc = await model.localized(imdb: imdb, series: series)
        let d = HeroDetails(logo: meta?.logo ?? loc?.logo, runtime: Self.runtimeText(meta?.runtime),
                            certification: loc?.certification, overview: meta?.description ?? loc?.overview,
                            ratings: await r, imdbRating: meta?.imdbRating, genre: meta?.genres?.first)
        guard !Task.isCancelled, model.scopeStillCurrent(scope, "Hero \(id)") else { return }
        // Welle E-a Runde 2: Addon-Antwort noch offen (3-s-Grenze) → nicht merken, nächster Besuch holt sie aus dem Cache.
        if !model.addonMetaPending(type: series ? "series" : "movie", imdb: imdb) {
            HeroDetailsCache.all.store(d, for: id, from: scope, current: model.scopes.current)
        }
        details = d; detailsID = id
    }

    /// "102 min" → "1 h 42 min".
    static func runtimeText(_ s: String?) -> String? {
        guard let m = parseRuntimeMinutes(s).map({ Int($0.rounded()) }), m > 0 else { return nil }
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
    }
}

/// Task 5.2 (`heroTitle`): the title logo from the metadata, without one the name as `display`; `text` always the
/// name. While the details of an IMDb/TMDB title load, the name waits (no flash before its logo arrives).
private struct HeroTitle: View {
    let item: MetaPreview
    let logo: String?
    let loaded: Bool
    let style: HeroInfoStyle

    private var showsName: Bool {
        style.title == .text || loaded || !item.id.hasPrefix("tt") && !item.id.hasPrefix("tmdb:")
    }

    var body: some View {
        Group {
            if style.title == .logo, let logo {
                RemoteImage(url: logo, maxPixels: 1200, fit: true)
                    .frame(maxWidth: 640, maxHeight: style.logoHeight, alignment: .bottomLeading)
            } else if showsName {
                Text(item.name).textRole(.display).lineLimit(2).minimumScaleFactor(0.6)
                    .frame(maxWidth: style.width, alignment: .bottomLeading)
            }
        }
        .frame(height: style.logoHeight, alignment: .bottomLeading)
    }
}

/// Task 5.2 (`heroInfo` ausführlich): quality badges of the shown title (4K, Dolby Vision/HDR, Atmos) from the
/// source cache. Waits for the batched `stored` pass like the poster badges. Integration build 5 (user decision
/// 26.11.): drawn in the theme's badge style (`detail.badgeStyle`, `logos` = wordmark logos), the shown badge types
/// from `appearance.badges`.
private struct HeroQualityBadges: View {
    @Environment(AppModel.self) var model
    @Environment(\.theme) private var theme
    let item: MetaPreview
    @State private var best: BestQuality?
    @State private var bestID: String?

    var body: some View {
        let shown = bestID == item.id ? best : nil
        let list = shown.map { QualityBadges.poster($0, settings: model.profile.appearance.badges.drawn(as: theme.badgeStyle)) } ?? []
        InfoBadges(ratings: [], tech: list)
            .frame(height: InfoBadges.height, alignment: .leading)
            .task(id: item.id) {
                best = QualityBadgeCache.shared.best(for: item, model: model)
                bestID = item.id
            }
            .onReceive(QualityBadgeCache.shared.stored) { ids in
                guard let id = QualityBadgeCache.shared.match(ids, for: item, model: model) else { return }
                best = QualityBadgeCache.shared.best(id: id, model: model)
                bestID = item.id
            }
    }
}
