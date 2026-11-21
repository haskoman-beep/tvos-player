import SwiftUI
import AetherEngine
import PlayerCore

/// Standard für Backends ohne Startstand/Kapitel.
extension PlaybackEngine {
    var startupStatus: StartupStatus? { nil }
    var chapterMarks: [ChapterMark] { [] }
}

/// AetherEngine 7.71.2: `startupProgress` (#361, echte Schritte, nie auf Zeit), `isAwaitingDisplaySwitch` (AE#1000),
/// `mediaChapters` (Matroska/MP4-Kapitel auf der `seek(to:)`-Achse).
extension AetherBackend {
    var startupStatus: StartupStatus? {
        guard let p = engine.startupProgress else { return nil }
        return StartupStatus(step: StartupStep(rawValue: p.stage.rawValue), fraction: p.fraction,
                             awaitingDisplaySwitch: engine.isAwaitingDisplaySwitch)
    }
    var chapterMarks: [ChapterMark] {
        engine.mediaChapters.map { ChapterMark(name: $0.name, start: $0.startSeconds, duration: $0.durationSeconds) }
    }
}

/// Ladeanzeige im Player: während des Starts Kreisel plus aktueller Schritt („Spuren werden gelesen 38 %“),
/// beim Springen/Nachpuffern nur der Kreisel (wie bisher).
struct PlayerLoadingSteps<E: PlaybackEngine>: View {
    @ObservedObject var engine: E

    var body: some View {
        let line = StartupSteps.line(engine.startupStatus, dynamicRange: engine.sourceVideoFormatName)
        if let line, engine.isLoading || engine.startupStatus?.awaitingDisplaySwitch == true {
            VStack(spacing: 28) {
                ProgressView().scaleEffect(2)
                HStack(spacing: 14) {
                    Text(line.text)
                    if let p = line.percent { Text("\(p) %").monospacedDigit().foregroundStyle(.secondary) }
                }
                .font(.headline)
                if let p = line.percent {
                    ProgressView(value: Double(p), total: 100).frame(width: 420)
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 36)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: line)
            .onChange(of: line) { _, l in RemoteLog.info("player", "Start: \(l.text)\(l.percent.map { " \($0) %" } ?? "")") }
        } else if engine.isLoading {
            ProgressView().scaleEffect(2)
        }
    }
}
