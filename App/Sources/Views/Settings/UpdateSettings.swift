import SwiftUI
import PlayerCore

/// Unterseite „App aktualisieren“ (System): neuesten main-Build suchen und über atvloadly am Pi installieren.
/// E7: Die Adresse kommt von der Bonjour-Suche oder der Handy-Seite (#system), kein Textfeld am Fernseher.
struct UpdatePage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = AppUpdater.shared

    private let tint = SettingsCategory.system.tint

    /// Adresse aus dem aktiven Profil, sonst aus irgendeinem Profil (die Handy-Seite speichert pro Profil).
    private var savedAddress: String? {
        let k = AtvloadlyAddress.key
        return model.profile.apiKeys[k] ?? model.stored.profiles.lazy.compactMap { $0.apiKeys[k] }.first
    }

    private var base: URL? { savedAddress.flatMap { AtvloadlyAddress.normalize($0) } }

    var body: some View {
        SettingsSubpage(title: "App aktualisieren", summary: "Installiert: Build " + updater.current.buildLabel) {
            SettingsSection {
                SettingsRow(symbol: "arrow.clockwise", tint: tint,
                            title: updater.phase == .checking ? "Suche läuft …" : "Nach Update suchen",
                            detail: statusText, detailAlwaysVisible: statusText != nil, reserveDetailSpace: false) {
                    if !updater.busy { updater.check() }
                }
                .settingsUnavailable(updater.busy)
                if case .checked(.available(let release, _)) = updater.phase {
                    if let base {
                        SettingsRow(symbol: "arrow.down.app", tint: tint, title: "Build " + Self.num(release.number) + " installieren",
                                    detail: "Die App wird beim Installieren beendet und muss danach neu geöffnet werden.",
                                    detailAlwaysVisible: true, reserveDetailSpace: false) {
                            if !updater.busy { updater.install(release, base: base) }
                        }
                        .settingsUnavailable(updater.busy)
                    } else {
                        SettingsFootnote("Zum Installieren zuerst die atvloadly-Adresse eintragen (Pi suchen oder am Handy).")
                    }
                }
            }
            SettingsSection("atvloadly (Pi)") {
                SettingsInfoRow(symbol: "server.rack", tint: tint, title: "Adresse",
                                value: base?.absoluteString ?? "nicht eingetragen")
                SettingsRow(symbol: "magnifyingglass", tint: tint, title: updater.searching ? "Suche läuft …" : "Pi im Netz suchen",
                            detail: "Findet atvloadly über Bonjour im Heimnetz und speichert die Adresse.",
                            reserveDetailSpace: false) {
                    guard !updater.searching else { return }
                    Task { if let u = await updater.discover() { save(u) } }
                }
                .settingsUnavailable(updater.searching)
                PhoneLinkRow(section: .system, symbol: "iphone", tint: tint, title: "Adresse am Handy eintragen",
                             detail: "Feld atvloadly im Abschnitt System.")
                if let note = updater.addressNote { SettingsFootnote(note) }
            }
        }
    }

    private var statusText: String? {
        switch updater.phase {
        case .idle: nil
        case .checking: "Frage GitHub nach dem neuesten main-Build …"
        case .checked(let state): Self.describe(state)
        case .starting: "Auftrag an atvloadly …"
        case .installing(let m), .done(let m), .failed(let m): m
        }
    }

    private static func num(_ n: Int?) -> String { n.map { String($0) } ?? "?" }

    static func describe(_ s: UpdateState) -> String {
        switch s {
        case .upToDate(let b):
            return "Aktuell – neuester main-Build ist \(b.number) (\(b.shortCommit))."
        case .available(let r, let b):
            let commit = r.commit.map { String($0.prefix(7)) } ?? "?"
            let lag = r.number == b.number ? "" : " (neuester Lauf: \(b.number))"
            return "Neu: Build \(num(r.number))\(lag) · \(commit)"
        case .notPublished(let b):
            return "Build \(b.number) ist fertig, aber noch nicht als Installationspaket veröffentlicht (Release „app-main“)."
        case .newerInstalled(let main):
            return "Installiert ist neuer als die veröffentlichte Version (Build \(main))"
        }
    }

    private func save(_ u: URL) {
        model.update { $0.apiKeys[AtvloadlyAddress.key] = u.absoluteString }
    }
}
