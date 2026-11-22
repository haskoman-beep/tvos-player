import SwiftUI
import UIKit
import AetherFEL
import PlayerCore

/// Backends, die Technik-Rohwerte für die Info-Spalte liefern (Auflösung, Dynamik, Tonkette).
@MainActor
protocol PlaybackTechInfoSource {
    var trackPanelTech: PlaybackTechSnapshot { get }
}

extension AetherBackend: PlaybackTechInfoSource {
    var trackPanelTech: PlaybackTechSnapshot {
        // Auflösung und Quell-Dynamik aus den Protokollwerten (dieselben wie bei den Player-2-Plaketten).
        PlaybackTechSnapshot(videoWidth: sourceVideoWidth,
                             sourceFormat: sourceVideoFormatName,
                             outputFormat: "\(engine.videoFormat)",
                             dolbyVisionProfile: engine.sourceDVProfile,
                             videoCodec: engine.sourceVideoCodecName,
                             audioPipeline: engine.activeAudioDecoder,
                             audioDelivery: "\(engine.audioDelivery)",
                             activeAudio: audioTracks.first { $0.id == activeAudioID })
    }
}

/// Welle F-h2: schmales Panel oben über dem laufenden Video (Wisch nach unten), höchstens ein Drittel hoch.
/// Spalten nebeneinander: Ton · Untertitel · Versatz, darunter Info als eine Fußzeile. ◀/▶ wechselt die Spalte,
/// ▲/▼ die Zeile, Auswahl wirkt sofort (Häkchen). Menü oder Wisch nach oben aus der obersten Zeile schließt nur das
/// Panel, die Wiedergabe läuft weiter. Eigene Präsentation, damit Fokus und Menü-Taste im Panel bleiben.
/// Breiten und Zeichenbudget: `TrackPanelMetrics` (PlayerCore).
struct PlayerTrackPanel<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let profile: Profile
    /// Adresse der Quelle (für den Dateinamen in der Info-Zeile).
    var sourceURL: URL? = nil
    /// Tonspur-Wechsel gesperrt (nach dem Hintergrund bis Play neu aufgebaut hat).
    var audioLocked = false
    /// Sperre zum Anzeigen (gesperrte Spalten, „lädt…“); als Wert, damit das Panel bei jeder Änderung neu zeichnet.
    var shownLock: TrackLock? = nil
    /// Welle F-h R1: Sperre beim Wählen frisch lesen; nil = frei.
    var lock: () -> TrackLock? = { nil }
    /// Welle F-h2 R1: Ton-Neuladen begonnen (Zielspur); der Player sperrt Untertitel/Versatz bis es fertig ist.
    var onAudioSwitch: (Int) -> Void = { _ in }
    /// Welle D-a: Nutzerwahl merken (Spur-Gedächtnis je Serie); nil = aus.
    var onRemember: ((TrackMemoryChange) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: TrackPanelSpot?
    /// Nutzer hat den Fokus bewegt (dann den Startfokus nicht mehr nachziehen).
    @State private var userMoved = false
    /// Einmal je Panel (StateObject); hält keine Closures, also keinen Verweis zurück aufs Panel (R1 I1).
    @StateObject private var swipeUp = PanelSwipeUp()

    private var columns: [TrackPanelColumnModel] {
        let activeSub = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }
        return TrackPanelLayout.applying(shownLock, to: [
            TrackPanelLayout.audioColumn(engine.audioTracks, activeID: engine.activeAudioID, priority: profile.audioPriority,
                                         audioLocked: audioLocked),
            TrackPanelLayout.subtitleColumn(engine.subtitleTracks, activeID: engine.activeSubtitleID,
                                            preferredLanguage: profile.subtitleLanguage),
            TrackPanelLayout.offsetColumn(offset: engine.subtitleOffset, nativeTrack: activeSub?.isNativelyRendered == true)])
    }

    var body: some View {
        GeometryReader { geo in
            // Höhe ⅓ des ganzen Bildschirms; der Inhalt bleibt im Sicherheitsrand (oben 60 bei 1080), nur der Grund reicht bis zur Kante.
            let screen = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let height = max(0, CGFloat(TrackPanelLayout.panelHeight(screenHeight: Double(screen))) - geo.safeAreaInsets.top)
            panel
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: height, alignment: .top)
                .clipped()
                .background {
                    ZStack { Rectangle().fill(.ultraThinMaterial); Theme.Palette.scrim }
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.overlayCard,
                                                          bottomTrailingRadius: Theme.Radius.overlayCard, style: .continuous))
                        .ignoresSafeArea(edges: [.top, .horizontal])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, TrackPanelLayout.initialSpot(columns))
        .onChange(of: focus) { old, new in
            swipeUp.spot = new
            // Erster Fokus beim Öffnen (old == nil) ist kein Nutzerschritt.
            guard let old, let new else { return }
            userMoved = true
            if let target = TrackPanelLayout.redirect(from: old, to: new, columns: columns) { focus = target }
        }
        .onChange(of: swipeUp.swipe) { _, e in
            guard let e, TrackPanelLayout.closesOnSwipeUp(startSpot: e.from, columns: columns) else { return }
            RemoteLog.info("player", "Panel zu (Wisch nach oben)")
            dismiss()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            let start = TrackPanelLayout.initialSpot(columns)
            if !userMoved, focus != start { focus = start }
        }
        .onAppear { RemoteLog.info("player", "Panel auf"); swipeUp.start() }
        .onDisappear { swipeUp.stop(); RemoteLog.info("player", "Panel zu") }
        .onExitCommand { dismiss() }
        .presentationBackground(.clear)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let l = shownLock, l != .audioSwitching { Text(l.text).font(.caption).foregroundStyle(Theme.Palette.secondary) }
            HStack(alignment: .top, spacing: CGFloat(TrackPanelMetrics.columnSpacing)) {
                let cols = columns
                column(cols[0], width: TrackPanelMetrics.audioColumnWidth, empty: "Keine Tonspuren")
                column(cols[1], width: TrackPanelMetrics.subtitleColumnWidth, empty: nil)
                column(cols[2], width: TrackPanelMetrics.offsetColumnWidth, empty: nil)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            infoLine
        }
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
    }

    // MARK: Spalte

    private func column(_ c: TrackPanelColumnModel, width: Double, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            heading(c.title, note: c.note)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    if c.rows.isEmpty, let empty {
                        Text(empty).font(.callout).foregroundStyle(Theme.Palette.secondary)
                    }
                    ForEach(c.rows) { r in
                        Button { choose(TrackPanelSpot(c.column, r.id)) } label: { TrackPanelRowLabel(row: r, mark: c.column != .offset) }
                            .buttonStyle(ThemeRowButtonStyle(minHeight: 0, maxWidth: .infinity, maxFocusGrowth: Theme.Focus.rowMaxGrowth,
                                                             restFill: .clear, verticalPadding: Theme.Space.xs))
                            .focused($focus, equals: TrackPanelSpot(c.column, r.id))
                            .disabled(c.isLocked)
                    }
                }
                // Platz fürs Anheben der fokussierten Zeile (TrackPanelMetrics.listInset).
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, 4)
            }
        }
        .frame(width: CGFloat(width), alignment: .leading)
        .focusSection()
    }

    private func heading(_ title: String, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.Palette.primary)
            if let note { Text(note).font(.caption).foregroundStyle(Theme.Palette.secondary).lineLimit(1) }
        }
        .padding(.leading, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Info (ohne Fokus, eine Zeile)

    @ViewBuilder private var infoLine: some View {
        let snap: PlaybackTechSnapshot = {
            var s = (engine as? any PlaybackTechInfoSource)?.trackPanelTech ?? PlaybackTechSnapshot()
            s.fileName = TrackPanelLogic.sourceFileName(sourceURL)
            return s
        }()
        if let line = TrackPanelLayout.infoLine(TrackPanelLogic.infoRows(snap)) {
            Text(line).font(.caption).foregroundStyle(Theme.Palette.secondary).lineLimit(1).truncationMode(.middle)
                .padding(.leading, Theme.Space.xs)
        }
    }

    // MARK: Wählen

    private func choose(_ spot: TrackPanelSpot) {
        guard !blocked(spot.column) else { return }
        switch (spot.column, spot.row) {
        case (.audio, .track(let id)): chooseAudio(id)
        case (.subtitles, .off): chooseSubtitle(nil)
        case (.subtitles, .track(let id)): chooseSubtitle(id)
        case (.offset, .step(let i)) where SubtitleOffset.steps.indices.contains(i):
            changeOffset(SubtitleOffset.adjusted(engine.subtitleOffset, by: SubtitleOffset.steps[i]))
        case (.offset, .reset): changeOffset(0)
        default: break
        }
    }

    /// Ton: sofort wirksam, Panel bleibt offen (Häkchen wandert, sobald die Engine die Spur meldet).
    /// Engine: sitzungserhaltendes Neuladen an derselben Stelle; bis es fertig ist, sperrt der Player Untertitel/Versatz.
    private func chooseAudio(_ id: Int) {
        guard let t = engine.audioTracks.first(where: { $0.id == id }) else { return }
        switch TrackChoice.audioAction(selected: t.id, active: engine.activeAudioID, locked: audioLocked) {
        case .apply: engine.selectAudio(t.id); onAudioSwitch(t.id); onRemember?(.audio(t)); logChoice(audio: t)
        case .keep: onRemember?(.audio(t)); logChoice(audio: t)
        case .locked: RemoteLog.info("player", "Tonspur gewählt: \(t.id) · gesperrt bis Play")
        }
    }

    /// Untertitel (auch „Aus“): Nutzerwahl, setzt subtitleChosenByUser; danach wählt keine Automatik mehr.
    private func chooseSubtitle(_ id: Int?) {
        let t = id.flatMap { id in engine.subtitleTracks.first { $0.id == id } }
        guard id == nil || t != nil else { return }
        engine.selectSubtitle(t?.id)
        onRemember?(.subtitle(t))
        logChoice(subtitle: .some(t))
    }

    // MARK: Untertitel-Versatz (Welle D-a)

    private func changeOffset(_ v: Double) {
        let n = SubtitleOffset.normalized(v)
        guard n != engine.subtitleOffset else { return }
        engine.setSubtitleOffset(n)
        let embedded = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }?.isExternal != true
        RemoteLog.info("player", "UT-Versatz: \(SubtitleOffset.label(n))"
                       + (n < 0 && embedded ? " · Vorauslesen der Engine aktiv (Fernquelle wird teils doppelt geladen)" : ""))
        onRemember?(.offset(n))
    }

    // MARK: Sperre (R1)

    /// Sperre beim Wählen (frisch gelesen). Tonwechsel: Wahl ignorieren, Panel bleibt offen (nichts vormerken).
    /// Andere Sperren: Hinweis loggen, Panel schließen. true = gesperrt.
    private func blocked(_ column: TrackPanelColumn) -> Bool {
        guard let l = lock(), l.blocks(column) else { return false }
        if l == .audioSwitching {
            RemoteLog.info("player", "Spurwahl gesperrt (Tonwechsel lädt)")
            return true
        }
        RemoteLog.info("player", "Spurwahl gesperrt: \(l.logText)")
        dismiss()
        return true
    }

    // MARK: Log

    /// „Spurwahl: Ton <x> / UT <y>“ mit der neuen Wahl; der andere Teil ist die laufende Spur.
    /// `subtitle`: nil = unverändert, .some(nil) = Aus.
    private func logChoice(audio: AudioTrackInfo? = nil, subtitle: AudioTrackInfo?? = nil) {
        let a = audio ?? TrackChoice.active(engine.audioTracks, id: engine.activeAudioID)
        let u = subtitle ?? TrackChoice.active(engine.subtitleTracks, id: engine.activeSubtitleID)
        let ids = "Ton-ID \(a.map { String($0.id) } ?? "-") · UT-ID \(u.map { String($0.id) } ?? "aus")"
        RemoteLog.info("player", "Spurwahl: \(TrackChoice.summary(audio: a, subtitle: u)) (\(ids))")
    }
}

/// Einzeilige Spurzeile: Häkchen, Text, kleine Marke. Farben aus den Tokens (liest den Fokus des Knopfs);
/// gesperrt (deaktiviert) gedimmt.
private struct TrackPanelRowLabel: View {
    let row: TrackPanelRow
    /// Häkchen-Platz (nicht in der Versatz-Spalte).
    let mark: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: CGFloat(TrackPanelMetrics.spacing)) {
            if mark {
                Image(systemName: "checkmark").font(.caption.bold()).opacity(row.isActive ? 1 : 0)
                    .frame(width: CGFloat(TrackPanelMetrics.markWidth))
            }
            Text(row.line).font(.callout.weight(row.isActive ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
            if let tag = row.tag {
                ThemeBadge(kind: .tech(.poster), text: tag, surface: focused ? .focusedRow : .plain)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(focused ? Theme.Palette.primaryOnFocus : (enabled ? Theme.Palette.primary : Theme.Palette.secondary))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isActive ? .isSelected : [])
    }
}

/// Welle F-h2: Wisch nach oben im Panel. Eigener Pan-Recognizer am Fenster, der Berührungen nicht schluckt
/// (die Fokussteuerung bewegt weiter die Zeilen). Merkt die Fokusstelle beim Wischbeginn (`spot`, vom Panel
/// gesetzt) und meldet den Wisch als veröffentlichtes Ereignis. R1 I1: keine gespeicherten Closures, also kein
/// Verweis zurück aufs Panel (und damit auf Backend und Engine); `stop()` löst den Recognizer.
@MainActor
final class PanelSwipeUp: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    struct Swipe: Equatable {
        let serial: Int
        let from: TrackPanelSpot?
    }

    /// Letzter Wisch nach oben (Fokus beim Beginn); das Panel entscheidet über `closesOnSwipeUp`.
    @Published private(set) var swipe: Swipe?
    /// Aktuelle Fokusstelle (vom Panel nachgeführt).
    var spot: TrackPanelSpot?
    private var startSpot: TrackPanelSpot?
    private var serial = 0
    private var recognizer: UIPanGestureRecognizer?

    func start() {
        stop()
        guard let window = PlayerWindow.key else {
            RemoteLog.info("player", "Panel: kein Fenster für Wisch nach oben")
            return
        }
        let g = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        g.delegate = self
        window.addGestureRecognizer(g)
        recognizer = g
    }

    func stop() {
        if let g = recognizer { g.view?.removeGestureRecognizer(g) }
        recognizer = nil
        startSpot = nil
    }

    deinit {
        Task { @MainActor in RemoteLog.info("player", "Panel freigegeben") }
    }

    @objc private func handle(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began: startSpot = spot
        case .ended:
            let tr = g.translation(in: g.view)
            let vy = Double(g.velocity(in: g.view).y)
            if TrackPanelEntry.isSwipeUp(translationX: Double(tr.x), translationY: Double(tr.y), velocityY: vy) {
                serial += 1
                swipe = Swipe(serial: serial, from: startSpot)
            }
            startSpot = nil
        case .cancelled, .failed: startSpot = nil
        default: break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
