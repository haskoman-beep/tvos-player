import SwiftUI
import UIKit
import PlayerCore

// Startseiten-Hero (Spec §2.2, §7a.1/§7a.2): gemeinsame Hintergrund- und Info-Ebene hinter dem ScrollView.
// Die Info zeigt die aktuelle Folie oder, solange der Fokus in den Reihen liegt, die fokussierte Kachel
// (b5r: nach mindestens 800 ms Ruhe, im Drück-Takt länger als der Takt, `BackdropRest`; Quellen vorladen danach, P3).
// Die Diashow pausiert, solange der Fokus in den Reihen liegt.

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
    /// Task 5.2 (`backdropFollowsFocus`): the backdrop and info follow the resting card; set by `HomeView` from the
    /// look. Off: the slide stays (the show pauses while the focus is in the rows), the prefetch still runs.
    @ObservationIgnored var followsBackdrop = false
    /// Task 5.2: at most one backdrop request per rest (PlayerCore `HeroBackdropFollow`).
    @ObservationIgnored private var follow = HeroBackdropFollow()
    /// Build 5 device test 1 (item 2): up from the first row was dropped; „Abspielen“ takes the focus (observed only
    /// by `HeroButtons`). the request also reaches a button row the lazy list builds again (within a second).
    private(set) var heroFocusRequest = 0
    /// Review N1: a request nobody claimed within a second expires.
    @ObservationIgnored private var heroFocusUntil: ContinuousClock.Instant?

    func requestHeroFocus() {
        heroFocusUntil = ContinuousClock.now + .seconds(1)
        heroFocusRequest &+= 1
    }

    /// True once per unexpired request (for the button row that applies it).
    func takeHeroFocusRequest() -> Bool {
        guard let until = heroFocusUntil else { return false }
        heroFocusUntil = nil
        return ContinuousClock.now < until
    }

    /// Build 5 (b5r): rest before the backdrop follows (800 ms, longer while the user presses in a rhythm).
    @ObservationIgnored private var rest = BackdropRest()

    /// Kachel hat den Fokus: Diashow sofort anhalten, Hintergrund erst nach der Ruhe von `BackdropRest` wechseln
    /// (b5r, device test 2: with 350 ms it swapped every 1–1.5 s while the user kept pressing right).
    /// Ein neuer Fokus bricht die Wartezeit ab; pro Ruhepause höchstens eine Log-Zeile.
    /// Build 4 follow-up 2 (P3): `onRest` (Quellen vorladen, Task 7) runs only after `FocusRest.prefetchMilliseconds`
    /// (1 s) of rest, b5r: never before the backdrop crossfade is over (rest + 0.6 s); and not for the short stops
    /// while browsing (the device log showed stops 0.5–0.8 s apart, each starting a search). Also when the backdrop already shows this tile
    /// (focus came back before its prefetch). A new focus or leaving the rows cancels both steps.
    /// Intended (P3 review M4): every return to the shown tile requests again after 1 s, so `keepStream` also promotes
    /// an entry that was prefetched already; harmless, do not skip the shown tile here.
    func set(_ m: MetaPreview, onRest: (() -> Void)? = nil) {
        if !inRows { inRows = true }
        pending?.cancel()
        pending = nil
        // Task 5.2: no token = nothing to show (option off, or this card is shown already): prefetch only.
        let token = follow.focus(m.id, follows: followsBackdrop)
        let restMs: Int = rest.moved(at: ProcessInfo.processInfo.systemUptime, wantsSwap: token != nil)
        let stop = FocusRest.stop(alreadyShown: token == nil, backdropRest: restMs,
                                  fadeMilliseconds: HeroMetrics.backdropFadeMilliseconds)
        guard stop.backdropWait != nil || onRest != nil else { return }
        pending = Task { [weak self] in
            if let wait = stop.backdropWait, let token {
                try? await Task.sleep(for: .milliseconds(wait))
                guard !Task.isCancelled, let self else { return }
                if self.follow.rested(token) != nil {
                    self.item = m
                    // b5r: rest waited and how many cards of the burst got no swap (next device test).
                    let skipped: Int = self.rest.swapped()
                    let burst: String = skipped > 0 ? " · \(skipped) Karten davor ohne Wechsel" : ""
                    RemoteLog.info("hero", "Fokus-Hintergrund \(m.id) nach \(wait) ms Ruhe\(burst)")
                }
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
        follow.leave()
        rest.reset()
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

    /// Task 5.2: carousel left/right on the hero button, wrapping at both ends (PlayerCore `HeroCarousel`).
    func step(forward: Bool) {
        guard items.count > 1 else { return }
        index = HeroCarousel.step(index, count: items.count, forward: forward)
    }
}

enum HeroMetrics {
    /// Abstand des ScrollView (Knopfzeile + Reihen) von oben; darüber steht die Info-Ebene.
    static let listTop: CGFloat = 470
    static let logoHeight: CGFloat = 140
    /// Height of the meta line ("2018 · 1 h 37 min · FSK 0").
    static let metaLineHeight: CGFloat = 30
    /// Device test 1 (user decision): logo (or title) of the collapsed info when there is room ("about 100 instead
    /// of 140").
    static let compactLogoHeight: CGFloat = 100
    /// P2 (follow-up 2): smallest logo (or title) of the collapsed info; with less room the floor of the collapsed
    /// list top wins and the tallest row no longer fits whole (logged as "passt nicht").
    static let compactLogoMin: CGFloat = 80
    /// Device test 1: tighter gaps of the collapsed info (full info: `Theme.Space.m`).
    static let compactSpacing: CGFloat = Theme.Space.s
    /// Two lines of the overview (`.callout`, `lineLimit(2)`).
    static let overviewHeight: CGFloat = (UIFont.preferredFont(forTextStyle: .callout).lineHeight * 2).rounded(.up)
    /// P2: the collapsed info as `HeroFullscreen` places it (PlayerCore `HeroInfoCollapse`): top inset, logo, meta line,
    /// ratings and the two-line overview (device test 1: nothing is dropped any more).
    static let compactInfo = HeroInfoCollapse.CompactInfo(topInset: Theme.Space.s, logoMax: compactLogoHeight,
                                                          logoMin: compactLogoMin, spacing: compactSpacing,
                                                          metaLine: metaLineHeight,
                                                          ratings: ThemeBadge.TechSize.detail.height,   // InfoBadges.height
                                                          overview: overviewHeight)
    /// Task 5.2: the hero pieces for PlayerCore (`HeroInfoMetrics`, today's tokens, measured overview).
    /// `infoMetrics.compactInfo(.vollbild, level: .standard)` equals `compactInfo` (test
    /// `fullscreenStandardCompactInfoIsTodays`).
    /// Review M2: every piece that has an app token is fed from it, so a token change cannot drift.
    static let infoMetrics: HeroInfoMetrics = {
        var m = HeroInfoMetrics.standard
        m.topInset = Theme.Space.s
        m.logo = logoHeight
        m.compactLogo = compactLogoHeight
        m.compactLogoMin = compactLogoMin
        m.spacing = Theme.Space.m
        m.compactSpacing = compactSpacing
        m.metaLine = metaLineHeight
        m.overview = overviewHeight
        m.ratings = ThemeBadge.TechSize.detail.height
        m.badges = ThemeBadge.TechSize.detail.height
        m.buttonRow = Theme.Layout.rowMinHeight + 2 * Theme.Space.s   // HeroButtons: button + vertical padding
        m.listPadding = listPadding
        m.fullscreenListTop = listTop
        m.frameGap = Theme.Space.m
        m.carouselGap = Theme.Space.l
        return m
    }()
    /// Top padding of the hero list content above the button row (`HomeView.heroHome`).
    static let listPadding: CGFloat = 24
    /// Longest backdrop crossfade (today's 0.6 s; `motion.backdrop` standard is 0.7). The P3 prefetch rest (1 s)
    /// starts after the backdrop rest (b5r: `BackdropRest`, at least 800 ms) plus this fade.
    static let backdropFade: Double = Double(BackdropRest.fadeMilliseconds) / 1000
    /// The same fade in ms for `FocusRest.stop(alreadyShown:backdropRest:fadeMilliseconds:)`.
    static let backdropFadeMilliseconds: Int = BackdropRest.fadeMilliseconds
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

/// Vollbild-Hintergrund: das Bild (`HeroPicture`) unter den Verläufen nach links und unten.
struct HeroBackdrop: View {
    let url: String?

    var body: some View {
        ZStack {
            HeroPicture(url: url)
            HeroScrim()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Verläufe nach links und unten, damit die Info lesbar bleibt (Vollbild und Karten, Task 5.2).
struct HeroScrim: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.35), location: 0.45),
                                   .init(color: .clear, location: 0.7)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.6), location: 0.6),
                                   .init(color: .black.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Hero-Bild; das neue Bild wird erst geladen und dann übergeblendet (`motion.backdrop`, höchstens 0,6 s wie
/// bisher; Bewegung aus: ohne Überblendung). Task 5.2: shared by full screen, banner, carousel card and the
/// carousel's next title (`logs` false: no `bilder: Hintergrund` line for that one). Always `ImageTarget.heroBackdrop`
/// (1920×1080 px), so every variant hits the same cache entry and the slide prefetch.
struct HeroPicture: View {
    let url: String?
    var logs = true
    @Environment(\.theme) private var theme
    @State private var shown: Shown?

    private struct Shown: Equatable {
        let url: String
        let image: UIImage
    }

    private var fade: Animation? {
        let d: Double = min(theme.motion.backdrop, HeroMetrics.backdropFade)
        return d > 0 ? Animation.easeInOut(duration: d) : nil
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
        }
        .allowsHitTesting(false)
        .task(id: url) { await load() }
        // Covered (detail page, playback): do not pin the backdrop bitmap outside the cache budget. P3 review 2 (M2):
        // since device test 1 it is ≈ 7.9 MiB, below `RemoteImage.releaseBytes`, so it is released without a size
        // check. On return `.task(id:)` runs again and takes it from the memory cache (`aus Speicher` in the
        // `bilder: Hintergrund` line) or the URLCache.
        .onDisappear { shown = nil }
    }

    private func load() async {
        guard let s = url, let u = URL(string: s) else {
            withAnimation(fade) { shown = nil }
            return
        }
        if shown?.url == s { return }
        let target = ImageTarget.heroBackdrop   // P3 device test 1: at most 1920×1080 px (user decision)
        let started = ContinuousClock.now
        // Speichercache-Treffer nach dem Freigeben (Rückkehr): sofort, ohne Überblendung.
        if shown == nil, let hit = ImagePipeline.shared.cachedImage(u, target: target) {
            shown = Shown(url: s, image: hit)
            if logs { PictureArrivalLog.backdrop.note(hit, fromMemory: true, waitMs: 0, fades: false) }   // P3
            return
        }
        // P3: from memory or loaded (disk/network + decode), and how long until the crossfade starts.
        let inMemory = ImagePipeline.shared.cachedImage(u, target: target, count: false) != nil
        guard let img = await ImagePipeline.shared.image(u, target: target), !Task.isCancelled else { return }
        let waited = Metric.ms(started.duration(to: ContinuousClock.now))
        if logs { PictureArrivalLog.backdrop.note(img, fromMemory: inMemory, waitMs: waited, fades: true) }
        withAnimation(fade) { shown = Shown(url: s, image: img) }
    }
}

/// Erste Zeile im ScrollView: [▶ Abspielen] [Details] und die Diashow-Punkte.
/// Fokus von den Reihen nach oben landet immer auf „Abspielen“ (eigene Fokus-Sektion mit Vorgabe).
struct HeroButtons: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.navigate) private var navigate
    @Environment(HomeFocus.self) private var focus
    @Environment(\.theme) private var theme
    let slides: HeroSlides
    /// Wave F-j: the button row gains (true) or loses (false) focus; it is the top edge of the home page.
    var onFocusChange: ((Bool) -> Void)? = nil
    /// Task 5.2: leading inset (full screen: `Theme.Space.edge`; banner and carousel: inside the card).
    var leading: CGFloat = Theme.Space.edge
    /// Task 5.2 (`heroStyle` karussell): left on „Abspielen“ / right on „Details“ switches the title.
    var carousel = false
    @FocusState private var field: Field?
    @State private var starting = false
    /// Task 5.2: when the focus last moved inside the row; a move command right after it was that focus move, not a
    /// carousel step at the row's end (the order of focus update and move command is not guaranteed).
    @State private var fieldMoved = ContinuousClock.now
    /// Review N4: the running claim of a hero focus request (re-asserts „Abspielen“ for a short while).
    @State private var heroClaim: Task<Void, Never>?

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
        .padding(.leading, leading)
        .padding(.trailing, Theme.Space.edge)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onMoveCommand(perform: moveAction)
        .focusSection()
        .defaultFocus($field, .play, priority: .userInitiated)
        // Die App-Akzentfarbe (RootView .tint) färbte beide Knöpfe blau; Welle F-i: Token-Knöpfe (ThemeActionButtonStyle).
        .tint(Color?.none)
        .onChange(of: field) { _, f in
            if f != nil { focus.leaveRows() }
        }
        .onChange(of: field != nil) { _, f in onFocusChange?(f) }
        .onChange(of: field) { fieldMoved = ContinuousClock.now }
        // Back from a pushed page with the focus state unchanged: report it again.
        .onAppear {
            if field != nil { onFocusChange?(true) }
            claimHeroFocusRequest()
        }
        .onChange(of: focus.heroFocusRequest) { claimHeroFocusRequest() }
        .onDisappear {
            onFocusChange?(false)
            heroClaim?.cancel()   // review N4: no late claim on a page that went away
            heroClaim = nil
        }
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

    /// Build 5 device test 1 (item 2): a dropped up press in the first row hands the focus to „Abspielen“.
    /// Review N4: on a button row built (or scrolled into view) in the same pass the focus engine can drop the
    /// assignment, so it is repeated (`FocusClaim`, at most half a second). b6 review 3: the claim ends as soon as the
    /// focus moved anywhere else meanwhile (the user went on in the rows), so it never pulls the focus back.
    private func claimHeroFocusRequest() {
        guard focus.takeHeroFocusRequest() else { return }
        heroClaim?.cancel()
        heroClaim = Task { @MainActor in
            let outcome = await FocusClaim.run(endsOnMove: true, held: { field != nil }, assign: { field = .play })
            switch outcome {
            case .held(let n) where n > 1: RemoteLog.info("fokus", "Abspielen nach \(n) Versuchen fokussiert")
            case .held, .cancelled: break
            case .movedAway: RemoteLog.info("fokus", "Abspielen: Anspruch beendet, Fokus woanders hin bewegt")
            case .gaveUp: RemoteLog.info("fokus", "Abspielen: Fokus nach \(FocusClaim.tries) Versuchen nicht übernommen")
            }
        }
    }

    /// Task 5.2: only the carousel listens to left/right (other styles keep the plain focus moves).
    private var moveAction: ((MoveCommandDirection) -> Void)? {
        guard carousel else { return nil }
        return { carouselMove($0) }
    }

    /// Task 5.2: carousel step at the row's ends (nothing focusable lies beyond them; the next title is a picture).
    /// Rules in PlayerCore `HeroCarousel.step(for:at:sidebar:)` (review I3): never up/down, a move inside the row is
    /// a focus move only, with the sidebar navigation left on „Abspielen“ reaches the sidebar.
    private func carouselMove(_ direction: MoveCommandDirection) {
        guard carousel, slides.items.count > 1, let move = Self.move(direction) else { return }
        guard fieldMoved.duration(to: ContinuousClock.now) > .milliseconds(150) else { return }
        let button: HeroCarousel.Button? = field.map { $0 == .play ? .first : .last }
        // Integration build 5 (review b5a2 R5): the navigation of the look (Task 5.6), as the tab view draws it.
        let sidebar: Bool = theme.chrome.navigation == .seitenleiste
        guard let forward = HeroCarousel.step(for: move, at: button, sidebar: sidebar) else { return }
        slides.step(forward: forward)
        let title = slides.current?.name ?? "?"
        RemoteLog.info("hero", "Karussell \(forward ? "vor" : "zurück") → \(title) (\(slides.index + 1)/\(slides.items.count))")
    }

    private static func move(_ d: MoveCommandDirection) -> HeroCarousel.Move? {
        switch d {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        @unknown default: return nil
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
    /// No caller on this branch since device test 1 (P3): the home hero, its slide prefetch and the expanded card use
    /// `ImageTarget.heroBackdrop` (1920×1080 px). Kept only so concurrent branches that still call it keep compiling;
    /// remove once they are merged. A new caller would split the hero's cache entry again.
    static func fullScreen(scale: CGFloat) -> ImageTarget {
        ImageTarget(points: 1920, 1080, scale: Double(scale), fit: false) ?? ImageTarget(width: 1920, height: 1280, fit: false)
    }
}

/// Review N4 (b6): a focus assignment the focus engine can drop (a view built or scrolled into view in the same
/// pass). Assigns after one main-queue hop and then every 100 ms until `held` holds, at most `tries` times (the last
/// check at 500 ms). `endsOnMove`: the claim ends when any focus update came in that did not reach the target (the
/// user moved on), so a late retry never steals the focus.
@MainActor enum FocusClaim {
    enum Outcome: Equatable {
        /// Held at this check (0 = before the first assignment, 1 = after it).
        case held(Int)
        case movedAway, gaveUp, cancelled
    }

    static let tries = 5

    static func run(endsOnMove: Bool, held: () -> Bool, assign: () -> Void) async -> Outcome {
        let updates = FocusUpdateCount()
        defer { updates.stop() }
        for attempt in 0...tries {
            if attempt == 0 {
                await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
            } else {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return .cancelled }
            if held() { return .held(attempt) }
            if endsOnMove, updates.count > 0 { return .movedAway }
            guard attempt < tries else { break }
            assign()
        }
        return .gaveUp
    }
}

/// Counts focus updates (`UIFocusSystem.didUpdateNotification`) from its creation until `stop()`.
@MainActor private final class FocusUpdateCount {
    private(set) var count = 0
    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(forName: UIFocusSystem.didUpdateNotification, object: nil,
                                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}
