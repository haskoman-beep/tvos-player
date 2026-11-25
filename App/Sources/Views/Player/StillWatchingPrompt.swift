import SwiftUI
import PlayerCore

/// Zustand für Auto-Weiter in der Quellenliste: „Noch da?“-Zähler, Addon je gestarteter Quelle (für den
/// Release-Vergleich der nächsten Folge) und eine offene Abfrage.
struct AutoNextState {
    var counter = StillWatchingCounter()
    /// Quellen-ID → Addon, auch für Quellen späterer Folgen (die nicht in der angezeigten Liste stehen).
    var addons: [String: String] = [:]
    var ask: StillWatchingAsk?

    /// Tastendruck: Zähler auf 0, Zeitpunkt merken (`counter.lastInputAt`; „Klick: jetzt“ startet die nächste Folge
    /// von Hand, siehe `StillWatchingCounter.startIsManual`).
    @MainActor static func userInput(_ s: Binding<AutoNextState>) {
        if s.wrappedValue.counter.userInput() { RemoteLog.info("player", "Noch da?: Tastendruck, Zähler zurückgesetzt") }
    }

    /// Vor dem automatischen Start der nächsten Folge: muss erst gefragt werden?
    func promptDue(_ profile: Profile) -> Bool { counter.promptDue(limit: profile.stillWatchingAfter) }

    /// Release-Merkmale der zuletzt gespielten Quelle; `listAddon` aus der angezeigten Liste als Rückfall.
    func releaseProfile(_ stream: StreamItem, listAddon: String?) -> ReleaseProfile {
        ReleaseProfile(stream: stream, addon: addons[stream.id] ?? listAddon)
    }
}

/// Offene „Noch da?“-Abfrage vor der nächsten Folge.
struct StillWatchingAsk: Identifiable {
    let id = UUID()
    /// Zuletzt gespielte Quelle (Release-Vergleich für die nächste Folge).
    let stream: StreamItem
    let next: PlayRequest
}

/// „Noch da?“-Abfrage: „Weiterschauen“ (Standardfokus) oder „Beenden“ (auch Menü/Zurück).
/// Ohne Antwort nach 60 s schließt sie sich, und es startet nichts.
/// Task 5.4 (`player.stillWatching`): own overlay instead of the system alert, same answers and timeout.
/// `dialog`: page dimmed 60 %, card 800 wide in the centre; `karte`: card bottom left (80/80), 760 wide, no dimming.
struct StillWatchingAlert: ViewModifier {
    @Binding var state: AutoNextState
    @Binding var note: String?
    let onContinue: (StillWatchingAsk) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(get: { state.ask != nil }, set: { if !$0 { state.ask = nil } })) {
                if let ask = state.ask {
                    StillWatchingPromptView(style: model.profile.themeLook.player.stillWatching, ask: ask,
                                            onContinue: { answerContinue(ask) }, onEnd: { answerEnd(ask) })
                        .environment(\.theme, theme)
                }
            }
            .task(id: state.ask?.id) {
                guard let id = state.ask?.id else { return }
                RemoteLog.info("player", "Noch da?: gefragt (Stil \(model.profile.themeLook.player.stillWatching.rawValue))")
                try? await Task.sleep(for: .seconds(StillWatchingCounter.answerTimeout))
                guard !Task.isCancelled, state.ask?.id == id else { return }
                state.ask = nil
                note = "Keine Antwort auf „Noch da?“ – nächste Folge nicht gestartet."
                RemoteLog.info("player", "Noch da?: keine Antwort in \(Int(StillWatchingCounter.answerTimeout)) s, nichts gestartet")
            }
    }

    private func answerContinue(_ ask: StillWatchingAsk) {
        guard state.ask?.id == ask.id else { return }
        state.ask = nil
        state.counter.userInput()
        RemoteLog.info("player", "Noch da?: Weiterschauen")
        onContinue(ask)
    }

    private func answerEnd(_ ask: StillWatchingAsk) {
        guard state.ask?.id == ask.id else { return }
        state.ask = nil
        note = "Wiedergabe beendet. Nächste Folge: \(ask.next.title)"
        RemoteLog.info("player", "Noch da?: Beenden")
    }
}

/// Task 5.4: the „Noch da?“ card. „Weiterschauen“ has the first focus; Menu answers „Beenden“ (as the cancel
/// button of the old alert did).
private struct StillWatchingPromptView: View {
    let style: LookStillWatching
    let ask: StillWatchingAsk
    let onContinue: () -> Void
    let onEnd: () -> Void
    @Environment(\.theme) private var theme
    @FocusState private var focus: Answer?

    private enum Answer: Hashable { case keepWatching, end }

    var body: some View {
        ZStack {
            if style == .dialog { Color.black.opacity(OverlayCardMetrics.dimDialog).ignoresSafeArea() }
            card
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style == .dialog ? .center : .bottomLeading)
                .padding(.leading, style == .dialog ? 0 : 80).padding(.bottom, style == .dialog ? 0 : 80)
                .ignoresSafeArea()
        }
        .defaultFocus($focus, .keepWatching)
        .onExitCommand { onEnd() }
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        OverlayCard {
            VStack(alignment: .leading, spacing: theme.space.m) {
                Text("Noch da?").textRole(.sectionTitle)
                Text("Nächste Folge: \(ask.next.title)").textRole(.rowDetail).lineLimit(2)
                HStack(spacing: theme.space.m) {
                    // 5.3-merge: ThemeButton(.primary)
                    Button("Weiterschauen", action: onContinue)
                        .buttonStyle(ThemeActionButtonStyle())
                        .focused($focus, equals: .keepWatching)
                    Button("Beenden", action: onEnd)
                        .buttonStyle(ThemeActionButtonStyle())
                        .focused($focus, equals: .end)
                }
                .font(theme.type.font(.rowTitleEmphasis))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: style == .dialog ? 800 : 760)
    }
}
