import SwiftUI
import UIKit
import PlayerCore

// Startseiten-Hero (Spec §2.2, §7a.1/§7a.2): gemeinsame Hintergrund- und Info-Ebene hinter dem ScrollView.
// Die Info zeigt die aktuelle Folie oder, solange der Fokus in den Reihen liegt, die fokussierte Kachel
// (nach 350 ms Ruhe). Die Diashow pausiert, solange der Fokus in den Reihen liegt.

/// Fokus der Startseite. Kacheln melden sich über `set`, die Hero-Knöpfe über `leaveRows`.
@MainActor @Observable
final class HomeFocus {
    /// Zuletzt (entprellt) fokussierte Kachel.
    private(set) var item: MetaPreview?
    /// Fokus liegt in den Reihen (nicht auf den Hero-Knöpfen).
    private(set) var inRows = false
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// Kachel hat den Fokus: Diashow sofort anhalten, Hintergrund erst nach 350 ms Ruhe wechseln.
    /// Ein neuer Fokus bricht die Wartezeit ab; pro Ruhepause höchstens eine Log-Zeile.
    /// `onRest` läuft nach derselben Ruhezeit (Quellen vorladen, Task 7), nicht bei vorzeitigem Fokuswechsel.
    func set(_ m: MetaPreview, onRest: (() -> Void)? = nil) {
        if !inRows { inRows = true }
        pending?.cancel()
        pending = nil
        guard m.id != item?.id else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.item = m
            self.pending = nil
            RemoteLog.info("hero", "Fokus-Hintergrund \(m.id)")
            onRest?()
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
    /// Erste Ladung abgeschlossen (leer = kein Hero).
    private(set) var loaded = false

    var current: MetaPreview? { items.isEmpty ? nil : items[min(index, items.count - 1)] }

    func set(_ new: [MetaPreview]) {
        if new.map(\.id) != items.map(\.id) { items = new; index = 0 }
        loaded = true
    }

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

    private var shown: MetaPreview? {
        focus.inRows ? (focus.item ?? slides.current) : slides.current
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeroBackdrop(url: shown.flatMap { $0.background ?? $0.poster })
            if let shown {
                HeroInfo(item: shown)
                    .padding(.leading, Theme.Space.edge).padding(.top, Theme.Space.s)
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
            // Speichercache-Treffer nach dem Freigeben (Rückkehr): sofort, ohne Überblendung.
            if shown == nil, let hit = ImagePipeline.shared.cachedImage(u, target: target) {
                shown = Shown(url: s, image: hit)
                return
            }
            guard let img = await ImagePipeline.shared.image(u, target: target), !Task.isCancelled else { return }
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
@MainActor enum HeroDetailsCache {
    static var all: [String: HeroDetails] = [:]
}

/// Logo (sonst Name), Metazeile Jahr · Laufzeit · FSK, Bewertungen, Beschreibung in 2 Zeilen.
struct HeroInfo: View {
    @EnvironmentObject var model: AppModel
    let item: MetaPreview
    @State private var details: HeroDetails?
    @State private var detailsID: String?

    private var current: HeroDetails? { detailsID == item.id ? details : nil }

    var body: some View {
        let d = current
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Group {
                if let logo = d?.logo ?? item.logo {
                    RemoteImage(url: logo, maxPixels: 1200, fit: true)
                        .frame(maxWidth: 640, maxHeight: HeroMetrics.logoHeight, alignment: .bottomLeading)
                } else if d != nil || !item.id.hasPrefix("tt") && !item.id.hasPrefix("tmdb:") {
                    Text(item.name).textRole(.display).lineLimit(2).minimumScaleFactor(0.6)
                        .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .bottomLeading)
                }
            }
            .frame(height: HeroMetrics.logoHeight, alignment: .bottomLeading)
            // Meta ist Text, keine Plakette (§4.5): „2018 · 1 h 37 min · FSK 0“.
            MetaLine(parts: [item.releaseInfo, d?.runtime, d?.certification])
                .frame(height: 30, alignment: .leading)
            InfoBadges(ratings: d.map { model.ratingBadges(imdbRating: $0.imdbRating, mdblist: $0.ratings) } ?? [], tech: [])
                .frame(height: InfoBadges.height, alignment: .leading)
            Text(d?.overview ?? item.description ?? "").font(.callout).lineLimit(2)
                .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.6), radius: 8)
        .animation(.easeInOut(duration: 0.3), value: item.id)
        .animation(.easeInOut(duration: 0.3), value: detailsID)
        .task(id: item.id) { await load() }
    }

    private func load() async {
        let id = item.id
        if let c = HeroDetailsCache.all[id] { details = c; detailsID = id; return }
        guard let imdb = await model.imdbID(for: item) else {
            guard !Task.isCancelled else { return }
            HeroDetailsCache.all[id] = HeroDetails()
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
        guard !Task.isCancelled else { return }
        // Welle E-a Runde 2: Addon-Antwort noch offen (3-s-Grenze) → nicht merken, nächster Besuch holt sie aus dem Cache.
        if !model.addonMetaPending(type: series ? "series" : "movie", imdb: imdb) { HeroDetailsCache.all[id] = d }
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
            Button { play() } label: {
                Label(starting ? "Wird geladen …" : "Abspielen", systemImage: "play.fill")
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
        var heldSince: ContinuousClock.Instant?
        while !Task.isCancelled, !LaunchFocus.done, ContinuousClock.now < deadline {
            if focus.inRows { LaunchFocus.finish("Fokus in den Reihen"); return }
            switch field {
            case nil:
                if heldSince != nil { RemoteLog.info("fokus", "Start: Fokus vor dem Halten verloren, zurückholen") }
                heldSince = nil
                field = .play
            case .play:
                let since = heldSince ?? ContinuousClock.now
                heldSince = since
                if ContinuousClock.now - since >= LaunchFocus.hold { LaunchFocus.finish("Abspielen hält den Fokus"); return }
            case .details:
                heldSince = nil
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !LaunchFocus.done, ContinuousClock.now >= deadline { LaunchFocus.finish("Startfenster vorbei") }
    }

    private func play() {
        guard !starting, let m = slides.current else { return }
        starting = true
        Task {
            let r = await model.quickPlayRequest(for: m)
            starting = false
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
    private(set) static var done = false

    static func finish(_ reason: String) {
        guard !done else { return }
        done = true
        RemoteLog.info("fokus", "Start: \(reason)")
    }
}

extension ImageTarget {
    /// Vollbild-Hintergrund (1920×1080 Punkte × Bildschirmfaktor; auf 4K also 3840 px breit), Welle C-b #16.
    static func fullScreen(scale: CGFloat) -> ImageTarget {
        ImageTarget(points: 1920, 1080, scale: Double(scale), fit: false) ?? ImageTarget(width: 1920, height: 1280, fit: false)
    }
}
