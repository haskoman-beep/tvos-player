import SwiftUI
import PlayerCore

/// Unterseite „App aktualisieren“ (System): neueste veröffentlichte Version suchen und über atvloadly am Pi installieren.
/// E7: Die Adresse kommt von der Bonjour-Suche oder der Handy-Seite (#system), kein Textfeld am Fernseher.
struct UpdatePage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = AppUpdater.shared
    /// Ergebnis der letzten Suche; gespeichert wird erst, wenn eine Zeile gewählt wird (SEC-11).
    @State private var choice: AtvloadlyAddress.CandidateChoice?

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
                // Bestätigungskarte: Build, Commit und Ziel stehen vor dem Druck da. Die Zeile hängt am gefundenen
                // Paket, nicht an der Phase – sie bleibt beim Installieren und nach einem Fehler stehen (F-B-6).
                if let release = updater.offered {
                    if let base {
                        SettingsRow(symbol: "arrow.down.app", tint: tint, title: Self.confirmTitle(release),
                                    detail: "Ziel: " + base.absoluteString,
                                    detailAlwaysVisible: true, reserveDetailSpace: false) {
                            if !updater.busy { updater.install(release, base: base) }
                        }
                        .settingsUnavailable(updater.busy)
                        if let sha = release.sha256 { SettingsFootnote("SHA256 des Pakets: " + sha) }
                        if base.scheme?.lowercased() == "http" {
                            SettingsFootnote("Hinweis: Die Verbindung zum Signier-Dienst (atvloadly) ist unverschlüsselt (http).")
                        }
                        SettingsFootnote("Die App wird beim Installieren beendet und muss danach neu geöffnet werden.")
                    } else {
                        SettingsFootnote("Zum Installieren zuerst die atvloadly-Adresse eintragen (Pi suchen oder am Handy).")
                    }
                }
            }
            SettingsSection("atvloadly (Pi)") {
                SettingsInfoRow(symbol: "server.rack", tint: tint, title: "Adresse",
                                value: base?.absoluteString ?? "nicht eingetragen")
                SettingsRow(symbol: "magnifyingglass", tint: tint, title: updater.searching ? "Suche läuft …" : "Pi im Netz suchen",
                            detail: "Findet atvloadly über Bonjour im Heimnetz und zeigt die Treffer zur Auswahl.",
                            reserveDetailSpace: false) {
                    guard !updater.searching else { return }
                    choice = nil
                    Task {
                        let found = await updater.discover()
                        choice = AtvloadlyAddress.chooseCandidate(found, saved: base)
                    }
                }
                .settingsUnavailable(updater.searching)
                switch choice {
                case .choose(let list, let replacing)?:
                    ForEach(list, id: \.url) { c in
                        SettingsRow(symbol: "checkmark.circle", tint: tint, title: c.name + " übernehmen",
                                    detail: Self.candidateDetail(c, replacing: replacing),
                                    detailAlwaysVisible: true, reserveDetailSpace: false) {
                            save(c.url)
                            choice = AtvloadlyAddress.chooseCandidate(list, saved: c.url)
                        }
                    }
                case .savedResponds(let c)?:
                    SettingsFootnote("Die eingetragene Adresse antwortet (atvloadly \(c.version)).")
                case .nothingFound?, nil:
                    EmptyView()
                }
                PhoneLinkRow(section: .system, symbol: "iphone", tint: tint, title: "Adresse am Handy eintragen",
                             detail: "Feld atvloadly im Abschnitt System.")
                if let note = updater.addressNote { SettingsFootnote(note) }
            }
        }
    }

    private var statusText: String? {
        switch updater.phase {
        case .idle: nil
        case .checking: "Frage GitHub nach der neuesten veröffentlichten Version …"
        case .checked(let state): Self.describe(state)
        case .starting: "Auftrag an atvloadly …"
        case .installing(let m), .done(let m), .failed(let m): m
        }
    }

    private static func num(_ n: Int?) -> String { n.map { String($0) } ?? "?" }

    /// „Build 41 · Commit abcdefg installieren?“
    private static func confirmTitle(_ r: ReleaseBuild) -> String {
        "Build \(num(r.number)) · Commit \(r.commit.map { String($0.prefix(7)) } ?? "?") installieren?"
    }

    private static func candidateDetail(_ c: AtvloadlyCandidate, replacing: URL?) -> String {
        let d = c.url.absoluteString + " · atvloadly " + c.version
        return replacing.map { d + " · ersetzt " + $0.absoluteString } ?? d
    }

    static func describe(_ s: UpdateState) -> String {
        switch s {
        case .upToDate(let b):
            return "Aktuell – neueste veröffentlichte Version ist Build \(b.number) (\(b.shortCommit))."
        case .available(let r, let b):
            let commit = r.commit.map { String($0.prefix(7)) } ?? "?"
            let lag = r.number == b.number ? "" : " (neuester Lauf: \(b.number))"
            return "Neu: Build \(num(r.number))\(lag) · \(commit)"
        case .notPublished(let b):
            return "Build \(b.number) ist fertig, aber das Installationspaket ist noch nicht veröffentlicht."
        case .newerInstalled(let main):
            return "Installiert ist neuer als die veröffentlichte Version (Build \(main))"
        }
    }

    private func save(_ u: URL) {
        model.update { $0.apiKeys[AtvloadlyAddress.key] = u.absoluteString }
    }
}
