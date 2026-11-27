import SwiftUI
import Combine
import PlayerCore

/// Quellenliste aller Addons (Reihenfolge von AIOStreams), mit Plaketten.
struct StreamListView: View {
    @Environment(AppModel.self) var model
    /// Task 5.3: `detail.sourceList` for the log line (the rows read it themselves).
    @Environment(\.theme) private var theme
    let request: PlayRequest
    /// Bei Autoplay die gerade laufende Folge.
    @State private var current: PlayRequest?
    @State private var nextNote: String?
    @State private var streams: [(addon: String, stream: StreamItem)] = []
    @State private var loading = true
    @State private var playing: StreamItem?
    /// Quellen, die in dieser Liste schon versagt haben, und Zahl der automatischen Wechsel.
    @State private var failed: Set<String> = []
    /// Welle G-a R1 (I1): Autostart (Weiterschauen bzw. Beste Wahl) nur einmal je Liste; `.task` läuft nach dem
    /// Vollbild-Player erneut, danach entscheidet allein die Rückfallleiter bzw. die Auswahl. Task 3.4 (F-B-5): the
    /// used autostart is also kept in `StreamListAutostarts` (survives a rebuild of the TabView).
    @State private var autostartDone = false
    @State private var fallbacks = 0
    /// „Noch da?“-Zähler, Addon je Quelle, offene Abfrage (StillWatchingPrompt.swift).
    @State private var autoNext = AutoNextState()
    /// Welle D-b (M3): veralteter, lückenhafter Stand gezeigt, die Erneuerung läuft und wird übernommen.
    @State private var refreshingPartial = false
    /// Welle F-c (§3.2): fokussierte Quelle; Eintritt auf die zuletzt gespielte, nach einem Fehler die nächste darunter.
    @FocusState private var focusedStream: String?
    @State private var focusRequest: SourceFocusRequest?
    @State private var entryFocusDone = false
    /// Zuletzt gescheiterte Quelle (von `fallback` gesetzt, beim Schließen des Players verbraucht).
    @State private var lastFailure: String?
    /// Automatischer Wechsel geplant: dann kein Fokuswunsch nach dem Fehler (Review F-c M2; das nächste Vollbild
    /// öffnet gleich, beim Schließen gilt die Regel für die zuletzt gespielte Quelle).
    @State private var autoSwitchScheduled = false
    /// Wave F-m: player that just closed; its focus move waits for the end of the cover dismissal (`playerDismissed`).
    @State private var closedPlayer: StreamItem?
    /// Wave Q: chosen filter chips (view only, per list visit) and the parsed traits per source id.
    @State private var filter: Set<SourceFilterChip> = []
    /// Parsed traits, keyed by `traitKey` (id plus the hints the id leaves out, review Q M3).
    @State private var traitsByID: [String: StreamTraits] = [:]
    /// Review Q I3/N1: the user chose on the chip bar (pressed a chip or moved between chips): the entry focus
    /// leaves them there. Focus that tvOS puts on "Alle" by itself (loading line gone) does not count.
    @State private var filterTouched = false
    /// Task 1.8: list opened (first creation of this view) and the `streams.firstRow` line written.
    @State private var listOpened = ContinuousClock.now
    @State private var firstRowLogged = false

    private static func traitKey(_ s: StreamItem) -> String {
        "\(s.id)|\(s.behaviorHints?.cached.map(String.init) ?? "-")|\(s.behaviorHints?.videoSize ?? -1)|\(s.behaviorHints?.filename ?? "")"
    }
    private func traits(_ s: StreamItem) -> StreamTraits { traitsByID[Self.traitKey(s)] ?? StreamTraits.parse(s) }
    private var filterOptions: [SourceFilterOption] {
        streams.count < 2 ? [] : SourceFilter.options(streams.map { traits($0.stream) }, selected: filter)
    }
    /// Rows on screen: the full list narrowed by the chips the list still offers.
    private func visibleStreams(_ options: [SourceFilterOption]) -> [(addon: String, stream: StreamItem)] {
        let active = SourceFilter.effective(filter, options: options)
        return active.isEmpty ? streams : streams.filter { SourceFilter.passes(traits($0.stream), active) }
    }
    private var visibleIDs: [String] { visibleStreams(filterOptions).map(\.stream.id) }
    /// Wave P-b: source chosen in the player's side panel and the held position it starts at (cleared on close).
    @State private var sideStart: (id: String, at: Double)?

    var body: some View {
        // Welle E-b: Addon-Name nur, wenn die Liste mehrere Addons mischt (sonst steht er schon im Text des Addons).
        let showAddon = Set(streams.map(\.addon)).count > 1
        let options = filterOptions
        let shown = visibleStreams(options)
        let shownIDs = shown.map(\.stream.id)
        // Titel als Listenkopf (scrollt mit weg) statt navigationTitle: der große tvOS-Titel lag über den Zeilen.
        ScrollViewReader { proxy in
            List {
                Section {
                    if let nextNote { Text(nextNote).foregroundStyle(.secondary) }
                    // N6: solange keine Zeile da ist, ist die Ladezeile das (unsichtbare) Fokusziel.
                    if loading { ProgressView("Quellen werden geladen …").quietFocusTarget(streams.isEmpty) }
                    if refreshingPartial { ProgressView("Fehlende Quellen werden nachgeladen …") }
                    AddonSearchStatusLine(id: (current ?? request).id)
                    if !loading && streams.isEmpty {
                        Text(model.profile.addons.isEmpty ? "Kein Addon installiert (Einstellungen → Addons)." : "Keine abspielbaren Quellen.")
                        FocusAnchor(kind: .back)   // N6: sonst nichts fokussierbar, Menu schlösse die App
                    }
                    if !options.isEmpty {
                        SourceFilterBar(options: options, selected: SourceFilter.effective(filter, options: options),
                                        total: streams.count, onAll: { setFilter([]) },
                                        onToggle: { setFilter(SourceFilter.toggle($0, in: SourceFilter.effective(filter, options: options))) },
                                        onUserMove: { filterTouched = true })
                            .listRowBackground(Color.clear)
                        if shown.isEmpty {
                            Text("Keine Quelle passt zum Filter.").foregroundStyle(.secondary)
                            Button("Filter aufheben") { clearFilterToList() }
                                .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity))
                                .listRowBackground(Color.clear)
                        }
                    }
                    ForEach(shown, id: \.stream.id) { entry in
                        Button {
                            fallbacks = 0; AutoNextState.userInput($autoNext); autoNext.ask = nil
                            PlaybackStability.shared.timing.markTap()
                            playing = entry.stream
                        } label: {
                            StreamRow(addon: showAddon ? entry.addon : nil, stream: entry.stream).opacity(failed.contains(entry.stream.id) ? 0.4 : 1)
                                .recentlyFailedMark(entry.stream, title: (current ?? request).id)
                        }
                        // Welle F-d: Zeilenform aus den Tokens (bg.row, radius.row, weiße Fokusfläche) über die volle Breite.
                        // Welle F-i: hohe Zeilen (ganzer Formatter-Text) wachsen beim Fokus höchstens um `Focus.rowMaxGrowth`
                        // je Seite, damit sie die Nachbarzeile nicht überdecken.
                        .buttonStyle(ThemeRowButtonStyle(maxWidth: .infinity, maxFocusGrowth: Theme.Focus.rowMaxGrowth))
                        .listRowBackground(Color.clear)
                        .focused($focusedStream, equals: entry.stream.id)
                        .id(entry.stream.id)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(current?.title ?? request.title).textRole(.pageTitle).lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        // X3: „161 Quellen · 8,4 s“, sobald die Suche fertig ist.
                        if !loading && !streams.isEmpty {
                            StreamListSummaryLine(id: (current ?? request).id, count: streams.count)
                        }
                    }
                    .textCase(nil).padding(.bottom, Theme.Space.s)
                }
            }
            .task(id: focusRequest) {
                guard let r = focusRequest else { return }
                // Verbrauchen (Review F-c M4): beim nächsten Erscheinen nicht erneut setzen; neuere Anfrage bleibt.
                defer { if focusRequest?.token == r.token { focusRequest = nil } }
                // Nach dem Player: erst nach dem Schließen des Vollbilds (sonst setzt tvOS den Fokus auf die gedrückte Zeile).
                try? await Task.sleep(for: .milliseconds(r.delayMs))
                for attempt in 1...4 {
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(r.id)
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    // Review Q N2: a keep move gives way to a key press (focus now on a third row).
                    if r.keep, let f = focusedStream, f != r.id, f != r.from {
                        RemoteLog.info("fokus", "Quellenliste \(r.reason): Zeile \(r.index + 1) abgebrochen (Taste)")
                        return
                    }
                    focusedStream = r.id
                    try? await Task.sleep(for: .milliseconds(150))
                    if focusedStream == r.id {
                        RemoteLog.info("fokus", "Quellenliste \(r.reason): Zeile \(r.index + 1) (Versuch \(attempt))")
                        return
                    }
                }
                RemoteLog.info("fokus", "Quellenliste \(r.reason): Zeile \(r.index + 1) nicht gesetzt")
            }
        }
        .listStyle(.grouped)
        // Gerätefoto Build 28: farbiger Schimmer hinter der Liste (App-Akzent als Tönung der Zeilen/Glasflächen,
        // durchscheinender Hintergrund). Neutral: keine Akzent-Tönung, eigener dunkler, deckender Hintergrund.
        .tint(Color?.none)
        .settingsSurface()
        .streamSearchPartials(id: request.id, loading: loading && current == nil) { streams = model.orderedStreams($0) }
        .onChange(of: streams.isEmpty) { _, empty in
            guard !empty, !firstRowLogged else { return }
            firstRowLogged = true
            // Task 5.3: the source list style in effect (once per list).
            RemoteLog.info("quellen", "Darstellung \(theme.detail.sourceList.rawValue)")
            RemoteLog.metric(.streamsFirstRow, ms: Metric.ms(listOpened.duration(to: ContinuousClock.now)),
                             fields: ["quellen": "\(streams.count)", "teilstand": loading ? "ja" : "nein"])
        }
        // Task 3.4 (F-B-1): the load task follows the episode that runs now. After "next episode automatically" it
        // loads that episode's sources (also when it runs again after the player closed), never the route's.
        .task(id: (current ?? request).id) {
            // Start of the push transition (the list appears as the push begins); see `autostartAfterPush`.
            let appeared = ProcessInfo.processInfo.systemUptime
            let r = current ?? request
            let followsOtherEpisode = r.id != request.id
            let wantsAutostart = (request.resumeLastSource || request.bestChoice != nil) && playing == nil
            let autostart = wantsAutostart && AutostartGate.shouldStart(
                requestID: request.id, alreadyStarted: StreamListAutostarts.shared.started,
                isRebuild: autostartDone || followsOtherEpisode)
            if wantsAutostart, !autostart, !autostartDone, !followsOtherEpisode {
                RemoteLog.info("nav", "Autostart schon verbraucht (Liste neu aufgebaut): \(request.id)")
            }
            let loaded = model.orderedStreams(autostart
                ? await model.streamsForAutoplay(type: r.type, id: r.id)
                : await model.streams(type: r.type, id: r.id))
            // A newer run (other episode) or a closed list takes over: nothing stale lands in the list.
            guard !Task.isCancelled, (current ?? request).id == r.id else { return }
            if followsOtherEpisode {
                // `startNext` already put this episode's rows in; while a source plays they stay (fallback and
                // the side panel look up the running source in them).
                if playing == nil || streams.isEmpty {
                    streams = loaded
                    RemoteLog.info("streams", "Quellenliste zeigt die laufende Folge: \(r.id) · \(loaded.count) Quellen")
                }
                loading = false
                return
            }
            streams = loaded
            loading = false
            if request.type == "series", request.episodes.isEmpty, let base = request.id.split(separator: ":").first {
                // Aus Weiterschauen: Folgenliste nachladen, damit die nächste Folge automatisch kommt.
                // Task 3.5 fix 1 (W-B-10): a special from Weiterschauen gets the specials, so up-next finds the next one.
                let eps = EpisodeRef.list(from: await model.meta(type: "series", imdb: String(base))?.videos ?? [],
                                          includeSpecials: EpisodeRef.includesSpecials(playingSeason: request.season))
                if current == nil { var r = request; r.episodes = eps; current = r }
            }
            // Welle G-a R1: in dieser Liste schon gescheiterte Quellen nie automatisch (die Rückfallleiter entscheidet).
            let untried = streams.filter { !failed.contains($0.stream.id) }
            let autostartNow = autostart && !Task.isCancelled
            if autostartNow { autostartDone = true; StreamListAutostarts.shared.started.insert(request.id) }
            if autostartNow, request.resumeLastSource, playing == nil, let last = model.progress.lastSource(for: request.id) {
                // nie eine zuletzt fehlgeschlagene; Welle E-b: Wahl immer in kluger Ordnung, egal wie die Liste sortiert ist
                let pick = Self.resumeCandidate(last, in: model.autoOrderedStreams(untried), title: request.id)
                if let s = pick.stream {
                    RemoteLog.info("player", "Weiterschauen mit letzter Quelle: \(s.name ?? "") \(s.label.prefix(60))")
                    if await autostartAfterPush(since: appeared) {
                        entryFocusDone = true   // Review F-c M3: Rückkehr regelt focusAfterPlayer, nicht der Eintritt
                        playing = s
                    }
                } else {
                    nextNote = pick.note
                    RemoteLog.info("player", "Letzte Quelle nicht gefunden (\(last.fingerprint.prefix(60)))")
                }
            }
            if autostartNow, let wanted = request.bestChoice, playing == nil {
                // Welle G-a: „Sofort abspielen“: die auf der Detailseite gezeigte Quelle; fehlt sie im frischen Stand
                // oder ist sie inzwischen fehlgeschlagen, neu wählen (gleiche Regeln). Rückfall danach wie immer.
                let auto = model.autoOrderedStreams(untried)
                let same = wanted.match(in: PlaybackStability.shared.autoCandidates(auto, title: request.id))
                if let s = same ?? model.bestChoice(untried, title: request.id)?.stream {
                    RemoteLog.info("play", "Beste Wahl startet\(same == nil ? " (neu gewählt)" : ""): \(s.name ?? "") \(s.label.prefix(60))")
                    if await autostartAfterPush(since: appeared) {
                        entryFocusDone = true
                        playing = s
                    }
                } else {
                    nextNote = "Keine abspielbare Quelle gefunden – bitte wählen."
                    RemoteLog.info("play", "Beste Wahl: keine abspielbare Quelle mehr → Liste")
                }
            }
            if playing == nil { focusOnEntry() }
            // Welle D-b (M3, Nacharbeit I2): lückenhafter alter Stand → Erneuerung abwarten und nur die neuen Quellen
            // anhängen (bestehende Zeilen bleiben: Fokus, `failed`, Rückfall). Nicht, wenn inzwischen etwas spielt oder
            // startet oder die Liste schon eine andere Folge zeigt.
            if playing == nil, current == nil, model.partialNeedsRefresh(id: request.id, forPage: true) {
                refreshingPartial = true
                let fresh = await model.refreshedPartialStreams(type: request.type, id: request.id)
                refreshingPartial = false
                if let fresh, !Task.isCancelled, playing == nil, current == nil {
                    let added = StreamListMerge.additions(to: streams, from: fresh)
                    if !added.isEmpty {
                        streams += model.orderedStreams(added)
                        RemoteLog.info("streams", "\(request.id): \(added.count) nachgeladene Quellen an die Liste angehängt")
                    }
                }
            }
        }
        .onChange(of: streams.map { Self.traitKey($0.stream) }) { _, keys in
            // Wave Q: parse each source once (body runs on every focus move); drop gone ones. Keyed with the hints,
            // so a hints-only change re-parses and re-checks the chips too (review Q M3/N3).
            let keep = Set(keys)
            var t = traitsByID.filter { keep.contains($0.key) }
            for (k, e) in zip(keys, streams) where t[k] == nil { t[k] = StreamTraits.parse(e.stream) }
            traitsByID = t
            dropMissingChips()
        }
        .onChange(of: shownIDs) { old, new in keepFocusPosition(old: old, new: new) }
        .onChange(of: playing) { old, s in
            if s == nil, let old { closedPlayer = old; sideStart = nil }
            guard let s else { return }
            // Addon aus der Liste, sonst das bei der nächsten Folge gemerkte (sonst „Addon nicht installiert“ beim Neuauflösen).
            model.rememberSource(current ?? request, stream: s,
                                 addon: streams.first { $0.stream.id == s.id }?.addon ?? autoNext.addons[s.id] ?? "")
        }
        .fullScreenCover(item: $playing, onDismiss: playerDismissed) { s in
            if let u = s.url.flatMap(URL.init(string:)) { PlayerScreen(url: u, request: current ?? request,
                                                                             headers: s.behaviorHints?.proxyHeaders?.request ?? [:],
                                                                             onEnded: { ended(s, autoplay: $0) }, onFallback: { fallback(from: s, reason: $0) },
                                                                             onUserInput: { AutoNextState.userInput($autoNext) },
                                                                             holdsUpNext: autoNext.promptDue(model.profile),
                                                                             onSourceVerdict: { [id = (current ?? request).id] in PlaybackStability.shared.apply($0, stream: s, title: id) },
                                                                             releaseName: s.behaviorHints?.filename,
                                                                             sideLinks: sidePanelLinks(for: s),
                                                                             startOverride: sideStart?.id == s.id ? sideStart?.at : nil).environment(model) }   // Wave P-b
        }
        .modifier(StillWatchingAlert(state: $autoNext, note: $nextNote) { startNext($0.next, after: $0.stream, auto: false) })
    }
}

/// Task 3.4 (F-B-5): route IDs of source lists whose autostart already ran. The routes stay in the tab paths when
/// the TabView is rebuilt (navigation style), the lists' own state does not. A new push of a list clears its ID
/// (`RootView.stack`), so opening the same title again starts again.
@MainActor
final class StreamListAutostarts {
    static let shared = StreamListAutostarts()
    var started: Set<String> = []

    func pushed(_ route: Route) {
        if case .streams(let r) = route { started.remove(r.id) }
    }
}

extension StreamListView {
    /// Wave F-j round 1 (hypothesis D): with a cache hit the autostart wanted the full-screen player about 140 ms
    /// after the push, while the push transition was still running; presenting during a push can leave the tab bar
    /// in a stale state. Waits until `AutostartAfterPush.settleMs` after the list appeared (no wait if the search
    /// took longer). A fixed delay rather than a transition callback: SwiftUI offers no reliable "push finished"
    /// event, and a missed callback would block the autostart for good. False if the list disappeared (task
    /// cancelled) or a row was chosen by hand meanwhile.
    private func autostartAfterPush(since appeared: Double) async -> Bool {
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - appeared) * 1000)
        let wait = AutostartAfterPush.remainingWait(elapsedMs: elapsed)
        if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
        guard !Task.isCancelled, playing == nil else { return false }
        RemoteLog.info("nav", "Autostart nach Push (\(Int((ProcessInfo.processInfo.systemUptime - appeared) * 1000)) ms)")
        return true
    }

    /// In dieser Liste startbar: Adresse da, hier nicht gescheitert, nicht im 8-h-Gedächtnis.
    private func focusPlayable(_ id: String) -> Bool {
        guard let s = streams.first(where: { $0.stream.id == id })?.stream else { return false }
        return s.url != nil && !failed.contains(id) && !PlaybackStability.shared.isRecentlyFailed(s, title: (current ?? request).id)
    }

    /// Eintritt (§3.2): zuletzt gespielte Quelle, sonst die erste spielbare. Einmal je Liste und nur, solange der
    /// Nutzer den Fokus nicht selbst auf eine andere Zeile gelegt hat.
    func focusOnEntry() {
        guard !entryFocusDone else { return }
        entryFocusDone = true
        let ids = visibleIDs
        guard focusedStream == nil || focusedStream == ids.first else { return }
        // Review Q I3: nil also means "on the chip bar"; a chosen filter counts as the user's choice too.
        if filterTouched {
            RemoteLog.info("fokus", "Quellenliste Eintritt: Fokus bleibt bei den Filtern")
            return
        }
        let last = model.progress.lastSource(for: (current ?? request).id)?.match(in: streams)?.id
        guard let id = SourceFocus.entry(ids: ids, lastPlayed: last, isPlayable: focusPlayable) else { return }
        requestFocus(id, in: ids, reason: last == id ? "Eintritt, zuletzt gespielt" : "Eintritt", delayMs: 0)
    }

    /// Player geschlossen (§3.2): nach einem Fehler die nächste Quelle unter der gescheiterten, sonst die gespielte.
    func focusAfterPlayer(_ played: StreamItem) {
        let failure = lastFailure == played.id
        lastFailure = nil
        if failure, autoSwitchScheduled {
            autoSwitchScheduled = false
            RemoteLog.info("fokus", "Quellenliste nach Fehler: automatischer Wechsel geplant, kein Fokuswunsch")
            return
        }
        let ids = visibleIDs
        guard let id = SourceFocus.afterPlayer(ids: ids, played: played.id, failed: failure, isPlayable: focusPlayable)
        else { return }
        requestFocus(id, in: ids, reason: failure ? "nach Fehler" : "nach dem Player", delayMs: 200)
    }

    /// Wave F-m: the cover is fully gone. Build 198 scrolled to the played row while it was still being dismissed
    /// (about 90 ms before the player's onDisappear) and the tab bar followed that scroll off screen for good.
    /// The focus move now starts here; the tab-wide guard checks the bar afterwards.
    func playerDismissed() {
        TabBarGuard.shared.check(.playerClosed)
        if PostPlayRoute.flushNow() { closedPlayer = nil; return }   // wave P-a: card pick → its detail page, no focus move
        guard let old = closedPlayer else { return }
        closedPlayer = nil
        focusAfterPlayer(old)
    }

    /// Wave Q: new sources sort in while the list is shown. The focus keeps its row position instead of following
    /// its source (the list would scroll under the user's thumb). Not while a player is open or closing, or a focus
    /// move is pending: those set the focus themselves.
    /// Review Q I2: goes through the checked request path (scroll, set, verify, up to 4 tries), which logs
    /// "Platz gehalten: Zeile n (Versuch k)" only once the focus is verified there, else "nicht gesetzt". A newer
    /// batch replaces a pending keep request and measures from its target; other requests are never replaced.
    private func keepFocusPosition(old: [String], new: [String]) {
        guard playing == nil, closedPlayer == nil else { return }
        let pending = focusRequest?.keep == true ? focusRequest : nil
        guard focusRequest == nil || pending != nil else { return }
        // Pending keep move: measure from its target, unless the user has moved on (review Q N2).
        let focused = pending.flatMap { p in focusedStream == nil || focusedStream == p.from ? p.id : nil } ?? focusedStream
        guard let id = SourceFocus.keepPosition(focused: focused, old: old, new: new) else { return }
        focusRequest = SourceFocusRequest(id: id, index: new.firstIndex(of: id) ?? 0, reason: "Platz gehalten",
                                          delayMs: 0, keep: true,
                                          from: pending != nil && focused == pending?.id ? pending?.from : focused)
    }

    private func setFilter(_ chips: Set<SourceFilterChip>) {
        filter = chips
        filterTouched = true
        let names = chips.map(\.label).sorted().joined(separator: ", ")
        RemoteLog.info("quellen", "Filter \(names.isEmpty ? "aus" : names) → \(visibleIDs.count) von \(streams.count)")
    }

    /// Review Q I1: a chosen chip the current list no longer has (next episode without DV) drops out; the
    /// selection falls back to "Alle".
    private func dropMissingChips() {
        guard !filter.isEmpty else { return }
        let gone = SourceFilter.dropped(filter, options: filterOptions)
        guard !gone.isEmpty else { return }
        filter = []
        RemoteLog.info("quellen", "Filter \(gone.map(\.label).sorted().joined(separator: ", ")) fehlt in der Liste → Alle")
    }

    /// Review Q M2: "Filter aufheben" disappears with the filter, so the focus goes to the first playable row.
    private func clearFilterToList() {
        setFilter([])
        let ids = visibleIDs
        guard let id = SourceFocus.entry(ids: ids, lastPlayed: nil, isPlayable: focusPlayable) else { return }
        requestFocus(id, in: ids, reason: "Filter aufgehoben", delayMs: 0)
    }

    private func requestFocus(_ id: String, in ids: [String], reason: String, delayMs: Int) {
        focusRequest = SourceFocusRequest(id: id, index: ids.firstIndex(of: id) ?? 0, reason: reason, delayMs: delayMs)
    }

    /// Nächste Quelle (Liste in kluger Ordnung): zuerst gecachte (⚡) unterhalb, dann gecachte oberhalb, zuletzt unbekannte; nie sicher ungecachte (🎫/⏳).
    func fallbackCandidate(after i: Int, in list: [StreamItem]) -> StreamItem? {
        let order = Array(list[(i + 1)...]) + Array(list[..<i])
        let open = order.filter { !failed.contains($0.id) && $0.url != nil
            && !PlaybackStability.shared.isRecentlyFailed($0, title: (current ?? request).id) }   // Welle C-a: 8-h-Gedächtnis
        return open.first { StreamTraits.parse($0).cached == true } ?? open.first { StreamTraits.parse($0).cached == nil }
    }

    /// Wave P-b: what the player's side panel may do with this list (other source, other episode).
    func sidePanelLinks(for s: StreamItem) -> PlayerSideLinks {
        PlayerSideLinks(stream: s, addon: streams.first { $0.stream.id == s.id }?.addon ?? autoNext.addons[s.id],
                        sources: { streams }, failed: { failed },
                        switchSource: { next, held in
                            fallbacks = 0; AutoNextState.userInput($autoNext); autoNext.ask = nil
                            playing = nil
                            Task {
                                try? await Task.sleep(for: .milliseconds(900))
                                guard playing == nil else { return }
                                PlaybackStability.shared.timing.markTap()
                                sideStart = (next.id, held)
                                playing = next
                            }
                        },
                        playEpisode: { next in
                            AutoNextState.userInput($autoNext); autoNext.ask = nil
                            playing = nil
                            startNext(next, after: s, auto: false)
                        })
    }

    /// Quelle versagt → nächste noch nicht gescheiterte Quelle darunter, höchstens 3 automatische Wechsel.
    func fallback(from s: StreamItem, reason: String) {
        failed.insert(s.id)
        lastFailure = s.id
        autoSwitchScheduled = false
        playing = nil
        // Welle E-b: Rückfall in kluger Ordnung (Dekoder, Sprache, Cache), auch wenn die Liste wie das Addon sortiert ist.
        let list = model.autoOrderedStreams(streams).map(\.stream)
        guard fallbacks < 3, let i = list.firstIndex(where: { $0.id == s.id }),
              let next = fallbackCandidate(after: i, in: list) else {
            nextNote = "\(reason). Bitte eine andere Quelle wählen."
            RemoteLog.info("player", "Kein automatischer Wechsel mehr (\(fallbacks) versucht)")
            return
        }
        fallbacks += 1
        autoSwitchScheduled = true
        nextNote = "\(reason) – versuche nächste Quelle (\(fallbacks)/3) …"
        RemoteLog.info("player", "Wechsel \(fallbacks)/3 auf: \(next.name ?? "") \(next.title?.prefix(60) ?? "")")
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            // Inzwischen von Hand eine Quelle gestartet: den laufenden Player nicht ersetzen.
            guard playing == nil else { return }
            playing = next
        }
    }

    /// Folge zu Ende → nächste Folge mit gleichem Release starten (Spec §6 Player: nächste Folge).
    /// Nach N automatischen Folgen ohne Tastendruck erst „Noch da?“ fragen.
    func ended(_ stream: StreamItem, autoplay: Bool = true) {
        playing = nil
        guard autoplay, model.profile.autoplayNext, let next = (current ?? request).nextRequest else { return }
        if autoNext.promptDue(model.profile) {
            RemoteLog.info("player", "Noch da?: nach \(autoNext.counter.autoStarts) automatischen Folgen, vor \(next.title)")
            // Erst nach dem Schließen des Players zeigen (Alert während der Cover-Animation geht verloren).
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                // Inzwischen von Hand eine Quelle gestartet oder Zähler zurückgesetzt: keine veraltete Abfrage.
                guard playing == nil, autoNext.promptDue(model.profile) else { return }
                autoNext.ask = StillWatchingAsk(stream: stream, next: next)
            }
            return
        }
        // Nur der Tastendruck, der diesen Start auslöst („Klick: jetzt“, ≤ 1,5 s vorher), macht ihn zu einem von Hand.
        startNext(next, after: stream, auto: !autoNext.counter.startIsManual())
    }

    /// Quellen der nächsten Folge holen und die zum laufenden Release passende starten (Rückfall: Listenreihenfolge).
    func startNext(_ next: PlayRequest, after stream: StreamItem, auto: Bool) {
        nextNote = "Nächste Folge wird gesucht: \(next.title) …"
        let ref = autoNext.releaseProfile(stream, listAddon: streams.first { $0.stream.id == stream.id }?.addon)
        Task {
            // Welle E-b: Wahl in kluger Ordnung, angezeigt wird die Liste nach „Quellen sortieren“.
            let fetched = await model.streamsForAutoplay(type: next.type, id: next.id)
            let list = model.autoOrderedStreams(fetched)
            // Während der Suche von Hand eine Quelle gestartet: Liste und Folge so lassen, nichts ersetzen.
            guard playing == nil else { nextNote = nil; return }
            guard let s = nextEpisodeStream(PlaybackStability.shared.autoCandidates(list, title: next.id), matching: ref) else {
                nextNote = nextEpisodeStream(list, matching: ref) != nil ? "Nur zuletzt fehlgeschlagene Quellen für \(next.title) – bitte wählen."
                                                                         : "Keine Quelle für \(next.title) gefunden."; return
            }
            let addon = list.first { $0.stream.id == s.id }?.addon
            RemoteLog.info("player", "Nächste Folge: \(addon ?? "?") · \(s.name ?? "") · Nähe \(ref.score(s, addon: addon))\(s.behaviorHints?.bingeGroup == ref.bingeGroup && ref.bingeGroup != nil ? " (bingeGroup)" : "")")
            if let addon { autoNext.addons[s.id] = addon }
            if auto { autoNext.counter.autoStarted() }
            nextNote = nil
            current = next
            // Liste zeigt jetzt die Quellen dieser Folge: Auswahl von Hand und Rückfall arbeiten auf ihr.
            streams = model.orderedStreams(fetched)
            failed = []
            fallbacks = 0
            try? await Task.sleep(for: .milliseconds(800))
            guard playing == nil else { return }
            playing = s
        }
    }
}

/// Fokuswunsch der Quellenliste; jede Anfrage ist neu (`token`), auch für dieselbe Zeile.
struct SourceFocusRequest: Equatable {
    let id: String
    let index: Int
    let reason: String
    let delayMs: Int
    /// Wave Q: keep-position move while sources arrive (a newer batch may replace it).
    var keep = false
    /// Keep move: the source the focus was on when the move began (a different focus means a key press).
    var from: String? = nil
    let token = UUID()
}

/// X3: Kopfzeile der Quellenliste „161 Quellen · 8,4 s“ (Dauer = längste Addon-Antwort der laufenden Suche).
/// Eigene View, damit nur sie dem Suchstand folgt, nicht die ganze Liste.
struct StreamListSummaryLine: View {
    @ObservedObject private var status = StreamSearchStatus.shared
    let id: String
    let count: Int

    var body: some View {
        Text(StreamListSummary.text(count: count, milliseconds: status.progress[id]?.elapsedMilliseconds))
            .textRole(.rowDetail)
    }
}

func timeText(_ s: Double) -> String {
    let t = Int(max(0, s)); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
