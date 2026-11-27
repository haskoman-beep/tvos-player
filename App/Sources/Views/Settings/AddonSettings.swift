import SwiftUI
import PlayerCore

/// Kategorie „Addons“ (wave S, from „Addons & Quellen“): installierte Addons (Unterseite je Addon), Hinzufügen am
/// Handy (#addon), Zeitgrenze je Addon (was System › Erweitert). Source rules: „Quellen“; TorBox key: Profil & Konten.
struct AddonSettings: View {
    @Environment(AppModel.self) var model

    private let tint = SettingsCategory.addons.tint

    var body: some View {
        let p = model.profile
        CategoryPage(.addons, summary: SettingsSummary.addonsPage(count: p.addons.count, timeoutSeconds: p.addonTimeout)) {
            StatusCard(leading: .symbol("puzzlepiece.extension", tint), title: SettingsSummary.addons(p.addons.count),
                       subtitle: SettingsSummary.catalogs(p.addons.reduce(0) { $0 + $1.manifest.catalogs.count }),
                       metrics: [StatusCard.Metric(text: "Zeitgrenze \(Int(AddonSearch.nearestChoice(p.addonTimeout))) s")])
            SettingsSection("Installierte Addons") {
                if p.addons.isEmpty {
                    SettingsFootnote("Noch kein Addon. Am Handy die Manifest-Adresse einfügen (z. B. von AIOStreams).")
                }
                ForEach(p.addons) { a in
                    SettingsLinkRow(symbol: "puzzlepiece.extension", tint: tint, title: a.manifest.name,
                                    detail: a.manifest.description,
                                    value: DesignText.metaLine([a.manifest.version, SettingsSummary.catalogs(a.manifest.catalogs.count)])) {
                        AddonDetailPage(manifestURL: a.manifestURL)
                    }
                }
                PhoneLinkRow(section: .addon, symbol: "plus", tint: tint, title: "Addon hinzufügen",
                             detail: "Manifest-Adresse am Handy einfügen.")
            }
            SettingsSection("Suche") {
                AddonTimeoutPicker()
            }
        }
    }
}

/// Unterseite eines Addons (§2.2/§2.4): Kataloge, Reihenfolge, „Addon entfernen …“ mit Rückfrage (E6).
struct AddonDetailPage: View {
    let manifestURL: String
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    private let tint = SettingsCategory.addons.tint

    var body: some View {
        let addons = model.profile.addons
        if let i = addons.firstIndex(where: { $0.manifestURL == manifestURL }) {
            let a = addons[i]
            let catalogs = a.manifest.catalogs
            SettingsSubpage(title: a.manifest.name,
                            summary: DesignText.metaLine(["Version " + a.manifest.version, SettingsSummary.catalogs(catalogs.count)])) {
                SettingsSection("Addon") {
                    SettingsInfoRow(symbol: "square.grid.2x2", tint: tint, title: "Kataloge",
                                    detail: catalogs.isEmpty ? "Liefert nur Quellen, keine Reihen."
                                        : catalogs.prefix(6).map { $0.name ?? $0.id }.joined(separator: ", ") + (catalogs.count > 6 ? " …" : ""),
                                    value: "\(catalogs.count)")
                    // Nur der Rechnername: die volle Manifest-Adresse kann Schlüssel enthalten.
                    SettingsInfoRow(symbol: "network", tint: tint, title: "Server", value: URL(string: a.manifestURL)?.host ?? "?")
                }
                SettingsSection("Reihenfolge") {
                    SettingsRow(symbol: "arrow.up", tint: tint, title: "Nach oben",
                                detail: "Position \(i + 1) von \(addons.count)", reserveDetailSpace: false) { move(by: -1) }
                        .settingsUnavailable(i == 0)
                    SettingsRow(symbol: "arrow.down", tint: tint, title: "Nach unten",
                                detail: "Position \(i + 1) von \(addons.count)", reserveDetailSpace: false) { move(by: 1) }
                        .settingsUnavailable(i == addons.count - 1)
                }
                SettingsSection {
                    SettingsRow(symbol: "trash", tint: Theme.Tone.error.color, title: "Addon entfernen …",
                                reserveDetailSpace: false) { confirm = true }
                }
            }
            .settingsConfirmation("\(a.manifest.name) entfernen?", isPresented: $confirm,
                                  message: "Kataloge und Quellen dieses Addons verschwinden aus allen Reihen.",
                                  verb: "Entfernen") {
                model.update { $0.addons.removeAll { $0.manifestURL == manifestURL } }
                model.clearCatalogCache()   // Reihen des Addons nicht aus dem Plattencache zurückholen
                RemoteLog.info("einstellung", "Addon entfernt: \(a.manifest.name)")
                dismiss()
            }
        } else {
            SettingsSubpage(title: "Addon", summary: "Nicht mehr installiert") {
                FocusAnchor(kind: .back)
            }
        }
    }

    private func move(by delta: Int) {
        model.update { p in
            guard let i = p.addons.firstIndex(where: { $0.manifestURL == manifestURL }) else { return }
            let j = i + delta
            guard p.addons.indices.contains(j) else { return }
            p.addons.swapAt(i, j)
        }
        RemoteLog.info("einstellung", "Addon verschoben (\(delta < 0 ? "hoch" : "runter"))")
    }
}
