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

    /// Satz für `url` bereitstellen (nil/ungültig = eingebaute Textplaketten).
    func ensure(_ url: String?) {
        let url = url?.trimmingCharacters(in: .whitespaces)
        guard url != loadedURL else { return }
        loadedURL = url
        running?.cancel()
        guard let url, RatingIconSet.isValidSetURL(url), let u = URL(string: url) else { icons = [:]; status = nil; return }
        if let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(Cached.self, from: d), c.url == url {
            icons = c.icons
            status = "\(c.icons.count) Icons"
            if Date().timeIntervalSince(c.at) < 24 * 3600 { return }
        }
        running = Task {
            do {
                let (data, resp) = try await URLSession.shared.data(from: u)
                guard !Task.isCancelled, loadedURL == url else { return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { status = "Fehler \(code)"; return }
                let set = RatingIconSet.parse(data)
                icons = set
                status = set.isEmpty ? "Keine Icons erkannt" : "\(set.count) Icons"
                RemoteLog.info("bewertung", "Icon-Satz: \(set.keys.sorted().joined(separator: ","))")
                if let d = try? JSONEncoder().encode(Cached(url: url, at: Date(), icons: set)) { try? d.write(to: file, options: .atomic) }
            } catch {
                guard !Task.isCancelled else { return }
                status = "Nicht erreichbar"
                RemoteLog.error("bewertung", "Icon-Satz: \(error)")
            }
        }
    }
}

/// Bewertungs-Quelle als Icon aus dem Satz, sonst der eingebaute Text.
struct RatingIconLabel<Fallback: View>: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = RatingIconStore.shared
    let source: String
    @ViewBuilder let fallback: Fallback

    var body: some View {
        Group {
            if let icon = store.icons[source] {
                RemoteImage(url: icon, maxPixels: 160, fit: true).frame(width: 64, height: 28)
            } else {
                fallback
            }
        }
        .task(id: model.profile.sources.ratingIconSetURL) { store.ensure(model.profile.sources.ratingIconSetURL) }
    }
}
