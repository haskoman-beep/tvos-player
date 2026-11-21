import SwiftUI

/// Klare Fehlermeldung, wenn die Fehlerleiter aufgibt (Ratenlimit, Netz weg, Zertifikat, Speicher).
/// Fokussierbare Knöpfe; Menü/Zurück schließt nur die Meldung (Abbrechen-Rolle).
struct PlaybackErrorAlert: ViewModifier {
    @Binding var notice: String?
    let chooseOther: () -> Void
    let retry: () -> Void

    func body(content: Content) -> some View {
        content.alert("Wiedergabe angehalten",
                      isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            // Aktion erst nach dem Schließen: ein neuer Fehler darf die nächste Meldung setzen.
            Button("Andere Quelle wählen") { notice = nil; Task { @MainActor in chooseOther() } }
            Button("Erneut versuchen") { notice = nil; Task { @MainActor in retry() } }
            Button("Schließen", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }
}

extension View {
    func playbackErrorAlert(_ notice: Binding<String?>, chooseOther: @escaping () -> Void,
                            retry: @escaping () -> Void) -> some View {
        modifier(PlaybackErrorAlert(notice: notice, chooseOther: chooseOther, retry: retry))
    }
}
