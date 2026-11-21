import SwiftUI
import AetherFEL
import PlayerCore

/// Backends, die Technik-Rohwerte für den Info-Reiter liefern (Auflösung, Dynamik, Tonkette).
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

/// Reiter des Spur-Panels.
enum PlayerTrackTab: Hashable, CaseIterable {
    case info, audio, subtitles
    var title: String {
        switch self {
        case .info: "Info"
        case .audio: "Ton"
        case .subtitles: "Untertitel"
        }
    }
}

/// Panel unten über dem laufenden Video (Wisch nach unten): Reiter Info · Ton · Untertitel.
/// Wird als eigene Präsentation gezeigt, damit Fokus und Menü-Taste im Panel bleiben:
/// Menü schließt nur das Panel, die Wiedergabe läuft weiter.
struct PlayerTrackPanel<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let profile: Profile
    /// Adresse der Quelle (für den Dateinamen im Info-Reiter).
    var sourceURL: URL? = nil
    /// Tonspur-Wechsel gesperrt (nach dem Hintergrund bis Play neu aufgebaut hat).
    var audioLocked = false
    /// Welle D-a: Nutzerwahl merken (Spur-Gedächtnis je Serie); nil = aus.
    var onRemember: ((TrackMemoryChange) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var tab: PlayerTrackTab = .audio
    @FocusState private var focus: Focus?
    /// Nutzer hat den Fokus bewegt (dann den Startfokus nicht mehr nachziehen).
    @State private var userMoved = false

    private enum Focus: Hashable {
        case tab(PlayerTrackTab)
        case audio(Int)
        case subtitleOff
        case subtitle(Int)
        /// Versatz-Knopf (Index in `SubtitleOffset.steps`) bzw. Zurücksetzen.
        case offsetStep(Int)
        case offsetReset
    }

    /// Startfokus: Reiter Ton auf der aktiven Spur (ohne Tonspuren: der Reiter selbst).
    private var initialFocus: Focus {
        if let id = engine.activeAudioID, engine.audioTracks.contains(where: { $0.id == id }) { return .audio(id) }
        if let first = engine.audioTracks.first { return .audio(first.id) }
        return .tab(.audio)
    }

    /// Aktive Untertitelzeile ("Aus", wenn keiner läuft oder die Spur fehlt).
    private var activeSubtitleFocus: Focus {
        if let id = engine.activeSubtitleID, engine.subtitleTracks.contains(where: { $0.id == id }) { return .subtitle(id) }
        return .subtitleOff
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            tabBar.focusSection()
            content.focusSection()
        }
        .padding(.horizontal, 40).padding(.top, 30).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 600, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 60).padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .defaultFocus($focus, initialFocus)
        .onChange(of: focus) { old, new in
            // Erster Fokus beim Öffnen (old == nil) ist kein Nutzerschritt: nichts umschalten.
            guard let old, let new else { return }
            userMoved = true
            if case .tab(let t) = new {
                guard t != tab else { return }
                // Von einer Zeile nach oben: zurück auf den offenen Reiter, nicht den nächstgelegenen.
                if !isTab(old) { focus = .tab(tab) } else { tab = t }
                return
            }
            // Vom Reiter in die Untertitel-Liste: auf die aktive Zeile.
            if isTab(old), tab == .subtitles, new != activeSubtitleFocus { focus = activeSubtitleFocus }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            if !userMoved, focus != initialFocus { tab = .audio; focus = initialFocus }
        }
        .onAppear { RemoteLog.info("player", "Panel auf") }
        .onDisappear { RemoteLog.info("player", "Panel zu") }
        .onExitCommand { dismiss() }
        .presentationBackground(.clear)
    }

    private func isTab(_ f: Focus) -> Bool { if case .tab = f { return true }; return false }

    // MARK: Reiter

    private var tabBar: some View {
        HStack(spacing: 20) {
            ForEach(PlayerTrackTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    FocusHighlight {
                        Text(t.title)
                            .font(.headline)
                            .foregroundStyle(t == tab ? Color.white : Color.secondary)
                            .padding(.bottom, 4)
                            .overlay(alignment: .bottom) {
                                if t == tab { Capsule().fill(Color.white).frame(height: 4) }
                            }
                    }
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .tab(t))
            }
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .info: infoTab
        case .audio: audioTab
        case .subtitles: subtitleTab
        }
    }

    // MARK: Info

    private var infoTab: some View {
        var snap = (engine as? any PlaybackTechInfoSource)?.trackPanelTech ?? PlaybackTechSnapshot()
        snap.fileName = TrackPanelLogic.sourceFileName(sourceURL)
        let rows = TrackPanelLogic.infoRows(snap)
        return VStack(alignment: .leading, spacing: 14) {
            if rows.isEmpty { Text("Noch keine Angaben").foregroundStyle(.secondary) }
            ForEach(rows) { r in
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(r.label).foregroundStyle(.secondary).frame(width: 260, alignment: .leading)
                    Text(r.value).lineLimit(1).truncationMode(.middle)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ton

    private var audioTab: some View {
        let tracks = TrackPanelLogic.sortedAudio(engine.audioTracks, priority: profile.audioPriority)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                if tracks.isEmpty { Text("Keine Tonspuren").foregroundStyle(.secondary).padding(16) }
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                    row(TrackPanelLogic.audioRow(t, number: i + 1), active: t.id == engine.activeAudioID) {
                        RemoteLog.info("player", "Tonspur gewählt: \(t.id)\(audioLocked ? " · gesperrt bis Play" : "")")
                        if !audioLocked { engine.selectAudio(t.id); onRemember?(.audio(t)) }
                        dismiss()
                    }
                    .focused($focus, equals: .audio(t.id))
                }
            }
        }
    }

    // MARK: Untertitel

    private var subtitleTab: some View {
        // Liste kommt live aus der Engine: nachgeladene (externe/Addon-)Spuren erscheinen von selbst.
        let groups = TrackPanelLogic.subtitleGroups(engine.subtitleTracks, preferredLanguage: profile.subtitleLanguage)
        // selectSubtitle ist die Nutzerwahl (auch „Aus“): setzt subtitleChosenByUser, danach wählt keine Automatik
        // mehr, auch der Addon-Loader nicht (der fügt dann nur noch Spuren hinzu).
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                offsetRow
                row(TrackRowLabel(title: "Aus", detail: nil, name: nil, badges: []), active: engine.activeSubtitleID == nil) {
                    RemoteLog.info("player", "Untertitel aus")
                    engine.selectSubtitle(nil); onRemember?(.subtitle(nil)); dismiss()
                }
                .focused($focus, equals: .subtitleOff)
                ForEach(groups, id: \.code) { g in
                    Text(g.header)
                        .font(.callout.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 18)
                    ForEach(Array(g.tracks.enumerated()), id: \.element.id) { i, t in
                        row(TrackPanelLogic.subtitleRow(t, number: i + 1), active: t.id == engine.activeSubtitleID) {
                            RemoteLog.info("player", "Untertitel gewählt: \(t.id)")
                            engine.selectSubtitle(t.id); onRemember?(.subtitle(t)); dismiss()
                        }
                        .focused($focus, equals: .subtitle(t.id))
                    }
                }
            }
        }
    }

    // MARK: Untertitel-Versatz (Welle D-a)

    /// Versatz für eingebettete und Addon-Untertitel; Knöpfe schließen das Panel nicht.
    private var offsetRow: some View {
        let value = engine.subtitleOffset
        let active = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("Versatz").font(.callout.bold()).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                ForEach(Array(SubtitleOffset.steps.enumerated()), id: \.offset) { i, step in
                    if i == SubtitleOffset.steps.count / 2 {
                        Text(SubtitleOffset.label(value)).font(.body.monospacedDigit().weight(.semibold))
                            .frame(width: 150)
                    }
                    Button { changeOffset(SubtitleOffset.adjusted(engine.subtitleOffset, by: step)) } label: {
                        FocusHighlight { Text(SubtitleOffset.stepLabel(step)).font(.body.monospacedDigit()) }
                    }
                    .buttonStyle(.plain)
                    .focused($focus, equals: .offsetStep(i))
                }
                Button { changeOffset(0) } label: { FocusHighlight { Text("Zurücksetzen").font(.body) } }
                    .buttonStyle(.plain)
                    .focused($focus, equals: .offsetReset)
                Spacer(minLength: 0)
            }
            Text(active?.isNativelyRendered == true
                 ? "Diese Spur zeichnet das System: der Versatz wirkt hier nicht."
                 : SubtitleOffset.hint(value) + (value < 0 && active?.isExternal != true
                                                  ? " · Früher anzeigen lädt den Film teils doppelt" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func changeOffset(_ v: Double) {
        let n = SubtitleOffset.normalized(v)
        guard n != engine.subtitleOffset else { return }
        engine.setSubtitleOffset(n)
        let embedded = engine.subtitleTracks.first { $0.id == engine.activeSubtitleID }?.isExternal != true
        RemoteLog.info("player", "UT-Versatz: \(SubtitleOffset.label(n))"
                       + (n < 0 && embedded ? " · Vorauslesen der Engine aktiv (Fernquelle wird teils doppelt geladen)" : ""))
        onRemember?(.offset(n))
    }

    // MARK: Zeile

    private func row(_ l: TrackRowLabel, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FocusHighlight {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: "checkmark").font(.callout.bold()).opacity(active ? 1 : 0).frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 14) {
                            Text(l.title).font(.body.weight(active ? .semibold : .regular))
                            if let n = l.name { Text(n).font(.body).foregroundStyle(.secondary).lineLimit(1) }
                            ForEach(l.badges, id: \.self) { b in Badge(b, .gray) }
                        }
                        if let d = l.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
