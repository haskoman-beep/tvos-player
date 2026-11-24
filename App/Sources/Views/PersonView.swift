import SwiftUI
import PlayerCore

/// Personenseite (aus der Besetzung): Foto, Name, Biografie, darunter die Filmografie nach Beliebtheit.
struct PersonView: View {
    @EnvironmentObject var model: AppModel
    let personID: Int
    let name: String
    @State private var person: PersonCredits?
    @State private var failed = false
    @State private var showBio = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .top, spacing: 50) {
                    RemoteImage(url: person?.photo, maxPixels: 600)
                        .frame(width: 260, height: 390).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay { if person?.photo == nil { Text(String(name.prefix(1))).font(.system(size: 90, weight: .bold)) } }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(person?.name ?? name).font(.largeTitle.bold())
                        if let k = person?.knownFor { Text("Bekannt für: \(Self.department(k))").foregroundStyle(.secondary) }
                        if let b = person?.biography {
                            Button { showBio = true } label: {
                                FocusHighlight { Text(b).font(.callout).foregroundStyle(.white).lineLimit(4).multilineTextAlignment(.leading) }
                            }
                            .buttonStyle(.plain)
                        }
                        // N6 (Welle F-c): beim Laden unsichtbares Fokusziel, bei Fehler bzw. leerer Seite „Zurück“.
                        if person == nil && !failed { ProgressView().quietFocusTarget() }
                        if failed { Text("Person konnte nicht geladen werden.").foregroundStyle(.secondary) }
                        if failed || (person != nil && person?.biography == nil && person?.credits.isEmpty == true) {
                            FocusAnchor(kind: .back)
                        }
                    }
                    .frame(maxWidth: 1100, alignment: .leading)
                }
                // Getrennt nach Art, jeweils nach Beliebtheit (Reihenfolge aus PersonCredits); leere Abschnitte entfallen.
                let credits = person?.credits ?? []
                section("Filme", credits.filter { $0.type == "movie" })
                section("Serien", credits.filter { $0.type == "series" })
            }
            .padding(80)
        }
        .tint(Color?.none)
        .sheet(isPresented: $showBio) { FullTextSheet(title: person?.name ?? name, text: person?.biography ?? "") }
        .task {
            guard person == nil else { return }
            // F-B-7: a later successful run must not keep the error text of an earlier (cancelled) one.
            failed = false
            guard let tmdb = model.tmdb else { failed = true; RemoteLog.info("person", "kein TMDB-Key"); return }
            do {
                let p = try await tmdb.personCredits(id: personID)
                person = p
                RemoteLog.info("person", "\(personID) \(p.name): \(p.credits.count) Titel, Bio \(p.biography == nil ? "fehlt" : "da")")
            } catch {
                // A cancelled task (tab switch) is no failure; the next appearance loads again.
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    RemoteLog.info("person", "\(personID) laden abgebrochen")
                    return
                }
                failed = true
                RemoteLog.error("person", "\(personID) laden fehlgeschlagen: \(error)")
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ items: [MetaPreview]) -> some View {
        if !items.isEmpty {
            Text(title).font(.title3.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(240), spacing: 40), count: 6), alignment: .leading, spacing: 50) {
                ForEach(items) { m in
                    NavigationLinkish(route: .detail(m), onActivate: { $0 }, label: PosterCard(item: m))
                        .tileMenu(m)   // Wave L
                }
            }
        }
    }

    static func department(_ d: String) -> String {
        switch d {
        case "Acting": "Schauspiel"
        case "Directing": "Regie"
        case "Writing": "Drehbuch"
        case "Production": "Produktion"
        case "Camera": "Kamera"
        case "Editing": "Schnitt"
        case "Sound": "Ton"
        default: d
        }
    }
}
