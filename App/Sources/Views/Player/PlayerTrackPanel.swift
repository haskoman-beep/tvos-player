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

/// Task 5.4 (`player.trackPanel`): Ton & Untertitel over the running video in three layouts (`TrackPanelStyle`
/// keeps the stored names and the gestures of Build 198):
/// - Seite (`topBar`, swipe down / ▼): panel from the right, 640 wide, full height; Ton, below it Untertitel and
///   Versatz. A swipe up from the very top closes it (`TrackPanelLayout.closesOnSwipe`).
/// - Unten (`bottomBar`, swipe up / ▲): card 80 from the left/right and 60 from the bottom, one row with the
///   columns Ton | Untertitel (plan, user decision 26.11.), Versatz as a strip of steps below them. A swipe down
///   from the lowest row (the strip) closes it.
/// - Mitte (`menu`, swipe up / ▲): the picture dimmed 45 %, a card 1000 wide in the centre (top 190) with the
///   columns Ton | Untertitel (Versatz below Untertitel). Only Menu closes it.
/// Selection works at once (checkmark). Menu closes only the panel, playback keeps running. Info as one footer line.
/// Own presentation, so focus and the Menu key stay in the panel. Widths and character budget: `TrackPanelMetrics`.
struct PlayerTrackPanel<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let profile: Profile
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
    /// F-h3 R1: vom unteren Bildrand bedeckte Höhe (Unten, Mitte), damit der Player die Untertitel darüber hebt.
    var onCoverBottom: (CGFloat) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @FocusState private var focus: TrackPanelSpot?
    /// Nutzer hat den Fokus bewegt (dann den Startfokus nicht mehr nachziehen).
    @State private var userMoved = false
    /// Einmal je Panel (StateObject); hält keine Closures, also keinen Verweis zurück aufs Panel (R1 I1).
    @StateObject private var swipe = PanelSwipe()
    /// p0a1 panel: column models of this panel, rebuilt only when their inputs change (`TrackPanelColumnCache`).
    @State private var columnCache = TrackPanelColumnCache()

    private var picker: TrackPicker<E> {
        TrackPicker(engine: engine, audioLocked: audioLocked, lock: lock, onAudioSwitch: onAudioSwitch, onRemember: onRemember)
    }

    private var columns: [TrackPanelColumnModel] {
        let w = TrackPanelLook.widths(style)
        return columnCache.columns(engine: engine, profile: profile, audioLocked: audioLocked, lock: shownLock,
                                   audioWidth: w.audio, subtitleWidth: w.subtitles)
    }

    var body: some View {
        ZStack {
            if style == .menu {
                Color.black.opacity(OverlayCardMetrics.dimTrackCard).ignoresSafeArea().allowsHitTesting(false)
            }
            switch style {
            case .topBar: sidePanel
            case .bottomBar: bottomCard
            case .menu: centreCard
            }
        }
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, TrackPanelLayout.initialSpot(columns))
        .onChange(of: focus) { old, new in
            swipe.spot = new
            // Erster Fokus beim Öffnen (old == nil) ist kein Nutzerschritt.
            guard let old, let new else { return }
            userMoved = true
            columnCache.focusMoves += 1
            PanelFrameMeter.focusMoved()
            // Task 5.4: stacked sections (Seite) and the step up from Versatz in Mitte keep the row the focus engine
            // chose; Unten keeps the redirect onto the active row (Build 198).
            guard !style.isStacked, !(style == .menu && old.column == .offset) else { return }
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
        .onAppear {
            RemoteLog.info("player", "Panel auf (\(style.title))")
            swipe.start()
            onCoverBottom(TrackPanelLook.coveredBottom(style))
        }
        .onDisappear {
            swipe.stop()
            PanelFrameMeter.stop()
            RemoteLog.info("player", "Panel zu")
            RemoteLog.info("player", columnCache.summary)
        }
        .onExitCommand { dismiss() }
        .presentationBackground(.clear)
    }

    // MARK: Layouts

    private var sidePanel: some View {
        let cols = columns
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.space.l) {
                lockLine
                section(cols[0], empty: "Keine Tonspuren")
                section(cols[1], empty: nil)
                section(cols[2], empty: nil)
                if showsInfo { infoLine }
            }
            .padding(.horizontal, TrackPanelLook.sidePaddingH)
            .padding(.vertical, TrackPanelLook.sidePaddingV)
        }
        .frame(width: TrackPanelLook.sideWidth)
        .frame(maxHeight: .infinity)
        .overlayCard(.flush, lifted: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .ignoresSafeArea()
    }

    private var bottomCard: some View {
        let cols = columns, w = TrackPanelLook.widths(.bottomBar)
        return VStack(alignment: .leading, spacing: theme.space.xs) {
            lockLine
            HStack(alignment: .top, spacing: TrackPanelLook.columnSpacing) {
                column(cols[0], width: w.audio, empty: "Keine Tonspuren")
                column(cols[1], width: w.subtitles, empty: nil)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            offsetStrip(cols[2])
            // R2 N3: bei Sperrzeile oben fällt die Info-Fußzeile weg, die Liste behält ≈ 3,5 Zeilen.
            if showsInfo { infoLine }
        }
        .padding(OverlayCardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: TrackPanelLook.bottomHeight, alignment: .top)
        .overlayCard()
        .padding(.horizontal, TrackPanelLook.edgeH).padding(.bottom, TrackPanelLook.edgeBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }

    private var centreCard: some View {
        let cols = columns, w = TrackPanelLook.widths(.menu)
        return VStack(alignment: .leading, spacing: theme.space.xs) {
            lockLine
            HStack(alignment: .top, spacing: TrackPanelLook.columnSpacing) {
                column(cols[0], width: w.audio, empty: "Keine Tonspuren")
                VStack(alignment: .leading, spacing: theme.space.m) {
                    column(cols[1], width: w.subtitles, empty: nil)
                    column(cols[2], width: w.subtitles, empty: nil)
                        .frame(height: TrackPanelLook.centreOffsetHeight, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            if showsInfo { infoLine }
        }
        .padding(OverlayCardMetrics.padding)
        .frame(width: TrackPanelLook.centreWidth, height: TrackPanelLook.centreHeight, alignment: .topLeading)
        .overlayCard()
        .padding(.top, TrackPanelLook.centreTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private var showsInfo: Bool { shownLock == nil || shownLock == .audioSwitching }

    @ViewBuilder private var lockLine: some View {
        if let l = shownLock, l != .audioSwitching { Text(l.text).textRole(.rowDetail) }
    }

    // MARK: Spalte

    /// Column side by side (Unten, Mitte): heading, own scroll list.
    private func column(_ c: TrackPanelColumnModel, width: Double, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            TrackPanelHeading(title: c.title, note: c.note)
            ScrollView(.vertical) { rows(c, empty: empty) }
        }
        .frame(width: CGFloat(width), alignment: .leading)
        .focusSection()
    }

    /// Versatz in „Unten“: heading and the steps side by side in one row below Ton | Untertitel.
    private func offsetStrip(_ c: TrackPanelColumnModel) -> some View {
        HStack(alignment: .center, spacing: theme.space.s) {
            TrackPanelHeading(title: c.title, note: c.note)
                .frame(width: TrackPanelLook.stripHeadingWidth, alignment: .leading)
            ForEach(c.rows) { r in
                Button { choose(TrackPanelSpot(c.column, r.id)) } label: { TrackPanelRowLabel(row: r, mark: false) }
                    .buttonStyle(TrackPanelRowLabel.style)
                    .focused($focus, equals: TrackPanelSpot(c.column, r.id))
                    .disabled(c.isLocked)
                    .frame(width: r.id == .reset ? TrackPanelLook.stripResetWidth : TrackPanelLook.stripStepWidth)
            }
        }
        .padding(.horizontal, theme.space.xs)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// Section of the stacked side panel: heading and rows; the panel scrolls as a whole.
    private func section(_ c: TrackPanelColumnModel, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            TrackPanelHeading(title: c.title, note: c.note)
            rows(c, empty: empty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func rows(_ c: TrackPanelColumnModel, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if c.rows.isEmpty, let empty {
                Text(empty).textRole(.rowDetail)
            }
            ForEach(c.rows) { r in
                Button { choose(TrackPanelSpot(c.column, r.id)) } label: { TrackPanelRowLabel(row: r, mark: c.column != .offset) }
                    .buttonStyle(TrackPanelRowLabel.style)
                    .focused($focus, equals: TrackPanelSpot(c.column, r.id))
                    .disabled(c.isLocked)
            }
        }
        // Platz fürs Anheben der fokussierten Zeile (TrackPanelMetrics.listInset).
        .padding(.horizontal, theme.space.xs)
        .padding(.vertical, 4)
    }

    // MARK: Info (ohne Fokus, eine Zeile)

    @ViewBuilder private var infoLine: some View {
        let snap: PlaybackTechSnapshot = {
            var s = (engine as? any PlaybackTechInfoSource)?.trackPanelTech ?? PlaybackTechSnapshot()
            s.fileName = TrackPanelLogic.sourceFileName(sourceURL)
            return s
        }()
        if let line = TrackPanelLayout.infoLine(TrackPanelLogic.infoRows(snap)) {
            Text(line).textRole(.rowDetail).lineLimit(style.isStacked ? 3 : 1).truncationMode(.middle)
                .padding(.leading, theme.space.xs)
        }
    }

    private func choose(_ spot: TrackPanelSpot) {
        if picker.pick(spot) == .close { dismiss() }
    }
}

/// Task 5.4: sizes of the three track panel layouts on the 1920 × 1080 screen (configurator scene „Player“).
enum TrackPanelLook {
    static let sideWidth: CGFloat = 640
    static let sidePaddingH: CGFloat = 50
    static let sidePaddingV: CGFloat = 80
    static let edgeH: CGFloat = 80
    static let edgeBottom: CGFloat = 60
    static let columnSpacing: CGFloat = 40
    /// Card „Unten“: ⅓ of the screen plus the card padding, so the lists keep ≈ 3,5 rows as the old bar; 60 more
    /// for the Versatz strip below the two columns (user decision 26.11.).
    static let bottomHeight: CGFloat = 460
    /// Versatz strip in „Unten“: heading („Versatz +0,5 s“, note), four steps and „Zurücksetzen“.
    static let stripHeadingWidth: CGFloat = 300
    static let stripStepWidth: CGFloat = 170
    static let stripResetWidth: CGFloat = 260
    static let centreWidth: CGFloat = 1000
    static let centreTop: CGFloat = 190
    static let centreHeight: CGFloat = 700
    /// Versatz under Untertitel in „Mitte“: heading plus about four rows; the rest scrolls.
    static let centreOffsetHeight: CGFloat = 250

    /// Column widths for the character budget of the rows (`TrackPanelMetrics.lineBudget`).
    static func widths(_ style: TrackPanelStyle) -> (audio: Double, subtitles: Double) {
        switch style {
        case .topBar:
            let w = Double(sideWidth - 2 * sidePaddingH)
            return (w, w)
        case .bottomBar:
            // 1920 − 2 × 80 − 2 × 36 = 1688: 840 + 808 + 40 = 1688 (two columns, Versatz as a strip below).
            return (840, 808)
        case .menu:
            let w = Double(centreWidth - 2 * OverlayCardMetrics.padding - columnSpacing) / 2
            return (w, w)
        }
    }

    /// Height covered from the bottom screen edge (the player lifts the subtitles above it); 0 = none.
    static func coveredBottom(_ style: TrackPanelStyle) -> CGFloat {
        switch style {
        case .topBar: 0
        case .bottomBar: bottomHeight + edgeBottom
        // The centre card ends 190 above the bottom edge: the subtitles stay where they are, below it.
        case .menu: 0
        }
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

/// p0a1 panel: column models of one open panel. Building them is the costly part of the panel body (11 Ton, 39 UT:
/// language names through `Locale` several times per track, line fitting, duplicate checks), and the body ran it up
/// to three times per focus step in „Unten“ (`defaultFocus`, the layout, the redirect in `onChange(of: focus)`) and
/// again on every engine publish. Now it runs once per change of tracks, choice, offset, lock, profile languages or
/// widths; focus steps read the stored models. Counters for the line `Panel-Messung` when the panel closes.
@MainActor
final class TrackPanelColumnCache {
    private struct Key: Equatable {
        var audio: [AudioTrackInfo]
        var subtitles: [AudioTrackInfo]
        var activeAudio: Int?
        var activeSubtitle: Int?
        var offset: Double
        var audioPriority: [String]
        var subtitleLanguage: String
        var audioLocked: Bool
        var lock: TrackLock?
        var audioWidth: Double
        var subtitleWidth: Double
    }

    private var key: Key?
    private var stored: [TrackPanelColumnModel] = []
    private var builds = 0
    private var hits = 0
    private var longestBuild: Duration = .zero
    private var totalBuild: Duration = .zero
    /// Focus steps of the user in this panel (set by the panel).
    var focusMoves = 0

    func columns<E: PlaybackEngine>(engine: E, profile: Profile, audioLocked: Bool, lock: TrackLock?,
                                    audioWidth: Double, subtitleWidth: Double) -> [TrackPanelColumnModel] {
        let k = Key(audio: engine.audioTracks, subtitles: engine.subtitleTracks, activeAudio: engine.activeAudioID,
                    activeSubtitle: engine.activeSubtitleID, offset: engine.subtitleOffset,
                    audioPriority: profile.audioPriority, subtitleLanguage: profile.subtitleLanguage,
                    audioLocked: audioLocked, lock: lock, audioWidth: audioWidth, subtitleWidth: subtitleWidth)
        if k == key { hits += 1; return stored }
        let clock = ContinuousClock()
        let start = clock.now
        stored = TrackPanelColumns.make(engine: engine, profile: profile, audioLocked: audioLocked, lock: lock,
                                        audioWidth: audioWidth, subtitleWidth: subtitleWidth)
        let took = clock.now - start
        key = k
        builds += 1
        totalBuild += took
        if took > longestBuild { longestBuild = took }
        return stored
    }

    /// „Panel-Messung: Fokus 12 Schritte · Spalten neu 2× (längster 3,4 ms, zusammen 5,1 ms) · aus Speicher 31×“.
    var summary: String {
        "Panel-Messung: Fokus \(focusMoves) Schritte · Spalten neu \(builds)× (längster \(Self.ms(longestBuild)) ms, "
            + "zusammen \(Self.ms(totalBuild)) ms) · aus Speicher \(hits)×"
    }

    /// Milliseconds with one decimal and a German comma („3,4“).
    private static func ms(_ d: Duration) -> String {
        let c = d.components
        let tenths = Int((Double(c.seconds) * 10_000 + Double(c.attoseconds) / 1e14).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }
}

/// Überschrift einer Spalte bzw. Menü-Ebene mit gedimmtem Hinweis („lädt…“).
private struct TrackPanelHeading: View {
    let title: String
    let note: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.space.xs) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(theme.color.primary)
            if let note { Text(note).textRole(.rowDetail).lineLimit(1) }
        }
        .padding(.leading, theme.space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
    @Environment(\.theme) private var theme

    /// Zeilenstil für Leiste und Menü (Weiß auf dunkel, fokussiert Schwarz auf Weiß).
    static var style: ThemeRowButtonStyle {
        ThemeRowButtonStyle(minHeight: 0, maxWidth: .infinity, maxFocusGrowth: Theme.Focus.rowMaxGrowth,
                            restFill: .clear, verticalPadding: Theme.Space.xs)
    }

    var body: some View {
        HStack(spacing: CGFloat(TrackPanelMetrics.spacing)) {
            if mark {
                Image(systemName: "checkmark").font(.callout.bold()).opacity(row.isActive ? 1 : 0)
                    .frame(width: CGFloat(TrackPanelMetrics.markWidth))
            }
            Text(row.line).font(.callout.weight(row.isActive ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
            if let tag = row.tag {
                ThemeBadge(kind: .tech(.poster), text: tag, surface: focused ? .focusedRow : .plain)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(focused ? theme.color.primaryOnFocus : (enabled ? theme.color.primary : theme.color.secondary))
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
