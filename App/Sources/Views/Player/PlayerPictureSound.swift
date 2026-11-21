import SwiftUI
import UIKit
import AetherFEL
import PlayerCore

// Welle D-a (Bild und Ton): Untertitel-Versatz, Zeichensatz der Addon-Untertitel, Bildschirmschoner,
// Spur-Wahl je Serie, eigener Fortschritt für Dateien ohne IMDb-ID (TorBox).

// MARK: Untertitel-Versatz

extension AetherBackend {
    /// Engine-Versatz für Software-Untertitel (`softwareSubtitleDelaySeconds`); das Overlay zeichnet gegen
    /// `Quellzeit - Versatz` (SubtitleOverlayView.time). Bei negativem Versatz liest die Engine selbst voraus,
    /// bei positivem hält sie die nötige Vorgeschichte. Systemseitig gezeichnete Spuren (AVPlayer) verschiebt er nicht.
    var subtitleOffset: Double { engine.softwareSubtitleDelaySeconds }

    func setSubtitleOffset(_ seconds: Double) {
        let v = SubtitleOffset.normalized(seconds)
        guard v != engine.softwareSubtitleDelaySeconds else { return }
        objectWillChange.send()   // Wert ist in der Engine nicht veröffentlicht: Panel neu zeichnen
        engine.setSoftwareSubtitleDelay(v)
    }
}

// MARK: Bildschirmschoner

/// `isIdleTimerDisabled` gehört immer genau einem Player (Kennung); ein später verschwindender alter Player
/// gibt den Schoner des neuen nicht frei.
@MainActor
enum PlayerIdleTimer {
    private static var owner: UUID?

    static func set(_ disabled: Bool, token: UUID) {
        if disabled { owner = token } else if owner == token { owner = nil } else if owner != nil { return }
        guard UIApplication.shared.isIdleTimerDisabled != disabled else { return }
        UIApplication.shared.isIdleTimerDisabled = disabled
        RemoteLog.info("player", "Bildschirmschoner \(disabled ? "gesperrt" : "frei")")
    }

    static func release(token: UUID) {
        guard owner == token || owner == nil else { return }
        owner = nil
        guard UIApplication.shared.isIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        RemoteLog.info("player", "Bildschirmschoner frei (Player verlassen)")
    }
}

extension PlayerControls {
    /// Jede Sekunde (und beim Erscheinen): Spielen, Laden, Nachpuffern sperren; Pause nur bis zur Grenze aus dem Profil.
    func idleTick() {
        guard !leaving else { releaseIdleTimer(); return }
        idle.pauseLimitMinutes = profile.player.screensaverPauseMinutes
        let busy = engine.isPlaying || engine.isLoading || engine.loadActivity.buffering || stab.loadInFlight || restoring
        PlayerIdleTimer.set(idle.update(busy: busy), token: idleToken)
    }

    /// Über `leave` und beim echten Verschwinden.
    func releaseIdleTimer() {
        idle.reset()
        PlayerIdleTimer.release(token: idleToken)
    }
}

// MARK: Spur-Wahl je Serie

extension PlayerControls {
    /// Gemerkte Tonspur, falls die Sprache in der Datei vorkommt (vor der Automatik).
    func rememberedAudio() -> AudioTrackInfo? {
        guard let m = trackMemory else { return nil }
        let t = TrackMemoryPlan.audio(m, tracks: engine.audioTracks)
        if let t { RemoteLog.info("player", "Tonspur aus Spur-Gedächtnis: \(t.id) · \(t.language ?? "?")") }
        return t
    }

    /// Gemerkter Versatz und Untertitel beim Start. true = Untertitel festgelegt (dann keine Automatik).
    /// Fehlt die gemerkte Sprache noch, versucht es der Addon-Loader nach dem Hinzufügen erneut.
    func applyRememberedSubtitles() -> Bool {
        guard let m = trackMemory else { return false }
        if let o = m.subtitleOffset, o != 0 {
            engine.setSubtitleOffset(o)
            RemoteLog.info("player", "UT-Versatz aus Spur-Gedächtnis: \(SubtitleOffset.label(o))")
        }
        switch TrackMemoryPlan.subtitle(m, tracks: engine.subtitleTracks) {
        case .automatic:
            subtitleMemoryPending = m.subtitle != nil
            return false
        case .off:
            engine.selectSubtitle(nil)
            RemoteLog.info("player", "UT aus Spur-Gedächtnis: aus")
            return true
        case .track(let id):
            engine.selectSubtitle(id)
            RemoteLog.info("player", "UT aus Spur-Gedächtnis: \(id)")
            return true
        }
    }

    /// Nach dem Hinzufügen von Addon-Untertiteln: gemerkte Sprache jetzt da? true = gewählt.
    func applyPendingSubtitleMemory() -> Bool {
        guard subtitleMemoryPending, !engine.subtitleChosenByUser else { return false }
        guard case .track(let id) = TrackMemoryPlan.subtitle(trackMemory, tracks: engine.subtitleTracks) else { return false }
        subtitleMemoryPending = false
        engine.selectSubtitle(id)
        RemoteLog.info("player", "Addon-UT aus Spur-Gedächtnis: \(id)")
        return true
    }
}

// MARK: Eigener Fortschritt (TorBox)

/// Fortschritt außerhalb von `ProgressBook` (kein Weiterschauen, kein Scrobble), z. B. TorBox-Dateien.
struct OwnProgress {
    var start: Double?
    var record: (Double, Double) -> Void
}

// MARK: Zeichensatz der Addon-Untertitel

/// Text-Untertitel aus Addons selbst laden, Zeichensatz erkennen (`SubtitleCharset`) und als UTF-8-Datei ohne BOM
/// an die Engine geben. Scheitert das Laden, bekommt die Engine die Adresse wie bisher.
enum AddonSubtitleFiles {
    static let textFormats: Set<String> = ["srt", "vtt", "ass", "ssa"]
    static let maxBytes = 5 * 1024 * 1024
    static let timeout: TimeInterval = 10
    /// Dateien in Caches/AddonSubtitles; ältere als 24 h räumt der erste Aufruf je App-Start weg.
    @MainActor private static var cleaned = false

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AddonSubtitles", isDirectory: true)
    }

    /// Addon-URL → lokale Datei (nur geglückte).
    @MainActor
    static func prepare(_ subs: [AddonSubtitle]) async -> [String: URL] {
        let wanted = subs.filter { textFormats.contains($0.formatHint) }
        guard !wanted.isEmpty else { return [:] }
        if !cleaned { cleaned = true; await Task.detached(priority: .utility) { cleanup() }.value }
        let results = await withTaskGroup(of: (String, URL?, String?).self) { group in
            for s in wanted {
                group.addTask { await fetch(s.url, format: s.formatHint) }
            }
            var out: [(String, URL?, String?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var map: [String: URL] = [:]
        var notes: [String] = []
        for (src, file, note) in results {
            if let file { map[src] = file }
            if let note { notes.append(note) }
        }
        RemoteLog.info("player", "Addon-UT Zeichensatz: \(map.count)/\(wanted.count) lokal\(notes.isEmpty ? "" : " · " + notes.joined(separator: ", "))")
        return map
    }

    /// Laden, umwandeln, schreiben. Notiz nur bei Umwandlung oder Fehler.
    nonisolated static func fetch(_ address: String, format: String) async -> (String, URL?, String?) {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return (address, nil, nil) }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (address, nil, "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            guard !data.isEmpty, data.count <= maxBytes else { return (address, nil, "Größe \(data.count) B") }
            // Gepackt (gzip/zip): nicht anfassen, die Engine bekommt die Adresse.
            if data.starts(with: [0x1F, 0x8B]) || data.starts(with: [0x50, 0x4B]) { return (address, nil, "gepackt") }
            let decoded = SubtitleCharset.decode(data)
            let dir = directory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(format)
            try decoded.utf8Data.write(to: file, options: .atomic)
            let plain = decoded.source == .utf8 && decoded.repaired == 0
            return (address, file, plain ? nil : decoded.logText)
        } catch {
            return (address, nil, Task.isCancelled ? nil : "Fehler \(LogRedact.text("\(error)"))")
        }
    }

    nonisolated static func cleanup() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-24 * 3600)
        for f in files {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date < limit { try? fm.removeItem(at: f) }
        }
    }
}

// MARK: Einstellungen

/// Einstellungs-Zeilen (Kategorie Wiedergabe): Spur-Gedächtnis und Bildschirmschoner.
struct PlayerComfortSettingsRows: View {
    @EnvironmentObject var model: AppModel
    @State private var cleared = false

    var body: some View {
        Toggle("Spur-Wahl je Serie merken", isOn: model.binding(\.player.rememberTracks))
        if model.profile.player.rememberTracks {
            Text("Merkt Tonsprache, Untertitel und Untertitel-Versatz aus dem Spur-Panel je Serie bzw. Film und nimmt sie beim nächsten Start, wenn die Spur da ist.")
                .font(.caption).foregroundStyle(.secondary)
            Button(cleared ? "Gemerkte Spur-Wahl gelöscht" : "Gemerkte Spur-Wahl löschen") {
                PlayerMemory.shared.clearTrackMemory(profile: model.profile.id)
                cleared = true
            }
            .disabled(cleared)
        }
        Picker("Bildschirmschoner in der Pause sperren", selection: model.binding(\.player.screensaverPauseMinutes)) {
            ForEach(IdleTimerPolicy.pauseChoices, id: \.self) { Text(IdleTimerPolicy.choiceLabel($0)).tag($0) }
        }
    }
}
