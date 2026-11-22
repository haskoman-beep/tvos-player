import SwiftUI
import UIKit
import PlayerCore

// Wave P-b: side panel in the player (right third, 720 pt) with Folgen, Kapitel, Andere Quelle and Infos.
// Logic (entries, gesture, navigation, rows): PlayerCore `SidePanel.swift`.

/// What the presenter (source list) lets the side panel do. nil for trailers and TorBox files: then the panel
/// only has Kapitel and Infos.
struct PlayerSideLinks {
    /// Running source (marked in "Andere Quelle", size and addon for Infos).
    var stream: StreamItem
    var addon: String?
    /// Current source list of the title, in the order of the list.
    var sources: @MainActor () -> [(addon: String, stream: StreamItem)]
    /// Sources that failed in this list (shown dimmed).
    var failed: @MainActor () -> Set<String>
    /// The player closed without recording anything: start this source at the given held position (seconds).
    var switchSource: @MainActor (StreamItem, Double) -> Void
    /// The player closed: look up this episode (same release first) and play it.
    var playEpisode: @MainActor (PlayRequest) -> Void

    /// Runs `before` ahead of each exit (PlayerScreen: an exit with the panel open is a real disappear, and a
    /// source switch pauses the scrobble instead of stopping it).
    func closing(_ before: @escaping @MainActor (SidePanelExit) -> Void) -> PlayerSideLinks {
        var l = self
        let s = switchSource, p = playEpisode
        l.switchSource = { before(.sourceSwitch); s($0, $1) }
        l.playEpisode = { before(.episodeSwitch); p($0) }
        return l
    }
}

extension PlayRequest {
    /// Wave P-b: the same series at another episode (built like `nextRequest`).
    func episode(season s: Int, episode e: Int) -> PlayRequest? {
        guard let base = seriesBase else { return nil }
        return PlayRequest(type: type, id: "\(base):\(s):\(e)", title: "\(item.name) S\(s)E\(e)",
                           item: item, season: s, episode: e, episodes: episodes)
    }

    /// Series ID in front of ":season:episode"; nil for a movie.
    var seriesBase: String? {
        guard season != nil, episode != nil, let b = id.split(separator: ":").first else { return nil }
        return String(b)
    }
}

/// Title data for the side panel and the pause card, loaded once per player (meta and TMDB texts are cached in
/// AppModel, so this is usually instant).
@MainActor
final class PlayerExtras: ObservableObject {
    @Published private(set) var meta: MetaDetail?
    @Published private(set) var localized: LocalizedMeta?
    /// Localized episode texts by season.
    @Published private(set) var seasonTexts: [Int: [Int: LocalizedEpisode]] = [:]
    private(set) var request: PlayRequest?
    private(set) var links: PlayerSideLinks?
    private weak var model: AppModel?
    private var task: Task<Void, Never>?
    private var seasonTasks: Set<Int> = []

    func attach(model: AppModel, request: PlayRequest, links: PlayerSideLinks?) {
        self.model = model
        self.links = links
        guard self.request == nil else { return }
        self.request = request
        let series = request.season != nil
        let id = request.item.id
        task = Task { [weak self] in
            let meta = await model.meta(type: series ? "series" : request.type, imdb: id)
            guard let self, !Task.isCancelled else { return }
            self.meta = meta
            if id.hasPrefix("tt") { self.localized = await model.localized(imdb: id, series: series) }
            if let s = request.season { self.loadSeason(s) }
            RemoteLog.info("player", "Seitenpanel-Daten: \(meta == nil ? "keine Metadaten" : "\(meta?.videos?.count ?? 0) Videos")"
                           + " · TMDB \(self.localized == nil ? "nein" : "ja")")
        }
    }

    /// Player left for good: stop loading (results only fill caches, but no work after the player is gone).
    func cancel() { task?.cancel() }

    /// Episodes: from the request (source list), else from the meta.
    var episodes: [EpisodeRef] {
        if let r = request, !r.episodes.isEmpty { return r.episodes }
        return EpisodeRef.list(from: meta?.videos ?? [])
    }

    var isSeries: Bool { request?.season != nil && episodes.count > 1 }

    func loadSeason(_ s: Int) {
        guard let model, let id = request?.item.id, id.hasPrefix("tt"), seasonTexts[s] == nil, seasonTasks.insert(s).inserted else { return }
        Task { [weak self] in
            let eps = await model.localizedSeason(imdb: id, season: s)
            self?.seasonTexts[s] = eps
        }
    }

    func thumbnail(season: Int, episode: Int) -> String? {
        seasonTexts[season]?[episode]?.still ?? meta?.videos?.first { $0.season == season && $0.episode == episode }?.thumbnail
    }

    func isWatched(season: Int, episode: Int) -> Bool {
        guard let model, let base = request?.seriesBase else { return false }
        return model.progress.isWatched("\(base):\(season):\(episode)")
    }

    /// Spoiler protection like the detail page (stills of unwatched episodes blurred).
    func blursStill(season: Int, episode: Int) -> Bool {
        (model?.profile.sources.blurUnwatchedStills ?? false) && !isWatched(season: season, episode: episode)
    }

    var cast: [String] { localized?.cast.map(\.name) ?? [] }

    var pauseContent: PauseCardContent? {
        guard let r = request else { return nil }
        let s = r.season, e = r.episode
        var video: MetaVideo?
        var locEp: LocalizedEpisode?
        if let s, let e {
            video = meta?.videos?.first { $0.season == s && $0.episode == e }
            locEp = seasonTexts[s]?[e]
        }
        let titleText = localized?.overview ?? meta?.description ?? r.item.description
        return PauseCardContent.make(title: localized?.name ?? meta?.name ?? r.item.name,
                                     logo: localized?.logo ?? meta?.logo ?? r.item.logo,
                                     season: s, episode: e, episodeTitle: locEp?.name ?? video?.name ?? video?.title,
                                     descriptions: s == nil ? [titleText] : [locEp?.overview, video?.overview],
                                     cast: cast)
    }
}

// MARK: Player actions

extension PlayerControls {
    /// Content of the player's cover when the side panel is open. Actions that leave the player run only after the
    /// cover is gone (`runSideAfterClose`), so two presentations never close at the same time.
    @ViewBuilder func sidePanel(_ extras: PlayerExtras) -> some View {
        PlayerSidePanel(engine: engine, extras: extras, sourceURL: url, scrubbing: { scrub.isActive },
                        onSeek: { t in sideAfterClose = { sidePanelSeek(t) } },
                        onEpisode: { r in
                            guard let links = extras.links else { return }
                            sideAfterClose = { sidePanelPlayEpisode(r, links: links) }
                        },
                        onSource: { s in
                            guard let links = extras.links else { return }
                            sideAfterClose = { sidePanelSwitchSource(s, links: links) }
                        })
    }

    /// onDismiss of the player's cover: run the action chosen in the side panel.
    func runSideAfterClose() {
        let action = sideAfterClose
        sideAfterClose = nil
        action?()
    }

    /// What the X-Ray slot gets (nil without title data).
    var pauseAccessoryContext: PauseCardAccessoryContext? {
        guard let x = sideExtras, let r = x.request else { return nil }
        return PauseCardAccessoryContext(itemID: r.item.id, season: r.season, episode: r.episode,
                                         position: engine.currentTime, cast: x.cast)
    }

    /// Chapter chosen: jump there (a collected ±10 s jump is dropped).
    func sidePanelSeek(_ t: Double) {
        guard !leaving else { return }
        guard !restorePending, !restoring else { RemoteLog.info("player", "Kapitel-Sprung gesperrt bis Play/Neuaufbau (nach Hintergrund)"); return }
        onUserInput()
        seekTask?.cancel(); pendingSeek = nil
        RemoteLog.info("player", "Seitenpanel: Kapitel-Sprung \(Int(engine.currentTime)) → \(Int(t))s")
        Task { await engine.seek(t) }
        poke()
    }

    /// Episode chosen: save the position, stop (display mode kept like for the next episode) and let the source
    /// list find the episode with the same release.
    func sidePanelPlayEpisode(_ r: PlayRequest, links: PlayerSideLinks) {
        guard !leaving else { return }
        onUserInput()
        saveProgress()
        RemoteLog.info("player", "Seitenpanel: Folge \(r.title) bei \(Int(engine.currentTime))s verlassen")
        stopBeforeNext(true)
        leave { links.playEpisode(r) }
    }

    /// Other source chosen: the new player starts exactly at the held position. Nothing is recorded on the way out
    /// (`SidePanelExit.sourceSwitch`: a switch in the credits must not mark the title watched), and the display
    /// mode is kept because the same title starts again right away.
    func sidePanelSwitchSource(_ s: StreamItem, links: PlayerSideLinks) {
        guard !leaving else { return }
        onUserInput()
        let held = pendingSeek ?? engine.currentTime
        sideHoldsProgress = true
        RemoteLog.info("player", "Seitenpanel: andere Quelle ab \(Int(held))s (ohne Fortschritt zu speichern): \(s.name ?? "") \(LogRedact.text(s.title ?? "").prefix(60))")
        engine.stopKeepingDisplayMode()
        leave { links.switchSource(s, held) }
    }
}

// MARK: Hint in the control bar

/// "▲ Folgen · Kapitel · Quelle · Infos": the way into the side panel, as a pill in the control bar.
struct SidePanelHint: View {
    let trackStyle: TrackPanelStyle
    let pages: [SidePanelPage]

    var body: some View {
        if let text = SidePanelMenu.hint(trackStyle: trackStyle, pages: pages) {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                .background(Theme.Palette.badgeFill, in: Capsule())
                .accessibilityLabel("Mehr: " + pages.map(\.title).joined(separator: ", "))
        }
    }
}

extension PlayerExtras {
    /// Pages the start list will show (for the hint), without the stills.
    func pages(chapters: Int) -> [SidePanelPage] {
        SidePanelMenu.entries(SidePanelAvailability(episodeCount: isSeries ? episodes.count : 0, chapterCount: chapters,
                                                    sourceCount: links?.sources().count)).map(\.page)
    }
}

// MARK: Panel

/// The panel itself, shown in the player's full-screen cover (like the track panel), so focus and the Menu button
/// stay inside. The picture keeps running; only the edge towards the panel is darkened.
struct PlayerSidePanel<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    @ObservedObject var extras: PlayerExtras
    var sourceURL: URL?
    /// The user is scrubbing (then the preview session is theirs; the chapter stills do not end it).
    var scrubbing: () -> Bool = { false }
    var gesture: String = ""
    let onSeek: (Double) -> Void
    let onEpisode: (PlayRequest) -> Void
    let onSource: (StreamItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nav = SidePanelNav(entries: [])
    @State private var season: Int?
    @State private var stills: [Int: UIImage] = [:]
    @FocusState private var focus: SideFocus?

    static var width: CGFloat { 720 }

    enum SideFocus: Hashable {
        case entry(SidePanelPage)
        case season(Int)
        case episode(String)
        case chapter(Int)
        case source(String)
        case info(String)
    }

    private var sources: [(addon: String, stream: StreamItem)] { extras.links?.sources() ?? [] }

    private var infoRows: [TrackPanelInfoRow] {
        var snap = (engine as? any PlaybackTechInfoSource)?.trackPanelTech ?? PlaybackTechSnapshot()
        snap.fileName = TrackPanelLogic.sourceFileName(sourceURL)
        let traits = extras.links.map { StreamTraits.parse($0.stream) }
        return SideInfo.rows(tech: snap, traits: traits, duration: engine.duration, addon: extras.links?.addon)
    }

    private var entries: [SidePanelEntry] {
        let chapters = engine.chapterMarks
        return SidePanelMenu.entries(SidePanelAvailability(
            episodeCount: extras.isSeries ? extras.episodes.count : 0,
            seasonCount: SideEpisodes.seasons(extras.episodes).count,
            currentSeason: extras.request?.season, currentEpisode: extras.request?.episode,
            chapterCount: chapters.count,
            currentChapter: SideChapters.rows(chapters, position: engine.currentTime).first(where: \.isCurrent)?.title,
            sourceCount: extras.links == nil ? nil : sources.count,
            infoSummary: SideInfo.summary(infoRows)))
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 160)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(nav.page?.title ?? "Mehr").font(.title3.bold())
                    .padding(.horizontal, Theme.Space.xs)
                page
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.vertical, Theme.Space.l)
            .padding(.horizontal, Theme.Space.m)
            .frame(width: Self.width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                ZStack { Rectangle().fill(.ultraThinMaterial); Theme.Palette.scrim }.ignoresSafeArea()
            }
        }
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, initialFocus)
        .onAppear {
            nav = SidePanelNav(entries: entries)
            season = SideEpisodes.initialSeason(current: extras.request?.season, in: extras.episodes)
            RemoteLog.info("player", "Seitenpanel auf (\(gesture)) · " + entries.map(\.title).joined(separator: ", "))
            refocus()
        }
        .onDisappear { RemoteLog.info("player", "Seitenpanel zu") }
        .onExitCommand {
            switch nav.back() {
            case .toList: refocus()
            case .close: dismiss()
            }
        }
        .onChange(of: season) { _, s in if let s { extras.loadSeason(s) } }
        .task(id: nav.page) { if nav.page == .chapters { await loadStills() } }
        .presentationBackground(.clear)
    }

    @ViewBuilder private var page: some View {
        switch nav.page {
        case nil: entryList
        case .episodes: episodePage
        case .chapters: chapterPage
        case .sources: sourcePage
        case .info: infoPage
        }
    }

    // MARK: Start list

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entries) { e in
                Button {
                    nav.open(e.page)
                    RemoteLog.info("player", "Seitenpanel: \(e.title)")
                    refocus()
                } label: {
                    SideRowLabel(title: e.title, detail: e.detail, trailing: "›")
                }
                .buttonStyle(SideRowLabel.style)
                .focused($focus, equals: .entry(e.page))
            }
        }
        .focusSection()
    }

    // MARK: Folgen

    private var episodePage: some View {
        let eps = extras.episodes
        let seasons = SideEpisodes.seasons(eps)
        let s = season ?? seasons.first ?? 1
        let current = extras.request.flatMap { r in r.season.flatMap { s in r.episode.map { EpisodeRef(season: s, episode: $0) } } }
        let titles = (extras.seasonTexts[s] ?? [:]).compactMapValues(\.name)
        let rows = SideEpisodes.rows(eps, season: s, current: current, titles: titles,
                                     isWatched: { extras.isWatched(season: $0.season, episode: $0.episode) })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(seasons, id: \.self) { n in
                            Button { season = n } label: {
                                SideRowLabel(title: "Staffel \(n)", isActive: n == s)
                            }
                            .buttonStyle(SideRowLabel.chipStyle)
                            .focused($focus, equals: .season(n))
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, Theme.Space.xs)
                }
                .focusSection()
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(rows) { row in
                            Button {
                                guard !row.isCurrent else { dismiss(); return }
                                guard let r = extras.request?.episode(season: row.season, episode: row.episode) else { return }
                                dismiss()
                                onEpisode(r)
                            } label: {
                                SideRowLabel(title: row.line, detail: row.isCurrent ? "läuft" : nil,
                                             image: .remote(extras.thumbnail(season: row.season, episode: row.episode),
                                                            blur: extras.blursStill(season: row.season, episode: row.episode)),
                                             mark: row.isWatched, isActive: row.isCurrent)
                            }
                            .buttonStyle(SideRowLabel.style)
                            .focused($focus, equals: .episode(row.id))
                            .id(row.id)
                        }
                    }
                    .padding(.horizontal, Theme.Space.xs).padding(.vertical, 4)
                }
                .onAppear { if let id = SideEpisodes.initialFocus(rows) { proxy.scrollTo(id, anchor: .center) } }
            }
            .focusSection()
        }
    }

    // MARK: Kapitel

    private var chapterPage: some View {
        let rows = SideChapters.rows(engine.chapterMarks, position: engine.currentTime)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { row in
                        Button {
                            dismiss()
                            onSeek(row.start)
                        } label: {
                            SideRowLabel(title: row.title, detail: row.time,
                                         image: engine.supportsScrubPreview ? .still(stills[row.index]) : nil,
                                         isActive: row.isCurrent)
                        }
                        .buttonStyle(SideRowLabel.style)
                        .focused($focus, equals: .chapter(row.index))
                        .id(row.index)
                    }
                }
                .padding(.horizontal, Theme.Space.xs).padding(.vertical, 4)
            }
            .onAppear { if let c = rows.first(where: \.isCurrent) { proxy.scrollTo(c.index, anchor: .center) } }
        }
        .focusSection()
    }

    /// Stills from already loaded data only (no second connection); chapters far away stay without a picture.
    private func loadStills() async {
        guard engine.supportsScrubPreview else { return }
        let rows = SideChapters.rows(engine.chapterMarks, position: engine.currentTime).prefix(60)
        var got = 0
        for row in rows where stills[row.index] == nil {
            guard !Task.isCancelled else { break }
            // A little after the chapter start: the first frame is often black.
            if let s = await engine.scrubPreview(at: row.start + 3, refined: false, maxWidth: 320) {
                stills[row.index] = UIImage(cgImage: s.image); got += 1
            }
        }
        if !scrubbing() { await engine.endScrubPreview() }
        RemoteLog.info("player", "Seitenpanel: Kapitelbilder \(got)/\(rows.count)")
    }

    // MARK: Andere Quelle

    private var sourcePage: some View {
        let list = sources
        let failed = extras.links?.failed() ?? []
        let current = extras.links?.stream.id
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(list, id: \.stream.id) { entry in
                        let text = StreamRowText(entry.stream)
                        let isCurrent = entry.stream.id == current
                        Button {
                            switch SideSources.choose(entry.stream.id, current: current, playable: entry.stream.url != nil) {
                            case .keep: dismiss()
                            case .unavailable: RemoteLog.info("player", "Seitenpanel: Quelle ohne Adresse")
                            case .switchTo:
                                dismiss()
                                onSource(entry.stream)
                            }
                        } label: {
                            SideRowLabel(title: text.name.isEmpty ? entry.addon : text.name,
                                         subtitle: text.body.isEmpty ? nil : text.body,
                                         detail: isCurrent ? "läuft" : StreamTraits.parse(entry.stream).sizeBytes.map(SideInfo.sizeLabel),
                                         isActive: isCurrent)
                            .opacity(failed.contains(entry.stream.id) ? 0.45 : 1)
                        }
                        .buttonStyle(SideRowLabel.style)
                        .focused($focus, equals: .source(entry.stream.id))
                        .id(entry.stream.id)
                    }
                }
                .padding(.horizontal, Theme.Space.xs).padding(.vertical, 4)
            }
            .onAppear { if let c = current { proxy.scrollTo(c, anchor: .center) } }
        }
        .focusSection()
    }

    // MARK: Infos

    private var infoPage: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(infoRows) { r in
                    // Focusable without an action, so the list can scroll and Menu has a target.
                    Button {} label: { SideRowLabel(title: r.label, subtitle: r.value) }
                        .buttonStyle(SideRowLabel.style)
                        .focused($focus, equals: .info(r.label))
                }
            }
            .padding(.horizontal, Theme.Space.xs).padding(.vertical, 4)
        }
        .focusSection()
    }

    // MARK: Focus

    private var initialFocus: SideFocus? {
        switch nav.page {
        case nil: return nav.listFocus.map { .entry($0) } ?? entries.first.map { .entry($0.page) }
        case .episodes:
            let eps = extras.episodes
            let s = season ?? SideEpisodes.seasons(eps).first ?? 1
            let current = extras.request.flatMap { r in r.season.flatMap { s in r.episode.map { EpisodeRef(season: s, episode: $0) } } }
            let rows = SideEpisodes.rows(eps, season: s, current: current, isWatched: { extras.isWatched(season: $0.season, episode: $0.episode) })
            return SideEpisodes.initialFocus(rows).map { .episode($0) }
        case .chapters:
            let rows = SideChapters.rows(engine.chapterMarks, position: engine.currentTime)
            return (rows.first(where: \.isCurrent) ?? rows.first).map { .chapter($0.index) }
        case .sources:
            return SideSources.initialFocus(ids: sources.map(\.stream.id), current: extras.links?.stream.id).map { .source($0) }
        case .info:
            return infoRows.first.map { .info($0.label) }
        }
    }

    /// After a page change the focus goes to the page's start row (one short retry, like the track panel).
    private func refocus() {
        let target = initialFocus
        focus = target
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if focus != target { focus = target }
        }
    }
}

/// Row of the side panel: optional picture, title, second line, value on the right, watched mark.
struct SideRowLabel: View {
    enum Picture {
        case remote(String?, blur: Bool)
        case still(UIImage?)
    }

    var title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var trailing: String? = nil
    var image: Picture? = nil
    var mark = false
    var isActive = false
    @Environment(\.isFocused) private var focused

    static var style: ThemeRowButtonStyle {
        ThemeRowButtonStyle(minHeight: 0, maxWidth: .infinity, maxFocusGrowth: Theme.Focus.rowMaxGrowth,
                            restFill: .clear, verticalPadding: Theme.Space.xs)
    }

    static var chipStyle: ThemeRowButtonStyle {
        ThemeRowButtonStyle(minHeight: 0, maxWidth: 260, maxFocusGrowth: Theme.Focus.rowMaxGrowth,
                            restFill: Theme.Palette.row, verticalPadding: Theme.Space.xs)
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let image { picture(image).frame(width: 160, height: 90).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(isActive ? .semibold : .regular)).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption)
                        .foregroundStyle(focused ? Theme.Palette.secondaryOnFocus : Theme.Palette.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if mark { Image(systemName: "checkmark.circle.fill").font(.caption) }
            if let detail {
                Text(detail).font(.caption)
                    .foregroundStyle(focused ? Theme.Palette.secondaryOnFocus : Theme.Palette.secondary)
                    .lineLimit(1)
            }
            if let trailing { Text(trailing).font(.callout.bold()) }
        }
        .foregroundStyle(focused ? Theme.Palette.primaryOnFocus : Theme.Palette.primary)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder private func picture(_ p: Picture) -> some View {
        switch p {
        case .remote(let url, let blur):
            RemoteImage(url: url, maxPixels: 320, blur: blur ? SpoilerStill.blurRadius : 0)
                .spoilerMark(blur && url != nil)
        case .still(let img):
            if let img { Image(uiImage: img).resizable().aspectRatio(contentMode: .fill) }
            else { Theme.Tile.placeholder }
        }
    }
}
