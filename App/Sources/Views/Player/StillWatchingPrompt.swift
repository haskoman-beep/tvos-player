import SwiftUI
import PlayerCore

/// Zustand für Auto-Weiter in der Quellenliste: „Noch da?“-Zähler, Addon je gestarteter Quelle (für den
/// Release-Vergleich der nächsten Folge) und eine offene Abfrage.
struct AutoNextState {
    var counter = StillWatchingCounter()
    /// Quellen-ID → Addon, auch für Quellen späterer Folgen (die nicht in der angezeigten Liste stehen).
    var addons: [String: String] = [:]
    var ask: StillWatchingAsk?
    /// Seit dem Start der laufenden Folge eine Taste gedrückt (z. B. „Klick: jetzt“ auf der Up-next-Karte):
    /// die nächste Folge zählt dann nicht als automatisch gestartet.
    var inputSinceStart = false

    /// Tastendruck: Zähler auf 0, Eingabe merken. Nur schreiben, wenn sich etwas ändert (sonst zeichnet jede Taste
    /// die Liste neu).
    @MainActor static func userInput(_ s: Binding<AutoNextState>) {
        var v = s.wrappedValue
        guard v.counter.autoStarts > 0 || !v.inputSinceStart else { return }
        if v.counter.userInput() { RemoteLog.info("player", "Noch da?: Tastendruck, Zähler zurückgesetzt") }
        v.inputSinceStart = true
        s.wrappedValue = v
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
struct StillWatchingAlert: ViewModifier {
    @Binding var state: AutoNextState
    @Binding var note: String?
    let onContinue: (StillWatchingAsk) -> Void

    func body(content: Content) -> some View {
        content
            .alert("Noch da?", isPresented: Binding(get: { state.ask != nil }, set: { if !$0 { state.ask = nil } }),
                   presenting: state.ask) { ask in
                Button("Weiterschauen") {
                    state.ask = nil
                    state.counter.userInput()
                    RemoteLog.info("player", "Noch da?: Weiterschauen")
                    onContinue(ask)
                }
                Button("Beenden", role: .cancel) {
                    state.ask = nil
                    note = "Wiedergabe beendet. Nächste Folge: \(ask.next.title)"
                    RemoteLog.info("player", "Noch da?: Beenden")
                }
            } message: { ask in
                Text("Nächste Folge: \(ask.next.title)")
            }
            .task(id: state.ask?.id) {
                guard let id = state.ask?.id else { return }
                try? await Task.sleep(for: .seconds(StillWatchingCounter.answerTimeout))
                guard !Task.isCancelled, state.ask?.id == id else { return }
                state.ask = nil
                note = "Keine Antwort auf „Noch da?“ – nächste Folge nicht gestartet."
                RemoteLog.info("player", "Noch da?: keine Antwort in \(Int(StillWatchingCounter.answerTimeout)) s, nichts gestartet")
            }
    }
}
