import SwiftUI
import PlayerCore

/// Welle C-d: lädt den Bewertungs-Icon-Satz (Adresse aus Einstellungen → Aussehen), Plattencache 24 h.
@MainActor
final class RatingIconStore: ObservableObject {
    static let shared = RatingIconStore()
    @Published private(set) var icons: [String: String] = [:]
    @Published private(set) var status: String?
    private var loadedURL: String?
    private var running: Task<Void, Never>?
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("rating-icons.json")

    private struct Cached: Codable { var url: String; var at: Date; var icons: [String: String] }

    /// Nach einem Fehler: dieselbe Adresse erst nach 5 min erneut versuchen, dann genau ein laufender Versuch
    /// (Welle D-b M2: weitere `ensure` brechen ihn nicht ab und starten ihn nicht neu).
    private var retry = FetchRetryGate()

    /// Satz für `url` bereitstellen (nil/ungültig = eingebaute Textplaketten).
    func ensure(_ url: String?) {
        let url = url?.trimmingCharacters(in: .whitespaces)
        // Gleiche Adresse: nichts tun, außer die Sperre nach einem Fehler ist abgelaufen und noch kein neuer
        // Versuch läuft.
        guard url != loadedURL || retry.retryDue(url) else { return }
        // Wechsel (auch auf „eingebaut“ oder zurück auf eine gescheiterte Adresse): Icons und Status gehören danach
        // immer zur neuen Wahl.
        loadedURL = url
        running?.cancel()
        retry.cancelled()   // ein abgebrochener erneuter Versuch ist beim Zurückwechseln gleich wieder fällig
        guard let url, RatingIconSet.isValidSetURL(url), let u = URL(string: url) else { icons = [:]; status = nil; return }
        if let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(Cached.self, from: d), c.url == url {
            icons = c.icons
            status = "\(c.icons.count) Icons"
            if Date().timeIntervalSince(c.at) < 24 * 3600 { return }
        } else {
            icons = [:]   // keine Icons eines früheren Satzes stehen lassen
            status = nil
        }
        if retry.isBlocked(url) {   // gesperrt: kein neuer Abruf, letzter Fehler bleibt sichtbar
            status = retry.lastError
            return
        }
        retry.begin(url)
        running = Task {
            do {
                // Welle D-b (N-M3): Größe und Gesamtzeit schon während des Downloads begrenzen.
                let (data, code) = try await RatingIconSet.withDeadline(RatingIconSet.timeout) { () async throws -> (Data, Int) in
                    var req = URLRequest(url: u)
                    req.timeoutInterval = RatingIconSet.timeout
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else { return (Data(), code) }
                    return (try await RatingIconSet.collect(bytes, expectedLength: resp.expectedContentLength), code)
                }
                guard !Task.isCancelled, loadedURL == url else { return }
                guard (200..<300).contains(code) else { fail(url, "Fehler \(code)"); return }
                let set = RatingIconSet.parse(data)
                icons = set
                retry.succeeded(url)
                status = set.isEmpty ? "Keine Icons erkannt" : "\(set.count) Icons"
                RemoteLog.info("bewertung", "Icon-Satz: \(set.keys.sorted().joined(separator: ","))")
                if let d = try? JSONEncoder().encode(Cached(url: url, at: Date(), icons: set)) { try? d.write(to: file, options: .atomic) }
            } catch {
                guard !Task.isCancelled, loadedURL == url else { return }
                switch error as? RatingIconSet.DownloadError {
                case .tooLarge: fail(url, "Datei zu groß (höchstens 256 KB)")
                case .timedOut: fail(url, "Zeitüberschreitung")
                case nil: fail(url, "Nicht erreichbar")
                }
                RemoteLog.error("bewertung", "Icon-Satz: \(LogRedact.text("\(error)"))")
            }
        }
    }

    private func fail(_ url: String, _ text: String) {
        status = text
        retry.failed(url, error: text)
        // loadedURL bleibt: nach der Sperre versucht `ensure` dieselbe Adresse erneut (retryDue).
    }
}

/// Bewertungs-Quelle als Icon aus dem Satz; solange das Bild nicht geladen ist oder scheitert, der eingebaute Text.
struct RatingIconLabel<Fallback: View>: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = RatingIconStore.shared
    let source: String
    @ViewBuilder let fallback: Fallback
    @State private var image: UIImage?

    var body: some View {
        let icon = store.icons[source]
        Group {
            if let image, icon != nil {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 28)
            } else {
                fallback
            }
        }
        .task(id: model.profile.sources.ratingIconSetURL) { store.ensure(model.profile.sources.ratingIconSetURL) }
        .task(id: icon) {
            guard let icon, let u = URL(string: icon) else { image = nil; return }
            let img = await ImagePipeline.shared.image(u, maxPixels: 160)
            guard !Task.isCancelled else { return }
            image = img
        }
    }
}
