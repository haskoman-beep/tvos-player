import SwiftUI
import PlayerCore

/// Welle F-b2: Verwalter „Reihen & Collections“ (Plan §2.5, Ebene 1). Ersetzt den Vollbild-Editor.
/// - Oben „Reihe hinzufügen“ (öffnet den Browser, Ebene 2), darunter eine kompakte Zeile je Reihe.
/// - OK auf einer Reihe klappt die Aktionsleiste auf (zwei Zeilen): Ganz nach oben · Ganz nach unten · Verschieben,
///   darunter An Position … · Stil, darunter Ausblenden … · Löschen … (Welle F-f)
/// - „Verschieben“: ▲▼ verschiebt, OK legt ab, Menu stellt die alte Stelle wieder her.
/// - Löschen fragt erst nach und nimmt die Reihe für immer weg (nicht unter „Ausgeblendet“).
/// - Ausblenden fragt erst nach; ausgeblendete Reihen stehen unten unter „Ausgeblendet“ (`Profile.hiddenRows`,
///   dieselbe Liste wie auf der Handy-Seite).
/// Alle Änderungen laufen über `HomeManager`/`HomeEditor` (PlayerCore) und werden sofort gespeichert.
struct HomeManagerView: View {
    /// Reihe, auf der der Fokus beim Öffnen liegt (Kontextmenü „Reihe bearbeiten“); nil = „Reihe hinzufügen“.
    var focusRow: UUID? = nil
    /// Gleich den Browser öffnen (leere Startseite „Reihen hinzufügen“); zurück landet man hier auf der neuen Reihe.
    var openBrowser = false
    @Environment(AppModel.self) var model
    @State private var session: HomeRowsSession?
    @Environment(\.theme) private var theme

    var body: some View {
        if let session {
            HomeManagerContent(session: session, focusRow: focusRow, openBrowser: openBrowser)
        } else {
            theme.color.surface.ignoresSafeArea()
                .onAppear { session = HomeRowsSession(model: model) }
        }
    }
}

private struct HomeManagerContent: View {
    let session: HomeRowsSession
    let focusRow: UUID?
    let openBrowser: Bool
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    enum BarAction: CaseIterable, Hashable { case top, bottom, move, position, style, hide, delete }
    enum Field: Hashable { case add, row(UUID), action(UUID, BarAction), hidden(UUID) }

    @FocusState private var focus: Field?
    @State private var expanded: UUID?
    @State private var hideCandidate: HomeRow?
    @State private var deleteCandidate: HomeRow?
    @State private var positionRow: HomeRow?
    @State private var positionChoice: PositionChoice?
    @State private var showBrowser = false
    @State private var beforeBrowser: HomeManager.Focus = .add
    @State private var started = false

    private var manager: HomeManager { session.manager }
    private var moving: UUID? { manager.moving?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: theme.space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        SettingsHeader(title: "Reihen & Collections",
                                       summary: "Reihenfolge und Stil der Startseite. Neue Reihen erscheinen unten.")
                        Spacer(minLength: theme.space.m)
                        Text(summary).textRole(.rowDetail).monospacedDigit().lineLimit(1)
                    }
                    .padding(.bottom, theme.space.m)
                    addLine
                    if manager.rows.isEmpty {
                        Text("Deine Startseite ist leer. Füge Reihen aus Addons, Collections oder dem Fusion-Kit hinzu.")
                            .textRole(.rowDetail)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, theme.space.s)
                    }
                    ForEach(manager.rows) { row in
                        VStack(alignment: .leading, spacing: theme.space.xs) {
                            line(row)
                            if expanded == row.id && moving == nil { actionBar(row) }
                        }
                        .id(row.id)
                    }
                    hiddenSection
                    Text(moving != nil ? "▲▼ verschieben · OK ablegen · Menu: alte Stelle"
                                       : "OK auf einer Reihe zeigt die Aktionen. Neue Reihen erscheinen unten.")
                        .textRole(.rowDetail)
                        .padding(.top, theme.space.m)
                }
                .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, theme.space.edge)
                .padding(.vertical, theme.space.edgeVertical)
            }
            .scrollClipDisabled()
            .onChange(of: manager.rows.map(\.id)) { _, _ in
                // Task 5.5: theme timing; with "reduce motion" the list jumps (no animation).
                if let m = moving { withAnimation(theme.motion.focusAnimation) { proxy.scrollTo(m, anchor: .center) } }
            }
        }
        .settingsSurface()
        .defaultFocus($focus, field(manager.entryFocus(row: focusRow)))
        .onAppear {
            guard !started else { return }
            started = true
            session.adoptProfile()
            focus = field(manager.entryFocus(row: focusRow))
            if openBrowser { open() }
        }
        .onChange(of: model.profile.home) { _, _ in session.adoptProfile() }
        .onChange(of: model.profile.hiddenRows) { _, _ in session.adoptProfile() }
        .onChange(of: showBrowser) { _, shown in
            guard !shown else { return }
            session.adoptProfile()
            set(manager.focusAfterBrowser(previous: beforeBrowser))
        }
        .navigationDestination(isPresented: $showBrowser) { AddRowBrowser(session: session) }
        .onExitCommand { exit() }
        // Eigene Rückfrage (F-a SettingsConfirmationView); Fokus-Rückgabe erst nach dem Schließen der Überlagerung.
        .settingsConfirmation(item: $hideCandidate, title: { "„\(session.title($0))“ ausblenden?" },
                              message: { _ in "Die Reihe verschwindet von der Startseite. Unter „Ausgeblendet“ lässt sie sich wieder einblenden." },
                              verb: "Ausblenden", symbol: "eye.slash", onKeep: { row in set(.row(row.id)) }) { row in
            expanded = nil
            set(session.hide(row.id))
        }
        // Welle F-f: Löschen, gleiche Rückfrage („Behalten“ mit Standardfokus), Fokus danach auf die Nachbarreihe.
        .settingsConfirmation(item: $deleteCandidate, title: { "„\(session.title($0))“ löschen?" },
                              message: { HomeView.deleteMessage($0) }, verb: "Löschen", symbol: "trash",
                              onKeep: { row in set(.row(row.id)) }) { row in
            expanded = nil
            set(session.delete(row.id))
        }
        // Task 4.1a (F-A-7): like the confirmations, move and focus only after the sheet closed (`onDismiss`);
        // before, the focus was set while it still lay in the sheet and the trigger (action bar) went away with it.
        .sheet(item: $positionRow, onDismiss: applyPositionChoice) { row in
            PositionPicker(title: session.title(row), current: manager.position(of: row.id) ?? 1,
                           positions: manager.positions) { p in
                positionChoice = PositionChoice(row: row.id, position: p)
                positionRow = nil
            }
        }
    }

    /// Task 4.1a (F-A-7): result of the position sheet, applied in its `onDismiss`.
    private struct PositionChoice { let row: UUID; let position: Int? }

    private func applyPositionChoice() {
        guard let c = positionChoice else { return }
        positionChoice = nil
        expanded = nil
        if let p = c.position { set(session.move(c.row, toPosition: p)) } else { set(.row(c.row)) }
    }

    private var summary: String {
        let n = manager.count
        let rows = n == 1 ? "1 Reihe" : "\(n) Reihen"
        let hidden = manager.restorable.count
        return DesignText.metaLine([rows, hidden > 0 ? "\(hidden) ausgeblendet" : nil])
    }

    // MARK: Zeilen

    private var addLine: some View {
        SettingsRow(symbol: "plus", tint: Theme.CategoryTint.home.color, title: "Reihe hinzufügen",
                    detail: "Addons, Collections, Fusion-Kit", accessory: .chevron, detailAlwaysVisible: true,
                    reserveDetailSpace: false) { open() }
            .focused($focus, equals: .add)
            .disabled(moving != nil)
    }

    private func line(_ row: HomeRow) -> some View {
        let isMoving = moving == row.id
        return Button {
            if isMoving {
                set(session.endMove())
            } else {
                withAnimation(theme.motion.focusAnimation) { expanded = expanded == row.id ? nil : row.id }
                // Erst im nächsten Durchlauf: dann gibt es die Leiste schon (Abnahme „OK, OK“, Review I3).
                if expanded == row.id {
                    let id = row.id
                    DispatchQueue.main.async { if expanded == id { focus = .action(id, .top) } }
                }
            }
        } label: {
            ManagedRowLine(position: manager.position(of: row.id) ?? 0, title: session.title(row),
                           info: session.info(row), isNew: manager.isNew(row.id), moving: isMoving)
        }
        .buttonStyle(ThemeRowButtonStyle(minHeight: Theme.Layout.categoryRowMinHeight))
        .overlay {
            if isMoving {
                RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous)
                    .stroke(Theme.Tone.warn.color, lineWidth: Theme.Layout.accentMarkWidth)
                    .allowsHitTesting(false)
            }
        }
        .focused($focus, equals: .row(row.id))
        .disabled(moving != nil && !isMoving)
        .onMoveCommand { dir in
            guard isMoving else { return }
            switch dir {
            case .up: _ = session.step(up: true)
            case .down: _ = session.step(up: false)
            default: break
            }
        }
        .accessibilityHint(isMoving ? "Nach oben oder unten wischen verschiebt, auswählen legt ab." : "Auswählen zeigt die Aktionen.")
    }

    /// Drei Zeilen (3 · 2 · 2 Knöpfe, Skizze §2.5), damit keine Beschriftung abgeschnitten wird (Review M10);
    /// die beiden entfernenden Aktionen stehen zusammen in der letzten Zeile.
    private func actionBar(_ row: HomeRow) -> some View {
        VStack(alignment: .leading, spacing: theme.space.xs) {
            HStack(spacing: theme.space.xs) {
                barButton(row, .top, "Ganz nach oben", "arrow.up.to.line") { set(session.moveToTop(row.id)); expanded = nil }
                barButton(row, .bottom, "Ganz nach unten", "arrow.down.to.line") { set(session.moveToBottom(row.id)); expanded = nil }
                barButton(row, .move, "Verschieben", "arrow.up.arrow.down") {
                    expanded = nil
                    if session.beginMove(row.id) { focus = .row(row.id) }
                }
            }
            HStack(spacing: theme.space.xs) {
                barButton(row, .position, "An Position …", "number") { positionRow = row }
                barButton(row, .style, "Stil: \(row.style.displayName)", "rectangle.grid.1x2") {
                    set(session.cycleStyle(row.id)); focus = .action(row.id, .style)
                }
            }
            HStack(spacing: theme.space.xs) {
                barButton(row, .hide, "Ausblenden …", "eye.slash") { hideCandidate = row }
                barButton(row, .delete, "Löschen …", "trash") { deleteCandidate = row }
            }
        }
        .padding(.leading, theme.space.l)
        .focusSection()
        .defaultFocus($focus, .action(row.id, .top))
    }

    private func barButton(_ row: HomeRow, _ a: BarAction, _ title: String, _ symbol: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .textRoleInRow(.rowDetail)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(ThemeRowButtonStyle(minHeight: Theme.Layout.actionBarRowHeight, maxWidth: .infinity))
        .focused($focus, equals: .action(row.id, a))
    }

    @ViewBuilder private var hiddenSection: some View {
        let hidden = manager.restorable
        if !hidden.isEmpty {
            SettingsSectionLabel(title: "Ausgeblendet")
            ForEach(hidden) { row in
                SettingsRow(symbol: "eye.slash", tint: Theme.CategoryTint.home.color, title: session.title(row),
                            detail: session.info(row).detail, accessory: .value("Wieder einblenden"),
                            reserveDetailSpace: false) {
                    set(session.restore(row.id))
                }
                .focused($focus, equals: .hidden(row.id))
                .disabled(moving != nil)
            }
        }
    }

    // MARK: Fokus und Menu

    private func field(_ f: HomeManager.Focus) -> Field {
        switch f {
        case .add: .add
        case .row(let id): .row(id)
        case .hidden(let id): .hidden(id)
        }
    }

    private func set(_ f: HomeManager.Focus) { focus = field(f) }

    private func open() {
        beforeBrowser = currentFocus
        expanded = nil
        showBrowser = true
    }

    private var currentFocus: HomeManager.Focus {
        switch focus {
        case .row(let id)?, .action(let id, _)?: .row(id)
        case .hidden(let id)?: .hidden(id)
        default: .add
        }
    }

    /// Menu: Verschieben abbrechen → Aktionsleiste zuklappen → Verwalter verlassen.
    private func exit() {
        if moving != nil {
            set(session.cancelMove())
        } else if let id = expanded {
            expanded = nil
            focus = .row(id)
        } else {
            dismiss()
        }
    }
}

/// Eine Zeile im Verwalter (72 pt): Platz · Symbol · Titel · „Liste · Poster“ und Herkunft · „neu“.
struct ManagedRowLine: View {
    let position: Int
    let title: String
    let info: ManagedRowInfo
    var isNew = false
    var moving = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.space.m) {
            Text("\(position)")
                .textRoleInRow(.rowDetail)
                .monospacedDigit()
                .frame(width: Theme.Layout.positionColumn, alignment: .trailing)
            IconTile(symbol: moving ? "arrow.up.arrow.down" : (info.kind == .list ? "list.bullet" : "square.grid.2x2"),
                     color: moving ? Theme.Tone.warn.color : Theme.CategoryTint.home.color)
            VStack(alignment: .leading, spacing: theme.space.xxs) {
                Text(title).textRoleInRow(.rowTitle).lineLimit(1)
                Text(DesignText.metaLine([info.detail, info.origin])).textRoleInRow(.rowDetail).lineLimit(1)
            }
            Spacer(minLength: theme.space.m)
            if isNew {
                ThemeBadge(kind: .status(.ok, onImage: false), text: "neu")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignText.accessibilityLabel(["Platz \(position)", title, info.detail, info.origin,
                                                           isNew ? "neu" : nil, moving ? "wird verschoben" : nil]))
    }
}

/// „An Position …“: Platz 1 … n, der aktuelle ist markiert und hat den Fokus. Menu schließt ohne Änderung.
private struct PositionPicker: View {
    let title: String
    let current: Int
    let positions: [Int]
    let done: (Int?) -> Void
    @FocusState private var focused: Int?
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.space.xs) {
                SettingsHeader(title: "An Position …", summary: "„\(title)“ steht auf Platz \(current).")
                    .padding(.bottom, theme.space.m)
                ForEach(positions, id: \.self) { p in
                    SettingsRow(symbol: p == current ? "checkmark" : "number", tint: Theme.CategoryTint.home.color,
                                title: "Platz \(p)", accessory: p == current ? .value("aktuell") : .none,
                                reserveDetailSpace: false) { done(p == current ? nil : p) }
                        .focused($focused, equals: p)
                }
            }
            .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, theme.space.edge)
            .padding(.vertical, theme.space.edgeVertical)
        }
        .settingsSurface()
        .defaultFocus($focused, current)
        .onExitCommand { done(nil) }
    }
}
