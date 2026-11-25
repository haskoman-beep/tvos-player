import SwiftUI
import UIKit
import PlayerCore

// Startseiten-Hero (Spec §2.2, §7a.1/§7a.2): gemeinsame Hintergrund- und Info-Ebene hinter dem ScrollView.
// Die Info zeigt die aktuelle Folie oder, solange der Fokus in den Reihen liegt, die fokussierte Kachel
// (nach 350 ms Ruhe; Quellen vorladen erst nach 1 s Ruhe, P3). Die Diashow pausiert, solange der Fokus in den Reihen liegt.

/// Fokus der Startseite. Kacheln melden sich über `set`, die Hero-Knöpfe über `leaveRows`.
@MainActor @Observable
final class HomeFocus {
    /// Zuletzt (entprellt) fokussierte Kachel.
    private(set) var item: MetaPreview?
    /// Fokus liegt in den Reihen (nicht auf den Hero-Knöpfen).
    private(set) var inRows = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Task 4.1a (F-A-12): rows that hold the focus, and the rest check after the last one lost it.
    @ObservationIgnored private var focusedRows: Set<UUID> = []
    @ObservationIgnored private var outside: Task<Void, Never>?
    /// P2 fix round: the page is covered (detail page, player, other tab); no rest check ends `inRows` meanwhile.
    @ObservationIgnored private var suspended = false

    /// Kachel hat den Fokus: Diashow sofort anhalten, Hintergrund erst nach 350 ms Ruhe wechseln.
    /// Ein neuer Fokus bricht die Wartezeit ab; pro Ruhepause höchstens eine Log-Zeile.
    /// Build 4 follow-up 2 (P3): `onRest` (Quellen vorladen, Task 7) runs only after `FocusRest.prefetchMilliseconds`
    /// (1 s) of rest: after the backdrop crossfade (350 ms + 0.6 s), and not for the short stops while browsing (the
    /// device log showed stops 0.5–0.8 s apart, each starting a search). Also when the backdrop already shows this tile
    /// (focus came back before its prefetch). A new focus or leaving the rows cancels both steps.
    /// Intended (P3 review M4): every return to the shown tile requests again after 1 s, so `keepStream` also promotes
    /// an entry that was prefetched already; harmless, do not skip the shown tile here.
    func set(_ m: MetaPreview, onRest: (() -> Void)? = nil) {
        if !inRows { inRows = true }
        pending?.cancel()
        pending = nil
        let stop = FocusRest.stop(alreadyShown: m.id == item?.id)
        guard stop.backdropWait != nil || onRest != nil else { return }
        pending = Task { [weak self] in
            if let wait = stop.backdropWait {
                try? await Task.sleep(for: .milliseconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.item = m
                RemoteLog.info("hero", "Fokus-Hintergrund \(m.id)")
            }
            guard let onRest else { self?.pending = nil; return }
            try? await Task.sleep(for: .milliseconds(stop.prefetchWait))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            onRest()
        }
    }

    /// Task 4.1a (F-A-12): a row gained or lost the focus. When no row holds it for 300 ms (sidebar, top bar, the
    /// button below the rows), the show runs again and the backdrop goes back to the slide.
    /// P2 fix round: any focus inside a row (card, placeholder, status tile, restore on return) counts as "in the
    /// rows", so the hero info collapses there too, not only once a loaded card calls `set`.
    func row(_ id: UUID, focused: Bool) {
        if focused {
            focusedRows.insert(id)
            outside?.cancel()
            outside = nil
            if !inRows { inRows = true }
            return
        }
        focusedRows.remove(id)
        checkOutside()
    }

    /// P2 fix round: the home page was covered (`onDisappear`). Rows report losing the focus as they go; the rest
    /// check waits for `resume`, so the page comes back as it was left (no expand behind the detail page).
    func suspend() {
        suspended = true
        outside?.cancel()
        outside = nil
    }

    /// P2 fix round: the home page is visible again; rows that still hold the focus report it on appear and
    /// cancel the check started here.
    func resume() {
        suspended = false
        checkOutside()
    }

    private func checkOutside() {
        guard !suspended, focusedRows.isEmpty, inRows, outside == nil else { return }
        outside = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.outside = nil
            guard self.focusedRows.isEmpty, self.inRows else { return }
            RemoteLog.info("hero", "Fokus außerhalb der Reihen: Diashow läuft weiter")
            self.leaveRows()
        }
    }

    /// Fokus ist auf den Hero-Knöpfen: Diashow läuft wieder.
    func leaveRows() {
        pending?.cancel()
        pending = nil
        if inRows { inRows = false }
    }
}

/// Folien der Diashow (höchstens 8, aus der Hero-Quellreihe).
@MainActor @Observable
final class HeroSlides {
    private(set) var items: [MetaPreview] = []
    private(set) var index = 0
    /// Erste Ladung abgeschlossen.
    private(set) var loaded = false
    /// Task 4.1a (F-A-4): last load failed and there is nothing to show (status tile instead of slides).
    private(set) var failed = false
    /// Raised by the status tile: loads the hero source again.
    var retry = 0

    var current: MetaPreview? { items.isEmpty ? nil : items[min(index, items.count - 1)] }

    /// Phase of the hero frame: slides, still loading, failed or empty (status tile; the layout stays).
    var phase: HomeRowPhase { HomeRowPhase(loaded: loaded, failed: failed, count: items.count) }

    /// New slides; same IDs keep the show where it is (A-B-6: a background refresh does not restart it). A failed
    /// load keeps slides already shown.
    func set(_ new: [MetaPreview], failed loadFailed: Bool = false) {
        if loadFailed, new.isEmpty, !items.isEmpty { loaded = true; return }
        if new.map(\.rowKey) != items.map(\.rowKey) { items = new; index = 0 }
        failed = loadFailed && new.isEmpty
        loaded = true
    }

    static let emptyText = "Die Hero-Quelle hat gerade keine Einträge."

    func advance() {
        guard items.count > 1 else { return }
        index = (index + 1) % items.count
    }

    var next: MetaPreview? { items.count > 1 ? items[(index + 1) % items.count] : nil }
}

enum HeroMetrics {
    /// Abstand des ScrollView (Knopfzeile + Reihen) von oben; darüber steht die Info-Ebene.
    static let listTop: CGFloat = 470
    static let logoHeight: CGFloat = 140
    /// Height of the meta line ("2018 · 1 h 37 min · FSK 0").
    static let metaLineHeight: CGFloat = 30
    /// P2 (follow-up 2): smallest logo (or title) of the collapsed info; with less room the floor of the collapsed
    /// list top wins and the tallest row no longer fits whole (logged as "passt nicht").
    static let compactLogoMin: CGFloat = 80
    /// P2: the collapsed info as `HeroLayer` places it: top inset, logo, gap, meta line (PlayerCore `HeroInfoCollapse`).
    static let compactInfo = HeroInfoCollapse.CompactInfo(topInset: Theme.Space.s, logoMax: logoHeight,
                                                          logoMin: compactLogoMin, spacing: Theme.Space.m,
                                                          metaLine: metaLineHeight)
}

extension Route {
    /// Anzeige-Eintrag für die Hero-Info, wenn diese Kachel fokussiert ist.
    var heroPreview: MetaPreview {
        switch self {
        case .detail(let m): m
        case .streams(let r): r.item
        case .folder(let f): MetaPreview(id: "folder:\(f.id)", type: "folder", name: f.title,
                                         background: f.backdrop ?? f.coverImage, logo: f.logo)
        case .collection(let id): MetaPreview(id: "collection:\(id)", type: "folder", name: id)
        case .person(let id, let name): MetaPreview(id: "person:\(id)", type: "person", name: name)
        }
    }
}

/// Hintergrund + Info des angezeigten Titels; steuert den Diashow-Takt.
struct HeroLayer: View {
    @Environment(HomeFocus.self) private var focus
    @Environment(\.displayScale) private var displayScale
    let slides: HeroSlides
    /// P2 (follow-up 2): collapsed info while the focus is in the rows.
    let collapse: HeroCollapse

    private var shown: MetaPreview? {
        focus.inRows ? (focus.item ?? slides.current) : slides.current
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeroBackdrop(url: shown.flatMap { $0.background ?? $0.poster })
            if let shown {
                HeroInfo(item: shown, compactLogo: collapse.collapsed ? collapse.compactLogo : nil)
                    .padding(.leading, Theme.Space.edge).padding(.top, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let text = slides.phase.statusText(empty: HeroSlides.emptyText) {
                // Task 4.1a (F-A-4): the hero frame stays; the reason stands where the info would be.
                Text(text).textRole(.rowDetail)
                    .padding(.leading, Theme.Space.edge).padding(.top, Theme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Diashow: alle 10 s, nur solange der Fokus nicht in den Reihen liegt; startet nach jeder Rückkehr neu.
        .task(id: "\(focus.inRows)|\(slides.items.count)") {
            guard !focus.inRows, slides.items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                slides.advance()
            }
        }
        .onChange(of: slides.index, initial: true) {
            // Nächste Folie schon laden, damit die Überblendung ohne Lücke läuft.
            guard let n = slides.next, let s = n.background ?? n.poster, let u = URL(string: s) else { return }
            Task { await ImagePipeline.shared.prefetch([u], target: .fullScreen(scale: displayScale)) }
        }
    }
}

/// Vollbild-Hintergrund; das neue Bild wird erst geladen und dann in 0,6 s übergeblendet.
struct HeroBackdrop: View {
    let url: String?
    @Environment(\.displayScale) private var displayScale
    @State private var shown: Shown?

    private struct Shown: Equatable {
        let url: String
        let image: UIImage
    }

    var body: some View {
        ZStack {
            Color.black
            if let shown {
                Color.clear
                    .overlay { Image(uiImage: shown.image).resizable().aspectRatio(contentMode: .fill) }
                    .clipped()
                    .id(shown.url)
                    .transition(.opacity)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.35), location: 0.45),
                                   .init(color: .clear, location: 0.7)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.6), location: 0.6),
                                   .init(color: .black.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: url) {
            guard let s = url, let u = URL(string: s) else {
                withAnimation(.easeInOut(duration: 0.6)) { shown = nil }
                return
            }
            if shown?.url == s { return }
            let target = ImageTarget.fullScreen(scale: displayScale)
            let started = ContinuousClock.now
            // Speichercache-Treffer nach dem Freigeben (Rückkehr): sofort, ohne Überblendung.
            if shown == nil, let hit = ImagePipeline.shared.cachedImage(u, target: target) {
                shown = Shown(url: s, image: hit)
                PictureArrivalLog.backdrop.note(hit, fromMemory: true, waitMs: 0, fades: false)   // P3
                return
            }
            // P3: from memory or loaded (disk/network + decode), and how long until the crossfade starts.
            let inMemory = ImagePipeline.shared.cachedImage(u, target: target, count: false) != nil
            guard let img = await ImagePipeline.shared.image(u, target: target), !Task.isCancelled else { return }
            let waited = Metric.ms(started.duration(to: ContinuousClock.now))
            PictureArrivalLog.backdrop.note(img, fromMemory: inMemory, waitMs: waited, fades: true)
            withAnimation(.easeInOut(duration: 0.6)) { shown = Shown(url: s, image: img) }
        }
        // Verdeckt (Detailseite, Wiedergabe): Vollbild-Bitmap nicht außerhalb des Cache-Budgets halten.
        // Beim Wiederkommen startet `.task(id:)` neu und holt es aus dem Speicher- oder Plattencache.
        .onDisappear {
            guard let img = shown?.image, ImagePipeline.cost(img) >= RemoteImage.releaseBytes else { return }
            shown = nil
        }
    }
}

/// Zusatzdaten der Info-Ebene (Logo, Laufzeit, FSK, Text, Bewertungen).
struct HeroDetails {
    var logo: String?
    var runtime: String?
    var certification: String?
    var overview: String?
    var ratings: ExternalRatings?
    /// Welle E-a: IMDb-Wertung aus den Metadaten (Addon/Cinemeta), geht MDBList vor.
    var imdbRating: String?
}

/// Je Titel einmal laden (die Quellen sind ohnehin gecacht, das spart die Wege dorthin).
/// Task 3.1: bound to the profile scope (profile, language, addon set) and bounded; a late load of an older scope
/// is not stored.
@MainActor enum HeroDetailsCache {
    static var all = ScopedCache<String, HeroDetails>(limit: 200)
}

/// Logo (sonst Name), Metazeile Jahr · Laufzeit · FSK, Bewertungen, Beschreibung in 2 Zeilen.
struct HeroInfo: View {
    @EnvironmentObject var model: AppModel
    let item: MetaPreview
    /// P2 (follow-up 2): collapsed info (logo or title of this height + meta line); nil = full info.
    var compactLogo: CGFloat? = nil
    @State private var details: HeroDetails?
    @State private var detailsID: String?

    private var current: HeroDetails? { detailsID == item.id ? details : nil }
    private var logoHeight: CGFloat { compactLogo ?? HeroMetrics.logoHeight }

    var body: some View {
        let d = current
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Group {
                if let logo = d?.logo ?? item.logo {
                    RemoteImage(url: logo, maxPixels: 1200, fit: true)
                        .frame(maxWidth: 640, maxHeight: logoHeight, alignment: .bottomLeading)
                } else if d != nil || !item.id.hasPrefix("tt") && !item.id.hasPrefix("tmdb:") {
                    Text(item.name).textRole(.display).lineLimit(2).minimumScaleFactor(0.6)
                        .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .bottomLeading)
                }
            }
            .frame(height: logoHeight, alignment: .bottomLeading)
            // Meta ist Text, keine Plakette (§4.5): „2018 · 1 h 37 min · FSK 0“.
            MetaLine(parts: [item.releaseInfo, d?.runtime, d?.certification])
                .frame(height: HeroMetrics.metaLineHeight, alignment: .leading)
            // P2: the collapsed info drops ratings and overview (the list moves up into their room).
            if compactLogo == nil {
                InfoBadges(ratings: d.map { model.ratingBadges(imdbRating: $0.imdbRating, mdblist: $0.ratings) } ?? [], tech: [])
                    .frame(height: InfoBadges.height, alignment: .leading)
                Text(d?.overview ?? item.description ?? "").font(.callout).lineLimit(2)
                    .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            }
        }
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
                            ratings: await r, imdbRating: meta?.imdbRating)
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

/// Erste Zeile im ScrollView: [▶ Abspielen] [Details] und die Diashow-Punkte.
/// Fokus von den Reihen nach oben landet immer auf „Abspielen“ (eigene Fokus-Sektion mit Vorgabe).
struct HeroButtons: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    @Environment(HomeFocus.self) private var focus
    let slides: HeroSlides
    /// Wave F-j: the button row gains (true) or loses (false) focus; it is the top edge of the home page.
    var onFocusChange: ((Bool) -> Void)? = nil
    @FocusState private var field: Field?
    @State private var starting = false

    enum Field: Hashable { case play, details }

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Button { slides.phase == .failed ? retryHero() : play() } label: {
                // Task 4.1a (F-A-4): failed hero source → the play button is the status tile "erneut laden".
                if slides.phase == .failed {
                    Label("Erneut laden", systemImage: "arrow.clockwise")
                } else {
                    Label(starting ? "Wird geladen …" : "Abspielen", systemImage: "play.fill")
                }
            }
            .focused($field, equals: .play)
            .buttonStyle(ThemeActionButtonStyle())
            Button { if let m = slides.current { navigate(.detail(m)) } } label: {
                Label("Details", systemImage: "info.circle")
            }
            .focused($field, equals: .details)
            .buttonStyle(ThemeActionButtonStyle())
            Spacer(minLength: Theme.Space.xl)
            if slides.items.count > 1 {
                HStack(spacing: Theme.Space.s) {
                    ForEach(slides.items.indices, id: \.self) { i in
                        Circle().fill(.white.opacity(i == slides.index ? 1 : 0.35))
                            .frame(width: 12, height: 12)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: slides.index)
            }
        }
        .padding(.horizontal, Theme.Space.edge)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus($field, .play, priority: .userInitiated)
        // Die App-Akzentfarbe (RootView .tint) färbte beide Knöpfe blau; Welle F-i: Token-Knöpfe (ThemeActionButtonStyle).
        .tint(Color?.none)
        .onChange(of: field) { _, f in
            if f != nil { focus.leaveRows() }
        }
        .onChange(of: field != nil) { _, f in onFocusChange?(f) }
        // Back from a pushed page with the focus state unchanged: report it again.
        .onAppear { if field != nil { onFocusChange?(true) } }
        .onDisappear { onFocusChange?(false) }
        .task { await claimLaunchFocus() }
    }

    /// Kaltstart: „Abspielen“ holt sich den ersten Fokus selbst (siehe `LaunchFocus`). Verliert es ihn, bevor er
    /// 300 ms gehalten hat, war das die Seitenleiste → zurückholen. Der Anspruch endet nur, wenn „Abspielen“ den Fokus
    /// 300 ms hält, der Fokus in den Reihen war oder das Startfenster vorbei ist. Ein Wegdrücken danach ist gewollt:
    /// die Knopfzeile greift nie mehr ein.
    private func claimLaunchFocus() async {
        guard !LaunchFocus.done else { return }
        let deadline = LaunchFocus.deadline ?? ContinuousClock.now + LaunchFocus.window
        LaunchFocus.deadline = deadline
        if LaunchFocus.shownAt == nil { LaunchFocus.shownAt = ContinuousClock.now }
        var heldSince: ContinuousClock.Instant?
        while !Task.isCancelled, !LaunchFocus.done, ContinuousClock.now < deadline {
            if focus.inRows { LaunchFocus.finish("Fokus in den Reihen", way: "reihen"); return }
            switch field {
            case nil:
                if heldSince != nil { RemoteLog.info("fokus", "Start: Fokus vor dem Halten verloren, zurückholen") }
                heldSince = nil
                field = .play
            case .play:
                let since = heldSince ?? ContinuousClock.now
                heldSince = since
                if LaunchFocus.firstPlayFocus == nil { LaunchFocus.firstPlayFocus = since }
                if ContinuousClock.now - since >= LaunchFocus.hold {
                    LaunchFocus.finish("Abspielen hält den Fokus", way: "hero", usableAt: since); return
                }
            case .details:
                heldSince = nil
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Fenster vorbei: bedienbar seit dem ersten Fokus auf „Abspielen“, sonst seit die Knopfzeile erschien.
        if !LaunchFocus.done, ContinuousClock.now >= deadline {
            LaunchFocus.finish("Startfenster vorbei", way: "fenster",
                               usableAt: LaunchFocus.firstPlayFocus ?? LaunchFocus.shownAt ?? ContinuousClock.now)
        }
    }

    private func retryHero() {
        RemoteLog.info("hero", "Hero-Quelle erneut laden")
        slides.retry += 1
    }

    private func play() {
        guard !starting, let m = slides.current else { return }
        starting = true
        let start = VisiblePage.stamp
        Task {
            let r = await model.quickPlayRequest(for: m)
            starting = false
            // F-A-1: the user opened another page or tab while waiting → no late jump into the source list.
            guard VisiblePage.mayNavigate(from: start, "hero Abspielen \(m.name)") else { return }
            guard let r else {
                model.lastError = "Abspielen nicht möglich: keine IMDb-ID für \(m.name)."
                return
            }
            RemoteLog.info("hero", "Abspielen \(m.name) → \(r.id)\(r.resumeLastSource ? " (letzte Quelle)" : "")")
            navigate(.streams(r))
        }
    }
}

/// Erster Fokus nach dem Kaltstart. Die Seitenleiste (`.sidebarAdaptable`, tvOS 18) nimmt sich beim ersten
/// Fokusdurchlauf den Fokus und klappt auf; `.defaultFocus` der Startseite greift dabei nicht.
/// Gilt einmal pro App-Lauf; das Fenster beginnt mit dem ersten Erscheinen der Knopfzeile und überdauert
/// einen Neuaufbau der Startseite in dieser Zeit.
@MainActor enum LaunchFocus {
    static let window: Duration = .milliseconds(2500)
    /// So lange muss „Abspielen“ den Fokus halten, dann gilt der Start als erledigt.
    static let hold: Duration = .milliseconds(300)
    static var deadline: ContinuousClock.Instant?
    /// Task 1.8: erstes Erscheinen der Knopfzeile und erster Fokus auf „Abspielen“ (für `start.usable`).
    static var shownAt: ContinuousClock.Instant?
    static var firstPlayFocus: ContinuousClock.Instant?
    private(set) static var done = false

    static func finish(_ reason: String, way: String, usableAt: ContinuousClock.Instant = ContinuousClock.now) {
        guard !done else { return }
        done = true
        RemoteLog.info("fokus", "Start: \(reason)")
        RemoteLog.startUsable(way, at: usableAt)   // Task 1.8: once per start (other screens: RootView, HomeView)
    }
}

extension ImageTarget {
    /// Vollbild-Hintergrund (1920×1080 Punkte × Bildschirmfaktor; auf 4K also 3840 px breit), Welle C-b #16.
    static func fullScreen(scale: CGFloat) -> ImageTarget {
        ImageTarget(points: 1920, 1080, scale: Double(scale), fit: false) ?? ImageTarget(width: 1920, height: 1280, fit: false)
    }
}
