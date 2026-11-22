import SwiftUI
import PlayerCore

/// Welle F-b2: Kontextmenü einer Startseiten-Reihe (langer Druck auf eine Kachel, Plan R6/N8):
/// „Reihe bearbeiten“ öffnet den Verwalter mit dieser Reihe, „Ganz nach oben“ setzt sie auf Platz 1,
/// „Ausblenden …“ und (Welle F-f) „Löschen …“ fragen erst nach (die Startseite zeigt die Rückfrage).
/// Ausblenden ist umkehrbar (unter „Ausgeblendet“), Löschen nimmt die Reihe für immer weg.
struct HomeRowMenu {
    var canMoveUp: Bool
    var edit: () -> Void
    var moveToTop: () -> Void
    var hide: () -> Void
    var delete: () -> Void
}

extension View {
    @ViewBuilder func homeRowMenu(_ menu: HomeRowMenu?) -> some View {
        if let menu {
            contextMenu { HomeRowMenuItems(menu: menu) }
        } else {
            self
        }
    }
}

/// The row actions as menu items; wave L puts them below the tile actions in the tile menu.
struct HomeRowMenuItems: View {
    let menu: HomeRowMenu

    var body: some View {
        Button { menu.edit() } label: { Label("Reihe bearbeiten", systemImage: "slider.horizontal.3") }
        if menu.canMoveUp {
            Button { menu.moveToTop() } label: { Label("Ganz nach oben", systemImage: "arrow.up.to.line") }
        }
        Button(role: .destructive) { menu.hide() } label: { Label("Ausblenden …", systemImage: "eye.slash") }
        Button(role: .destructive) { menu.delete() } label: { Label("Löschen …", systemImage: "trash") }
    }
}
