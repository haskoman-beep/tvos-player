import SwiftUI
import PlayerCore

/// Wave S: „System“ sections Diagnose (Welle C-b, Gerät statt Profil; Fern-Log and Verlauf, task 1.5) and Zwischenspeicher
/// (Katalog-Zwischenspeicher leeren, mit Rückfrage, E6). Was the subpage „System › Erweitert“, which is dissolved:
/// Zeitgrenze je Addon → Addons, Dolby Vision fest/FEL → Bild & Ton, Icon-Satz only under Aussehen › Plaketten.
struct SystemMaintenanceRows: View {
    @Environment(AppModel.self) var model
    @AppStorage(MainThreadWatchdog.settingKey) private var hitchLog = true
    @AppStorage(XRayProbe.settingKey) private var xrayProbe = false
    /// Task 5.1: Build 4 cards on the home page (one build, for telling focus problems of the new cards apart).
    @AppStorage(CardDiagnostics.oldCardKey) private var oldCard = false
    @State private var confirmClear = false
    @State private var cleared = false
    /// Review F-a M4: RemoteLog ist kein ObservableObject; die Seite fragt den Zustand alle 2 s neu ab.
    @State private var logStatus = RemoteLog.shared.status

    private let tint = SettingsCategory.system.tint

    var body: some View {
        // A VStack, not a Group: modifiers on a Group would run once per section (two polls, two covers).
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SettingsSection("Diagnose") {
                SettingsToggleRow(symbol: "waveform.path.ecg", tint: tint, title: "Ruckler protokollieren",
                                  detail: "Schreibt ins Ereignis-Log, wenn die Oberfläche länger als 250 ms hängt (mit letzter Aktion und Speicherverbrauch).",
                                  reserveDetailSpace: false, isOn: $hitchLog)
                    .onChange(of: hitchLog) { MainThreadWatchdog.apply() }
                SettingsToggleRow(symbol: "person.crop.rectangle", tint: tint, title: "Gesichter bei Pause prüfen (Test)",
                                  detail: "Entwicklung: Bei jeder Pause sucht das Gerät Gesichter im Standbild und schreibt Zeiten und Größen ins Ereignis-Log (xray). Nichts wird angezeigt oder gespeichert.",
                                  reserveDetailSpace: false, isOn: $xrayProbe)
                SettingsToggleRow(symbol: "rectangle.on.rectangle", tint: tint, title: "Alte Karte (Test)",
                                  detail: "Startseite: Karten wie in Build 4 (Form aus dem Reihenstil, System-Fokus, keine Titel darunter). Zum Vergleich bei Fokusproblemen.",
                                  reserveDetailSpace: false, isOn: $oldCard)
                    .onChange(of: oldCard) { _, on in RemoteLog.info("home", "Diagnose alte Karte \(on ? "an" : "aus")") }
                SettingsLinkRow(symbol: "antenna.radiowaves.left.and.right", tint: tint, title: "Fern-Log",
                                detail: "Ereignis-Log an ein Log-Programm im Heimnetz senden (gewählter Empfänger, mit Schlüssel). Standardmäßig aus.",
                                value: RemoteLogPage.statusValue(logStatus)) {
                    RemoteLogPage()
                }
                SettingsLinkRow(symbol: "list.bullet.rectangle", tint: tint, title: "Verlauf",
                                detail: "Die letzten \(LogRing.pageLines) Zeilen des Ereignis-Logs auf diesem Gerät, auf Wunsch nur Fehler.") {
                    DiagnosePage()
                }
            }
            SettingsSection("Zwischenspeicher") {
                SettingsRow(symbol: "trash", tint: Theme.Tone.error.color,
                            title: cleared ? "Katalog-Zwischenspeicher geleert" : "Katalog-Zwischenspeicher leeren …",
                            detail: "Kataloge und Reihen werden danach neu geladen.", reserveDetailSpace: false) {
                    if !cleared { confirmClear = true }
                }
                .settingsUnavailable(cleared)
            }
        }
        .task {
            while !Task.isCancelled {
                logStatus = RemoteLog.shared.status
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .settingsConfirmation("Katalog-Zwischenspeicher leeren?", isPresented: $confirmClear,
                              message: "Alle Reihen laden beim nächsten Öffnen neu; das kann kurz dauern.",
                              verb: "Leeren") {
            model.clearCatalogCache()
            RemoteLog.info("einstellung", "Katalog-Zwischenspeicher geleert")
            cleared = true
        }
    }
}

/// Task 1.5 (SEC-2): Unterseite „Fern-Log“. Aus per Standard; beim Einschalten erscheinen die gefundenen Empfänger
/// zur Auswahl. Gesendet wird nur an den gewählten Dienstnamen und nur mit dem Schlüssel von der Handy-Seite.
struct RemoteLogPage: View {
    @Environment(AppModel.self) var model
    @State private var found = RemoteLog.shared.foundReceivers
    @State private var status = RemoteLog.shared.status

    private let tint = SettingsCategory.system.tint

    /// Gewählter Empfänger zuerst sichtbar, auch wenn er gerade nicht angekündigt ist.
    private var names: [String] {
        var all = found
        if let r = model.device.remoteLogReceiver, !all.contains(r) { all.append(r) }
        return all.sorted()
    }

    private var hasSecret: Bool {
        let k = LogSignature.secretKey
        let v = model.profile.apiKeys[k] ?? model.stored.profiles.lazy.compactMap { $0.apiKeys[k] }.first
        return !(v ?? "").isEmpty
    }

    var body: some View {
        SettingsSubpage(title: "Fern-Log", summary: Self.statusText(status)) {
            SettingsSection {
                SettingsToggleRow(symbol: "antenna.radiowaves.left.and.right", tint: tint, title: "Ereignis-Log senden",
                                  detail: "Nur an den unten gewählten Empfänger; jede Sendung ist mit dem gemeinsamen Schlüssel signiert.",
                                  reserveDetailSpace: false, isOn: model.deviceBinding(\.remoteLogEnabled))
            }
            if model.device.remoteLogEnabled {
                SettingsSection("Empfänger") {
                    if names.isEmpty {
                        SettingsFootnote("Kein Log-Programm im Heimnetz gefunden (Dienst _playerlog._tcp). Die Suche läuft weiter.")
                    }
                    ForEach(names, id: \.self) { name in
                        let chosen = name == model.device.remoteLogReceiver
                        SettingsRow(symbol: chosen ? "checkmark" : "desktopcomputer", tint: tint, title: name,
                                    accessory: .value(chosen ? "Gewählt" : (found.contains(name) ? "" : "Nicht gefunden")),
                                    reserveDetailSpace: false) {
                            guard !chosen else { return }
                            model.updateDevice { $0.remoteLogReceiver = name }
                            RemoteLog.info("log", "Empfänger \(name) gewählt")   // Task 1.8 (plan line)
                        }
                    }
                }
                SettingsSection("Schlüssel") {
                    PhoneLinkRow(section: .system, symbol: "key", tint: tint, title: "Gemeinsamer Schlüssel",
                                 detail: "Am Handy unter „System“ eingeben; dasselbe Geheimnis bekommt das Log-Programm (PLAYERLOG_SECRET).",
                                 value: hasSecret ? "Gesetzt" : "Fehlt")
                }
            }
        }
        .onChange(of: model.device.remoteLogEnabled) { _, on in
            RemoteLog.info("einstellung", "Fern-Log: \(on ? "an" : "aus")")
        }
        .task {
            RemoteLog.shared.startBrowsing()
            while !Task.isCancelled {
                found = RemoteLog.shared.foundReceivers
                status = RemoteLog.shared.status
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Kurzer Wert für die Zeile in „System“.
    static func statusValue(_ s: RemoteLogTarget.Status) -> String {
        switch s {
        case .off: "Aus"
        case .noReceiver: "Empfänger wählen"
        case .noSecret: "Schlüssel fehlt"
        case .notFound: "Nicht gefunden"
        case .ready: "Sendet"
        }
    }

    static func statusText(_ s: RemoteLogTarget.Status) -> String {
        switch s {
        case .off: "Aus · das Log bleibt auf dem Gerät"
        case .noReceiver: "An · noch kein Empfänger gewählt"
        case .noSecret: "An · Schlüssel fehlt, es wird nichts gesendet"
        case .notFound: "An · gewählter Empfänger gerade nicht im Netz"
        case .ready: "An · sendet an den gewählten Empfänger"
        }
    }
}

/// Task 1.5: Seite „Diagnose“ – Verlauf des Ereignis-Logs auf diesem Gerät (`LogRing`), neueste Zeile oben,
/// Filter „Nur Fehler“. Liest den Stand beim Öffnen und beim Umschalten des Filters.
struct DiagnosePage: View {
    @State private var errorsOnly = false
    @State private var lines: [LogLine] = []

    private let tint = SettingsCategory.system.tint

    var body: some View {
        SettingsSubpage(title: "Diagnose", summary: "Ereignis-Log auf diesem Gerät · letzte \(LogRing.pageLines) Zeilen") {
            SettingsSection {
                SettingsToggleRow(symbol: "exclamationmark.triangle", tint: tint, title: "Nur Fehler",
                                  reserveDetailSpace: false, isOn: $errorsOnly)
            }
            SettingsSection("Verlauf") {
                if lines.isEmpty {
                    SettingsFootnote(errorsOnly ? "Keine Fehler im Verlauf." : "Noch keine Zeilen im Verlauf.")
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    SettingsInfoRow(symbol: line.isError ? "exclamationmark.triangle" : "text.alignleft",
                                    tint: line.isError ? Theme.Tone.error.color : tint,
                                    title: Self.clock(line.time) + " · " + line.category,
                                    detail: line.message, detailAlwaysVisible: true)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: errorsOnly) { reload() }
    }

    private func reload() { lines = RemoteLog.shared.recent(LogRing.pageLines, errorsOnly: errorsOnly) }

    /// Ortszeit „TT.MM. HH:MM:SS“; unlesbare Zeitangaben unverändert.
    private static func clock(_ iso: String) -> String {
        guard let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso) else { return iso }
        let style = Date.VerbatimFormatStyle(
            format: "\(day: .twoDigits).\(month: .twoDigits). \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: .current, calendar: Calendar(identifier: .gregorian))
        return d.formatted(style)
    }
}
