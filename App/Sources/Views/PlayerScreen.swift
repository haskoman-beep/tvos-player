import SwiftUI
import UIKit
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
    /// Wave P-b: what the side panel may do (other source, other episode); nil = only Kapitel and Infos.
    var sideLinks: PlayerSideLinks? = nil
    /// Wave P-b: held position of a source switch; wins over the saved progress and its thresholds.
    var startOverride: Double? = nil
    @StateObject private var extras = PlayerExtras()   // Wave P-b: side panel and pause card data
    @State private var sideExit: SidePanelExit?
    @State private var backend: AetherBackend?
    @State private var initError: String?
    /// Kennzeichen beim Vorladen: solange ein Player offen ist, keine Vorlade-Abfragen.
    @State private var prefetchToken = UUID()
    /// Spur-Panel (fullScreenCover) offen: ein onDisappear dabei ist kein Verlassen des Players.
    @State private var tracksOpen = false

    var body: some View {
        Group {
            if let backend { PlayerControls(engine: backend, url: url, title: request.title, profile: model.profile,
                                                       start: ownProgress != nil ? ownProgress?.start : (isTrailer ? nil : PlayerStartChoice.choose(held: startOverride, resume: model.progress.resumePosition(for: request.id), fraction: nil).start),
                                                       startFraction: isTrailer || ownProgress != nil || startOverride != nil ? nil : model.progress.resumeFraction(for: request.id),
                                                       runtimeMinutes: request.runtimeMinutes,
                                                       heading: PlayerHeading(request),
                                                       checksPlaceholder: !isTrailer,
                                                       fallsBackOnLoadError: isTrailer,
                                                       prefs: LoadPrefs(audioLanguages: model.profile.audioPriority.filter { $0 != "orig" },
                                                                        // Untertitel bewusst ohne Engine-Vorwahl: SubtitlePicker wählt nach dem Laden.
                                                                        subtitleLanguages: [],
                                                                        headers: headers, nativeRemoteHLS: remoteHLS,
                                                                        diskCache: isTrailer && ownProgress == nil ? nil : model.profile.diskCache,
                                                                        audio: isTrailer && ownProgress == nil ? nil : model.device.audioShaping,
                                                                        display: isTrailer && ownProgress == nil ? nil : model.device.displayMode),
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
                                                       postPlayItem: isTrailer || ownProgress != nil || request.type != "movie" ? nil : request.item,   // wave P-a
                                                       onUserInput: onUserInput,
                                                       onSourceVerdict: isTrailer ? { _ in } : onSourceVerdict,
                                                       releaseName: releaseName,
                                                       trackMemory: memoryKey.flatMap { PlayerMemory.shared.trackMemory(profile: model.profile.id, key: $0) },
                                                       onRemember: memoryKey.map { key -> (TrackMemoryChange) -> Void in
                                                           { change in PlayerMemory.shared.remember(change, key: key, profile: model.profile.id) }
                                                       },
                                                       sideExtras: isTrailer ? nil : extras) }
            else {
                VStack(spacing: Theme.Space.l) {
                    Text(initError ?? "Player wird gestartet …")
                    // N6: Fehlerseite mit Fokusziel; „Zurück“ schließt den Player (zur startenden Seite).
                    if initError != nil { FocusAnchor(kind: .back) }
                }
            }
        }
        .onDisappear {
            PostPlayRoute.flushLater()   // wave P-a: fallback; the stream list runs the route in playerDismissed
            // Öffnet das Spur-Panel (fullScreenCover) und löst onDisappear aus: Vorlader bleibt gesperrt,
            // kein Wiedergabe-Ende melden.
            guard !tracksOpen else { return }
            StreamPrefetcher.shared.playerDisappeared(prefetchToken)
            extras.cancel()   // Wave P-b
            // Wave P-b: a source switch pauses the scrobble (the new player continues it), it never stops it.
            if !isTrailer { if sideExit?.stopsScrobble == false { model.scrobblePause(request) } else { model.endPlayback(request) } }
        }
        .onAppear {
            // Beim Vorlader immer anmelden (onDisappear meldet ab), das Backend aber nur einmal anlegen.
            StreamPrefetcher.shared.playerAppeared(prefetchToken)
            if !isTrailer { extras.attach(model: model, request: request, links: sideLinks?.closing { tracksOpen = false; sideExit = $0 }) }   // Wave P-b
            guard backend == nil else { return }
            do { let b = try AetherBackend(); NowPlayingBridge.stage(b, request: request, skipSeconds: model.profile.player.remoteSkipSeconds); backend = b } catch { initError = "Player-Start fehlgeschlagen: \(error)"; RemoteLog.error("player", initError ?? "") }
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
    /// Intern auch für PlayerStability.swift (gesunde Spielzeit, W-A-9).
    @State var recoveryPlan = RecoveryPlanner()
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
    /// Wave P-a: the movie for the card after the movie (nil = episode, trailer, own file).
    var postPlayItem: MetaPreview? = nil
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
    /// Wave P-b: side panel and pause card (PlayerSidePanel.swift, PlayerPauseCard.swift); nil = trailer.
    var sideExtras: PlayerExtras? = nil
    @State var sideOpen = false
    @State var sideAfterClose: (@MainActor () -> Void)?
    /// Source switch from the side panel: record no progress on the way out (`SidePanelExit.sourceSwitch`).
    @State var sideHoldsProgress = false
    /// When a panel last closed (uptime), for the side panel's quiet time.
    @State var lastPanelClose: Double?
    @StateObject var pauseCard = PauseCardState()
    @State var subtitleMemoryPending = false
    /// Bildschirmschoner-Regel (PlayerPictureSound.swift).
    @State var idle = IdleTimerPolicy()
    @State var idleToken = UUID()
    /// Laufende Addon-UT-Abfrage; abgebrochen beim Verlassen und vor dem Neuladen.
    @State var addonSubTask: Task<Void, Never>?
    /// Laufendes Neuladen nach einem Fehler; abgebrochen beim Verlassen.
    @State var recoverTask: Task<Void, Never>?
    /// Welle F-h R1: die Fehlerleiter lädt gerade neu (Spurwahl gesperrt). `recoverGen` zählt die Aufgaben, damit eine
    /// abgelöste alte das Flag der neuen nicht zurücksetzt.
    @State var recovering = false
    @State var recoverGen = 0
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
    /// F-h3 R1: vom Panel (Leiste unten) bzw. Menü gemeldete bedeckte Höhe am unteren Rand; 0 = nichts gemeldet.
    @State private var coverBottom: CGFloat = 0
    /// Welle F-h2 R1: Ton-Neuladen aus dem Panel läuft (sperrt Untertitel/Versatz, `TrackLock.audioSwitching`).
    @State private var audioSwitch = AudioSwitchWatch()
    /// R2 N2: Takt der Zeitgrenzen; als gehaltener Task, nicht `.task`, denn dieses View verschwindet unterm Panel.
    @State private var audioSwitchTick: Task<Void, Never>?
    /// Task 1.8: audio choice at the start differs from the engine's (second session build): target track, time of
    /// the choice and whether the engine has been loading since; ends with the `player.audioReload` line.
    @State private var startAudioReload: (target: Int, at: ContinuousClock.Instant, sawLoading: Bool)?
    @State private var hideTask: Task<Void, Never>?
    @State private var loadError: String?
    @State private var tick = 0
    /// Task 3.2: which start steps run after each successful load (PlayerCore `StartSequence`).
    @State private var startSeq = StartSequence()
    /// Sync fraction jump issued, not yet arrived (target in seconds); nil = none in flight.
    @State private var fractionSeekTarget: Double?
    /// Sync fraction jump waiting for the duration (runs from `onChange(of: engine.duration)`).
    @State private var fractionAwaitingDuration: Double?
    /// Gesammeltes Sprungziel: mehrere ±10-s-Drücke werden zu einem Sprung (Muxer-Neustarts sparen).
    /// Intern auch für PlayerScrub.swift (`confirmScrub`); sonst nur hier setzen.
    @State var pendingSeek: Double?
    @State var seekTask: Task<Void, Never>?
    /// Welle G-a: letzter ◀/▶-Sprung (Richtung, Zeit), damit ein Halten den Sprung desselben Drucks abfängt.
    @State private var lastArrow: (forward: Bool, at: Double)?
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
            engine.subtitleLayer(controlsInset: subtitleInset).environment(\.subtitleStyle, profile.subtitleStyle)
            PlayerLoadingSteps(engine: engine)
            PlayerNetworkBanner(text: stab.networkNotice)
            if let e = loadError ?? engine.errorText {
                // Auch auf dem Bildschirm ohne Schlüssel/volle Adressen (Fotos, Bildschirmfotos).
                Text("Fehler: \(LogRedact.text(e))").padding(30).background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
            // F-h3: Leiste unten bzw. Menü decken den unteren Rand; dann keine Steuerleiste darunter.
            if showOverlay && !panelCoversBottom && !pauseCard.isVisible {
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
                              },
                              // Wave P-a: action per type, cards that cover the credits, jumps without side effects.
                              settings: profile.skip, upNextCard: nextTitle != nil, postPlayItem: postPlayItem,
                              canSkip: { !leaving && !restorePending && !restoring && !showTracks && !sideOpen },   // P-b side panel blocks jumps too
                              onLeave: { leaveWithModeSwitch() })
                .opacity(panelCoversBottom ? 0 : 1)   // F-h3: nicht unter Leiste unten / Menü durchscheinen
            ScrubPreviewCard(controller: scrub, duration: engine.duration, current: engine.currentTime)
            PlayerPauseCardLayer(state: pauseCard, engine: engine, content: sideExtras?.pauseContent,
                                 accessoryContext: pauseAccessoryContext,
                                 blockReason: PauseCardRule.blockReason(panelOpen: showTracks, scrubbing: scrub.isActive,
                                     failure: failureNotice != nil || loadError != nil || engine.errorText != nil, upNext: upNext != nil,
                                     skipPrompt: skip.holdsFocus, loading: engine.isLoading, leaving: leaving || blackCover,
                                     noPicture: !engine.loadActivity.hasFirstFrame || restorePending))   // Wave P-b
            if blackCover { Color.black.ignoresSafeArea() }
        }
        // Steht der Überspringen-Knopf, bekommt er den Fokus; Befehle unten erreichen die Fläche weiterhin.
        .focusable(!skip.holdsFocus)
        .focused($surfaceFocused)
        .onChange(of: skip.holdsFocus) { _, held in if !held { surfaceFocused = true } }
        .onPlayPauseCommand { guard !leaving else { return }; onUserInput(); skip.noteKey(); if scrub.isActive { lastToggle = Date(); confirmScrub(); return }; togglePlay() }   // G-a R1: Doppel als MP-Toggle fällt in den 350-ms-Filter
        .onTapGesture {   // Klick auf das Touchpad (Mitte) pausiert ebenfalls
            guard !leaving else { return }   // geordneter Ausstieg läuft (schwarz): keine Eingaben mehr
            if scrub.isActive { onUserInput(); confirmScrub(); return }   // Select bestätigt das Spulen
            // Select auf dem Überspringen-Knopf überspringt nur, kein zusätzliches Pausieren.
            guard !skip.holdsFocus else { return }
            onUserInput(); togglePlay()
        }
        .onMoveCommand { dir in
            guard !leaving else { return }
            onUserInput()
            if skip.noteKey() { return }   // wave P-a: stops a skip countdown; the card after a movie takes the arrows
            if upNext != nil {
                withAnimation { upNext = nil }; upNextCancelled = true
                RemoteLog.info("player", "Up-next abgebrochen"); return
            }
            // Beim Spulen verschieben ◀/▶ das Ziel; kurz nach einer Wischbewegung zählen sie nicht als Sprung.
            if scrub.isActive { if dir == .left { scrub.nudge(-10) } else if dir == .right { scrub.nudge(10) }; poke(); return }
            if dir == .left || dir == .right, scrub.suppressesMove() { return }
            if dir == .left || dir == .right { lastArrow = (dir == .right, ProcessInfo.processInfo.systemUptime) }
            switch dir {
            case .left: queueSeek(-10)
            case .right: queueSeek(10)
            case .down: openTracks(.clickDown)
            case .up: openTracks(.clickUp)
            default: break
            }
            poke()
        }
        .onExitCommand {
            guard !leaving else { return }
            if scrub.cancel() { onUserInput(); return }   // Menü bricht zuerst das Spulen ab
            if skip.dismissPrompt() { onUserInput(); return }   // Menü schließt zuerst den Überspringen-Knopf
            if pauseCard.dismiss() { onUserInput(); poke(); return }   // Wave P-b: Menu closes only the pause card
            // N5 (Welle F-c): offene Überlagerung schließt nur sich selbst, erst bei freiem Bild verlassen.
            switch PlayerMenuStep.decide(upNext: upNext != nil, controlsVisible: showOverlay,
                                         hasPicture: engine.loadActivity.hasFirstFrame,
                                         failed: loadError != nil || engine.errorText != nil) {
            case .cancelUpNext:
                onUserInput()
                withAnimation { upNext = nil }; upNextCancelled = true
                RemoteLog.info("player", "Menu: Up-next abgebrochen")
            case .hideControls:
                onUserInput()
                hideTask?.cancel()
                withAnimation { showOverlay = false }
                RemoteLog.info("player", "Menu: Steuerleiste ausgeblendet")
            case .leave:
                leaveWithModeSwitch()   // Abdeckung, Moduswechsel abwarten, dann schließen (PlayerExit.swift)
            }
        }
        .onReceive(timer) { _ in
            tick &+= 1
            // Gesunde Spielzeit für die Fehlerleiter zählt stabilityTick (nur ohne Puffern, Position läuft; W-A-9).
            if engine.isPlaying, engine.errorText == nil { lastGoodTime = engine.currentTime }
            noteFractionSeekArrival()
            if tick % 10 == 0 && engine.isPlaying { saveProgress() }
            upNextTick()
            stabilityTick(blocked: failureNotice != nil || loadError != nil)
            idleTick(failed: failureNotice != nil || loadError != nil)
        }
        .onChange(of: engine.loadActivity.hasFirstFrame) { _, f in
            guard f else { return }
            let counted = !stab.firstFrameSeen
            stabilityFirstFrame()
            if counted { logFirstFrameMetric() }
        }
        .onChange(of: stability.isOnline) { _, on in stabilityNetworkChanged(on) }
        .onAppear {
            surfaceFocused = true
            scrub.attach(engine: engine,
                         canScrub: { !leaving && !showTracks && upNext == nil && !skip.holdsFocus && failureNotice == nil
                                     && !restorePending && !restoring && engine.duration > 0 && engine.errorText == nil },
                         edges: { SkipSegments.snapEdges(skip.segments) + engine.chapterMarks.map(\.start) },
                         holdAllowed: { !leaving },
                         holdOrigin: { fastSeekOrigin(forward: $0) },
                         holdLimit: { FastSeek.upperLimit(duration: engine.duration, creditsStart: skip.upNextAt, origin: $0) },
                         // F-h2: im offenen Panel ist senkrechtes Wischen ein Listenschritt (kein Öffnen, kein Log-Rauschen).
                         swipe: { if !showTracks { openTracks($0) } },
                         verticalQuiet: { showTracks })
            idleTick(failed: failureNotice != nil || loadError != nil)
            NowPlayingBridge.route(engine, handlers: .init(context: { RemoteTransportContext(isPlaying: engine.isPlaying, isBusy: engine.isLoading, position: pendingSeek ?? engine.currentTime, inputBlocked: leaving || scrub.isActive || showTracks || failureNotice != nil, upNextShowing: upNext != nil, sinceLastPress: Date().timeIntervalSince(lastToggle)) }, toggle: { onUserInput(); togglePlay() }, seekBy: { onUserInput(); queueSeek($0); poke() }))
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
            // Stand aus Trakt/Simkl kennt nur den Anteil: der Startschritt `seek` wartet hier auf die Laufzeit.
            guard d > 0, let f = fractionAwaitingDuration else { return }
            fractionAwaitingDuration = nil
            seekToFraction(f)
        }
        .onChange(of: engine.isEnded) { _, ended in
            guard ended else { return }
            if engine.duration > 0 { report(engine.duration, engine.duration) }
            finishAtEnd(autoplay: !upNextCancelled)   // HDMI-Modus halten oder geordneter Ausstieg (PlayerExit.swift)
        }
        .onChange(of: showTracks) { _, open in if !open { coverBottom = 0; lastPanelClose = ProcessInfo.processInfo.systemUptime }; onTracksShown(open) }
        .onChange(of: scrub.isActive) { _, a in if a { onUserInput() }; poke() }
        .onChange(of: scrub.holdSpeed != nil) { _, h in if h { onUserInput() } }   // G-a R1: Halten zählt als Eingabe
        .onChange(of: scrub.target) { _, _ in poke() }
        .modifier(XRayProbeHook(engine: engine, playing: engine.isPlaying, blocked: leaving || showTracks || scrub.isActive || failureNotice != nil))   // X0: debug face probe on pause (XRayProbeHook.swift)
        .fullScreenCover(isPresented: $showTracks, onDismiss: runSideAfterClose) {
            if sideOpen, let sideExtras { sidePanel(sideExtras) }   // Wave P-b
            else if trackStyle == .menu {
                PlayerTrackMenu(engine: engine, profile: profile, audioLocked: restorePending, shownLock: trackLock,
                                lock: { trackLock }, onAudioSwitch: { beginAudioSwitch($0) }, onRemember: onRemember,
                                onCoverBottom: { coverBottom = $0 })
            } else {
                PlayerTrackPanel(engine: engine, profile: profile, style: trackStyle, sourceURL: url, audioLocked: restorePending,
                                 shownLock: trackLock, lock: { trackLock }, onAudioSwitch: { beginAudioSwitch($0) },
                                 onRemember: onRemember, onCoverBottom: { coverBottom = $0 })
            }
        }
        .onChange(of: engine.isLoading) { _, _ in checkAudioSwitch(); noteStartAudioReload() }
        .onChange(of: engine.activeAudioID) { _, _ in checkAudioSwitch(); noteStartAudioReload() }
        // Play von außen (Siri, Kontrollzentrum) nach dem Hintergrund: erst neu aufbauen.
        .onChange(of: engine.isPlaying) { _, p in if p { stabilityPlaying(); pauseCard.noteInput() }; if p, restorePending { restoreAndPlay() } }
        .onPlayerLifecycle { handlePhase($0) }
        .playbackErrorAlert($failureNotice, chooseOther: { leaveWithModeSwitch() },
                            retry: { recoveryPlan.reset(); life.userResumed(); recover("Erneut versuchen", manual: true) })
    }

    /// Laden, Ton- und UT-Wahl, Start. Läuft als `loadTask` genau einmal je Player.
    private func loadAndStart() async {
        do {
            RemoteLog.info("player", "Laden \(title) · Start \(start.map { Int($0) } ?? 0)s · \(url.host ?? "?")")
            stabilityLoadBegins()
            // Task 1.8: press on the source until loading begins (a stale press is dropped by `markResolved`).
            let timing = PlaybackStability.shared.timing
            if let ms = StartTiming.ms(timing.tapUptime, timing.resolvedUptime) {
                RemoteLog.metric(.playerLoadBegins, ms: ms)
            }
            // Wiederholter Start nach neu aufgelöstem Link: dessen Adresse und Kopfzeilen.
            try await engine.load(resolvedURL ?? url, start: start, prefs: resolvedPrefs ?? prefs)
            // Während des Ladens verlassen (oder Start vom Lade-Wächter abgebrochen): nicht mehr wählen und nicht starten.
            guard !Task.isCancelled, !leaving else { return }
            stabilityLoadEnded()
            runStartSteps(startSeq.afterSuccessfulLoad(isFirst: true, remembered: nil, pendingFraction: syncFraction))
        } catch {
            // Abgebrochen, weil der Player verlassen wurde: kein Fehlertext, keine nächste Quelle.
            guard !Task.isCancelled, !leaving else { RemoteLog.info("player", "Laden abgebrochen (verlassen oder Neustart)"); return }
            stabilityLoadEnded()
            RemoteLog.error("player", "Laden fehlgeschlagen: \(error)")
            let shown = LogRedact.text("\(error)")
            if fallsBackOnLoadError { engine.stop(); leave { onFallback("Laden fehlgeschlagen: \(shown)") } } else { loadError = shown }
        }
    }

    /// Task 3.2: one executor for the start steps of both ways in (loadAndStart and the error ladder).
    /// `audioBefore`: the audio track active before a reload (for `selectAudio(restore:)`).
    private func runStartSteps(_ steps: [StartSequence.Step], audioBefore: TrackMemory.Entry? = nil) {
        RemoteLog.info("player", "Startschritte \(StartSequence.logText(steps))")
        let wholeStart = steps.contains(.placeholderCheck)
        // Tonwahl läuft asynchron: die Sprache der gewählten Spur direkt mitgeben (auch an die Addon-UT).
        var startAudio = engine.audioTracks.first(where: { $0.id == engine.activeAudioID })?.language
        for step in steps {
            switch step {
            case .placeholderCheck:
                if checksPlaceholder, isPlaceholderVideo(duration: engine.duration, expectedRuntimeMinutes: runtimeMinutes) {
                    RemoteLog.info("player", "Platzhalter erkannt (\(Int(engine.duration))s, erwartet \(runtimeMinutes.map { Int($0) } ?? 0) min) → nächste Quelle")
                    onSourceVerdict(.placeholder)
                    engine.stop(); leave { onFallback("Quelle noch nicht bereit (Platzhalter)") }; return
                }
                RemoteLog.info("player", "Geladen · \(Int(engine.duration))s · \(engine.infoText) · Ton: " +
                    engine.audioTracks.map { "\($0.id):\($0.language ?? "?")/\($0.channels ?? 0)ch" }.joined(separator: " ") +
                    " · UT: \(engine.subtitleTracks.count)")
            case .selectAudio(restore: .none):
                // Spur-Gedächtnis (Welle D-a) vor der Automatik, nur wenn die Sprache da ist.
                let best = rememberedAudio() ?? preferredAudioTrack(engine.audioTracks, priority: profile.audioPriority)
                if let best, best.id != engine.activeAudioID {
                    if wholeStart { startAudioReload = (target: best.id, at: ContinuousClock.now, sawLoading: false) }
                    engine.selectAudio(best.id)
                } else if wholeStart {
                    startAudioReload = nil
                    RemoteLog.metric(.playerAudioReload, ms: 0, fields: ["neu": "nein"])
                }
                if let best { startAudio = best.language }
            case .selectAudio(restore: let id?):
                // W-A-3: a fresh load starts with the engine's choice; choose the previous track again (ID, else language).
                let before = audioBefore ?? TrackMemory.Entry(audioID: id, audioLanguage: nil)
                if let t = before.track(in: engine.audioTracks) {
                    if t.id != engine.activeAudioID {
                        engine.selectAudio(t.id)
                        RemoteLog.info("player", "Tonspur wiederhergestellt: \(t.id) · \(t.language ?? "?")")
                    }
                    startAudio = t.language
                } else {
                    RemoteLog.info("player", "Tonspur \(id) (\(before.audioLanguage ?? "?")) nach dem Neuladen nicht da → Engine-Wahl")
                }
            case .subtitleAutomatic:
                engine.subtitlePreferences = SubtitlePreferences(profile: profile)
                if !applyRememberedSubtitles() { engine.reconsiderSubtitles(audioLanguage: startAudio) }
            case .addonSubtitles:
                let audio = startAudio
                addonSubTask = Task { await loadAddonSubtitles(audioLanguage: audio) }
            case .seek(let f):
                if let f { seekToFraction(f) }
            case .play:
                if wholeStart {
                    RemoteLog.info("player", "Spielt · Tonspur \(engine.activeAudioID.map(String.init) ?? "-") · UT \(engine.activeSubtitleID.map(String.init) ?? "aus") · \(engine.infoText)")
                }
                playUnlessHeld()
                if wholeStart { poke() }
            }
        }
    }

    /// Synced fraction (Trakt/Simkl) to jump to; nil = fixed start position or none.
    private var syncFraction: Double? { start == nil ? startFraction : nil }

    /// W-A-4/W-B-4: jump to the synced fraction. Counts as done only once playback ran at the target
    /// (`noteFractionSeekArrival`); until then every reload repeats it (`StartSequence`).
    private func seekToFraction(_ f: Double) {
        let d = engine.duration
        guard d > 0 else { fractionAwaitingDuration = f; return }
        let target = f * d
        fractionSeekTarget = target
        RemoteLog.info("player", "Sprung auf Sync-Anteil \(Int((f * 100).rounded())) % → \(Int(target))s")
        Task { await engine.seek(target) }
    }

    /// Every tick: the fraction jump has arrived when playback runs (no load, no seek) at or behind the target.
    private func noteFractionSeekArrival() {
        guard let t = fractionSeekTarget, engine.isPlaying, engine.errorText == nil, !engine.isLoading,
              !engine.loadActivity.seeking, engine.currentTime >= t - 15 else { return }
        fractionSeekTarget = nil
        startSeq.noteSeekExecuted()
        RemoteLog.info("player", "Sprung auf Sync-Anteil angekommen · bei \(Int(engine.currentTime))s")
    }

    /// Task 1.8: start of loading until the first frame (and from the press, if there was one); once per load.
    private func logFirstFrameMetric() {
        let t = PlaybackStability.shared.timing
        guard let ms = StartTiming.ms(t.resolvedUptime, t.firstFrameUptime) else { return }
        let press = StartTiming.ms(t.tapUptime, t.firstFrameUptime).map { "\($0)" } ?? "-"
        RemoteLog.metric(.playerFirstFrame, ms: ms, fields: ["druck": press])
    }

    /// Task 1.8: the start's audio reload is over once the engine has loaded and plays the chosen track.
    private func noteStartAudioReload() {
        guard var r = startAudioReload else { return }
        if engine.isLoading { r.sawLoading = true; startAudioReload = r; return }
        guard r.sawLoading, engine.activeAudioID == r.target else { return }
        startAudioReload = nil
        RemoteLog.metric(.playerAudioReload, ms: Metric.ms(r.at.duration(to: ContinuousClock.now)), fields: ["neu": "ja"])
    }

    /// Jeder Ausgang aus dem Player (Menü, Ende, nächste Folge, nächste Quelle) geht hier durch.
    func leave(_ exit: () -> Void) {
        leaving = true
        audioSwitchTick?.cancel()
        releaseIdleTimer()   // Bildschirmschoner wieder frei (Welle D-a)
        NowPlayingBridge.detach(engine)   // Now Playing: Befehle sperren, Karte leeren (Welle G-b)
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
            // F-h2 R1 M7: hinter dem offenen Spur-Panel zählt die Karte nicht weiter.
            else if engine.isPlaying, !showTracks { if n <= 1 { startNext() } else { upNext = n - 1 } }
        } else if now >= cardAt, rem > 0, engine.isPlaying, !upNextCancelled, !showTracks {
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
            // Welle F-h: aktuelle Spurwahl und der Weg ins Panel stehen sichtbar in der Leiste.
            if !engine.audioTracks.isEmpty || !engine.subtitleTracks.isEmpty {
                Text(TrackChoice.overlayLine(audio: TrackChoice.active(engine.audioTracks, id: engine.activeAudioID),
                                             subtitle: TrackChoice.active(engine.subtitleTracks, id: engine.activeSubtitleID)))
                    .font(.caption).lineLimit(1)
            }
            if let x = sideExtras { SidePanelHint(trackStyle: trackStyle, pages: x.pages(chapters: engine.chapterMarks.count)) }   // Wave P-b
            Text("◀▶ 10 s · ◀▶ halten: Schnellsuchlauf · waagerecht wischen/Rand drehen: spulen · \(SidePanelGesture.trackHint(trackStyle: trackStyle)) · ⏯ Pause · Zurück beenden").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(60)
        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
    }

    /// Welle F-h3: „Ton & Untertitel öffnen“ (Profil); beim Öffnen gelesen.
    private var trackStyle: TrackPanelStyle { profile.player.trackPanelStyle }

    /// Leiste unten bzw. Menü offen: Steuerleiste und Überspringen-Knopf ausblenden.
    private var panelCoversBottom: Bool { showTracks && (sideOpen || trackStyle.coversBottom) }   // P-b: side panel too

    /// Untertitel über der Steuerleiste; bei offener Leiste unten bzw. offenem Menü darüber (gemessene Höhe, R1 I1/M5).
    /// Gewählt statt das Menü zu verschieben: der Platz unten rechts bleibt wie vereinbart, und die Untertitel bleiben
    /// ganz sichtbar, auch beim Einstellen des Versatzes.
    private var subtitleInset: CGFloat {
        if panelCoversBottom, coverBottom > 0 { return coverBottom }
        return showOverlay && !panelCoversBottom ? (controlsHeight ?? SubtitleOverlayView.fallbackControlsInset) : 0
    }

    /// Welle F-h: Spur-Panel öffnen, per Wisch (Pan-Recognizer der Spul-Steuerung) oder Klick auf den Rand
    /// (`onMoveCommand`); tvOS meldet einen Wisch nicht als Move-Befehl. F-h3: welche Geste öffnet, hängt vom Stil ab.
    private func openTracks(_ gesture: TrackPanelGesture) {
        // Wave P-b: the vertical direction the track style leaves free opens the side panel.
        let side = sideExtras != nil && SidePanelGesture.opens(trackStyle: trackStyle, gesture: gesture)
        if side, !showTracks, let why = SidePanelGesture.holdBack(controlsVisible: showOverlay && !pauseCard.isVisible,
                                                                 sincePanelClosed: lastPanelClose.map { ProcessInfo.processInfo.systemUptime - $0 }) {
            RemoteLog.info("player", "Seitenpanel nicht geöffnet (\(gesture.logText)): \(why)")
            poke()   // the press shows the control bar (a swipe does not reach onMoveCommand's poke)
            return
        }
        let via = "\(gesture.logText), \(side ? "Seitenpanel" : trackStyle.title)"
        switch TrackPanelEntry.decide(style: side ? SidePanelGesture.guardStyle(for: gesture) : trackStyle, gesture: gesture,
                                      leaving: leaving, scrubbing: scrub.isActive, upNextShowing: upNext != nil,
                                      failureShowing: failureNotice != nil, alreadyOpen: showTracks,
                                      skipPromptShowing: skip.holdsFocus, lock: trackLock) {
        case .open:
            onUserInput()
            // Gesammelter ±10-s-Sprung nicht parallel zu einem Ton-Neuladen aus dem Panel (R1 M3).
            if pendingSeek != nil {
                seekTask?.cancel(); seekTask = nil; pendingSeek = nil
                RemoteLog.info("player", "Gesammelter Sprung verworfen (Spur-Panel öffnet)")
            }
            RemoteLog.info("player", "Spur-Panel öffnen (\(via)) · " + TrackChoice.summary(
                audio: TrackChoice.active(engine.audioTracks, id: engine.activeAudioID),
                subtitle: TrackChoice.active(engine.subtitleTracks, id: engine.activeSubtitleID))
                + " · \(engine.audioTracks.count) Ton, \(engine.subtitleTracks.count) UT")
            sideOpen = side
            showTracks = true
        case .cancelUpNext:
            onUserInput()
            withAnimation { upNext = nil }; upNextCancelled = true
            RemoteLog.info("player", "Up-next abgebrochen")
        case .ignore(.otherGesture) where !gesture.isSwipe:
            break   // ▲/▼ der anderen Richtung tut nichts, wie bisher ▲ (kein Log-Rauschen)
        case .ignore(let why):
            RemoteLog.info("player", "Spur-Panel nicht geöffnet (\(via)): \(why.logText)")
        }
    }

    /// Welle F-h R1: Spurwahl gesperrt während Neuaufbau, Fehlerleiter, Start (TrackLock in PlayerCore).
    var trackLock: TrackLock? {
        TrackLock.current(restoring: restoring, recovering: recovering, loadInFlight: stab.loadInFlight,
                          startPending: stab.startPending, waitingForNetwork: stab.networkNotice != nil,
                          engineError: engine.errorText != nil, audioSwitching: audioSwitch.isActive)
    }

    /// Welle F-h2 R1: Ton-Neuladen aus dem Panel begonnen.
    private func beginAudioSwitch(_ id: Int) {
        audioSwitch.begin(id, now: Date())
        // Zeitgrenzen (verworfen nach 3 s, hart nach 30 s) auch ohne Engine-Änderung und bei offenem Panel prüfen.
        audioSwitchTick?.cancel()
        audioSwitchTick = Task { @MainActor in
            while !Task.isCancelled, let d = audioSwitch.nextDeadline {
                try? await Task.sleep(for: .seconds(max(0, d.timeIntervalSinceNow) + 0.1))
                guard !Task.isCancelled else { return }
                checkAudioSwitch()
            }
        }
        RemoteLog.info("player", "Tonwechsel lädt (Ton-ID \(id)) · Untertitel/Versatz gesperrt")
    }

    private func checkAudioSwitch() {
        guard audioSwitch.isActive else { return }
        let target = audioSwitch.target
        if let o = audioSwitch.update(activeID: engine.activeAudioID, isLoading: engine.isLoading,
                                      failed: engine.errorText != nil, now: Date()) {
            RemoteLog.info("player", "Tonwechsel \(o.logText) (Ziel \(target.map(String.init) ?? "-") · aktiv \(engine.activeAudioID.map(String.init) ?? "-")) · Spurwahl frei")
        }
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

    /// Welle G-a: Schnellsuchlauf beginnt. Ein gesammelter ±10-s-Sprung springt nicht mehr (Ziel = Ausgangsstelle,
    /// der Sprung desselben Drucks fällt weg: `FastSeek.origin`); gesprungen wird erst bei Select/Play.
    private func fastSeekOrigin(forward: Bool) -> Double {
        let age = lastArrow.map { ProcessInfo.processInfo.systemUptime - $0.at }
        let from = FastSeek.origin(pending: pendingSeek, current: engine.currentTime, lastArrowForward: lastArrow?.forward,
                                   lastArrowAge: age, forward: forward)
        if pendingSeek != nil { RemoteLog.info("player", "Gesammelter Sprung → Schnellsuchlauf ab \(Int(from))s") }
        seekTask?.cancel(); seekTask = nil; pendingSeek = nil
        return from
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
        // W-A-3: the audio track before the teardown, chosen again after the reload.
        let audioBefore = engine.activeAudioID.map { TrackMemory.Entry(audioID: $0, audioLanguage: audioLanguage) }
        recoverTask?.cancel()
        recoverGen &+= 1
        let gen = recoverGen
        recovering = true
        recoverTask = Task {
            defer { if recoverGen == gen { recovering = false } }
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
            let steps = startSeq.afterSuccessfulLoad(isFirst: false, remembered: audioBefore, pendingFraction: syncFraction)
            // W-A-1: first successful load of this player (the first load failed): run the whole start.
            if steps.contains(.placeholderCheck) { runStartSteps(steps); return }
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
            runStartSteps(steps, audioBefore: audioBefore)   // Ton wiederherstellen, Sprung (falls offen), weiterspielen
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
        guard engine.duration > 0, engine.currentTime > 0, !sideHoldsProgress else { return }
        report(engine.currentTime, engine.duration)
    }

    /// Intern auch für PlayerScrub.swift (Steuerleiste beim Spulen zeigen).
    func poke() {
        pauseCard.noteInput()   // Wave P-b
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
