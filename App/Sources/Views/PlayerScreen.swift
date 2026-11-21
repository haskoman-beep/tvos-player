import SwiftUI
import Combine
import PlayerCore

/// Vollbild-Player. Kennt nur `PlaybackEngine`; das Backend ist austauschbar.
struct PlayerScreen: View {
    @EnvironmentObject var model: AppModel
    let url: URL
    let request: PlayRequest
    var headers: [String: String] = [:]
    /// true = nächste Folge darf automatisch starten.
    var onEnded: (Bool) -> Void = { _ in }
    /// Quelle taugt nicht (Platzhalter, Fehler nach Neustart): nächste Quelle versuchen.
    var onFallback: (String) -> Void = { _ in }
    /// Trailer: kein Fortschritt, kein Scrobble, kein Up-next, kein Fortsetzen.
    var isTrailer = false
    /// Adresse ist ein entferntes HLS-Master (AVPlayer direkt, ohne Demuxer-Probe).
    var remoteHLS = false
    /// Jeder Tastendruck im Player („Noch da?“-Zähler zurücksetzen).
    var onUserInput: () -> Void = {}
    /// „Noch da?“ steht an: kein Up-next-Countdown, die Abfrage kommt nach dem Ende.
    var holdsUpNext = false
    /// Welle C-a: Urteil über die laufende Quelle (fehlgeschlagen / Platzhalter / stabil) für das 8-h-Gedächtnis.
    var onSourceVerdict: (SourceVerdict) -> Void = { _ in }
    /// Dateiname der Quelle (`behaviorHints.filename`) für den Untertitel-Abgleich; nil = aus der Adresse.
    var releaseName: String? = nil
    /// Welle D-a: eigener Fortschritt (TorBox-Dateien): Startstelle und Ablage statt ProgressBook; Profil-Einstellungen
    /// für Plattencache, Ton und Bild gelten dann wie bei Filmen, sonst bleibt es beim Trailer-Verhalten.
    var ownProgress: OwnProgress? = nil
    @State private var backend: AetherBackend?
    @State private var initError: String?
    /// Kennzeichen beim Vorladen: solange ein Player offen ist, keine Vorlade-Abfragen.
    @State private var prefetchToken = UUID()
    /// Spur-Panel (fullScreenCover) offen: ein onDisappear dabei ist kein Verlassen des Players.
    @State private var tracksOpen = false

    var body: some View {
        Group {
            if let backend { PlayerControls(engine: backend, url: url, title: request.title, profile: model.profile,
                                                       start: ownProgress != nil ? ownProgress?.start : (isTrailer ? nil : model.progress.resumePosition(for: request.id)),
                                                       startFraction: isTrailer || ownProgress != nil ? nil : model.progress.resumeFraction(for: request.id),
                                                       runtimeMinutes: request.runtimeMinutes,
                                                       heading: PlayerHeading(request),
                                                       checksPlaceholder: !isTrailer,
                                                       fallsBackOnLoadError: isTrailer,
                                                       prefs: LoadPrefs(audioLanguages: model.profile.audioPriority.filter { $0 != "orig" },
                                                                        // Untertitel bewusst ohne Engine-Vorwahl: SubtitlePicker wählt nach dem Laden.
                                                                        subtitleLanguages: [],
                                                                        headers: headers, nativeRemoteHLS: remoteHLS,
                                                                        diskCache: isTrailer && ownProgress == nil ? nil : model.profile.diskCache,
                                                                        audio: isTrailer && ownProgress == nil ? nil : model.profile.audioShaping,
                                                                        display: isTrailer && ownProgress == nil ? nil : model.profile.displayMode),
                                                       report: { pos, dur in
                                                           if let ownProgress { ownProgress.record(pos, dur) }
                                                           else if !isTrailer { model.recordProgress(request, position: pos, duration: dur) }
                                                       },
                                                       // Ausgang bei offenem Panel: danach ist onDisappear echt.
                                                       onEnded: { tracksOpen = false; onEnded($0) },
                                                       onFallback: { tracksOpen = false; onFallback($0) },
                                                       onPause: { if !isTrailer { model.scrobblePause(request) } },
                                                       nextTitle: !isTrailer && !holdsUpNext && model.profile.autoplayNext ? request.nextRequest?.title : nil,
                                                       onNextSoon: {
                                                           guard let n = request.nextRequest else { return }
                                                           Task { _ = await model.streams(type: n.type, id: n.id) }
                                                       },
                                                       addonSubtitles: { await model.addonSubtitles(for: request, media: url, headers: headers, enabled: !isTrailer) },
                                                       onTracksShown: { tracksOpen = $0 },
                                                       reresolve: { isTrailer ? nil : await model.freshStream(for: request) },
                                                       skipLookup: { isTrailer ? nil : await model.introDBQuery(for: request) },
                                                       onUserInput: onUserInput,
                                                       onSourceVerdict: isTrailer ? { _ in } : onSourceVerdict,
                                                       releaseName: releaseName,
                                                       trackMemory: memoryKey.flatMap { PlayerMemory.shared.trackMemory(profile: model.profile.id, key: $0) },
                                                       onRemember: memoryKey.map { key -> (TrackMemoryChange) -> Void in
                                                           { change in PlayerMemory.shared.remember(change, key: key, profile: model.profile.id) }
                                                       }) }
            else { Text(initError ?? "Player wird gestartet …") }
        }
        .onDisappear {
            // Öffnet das Spur-Panel (fullScreenCover) und löst onDisappear aus: Vorlader bleibt gesperrt,
            // kein Wiedergabe-Ende melden.
            guard !tracksOpen else { return }
            StreamPrefetcher.shared.playerDisappeared(prefetchToken)
            if !isTrailer { model.endPlayback(request) }
        }
        .onAppear {
            // Beim Vorlader immer anmelden (onDisappear meldet ab), das Backend aber nur einmal anlegen.
            StreamPrefetcher.shared.playerAppeared(prefetchToken)
            guard backend == nil else { return }
            do { backend = try AetherBackend() } catch { initError = "Player-Start fehlgeschlagen: \(error)"; RemoteLog.error("player", initError ?? "") }
        }
    }

    /// Spur-Wahl je Serie/Film (Welle D-a): nil = aus (Einstellung) oder Trailer.
    private var memoryKey: String? {
        guard model.profile.player.rememberTracks, !isTrailer || ownProgress != nil else { return nil }
        return TrackMemoryBook.key(itemID: request.item.id)
    }
}

struct PlayerControls<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let url: URL
    let title: String
    let profile: Profile
    let start: Double?
    var startFraction: Double? = nil
    var runtimeMinutes: Double? = nil
    /// Kopfzeile der Steuerleiste (Serienname + Folge); nil = `title`.
    var heading: PlayerHeading? = nil
    /// Trailer sind kurz: keine Platzhalter-Erkennung.
    var checksPlaceholder = true
    /// Laden fehlgeschlagen → onFallback statt Fehlertext stehen lassen (Trailer: zurück zur Detailseite mit Hinweis).
    var fallsBackOnLoadError = false
    var prefs = LoadPrefs()
    let report: (Double, Double) -> Void
    let onEnded: (Bool) -> Void
    var onFallback: (String) -> Void = { _ in }
    var onPause: () -> Void = {}
    /// Titel der nächsten Folge (nil = kein Up-next).
    var nextTitle: String? = nil
    /// Kurz vor Ende: Quellen der nächsten Folge vorab holen.
    var onNextSoon: () -> Void = {}
    /// Untertitel aus Addons holen (nil = keine; Ergebnis nil = kein Untertitel-Addon installiert).
    var addonSubtitles: (@MainActor () async -> [AddonSubtitle]?)? = nil
    /// Spur-Panel auf/zu (für PlayerScreen: onDisappear bei offenem Panel ist kein Verlassen).
    var onTracksShown: (Bool) -> Void = { _ in }
    /// Abgelaufenen Link derselben Quelle neu auflösen (nil = geht nicht, z. B. Trailer).
    var reresolve: (@MainActor () async -> (url: URL, headers: [String: String])?)? = nil
    /// Fehlerleiter, TV-aus-Verhalten, Fehlermeldung, neu aufgelöster Link (Logik in PlayerCore, PlayerLifecycle.swift).
    @State private var recoveryPlan = RecoveryPlanner()
    @State var life = PlaybackLifecycle()
    @State var lifeTask: Task<Void, Never>?
    @State private var failureNotice: String?
    @State private var resolvedURL: URL?
    /// Ladewünsche mit den Kopfzeilen der neu aufgelösten Quelle (nil = `prefs`).
    @State private var resolvedPrefs: LoadPrefs?
    /// Nach dem Hintergrund: Engine hat das Bild freigegeben, Neuaufbau erst beim Play-Druck (PlayerLifecycle.swift).
    @State var restorePending = false
    @State var restoring = false
    /// IntroDB-Abfrage für „Intro überspringen“ (nil bzw. Ergebnis nil = keine, z. B. Trailer); Kapitel gelten immer.
    var skipLookup: (@MainActor () async -> IntroDBQuery?)? = nil
    /// Sprungbereiche, Überspringen-Knopf, Abspann-Zeitpunkt (`skip.upNextAt`); SkipSegmentButton.swift.
    @StateObject private var skip = SkipSegmentController()
    /// Fokus der Spielerfläche; geht zurück, sobald der Überspringen-Knopf verschwindet.
    @FocusState private var surfaceFocused: Bool
    /// Jeder Tastendruck („Noch da?“-Zähler).
    var onUserInput: () -> Void = {}
    /// Welle C-a: Urteil über die Quelle (PlayerStability.swift); Lade-Wächter, Netz-Warten, Startzeiten.
    var onSourceVerdict: (SourceVerdict) -> Void = { _ in }
    @State var stab = PlayerStabilityState()
    @ObservedObject var stability = PlaybackStability.shared
    /// Dateiname der Quelle für den Untertitel-Abgleich (AddonSubtitleLoader); nil = aus der Adresse.
    var releaseName: String? = nil
    /// Welle D-a: gemerkte Spur-Wahl dieses Titels (nil = keine) und Rückruf für neue Wahlen im Panel.
    var trackMemory: TrackMemory? = nil
    var onRemember: ((TrackMemoryChange) -> Void)? = nil
    @State var subtitleMemoryPending = false
    /// Bildschirmschoner-Regel (PlayerPictureSound.swift).
    @State var idle = IdleTimerPolicy()
    @State var idleToken = UUID()
    /// Laufende Addon-UT-Abfrage; abgebrochen beim Verlassen und vor dem Neuladen.
    @State var addonSubTask: Task<Void, Never>?
    /// Laufendes Neuladen nach einem Fehler; abgebrochen beim Verlassen.
    @State var recoverTask: Task<Void, Never>?
    /// Laden und Start; läuft einmal (ein onAppear nach dem Spur-Panel lädt nicht neu), abgebrochen beim Verlassen.
    /// Intern auch für PlayerExit.swift (Abbruch beim geordneten Ausstieg).
    @State var loadTask: Task<Void, Never>?
    /// Addon-URL je angelegter Addon-UT-Spur (ID → URL): Wiederwahl nach dem Neuladen, keine Dubletten.
    @State var addonTrackURLs: [Int: String] = [:]
    /// Player wird verlassen (Menü, Ende, nächste Quelle): onDisappear ist dann echt, auch bei offenem Panel.
    @State var leaving = false
    @State private var upNext: Int?
    @State private var upNextCancelled = false
    @State private var nextPrefetched = false
    @Environment(\.dismiss) var dismiss
    @State private var showOverlay = true
    @State private var showTracks = false
    @State private var hideTask: Task<Void, Never>?
    @State private var loadError: String?
    @State private var tick = 0
    @State private var fractionApplied = false
    /// Gesammeltes Sprungziel: mehrere ±10-s-Drücke werden zu einem Sprung (Muxer-Neustarts sparen).
    /// Intern auch für PlayerScrub.swift (`confirmScrub`); sonst nur hier setzen.
    @State var pendingSeek: Double?
    @State var seekTask: Task<Void, Never>?
    @State private var lastToggle = Date.distantPast
    @State private var lastGoodTime: Double = 0
    /// Gemessene Höhe der Steuerleiste (nil = noch nicht gemessen), für das Untertitel-Overlay.
    @State private var controlsHeight: CGFloat?
    /// Spulen über die Touchfläche (PlayerScrub.swift) und schwarze Abdeckung (Ausstieg/Rückkehr, PlayerExit.swift).
    @StateObject var scrub = ScrubController()
    @State var blackCover = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            engine.surface().ignoresSafeArea()
            engine.subtitleLayer(controlsInset: showOverlay ? (controlsHeight ?? SubtitleOverlayView.fallbackControlsInset) : 0)
            PlayerLoadingSteps(engine: engine)
            PlayerNetworkBanner(text: stab.networkNotice)
            if let e = loadError ?? engine.errorText {
                // Auch auf dem Bildschirm ohne Schlüssel/volle Adressen (Fotos, Bildschirmfotos).
                Text("Fehler: \(LogRedact.text(e))").padding(30).background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
            if showOverlay {
                // Höhe der Steuerleiste (Titel, Folge, Plaketten, Zeitleiste, Hinweis) → controlsInset der Untertitel.
                overlay.transition(.opacity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
            }
            if let n = upNext, let t = nextTitle { upNextCard(n, t).transition(.move(edge: .trailing).combined(with: .opacity)) }
            SkipSegmentButton(controller: skip, engine: engine, lookup: skipLookup,
                              onBeforeSkip: {
                                  guard !leaving else { return false }   // geordneter Ausstieg: kein Sprung auf die stoppende Engine
                                  onUserInput()  // Klick auf den Knopf ist ein Tastendruck („Noch da?“)
                                  seekTask?.cancel(); pendingSeek = nil
                                  // Wie queueSeek: Bild nach dem Hintergrund freigegeben, erst Play baut neu auf.
                                  guard !restorePending, !restoring else { RemoteLog.info("player", "Überspringen gesperrt bis Play/Neuaufbau (nach Hintergrund)"); return false }
                                  return true
                              })
            ScrubPreviewCard(controller: scrub, duration: engine.duration, current: engine.currentTime)
            if blackCover { Color.black.ignoresSafeArea() }
        }
        // Steht der Überspringen-Knopf, bekommt er den Fokus; Befehle unten erreichen die Fläche weiterhin.
        .focusable(skip.prompt == nil)
        .focused($surfaceFocused)
        .onChange(of: skip.prompt) { _, p in if p == nil { surfaceFocused = true } }
        .onPlayPauseCommand { guard !leaving else { return }; onUserInput(); if scrub.isActive { confirmScrub(); return }; togglePlay() }
        .onTapGesture {   // Klick auf das Touchpad (Mitte) pausiert ebenfalls
            guard !leaving else { return }   // geordneter Ausstieg läuft (schwarz): keine Eingaben mehr
            if scrub.isActive { onUserInput(); confirmScrub(); return }   // Select bestätigt das Spulen
            // Select auf dem Überspringen-Knopf überspringt nur, kein zusätzliches Pausieren.
            guard skip.prompt == nil else { return }
            onUserInput(); togglePlay()
        }
        .onMoveCommand { dir in
            guard !leaving else { return }
            onUserInput()
            if upNext != nil {
                withAnimation { upNext = nil }; upNextCancelled = true
                RemoteLog.info("player", "Up-next abgebrochen"); return
            }
            // Beim Spulen verschieben ◀/▶ das Ziel; kurz nach einer Wischbewegung zählen sie nicht als Sprung.
            if scrub.isActive { if dir == .left { scrub.nudge(-10) } else if dir == .right { scrub.nudge(10) }; poke(); return }
            if dir == .left || dir == .right, scrub.suppressesMove() { return }
            switch dir {
            case .left: queueSeek(-10)
            case .right: queueSeek(10)
            case .down: showTracks = true
            default: break
            }
            poke()
        }
        .onExitCommand {
            guard !leaving else { return }
            if scrub.cancel() { onUserInput(); return }   // Menü bricht zuerst das Spulen ab
            if skip.dismissPrompt() { onUserInput(); return }   // Menü schließt zuerst den Überspringen-Knopf
            leaveWithModeSwitch()   // Abdeckung, Moduswechsel abwarten, dann schließen (PlayerExit.swift)
        }
        .onReceive(timer) { _ in
            tick &+= 1
            if engine.isPlaying, engine.errorText == nil { lastGoodTime = engine.currentTime; recoveryPlan.notePlaying() }
            if tick % 10 == 0 && engine.isPlaying { saveProgress() }
            upNextTick()
            stabilityTick(blocked: failureNotice != nil || loadError != nil)
            idleTick(failed: failureNotice != nil || loadError != nil)
        }
        .onChange(of: engine.loadActivity.hasFirstFrame) { _, f in if f { stabilityFirstFrame() } }
        .onChange(of: stability.isOnline) { _, on in stabilityNetworkChanged(on) }
        .onAppear {
            surfaceFocused = true
            scrub.attach(engine: engine,
                         canScrub: { !leaving && !showTracks && upNext == nil && skip.prompt == nil && failureNotice == nil
                                     && !restorePending && !restoring && engine.duration > 0 && engine.errorText == nil },
                         edges: { SkipSegments.snapEdges(skip.segments) + engine.chapterMarks.map(\.start) })
            idleTick(failed: failureNotice != nil || loadError != nil)
            guard loadTask == nil else { return }
            loadTask = Task { await loadAndStart() }
        }
        .onDisappear {
            saveProgress()
            scrub.detach()
            // Das Spur-Panel (fullScreenCover) kann onDisappear auslösen: dann laufen Laden, Abfrage und
            // Neuladen weiter. Bei einem Ausgang (leave) ist es echt, auch wenn das Panel noch offen ist.
            RemoteLog.info("player", "Verlassen (Panel \(showTracks ? "offen" : "zu")\(leaving ? ", Ausgang" : ""))")
            guard !showTracks || leaving else { return }
            loadTask?.cancel(); addonSubTask?.cancel(); recoverTask?.cancel(); lifeTask?.cancel()
            releaseIdleTimer()
        }
        .onChange(of: engine.errorText) { _, e in
            guard let e else { return }
            RemoteLog.error("player", "Engine: \(e) · \(engine.infoText) · \(engine.errorDetail) · bei \(Int(lastGoodTime))s")
            recover(e)
        }
        .onChange(of: engine.duration) { _, d in
            // Stand aus Trakt/Simkl kennt nur den Anteil: springen, sobald die Laufzeit da ist.
            guard d > 0, !fractionApplied, start == nil, let f = startFraction else { return }
            fractionApplied = true
            Task { await engine.seek(f * d) }
        }
        .onChange(of: engine.isEnded) { _, ended in
            guard ended else { return }
            if engine.duration > 0 { report(engine.duration, engine.duration) }
            finishAtEnd(autoplay: !upNextCancelled)   // HDMI-Modus halten oder geordneter Ausstieg (PlayerExit.swift)
        }
        .onChange(of: showTracks) { _, open in onTracksShown(open) }
        .onChange(of: scrub.isActive) { _, a in if a { onUserInput() }; poke() }
        .onChange(of: scrub.target) { _, _ in poke() }
        .fullScreenCover(isPresented: $showTracks) { PlayerTrackPanel(engine: engine, profile: profile, sourceURL: url, audioLocked: restorePending, onRemember: onRemember) }
        // Play von außen (Siri, Kontrollzentrum) nach dem Hintergrund: erst neu aufbauen.
        .onChange(of: engine.isPlaying) { _, p in if p { stabilityPlaying() }; if p, restorePending { restoreAndPlay() } }
        .onPlayerLifecycle { handlePhase($0) }
        .playbackErrorAlert($failureNotice, chooseOther: { leaveWithModeSwitch() },
                            retry: { recoveryPlan.reset(); life.userResumed(); recover("Erneut versuchen", manual: true) })
    }

    /// Laden, Ton- und UT-Wahl, Start. Läuft als `loadTask` genau einmal je Player.
    private func loadAndStart() async {
        do {
            RemoteLog.info("player", "Laden \(title) · Start \(start.map { Int($0) } ?? 0)s · \(url.host ?? "?")")
            stabilityLoadBegins()
            // Wiederholter Start nach neu aufgelöstem Link: dessen Adresse und Kopfzeilen.
            try await engine.load(resolvedURL ?? url, start: start, prefs: resolvedPrefs ?? prefs)
            // Während des Ladens verlassen (oder Start vom Lade-Wächter abgebrochen): nicht mehr wählen und nicht starten.
            guard !Task.isCancelled, !leaving else { return }
            stabilityLoadEnded()
            if checksPlaceholder, isPlaceholderVideo(duration: engine.duration, expectedRuntimeMinutes: runtimeMinutes) {
                RemoteLog.info("player", "Platzhalter erkannt (\(Int(engine.duration))s, erwartet \(runtimeMinutes.map { Int($0) } ?? 0) min) → nächste Quelle")
                onSourceVerdict(.placeholder)
                engine.stop(); leave { onFallback("Quelle noch nicht bereit (Platzhalter)") }; return
            }
            RemoteLog.info("player", "Geladen · \(Int(engine.duration))s · \(engine.infoText) · Ton: " +
                engine.audioTracks.map { "\($0.id):\($0.language ?? "?")/\($0.channels ?? 0)ch" }.joined(separator: " ") +
                " · UT: \(engine.subtitleTracks.count)")
            // Spur-Gedächtnis (Welle D-a) vor der Automatik, nur wenn die Sprache da ist.
            let best = rememberedAudio() ?? preferredAudioTrack(engine.audioTracks, priority: profile.audioPriority)
            if let best, best.id != engine.activeAudioID {
                engine.selectAudio(best.id)
            }
            // Tonwahl läuft asynchron: die Sprache der gewählten Spur direkt mitgeben (auch an die Addon-UT).
            let startAudio = (best ?? engine.audioTracks.first(where: { $0.id == engine.activeAudioID }))?.language
            engine.subtitlePreferences = SubtitlePreferences(profile: profile)
            if !applyRememberedSubtitles() { engine.reconsiderSubtitles(audioLanguage: startAudio) }
            addonSubTask = Task { await loadAddonSubtitles(audioLanguage: startAudio) }
            RemoteLog.info("player", "Spielt · Tonspur \(engine.activeAudioID.map(String.init) ?? "-") · UT \(engine.activeSubtitleID.map(String.init) ?? "aus") · \(engine.infoText)")
            playUnlessHeld()
            poke()
        } catch {
            // Abgebrochen, weil der Player verlassen wurde: kein Fehlertext, keine nächste Quelle.
            guard !Task.isCancelled, !leaving else { RemoteLog.info("player", "Laden abgebrochen (verlassen oder Neustart)"); return }
            stabilityLoadEnded()
            RemoteLog.error("player", "Laden fehlgeschlagen: \(error)")
            let shown = LogRedact.text("\(error)")
            if fallsBackOnLoadError { engine.stop(); leave { onFallback("Laden fehlgeschlagen: \(shown)") } } else { loadError = shown }
        }
    }

    /// Jeder Ausgang aus dem Player (Menü, Ende, nächste Folge, nächste Quelle) geht hier durch.
    func leave(_ exit: () -> Void) {
        leaving = true
        releaseIdleTimer()   // Bildschirmschoner wieder frei (Welle D-a)
        exit()
    }

    /// Up-next: Karte mit 10-s-Countdown ab Abspannbeginn (`skip.upNextAt`, Welle B-b), sonst 20 s vor Ende;
    /// 2 min vor Ende bzw. 100 s vor der Karte vorladen, dann nächste Folge.
    private func upNextTick() {
        guard nextTitle != nil, engine.duration > 300, engine.errorText == nil else { return }
        let now = engine.currentTime, rem = engine.duration - now
        // Abspann-Zeitpunkt bei jedem Takt neu lesen (Kapitel/IntroDB kommen später); nie später als die alte Regel.
        let cardAt = min(skip.upNextAt ?? .greatestFiniteMagnitude, engine.duration - 20)
        // Vor den Abspann zurückgespult: abgebrochenes Up-next gilt wieder.
        if upNextCancelled, now < cardAt - 20 { upNextCancelled = false }
        if rem < 120 || now >= cardAt - 100, !nextPrefetched { nextPrefetched = true; onNextSoon() }
        if let n = upNext {
            if now < cardAt - 20 { withAnimation { upNext = nil } }   // zurückgespult
            else if engine.isPlaying { if n <= 1 { startNext() } else { upNext = n - 1 } }
        } else if now >= cardAt, rem > 0, engine.isPlaying, !upNextCancelled {
            let fromCredits = cardAt < engine.duration - 20 ? " · ab Abspann \(Int(cardAt))s" : ""
            RemoteLog.info("player", "Up-next: \(nextTitle ?? "")\(fromCredits)")
            withAnimation { upNext = 10 }
        }
    }

    private func startNext() {
        guard !leaving else { return }
        upNext = nil
        if engine.duration > 0 { report(engine.duration, engine.duration) }
        RemoteLog.info("player", "Nächste Folge startet")
        stopBeforeNext(true)
        leave { onEnded(true) }
    }

    private func upNextCard(_ n: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nächste Folge in \(n) s").font(.headline)
            Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Text("Klick: jetzt · Wischen: abbrechen").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28).frame(width: 560, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var overlay: some View {
        let _ = tick
        let d = max(engine.duration, 1)
        let pos = scrub.isActive ? scrub.target : (pendingSeek ?? engine.currentTime)
        return VStack(alignment: .leading, spacing: 14) {
            Text(heading?.title ?? title).font(.title3.bold())
            if let ep = heading?.episodeLine { Text(ep).font(.callout).foregroundStyle(.secondary) }
            PlayerInfoBadges(engine: engine)
            PlayerTimeline(position: min(pos, d), duration: d, marks: SkipSegments.timelineMarks(skip.segments, duration: engine.duration),
                           scrubTarget: scrub.isActive ? scrub.target : nil, current: engine.currentTime)
            HStack {
                Text(fmt(pos)); Spacer()
                if engine.duration > 0, let end = MediaLabels.endTime(remaining: d - pos) {
                    Text(end).foregroundStyle(.secondary)
                }
                Text("-" + fmt(d - pos))
            }
            .font(.caption.monospacedDigit())
            Text("◀▶ 10 s · Wischen/Rand drehen: spulen · ▼ Ton/Untertitel · ⏯ Pause · Zurück beenden").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(60)
        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
    }

    private func togglePlay() {
        guard !leaving else { return }
        // Ein Druck kann doppelt ankommen (Play/Pause-Taste + Systembefehl): zweiten innerhalb 350 ms ignorieren.
        let now = Date()
        if now.timeIntervalSince(lastToggle) < 0.35 { RemoteLog.info("player", "Play/Pause doppelt, ignoriert"); return }
        lastToggle = now
        life.userResumed()
        if upNext != nil { startNext(); return }
        let before = engine.stateText
        if engine.errorText != nil { recoveryPlan.reset(); recover("Neuer Versuch per Play/Pause", manual: true); return }
        if restorePending { restoreAndPlay(); poke(); return }
        engine.togglePlayPause()
        RemoteLog.info("player", "Play/Pause gedrückt · Zustand vorher \(before)")
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            RemoteLog.info("player", "Play/Pause · Zustand danach \(engine.stateText)")
            if !engine.isPlaying { saveProgress(); onPause() }
        }
        poke()
    }

    /// ±10 s sammeln und nach 450 ms einmal springen.
    private func queueSeek(_ delta: Double) {
        guard !leaving else { return }
        // Bild nach dem Hintergrund freigegeben: erst Play baut neu auf (ein Neuaufbau würde von selbst starten).
        guard !restorePending, !restoring else { RemoteLog.info("player", "Sprung gesperrt bis Play/Neuaufbau (nach Hintergrund)"); return }
        let base = pendingSeek ?? engine.currentTime
        let limit = engine.duration > 10 ? engine.duration - 5 : .greatestFiniteMagnitude
        let target = min(max(0, base + delta), limit)
        pendingSeek = target
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            RemoteLog.info("player", "Sprung \(Int(engine.currentTime)) → \(Int(target))s")
            await engine.seek(target)
            pendingSeek = nil
        }
    }

    /// Fehler: einordnen (PlayerCore `RecoveryPlanner`) und je Klasse gleiche Quelle neu laden, Link neu auflösen,
    /// nächste Quelle oder Meldung. `manual`: Nutzer will es erneut versuchen, auch wo die Leiter aufgeben würde.
    /// `failure`: eigener Fehler (Lade-Wächter); `networkBack`: Netz zurück nach `.waitForNetwork` (Welle C-a).
    func recover(_ reason: String, manual: Bool = false, failure given: PlaybackFailure? = nil, networkBack: Bool = false) {
        guard !leaving else { return }
        addonSubTask?.cancel()
        recoveryPlan.canReresolve = reresolve != nil
        let failure = given ?? engine.playbackFailure ?? PlaybackFailure(message: reason)
        let (cls, planned) = networkBack ? (PlaybackErrorClass.offline, recoveryPlan.networkRestored())
                                         : recoveryPlan.next(for: failure, context: stabilityContext())
        var step = planned
        if case .giveUp = planned {
            // Trailer: nie stehen bleiben (zurück zur Detailseite mit Hinweis); Nutzerwunsch: trotzdem versuchen.
            if fallsBackOnLoadError { step = .nextSource } else if manual { step = .retrySame(delay: 0) }
        }
        RemoteLog.info("player", "Fehler eingeordnet: \(cls.rawValue) (\(failure.logText)) → \(step) · Versuch \(recoveryPlan.total)/\(recoveryPlan.maxAttempts) · bei \(Int(lastGoodTime))s")
        // Start hängt noch in engine.load (Lade-Wächter, Netz): abbrechen; neu gestartet wird unten bzw. nach dem Netz.
        // Auch eine angesetzte, noch nicht begonnene Wiederholung (`startPending`, Wartezeit/frischer Link) zählt.
        let startAborted = stab.loadInFlight || stab.startPending
        if startAborted { loadTask?.cancel(); stabilityLoadEnded() }
        switch step {
        case .nextSource:
            onSourceVerdict(SourceVerdict.forNextSource(cls, failureKind: failure.kind, reachedFirstFrame: stab.firstFrameSeen))
            saveProgress(); engine.stop(); leave { onFallback("\(cls.label): \(reason)") }; return
        case .giveUp(let message):
            if startAborted { stab.startPending = true }   // „Erneut versuchen“ wiederholt dann den ganzen Start
            saveProgress(); failureNotice = message; return
        case .waitForNetwork(let message):
            saveProgress(); stabilityWaitForNetwork(message, startAborted: startAborted); return
        case .retrySame, .reresolve: break
        }
        // Start war nicht fertig: ganzen Start wiederholen (Ton-/UT-Wahl, Platzhalter-Prüfung), nicht nur neu laden.
        // Bei .reresolve zuerst den frischen Link holen, dann mit ihm den ganzen Start wiederholen.
        if stabilityResumes(startAborted: startAborted) {
            failureNotice = nil; loadError = nil
            recoverTask?.cancel()
            // Bis loadAndStart beginnt (Wartezeit, frischer Link) gilt der Start als offen: ein zweiter Fehler in
            // diesem Fenster wiederholt ebenfalls den ganzen Start statt nur neu zu laden.
            stab.startPending = true
            loadTask = Task {
                if case .retrySame(let delay) = step, delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, !leaving else { return }
                if step == .reresolve {
                    let fresh = await reresolve?()
                    guard !Task.isCancelled, !leaving else { return }
                    guard let fresh else {
                        RemoteLog.info("player", "Kein frischer Link → nächste Quelle")
                        onSourceVerdict(.failed(cls))
                        saveProgress(); engine.stop(); leave { onFallback("\(cls.label): \(reason)") }; return
                    }
                    var freshPrefs = prefs
                    freshPrefs.headers = fresh.headers
                    resolvedURL = fresh.url; resolvedPrefs = freshPrefs
                    RemoteLog.info("player", "Frischer Link · Start wird wiederholt")
                } else {
                    RemoteLog.info("player", "Start wird wiederholt")
                }
                await loadAndStart()
            }
            return
        }
        failureNotice = nil
        // Neu laden baut die Sitzung ohnehin neu auf.
        restorePending = false
        // Vor dem ersten Bild (Fehler beim Start) gilt die gewünschte Startstelle, nicht 0.
        let pos = lastGoodTime > 0 ? lastGoodTime : (start ?? 0)
        // UT-Wahl VOR dem Abbau merken (danach ist sie weg) und nach dem Neuladen wieder setzen. Eine Addon-Spur
        // zusätzlich nach URL (sonst Name und Sprache): nach dem Ersatz-Laden fehlt sie und bekommt beim
        // Neuanlegen eine neue ID.
        let sub = engine.activeSubtitleID, subByUser = engine.subtitleChosenByUser
        let external = ExternalSubtitleRestore(track: engine.subtitleTracks.first { $0.id == sub },
                                               url: sub.flatMap { addonTrackURLs[$0] }, byUser: subByUser)
        let audioLanguage = engine.audioTracks.first { $0.id == engine.activeAudioID }?.language
        recoverTask?.cancel()
        recoverTask = Task {
            var reloaded = false
            if case .retrySame(let delay) = step, delay > 0 {
                RemoteLog.info("player", "Neu laden in \(Int(delay)) s")
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, !leaving else { return }
            }
            if step == .reresolve {
                let fresh = await reresolve?()
                guard !Task.isCancelled, !leaving else { return }
                guard let fresh else {
                    RemoteLog.info("player", "Kein frischer Link → nächste Quelle")
                    onSourceVerdict(.failed(cls))
                    saveProgress(); engine.stop(); leave { onFallback("\(cls.label): \(reason)") }; return
                }
                RemoteLog.info("player", "Frischer Link · load ab \(Int(pos))s")
                var freshPrefs = prefs
                freshPrefs.headers = fresh.headers
                do {
                    try await engine.load(fresh.url, start: pos, prefs: freshPrefs)
                    resolvedURL = fresh.url; resolvedPrefs = freshPrefs; reloaded = true
                }
                catch { await escalate(after: error); return }
            } else {
                do { try await engine.recover() }
                catch {
                    // Inzwischen verlassen (z. B. Menü): kein Ersatz-Laden und keine nächste Quelle.
                    guard !Task.isCancelled, !leaving else { return }
                    RemoteLog.error("player", "reloadAtCurrentPosition fehlgeschlagen: \(error) → load ab \(Int(pos))s")
                    do { try await engine.load(resolvedURL ?? url, start: pos, prefs: resolvedPrefs ?? prefs); reloaded = true }
                    catch { await escalate(after: error); return }
                }
            }
            // Player inzwischen verlassen: nichts mehr wählen, keine Addon-Abfrage starten, nicht weiterspielen.
            guard !Task.isCancelled, !leaving else { return }
            loadError = nil
            // Nach dem Ersatz-Laden sind alle externen Spuren weg, ihre IDs gelten nicht mehr.
            if reloaded { addonTrackURLs = [:] }
            // Externe Spur nach dem Ersatz-Laden (oder wenn sie fehlt) nicht per alter ID setzen: das macht
            // loadAddonSubtitles mit `restore` nach dem Neuanlegen.
            let externalGone = external != nil
                && (reloaded || !engine.subtitleTracks.contains(where: { $0.id == sub && $0.isExternal }))
            if engine.activeSubtitleID != sub, !externalGone {
                if subByUser { engine.selectSubtitle(sub) } else { engine.autoSelectSubtitle(sub) }
            }
            // Addon-UT neu holen, wenn keine externe Spur mehr da ist (Fallback-load verliert sie, oder die
            // Abfrage wurde oben abgebrochen, bevor sie fertig war) oder die aktive fehlt; reloadAtCurrentPosition
            // behält sie. Schon vorhandene URLs legt loadAddonSubtitles nicht doppelt an.
            if externalGone || !engine.subtitleTracks.contains(where: \.isExternal) {
                addonSubTask = Task { await loadAddonSubtitles(audioLanguage: audioLanguage, restore: externalGone ? external : nil) }
            }
            playUnlessHeld()
        }
    }

    /// Ersatz-Laden schlug fehl: die Engine meldet den Fehler meist selbst (onChange → recover bricht diese
    /// Aufgabe ab). Sonst nach kurzer Pause selbst die nächste Stufe der Leiter nehmen (kein doppelter Schritt).
    func escalate(after error: Error) async {
        guard !Task.isCancelled, !leaving else { return }
        RemoteLog.error("player", "Neu laden fehlgeschlagen: \(error)")
        try? await Task.sleep(for: .milliseconds(1500))
        guard !Task.isCancelled, !leaving else { return }
        recover("Neu laden fehlgeschlagen")
    }

    /// Start bzw. Weiterspielen nach dem Laden, außer das System hat pausiert (TV aus, Home-Taste).
    private func playUnlessHeld() {
        if life.holdsPlayback { engine.pause(); RemoteLog.info("player", "Bleibt pausiert (App war inaktiv)") }
        else { engine.play() }
    }

    func saveProgress() {
        guard engine.duration > 0, engine.currentTime > 0 else { return }
        report(engine.currentTime, engine.duration)
    }

    /// Intern auch für PlayerScrub.swift (Steuerleiste beim Spulen zeigen).
    func poke() {
        withAnimation { showOverlay = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled && engine.isPlaying && !scrub.isActive { withAnimation { showOverlay = false } }
        }
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(max(0, s)); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
