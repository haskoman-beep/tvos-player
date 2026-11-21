import SwiftUI
import PlayerCore

/// Einstellungen → Startseite → Fusion-Kit: Kit an/aus und Auswahl der Reihen.
/// Die Kit-Dateien kommen zur Laufzeit von GitHub (kit.betterer.cc); gewählte Reihen erscheinen am Ende der Startseite
/// und lassen sich dort wie jede Reihe verschieben, umstellen oder entfernen.
struct FusionKitSettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var kit = FusionKitStore.shared

    var body: some View {
        Section("Startseiten-Kit (Fusion)") {
            Toggle("Kit-Reihen auf der Startseite", isOn: Binding(get: { kit.settings.enabled }, set: { kit.setEnabled($0) }))
            if !model.hasTraktID {
                Text("Ohne Trakt Client ID (Handy-Seite) bleiben Trakt-Reihen und -Kacheln ausgeblendet.")
                    .foregroundStyle(.secondary)
            }
            Button { Task { await kit.refresh(force: true, all: true) } } label: { Text(busy ? "Lädt …" : "Kit neu laden") }
                .disabled(busy)
            if let e = kit.listingError {
                Text("Kit-Katalog nicht erreichbar: \(e)").foregroundStyle(.secondary)
            }
            Text("Weitere Kits: auf kit.betterer.cc „Copy JSON URL“ wählen und auf der Handy-Seite einfügen.")
                .foregroundStyle(.secondary)
        }
        .task { await kit.refresh(all: true) }

        ForEach(kit.sources) { src in
            Section(src.title) {
                if let c = kit.contents[src.id] {
                    if c.rows.isEmpty { Text("Keine passenden Reihen").foregroundStyle(.secondary) }
                    ForEach(c.rows) { row in
                        Toggle(isOn: Binding(get: { kit.settings.isSelected(row.id) },
                                             set: { kit.select(row.id, $0, source: src) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                Text(detail(row)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if let e = kit.errors[src.id] {
                    Text("Nicht geladen: \(e)").foregroundStyle(.secondary)
                } else {
                    Text(kit.loading.contains(src.id) ? "Lädt …" : "Noch nicht geladen").foregroundStyle(.secondary)
                }
                if !kit.isListed(src.id) {
                    Button("Entfernen", role: .destructive) { kit.removeSource(src.id) }
                }
            }
        }
    }

    private var busy: Bool { kit.listingLoading || !kit.loading.isEmpty }

    /// Art der Reihe plus, was ihr fehlt (Trakt Client ID, Anmeldung, TMDB-Schlüssel).
    private func detail(_ row: FusionKitRow) -> String {
        var parts: [String] = []
        let traktID = model.hasTraktID, login = model.isConnected("trakt")
        switch row.body {
        case .collection(let c): parts.append("\(c.folders.count) Kacheln")
        case .list: parts.append(row.style == .top10 ? "Liste mit Rang" : "Liste")
        }
        if let a = row.available(traktID: traktID, traktLogin: login) {
            if case .collection(let full) = row.body, case .collection(let v) = a.body, v.folders.count < full.folders.count {
                parts.append("ohne Trakt Client ID nur \(v.folders.count) Kacheln")
            }
        } else {
            parts.append(traktID && row.needs.contains(.traktLogin) ? "braucht Trakt-Anmeldung" : "braucht Trakt Client ID")
        }
        if row.needs.contains(.tmdb) && model.tmdb == nil { parts.append("braucht TMDB-Schlüssel") }
        return parts.joined(separator: " · ")
    }
}
