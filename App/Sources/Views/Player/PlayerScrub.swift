import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import GameController
import AetherFEL
import PlayerCore

// MARK: Vorschaubilder aus der Engine

/// Ein Vorschaubild und die Zeit, die es wirklich zeigt (nächstes dekodierbares Bild, kann vom Ziel abweichen).
struct ScrubStill {
    let image: CGImage
    let seconds: Double
}

/// Standard für Backends ohne Vorschau.
extension PlaybackEngine {
    var supportsScrubPreview: Bool { false }
    func scrubPreview(at seconds: Double, refined: Bool, maxWidth: Int) async -> ScrubStill? { nil }
    func endScrubPreview() async {}
}

/// AetherEngine 7.71.2: `scrubPreviewFrame` liest nur schon geladene Segmente bzw. den Paketpuffer, öffnet nie
/// eine zweite Verbindung und sucht nie in der Wiedergabe. `supportsCacheBackedStills` = Quelle liefert Standbilder
/// (nicht z. B. Dolby Vision Profil 5 ohne Umformung). Nach dem Spulen die Still-Dekoder freigeben.
extension AetherBackend {
    var supportsScrubPreview: Bool { engine.supportsCacheBackedStills }
    func scrubPreview(at seconds: Double, refined: Bool, maxWidth: Int) async -> ScrubStill? {
        guard engine.supportsCacheBackedStills else { return nil }
        // `isCancelled: { false }` genügt: die Engine prüft zusätzlich `Task.isCancelled`, und der Aufruf läuft
        // strukturiert im `previewTask` des ScrubController (dessen Abbruch beendet die Abfrage).
        guard let f = await engine.scrubPreviewFrame(atSeconds: seconds, refined: refined, maxWidth: maxWidth,
                                                     isCancelled: { false }) else { return nil }
        return ScrubStill(image: f.image, seconds: f.actualSeconds)
    }
    func endScrubPreview() async { await engine.releaseScrubPreviewDecoders() }
}

// MARK: Spul-Steuerung

/// Spulen über die Touchfläche (Welle C-c, #18): Wischen mit Beschleunigung, Drehrad am Außenring, Vorschau,
/// Select bestätigt, Menü bricht ab. Logik: `ScrubPlanner` (PlayerCore). Eine Wiedergabe = ein Controller.
@MainActor
final class ScrubController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var target: Double = 0
    @Published private(set) var preview: CGImage?
    /// Zeit des gezeigten Bildes (kann vom Ziel abweichen, solange das neue lädt).
    @Published private(set) var previewTime: Double?
    /// Welle G-a: Schnellsuchlauf (◀/▶ gehalten): Geschwindigkeit mit Vorzeichen, nil = nichts gehalten.
    @Published private(set) var holdSpeed: Double?
    /// Ziel steht an der Grenze (Anfang, Dateiende, vor dem Abspann).
    @Published private(set) var holdAtLimit = false

    private var planner = ScrubPlanner()
    private var cache = ScrubPreviewCache<ScrubStill>(capacity: 48)
    private let input = RemoteTouchInput()
    private var previewTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var fetching = false
    /// Wechselt mit jedem Spul-Ende: ein abgebrochener alter Vorschau-Task setzt `fetching` nicht mehr zurück.
    private var previewGen = 0
    private var usedPreview = false

    /// Von PlayerControls beim Erscheinen gesetzt.
    private var canScrub: () -> Bool = { false }
    private var position: () -> Double = { 0 }
    private var duration: () -> Double = { 0 }
    private var edges: () -> [Double] = { [] }
    private var supportsPreview: () -> Bool = { false }
    private var fetch: (Double, Bool) async -> ScrubStill? = { _, _ in nil }
    private var release: () async -> Void = {}
    /// Schnellsuchlauf: Ausgangsstelle (verbraucht einen gesammelten ±10-s-Sprung) und Obergrenze ab einer Stelle.
    private var holdAllowed: () -> Bool = { false }
    private var holdOrigin: (Bool) -> Double = { _ in 0 }
    private var holdLimit: (Double) -> Double = { _ in .greatestFiniteMagnitude }
    private var holdTask: Task<Void, Never>?
    /// Welle F-h: Wisch nach unten (Spur-Panel). tvOS meldet ihn nicht als `onMoveCommand(.down)`.
    private var swipeDown: () -> Void = {}

    static let previewWidth = 480
    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    func attach<E: PlaybackEngine>(engine: E, canScrub: @escaping () -> Bool, edges: @escaping () -> [Double],
                                   holdAllowed: @escaping () -> Bool,
                                   holdOrigin: @escaping (Bool) -> Double, holdLimit: @escaping (Double) -> Double,
                                   swipeDown: @escaping () -> Void, verticalQuiet: @escaping () -> Bool = { false }) {
        self.canScrub = canScrub
        self.swipeDown = swipeDown
        self.edges = edges
        self.holdAllowed = holdAllowed
        self.holdOrigin = holdOrigin
        self.holdLimit = holdLimit
        position = { [weak engine] in engine?.currentTime ?? 0 }
        duration = { [weak engine] in engine?.duration ?? 0 }
        supportsPreview = { [weak engine] in engine?.supportsScrubPreview ?? false }
        fetch = { [weak engine] t, refined in await engine?.scrubPreview(at: t, refined: refined, maxWidth: ScrubController.previewWidth) }
        release = { [weak engine] in await engine?.endScrubPreview() }
        input.onPan = { [weak self] dx, vx in self?.pan(dx, vx) }
        input.onPanEnded = { [weak self] in self?.planner.panEnded() }
        input.onSwipeDown = { [weak self] in self?.swipeDown() }
        input.verticalQuiet = verticalQuiet
        input.onTouch = { [weak self] x, y in self?.touch(x, y) }
        input.onTouchEnded = { [weak self] in self?.planner.touchEnded() }
        input.onHoldBegan = { [weak self] forward in self?.holdBegan(forward) }
        input.onHoldEnded = { [weak self] in self?.holdEnded() }
        input.canHold = { [weak self] in self?.canHold() ?? false }
        input.start()
    }

    /// Player verschwindet (auch fürs Spur-Panel): Eingaben abmelden, laufendes Spulen verwerfen.
    func detach() {
        input.stop()
        _ = cancel(log: false)
    }

    /// ◀/▶ kommt kurz nach einer Wischbewegung (die Geste löst sie mit aus): nicht als ±10-s-Sprung werten.
    func suppressesMove() -> Bool { planner.suppressesMove(now: Self.now) }

    /// ◀/▶-Klick während des Spulens: Ziel um 10 s verschieben.
    func nudge(_ seconds: Double) {
        if planner.nudge(seconds, now: Self.now) { publish() }
    }

    /// Select/Play: Ziel übernehmen (nil = nichts zu springen).
    func confirm() -> Double? {
        let t = planner.confirm()
        end()
        RemoteLog.info("spulen", t.map { "bestätigt → \(Int($0))s" } ?? "bestätigt ohne Änderung")
        return t
    }

    /// Menü: verwerfen. true = es lief ein Spulen (Taste verbraucht).
    func cancel(log: Bool = true) -> Bool {
        guard planner.cancel() else { return false }
        end()
        if log { RemoteLog.info("spulen", "abgebrochen") }
        return true
    }

    // MARK: Eingaben

    private func pan(_ dx: Double, _ vx: Double) {
        guard planner.isActive || canScrub() else { return }
        let was = planner.isActive
        prepare(was)
        if planner.pan(deltaX: dx, velocityX: vx, position: position(), duration: duration(), now: Self.now) || planner.isActive != was {
            publish()
        }
    }

    private func touch(_ x: Double, _ y: Double) {
        guard planner.isActive || canScrub() else { planner.touchEnded(); return }
        let was = planner.isActive
        prepare(was)
        if planner.touch(x: x, y: y, position: position(), duration: duration(), now: Self.now) || planner.isActive != was {
            publish()
        }
    }

    /// ◀/▶ gehalten (`FastSeek.holdThreshold`): Ziel läuft mit steigender Geschwindigkeit, bis losgelassen wird.
    /// Gleiche Bedingung für den Recognizer (`gestureRecognizerShouldBegin`) und den Beginn (R1 M4).
    private func canHold() -> Bool { holdAllowed() && (planner.isActive || canScrub()) }

    private func holdBegan(_ forward: Bool) {
        guard canHold() else { return }
        let was = planner.isActive
        prepare(was)
        let from = was ? planner.target : holdOrigin(forward)
        let upper = holdLimit(from)
        planner.holdBegin(forward: forward, position: from, duration: duration(), upper: upper, now: Self.now)
        RemoteLog.info("spulen", "Schnellsuchlauf \(forward ? "vor" : "zurück") ab \(Int(planner.target))s"
            + (upper < .greatestFiniteMagnitude ? " · Grenze \(Int(upper))s" : ""))
        publish()
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            var lastSpeed: Double?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(FastSeek.tick))
                guard let self, !Task.isCancelled, self.planner.isHolding else { return }
                let moved = self.planner.holdTick(now: Self.now)
                let sp = self.planner.holdSpeed(now: Self.now)
                if sp != lastSpeed, let sp {
                    lastSpeed = sp
                    RemoteLog.info("spulen", "Schnellsuchlauf \(FastSeek.label(speed: sp)) bei \(Int(self.planner.target))s")
                }
                if moved || sp != self.holdSpeed || self.planner.holdAtLimit != self.holdAtLimit { self.publish() }
            }
        }
    }

    /// Losgelassen: Ziel bleibt stehen; Select/Play springt, Menü verwirft.
    private func holdEnded() {
        guard planner.isHolding else { return }
        holdTask?.cancel(); holdTask = nil
        planner.holdEnd(now: Self.now)
        RemoteLog.info("spulen", "Schnellsuchlauf losgelassen bei \(Int(planner.target))s\(planner.holdAtLimit ? " (Grenze)" : "")")
        publish()
    }

    private func prepare(_ active: Bool) {
        if !active { planner.snapEdges = edges() }
    }

    private func publish() {
        let started = !isActive && planner.isActive
        isActive = planner.isActive
        target = planner.target
        holdSpeed = planner.holdSpeed(now: Self.now)
        holdAtLimit = planner.holdAtLimit
        guard isActive else { return }
        if started {
            RemoteLog.info("spulen", "Beginn bei \(Int(planner.origin))s · Vorschau \(supportsPreview() ? "ja" : "nein (Quelle liefert keine Standbilder)")")
            startIdleWatch()
        }
        requestPreview()
    }

    private func end() {
        isActive = false
        holdTask?.cancel(); holdTask = nil
        holdSpeed = nil; holdAtLimit = false
        previewTask?.cancel(); previewTask = nil
        idleTask?.cancel(); idleTask = nil
        preview = nil; previewTime = nil
        previewGen &+= 1; fetching = false
        // Bilder nicht über das Spulen hinaus halten (bis zu 48 × 480 px); die Engine behält ihre eigenen.
        cache.reset()
        if usedPreview {
            usedPreview = false
            Task { await release() }
        }
    }

    private func startIdleWatch() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.planner.idleExpired(now: Self.now) {
                    RemoteLog.info("spulen", "ohne Eingabe → verworfen")
                    _ = self.cancel(log: false)
                    return
                }
            }
        }
    }

    // MARK: Vorschau

    /// Grobes Bild je 2-s-Feld (aus dem Zwischenspeicher oder neu), nach kurzer Ruhe ein genaues für das Ziel.
    /// Immer nur eine Abfrage gleichzeitig; danach gilt das dann aktuelle Ziel.
    private func requestPreview() {
        guard supportsPreview() else { return }
        if let hit = cache.value(at: target) { preview = hit.image; previewTime = hit.seconds }
        guard !fetching else { return }
        previewTask?.cancel()
        let gen = previewGen
        previewTask = Task { [weak self] in await self?.runPreview(gen) }
    }

    private func runPreview(_ gen: Int) async {
        fetching = true
        defer { if gen == previewGen { fetching = false } }
        var lastCoarse: Int?
        while !Task.isCancelled, isActive {
            let t = target, key = ScrubPreviewCache<ScrubStill>.key(t)
            if key != lastCoarse, cache.value(at: t) == nil {
                lastCoarse = key
                usedPreview = true
                let img = await fetch(t, false)
                guard !Task.isCancelled, isActive else { return }
                if let img {
                    cache.store(img, at: t)
                    if ScrubPreviewCache<ScrubStill>.key(target) == key { preview = img.image; previewTime = img.seconds }
                }
                continue
            }
            // Ziel ruht: genaues Bild für genau diese Stelle (nicht zwischengespeichert).
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, isActive else { return }
            guard target == t else { continue }
            usedPreview = true
            if let img = await fetch(t, true), !Task.isCancelled, isActive, target == t { preview = img.image; previewTime = img.seconds }
            // Bis zur nächsten Bewegung nichts mehr tun.
            while !Task.isCancelled, isActive, target == t { try? await Task.sleep(for: .milliseconds(100)) }
        }
    }
}

// MARK: Touchfläche (UIKit/GameController)

/// Wischbewegung über einen Pan-Recognizer am Fenster (erreicht jede fokussierte Ansicht, stört den Fokus
/// nicht) und absolute Fingerposition über `GCMicroGamepad` (für das Drehrad). Beim Abmelden wird der
/// vorige Gamepad-Zustand wiederhergestellt.
@MainActor
final class RemoteTouchInput: NSObject, UIGestureRecognizerDelegate {
    var onPan: (Double, Double) -> Void = { _, _ in }
    var onPanEnded: () -> Void = {}
    /// Welle F-h: Wischbewegung endete als Wisch nach unten (`TrackPanelEntry.isSwipeDown`).
    var onSwipeDown: () -> Void = {}
    /// Welle F-h2 R1: senkrechtes Wischen gehört gerade jemand anderem (offenes Spur-Panel): nichts melden, nichts loggen.
    var verticalQuiet: () -> Bool = { false }
    var onTouch: (Double, Double) -> Void = { _, _ in }
    var onTouchEnded: () -> Void = {}
    /// Welle G-a: ◀/▶ gehalten (true = vor) bzw. losgelassen.
    var onHoldBegan: (Bool) -> Void = { _ in }
    var onHoldEnded: () -> Void = {}
    /// Halten darf beginnen (sonst scheitert der Recognizer und der Druck läuft normal weiter, z. B. Up-next abbrechen).
    var canHold: () -> Bool = { false }

    private var recognizer: UIPanGestureRecognizer?
    private var holdRecognizer: ArrowHoldRecognizer?
    private var lastTranslation: CGFloat = 0
    /// Je Gamepad der vorige Zustand (absolute Werte, Handler), beim Abmelden zurückgesetzt.
    private var pads: [(pad: GCMicroGamepad, absolute: Bool, handler: GCControllerDirectionPadValueChangedHandler?)] = []
    private var connectObserver: NSObjectProtocol?

    func start() {
        stop()
        if let window = PlayerWindow.key {
            let g = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
            g.delegate = self
            window.addGestureRecognizer(g)
            recognizer = g
            let h = ArrowHoldRecognizer(target: self, action: #selector(handleHold(_:)))
            h.delegate = self
            window.addGestureRecognizer(h)
            holdRecognizer = h
        } else {
            RemoteLog.info("spulen", "kein Fenster für die Wischgeste")
        }
        attachPads()
        connectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachPads() }
        }
    }

    func stop() {
        if let g = recognizer { g.view?.removeGestureRecognizer(g) }
        recognizer = nil
        if let h = holdRecognizer { h.view?.removeGestureRecognizer(h) }
        holdRecognizer = nil
        for p in pads {
            p.pad.dpad.valueChangedHandler = p.handler
            p.pad.reportsAbsoluteDpadValues = p.absolute
        }
        pads = []
        if let o = connectObserver { NotificationCenter.default.removeObserver(o) }
        connectObserver = nil
    }

    private func attachPads() {
        for c in GCController.controllers() {
            guard let pad = c.microGamepad, !pads.contains(where: { $0.pad === pad }) else { continue }
            let previous = pad.dpad.valueChangedHandler
            pads.append((pad, pad.reportsAbsoluteDpadValues, previous))
            pad.reportsAbsoluteDpadValues = true
            pad.dpad.valueChangedHandler = { [weak self] d, x, y in
                previous?(d, x, y)
                MainActor.assumeIsolated {
                    if x == 0 && y == 0 { self?.onTouchEnded() } else { self?.onTouch(Double(x), Double(y)) }
                }
            }
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            lastTranslation = g.translation(in: g.view).x
        case .changed:
            let tr = g.translation(in: g.view)
            let dx = tr.x - lastTranslation
            lastTranslation = tr.x
            // Schräges/senkrechtes Wischen (z. B. ▼ zum Spur-Panel) spult nicht.
            guard ScrubPlanner.panIsHorizontal(translationX: Double(tr.x), translationY: Double(tr.y)) else { return }
            onPan(Double(dx), Double(g.velocity(in: g.view).x))
        case .ended, .cancelled, .failed:
            let tr = g.translation(in: g.view)
            lastTranslation = 0
            onPanEnded()
            // Welle F-h: senkrechter Wisch nach unten öffnet das Spur-Panel (Spulen ist nur waagerecht).
            guard g.state == .ended, !verticalQuiet() else { return }
            let vy = Double(g.velocity(in: g.view).y)
            if TrackPanelEntry.isSwipeDown(translationX: Double(tr.x), translationY: Double(tr.y), velocityY: vy) {
                onSwipeDown()
            } else if abs(tr.y) > abs(tr.x) * 1.5, abs(tr.y) >= TrackPanelEntry.swipeFastDistance {
                RemoteLog.info("spulen", "Senkrechtes Wischen ohne Wirkung (dy \(Int(tr.y)), vy \(Int(vy)))")
            }
        default: break
        }
    }

    @objc private func handleHold(_ g: ArrowHoldRecognizer) {
        switch g.state {
        case .began: onHoldBegan(g.forward)
        case .ended, .cancelled, .failed: onHoldEnded()
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        g === holdRecognizer ? canHold() : true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Welle G-a: ◀/▶ (Rand der Touchfläche bzw. Ring) länger als `FastSeek.holdThreshold` gedrückt. Erkannt
/// bricht er den Druck für die Ansichten ab (`cancelsTouchesInView`), danach kommt kein ◀/▶-Befehl mehr an;
/// ein kurzer Druck scheitert und läuft unverändert als ±10-s-Sprung (onMoveCommand) durch.
/// Nur Tasten, keine Berührungen: Wischen und Drehrad bleiben beim Pan-Recognizer bzw. GameController.
@MainActor
final class ArrowHoldRecognizer: UIGestureRecognizer {
    private(set) var forward = true
    private var press: UIPress?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue),
                             NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        allowedTouchTypes = []
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard press == nil, let p = presses.first(where: { $0.type == .leftArrow || $0.type == .rightArrow }) else { return }
        press = p
        forward = p.type == .rightArrow
        perform(#selector(holdReached), with: nil, afterDelay: FastSeek.holdThreshold)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard let p = press, presses.contains(p) else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(holdReached), object: nil)
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard let p = press, presses.contains(p) else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(holdReached), object: nil)
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }

    override func reset() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(holdReached), object: nil)
        press = nil
        super.reset()
    }

    @objc private func holdReached() {
        guard press != nil, state == .possible else { return }
        state = .began
    }
}

// MARK: Ansichten

/// Vorschaukarte über der Zeitleiste: Bild (falls die Quelle Standbilder liefert), Zielzeit und Abstand.
struct ScrubPreviewCard: View {
    @ObservedObject var controller: ScrubController
    let duration: Double
    let current: Double

    var body: some View {
        GeometryReader { geo in
            if controller.isActive {
                let d = max(duration, 1), f = min(max(controller.target / d, 0), 1)
                let cardW: CGFloat = 480, inset: CGFloat = 60
                let x = min(max(inset + f * (geo.size.width - 2 * inset), cardW / 2 + 20), geo.size.width - cardW / 2 - 20)
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.6))
                        if let img = controller.preview {
                            Image(decorative: img, scale: 1).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: cardW, height: cardW * 9 / 16)
                    HStack(spacing: 12) {
                        // Welle G-a: Geschwindigkeit des Schnellsuchlaufs (auch bei ausgeblendeter Steuerleiste).
                        if let sp = controller.holdSpeed {
                            Text(FastSeek.label(speed: sp)).font(.title3.monospacedDigit().bold())
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(.white.opacity(0.18), in: Capsule())
                        }
                        Text(PlayerClock.text(controller.target)).font(.title3.monospacedDigit().bold())
                        Text(PlayerClock.delta(controller.target - current)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if controller.holdAtLimit {
                        Text(controller.target < 1 ? "Anfang erreicht" : "Halt vor dem Ende")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(controller.holdSpeed != nil ? "Loslassen: anhalten · Select/Play: springen · Zurück: abbrechen"
                                                     : "Select/Play: springen · ◀▶ halten: Schnellsuchlauf · Zurück: abbrechen")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .position(x: x, y: geo.size.height - 300 - cardW * 9 / 32)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: controller.isActive)
    }
}

/// Zeitleiste der Steuerleiste: Fortschritt, farbige Bereiche (Intro, Rückblick, Abspann) und beim Spulen das Ziel.
struct PlayerTimeline: View {
    let position: Double
    let duration: Double
    var marks: [TimelineMark] = []
    /// Ziel beim Spulen (nil = kein Spulen); dann zeigt `position` die laufende Stelle als dünnen Strich.
    var scrubTarget: Double? = nil
    var current: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, d = max(duration, 1)
            let shown = min(max((scrubTarget ?? position) / d, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                ForEach(marks, id: \.self) { m in
                    Rectangle().fill(Self.color(m.kind))
                        .frame(width: max(2, (m.to - m.from) * w), height: 10)
                        .offset(x: m.from * w)
                }
                Capsule().fill(.white).frame(width: max(0, shown * w))
                    .opacity(scrubTarget == nil ? 1 : 0.85)
                if scrubTarget != nil {
                    let c = min(max(current / d, 0), 1)
                    Rectangle().fill(.white.opacity(0.6)).frame(width: 3, height: 18).offset(x: c * w - 1.5)
                    Circle().fill(.white).frame(width: 22, height: 22).offset(x: shown * w - 11)
                }
            }
            .frame(height: 10)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 22)
    }

    static func color(_ k: SkipSegment.Kind) -> Color {
        switch k {
        case .intro, .recap: return .yellow.opacity(0.75)
        case .credits, .postCredits: return .cyan.opacity(0.6)
        }
    }
}

/// Zeitangaben im Player („1:02:03“, „+2:10“).
enum PlayerClock {
    static func text(_ s: Double) -> String {
        let t = Int(max(0, s.isFinite ? s : 0))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
    static func delta(_ s: Double) -> String {
        guard s.isFinite else { return "" }
        return (s < 0 ? "−" : "+") + text(abs(s))
    }
}

// MARK: PlayerControls

extension PlayerControls {
    /// Select/Play beim Spulen: an das Ziel springen (gleiche Sperre wie ±10 s nach dem Hintergrund).
    func confirmScrub() {
        guard !leaving else { _ = scrub.cancel(log: false); return }
        guard let t = scrub.confirm() else { poke(); return }
        guard !restorePending, !restoring else { RemoteLog.info("player", "Spulen gesperrt bis Play/Neuaufbau (nach Hintergrund)"); return }
        // Ziel bis zur Landung halten (wie `queueSeek`), sonst springt die Zeitleiste kurz zurück.
        seekTask?.cancel(); pendingSeek = t
        RemoteLog.info("player", "Spulen \(Int(engine.currentTime)) → \(Int(t))s")
        seekTask = Task {
            guard !Task.isCancelled, !leaving else { return }
            await engine.seek(t)
            guard !Task.isCancelled else { return }
            pendingSeek = nil
        }
        poke()
    }
}
