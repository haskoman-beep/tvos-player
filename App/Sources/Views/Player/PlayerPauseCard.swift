import SwiftUI
import PlayerCore

// Wave P-b: pause card. Rule and texts in PlayerCore `PauseCard.swift`.

/// Slot for a later accessory on the pause card (X-Ray, waves X4/X5). Set it with
/// `.environment(\.pauseCardAccessory, PauseCardAccessory { ctx in AnyView(...) })` above the player; nil = the cast
/// line is shown instead.
struct PauseCardAccessory: Sendable {
    var make: @MainActor @Sendable (PauseCardAccessoryContext) -> AnyView
}

private struct PauseCardAccessoryKey: EnvironmentKey {
    static let defaultValue: PauseCardAccessory? = nil
}

extension EnvironmentValues {
    var pauseCardAccessory: PauseCardAccessory? {
        get { self[PauseCardAccessoryKey.self] }
        set { self[PauseCardAccessoryKey.self] = newValue }
    }
}

/// Visibility of the card for one player. The player feeds inputs (`noteInput`, `dismiss`); the layer feeds the
/// playing state and the blocks twice a second.
@MainActor
final class PauseCardState: ObservableObject {
    @Published private(set) var isVisible = false
    private var rule = PauseCardRule()
    private var lastBlock: String?

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func evaluate(isPlaying: Bool, blockReason: String?) {
        rule.update(isPlaying: isPlaying, now: now)
        // A block counts as input: after a panel, scrubbing or the skip button the longer wait applies.
        if blockReason != nil { rule.noteInput(now: now) }
        if blockReason != lastBlock, !isPlaying, rule.pausedSince != nil {
            if let b = blockReason { RemoteLog.info("player", "Pausenkarte zurückgehalten: \(b)") }
            lastBlock = blockReason
        }
        if isPlaying { lastBlock = nil }
        let v = rule.isVisible(now: now, blocked: blockReason != nil)
        if v != isVisible {
            withAnimation(.easeInOut(duration: 0.35)) { isVisible = v }
            RemoteLog.info("player", v ? "Pausenkarte an" : "Pausenkarte aus")
        }
    }

    /// Any key, swipe or click hides the card.
    func noteInput() {
        rule.noteInput(now: now)
        if isVisible { withAnimation(.easeOut(duration: 0.2)) { isVisible = false } }
    }

    /// Menu while the card is visible only closes the card. Returns true when it did.
    func dismiss() -> Bool {
        guard isVisible else { return false }
        noteInput()
        RemoteLog.info("player", "Pausenkarte: Menü schließt nur die Karte")
        return true
    }
}

/// Full-screen layer of the card: dark gradient, clock top right, logo or title, episode line, short description,
/// cast line (or the accessory) bottom left. Not focusable; the player keeps all commands.
struct PlayerPauseCardLayer<E: PlaybackEngine>: View {
    @ObservedObject var state: PauseCardState
    @ObservedObject var engine: E
    let content: PauseCardContent?
    let accessoryContext: PauseCardAccessoryContext?
    /// Why the card must not show now (nil = free); read on every check.
    let blockReason: String?
    @Environment(\.pauseCardAccessory) private var accessory
    @State private var logoFailed = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if state.isVisible, let content {
                card(content).transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .onReceive(timer) { _ in
            state.evaluate(isPlaying: engine.isPlaying, blockReason: content == nil ? "keine Daten" : blockReason)
        }
    }

    private func card(_ c: PauseCardContent) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                           startPoint: .bottom, endPoint: .top)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let logo = c.logoURL, !logoFailed {
                    RemoteImage(url: logo, maxPixels: 1200, fit: true, onFailure: { _ in logoFailed = true })
                        .frame(maxWidth: 560, maxHeight: 180, alignment: .bottomLeading)
                        .accessibilityLabel(c.title)
                } else {
                    Text(c.title).font(.largeTitle.bold()).lineLimit(2)
                }
                if let line = c.episodeLine {
                    Text(line).font(.title3.weight(.semibold))
                }
                if let d = c.description {
                    Text(d).font(.callout).lineLimit(3)
                        .foregroundStyle(Theme.Palette.primary.opacity(0.9))
                }
                if let accessory, let ctx = accessoryContext {
                    accessory.make(ctx)
                } else if let cast = c.castLine {
                    Text(cast).font(.caption).lineLimit(1).foregroundStyle(Theme.Palette.secondary)
                }
                Text("Pausiert · beliebige Taste blendet aus").font(.caption2).foregroundStyle(Theme.Palette.secondary)
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, 80).padding(.bottom, 70)
            .foregroundStyle(Theme.Palette.primary)
        }
        .overlay(alignment: .topTrailing) {
            ClockView().padding(.top, 50).padding(.trailing, 80)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}
