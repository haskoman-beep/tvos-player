import SwiftUI
import PlayerCore

/// Designsystem der App (Plan §4.1–4.4): Textrollen, Abstände, Radien, Flächen und Farben.
/// Views nehmen diese Tokens statt fester Zahlen.
/// Task 4.4: these constants are today's design and the source of `ThemeValues.standard`. New and moved views read
/// the runtime theme (`@Environment(\.theme)`); the static API stays as a forwarding layer until every view is moved.
enum Theme {

    // MARK: Textrollen (§4.2)

    /// Sechs Textrollen auf tvOS-Textstilen. Höchstens zwei Gewichte pro Bildschirm (regular und semibold/bold).
    enum TextRole: CaseIterable {
        /// largeTitle bold (76): Filmtitel ohne Logo, Profilwahl.
        case display
        /// title2 bold (48): „Einstellungen“, „Reihen & Collections“, Titel der Quellenliste.
        case pageTitle
        /// title3 semibold (38): Reihentitel auf Start, „Besetzung“, Kategoriekopf rechts.
        case sectionTitle
        /// body (29): Listenzeilen, Kartenunterschrift.
        case rowTitle
        /// headline (29, semibold): hervorgehobene Listenzeile, Statuskarte, Fokusanker.
        case rowTitleEmphasis
        /// subheadline (29), sekundär: Beschreibungen, Zeilenwerte, Meta-Zeile.
        case rowDetail
        /// caption bold (25): Plakettentext.
        case badge

        var font: Font {
            switch self {
            case .display: .largeTitle.bold()
            case .pageTitle: .title2.bold()
            case .sectionTitle: .title3.weight(.semibold)
            case .rowTitle: .body
            case .rowTitleEmphasis: .headline
            case .rowDetail: .subheadline
            case .badge: .caption.bold()
            }
        }

        /// Sekundäre Rollen tragen `fg.secondary` (bzw. Schwarz 60 % in fokussierten Zeilen).
        var isSecondary: Bool { self == .rowDetail }
    }

    // MARK: Abstände (§4.3)

    enum Space {
        /// 8: Plakette ↔ Plakette, Symbol ↔ Text.
        static let xs: CGFloat = 8
        /// 12: innerhalb einer Zeile.
        static let s: CGFloat = 12
        /// 20: Zeile ↔ Zeile in Karten, Karte ↔ Karte in einer Reihe.
        static let m: CGFloat = 20
        /// 32: Abschnitt ↔ Abschnitt.
        static let l: CGFloat = 32
        /// 48: Reihe ↔ Reihe auf Start, Spalte ↔ Spalte.
        static let xl: CGFloat = 48
        /// 80: tvOS-Sicherheitsrand waagrecht (Titel, Plaketten und Reihen starten auf einer Linie).
        static let edge: CGFloat = 80
        /// 60: tvOS-Sicherheitsrand senkrecht.
        static let edgeVertical: CGFloat = 60
    }

    /// Wave F-k R1: tvOS lays out every screen at 1920 × 1080 points (HD and 4K alike); window frame for
    /// „tile on screen“ (visible-tile prefetch).
    enum Screen {
        static let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    /// Feste Maße der Bedienseiten (§4.3, §4.6).
    enum Layout {
        /// Linke Spalte der Einstellungen bzw. des Browsers („Am Handy einrichten“ bricht sonst um).
        static let categoryColumnWidth: CGFloat = 560
        /// Größte Textbreite der rechten Spalte.
        static let contentMaxWidth: CGFloat = 1100
        /// Breite der Rückfrage-Karte (`SettingsConfirmationView`).
        static let confirmationWidth: CGFloat = 760
        /// Mindesthöhe einer `SettingsRow`.
        static let rowMinHeight: CGFloat = 80
        /// Symbolkachel einer Zeile (48×48) und Symbolgröße darin (32 pt).
        static let iconTile: CGFloat = 48
        static let iconSize: CGFloat = 32
        /// Breite der Akzentmarke an der aktiven Kategorie.
        static let accentMarkWidth: CGFloat = 6
        /// Mindesthöhe eines Eintrags der linken Spalte (`CategoryList`).
        static let categoryRowMinHeight: CGFloat = 72
        /// Kreis links in der `StatusCard` (Initiale bzw. Symbol).
        static let statusMark: CGFloat = 72
    }

    /// Welle F-f: Kachelmaße der Reihen. Grundmaße und Rechnung in PlayerCore (`PosterSize`); `scale` ist der Faktor
    /// der Postergröße (`Appearance.cardSize`, von `Strip` als `cardScale` gesetzt). Hero bleibt fest.
    enum Tile {
        static func size(_ kind: TileKind, _ scale: CGFloat) -> CGSize { PosterSize.tileSize(kind, scale: scale) }
        static func width(_ kind: TileKind, _ scale: CGFloat) -> CGFloat { size(kind, scale).width }
        static func height(_ kind: TileKind, _ scale: CGFloat) -> CGFloat { size(kind, scale).height }
        /// Platzhalterfläche einer ladenden Reihe (Weiß 8 %, wie die Logo-Kacheln).
        static let placeholder = Color.white.opacity(0.08)
        /// Welle F-g: Farbverläufe der Paket-Kacheln ohne Bild (Index aus `ReadyPackages.tileStyle`), gedeckte
        /// Eigenfarben, keine Markenfarben. Genau `ReadyPackages.toneCount` Einträge.
        static let packageGradients: [[Color]] = [
            [Color(red: 0.16, green: 0.22, blue: 0.42), Color(red: 0.08, green: 0.10, blue: 0.20)],
            [Color(red: 0.36, green: 0.16, blue: 0.30), Color(red: 0.16, green: 0.07, blue: 0.15)],
            [Color(red: 0.12, green: 0.32, blue: 0.32), Color(red: 0.05, green: 0.14, blue: 0.15)],
            [Color(red: 0.40, green: 0.22, blue: 0.12), Color(red: 0.18, green: 0.09, blue: 0.06)],
            [Color(red: 0.24, green: 0.18, blue: 0.42), Color(red: 0.10, green: 0.08, blue: 0.20)],
            [Color(red: 0.18, green: 0.30, blue: 0.16), Color(red: 0.07, green: 0.13, blue: 0.07)],
        ]
        static func packageGradient(_ tone: Int) -> LinearGradient {
            let c = packageGradients[((tone % packageGradients.count) + packageGradients.count) % packageGradients.count]
            return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Fokuseffekt der Bedienzeilen (`ThemeRowButtonStyle`).
    enum Focus {
        /// Anheben bei Fokus bzw. Eindrücken beim Klick.
        static let scale: CGFloat = 1.02
        /// Anheben von Aktionsknöpfen und Kacheln (`ThemeActionButtonStyle`, `ThemeTileButtonStyle`), Welle F-i.
        static let tileScale: CGFloat = 1.06
        /// Höchstes Wachsen hoher Zeilen je Seite beim Fokus (Quellenliste, `ThemeRowButtonStyle.maxFocusGrowth`):
        /// greift ab etwa 200 pt Zeilenhöhe, darunter bleibt `scale`.
        static let rowMaxGrowth: CGFloat = 2
        /// Senkrechter Rand um Kachelreihen (Besetzung, Ähnliche Titel): Wachsen beim Fokus (bis etwa 10 pt bei
        /// 300 pt Kachelhöhe) plus Schatten (Radius 14, y 8), damit nichts in Nachbarreihe oder Überschrift ragt.
        static let tileRowPadding: CGFloat = 44
        /// Wave F-k: lift of the system card style (`.buttonStyle(.card)`, poster rows). tvOS does not publish the
        /// factor; on device photos (build 187) a focused 360 pt poster grew by about 12 % including the tilt.
        /// Rounded up so the room is never too small.
        static let cardLiftScale: CGFloat = 1.15
        /// Wave F-k: how far shadow and tilt of a lifted card reach beyond its scaled edge.
        static let cardLiftShadow: CGFloat = 12
        /// Wave F-k: soft fade at the top edge of the home list under the hero info.
        static let listFade: CGFloat = 24
        /// Wave F-k: vertical padding of a `.card` tile row (lift + shadow, PlayerCore `FocusHeadroom`), at least
        /// `minimum` (rows with enough room keep it).
        /// Gap between tiles of one row so a lifted card never covers its neighbour (8 pt clearance, at least `minimum`).
        static func tileSpacing(width: CGFloat, minimum: CGFloat) -> CGFloat {
            FocusHeadroom.tileSpacing(width: width, scale: cardLiftScale, clearance: 8, minimum: minimum)
        }

        static func cardRowPadding(height: CGFloat, minimum: CGFloat) -> CGFloat {
            FocusHeadroom.rowPadding(height: height, scale: cardLiftScale, shadow: cardLiftShadow, minimum: minimum)
        }
        /// Lift of the system card style as a `FocusHeadroom.CardLift` (same as `FocusHeadroom.lift` with glow).
        static let systemLift = FocusHeadroom.CardLift(scale: cardLiftScale, reach: cardLiftShadow,
                                                       side: FocusHeadroom.sideClearance)
        /// Wave F-k: band above the home list's top edge in which a lifted card may draw (lift room + fade).
        /// `lift`: how the focused card grows (Task 5.1 `FocusHeadroom.lift` of the look; system card style by default).
        static func listEdgeBand(height: CGFloat, lift: FocusHeadroom.CardLift = Theme.Focus.systemLift) -> CGFloat {
            FocusHeadroom.edgeBand(height: height, scale: lift.scale, shadow: lift.reach, fade: listFade)
        }
        /// Wave F-m: room between the bottom of the home list and the screen edge for the lift of its tallest tile
        /// (PlayerCore `FocusHeadroom.listBottomRoom`); the list draws into it. `lift` as in `listEdgeBand`.
        static func listBottomRoom(height: CGFloat, lift: FocusHeadroom.CardLift = Theme.Focus.systemLift) -> CGFloat {
            FocusHeadroom.listBottomRoom(height: height, scale: lift.scale, shadow: lift.reach)
        }
        static let pressedScale: CGFloat = 0.98
        /// Schatten der fokussierten Zeile.
        static let shadowOpacity: Double = 0.35
        static let shadowRadius: CGFloat = 14
        static let shadowY: CGFloat = 8
        /// Dauer der Fokus-Übergänge (auch Ein- und Ausblenden der Zeilenbeschreibung).
        static let duration: Double = 0.15
        static let pressDuration: Double = 0.1
    }

    // MARK: Radien (§4.4)

    /// Drei Radien. `card` ist bewusst keine Zahl: Poster, Querformat und Kacheln nehmen den Systemstil
    /// `.buttonStyle(.card)` mit dessen eigenem Eckradius und Fokuseffekt.
    enum Radius {
        /// 8: Plaketten.
        static let badge: CGFloat = 8
        /// 20: Listenzeilen, Quellenzeilen, Statuskarte, Plus-Kachel.
        static let row: CGFloat = 20
        /// 24: Rückfrage-Karte über abgedunkeltem Grund (`SettingsConfirmationView`).
        static let overlayCard: CGFloat = 24
        // card: Systemradius von `.buttonStyle(.card)`; Karten setzen keinen eigenen Radius.
    }

    // MARK: Flächen und Farben (§4.4)

    enum Palette {
        /// `bg.base`: App-Hintergrund.
        static let base = Color.black
        /// `bg.surface`: dunkler, ruhiger Grund der Bedienseiten (Einstellungen, Verwalter, Quellen).
        /// Weiß 7 % über Schwarz, deckend gemischt, damit kein Bildgrund oder Glas durchscheint (Nutzerentscheidung 3).
        static let surface = Color(white: 0.07)
        /// Abdunklung hinter einer Rückfrage (Schwarz 75 %), die Seite darunter bleibt erkennbar.
        static let scrim = Color.black.opacity(0.75)
        /// Karte einer Rückfrage über `scrim`: Weiß 12 %, deckend gemischt.
        static let overlayCard = Color(white: 0.12)
        /// `bg.row`: ruhende Zeilen (Weiß 10 %).
        static let row = Color.white.opacity(0.10)
        /// Fokussierte Zeile: Systemweiß wie beim tvOS-Fokus.
        static let rowFocused = Color.white
        /// `fg.primary`.
        static let primary = Color.white
        /// `fg.secondary`: Weiß 65 % (nicht `.secondary`, das auf Glas unter 3:1 fällt).
        static let secondary = Color.white.opacity(0.65)
        /// Text auf fokussierter (weißer) Zeile.
        static let primaryOnFocus = Color.black
        /// Untertitel und Werte auf fokussierter Zeile: Schwarz 60 % (A3).
        static let secondaryOnFocus = Color.black.opacity(0.6)
        /// Neutrale Plakettenfläche (Technik): Weiß 18 %.
        static let badgeFill = Color.white.opacity(0.18)
        /// Technik-Plakette auf fokussierter (weißer) Zeile: Schwarz 10 %, Schrift `primaryOnFocus`.
        static let badgeFillOnFocus = Color.black.opacity(0.10)
        /// Streifen unter dem Posterbild für Plaketten „Unten“ (Schwarz 55 %).
        static let posterBand = Color.black.opacity(0.55)
        /// Status-Kapsel auf Bildern: Schwarz 65 %.
        static let badgeOnImage = Color.black.opacity(0.65)

        /// Vordergrund je nach Fokus der Zeile.
        static func foreground(secondary: Bool, focused: Bool) -> Color {
            switch (secondary, focused) {
            case (false, false): primary
            case (true, false): self.secondary
            case (false, true): primaryOnFocus
            case (true, true): secondaryOnFocus
            }
        }
    }

    /// Zustandsfarben. Rot, Grün und Orange tragen nur Zustände, nie Dekoration; Farbe ist nie der einzige
    /// Träger (A5), deshalb hat jeder Zustand auch ein Symbol und einen Namen für VoiceOver.
    /// Token `state.*`. Name `Tone` statt `State`, damit es nicht mit SwiftUIs `@State` kollidiert.
    enum Tone: CaseIterable {
        /// „sofort“, „Verbunden“.
        case ok
        /// Fehlender Schlüssel, Zeitüberschreitung.
        case warn
        /// Fehler, destruktive Knöpfe.
        case error

        var color: Color {
            switch self {
            case .ok: .green          // Systemgrün; das alte (0.16, 0.56, 0.30) ist für Text zu dunkel
            case .warn: .orange
            case .error: .red
            }
        }

        /// Textfarbe des Zustands auf dunklen Flächen (bg.row, Status-Kapsel): mindestens 4,5:1.
        /// Systemrot liegt dort bei rund 4,2:1, deshalb ein helleres Rot (≈ 5,3:1); `color` bleibt für Flächen
        /// und destruktive Knöpfe.
        var textColor: Color {
            switch self {
            case .ok, .warn: color
            case .error: Color(red: 1, green: 0.45, blue: 0.42)
            }
        }

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .warn: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var accessibilityName: String {
            switch self {
            case .ok: "In Ordnung"
            case .warn: "Warnung"
            case .error: "Fehler"
            }
        }
    }

    /// Kachelfarben der Kategoriesymbole (§4.6). Task 4.5 (D-19, `07` §3.1): the nine colours give way to one
    /// neutral tile (`bg.raised`, symbol `fg.primary`); only the active category carries the accent mark.
    /// The cases stay so call sites keep their meaning.
    enum CategoryTint: CaseIterable {
        case profile, addons, sources, home, appearance, playback, audio, picture, system

        /// Marks the neutral tile. `IconTile` and `StatusCard` draw it from the runtime theme (`color.raised` /
        /// `color.primary`); other views get today's `bg.raised`. Task 4.5 review M4: a value of its own (99.9 %
        /// opaque, looks like `Palette.overlayCard`), so an explicit `Palette.overlayCard` tint is a normal grey tile
        /// again. Test with `isNeutral(_:)`, never with `==` at the call site; a derived colour (`.opacity(…)`) is
        /// not neutral.
        static let neutral = Palette.overlayCard.opacity(0.999)

        /// Whether `color` is the neutral category tint (the one place that compares colours).
        static func isNeutral(_ color: Color) -> Bool { color == neutral }

        var color: Color { Self.neutral }
    }

    /// Akzent: nur „aktiv/gewählt“, Hauptknopf und Akzentmarke, nie das einzige Fokuszeichen (A6).
    /// Die Farbe kommt aus der Profilwahl über `.tint` (RootView); hier nur die Regel für die Marke:
    /// auf fokussierter (weißer) Zeile wird sie dunkel gezeichnet, sonst wäre ein weißer Akzent unsichtbar.
    static func accentMark(focused: Bool) -> AnyShapeStyle {
        focused ? AnyShapeStyle(Palette.primaryOnFocus) : AnyShapeStyle(TintShapeStyle())
    }
}

// MARK: - Modifikatoren

extension View {
    /// Schrift einer Textrolle; sekundäre Rollen bekommen `fg.secondary`.
    /// `tracking` (points) is added to the role's own tracking; an outer `.tracking` no longer works on a role.
    func textRole(_ role: Theme.TextRole, tracking: CGFloat = 0) -> some View {
        modifier(TextRoleModifier(role: role, focusAware: false, extraTracking: tracking))
    }

    /// Wie `textRole`, aber mit Fokusfarben, wenn der Text im Label eines fokussierten Knopfs liegt
    /// (Schwarz bzw. Schwarz 60 % auf der weißen Fokusfläche).
    func textRoleInRow(_ role: Theme.TextRole, tracking: CGFloat = 0) -> some View {
        modifier(TextRoleModifier(role: role, focusAware: true, extraTracking: tracking))
    }

    /// Dunkler, ruhiger Grund für Bedienseiten (Einstellungen, Verwalter, Quellen) statt heller Glasfläche.
    /// (`scrollContentBackground` gibt es auf tvOS nicht; tvOS-Listen zeichnen ohnehin keinen eigenen Grund.)
    func settingsSurface() -> some View {
        modifier(SettingsSurfaceModifier())
    }
}

/// Task 4.4: reads `bg.surface` from the runtime theme (`standard` = `Theme.Palette.surface`).
private struct SettingsSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.color.surface.ignoresSafeArea())
    }
}

private struct TextRoleModifier: ViewModifier {
    let role: Theme.TextRole
    let focusAware: Bool
    var extraTracking: CGFloat = 0
    @Environment(\.isFocused) private var focused
    /// Task 4.4: fonts and colors from the runtime theme (`standard` = today's `role.font` and `Theme.Palette`).
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.type.font(role))
            // The modifier nearest the Text wins, so an outer `.tracking` on a role would be overridden by this
            // one: pass extra spacing through `textRole(_:tracking:)` instead.
            .tracking(theme.type.tracking(role) + extraTracking)
            .foregroundStyle(focusAware
                             ? theme.color.foreground(secondary: role.isSecondary, focused: focused)
                             : (role.isSecondary ? theme.color.secondary : theme.color.primary))
    }
}

/// Knopfstil der Bedienzeilen: ruhend `bg.row`, fokussiert weiß mit leichtem Anheben, Radius `radius.row`.
/// Die Texte im Label wählen ihre Farbe selbst über `textRoleInRow` (liest denselben Fokus).
/// `maxWidth` begrenzt die ganze Fläche (Standard: Textbreite 1100), damit der Wert rechts am Flächenende steht.
/// Wer den Stil übernimmt, richtet das Label selbst links aus (`VStack(alignment: .leading)`, mehrzeilige Texte
/// `.multilineTextAlignment(.leading)`): der Stil legt nur das Label als Ganzes links in die Fläche, nicht dessen Inhalt.
struct ThemeRowButtonStyle: ButtonStyle {
    var minHeight: CGFloat = Theme.Layout.rowMinHeight
    var maxWidth: CGFloat = Theme.Layout.contentMaxWidth
    /// Höchstes Wachsen beim Fokus je Seite (Punkte); nil = immer `Theme.Focus.scale`. Für hohe Zeilen, die sonst
    /// beim Anheben die Nachbarzeile überdecken (Quellenliste, Welle F-i).
    var maxFocusGrowth: CGFloat? = nil
    /// Fläche in Ruhe (Standard `bg.row`); Listen auf dunklem Grund (Spur-Panel, Welle F-h2) nehmen `.clear`.
    var restFill: Color = Theme.Palette.row
    /// Innenrand oben/unten (Standard `Space.s`); einzeilige Listenzeilen nehmen `Space.xs`.
    var verticalPadding: CGFloat = Theme.Space.s

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, minHeight: minHeight, maxWidth: maxWidth, maxFocusGrowth: maxFocusGrowth,
                restFill: restFill, verticalPadding: verticalPadding)
    }

    private struct RowBody: View {
        let configuration: Configuration
        let minHeight: CGFloat
        let maxWidth: CGFloat
        let maxFocusGrowth: CGFloat?
        let restFill: Color
        let verticalPadding: CGFloat
        @Environment(\.isFocused) private var focused
        /// Task 4.4: surfaces, focus, shadow and timing from the runtime theme (`standard` = the `Theme` constants).
        @Environment(\.theme) private var theme
        @State private var height: CGFloat = 0

        /// Fokus-Anheben, bei `maxFocusGrowth` so begrenzt, dass die Zeile oben und unten höchstens so viel wächst.
        private var focusScale: CGFloat {
            guard let g = maxFocusGrowth, height > 0 else { return theme.focus.scale }
            return min(theme.focus.scale, 1 + 2 * g / height)
        }

        var body: some View {
            let shadow = theme.elevation.focus
            configuration.label
                .padding(.horizontal, theme.space.m)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: maxWidth, minHeight: minHeight, alignment: .leading)
                .background(focused ? theme.color.rowFocused : restFill,
                            in: RoundedRectangle(cornerRadius: theme.radius.row, style: .continuous))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if maxFocusGrowth != nil { height = $0 } }
                .scaleEffect(configuration.isPressed ? theme.focus.pressedScale : (focused ? focusScale : 1))
                .shadow(color: .black.opacity(focused ? shadow.opacity : 0),
                        radius: focused ? shadow.radius : 0, y: focused ? shadow.y : 0)
                .animation(theme.motion.focusAnimation, value: focused)
                .animation(theme.motion.pressAnimation, value: configuration.isPressed)
        }
    }
}

/// Welle F-i: Aktionsknopf (Detailseite: Sofort abspielen, Abspielen, Trailer, Staffeln; Startseite: Hero-Knöpfe,
/// Reihen-Verwalter). Ersetzt den Systemknopf, der die App-Akzentfarbe bzw. das System-Blau ins Label zog
/// (`.tint(Color?.none)` half nicht mehr): Farben nur aus den Tokens, ruhend Weiß auf `bg.row`, im Fokus Schwarz
/// auf Weiß. `selected` (z. B. gewählte Staffel): Fläche `badgeFill` statt `bg.row`.
struct ThemeActionButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration, selected: selected)
    }

    private struct ActionBody: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Theme.Palette.primaryOnFocus : Theme.Palette.primary)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .frame(minHeight: Theme.Layout.rowMinHeight)
                .background(focused ? Theme.Palette.rowFocused : (selected ? Theme.Palette.badgeFill : Theme.Palette.row),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .scaleEffect(configuration.isPressed ? Theme.Focus.pressedScale : (focused ? Theme.Focus.tileScale : 1))
                .shadow(color: .black.opacity(focused ? Theme.Focus.shadowOpacity : 0),
                        radius: focused ? Theme.Focus.shadowRadius : 0, y: focused ? Theme.Focus.shadowY : 0)
                .animation(.easeOut(duration: Theme.Focus.duration), value: focused)
                .animation(.easeOut(duration: Theme.Focus.pressDuration), value: configuration.isPressed)
        }
    }
}

/// Welle F-i: Kachel einer Reihe (Besetzung) mit festem Fokus-Anheben `Focus.tileScale` statt `.card`, damit
/// Abstand (`LazyHStack`-spacing ≥ Wachsen) und Rand (`Focus.tileRowPadding`) sicher reichen.
struct ThemeTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TileBody(configuration: configuration) }

    private struct TileBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Theme.Palette.primaryOnFocus : Theme.Palette.primary)
                .padding(Theme.Space.s)
                .background(focused ? Theme.Palette.rowFocused : Theme.Palette.row,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .scaleEffect(configuration.isPressed ? Theme.Focus.pressedScale : (focused ? Theme.Focus.tileScale : 1))
                .shadow(color: .black.opacity(focused ? Theme.Focus.shadowOpacity : 0),
                        radius: focused ? Theme.Focus.shadowRadius : 0, y: focused ? Theme.Focus.shadowY : 0)
                .animation(.easeOut(duration: Theme.Focus.duration), value: focused)
                .animation(.easeOut(duration: Theme.Focus.pressDuration), value: configuration.isPressed)
        }
    }
}

/// Symbolkachel 48×48 mit gefülltem Symbol (32 pt).
/// Task 4.5 (D-19): `Theme.CategoryTint.neutral` draws the neutral tile from the runtime theme
/// (`color.raised`, symbol `color.primary`); any other colour keeps the coloured tile with the white symbol.
struct IconTile: View {
    let symbol: String
    let color: Color
    @Environment(\.theme) private var theme

    private var isNeutral: Bool { Theme.CategoryTint.isNeutral(color) }

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(.fill)
            .font(.system(size: Theme.Layout.iconSize, weight: .semibold))
            .foregroundStyle(isNeutral ? theme.color.primary : .white)
            .frame(width: Theme.Layout.iconTile, height: Theme.Layout.iconTile)
            .background(isNeutral ? theme.color.raised : color,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("Tokens") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Display").textRole(.display)
            Text("Seitentitel").textRole(.pageTitle)
            Text("Abschnitt").textRole(.sectionTitle)
            Text("Zeilentitel").textRole(.rowTitle)
            Text(DesignText.metaLine(["2018", "97 min", "FSK 0", "Animation"])).textRole(.rowDetail)
            Text("PLAKETTE").textRole(.badge)
            HStack(spacing: Theme.Space.xs) {
                ForEach(Theme.CategoryTint.allCases, id: \.self) { IconTile(symbol: "gearshape", color: $0.color) }
            }
            HStack(spacing: Theme.Space.m) {
                ForEach(Theme.Tone.allCases, id: \.self) { s in
                    Label(s.accessibilityName, systemImage: s.symbol).foregroundStyle(s.color)
                }
            }
        }
        .padding(.horizontal, Theme.Space.edge)
        .padding(.vertical, Theme.Space.edgeVertical)
    }
    .settingsSurface()
}
