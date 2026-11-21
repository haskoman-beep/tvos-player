import SwiftUI
import PlayerCore

/// Welle C-a: Stand der Quellensuche je Inhalt (Status je Addon, schon eingetroffene Treffer).
@MainActor
final class StreamSearchStatus: ObservableObject {
    static let shared = StreamSearchStatus()
    @Published private(set) var progress: [String: AddonSearchProgress] = [:]
    private var updatedAt: [String: Date] = [:]
    private init() {}

    func update(_ id: String, _ p: AddonSearchProgress) {
        progress[id] = p
        updatedAt[id] = Date()
        // Nur wenige Inhalte behalten (Vorladen fragt viele ab): der am längsten nicht aktualisierte fällt heraus.
        if progress.count > 30, let drop = updatedAt.filter({ $0.key != id }).min(by: { $0.value < $1.value })?.key {
            progress[drop] = nil; updatedAt[drop] = nil
        }
    }

    /// Schon eingetroffene, abspielbare Treffer in Addon-Reihenfolge.
    func partial(_ id: String) -> [(addon: String, stream: StreamItem)] {
        (progress[id]?.results ?? []).flatMap { r in playableStreams(r.streams).map { (r.addon.manifest.name, $0) } }
    }
}

extension AppModel {
    /// Quellensuche mit Zeitgrenze je Addon (Profil `addonTimeout`); meldet jeden Zwischenstand an `StreamSearchStatus`.
    /// Ergebnis wie `addons.streams(from:type:id:)`: nur Addons mit Antwort, in Addon-Reihenfolge.
    /// `failed`: gefragte Addons ohne Antwort (Fehler, Zeitüberschreitung); nicht leer = lückenhaft → nur kurz frisch.
    /// Direkt aus dem Ergebnis bestimmt, nicht aus dem globalen Status (der kann inzwischen verdrängt sein).
    /// Läuft als ungebundene Aufgabe in `streams()` (geteilt mit Vorladen und Cache) und endet spätestens nach der
    /// Addon-Frist; Verlassen der Liste bricht sie deshalb bewusst nicht ab.
    func searchAddons(type: String, id: String) async -> (results: [(addon: InstalledAddon, streams: [StreamItem])], failed: Set<String>) {
        let timeout = profile.addonTimeout
        let asked = profile.addons.filter { $0.manifest.supports("stream", type: type, id: id) }.map(\.manifest.name)
        let result = await addons.streams(from: profile.addons, type: type, id: id, timeout: timeout) { p in
            await MainActor.run { StreamSearchStatus.shared.update(id, p) }
        }
        if let p = StreamSearchStatus.shared.progress[id] {
            RemoteLog.info("streams", "\(id): Addon-Status \(p.logText) · Grenze \(Int(timeout)) s")
        }
        return (result, Set(asked).subtracting(result.map(\.addon.manifest.name)))
    }
}

/// Status je Addon in der Quellenliste: lädt / n Quellen / Fehler / Zeitüberschreitung; ohne Netz ein Hinweis.
struct AddonSearchStatusLine: View {
    let id: String
    @ObservedObject private var search = StreamSearchStatus.shared
    @ObservedObject private var stability = PlaybackStability.shared

    var body: some View {
        let statuses = search.progress[id]?.statuses ?? []
        // Nichts zu zeigen (z. B. Cache-Treffer ohne gemerkten Status, online): keine leere Zeile in der Liste.
        if !statuses.isEmpty || !stability.isOnline {
        VStack(alignment: .leading, spacing: 6) {
            if !stability.isOnline {
                Label("Keine Netzverbindung", systemImage: "wifi.slash").foregroundStyle(.orange)
            }
            if let running = search.progress[id]?.runningSummary { Text(running).foregroundStyle(.secondary) }
            ForEach(statuses) { s in
                HStack(spacing: 10) {
                    Image(systemName: symbol(s.state)).foregroundStyle(color(s.state))
                    Text(s.name)
                    Text(s.state.label).foregroundStyle(color(s.state))
                    if let ms = s.milliseconds, s.state != .timedOut { Text("\(ms) ms").foregroundStyle(.secondary) }
                }
            }
        }
        .font(.caption)
        }
    }

    private func symbol(_ s: AddonSearchState) -> String {
        switch s {
        case .loading: "hourglass"
        case .ok: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .timedOut: "clock.badge.exclamationmark"
        }
    }

    private func color(_ s: AddonSearchState) -> Color {
        switch s {
        case .loading, .ok: .secondary
        case .failed, .timedOut: .orange
        }
    }
}

/// Zwischenstand der Suche in die Liste übernehmen, solange sie noch lädt (Treffer erscheinen sofort).
struct StreamSearchPartials: ViewModifier {
    let id: String
    let loading: Bool
    let apply: ([(addon: String, stream: StreamItem)]) -> Void
    @ObservedObject private var search = StreamSearchStatus.shared

    func body(content: Content) -> some View {
        content.onChange(of: search.progress[id]?.finishedCount ?? 0) { _, _ in
            guard loading else { return }
            let list = search.partial(id)
            if !list.isEmpty { apply(list) }
        }
    }
}

/// Markierung „zuletzt fehlgeschlagen“ an einer Quellenzeile (von Hand bleibt sie wählbar).
struct RecentlyFailedMark: ViewModifier {
    let stream: StreamItem
    let title: String
    @ObservedObject private var stability = PlaybackStability.shared

    func body(content: Content) -> some View {
        if stability.isRecentlyFailed(stream, title: title) {
            VStack(alignment: .leading, spacing: 6) {
                content
                Label("zuletzt fehlgeschlagen", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.caption2).foregroundStyle(.orange)
            }
        } else {
            content
        }
    }
}

extension View {
    func streamSearchPartials(id: String, loading: Bool,
                              apply: @escaping ([(addon: String, stream: StreamItem)]) -> Void) -> some View {
        modifier(StreamSearchPartials(id: id, loading: loading, apply: apply))
    }

    func recentlyFailedMark(_ stream: StreamItem, title: String) -> some View {
        modifier(RecentlyFailedMark(stream: stream, title: title))
    }
}

extension StreamListView {
    /// Weiterschauen mit der gemerkten Quelle, aber nie mit einer kürzlich fehlgeschlagenen (Rückgabe: Quelle, Hinweis).
    static func resumeCandidate(_ last: LastSource, in streams: [(addon: String, stream: StreamItem)],
                                title: String) -> (stream: StreamItem?, note: String?) {
        let stability = PlaybackStability.shared
        if let s = last.match(in: stability.autoCandidates(streams, title: title)) { return (s, nil) }
        if let s = last.match(in: streams), stability.isRecentlyFailed(s, title: title) {
            RemoteLog.info("player", "Letzte Quelle zuletzt fehlgeschlagen → nicht automatisch starten")
            return (nil, "Letzte Quelle ist zuletzt fehlgeschlagen – bitte wählen.")
        }
        return (nil, "Letzte Quelle nicht mehr verfügbar – bitte wählen.")
    }
}

/// Einstellung „Zeitgrenze je Addon“ (Einstellungen → Addons).
struct AddonTimeoutPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let stored = model.binding(\.addonTimeout)
        // Alte/fremde Werte auf die nächstliegende Auswahl abbilden, sonst zeigt der Picker nichts an.
        let selection = Binding(get: { AddonSearch.nearestChoice(stored.wrappedValue) }, set: { stored.wrappedValue = $0 })
        Picker("Zeitgrenze je Addon", selection: selection) {
            ForEach(AddonSearch.timeoutChoices, id: \.self) { Text("\(Int($0)) s").tag($0) }
        }
        Text("So lange wartet die Quellensuche auf jedes Addon. Schnelle Addons erscheinen sofort; "
             + "ein zu langsames wird als „Zeitüberschreitung“ angezeigt.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
