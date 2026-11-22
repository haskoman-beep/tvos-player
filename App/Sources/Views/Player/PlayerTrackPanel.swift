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

/// Spaltenbreiten und Zeilenhöhe (außerhalb des generischen Panels: dort gehen keine statischen Konstanten).
private enum Size {
    static let audioWidth: CGFloat = 520
    static let subtitleWidth: CGFloat = 460
    static let offsetWidth: CGFloat = 230
    static let rowHeight: CGFloat = 52
}

/// Welle F-h2: schmales Panel oben über dem laufenden Video (Wisch nach unten), höchstens ein Drittel hoch.
/// Spalten nebeneinander: Ton · Untertitel · Versatz, rechts Info als reine Textspalte. ◀/▶ wechselt die Spalte,
/// ▲/▼ die Zeile, Auswahl wirkt sofort (Häkchen). Menü oder Wisch nach oben aus der obersten Zeile schließt nur das
/// Panel, die Wiedergabe läuft weiter. Eigene Präsentation, damit Fokus und Menü-Taste im Panel bleiben.
struct PlayerTrackPanel<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let profile: Profile
    /// Adresse der Quelle (für den Dateinamen in der Info-Spalte).
    var sourceURL: URL? = nil
    /// Tonspur-Wechsel gesperrt (nach dem Hintergrund bis Play neu aufgebaut hat).
    var audioLocked = false
    /// Welle F-h R1: Spurwahl ganz gesperrt (Neuaufbau, Fehlerleiter, Start); nil = frei. Wird beim Wählen neu gelesen.
    var lock: () -> TrackLock? = { nil }
    /// Welle D-a: Nutzerwahl merken (Spur-Gedächtnis je Serie); nil = aus.
    var onRemember: ((TrackMemoryChange) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: TrackPanelSpot?
    /// Nutzer hat den Fokus bewegt (dann den Startfokus nicht mehr nachziehen).
    @State private var userMoved = false
    @State private var swipeUp = PanelSwipeUp()

    private var columns: [TrackPanelColumnModel] {
        let activeSub = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }
        return [TrackPanelLayout.audioColumn(engine.audioTracks, activeID: engine.activeAudioID, priority: profile.audioPriority),
                TrackPanelLayout.subtitleColumn(engine.subtitleTracks, activeID: engine.activeSubtitleID,
                                                preferredLanguage: profile.subtitleLanguage),
                TrackPanelLayout.offsetColumn(offset: engine.subtitleOffset, nativeTrack: activeSub?.isNativelyRendered == true)]
    }

    var body: some View {
        GeometryReader { geo in
            let height = TrackPanelLayout.panelHeight(screenHeight: Double(geo.size.height))
            panel
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: CGFloat(height), alignment: .top)
                .background {
                    ZStack { Rectangle().fill(.ultraThinMaterial); Theme.Palette.scrim }
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.overlayCard,
                                                          bottomTrailingRadius: Theme.Radius.overlayCard, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, TrackPanelLayout.initialSpot(columns))
        .onChange(of: focus) { old, new in
            // Erster Fokus beim Öffnen (old == nil) ist kein Nutzerschritt.
            guard let old, let new else { return }
            userMoved = true
            if let target = TrackPanelLayout.redirect(from: old, to: new, columns: columns) { focus = target }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            let start = TrackPanelLayout.initialSpot(columns)
            if !userMoved, focus != start { focus = start }
        }
        .onAppear {
            RemoteLog.info("player", "Panel auf")
            swipeUp.start(focus: { focus }) {
                guard TrackPanelLayout.closesOnSwipeUp(startSpot: $0, columns: columns) else { return }
                RemoteLog.info("player", "Panel zu (Wisch nach oben)")
                dismiss()
            }
        }
        .onDisappear { swipeUp.stop(); RemoteLog.info("player", "Panel zu") }
        .onExitCommand { dismiss() }
        .presentationBackground(.clear)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let l = lock() { Text(l.text).font(.caption).foregroundStyle(Theme.Palette.secondary) }
            HStack(alignment: .top, spacing: Theme.Space.l) {
                let cols = columns
                column(cols[0], width: Size.audioWidth, empty: "Keine Tonspuren")
                column(cols[1], width: Size.subtitleWidth, empty: nil)
                column(cols[2], width: Size.offsetWidth, empty: nil)
                infoColumn
            }
        }
        .padding(.horizontal, Theme.Space.edge)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.m)
    }

    // MARK: Spalte

    private func column(_ c: TrackPanelColumnModel, width: CGFloat, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            heading(c.title, note: c.note)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    if c.rows.isEmpty, let empty {
                        Text(empty).font(.callout).foregroundStyle(Theme.Palette.secondary)
                    }
                    ForEach(c.rows) { r in
                        Button { choose(TrackPanelSpot(c.column, r.id)) } label: { TrackPanelRowLabel(row: r, mark: c.column != .offset) }
                            .buttonStyle(TrackPanelRowStyle(height: Size.rowHeight))
                            .focused($focus, equals: TrackPanelSpot(c.column, r.id))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: width, alignment: .leading)
        .focusSection()
    }

    private func heading(_ title: String, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.Palette.secondary)
            if let note { Text(note).font(.caption2).foregroundStyle(Theme.Palette.secondary).lineLimit(1) }
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Info (ohne Fokus)

    private var infoColumn: some View {
        var snap = (engine as? any PlaybackTechInfoSource)?.trackPanelTech ?? PlaybackTechSnapshot()
        snap.fileName = TrackPanelLogic.sourceFileName(sourceURL)
        let rows = TrackPanelLogic.infoRows(snap)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            heading("Info", note: nil)
            if rows.isEmpty { Text("Noch keine Angaben").font(.caption).foregroundStyle(Theme.Palette.secondary) }
            ForEach(rows) { r in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(r.label).foregroundStyle(Theme.Palette.secondary)
                    Text(r.value).foregroundStyle(Theme.Palette.primary).truncationMode(.middle)
                }
                .font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Wählen

    private func choose(_ spot: TrackPanelSpot) {
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

    /// Ton: sofort wirksam, Panel bleibt offen (Häkchen wandert). Engine: sitzungserhaltendes Neuladen an derselben Stelle.
    private func chooseAudio(_ id: Int) {
        guard let t = engine.audioTracks.first(where: { $0.id == id }), !blocked() else { return }
        switch TrackChoice.audioAction(selected: t.id, active: engine.activeAudioID, locked: audioLocked) {
        case .apply: engine.selectAudio(t.id); onRemember?(.audio(t)); logChoice(audio: t)
        case .keep: onRemember?(.audio(t)); logChoice(audio: t)
        case .locked: RemoteLog.info("player", "Tonspur gewählt: \(t.id) · gesperrt bis Play")
        }
    }

    /// Untertitel (auch „Aus“): Nutzerwahl, setzt subtitleChosenByUser; danach wählt keine Automatik mehr.
    private func chooseSubtitle(_ id: Int?) {
        let t = id.flatMap { id in engine.subtitleTracks.first { $0.id == id } }
        guard id == nil || t != nil, !blocked() else { return }
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

    /// Sperre beim Wählen: Hinweis loggen, Panel schließen, nichts umschalten. true = gesperrt.
    private func blocked() -> Bool {
        guard let l = lock() else { return false }
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

/// Einzeilige Spurzeile: Häkchen, Text, kleine Marke. Farben aus den Tokens (liest den Fokus des Knopfs).
private struct TrackPanelRowLabel: View {
    let row: TrackPanelRow
    /// Häkchen-Platz (nicht in der Versatz-Spalte).
    let mark: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if mark {
                Image(systemName: "checkmark").font(.caption.bold()).opacity(row.isActive ? 1 : 0).frame(width: 28)
            }
            Text(row.line).font(.callout.weight(row.isActive ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
            if let tag = row.tag {
                ThemeBadge(kind: .tech(.poster), text: tag, surface: focused ? .focusedRow : .plain)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(focused ? Theme.Palette.primaryOnFocus : Theme.Palette.primary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isActive ? .isSelected : [])
    }
}

/// Zeilenstil im Panel: ruhend ohne Fläche (weißer Text auf dem dunklen Grund), fokussiert weiße Fläche mit
/// schwarzem Text und leichtem Anheben. Keine Systemfarben (kein Akzent-Blau).
private struct TrackPanelRowStyle: ButtonStyle {
    let height: CGFloat
    func makeBody(configuration: Configuration) -> some View { RowBody(configuration: configuration, height: height) }

    private struct RowBody: View {
        let configuration: Configuration
        let height: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, Theme.Space.s)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                .background(focused ? Theme.Palette.rowFocused : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.badge * 1.5, style: .continuous))
                .scaleEffect(configuration.isPressed ? Theme.Focus.pressedScale : (focused ? Theme.Focus.scale : 1))
                .animation(.easeOut(duration: Theme.Focus.duration), value: focused)
                .animation(.easeOut(duration: Theme.Focus.pressDuration), value: configuration.isPressed)
        }
    }
}

/// Welle F-h2: Wisch nach oben im Panel. Eigener Pan-Recognizer am Fenster, der Berührungen nicht schluckt
/// (die Fokussteuerung bewegt weiter die Zeilen). Merkt die Fokusstelle beim Wischbeginn: nur aus der obersten
/// Zeile schließt der Wisch, sonst war er ein Schritt nach oben.
@MainActor
final class PanelSwipeUp: NSObject, UIGestureRecognizerDelegate {
    private var recognizer: UIPanGestureRecognizer?
    private var focus: () -> TrackPanelSpot? = { nil }
    private var onSwipeUp: (TrackPanelSpot?) -> Void = { _ in }
    private var startSpot: TrackPanelSpot?

    func start(focus: @escaping () -> TrackPanelSpot?, onSwipeUp: @escaping (TrackPanelSpot?) -> Void) {
        stop()
        self.focus = focus
        self.onSwipeUp = onSwipeUp
        guard let window = PlayerWindow.key else { return }
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
    }

    @objc private func handle(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began: startSpot = focus()
        case .ended:
            let tr = g.translation(in: g.view)
            let vy = Double(g.velocity(in: g.view).y)
            if TrackPanelEntry.isSwipeUp(translationX: Double(tr.x), translationY: Double(tr.y), velocityY: vy) { onSwipeUp(startSpot) }
            startSpot = nil
        case .cancelled, .failed: startSpot = nil
        default: break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
