import SwiftUI
import PlayerCore

/// Abschnitt „App aktualisieren“ (in „Über“): neuesten main-Build suchen und über atvloadly am Pi installieren.
struct UpdateSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = AppUpdater.shared
    @State private var addressInput = ""

    /// Adresse aus dem aktiven Profil, sonst aus irgendeinem Profil (die Handy-Seite speichert pro Profil).
    private var savedAddress: String? {
        let k = AtvloadlyAddress.key
        return model.profile.apiKeys[k] ?? model.stored.profiles.lazy.compactMap { $0.apiKeys[k] }.first
    }

    private var base: URL? { savedAddress.flatMap { AtvloadlyAddress.normalize($0) } }

    private var checkTitle: String { updater.phase == .checking ? "Suche läuft …" : "Nach Update suchen" }
    private var searchTitle: String { updater.searching ? "Suche läuft …" : "Pi im Netz suchen" }

    var body: some View {
        Section("App aktualisieren") {
            HStack { Text("Installiert"); Spacer(); Text("Build " + updater.current.buildLabel).foregroundStyle(.secondary) }
            status
            Button(checkTitle) { updater.check() }
                .disabled(updater.busy)
            if case .checked(.available(let release, _)) = updater.phase {
                if let base {
                    Button("Build " + Self.num(release.number) + " installieren") { updater.install(release, base: base) }
                        .disabled(updater.busy)
                    Text("Die App wird beim Installieren beendet und muss danach neu geöffnet werden.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Zum Installieren zuerst die atvloadly-Adresse eintragen (unten oder über die Handy-Seite).")
                        .foregroundStyle(.secondary)
                }
            }
        }
        Section("atvloadly (Pi)") {
            HStack { Text("Adresse"); Spacer(); Text(base?.absoluteString ?? "nicht eingetragen").foregroundStyle(.secondary) }
            Button(searchTitle) {
                Task { if let u = await updater.discover() { save(u) } }
            }
            .disabled(updater.searching)
            TextField("Adresse, z. B. http://pi-name.local:5533", text: $addressInput)
            Button("Adresse speichern") {
                if let u = AtvloadlyAddress.normalize(addressInput) {
                    save(u)
                    addressInput = ""
                    updater.verify(u)
                }
            }
            .disabled(AtvloadlyAddress.normalize(addressInput) == nil)
            if let note = updater.addressNote { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .checking:
            HStack { ProgressView(); Text("Frage GitHub nach dem neuesten main-Build …").foregroundStyle(.secondary) }
        case .checked(let state):
            Text(Self.describe(state)).foregroundStyle(.secondary)
        case .starting:
            HStack { ProgressView(); Text("Auftrag an atvloadly …").foregroundStyle(.secondary) }
        case .installing(let m):
            HStack { ProgressView(); Text(m).foregroundStyle(.secondary) }
        case .done(let m), .failed(let m):
            Text(m).foregroundStyle(.secondary)
        }
    }

    private static func num(_ n: Int?) -> String { n.map { String($0) } ?? "?" }

    private static func describe(_ s: UpdateState) -> String {
        switch s {
        case .upToDate(let b):
            return "Aktuell – neuester main-Build ist \(b.number) (\(b.shortCommit))."
        case .available(let r, let b):
            let commit = r.commit.map { String($0.prefix(7)) } ?? "?"
            let lag = r.number == b.number ? "" : " (neuester Lauf: \(b.number))"
            return "Neu: Build \(num(r.number))\(lag) · \(commit)"
        case .notPublished(let b):
            return "Build \(b.number) ist fertig, aber noch nicht als Installationspaket veröffentlicht (Release „app-main“)."
        }
    }

    private func save(_ u: URL) {
        model.update { $0.apiKeys[AtvloadlyAddress.key] = u.absoluteString }
    }
}
