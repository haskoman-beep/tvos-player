import SwiftUI
import AVKit
import AVFoundation
import PlayerCore

/// Welle C-d: Geräte-Check („Apple TV richtig eingestellt?“) und eine feste Tabelle, was wie abgespielt wird.
/// Liest nur Systemwerte, ändert nichts.
struct DeviceCheckSettings: View {
    @State private var check: DeviceCheck?

    var body: some View {
        Section("Geräte-Check") {
            if let check {
                ForEach(check.rows) { r in
                    // Knöpfe ohne Aktion: so erreicht der Fokus jede Zeile und die Liste scrollt mit.
                    Button {} label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: Self.icon(r.ok).name).foregroundStyle(Self.icon(r.ok).color)
                                Text(r.title)
                                Spacer()
                                Text(r.value).foregroundStyle(.secondary)
                            }
                            if let hint = r.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task { check = DeviceCheck.read() }
        Section("Was spielt wie") {
            ForEach(Self.formats, id: \.0) { f in
                Button {} label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.0)
                        Text(f.1).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func icon(_ ok: Bool?) -> (name: String, color: Color) {
        switch ok {
        case nil: return ("info.circle", .secondary)
        case true?: return ("checkmark.circle.fill", .green)
        case false?: return ("exclamationmark.triangle.fill", .orange)
        }
    }

    /// Stand AetherEngine 7.71.2 mit unseren Ladeoptionen (Tonbrücke „surroundCompat“, Engine stellt den Bildmodus).
    static let formats: [(String, String)] = [
        ("Dolby Vision Profil 5 / 8.1", "nativ als Dolby Vision"),
        ("Dolby Vision Profil 7 (UHD-Remux)", "live in Profil 8.1 umgewandelt: MEL verlustfrei, bei FEL wird die Zusatzschicht verworfen"),
        ("HDR10 / HDR10+ / HLG", "nativ; HDR nur, wenn der Fernseher HDR meldet"),
        ("HEVC / H.264", "nativ über den Hardware-Dekoder"),
        ("AV1", "Software-Dekoder auf jedem Apple TV: 4K-AV1 kann ruckeln, darum sortiert die Quellenliste es nach hinten"),
        ("Dolby Digital / Dolby Digital Plus / Atmos (DD+)", "unverändert durchgereicht; Atmos geht als Dolby MAT 2.0 an HDMI"),
        ("TrueHD / DTS / DTS-HD MA", "in Dolby Digital Plus 5.1 umgewandelt (768 kbit/s), 7.1 wird 5.1; Atmos-/DTS:X-Höhen fallen weg"),
        ("AAC / FLAC", "unverändert; Stereo-Quellen anderer Formate werden verlustfrei als FLAC gebrückt"),
    ]
}

/// Abgelesene Systemwerte, einmal beim Öffnen.
@MainActor
struct DeviceCheck {
    struct Row: Identifiable {
        let id: String
        let title: String
        let value: String
        /// nil = nur Info, true = passt, false = Hinweis.
        let ok: Bool?
        let hint: String?
    }
    var rows: [Row]

    static func read() -> DeviceCheck {
        var rows: [Row] = []
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        if let dm = windows.first?.avDisplayManager {
            let on = dm.isDisplayCriteriaMatchingEnabled
            rows.append(Row(id: "match", title: "Inhalt anpassen (Dynamikbereich/Bildrate)", value: on ? "an" : "aus", ok: on,
                            hint: on ? nil : "Einstellungen → Video und Audio → Inhalt anpassen: Dynamikbereich und Bildrate einschalten. "
                                + "Sonst laufen HDR/Dolby Vision und 24-Hz-Filme im festen Bildmodus des Apple TV."))
        } else {
            rows.append(Row(id: "match", title: "Inhalt anpassen", value: "unbekannt", ok: nil, hint: nil))
        }
        let modes = AVPlayer.availableHDRModes
        var names: [String] = []
        if modes.contains(.dolbyVision) { names.append("Dolby Vision") }
        if modes.contains(.hdr10) { names.append("HDR10") }
        if modes.contains(.hlg) { names.append("HLG") }
        rows.append(Row(id: "hdr", title: "HDR des Fernsehers", value: names.isEmpty ? "keins" : names.joined(separator: ", "),
                        ok: names.isEmpty ? false : true,
                        hint: names.isEmpty ? "Kein HDR gemeldet: HDMI-Kabel, Eingang (z. B. „HDMI Deep Colour“/„UHD Deep Colour“ am Fernseher) und Inhalt anpassen prüfen." : nil))
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let port = outputs.first.map { $0.portType == .HDMI ? "HDMI" : $0.portName } ?? "keine"
        let ch = session.maximumOutputNumberOfChannels
        rows.append(Row(id: "audio", title: "Tonausgang", value: "\(port) · bis \(ch) Kanäle", ok: ch >= 6 ? true : nil,
                        hint: ch >= 6 ? nil : "Nur Stereo gemeldet: Surround (5.1) kommt so nicht an. Audioformat am Apple TV und Verkabelung prüfen; "
                            + "an einer optisch angeschlossenen Anlage trägt nur Dolby Digital 5.1."))
        let av1 = DecoderCapabilities.av1Hardware
        rows.append(Row(id: "av1", title: "AV1-Hardware-Dekoder", value: av1 ? "ja" : "nein", ok: nil,
                        hint: av1 ? nil : "AV1 läuft in Software; 4K-AV1-Quellen stehen in der Quellenliste hinten."))
        return DeviceCheck(rows: rows)
    }
}
