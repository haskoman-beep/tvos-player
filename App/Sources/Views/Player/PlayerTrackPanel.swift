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

/// Welle F-h3: Wahl ausführen, gemeinsam für Leiste und kleines Menü (Sperren, Tonwechsel-Wache, Gedächtnis, Logs).
@MainActor
struct TrackPicker<E: PlaybackEngine> {
    let engine: E
    /// Tonspur-Wechsel gesperrt (nach dem Hintergrund bis Play neu aufgebaut hat).
    let audioLocked: Bool
    /// Sperre beim Wählen frisch lesen; nil = frei.
    let lock: () -> TrackLock?
    /// Ton-Neuladen begonnen (Zielspur); der Player sperrt Untertitel/Versatz bis es fertig ist.
    let onAudioSwitch: (Int) -> Void
    /// Nutzerwahl merken (Spur-Gedächtnis je Serie); nil = aus.
    let onRemember: ((TrackMemoryChange) -> Void)?

    enum Result: Equatable {
        /// Gewählt (oder unverändert bestätigt).
        case done
        /// Gesperrt: nichts geschehen, Panel bleibt (Tonwechsel lädt).
        case ignored
        /// Gesperrt: Panel bzw. Menü schließen (Neuaufbau, Fehlerleiter, Start).
        case close
    }

    func pick(_ spot: TrackPanelSpot) -> Result {
        if let l = lock(), l.blocks(spot.column) {
            if l == .audioSwitching {
                RemoteLog.info("player", "Spurwahl gesperrt (Tonwechsel lädt)")
                return .ignored
            }
            RemoteLog.info("player", "Spurwahl gesperrt: \(l.logText)")
            return .close
        }
        switch (spot.column, spot.row) {
        case (.audio, .track(let id)): chooseAudio(id)
        case (.subtitles, .off): chooseSubtitle(nil)
        case (.subtitles, .track(let id)): chooseSubtitle(id)
        case (.offset, .step(let i)) where SubtitleOffset.steps.indices.contains(i):
            changeOffset(SubtitleOffset.adjusted(engine.subtitleOffset, by: SubtitleOffset.steps[i]))
        case (.offset, .reset): changeOffset(0)
        default: break
        }
        return .done
    }

    /// Ton: sofort wirksam (Häkchen wandert, sobald die Engine die Spur meldet). Läuft schon ein Tonwechsel,
    /// geht jede Wahl an die Engine (R2 N1).
    private func chooseAudio(_ id: Int) {
        guard let t = engine.audioTracks.first(where: { $0.id == id }) else { return }
        switch TrackChoice.audioAction(selected: t.id, active: engine.activeAudioID, locked: audioLocked,
                                       switching: lock() == .audioSwitching) {
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

    /// Untertitel-Versatz (Welle D-a).
    private func changeOffset(_ v: Double) {
        let n = SubtitleOffset.normalized(v)
        guard n != engine.subtitleOffset else { return }
        engine.setSubtitleOffset(n)
        let embedded = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }?.isExternal != true
        RemoteLog.info("player", "UT-Versatz: \(SubtitleOffset.label(n))"
                       + (n < 0 && embedded ? " · Vorauslesen der Engine aktiv (Fernquelle wird teils doppelt geladen)" : ""))
        onRemember?(.offset(n))
    }

    /// „Spurwahl: Ton <x> / UT <y>“ mit der neuen Wahl; der andere Teil ist die laufende Spur.
    /// `subtitle`: nil = unverändert, .some(nil) = Aus.
    private func logChoice(audio: AudioTrackInfo? = nil, subtitle: AudioTrackInfo?? = nil) {
        let a = audio ?? TrackChoice.active(engine.audioTracks, id: engine.activeAudioID)
        let u = subtitle ?? TrackChoice.active(engine.subtitleTracks, id: engine.activeSubtitleID)
        let ids = "Ton-ID \(a.map { String($0.id) } ?? "-") · UT-ID \(u.map { String($0.id) } ?? "aus")"
        RemoteLog.info("player", "Spurwahl: \(TrackChoice.summary(audio: a, subtitle: u)) (\(ids))")
    }
}

/// Welle F-h2: schmales Panel über dem laufenden Video, höchstens ein Drittel hoch; F-h3: oben oder unten angedockt.
/// Spalten nebeneinander: Ton · Untertitel · Versatz, darunter Info als eine Fußzeile. ◀/▶ wechselt die Spalte,
/// ▲/▼ die Zeile, Auswahl wirkt sofort (Häkchen). Menü schließt nur das Panel, die Wiedergabe läuft weiter; ebenso
/// ein Wisch zum Rand hin aus der Randzeile (oben: nach oben aus der obersten, unten: nach unten aus der untersten).
/// Eigene Präsentation, damit Fokus und Menü-Taste im Panel bleiben. Breiten und Zeichenbudget: `TrackPanelMetrics`.
struct PlayerTrackPanel<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let profile: Profile
    /// `.topBar` oder `.bottomBar` (`.menu` zeigt `PlayerTrackMenu`).
    var style: TrackPanelStyle = .topBar
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
    @StateObject private var swipe = PanelSwipe()

    private var atBottom: Bool { style == .bottomBar }

    private var picker: TrackPicker<E> {
        TrackPicker(engine: engine, audioLocked: audioLocked, lock: lock, onAudioSwitch: onAudioSwitch, onRemember: onRemember)
    }

    private var columns: [TrackPanelColumnModel] {
        TrackPanelColumns.make(engine: engine, profile: profile, audioLocked: audioLocked, lock: shownLock)
    }

    var body: some View {
        GeometryReader { geo in
            // Höhe ⅓ des ganzen Bildschirms; der Inhalt bleibt im Sicherheitsrand, nur der Grund reicht bis zur Kante.
            let screen = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let edgeInset = atBottom ? geo.safeAreaInsets.bottom : geo.safeAreaInsets.top
            let height = max(0, CGFloat(TrackPanelLayout.panelHeight(screenHeight: Double(screen))) - edgeInset)
            let r = Theme.Radius.overlayCard
            panel
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: height, alignment: .top)
                .clipped()
                .background {
                    ZStack { Rectangle().fill(.ultraThinMaterial); Theme.Palette.scrim }
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: atBottom ? r : 0, bottomLeadingRadius: atBottom ? 0 : r,
                                                          bottomTrailingRadius: atBottom ? 0 : r, topTrailingRadius: atBottom ? r : 0,
                                                          style: .continuous))
                        .ignoresSafeArea(edges: atBottom ? [.bottom, .horizontal] : [.top, .horizontal])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: atBottom ? .bottom : .top)
        }
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, TrackPanelLayout.initialSpot(columns))
        .onChange(of: focus) { old, new in
            swipe.spot = new
            // Erster Fokus beim Öffnen (old == nil) ist kein Nutzerschritt.
            guard let old, let new else { return }
            userMoved = true
            if let target = TrackPanelLayout.redirect(from: old, to: new, columns: columns) { focus = target }
        }
        .onChange(of: swipe.swipe) { _, e in
            guard let e, TrackPanelLayout.closesOnSwipe(e.gesture, style: style, startSpot: e.from, columns: columns) else { return }
            RemoteLog.info("player", "Panel zu (\(e.gesture.logText))")
            dismiss()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            let start = TrackPanelLayout.initialSpot(columns)
            if !userMoved, focus != start { focus = start }
        }
        .onAppear { RemoteLog.info("player", "Panel auf (\(style.title))"); swipe.start() }
        .onDisappear { swipe.stop(); RemoteLog.info("player", "Panel zu") }
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
            // R2 N3: bei Sperrzeile oben fällt die Info-Fußzeile weg, die Liste behält ≈ 3,5 Zeilen.
            if shownLock == nil || shownLock == .audioSwitching { infoLine }
        }
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
    }

    // MARK: Spalte

    private func column(_ c: TrackPanelColumnModel, width: Double, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            TrackPanelHeading(title: c.title, note: c.note)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    if c.rows.isEmpty, let empty {
                        Text(empty).font(.callout).foregroundStyle(Theme.Palette.secondary)
                    }
                    ForEach(c.rows) { r in
                        Button { choose(TrackPanelSpot(c.column, r.id)) } label: { TrackPanelRowLabel(row: r, mark: c.column != .offset) }
                            .buttonStyle(TrackPanelRowLabel.style)
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

    private func choose(_ spot: TrackPanelSpot) {
        if picker.pick(spot) == .close { dismiss() }
    }
}

/// Spalten aus dem Engine-Stand, mit Sperre (gemeinsam für Leiste und Menü).
@MainActor
enum TrackPanelColumns {
    static func make<E: PlaybackEngine>(engine: E, profile: Profile, audioLocked: Bool, lock: TrackLock?,
                                        audioWidth: Double = TrackPanelMetrics.audioColumnWidth,
                                        subtitleWidth: Double = TrackPanelMetrics.subtitleColumnWidth) -> [TrackPanelColumnModel] {
        let activeSub = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }
        return TrackPanelLayout.applying(lock, to: [
            TrackPanelLayout.audioColumn(engine.audioTracks, activeID: engine.activeAudioID, priority: profile.audioPriority,
                                         audioLocked: audioLocked, width: audioWidth),
            TrackPanelLayout.subtitleColumn(engine.subtitleTracks, activeID: engine.activeSubtitleID,
                                            preferredLanguage: profile.subtitleLanguage, width: subtitleWidth),
            TrackPanelLayout.offsetColumn(offset: engine.subtitleOffset, nativeTrack: activeSub?.isNativelyRendered == true)])
    }
}

/// Welle F-h3: kleines Menü unten rechts. Ebene 1: „Ton ›“, „Untertitel ›“, „Versatz ›“ mit der laufenden Wahl als
/// zweite Zeile; Ebene 2: die Liste (dieselben Zeilen wie in der Leiste). Menü-Taste: eine Ebene zurück, dann zu.
/// Navigation: `TrackMenuNav` (PlayerCore).
struct PlayerTrackMenu<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let profile: Profile
    var audioLocked = false
    var shownLock: TrackLock? = nil
    var lock: () -> TrackLock? = { nil }
    var onAudioSwitch: (Int) -> Void = { _ in }
    var onRemember: ((TrackMemoryChange) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var nav = TrackMenuNav()
    @FocusState private var focus: MenuFocus?

    enum MenuFocus: Hashable {
        case entry(TrackPanelColumn)
        case row(TrackPanelSpot)
    }

    private var picker: TrackPicker<E> {
        TrackPicker(engine: engine, audioLocked: audioLocked, lock: lock, onAudioSwitch: onAudioSwitch, onRemember: onRemember)
    }

    private var columns: [TrackPanelColumnModel] {
        TrackPanelColumns.make(engine: engine, profile: profile, audioLocked: audioLocked, lock: shownLock,
                               audioWidth: TrackMenuMetrics.width, subtitleWidth: TrackMenuMetrics.width)
    }

    private var entries: [TrackMenuEntry] { TrackMenuNav.entries(columns, offset: engine.subtitleOffset) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let l = shownLock, l != .audioSwitching { Text(l.text).font(.caption).foregroundStyle(Theme.Palette.secondary) }
            switch nav.level {
            case .root: rootLevel
            case .list(let c): if let col = columns.first(where: { $0.column == c }) { listLevel(col) }
            }
        }
        .padding(Theme.Space.s)
        .frame(width: CGFloat(TrackMenuMetrics.width), alignment: .leading)
        .background {
            ZStack { Rectangle().fill(.ultraThinMaterial); Theme.Palette.scrim }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.overlayCard, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, .entry(nav.rootFocus))
        .onAppear {
            nav = TrackMenuNav(entries: entries)
            RemoteLog.info("player", "Menü auf (Ton & Untertitel)")
            refocus()
        }
        .onDisappear { RemoteLog.info("player", "Menü zu") }
        .onExitCommand {
            switch nav.back() {
            case .toRoot: refocus()
            case .close: dismiss()
            }
        }
        .presentationBackground(.clear)
    }

    private var rootLevel: some View {
        VStack(alignment: .leading, spacing: 2) {
            TrackPanelHeading(title: "Ton & Untertitel", note: nil)
            ForEach(entries) { e in
                Button { openEntry(e) } label: { TrackMenuEntryLabel(entry: e) }
                    .buttonStyle(TrackPanelRowLabel.style)
                    .focused($focus, equals: .entry(e.column))
                    .disabled(e.isLocked || e.isEmpty)
            }
        }
    }

    private func listLevel(_ c: TrackPanelColumnModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            TrackPanelHeading(title: c.title, note: c.note)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(c.rows) { r in
                        let spot = TrackPanelSpot(c.column, r.id)
                        Button { choose(spot) } label: { TrackPanelRowLabel(row: r, mark: c.column != .offset) }
                            .buttonStyle(TrackPanelRowLabel.style)
                            .focused($focus, equals: .row(spot))
                            .disabled(c.isLocked)
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: CGFloat(TrackMenuMetrics.maxVisibleRows) * CGFloat(TrackMenuMetrics.rowHeight))
        }
    }

    private func openEntry(_ e: TrackMenuEntry) {
        guard nav.open(e) else { return }
        RemoteLog.info("player", "Menü: \(e.title)")
        refocus()
    }

    private func choose(_ spot: TrackPanelSpot) {
        switch picker.pick(spot) {
        case .close: dismiss()
        case .ignored: break
        case .done:
            let before = nav.level
            nav.picked(spot.column)
            if nav.level != before { refocus() }
        }
    }

    /// Fokus nach einem Ebenenwechsel setzen, sobald die neue Ebene steht.
    private func refocus() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            switch nav.level {
            case .root: focus = .entry(nav.rootFocus)
            case .list(let c):
                if let r = columns.first(where: { $0.column == c })?.entryRow { focus = .row(TrackPanelSpot(c, r)) }
            }
        }
    }
}

/// Überschrift einer Spalte bzw. Menü-Ebene mit gedimmtem Hinweis („lädt…“).
private struct TrackPanelHeading: View {
    let title: String
    let note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.Palette.primary)
            if let note { Text(note).font(.caption).foregroundStyle(Theme.Palette.secondary).lineLimit(1) }
        }
        .padding(.leading, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Eintrag der ersten Menü-Ebene: Titel mit „›“, darunter die laufende Wahl.
private struct TrackMenuEntryLabel: View {
    let entry: TrackMenuEntry
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: CGFloat(TrackPanelMetrics.spacing)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(entry.title).font(.callout.weight(.semibold))
                    if let note = entry.note { Text(note).font(.caption) }
                }
                Text(entry.detail).font(.caption).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(focused ? Theme.Palette.secondaryOnFocus : Theme.Palette.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold())
        }
        .foregroundStyle(focused ? Theme.Palette.primaryOnFocus : (enabled ? Theme.Palette.primary : Theme.Palette.secondary))
        .accessibilityElement(children: .combine)
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

    /// Zeilenstil für Leiste und Menü (Weiß auf dunkel, fokussiert Schwarz auf Weiß).
    static var style: ThemeRowButtonStyle {
        ThemeRowButtonStyle(minHeight: 0, maxWidth: .infinity, maxFocusGrowth: Theme.Focus.rowMaxGrowth,
                            restFill: .clear, verticalPadding: Theme.Space.xs)
    }

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

/// Welle F-h2/F-h3: senkrechter Wisch im Panel. Eigener Pan-Recognizer am Fenster, der Berührungen nicht schluckt
/// (die Fokussteuerung bewegt weiter die Zeilen). Merkt die Fokusstelle beim Wischbeginn (`spot`, vom Panel
/// gesetzt) und meldet den Wisch als veröffentlichtes Ereignis. R1 I1: keine gespeicherten Closures, also kein
/// Verweis zurück aufs Panel (und damit auf Backend und Engine); `stop()` löst den Recognizer.
@MainActor
final class PanelSwipe: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    struct Swipe: Equatable {
        let serial: Int
        let gesture: TrackPanelGesture
        let from: TrackPanelSpot?
    }

    /// Letzter senkrechter Wisch (Richtung, Fokus beim Beginn); das Panel entscheidet über `closesOnSwipe`.
    @Published private(set) var swipe: Swipe?
    /// Aktuelle Fokusstelle (vom Panel nachgeführt).
    var spot: TrackPanelSpot?
    private var startSpot: TrackPanelSpot?
    private var serial = 0
    private var recognizer: UIPanGestureRecognizer?

    func start() {
        stop()
        guard let window = PlayerWindow.key else {
            RemoteLog.info("player", "Panel: kein Fenster für Wisch zum Schließen")
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
            let gesture: TrackPanelGesture? =
                TrackPanelEntry.isSwipeUp(translationX: Double(tr.x), translationY: Double(tr.y), velocityY: vy) ? .swipeUp
                : TrackPanelEntry.isSwipeDown(translationX: Double(tr.x), translationY: Double(tr.y), velocityY: vy) ? .swipeDown
                : nil
            if let gesture {
                serial += 1
                swipe = Swipe(serial: serial, gesture: gesture, from: startSpot)
            }
            startSpot = nil
        case .cancelled, .failed: startSpot = nil
        default: break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
