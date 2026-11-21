import SwiftUI
import PlayerCore

extension AppModel {
    /// IntroDB-Abfrage für den PlayRequest (Film oder Folge); nil ohne IMDb-ID.
    func introDBQuery(for r: PlayRequest) async -> IntroDBQuery? {
        var imdb = await imdbID(for: r.item)
        if imdb == nil, r.id.hasPrefix("tt") { imdb = r.id.split(separator: ":").first.map(String.init) }
        guard let imdb else { return nil }
        if r.type == "series" {
            guard let s = r.season, let e = r.episode else { return nil }
            return IntroDBQuery(imdb: imdb, season: s, episode: e)
        }
        return IntroDBQuery(imdb: imdb)
    }
}

/// Sprungbereiche der laufenden Wiedergabe: IntroDB + Kapitel, Planer für den Knopf, Abspann-Zeitpunkt.
/// Lebt als @StateObject in PlayerControls (eine Wiedergabe = ein Controller).
@MainActor
final class SkipSegmentController: ObservableObject {
    /// Bereich, für den der Knopf gerade steht (nil = kein Knopf).
    @Published private(set) var prompt: SkipSegment?
    /// Zeitpunkt der Nächste-Folge-Karte aus dem Abspann (Sekunden ab Dateibeginn); nil = Standard
    /// (bisherige Regel 20 s vor Ende). Für Abschnitt c (Up-next).
    @Published private(set) var upNextAt: Double?
    /// Alle bekannten Bereiche (Kapitel gewinnen je Art).
    @Published private(set) var segments: [SkipSegment] = []

    private var planner = SkipPlanner()
    private var introDB: [SkipSegment] = []
    private var chapters: [ChapterMark] = []
    private var duration: Double = 0
    private var lookupDone = false
    /// Treffer je Abfrage für die Laufzeit der App (nur nicht-leere Antworten; Fehler werden nicht gemerkt).
    private static var cache: [IntroDBQuery: [SkipSegment]] = [:]

    /// IntroDB einmal je Wiedergabe abfragen. Abgebrochen (Player verlassen/Panel) → beim nächsten Mal erneut.
    func lookup(_ query: (@MainActor () async -> IntroDBQuery?)?) async {
        guard let query, !lookupDone else { return }
        // Kein `leaving`-Wächter nötig: hier wird nur Zustand dieses Controllers gesetzt (kein Start, kein Ausgang,
        // keine Engine-Aufrufe). Beim Verlassen bricht `.task` ab, und der Controller stirbt mit PlayerControls.
        guard let q = await query() else { lookupDone = true; RemoteLog.info("skip", "IntroDB: keine Abfrage (Trailer oder ohne IMDb-ID)"); return }
        guard !Task.isCancelled else { return }
        if let hit = Self.cache[q] {
            introDB = hit
        } else {
            let tag = "\(q.imdb)\(q.isMovie ? "" : " S\(q.season ?? 0)E\(q.episode ?? 0)")"
            let list = await IntroDBClient().segments(q, log: { line in
                Task { @MainActor in RemoteLog.info("skip", "IntroDB \(tag): \(line)") }
            })
            guard !Task.isCancelled else { return }
            if !list.isEmpty { Self.cache[q] = list }
            introDB = list
        }
        lookupDone = true
        rebuild()
    }

    /// Stand der Engine übernehmen (Kapitel, Laufzeit, Position). Etwa zweimal je Sekunde.
    func update<E: PlaybackEngine>(engine: E) {
        let marks = engine.chapterMarks, d = engine.duration
        if marks != chapters || abs(d - duration) > 1 { chapters = marks; duration = d; rebuild() }
        // Ohne Laufzeit (vor dem Laden) oder bei Fehler nie ein Knopf: wie „Engine beschäftigt“ behandeln.
        let pos = engine.currentTime, busy = engine.isLoading || engine.duration <= 0 || engine.errorText != nil
        planner.observe(position: pos, engineSeeking: busy, now: Self.now)
        let p = planner.prompt(at: pos, engineSeeking: busy)
        if p != prompt {
            if let p { RemoteLog.info("skip", "Knopf \(p.kind.rawValue) (\(p.source.rawValue)) \(Int(p.start))–\(Int(p.end))s bei \(Int(pos))s") }
            prompt = p
        }
    }

    /// Knopf gedrückt: ans Bereichsende springen. Während des Sprungs zeigt der Planer keinen Knopf.
    func skip<E: PlaybackEngine>(engine: E) async {
        guard let s = prompt else { return }
        let target = planner.beginSkip(s, duration: engine.duration, now: Self.now)
        prompt = nil
        RemoteLog.info("skip", "\(s.kind.rawValue) übersprungen \(Int(engine.currentTime)) → \(Int(target))s")
        await engine.seek(target, exact: true)
    }

    /// Menü/Zurück bei sichtbarem Knopf: Knopf weg (bis der Bereich verlassen wurde). true = Taste verbraucht.
    func dismissPrompt() -> Bool {
        guard let s = prompt else { return false }
        planner.dismiss(s)
        prompt = nil
        RemoteLog.info("skip", "Knopf \(s.kind.rawValue) weggeschickt")
        return true
    }

    private func rebuild() {
        let merged = SkipSegments.merge(chapters: SkipSegments.fromChapters(chapters, duration: duration),
                                        introDB: introDB, duration: duration)
        guard merged != segments else { return }
        segments = merged
        planner.setSegments(merged)
        upNextAt = SkipSegments.upNextTime(merged, duration: duration)
        if !merged.isEmpty {
            RemoteLog.info("skip", "Bereiche: " + merged.map { "\($0.kind.rawValue)/\($0.source.rawValue) \(Int($0.start))–\(Int($0.end))s" }
                .joined(separator: ", ") + (upNextAt.map { " · Up-next ab \(Int($0))s" } ?? ""))
        }
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }
}

/// „Intro überspringen“ / „Rückblick überspringen“ unten rechts. Fokussierbar (PlayerControls nimmt sich dafür
/// den Fokus weg, solange der Knopf steht); verschwindet nach dem Bereich. Kein Auto-Sprung.
struct SkipSegmentButton<E: PlaybackEngine>: View {
    @ObservedObject var controller: SkipSegmentController
    let engine: E
    var lookup: (@MainActor () async -> IntroDBQuery?)?
    /// Vor dem Sprung: gesammelten ±10-s-Sprung in PlayerControls verwerfen.
    var onBeforeSkip: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if let s = controller.prompt, let title = s.buttonTitle {
                Button { onBeforeSkip(); Task { await controller.skip(engine: engine) } } label: {
                    Label(title, systemImage: "forward.end.fill").font(.headline)
                }
                .focused($focused)
                .padding(.trailing, 80).padding(.bottom, 300)
                .transition(.opacity)
                .onAppear { focused = true }
                .task(id: s) {
                    // Fokus sofort und noch einmal eine Runde später (falls der Knopf beim ersten Mal noch nicht im
                    // Fokus-Baum war): die Fläche ist ab jetzt nicht fokussierbar, ohne Knopf-Fokus gingen Befehle verloren.
                    focused = true
                    try? await Task.sleep(for: .milliseconds(50))
                    if !focused { focused = true }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.prompt)
        // IntroDB einmal je Wiedergabe; daneben zweimal je Sekunde Kapitel/Position übernehmen.
        .task { await controller.lookup(lookup) }
        .task {
            while !Task.isCancelled {
                controller.update(engine: engine)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
