import Foundation
import Network
import AVFoundation
import PlayerCore

/// Welle C-a: Zustand für die Stabilität der Wiedergabe, app-weit.
/// - Netzpfad (NWPathMonitor ab App-Start): ohne Netz wartet die Fehlerleiter, statt weiterzuschalten.
/// - Ton-/HDMI-Routenwechsel (AVAudioSession): ein Fehler kurz danach lädt einmal an der Stelle neu.
/// - Kürzlich fehlgeschlagene Quellen je Titel (8 h, dauerhaft über die App-Ablage).
/// - Zeitstempel des laufenden Starts (t0–t3, eine Logzeile).
@MainActor
final class PlaybackStability: ObservableObject {
    static let shared = PlaybackStability()

    @Published private(set) var isOnline = true
    @Published private(set) var failedLinks = FailedLinkBook()
    var routeWindow = RouteChangeWindow()
    var timing = StartTiming()

    private var storage: BlobStorage?
    private var monitor: NWPathMonitor?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Einmal beim App-Start (AppModel.init): Buch laden, Netz- und Routenbeobachtung starten.
    func attach(_ storage: BlobStorage) {
        guard self.storage == nil else { return }
        self.storage = storage
        failedLinks = FailedLinkBook.load(from: storage)
        let n = failedLinks.entries.values.reduce(0) { $0 + $1.count }
        if n > 0 { RemoteLog.info("stabil", "Zuletzt fehlgeschlagene Quellen: \(n) in \(failedLinks.entries.count) Titel(n)") }
        startNetworkMonitor()
        startRouteObservers()
    }

    // MARK: Netz

    private func startNetworkMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in PlaybackStability.shared.networkChanged(online: online) }
        }
        m.start(queue: DispatchQueue(label: "player.netzpfad"))
        monitor = m
    }

    private func networkChanged(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        RemoteLog.info("stabil", online ? "Netz wieder da" : "Kein Netzpfad (offline)")
    }

    // MARK: Ton-Route

    private func startRouteObservers() {
        let session = AVAudioSession.sharedInstance()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in PlaybackStability.shared.routeChanged(reasonRaw: raw) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { _ in
            Task { @MainActor in PlaybackStability.shared.routeChanged(reasonRaw: nil) }
        })
    }

    private func routeChanged(reasonRaw: UInt?) {
        routeWindow.note(reasonRaw: reasonRaw)
        guard reasonRaw != RouteChangeWindow.ignoredReasonRaw else { return }
        RemoteLog.info("stabil", reasonRaw.map { "Ton-Route gewechselt (Grund \($0))" } ?? "Tonsitzung unterbrochen")
    }

    /// Umstände für die Fehlerleiter. Verbraucht einen kurz zurückliegenden Routenwechsel.
    func recoveryContext(afterFirstFrame: Bool) -> RecoveryContext {
        RecoveryContext(offline: !isOnline, routeChangedRecently: routeWindow.consume(afterFirstFrame: afterFirstFrame))
    }

    // MARK: Fehlgeschlagene Quellen

    func isRecentlyFailed(_ s: StreamItem, title: String) -> Bool { failedLinks.isRecentlyFailed(s, title: title) }

    /// Liste für automatische Wahlen (Weiterschauen, Rückfall, nächste Folge): ohne kürzlich fehlgeschlagene.
    func autoCandidates(_ list: [(addon: String, stream: StreamItem)], title: String) -> [(addon: String, stream: StreamItem)] {
        list.filter { !failedLinks.isRecentlyFailed($0.stream, title: title) }
    }

    /// Urteil des Players anwenden und speichern.
    func apply(_ verdict: SourceVerdict, stream: StreamItem, title: String) {
        guard failedLinks.apply(verdict, stream: stream, title: title) else { return }
        switch verdict {
        case .healthy: RemoteLog.info("stabil", "Quelle spielt stabil → nicht mehr als fehlgeschlagen markiert")
        case .placeholder: RemoteLog.info("stabil", "Quelle für 8 h als fehlgeschlagen gemerkt (Platzhalter)")
        case .failed(let cls): RemoteLog.info("stabil", "Quelle für 8 h als fehlgeschlagen gemerkt (\(cls.rawValue))")
        }
        guard let storage else { return }
        do { try failedLinks.save(to: storage) } catch { RemoteLog.error("stabil", "Fehlgeschlagene Quellen nicht gespeichert: \(error)") }
    }
}
