import SwiftUI
import PlayerCore

/// Welle C-a: Stand der Quellensuche je Inhalt (Status je Addon, schon eingetroffene Treffer).
@MainActor
final class StreamSearchStatus: ObservableObject {
    static let shared = StreamSearchStatus()
    @Published private(set) var progress: [String: AddonSearchProgress] = [:]
    private var updatedAt: [String: Date] = [:]
    private init() {}

    /// Welle D-b (I1): Profilwechsel – kein Zwischenstand eines anderen Profils bleibt sichtbar.
    func reset() { progress.removeAll(); updatedAt.removeAll() }

    func update(_ id: String, _ p: AddonSearchProgress) {
        progress[id] = p
        updatedAt[id] = Date()
        // Nur wenige Inhalte behalten (Vorladen fragt viele ab): der am längsten nicht aktualisierte fällt heraus.
        if progress.count > 30, let drop = updatedAt.filter({ $0.key != id }).min(by: { $0.value < $1.value })?.key {
            progress[drop] = nil; updatedAt[drop] = nil
        }
    }

    /// Schon eingetroffene, abspielbare Treffer in Addon-Reihenfolge.
    /// Task 3.6: entries carry the unique label of their installation (`AddonIdentity`), not the bare name.
    func partial(_ id: String) -> [(addon: String, stream: StreamItem)] {
        guard let p = progress[id] else { return [] }
        return p.results.flatMap { r in playableStreams(r.streams).map { (p.label(of: r.addon), $0) } }
    }
}

extension AppModel {
    /// Quellensuche mit Zeitgrenze je Addon (Profil `addonTimeout`); meldet jeden Zwischenstand an `StreamSearchStatus`.
    /// Ergebnis wie `addons.streams(from:type:id:)`: nur Addons mit Antwort, in Addon-Reihenfolge.
    /// `failed`: gefragte Addons ohne Antwort (Fehler, Zeitüberschreitung); nicht leer = lückenhaft → nur kurz frisch.
    /// Direkt aus dem Ergebnis bestimmt, nicht aus dem globalen Status (der kann inzwischen verdrängt sein).
    /// Läuft als ungebundene Aufgabe in `streams()` (geteilt mit Vorladen und Cache) und endet spätestens nach der
    /// Addon-Frist; Verlassen der Liste bricht sie deshalb bewusst nicht ab.
    /// Welle D-b (I1): Zwischenstände nur melden, solange Profil (`owner`) und Stand (`epoch`) noch gelten; eine
    /// alte Suche nach dem Profilwechsel füllt sonst die Quellenliste des neuen Profils.
    func searchAddons(type: String, id: String, owner: UUID, epoch: Int) async -> (results: [(addon: InstalledAddon, streams: [StreamItem])], failed: Set<String>) {
        let timeout = profile.addonTimeout
        let installed = profile.addons
        let asked = installed.filter { $0.manifest.supports("stream", type: type, id: id) }
        let result = await addons.streams(from: profile.addons, type: type, id: id, timeout: timeout) { p in
            await MainActor.run {
                guard self.searchStillCurrent(owner: owner, epoch: epoch) else { return }
                StreamSearchStatus.shared.update(id, p)
            }
        }
        if searchStillCurrent(owner: owner, epoch: epoch), let p = StreamSearchStatus.shared.progress[id] {
            RemoteLog.info("streams", "\(id): Addon-Status \(p.logText) · Grenze \(Int(timeout)) s")
        }
        // Task 3.6 (A-A-9): compared by `instanceID`; two installations with one name no longer cover for each other.
        return (result, AddonIdentity.unanswered(asked: asked, answered: result.map(\.addon), in: installed))
    }

    /// Welle D-b: Suche gehört noch zum aktiven Profil und wurde nicht durch einen Profilwechsel vergessen.
    func searchStillCurrent(owner: UUID, epoch: Int) -> Bool {
        profile.id == owner && streamTasks.isCurrent(epoch: epoch)
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
/// Task 3.7 (A-A-7): also the state that already exists when the view appears (joining a running search of the
/// detail page or the prefetch), not only the next finished addon. A finished search is left to the caller's own
/// result (its last state may be an older search of this title).
struct StreamSearchPartials: ViewModifier {
    let id: String
    let loading: Bool
    let apply: ([(addon: String, stream: StreamItem)]) -> Void
    @ObservedObject private var search = StreamSearchStatus.shared

    func body(content: Content) -> some View {
        content.onChange(of: search.progress[id]?.finishedCount ?? 0, initial: true) { old, new in
            guard loading, let p = search.progress[id], !p.isComplete else { return }
            let list = search.partial(id)
            guard !list.isEmpty else { return }
            if old == new { RemoteLog.info("streams", "\(id): Beitritt mit Zwischenstand (\(p.finishedCount)/\(p.statuses.count) Addons, \(list.count) Quellen)") }
            apply(list)
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

/// Einstellung „Zeitgrenze je Addon“ (Einstellungen › Addons › Suche, wave S).
struct AddonTimeoutPicker: View {
    @Environment(AppModel.self) var model

    var body: some View {
        // Alte/fremde Werte auf die nächstliegende Auswahl abbilden (Welle F-a: Auswahlzeile statt Picker).
        SettingsChoiceRow(symbol: "timer", tint: SettingsCategory.addons.tint, title: "Zeitgrenze je Addon",
                          detail: "So lange wartet die Quellensuche auf jedes Addon. Schnelle Addons erscheinen sofort; "
                              + "ein zu langsames wird als „Zeitüberschreitung“ angezeigt.",
                          options: AddonSearch.timeoutChoices,
                          selection: Binding(get: { AddonSearch.nearestChoice(model.profile.addonTimeout) },
                                             set: { v in model.update { $0.addonTimeout = v } }),
                          label: { "\(Int($0)) s" })
    }
}
