import SwiftUI
import PlayerCore

/// Kategorie 7 „System“ (§2.2): Status mit Version und Update, darunter App aktualisieren ›, Gerätecheck ›,
/// Erweitert ›, Lizenzen ›.
struct SystemSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = AppUpdater.shared

    private let tint = SettingsCategory.system.tint

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    private var checked: UpdateState? {
        if case .checked(let s) = updater.phase { return s }
        return nil
    }

    var body: some View {
        let status = SettingsSummary.UpdateStatus.of(checked)
        CategoryPage(.system, summary: SettingsSummary.system(build: updater.current.build, update: status)) {
            StatusCard(leading: .symbol("gearshape.2", tint), title: "Player \(version)",
                       subtitle: "Build " + updater.current.buildLabel,
                       metrics: [updateMetric(status),
                                 StatusCard.Metric(text: DesignText.metaLine([SettingsSummary.addons(model.profile.addons.count),
                                                                              SettingsSummary.profiles(model.stored.profiles.count)]))],
                       // Review F-a M3: Aktion bleibt während der Suche stehen (kein Fokussprung), tut dann nichts.
                       action: StatusCard.Action(title: updater.busy ? "Suche läuft …" : "Nach Update suchen", symbol: "arrow.down.circle") {
                           if !updater.busy { updater.check() }
                       })
            SettingsSection {
                SettingsLinkRow(symbol: "arrow.down.app", tint: tint, title: "App aktualisieren",
                                detail: "Neuesten Build suchen und über atvloadly installieren.",
                                value: updateValue(status)) {
                    UpdatePage()
                }
                SettingsLinkRow(symbol: "checkmark.seal", tint: tint, title: "Gerätecheck",
                                detail: "Ist das Apple TV richtig eingestellt? Und was spielt wie?") {
                    DeviceCheckPage()
                }
                SettingsLinkRow(symbol: "wrench.and.screwdriver", tint: tint, title: "Erweitert",
                                detail: "Diagnose, Zeitgrenze je Addon, Dolby Vision, Zwischenspeicher.") {
                    AdvancedSettingsPage()
                }
                SettingsLinkRow(symbol: "doc.text", tint: tint, title: "Lizenzen",
                                detail: "Mitgelieferte Komponenten und ihre Lizenzen.") {
                    LicensesPage()
                }
            }
        }
    }

    private func updateMetric(_ s: SettingsSummary.UpdateStatus) -> StatusCard.Metric {
        switch s {
        case .unknown: StatusCard.Metric(text: "Update nicht geprüft")
        case .upToDate: StatusCard.Metric(text: "Aktuell", tone: .ok)
        case .available(let n): StatusCard.Metric(text: "Update: Build " + (n.map(String.init) ?? "?"), tone: .warn)
        case .newerInstalled: StatusCard.Metric(text: "Neuer als die veröffentlichte Version")
        }
    }

    private func updateValue(_ s: SettingsSummary.UpdateStatus) -> String? {
        switch s {
        case .unknown: nil
        case .upToDate: "Aktuell"
        case .available(let n): "Build " + (n.map(String.init) ?? "?")
        case .newerInstalled: "Neuer als veröffentlicht"
        }
    }
}

/// Unterseite „Lizenzen“: mitgelieferte Fremdkomponenten (Stand Engine 7.71.2); Volltexte in THIRD_PARTY_NOTICES.md.
struct LicensesPage: View {
    private struct Credit { let name: String; let detail: String }
    private static let credits: [Credit] = [
        Credit(name: "Player (diese App)", detail: "App: MIT · die Komponenten unten behalten ihre eigenen Lizenzen"),
        Credit(name: "AetherEngine 7.71.2", detail: "© 2026 Vincent Herbst · LGPL-3.0 mit App-Store-/DRM-Ausnahme · github.com/superuser404notfound/AetherEngine · mit Zusatzteil Dolby-Vision-FEL-Kurven (DolbyVisionFelCurves)"),
        Credit(name: "FFmpeg n8.1.3 (FFmpegBuild 3.16)", detail: "© die FFmpeg-Entwickler · LGPL-2.1 oder neuer, als austauschbare dynamische Frameworks · Quelle: github.com/superuser404notfound/FFmpegBuild"),
        Credit(name: "libzvbi", detail: "LGPL-2.0 oder neuer (unter LGPL-2.1), ure.c MIT"),
        Credit(name: "dav1d", detail: "© 2018-2019 VideoLAN und die dav1d-Autoren · BSD-2-Clause"),
        Credit(name: "zimg", detail: "WTFPL"),
        Credit(name: "libdovi (dovi_tool)", detail: "© quietvoid und Mitwirkende · MIT"),
        Credit(name: "Anime4K", detail: "© 2019-2021 bloc97 · MIT"),
    ]

    var body: some View {
        SettingsSubpage(title: "Lizenzen", summary: "\(Self.credits.count) Komponenten") {
            ForEach(Self.credits, id: \.name) { c in
                SettingsInfoRow(symbol: "doc.text", tint: SettingsCategory.system.tint, title: c.name,
                                detail: c.detail, detailAlwaysVisible: true)
            }
            SettingsFootnote("Die vollständigen Lizenztexte stehen in THIRD_PARTY_NOTICES.md im Quellcode-Repository; jedes Release verweist darauf.")
        }
    }
}
