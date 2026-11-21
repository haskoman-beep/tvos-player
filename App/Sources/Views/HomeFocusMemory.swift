import SwiftUI
import PlayerCore

// Welle C-b (#19, #8/#34): Fokus-Gedächtnis je Startseiten-Reihe und vergleichbare Karten.

/// Nicht beobachtete Referenz-Box: Merken löst keinen Neuaufbau aus. Die Reihe liest den gemerkten Stand,
/// wenn sie ohnehin neu zeichnet (jede Fokusänderung in ihr tut das), und setzt ihn als `defaultFocus`.
@MainActor
final class HomeRowFocusMemory {
    var state = RowFocusMemory()
}

private struct HomeRowFocusMemoryKey: EnvironmentKey {
    static let defaultValue: HomeRowFocusMemory? = nil
}

extension EnvironmentValues {
    /// Nur auf der Startseite gesetzt.
    var homeRowFocusMemory: HomeRowFocusMemory? {
        get { self[HomeRowFocusMemoryKey.self] }
        set { self[HomeRowFocusMemoryKey.self] = newValue }
    }
}

// Karten vergleichbar: Wandert der Fokus, baut SwiftUI unveränderte Karten nicht neu (`.equatable()` in HomeRowView).
// Fokus, Kartengröße und Aufklappen kommen aus der Umgebung bzw. dem eigenen Zustand und wirken weiter.
extension PosterCard: Equatable {
    nonisolated static func == (a: PosterCard, b: PosterCard) -> Bool { a.item == b.item }
}

extension LandscapeCard: Equatable {
    nonisolated static func == (a: LandscapeCard, b: LandscapeCard) -> Bool { a.item == b.item }
}

extension Top10Card: Equatable {
    nonisolated static func == (a: Top10Card, b: Top10Card) -> Bool { a.item == b.item && a.rank == b.rank }
}
