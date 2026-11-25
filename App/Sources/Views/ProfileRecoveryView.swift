import SwiftUI
import PlayerCore

/// Task 1.3 (S-1): start screen when the stored profiles cannot be read. Until the user picks a way out, the app
/// saves nothing (`AppModel.save()` is a no-op), so the unreadable state is never overwritten.
struct ProfileRecoveryView: View {
    @EnvironmentObject var model: AppModel
    let reason: String
    let candidates: [RecoveryCandidate]
    @State private var selected: String?
    @Environment(\.theme) private var theme
    @State private var confirmFresh = false
    /// Final review: feedback when „Erneut versuchen“ finds the same unreadable state.
    @State private var retryNote: String?
    @FocusState private var focus: Field?

    enum Field: Hashable { case retry, candidate(String), load, fresh }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Profile nicht lesbar").textRole(.pageTitle)
                Text(reason).textRole(.rowDetail)
                Text("Bis du hier etwas wählst, speichert die App nichts. Der unlesbare Stand bleibt als Sicherung erhalten.")
                    .textRole(.rowDetail)
            }
            if candidates.isEmpty {
                Text("Keine ältere Fassung gefunden.").textRole(.rowTitle)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Ältere Fassungen").textRole(.sectionTitle)
                    ForEach(candidates) { c in
                        Button { selected = c.id } label: {
                            HStack(spacing: Theme.Space.m) {
                                Image(systemName: selected == c.id ? "checkmark.circle.fill" : "circle")
                                    .font(theme.type.glyph(.symbol))
                                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                    Text(c.label).textRoleInRow(.rowTitle)
                                    Text(Self.detail(c)).textRoleInRow(.rowDetail)
                                }
                            }
                        }
                        .buttonStyle(ThemeRowButtonStyle())
                        .focused($focus, equals: .candidate(c.id))
                    }
                }
            }
            HStack(spacing: Theme.Space.xl) {
                Button("Erneut versuchen") {
                    retryNote = nil
                    if !model.retryProfileLoad() {
                        retryNote = "Weiterhin nicht lesbar (Stand \(Date().formatted(date: .omitted, time: .standard)))."
                    }
                }
                    .focused($focus, equals: .retry)
                Button("Diese Fassung laden") { if let s = selected { model.restoreProfiles(s) } }
                    .disabled(selected == nil)
                    .focused($focus, equals: .load)
                Button("Neu anfangen", role: .destructive) { confirmFresh = true }
                    .focused($focus, equals: .fresh)
            }
            if let retryNote { Text(retryNote).textRole(.rowDetail) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.edge)
        .padding(.vertical, Theme.Space.edgeVertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .settingsSurface()
        .defaultFocus($focus, .retry)
        .onAppear { if selected == nil { selected = candidates.first?.id } }
        .onChange(of: candidates) { _, new in
            if !new.contains(where: { $0.id == selected }) { selected = new.first?.id }
        }
        .alert("Neu anfangen?", isPresented: $confirmFresh) {
            Button("Neu anfangen", role: .destructive) { model.startFreshProfiles() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die App legt ein neues Profil „Ich“ an. Der unlesbare Stand bleibt als Sicherung erhalten.")
        }
    }

    /// "2 Profile · 22.11.2026, 18:04" (date unknown for copies that only lie in UserDefaults).
    static func detail(_ c: RecoveryCandidate) -> String {
        let count = c.profiles == 1 ? "1 Profil" : "\(c.profiles) Profile"
        let date = c.savedAt.map { $0.formatted(date: .numeric, time: .shortened) } ?? "Datum unbekannt"
        return "\(count) · \(date)"
    }
}
