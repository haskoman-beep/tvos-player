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

    /// Nach einem Fehler: dieselbe Adresse erst nach 5 min erneut versuchen.
    private var failedURL: String?
    private var failedUntil = Date.distantPast
    private var failedText: String?

    /// Satz für `url` bereitstellen (nil/ungültig = eingebaute Textplaketten).
    func ensure(_ url: String?) {
        let url = url?.trimmingCharacters(in: .whitespaces)
        // Gleiche Adresse: nichts tun, außer die Sperre nach einem Fehler ist abgelaufen (neuer Versuch).
        let retryDue = url != nil && url == failedURL && Date() >= failedUntil
        guard url != loadedURL || retryDue else { return }
        // Wechsel (auch auf „eingebaut“ oder zurück auf eine gescheiterte Adresse): Icons und Status gehören danach
        // immer zur neuen Wahl.
        loadedURL = url
        running?.cancel()
        guard let url, RatingIconSet.isValidSetURL(url), let u = URL(string: url) else { icons = [:]; status = nil; return }
        if let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(Cached.self, from: d), c.url == url {
            icons = c.icons
            status = "\(c.icons.count) Icons"
            if Date().timeIntervalSince(c.at) < 24 * 3600 { return }
        } else {
            icons = [:]   // keine Icons eines früheren Satzes stehen lassen
            status = nil
        }
        if url == failedURL, Date() < failedUntil {   // gesperrt: kein neuer Abruf, letzter Fehler bleibt sichtbar
            status = failedText
            return
        }
        running = Task {
            do {
                var req = URLRequest(url: u)
                req.timeoutInterval = RatingIconSet.timeout
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard !Task.isCancelled, loadedURL == url else { return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { fail(url, "Fehler \(code)"); return }
                guard resp.expectedContentLength <= Int64(RatingIconSet.maxBytes), data.count <= RatingIconSet.maxBytes else {
                    fail(url, "Datei zu groß (höchstens 256 KB)"); return
                }
                let set = RatingIconSet.parse(data)
                icons = set
                if failedURL == url { failedURL = nil }
                status = set.isEmpty ? "Keine Icons erkannt" : "\(set.count) Icons"
                RemoteLog.info("bewertung", "Icon-Satz: \(set.keys.sorted().joined(separator: ","))")
                if let d = try? JSONEncoder().encode(Cached(url: url, at: Date(), icons: set)) { try? d.write(to: file, options: .atomic) }
            } catch {
                guard !Task.isCancelled else { return }
                fail(url, "Nicht erreichbar")
                RemoteLog.error("bewertung", "Icon-Satz: \(LogRedact.text("\(error)"))")
            }
        }
    }

    private func fail(_ url: String, _ text: String) {
        status = text
        failedURL = url; failedUntil = Date().addingTimeInterval(300); failedText = text
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
