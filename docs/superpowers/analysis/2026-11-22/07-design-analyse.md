# 07 · Design-Analyse, Design-System und Konfigurator-Schema

Stand: Branch `integ`, Commit `b2188a2` (Build 249). Der Ist-Zustand ist vollständig aus dem Code erhoben; sichtbare
Wirkung (Kontrast, HDR, Fokus-Gefühl) ist **abgeleitet** und steht unter „Am Gerät prüfen“.

Methodik: Skills `design:design-critique`, `design:design-system`, `frontend-design:frontend-design`.
Abkürzungen in den Ortsangaben: `V/` = `App/Sources/Views/`, `PC/` = `Packages/PlayerCore/Sources/PlayerCore/`.

Aufbau dieses Dokuments:

1. Kurzfassung
2. Ist-Zustand je Bereich (Bewertung)
3. Design-System als Vorschlag
4. tvOS-Regeln
5. Konfigurator und JSON-Schema
6. Anhang: vollständiges Inventar, Anpassbarkeit heute, alle 28 Befunde, Komponentenliste

Der Konfigurator liegt unter [`docs/design/konfigurator/index.html`](../../../design/konfigurator/index.html).

## 1. Kurzfassung

- **Die App hat bereits ein ordentliches Token-System** (`V/Design/Theme.swift`): sieben Textrollen, eine Abstandsskala,
  drei Radien, eine Palette, drei Knopfstile, einen Plakettentyp. Einstellungen, Reihen-Verwalter und Quellenliste
  nutzen es durchgehend. Das ist eine gute Grundlage und kein Neuanfang.
- **Es gibt zwei Designwelten.** Der Player, die Personenseite, die Suche, die Profilwahl und die QR-Seiten stehen noch
  außerhalb: 135 Farb-, 173 Größen-, 15 Radius-Literale, 39 Dauer-Angaben und 10 Schatten liegen außerhalb von
  `Theme.swift` (D-3, D-17).
- **Was heute „billig“ wirkt**, sind fünf Dinge: keine sichtbare Typo-Hierarchie im Lesebereich (D-4), fünf
  verschiedene Fokus-Darstellungen (D-6), Player-Karten nur auf Glas ohne Abdunklung (D-2), Unicode-Zeichen und Emoji
  statt Symbolen (D-10) und eine Detailseite, die ihr Bild unter einer gleichmäßigen 55-%-Abdunklung versteckt (D-7).
- **Für „viele Optionen mit Vorlagen“ fehlt die Technik:** `Theme` ist statisch, es gibt keine Vorlagen, und ein
  unbekannter Aussehens-Wert macht heute die ganze Profildatei unlesbar (D-1). Die Architektur dafür steht in
  [04 §8](04-system-design.md).

## 2. Ist-Zustand je Bereich

### 2.1 Startseite und Hero

| Aspekt | Ist (Beleg im Anhang 1.3) | Bewertung |
|---|---|---|
| Farben | Schwarz, zwei harte Verläufe über dem Hero-Bild (links 85 %, unten 95 %) | funktioniert; die Verläufe sind Literale und für jeden Hintergrundton gleich |
| Typografie | Titel `display`, Beschreibung `.callout` (31 pt), Reihentitel `sectionTitle` (38 pt semibold) | die Beschreibung ist größer als der Zeilentitel der App (29 pt), die Reihentitel sind so kräftig wie Seitentitel (D-4) |
| Abstände | Reihe ↔ Reihe 48, Karte ↔ Karte 20 × Faktor, Rand 80 | ruhig und konsistent; die Ränder der Liste oben und unten sind Sonderwerte |
| Ecken | Systemradius der `.card` | einheitlich, aber nicht wählbar |
| Schatten | Info-Block mit Schatten auf dem ganzen Block; Kacheltitel mit `shadow(radius: 4/6/8)` | Schatten ersetzen fehlende Verläufe; wirkt unsauber auf hellen Bildern (D-8, D-9) |
| Fokus | System-`.card` (ca. 1,15 mit Neigung und Glanz) | der stärkste Fokus-Effekt der App neben dem schwächsten (Zeilen 1,02) (D-6) |
| Bewegung | Hintergrund 0,6 s, Info 0,3 s, Aufklappen 0,25 s, Ruhezeit 350 ms | plausibel, aber vier Dauern ohne gemeinsame Skala (D-13) |
| Inkonsistenzen | Logo-Kachel nutzt ein Literal statt `Tile.placeholder`; Kalender-Kachel hat feste Maße statt Postergröße (D-16, D-17) | |

**Was billig wirkt:** Titel direkt auf dem Bild ohne Verlauf (Querformat- und Collection-Kacheln, D-8); der
„Gesehen“-Haken und der Fortschrittsbalken sind eigene Zeichnungen statt eines gemeinsamen Bausteins (D-23, D-24).

### 2.2 Detailseite, Person, Suche

| Aspekt | Ist (Anhang 1.4) | Bewertung |
|---|---|---|
| Farben | Hintergrundbild unter gleichmäßig Schwarz 55 %, kein Verlauf | das Bild verliert seine Wirkung, der Text gewinnt trotzdem zu wenig Kontrast (D-7) |
| Typografie | Titel `display`, Beschreibung `.callout`, Besetzung `.caption`/`.caption2` (25 und 23 pt) | Text unter 29 pt an mehreren Stellen (D-5) |
| Abstände | Infoblock mit `Space.l`; Suche mit 60/40; Person mit 80 rundum | drei Rand-Regeln für drei Seiten (D-15) |
| Ecken | Poster 12, Text-Fokus 12, Folgenbild ohne Radius | außerhalb der drei Tokens (D-12) |
| Fokus | Knöpfe weiß 1,06; Text-Fokus Weiß 14 %; Besetzung 1,06; „Über“-Karte mit `.card` und leerer Aktion | vier Fokus-Sprachen auf einer Seite (D-6) |
| Knöpfe | alle im selben Stil, „▶“ als Unicode-Zeichen | keine Hierarchie zwischen „Abspielen“ und dem Rest (D-22, D-10) |
| Quellenzeile | Addon-Text bis 4 Zeilen plus Plaketten plus Status | überladen (D-20) |

**Was billig wirkt:** Die Personenseite, die Suche und die Profilwahl sind im Rohzustand des ersten Entwurfs
(D-3, D-25). Vier Markenfarben für Bewertungen stehen als RGB-Literale in der View.

### 2.3 Player-Oberfläche

| Aspekt | Ist (Anhang 1.5) | Bewertung |
|---|---|---|
| Flächen | Vier Karten (Nächste Folge, Spul-Vorschau, Karte nach dem Film, Szenen-Hinweis) nur auf `.ultraThinMaterial`; Spur-Leiste und Seitenpanel mit Material plus 75 % Abdunklung | auf hellen und HDR-Bildern sind die vier Karten nicht sicher lesbar (D-2) |
| Typografie | viel Text in `.caption`/`.footnote`; Bedienhinweise mit „◀▶ … ⏯“ | unter der Lesegröße für 3 m Abstand (D-5), Zeichen statt Symbole (D-10) |
| Plaketten | drei eigene Zeichnungen neben `ThemeBadge` | widerspricht der eigenen Regel „ein Plakettentyp“ (D-11) |
| Ränder | 60, 80/70, 80/60, oben 50 | vier Varianten (D-15) |
| Meldungen | Fehler und Netzstatus als farbige Signalflächen | zu laut für ein ruhiges Bild (D-18) |
| Bewegung | acht verschiedene Dauern in `PlayerScreen.swift` | keine Skala (D-13) |

**Was billig wirkt:** Der Player ist der Bereich mit den meisten Literalen (50 Farbstellen in den Player-Dateien) und
zugleich der, in dem man die meiste Zeit verbringt.

### 2.4 Navigation und Einstellungen

| Aspekt | Ist (Anhang 1.6) | Bewertung |
|---|---|---|
| Navigation | System-`TabView`, wahlweise `.sidebarAdaptable`; Uhr als Overlay | richtig entschieden: Systemfokus, wenig eigener Code |
| Einstellungen | linke Spalte 560, Inhalt max. 1100, Zeilen 80 hoch, weiße Fokuszeile 1,02 | der am besten durchgearbeitete Teil, vollständig auf Tokens |
| Farben | neun bunte Kategoriefarben | wirkt wie die Systemeinstellungen von iOS, nicht wie eine Kino-Oberfläche (D-19) |
| Akzent | einstellbar, aber auf Start, Detail, Person und Quellen ausdrücklich abgeschaltet | die Option hat kaum sichtbare Wirkung (D-14) |
| Anpassbarkeit | rund 30 Optionen in vier Strukturen, keine Vorlagen | (D-28) |

## 3. Design-System als Vorschlag

Leitidee für die Vorlage „Edel“: **Das Bild führt, die Oberfläche tritt zurück.** Große Bilder mit sauberen Verläufen,
wenige Schriftgrößen mit klarem Abstand zueinander, ein einziger Fokus-Stil, eine warme Akzentfarbe nur für
„gewählt“ und für den Hauptknopf. Alle Werte unten sind der **Vorschlag für die Vorlage „Edel“**; die anderen Vorlagen
ändern nur die als wählbar markierten Tokens. Die endgültigen Werte kommen aus dem Export des Konfigurators.

### 3.1 Farben

| Token | Wert (Edel) | Verwendung | wählbar über |
|---|---|---|---|
| `bg.base` | `#0B0C0E` (Graphit) | App-Hintergrund | `global.background`: Schwarz `#000000`, Graphit, Tinte `#070B14`, Warm `#0E0B08` |
| `bg.surface` | `#17191D` | Bedienseiten, Panels | folgt `background` |
| `bg.raised` | `#22252B` | Karten über einer Fläche, Dialoge | folgt `background` |
| `bg.row` | Weiß 8 % | ruhende Zeile | – |
| `bg.scrim` | `bg.base` 78 % | Abdunklung hinter Dialogen und **unter jeder Karte über Video** | – |
| `fg.primary` | `#F4F3EF` (leicht warmes Weiß) | Text | – |
| `fg.secondary` | Weiß 68 % | Meta-Zeilen, Werte | – |
| `fg.tertiary` | Weiß 45 % | nur für nicht notwendige Angaben, nie unter 29 pt | – |
| `fg.onFocus` / `fg.onFocus.secondary` | `#111111` / Schwarz 62 % | Text auf der weißen Fokusfläche | – |
| `accent` | `#D4B87A` (Champagner) | „gewählt“, Hauptknopf, Akzentmarke | `global.accent`: Champagner, Weiß, Eisblau, Blau, Rot, Koralle, Salbei, Violett |
| `accent.on` | `#17140C` | Text auf Akzent | folgt `accent` |
| `focus.fill` | `#FFFFFF` | Fokusfläche von Zeilen und Knöpfen | – (Fokus bleibt weiß, damit er nie von der Akzentfarbe abhängt) |
| `state.ok` / `warn` / `error` | Systemgrün / Systemorange / `#FF736B` | nur Zustände, immer mit Symbol | – |
| `image.gradient.bottom` | `bg.base` 0 % → 75 % → 100 % (55 % → 78 % → 100 % der Höhe) | Text auf Bildern unten | – |
| `image.gradient.leading` | `bg.base` 92 % → 55 % → 0 % (0 → 38 % → 70 % der Breite) | Hero und Detailseite links | – |

Regeln: Verläufe laufen immer in den Hintergrundton aus, nie in reines Schwarz, sonst entsteht bei getönten
Hintergründen eine sichtbare Kante. Die neun Kategoriefarben der Einstellungen entfallen zugunsten einer neutralen
Symbolkachel (`bg.raised`, Symbol `fg.primary`); nur die aktive Kategorie trägt die Akzentmarke.

### 3.2 Typografie (SF Pro, 1920 × 1080 Punkte, 3 m Abstand)

Sieben Rollen bleiben, bekommen aber echte Abstände zueinander, feste Laufweiten und Zeilenhöhen. Kleinste Größe für
Text, den man lesen können muss: 29 pt. Plaketten dürfen 25 pt haben, weil sie kurz und fett sind.

| Rolle | Größe | Gewicht (neutral / editorial / technisch) | Laufweite | Zeilenhöhe | Einsatz |
|---|---|---|---|---|---|
| `display` | 76 | 700 / 300 / 800 | −1 % / −2,5 % / 0 | 1,02 | Filmtitel ohne Logo |
| `pageTitle` | 48 | 700 / 500 / 700 | 0 | 1,1 | Seitentitel |
| `sectionTitle` | 34 (heute 38) | 600 / 500 / 700 | 0 / +0,5 % / +1 % | 1,15 | Reihentitel, Abschnittsköpfe |
| `sectionLabel` (neu) | 27 | 500 | +2 % | 1,2 | dezente Reihentitel (`home.rowTitle = dezent`) |
| `body` | 29 | 400 | 0 | 1,32 | Beschreibung, Listenzeile |
| `bodyEmphasis` | 29 | 600 | 0 | 1,32 | hervorgehobene Zeile, Knopf |
| `meta` | 26 | 500 | +1 % / +3 % / +5 % | 1,25 | Jahr, Laufzeit, Freigabe; nur einzeilig |
| `badge` | 23 bis 25 | 700 | +4 % | 1 | Plaketten |

`global.typeScale` multipliziert alle Größen mit 0,9 / 1,0 / 1,12. `global.typeCharacter` wählt die Spalte bei
Gewicht und Laufweite. Entfällt: `.callout` (31 pt) als Fließtext, `.caption2` und `.footnote` für Lesetext.
Höchstens zwei Gewichte je Bildschirm.

### 3.3 Abstände, Raster, Radien

| Token | Wert | Hinweis |
|---|---|---|
| `space.xxs` | 4 | neu, ersetzt `Space.xs / 2` und die Literale 2 und 4 (D-27) |
| `space.xs` / `s` / `m` / `l` / `xl` | 8 / 12 / 20 / 32 / 48 | wie heute |
| `space.xxl` | 64 | neu: Reihe ↔ Reihe bei „luftig“ |
| `edge.h` / `edge.v` | 80 / 60 | sichere Ränder; **eine** Regel für alle Seiten und den Player (D-15) |
| `home.rowSpacing` | eng 16/36 · normal 24/48 · luftig 32/64 (Karte/Reihe) | wählbar |
| `radius.badge` | 7 | |
| `radius.card` | 0 / 8 / 14 / 26 (`home.corners`: eckig, leicht, weich, rund) | wählbar; gilt für Karten, Vorschaubilder, Folgenbilder |
| `radius.row` | `radius.card` + 4 | Zeilen, Knöpfe |
| `radius.panel` | `radius.card` + 8 | Panels, Dialoge |

Wichtig für die Umsetzung: Ein eigener Radius ist nur möglich, wenn Karten **nicht** mehr den Systemstil
`.buttonStyle(.card)` verwenden. Siehe 4.2.

### 3.4 Elevation (Schatten)

Drei Stufen statt zehn Einzelwerten (D-9):

| Token | Wert | Einsatz |
|---|---|---|
| `elevation.0` | kein Schatten | alles Ruhende. Text auf Bildern bekommt einen Verlauf, keinen Schatten. |
| `elevation.focus` | Schwarz 45 %, Radius 20, y 18 (`weich`) bzw. Schwarz 75 %, Radius 35, y 34 (`tief`) | fokussierte Karte (`home.focusShadow`) |
| `elevation.overlay` | Schwarz 50 %, Radius 30, y 12 | Dialoge und Karten über Video |

### 3.5 Fokus-Zustände

Ein Fokus-Stil für die ganze App, in zwei Ausprägungen:

| Element | Ruhend | Fokussiert |
|---|---|---|
| Zeile, Knopf | `bg.row`, Text `fg.primary` | `focus.fill`, Text `fg.onFocus`, Skalierung 1,02, `elevation.focus` weich |
| Hauptknopf („Abspielen“) | `accent`, Text `accent.on` | `focus.fill`, sonst wie Knopf |
| Karte (Poster, Querformat, Kachel) | Bild, `radius.card` | Skalierung nach `home.focusScale` (1,0 / 1,05 / 1,12), Rahmen nach `home.focusBorder` (4 pt, 4 pt Abstand, Weiß oder Akzent), Schatten nach `home.focusShadow`, Glanz nach `home.focusGlow` |
| Text-Fokus (Beschreibung) | – | wie Zeile, aber ohne Skalierung |

Regel: Mindestens einer von Skalierung, Rahmen oder Schatten ist an. Der Konfigurator erlaubt „alles aus“ nicht
sinnvoll; die App erzwingt dann einen weißen Rahmen. Farbe ist nie das einzige Fokus-Zeichen.

### 3.6 Bewegung

| Token | aus | dezent (Edel) | standard | Einsatz |
|---|---|---|---|---|
| `motion.focus` | 0 | 0,18 s | 0,22 s | Fokus-Wechsel, Kurve `cubic-bezier(0.2, 0.7, 0.2, 1)` |
| `motion.fade` | 0 | 0,24 s | 0,38 s | Einblenden von Text, Plaketten, Panels, Kurve `easeOut` |
| `motion.backdrop` | 0 | 0,5 s | 0,7 s | Hintergrundwechsel, Kurve `easeInOut` |
| `motion.expand` | 0 | 0,25 s | 0,3 s | Poster aufklappen |
| `rest.backdrop` / `rest.expand` / `rest.prefetch` | 350 / 500 / 700 ms | | | Ruhezeiten, gestaffelt statt gleichzeitig ([04 §6.5](04-system-design.md)) |

„Bewegung reduzieren“ des Systems setzt alles auf „aus“ und schaltet Fokus-Videos und das Aufklappen ab (Q-28).
Keine Federungen, keine Überschwinger, nichts läuft ohne Anlass.

### 3.7 Komponenten, die das System braucht

| Baustein | ersetzt heute | Varianten |
|---|---|---|
| `ThemeCard` | `.buttonStyle(.card)` an Postern und Kacheln | Poster, Querformat, Logo, Collection; mit Titel immer / bei Fokus / nie |
| `ThemeButton` | `ThemeActionButtonStyle` | primär (Akzent), sekundär (Fläche), still (nur Text) |
| `ThemeBadge` | drei eigene Plaketten im Player | Umriss, gefüllt, Text, Logos |
| `ThemeProgressBar` | vier Fortschrittsanzeigen (D-23) | Kachel, Zeile, Player |
| `WatchedMark` | vier „Gesehen“-Zeichen (D-24) | auf Bild, in Zeile |
| `OverlayCard` | vier Player-Karten auf Glas | mit `bg.scrim`, `radius.panel`, `elevation.overlay` |
| `ImageScrim` | einzelne Verläufe und Schatten | unten, links, unten + links |
| `RatingRow` | Bewertungszeile mit RGB-Literalen | Symbol + Zahl, Textzeile, Kacheln |
| `HeroLayout` | `HomeHero` | Vollbild, Banner, Karussell |
| `DetailLayout` | `DetailView`-Kopf | links, zentriert, Kino-Vollbild |

## 4. tvOS-Regeln

### 4.1 Sichere Ränder, Größen, Lesbarkeit

- Inhalte halten 80 pt waagrecht und 60 pt senkrecht Abstand zum Bildrand. Nur Hintergrundbilder und Verläufe
  ignorieren die sichere Fläche. Heute hält die Startseite das ein; Suche, Person und Player nicht einheitlich (D-15).
- Lesetext mindestens 29 pt, Meta-Zeilen 26 pt, Plaketten 23 bis 25 pt fett. Heute gibt es Text mit 23 pt und kleiner
  im Player und bei der Besetzung (D-5).
- Kontrast: Text auf Bildern nur über einem Verlauf oder einer Abdunklung, Zielwert 4,5:1 für Lesetext, 3:1 für
  große Titel. `.secondary` des Systems fällt auf Glas unter 3:1 und wird nicht verwendet (Q-29).

### 4.2 Fokus-Engine

- **Systemstil gegen eigene Karte.** `.buttonStyle(.card)` liefert Neigung, Glanz und Parallax, legt aber Skalierung,
  Schatten und Radius selbst fest. Die Optionen Ecken, Skalierung, Rahmen und Schatten verlangen eine eigene Karte
  (`ThemeCard`). Daraus folgt eine klare Regel für die App: Mit `focusGlow = an` wird der Systemstil benutzt und die
  drei anderen Fokus-Optionen sind ausgegraut; mit `focusGlow = aus` gilt die eigene Karte. Der Konfigurator markiert
  „Glanz“ deshalb als aufwendig.
- **Die fokussierte View darf ihre Identität nicht ändern.** Jede Option, die das Layout umschaltet, wirkt erst beim
  nächsten Aufbau der Seite. Aufklappen, Hintergrund nach Fokus und Kartentitel bei Fokus ändern nur Maße und
  Deckkraft, nie den View-Baum.
- **Aufklappende Poster** bleiben die riskanteste Option (9 Commits in der Historie). Die Vorlage „Edel“ schaltet sie
  aus. Wer sie einschaltet, bekommt die gestaffelte Ruhezeit von 500 ms.
- **Karussell-Hero** braucht eine eigene Fokus-Führung (links/rechts wechselt die Folie, hoch/runter verlässt den
  Hero). Das ist der teuerste Hero-Stil und wird erst gebaut, wenn der Export ihn verlangt.
- **Kachel-Einstellungen** brauchen eine eigene Rasterseite; die zweispaltige Form und die Liste gibt es schon.

### 4.3 HDR-Inhalte hinter der Oberfläche

Im Player liegt die Oberfläche über Dolby-Vision- und HDR-Bildern mit bis zu 1 000 nits und mehr. Glas
(`.ultraThinMaterial`) lässt Spitzlichter durch. Regeln:

1. Jede Fläche über Video hat eine deckende Abdunklung (`bg.scrim`, mindestens 75 %) über dem Material, wie es
   Spur-Leiste und Seitenpanel heute schon tun.
2. Der Verlauf der Steuerleiste reicht so hoch, dass auch der Titel in seinem dunklen Teil steht.
3. Weiß in der Oberfläche über HDR wird gedämpft (`fg.primary` mit 90 % statt 100 %), analog zur vorhandenen Option
   „Helligkeit der Untertitel bei HDR“.
4. Keine farbigen Signalflächen im Player; Fehler stehen in einer neutralen `OverlayCard` mit Zustandssymbol.

## 5. Konfigurator und JSON-Schema

### 5.1 Was der Konfigurator kann

- Vorschau im Format 16:9 (1920 × 1080 Punkte, skaliert) mit erfundenen Titeln und gezeichneten Platzhalterbildern.
- Vier Bereiche mit Live-Vorschau: Startseite & Hero, Detailseite, Player (vier Szenen: Steuerleiste, Ton &
  Untertitel, Nächste Folge, „Noch da?“), Navigation & Einstellungen.
- Fünf Vorlagen: **Edel** (empfohlener Standard), Apple TV, Infuse, Kino-Boutique, Streaming. Danach ist jede
  Einstellung frei änderbar; die Vorlage zeigt dann „(angepasst)“.
- Ein Klick auf eine Karte der Vorschau setzt den Fokus dorthin.
- Export als JSON (kopieren oder als Datei speichern), Import aus Text oder Datei. Unbekannte Werte werden beim Import
  durch den Wert der Vorlage ersetzt und gezählt.
- Jede Option hat einen Kurztext. Optionen, die auf tvOS aufwendig sind, tragen eine Markierung mit Begründung.

### 5.2 Schema `player.appearance.preset`, Version 1

```json
{
  "schema": "player.appearance.preset",
  "version": 1,
  "preset": "edel",
  "modified": false,
  "exportedAt": "2026-11-22T21:00:00.000Z",
  "values": {
    "global": { "navigation": "seitenleiste", "clock": true, "settingsLayout": "spalten", "accent": "champagner",
                "background": "graphit", "typeScale": "standard", "typeCharacter": "editorial", "motion": "dezent" },
    "home":   { "heroStyle": "vollbild", "heroInfo": "standard", "heroTitle": "logo", "backdropFollowsFocus": true,
                "cardShape": "mischung", "cardSize": "mittel", "corners": "weich", "rowSpacing": "luftig",
                "rowTitle": "dezent", "cardTitles": "fokus", "expandPosters": false, "focusScale": "dezent",
                "focusBorder": "weiss", "focusShadow": "weich", "focusGlow": false },
    "detail": { "layout": "links", "descriptionLines": 3, "cast": "kreise", "badgeStyle": "umriss",
                "ratingStyle": "symbole", "sourceList": "karten" },
    "player": { "controlBar": "standard", "badges": "kompakt", "timeDisplay": "rest", "trackPanel": "seite",
                "upNext": "karte", "stillWatching": "karte" }
  }
}
```

| Feld | Typ | Bedeutung |
|---|---|---|
| `schema` | Text, fest | Erkennung im Schnell-Import der Handy-Seite |
| `version` | Zahl | 1. Höhere Versionen werden gelesen; unbekannte Felder und Werte werden ignoriert |
| `preset` | `edel`, `appletv`, `infuse`, `kino`, `streaming` | Basis-Vorlage |
| `modified` | Wahrheitswert | nur zur Anzeige |
| `exportedAt` | ISO-8601 | nur zur Anzeige |
| `values` | Objekt | alle Werte, vollständig |

Erlaubte Werte je Option:

| Bereich | Option | Werte | auf tvOS aufwendig |
|---|---|---|---|
| global | `navigation` | `seitenleiste`, `oben` | |
| global | `clock` | `true`, `false` | |
| global | `settingsLayout` | `spalten`, `kacheln`, `liste` | `kacheln`: eigene Rasterseite |
| global | `accent` | `champagner`, `weiss`, `eisblau`, `blau`, `rot`, `koralle`, `salbei`, `violett` | |
| global | `background` | `schwarz`, `graphit`, `tinte`, `warm` | |
| global | `typeScale` | `kompakt`, `standard`, `gross` | |
| global | `typeCharacter` | `neutral`, `editorial`, `technisch` | |
| global | `motion` | `aus`, `dezent`, `standard` | |
| home | `heroStyle` | `vollbild`, `banner`, `karussell`, `aus` | `karussell`: eigene Fokus-Führung |
| home | `heroInfo` | `minimal`, `standard`, `ausfuehrlich` | |
| home | `heroTitle` | `logo`, `text` | |
| home | `backdropFollowsFocus` | `true`, `false` | lädt je Ruhepause ein großes Bild |
| home | `cardShape` | `poster`, `querformat`, `mischung` | |
| home | `cardSize` | `klein`, `mittel`, `gross` | |
| home | `corners` | `eckig`, `leicht`, `weich`, `rund` | verlangt eigene Karte statt Systemstil |
| home | `rowSpacing` | `eng`, `normal`, `luftig` | |
| home | `rowTitle` | `dezent`, `standard`, `gross` | |
| home | `cardTitles` | `immer`, `fokus`, `aus` | |
| home | `expandPosters` | `true`, `false` | ändert die Reihenbreite unter dem Fokus |
| home | `focusScale` | `keine`, `dezent`, `kraeftig` | |
| home | `focusBorder` | `keiner`, `weiss`, `akzent` | |
| home | `focusShadow` | `keiner`, `weich`, `tief` | |
| home | `focusGlow` | `true`, `false` | echter Glanz nur im Systemstil der Karte |
| detail | `layout` | `links`, `zentriert`, `kino` | |
| detail | `descriptionLines` | `2`, `3`, `5` | |
| detail | `cast` | `kreise`, `karten`, `text`, `aus` | |
| detail | `badgeStyle` | `umriss`, `gefuellt`, `text`, `logos` | `logos`: selbst gezeichnet, Markenrecht beachten |
| detail | `ratingStyle` | `symbole`, `text`, `kacheln` | |
| detail | `sourceList` | `kompakt`, `ausfuehrlich`, `karten` | |
| player | `controlBar` | `minimal`, `standard`, `ausfuehrlich` | |
| player | `badges` | `aus`, `kompakt`, `voll` | |
| player | `timeDisplay` | `rest`, `gesamt`, `ende` | |
| player | `trackPanel` | `seite`, `unten`, `mitte` | |
| player | `upNext` | `karte`, `leiste`, `vollbild` | |
| player | `stillWatching` | `dialog`, `karte` | |

Das Schema entspricht dem Modell `Look` aus [04 §8](04-system-design.md): `preset` wird zu `Look.preset`, `values`
wird beim Import in Abweichungen gegenüber der Vorlage umgerechnet. Die Datei
`docs/design/konfigurator/export.json` ist die Eingabe für die Design-Tasks des Plans (Builds 4 und 5).

### 5.3 Die fünf Vorlagen

| Option | Edel | Apple TV | Infuse | Kino-Boutique | Streaming |
|---|---|---|---|---|---|
| Navigation · Uhr | Seitenleiste · an | oben · aus | oben · an | Seitenleiste · aus | oben · aus |
| Akzent · Hintergrund | Champagner · Graphit | Weiß · Schwarz | Koralle · Graphit | Weiß · Warm | Rot · Schwarz |
| Schrift | Standard, editorial | Standard, neutral | Kompakt, technisch | Groß, editorial | Groß, neutral |
| Bewegung | dezent | standard | dezent | dezent | standard |
| Hero | Vollbild, Standard, Logo | Vollbild, minimal, Logo | Banner, ausführlich, Text | Banner, minimal, Text | Vollbild, ausführlich, Logo |
| Karten | Mischung, mittel, weich, luftig | Querformat, groß, rund, luftig | Poster, mittel, leicht, normal | Poster, groß, eckig, luftig | Querformat, mittel, leicht, eng |
| Fokus | 1,05 + weißer Rahmen + weicher Schatten | 1,12 + Glanz + tiefer Schatten | 1,05 + Akzent-Rahmen | nur weißer Rahmen | 1,12 + tiefer Schatten |
| Hintergrund nach Fokus · Aufklappen | an · aus | aus · aus | an · aus | aus · aus | an · an |
| Detailseite | links, Umriss-Plaketten, Kreise, Quellen als Karten | Kino, Text, Kreise, kompakt | links, gefüllt, Karten, ausführlich | Kino, Text, Textzeile, kompakt | links, gefüllt, Kacheln, Karten |
| Player | Standard, Panel seitlich, Karte | minimal, Panel unten, Karte | ausführlich, Panel seitlich, Leiste | minimal, Panel mittig, Vollbild | Standard, Panel unten, Vollbild |

## 6. Am Gerät prüfen (Design)

- Echte Punktgrößen der tvOS-Textstile (die Kommentare in `V/Design/Theme.swift:13`–`:25` weichen von Apples Tabelle ab).
- Ob der sichtbare Seitenrand mit Seitenleiste 80 oder 160 pt beträgt.
- Lesbarkeit der vier Player-Karten über einer hellen HDR-Szene.
- Tatsächliche Skalierung des Systemstils `.card` (im Code mit 1,15 angenommen).
- Kontrast von `fg.secondary` auf dem Hero-Verlauf bei hellen Bildern.

---

# Anhang: Erhebung aus dem Code

Die folgenden Teile sind die vollständige Erhebung: Token-Inventar (Teil 1), Anpassbarkeit heute (Teil 2), alle
Befunde D-1 bis D-28 (Teil 3) und die Komponentenliste (Teil 4).

## Teil 1 — Token-Inventar

### 1.1 Was `Theme.swift` definiert

| Token | Wert | Zeile |
|---|---|---|
| `TextRole.display` | `.largeTitle.bold()` (Kommentar: 76) | `V/Design/Theme.swift:30` |
| `TextRole.pageTitle` | `.title2.bold()` (Kommentar: 48) | `:31` |
| `TextRole.sectionTitle` | `.title3.weight(.semibold)` (Kommentar: 38) | `:32` |
| `TextRole.rowTitle` | `.body` (Kommentar: 29) | `:33` |
| `TextRole.rowTitleEmphasis` | `.headline` (Kommentar: 29 semibold) | `:34` |
| `TextRole.rowDetail` | `.subheadline`, Farbe `Palette.secondary` (Kommentar: 29) | `:35`, `:41` |
| `TextRole.badge` | `.caption.bold()` (Kommentar: 25) | `:36` |
| `Space.xs / s / m / l / xl` | 8 / 12 / 20 / 32 / 48 | `:48`–`:56` |
| `Space.edge` / `edgeVertical` | 80 / 60 | `:58`, `:60` |
| `Screen.bounds` | 1920 × 1080 | `:66` |
| `Layout.categoryColumnWidth` | 560 | `:72` |
| `Layout.contentMaxWidth` | 1100 | `:74` |
| `Layout.confirmationWidth` | 760 | `:76` |
| `Layout.rowMinHeight` | 80 | `:78` |
| `Layout.iconTile` / `iconSize` | 48 / 32 | `:80`, `:81` |
| `Layout.accentMarkWidth` | 6 | `:83` |
| `Layout.categoryRowMinHeight` | 72 | `:85` |
| `Layout.statusMark` | 72 | `:87` |
| `Tile.size/width/height` | aus `PosterSize` (Poster 240×360, Quer 440×248, Logo 320×180, Hero 1600×620) × Faktor | `:93`–`:95`, `PC/Models/PosterSize.swift:22`–`:25` |
| `Tile.placeholder` | Weiß 8 % | `:97` |
| `Tile.packageGradients` | 6 Zweifarb-Verläufe (RGB-Literale), topLeading → bottomTrailing | `:100`–`:110` |
| `Focus.scale` | 1,02 (Zeilen) | `:117` |
| `Focus.tileScale` | 1,06 (Aktionsknopf, Besetzungskachel) | `:119` |
| `Focus.rowMaxGrowth` | 2 pt je Seite | `:122` |
| `Focus.tileRowPadding` | 44 | `:125` |
| `Focus.cardLiftScale` | 1,15 (Annahme für System-`.card`) | `:129` |
| `Focus.cardLiftShadow` | 12 | `:131` |
| `Focus.listFade` | 24 | `:133` |
| `Focus.pressedScale` | 0,98 | `:148` |
| `Focus.shadowOpacity/Radius/Y` | 0,35 / 14 / 8 | `:150`–`:152` |
| `Focus.duration` / `pressDuration` | 0,15 s / 0,1 s (beide `easeOut`) | `:154`, `:155` |
| `Radius.badge / row / overlayCard` | 8 / 20 / 24 (`card` = Systemradius, keine Zahl) | `:164`, `:166`, `:168` |
| `Palette.base` | Schwarz | `:176` |
| `Palette.surface` | `Color(white: 0.07)` | `:179` |
| `Palette.scrim` | Schwarz 75 % | `:181` |
| `Palette.overlayCard` | `Color(white: 0.12)` | `:183` |
| `Palette.row` | Weiß 10 % | `:185` |
| `Palette.rowFocused` | Weiß 100 % | `:187` |
| `Palette.primary` / `secondary` | Weiß / Weiß 65 % | `:189`, `:191` |
| `Palette.primaryOnFocus` / `secondaryOnFocus` | Schwarz / Schwarz 60 % | `:193`, `:195` |
| `Palette.badgeFill` / `badgeFillOnFocus` | Weiß 18 % / Schwarz 10 % | `:197`, `:199` |
| `Palette.posterBand` | Schwarz 55 % | `:201` |
| `Palette.badgeOnImage` | Schwarz 65 % | `:203` |
| `Tone.ok / warn / error` | `.green` / `.orange` / `.red`; Textrot `(1, 0.45, 0.42)`; je ein SF Symbol | `:229`–`:231`, `:241`, `:247`–`:249` |
| `CategoryTint` (9) | blue, purple, cyan, orange, pink, green, teal, indigo, gray | `:269`–`:277` |
| `accentMark(focused:)` | `TintShapeStyle()` bzw. Schwarz auf Fokus | `:285`–`:287` |
| `ThemeRowButtonStyle` | Fläche `row`→Weiß, Radius 20, Rand waagrecht 20 / senkrecht 12, Skala 1,02, Schatten, 0,15 s | `:331`–`:377` |
| `ThemeActionButtonStyle` | wie oben, Rand 32/12, Mindesthöhe 80, Skala 1,06, `selected` = `badgeFill` | `:384`–`:410` |
| `ThemeTileButtonStyle` | Rand 12 rundum, Skala 1,06 | `:415`–`:434` |
| `IconTile` | 48×48, Radius 8, Symbol 32 pt semibold weiß gefüllt | `:438`–`:450` |
| `ThemeBadge.TechSize` | Höhe 34 (detail) / 30 (sources) / 26 (poster); Poster-Schrift `.caption2.bold()` | `V/Design/ThemeBadge.swift:19`–`:21`, `:29` |
| Status-Plakette | Kapsel, Zustandsfarbe 22 % bzw. `badgeOnImage` | `V/Design/ThemeBadge.swift:102`, `:135` |

Nicht als Token vorhanden: Schattenstufen außer Fokus, Bewegungsdauern außer Fokus, Verläufe/Scrims für Bilder, Radius für Vorschaubilder, Ränder des Players, Zeilenabstand, Laufweite, eine Rolle für Fließtext und für Hinweise.

Hinweis: Der Kopfkommentar `V/Design/Theme.swift:5` („Noch an keiner bestehenden Stelle eingesetzt“) ist überholt.

### 1.2 Zählung hart codierter Literale außerhalb von `Theme.swift`

Zählweise (grep je Datei, Kommentarzeilen ausgenommen): Farbe = `Color(red:/white:)`, `.opacity(<Zahl>)`, benannte Systemfarben, `.secondary/.white/.black` als Stil, `.ultraThinMaterial`; Größe = `.system(size:)`, `padding(<Zahl>)`, `spacing: <Zahl>`, `width/height/max…: <Zahl>`, `lineWidth`, `GridItem(.fixed(<Zahl>))`; Radius = `cornerRadius: <Zahl>`; Dauer = `duration: <Zahl>`, `withAnimation {` ohne Angabe, 350-ms-Ruhezeit; Schatten = `.shadow(`.

| Datei (unter `App/Sources/`) | Farbe | Größe | Radius | Dauer | Schatten |
|---|---:|---:|---:|---:|---:|
| `Views/Player/PlayerScrub.swift` | 18 | 10 | 3 | 1 | 0 |
| `Views/DetailViews.swift` | 15 | 21 | 2 | 2 | 1 |
| `Views/RowViews.swift` | 12 | 13 | 0 | 3 | 5 |
| `Views/PlayerScreen.swift` | 11 | 7 | 2 | 8 | 0 |
| `Views/Player/SubtitleTextView.swift` | 8 | 4 | 0 | 0 | 1 |
| `Views/HomeHero.swift` | 7 | 6 | 0 | 6 | 1 |
| `Views/Settings/SubtitleStyleSettingsRows.swift` | 6 | 2 | 1 | 2 | 0 |
| `Views/PhoneInputView.swift` | 5 | 7 | 1 | 0 | 0 |
| `Views/Player/PlayerPauseCard.swift` | 4 | 3 | 0 | 2 | 0 |
| `AppModel+StreamSearch.swift` | 4 | 3 | 0 | 0 | 0 |
| `Views/PersonView.swift` | 3 | 11 | 1 | 0 | 0 |
| `Views/SyncLoginView.swift` | 3 | 8 | 1 | 0 | 0 |
| `Views/Player/SkipSegmentButton.swift` | 3 | 5 | 0 | 4 | 0 |
| `Views/Player/PlayerLoadingSteps.swift` | 3 | 3 | 1 | 1 | 0 |
| `Views/Design/ThemeBadge.swift` | 3 | 0 | 0 | 0 | 0 |
| `Views/Player/PlayerSidePanel.swift` | 2 | 14 | 0 | 0 | 0 |
| `Views/Player/PostPlayCard.swift` | 2 | 12 | 2 | 1 | 0 |
| `Views/TorBoxFilesRow.swift` | 2 | 11 | 0 | 0 | 0 |
| `Views/Player/PlayerTrackPanel.swift` | 2 | 5 | 0 | 0 | 0 |
| `Views/Home/HomeManagerView.swift` | 2 | 3 | 0 | 1 | 0 |
| `Views/Player/PlayerInfoBadges.swift` | 2 | 1 | 0 | 0 | 0 |
| `Views/HomeView.swift` | 2 | 1 | 0 | 0 | 0 |
| `Views/Player/PlayerStability.swift` | 2 | 0 | 1 | 0 | 0 |
| `Views/Design/StatusCard.swift`, `Views/SpoilerBlur.swift`, `Views/Settings/DeviceCheckSettings.swift`, `ImagePipeline.swift` | je 2 | 0 | 0 | 0–3 | 0 |
| `PlayerApp.swift` | 1 | 5 | 0 | 0 | 0 |
| `Views/CalendarView.swift` | 1 | 7 | 0 | 0 | 2 |
| übrige (je ≤ 3 Treffer: `ClockView`, `GenrePageView`, `SourceFilterBar`, `AppearanceSettings`, `AddRowBrowser`, `LibraryView`, `ProfileSettings`, `TabBarGuard`, `TilePosterImage`, `HomeTopEdgeWatch`, `FocusVideo`, `QualityBadges`, `SubtitleOverlayView`, `RatingIconStore`) | 4 | 12 | 0 | 5 | 0 |
| **Summe** | **135** | **173** | **15** | **39** | **10** |

Frei von Literalen (nur Tokens): `Views/Settings/*` bis auf die Untertitel-Vorschau, `Views/Design/CategoryList.swift`, `SettingsRow.swift`, `FocusAnchor.swift`, `Views/Home/AddRowBrowser.swift` (1 Treffer), `Views/SettingsView.swift`.

### 1.3 Bereich 1 — Startseite und Hero

| Art | Wert | Herkunft | Ort |
|---|---|---|---|
| Hintergrund | Schwarz, Vollbild-Bild, `ignoresSafeArea()` nur für die Hintergrundebene | Literal | `V/HomeHero.swift:136`, `:151` |
| Verlauf links→rechts | Schwarz 85 % (0) → 35 % (0,45) → klar (0,7) | Literal | `V/HomeHero.swift:144`–`:146` |
| Verlauf oben→unten | klar (0,3) → Schwarz 60 % (0,6) → 95 % (1) | Literal | `V/HomeHero.swift:147`–`:149` |
| Überblendung Hintergrund | 0,6 s `easeInOut` | Literal | `V/HomeHero.swift:155`, `:166` |
| Info-Wechsel | 0,3 s `easeInOut` | Literal | `V/HomeHero.swift:224`, `:225` |
| Diashow | 10 s Takt, Fokus-Ruhezeit 350 ms | Literal | `V/HomeHero.swift:110`, `:27` |
| Hero-Maße | `listTop` 470, `logoHeight` 140, Logo max. 640 breit, Meta-Zeile 30 hoch | Literal (`HeroMetrics`) | `V/HomeHero.swift:69`, `:70`, `:208`, `:217` |
| Titel ohne Logo | `textRole(.display)`, 2 Zeilen, `minimumScaleFactor(0.6)` | Token | `V/HomeHero.swift:210` |
| Beschreibung | `.callout`, 2 Zeilen, max. 1100 | Literal Schrift, Token Breite | `V/HomeHero.swift:220`, `:221` |
| Schatten Info-Block | Schwarz 60 %, Radius 8, auf dem ganzen Block | Literal | `V/HomeHero.swift:223` |
| Hero-Knöpfe | `ThemeActionButtonStyle`, Abstand `Space.l`, Rand `Space.edge`/`Space.s` | Token | `V/HomeHero.swift:273`–`:296` |
| Diashow-Punkte | 12 × 12, Weiß 100 %/35 %, 0,3 s | Literal | `V/HomeHero.swift:288`–`:292` |
| Listenabstand | Reihe ↔ Reihe `Space.xl` (48) | Token | `V/HomeView.swift:42`, `:112` |
| Listenränder | oben 24 bzw. `max(0, 40 − room)`, unten 60 bzw. 40, Knopf unten +20 | Literal | `V/HomeView.swift:43`, `:44`, `:116`, `:117`, `:192` |
| Maske oben | Verlauf klar→Schwarz, Höhe `Focus.listFade` (24) | Token | `V/HomeView.swift:130`, `:131` |
| Sicherer Rand unten | `ignoresSafeArea(edges: .bottom)` für die Liste (Platz fürs Anheben), eigener Wert 60 | Literal | `V/HomeView.swift:54`, `:142`, `:157` |
| Reihentitel | `textRole(.sectionTitle)`, Rand links `Space.edge` | Token | `V/RowViews.swift:36` |
| Reihe | Kartenabstand `Space.m × Faktor`, `contentMargins` 80, `scrollClipDisabled` | Token | `V/RowViews.swift:359`–`:370` |
| Poster-Fokus | System `.buttonStyle(.card)` | System | `V/RowViews.swift:207`, `:228`, `:313` |
| Aufklappen | Ruhezeit 350 ms, 0,25 s `easeInOut`, Breite Höhe × 16/9 | Literal | `V/RowViews.swift:399`, `:406`–`:413` |
| Aufgeklappt: Verlauf | Schwarz 75 % → klar (unten → Mitte) | Literal | `V/RowViews.swift:431` |
| Aufgeklappt: Titel | `.headline`, 2 Zeilen, `shadow(radius: 6)`, Rand 18/26 | Literal | `V/RowViews.swift:439`, `:443` |
| Querformat-Karte | Titel `.headline`, `shadow(radius: 6)`, Rand 14/24, kein Verlauf | Literal | `V/RowViews.swift:457` |
| Hero-Karte (Reihenstil) | 1600×620, Verlauf Schwarz 85 % → klar, Innenrand `Space.xl`, Beschreibung ohne Schriftangabe, max. 1000 | gemischt | `V/RowViews.swift:468`–`:477` |
| Top 10 | Ziffer 220 × Faktor, `.black`, Weiß 85 %, `shadow(radius: 8)`, Überlappung −30 | Literal | `V/RowViews.swift:486`–`:488` |
| Logo-Kachel | Grund Weiß 8 % (Literal statt `Tile.placeholder`), Innenrand 30 | Literal | `V/RowViews.swift:519`, `:520` |
| Collection-Kachel | Titel `.headline`, `shadow(radius: 4)`, Rand 14 | Literal | `V/RowViews.swift:539` |
| Paket-Kachel | `Tile.packageGradient`, Symbol 64 × Faktor semibold, Abstand 14, Rand 20 | gemischt | `V/RowViews.swift:549`–`:555` |
| Platzhalter | `Tile.placeholder` | Token | `V/RowViews.swift:582`, `:609` |
| Gesehen-Haken | `checkmark.circle.fill`, `.title3`, Palette Schwarz/Weiß, `shadow(radius: 4)`, Rand 10 | Literal | `V/RowViews.swift:625`–`:627` |
| Fortschrittsbalken | Kapsel 6 hoch, Weiß 30 % / 100 %, Rand 10 | Literal | `V/RowViews.swift:638`–`:642` |
| Poster-Plaketten | `ThemeBadge(.poster, .image)`, Abstand `Space.xs`, Einblenden 0,2 s `easeOut`, Abstand oben 10 bzw. 56 × Faktor | gemischt | `V/QualityBadges.swift:26`–`:28`, `:61`, `:76`–`:78` |
| Plakettenstreifen | `Palette.posterBand`, Höhe 26 + 2 × 8 | Token | `V/QualityBadges.swift:22`–`:24`, `:92` |
| Ersatztitel ohne Bild | `.caption`, Rand 10 | Literal | `V/TilePosterImage.swift:36` |
| Kalender-Kachel | 440×248 fest, Verlauf Schwarz 85 % → klar, `shadow(radius: 6)` | Literal Maß, Token Schrift | `V/CalendarView.swift:93`–`:101` |
| TorBox-Kachel | 480×150 / 240×150, Rand 16, `.headline`/`.caption`, `.card` | Literal | `V/TorBoxFilesRow.swift:40`–`:65` |

### 1.4 Bereich 2 — Detailseite, Person, Genre, Quellenliste

| Art | Wert | Herkunft | Ort |
|---|---|---|---|
| Hintergrund | Bild vollflächig, darüber einheitlich Schwarz 55 %, kein Verlauf | Literal | `V/DetailViews.swift:108` |
| Ränder | `Space.edge` / `Space.edgeVertical` innerhalb der sicheren Fläche | Token | `V/DetailViews.swift:161`, `:162` |
| Logo | max. 700 × 200 | Literal | `V/DetailViews.swift:113` |
| Titel | `textRole(.display)` | Token | `V/DetailViews.swift:115` |
| Poster links | Höhe = Infoblock, Abstand 40 (`DetailPage.posterGap`), Radius 12, Schatten Schwarz 45 % / 12 / y 6 | Literal | `V/DetailViews.swift:118`, `:646`, `:647` |
| Infoblock | Abstand `Space.l`; Meta-Zeile; Plaketten; Tagline kursiv `rowDetail`; Beschreibung `.callout` weiß, 3 Zeilen | gemischt | `V/DetailViews.swift:412`–`:424` |
| Text-Fokus | `FocusHighlight`: Weiß 14 %, Radius 12 (nicht `continuous`), Rand 16/10, 0,15 s | Literal | `V/DetailViews.swift:654`, `:655`, `:665`, `:666` |
| Knöpfe | `ThemeActionButtonStyle`; Beschriftung mit Unicode „▶“ | Token + Literal | `V/DetailViews.swift:144`, `:152`, `:493` |
| Karte „Sofort abspielen“ | max. 620 breit | Literal | `V/DetailViews.swift:496` |
| Staffelknöpfe | `ThemeActionButtonStyle(selected:)` | Token | `V/DetailViews.swift:584` |
| Folgenzeile | Standbild 280×158 ohne Radius, `ThemeRowButtonStyle(maxWidth: .infinity)`, Haken `Tone.ok`, `ProgressView` 120 breit | gemischt | `V/DetailViews.swift:605`, `:612`, `:614`, `:622` |
| Besetzung | Kreis 180, Kachel 220 breit, Name `.caption.weight(.semibold)`, Rolle `.caption2` + `.secondary`, `ThemeTileButtonStyle`, Abstand `Space.l` | gemischt | `V/DetailViews.swift:1353`–`:1368` |
| Ähnliche Titel | Abstand 40, Poster 240×360 fest | Literal | `V/DetailViews.swift:1375` |
| „Über“ | Raster 40/14, `.callout`, Innenrand 36, max. 1400, `.buttonStyle(.card)` mit leerer Aktion | Literal | `V/DetailViews.swift:1398`–`:1409` |
| Plakettenzeile | Technik Abstand `Space.xs`, Bewertungen `Space.m`, max. 1400 | gemischt | `V/DetailViews.swift:1291`, `:1298`–`:1304` |
| Markenfarben Bewertungen | 4 RGB-Literale | Literal | `V/DetailViews.swift:1311`–`:1314` |
| Ganzer Text (Blatt) | `pageTitle`, Absätze `.body`, max. 1300, Rand 60 | gemischt | `V/DetailViews.swift:678`–`:684` |
| Quellenliste | `List` `.grouped`, `settingsSurface()`, Zeilen `ThemeRowButtonStyle(maxFocusGrowth: 2)` | Token | `V/DetailViews.swift:788`, `:831`, `:835` |
| Quellenzeile | Namensspalte 330 fest; Text `rowDetail` ohne Zeilengrenze; Dateiname zusätzlich 75 %; Fehlversuch 40 % | gemischt | `V/DetailViews.swift:782`, `:1188`, `:1192`, `:1196` |
| Filterleiste | `ThemeActionButtonStyle(selected:)`, Zähler 60 % | Token + Literal | `V/SourceFilterBar.swift:40`–`:45` |
| Person | Rand 80 rundum, Foto 260×390 Radius 16, Name `.largeTitle.bold()`, Initiale 90 bold, Abschnitt `.title3.bold()`, Raster 6 × 240 fest, Abstand 40/50 | Literal | `V/PersonView.swift:15`–`:43`, `:63`, `:64` |
| Suche | Rand 60/40, Raster 6 × 240, Abstand 40/50/30 | Literal | `V/DetailViews.swift:1243`–`:1257` |
| Genre-Seite | durchgehend Tokens; Raster aus `PosterSize` und Postergröße | Token | `V/GenrePageView.swift:44`–`:73`, `:138` |

### 1.5 Bereich 3 — Player-Oberfläche

| Art | Wert | Herkunft | Ort |
|---|---|---|---|
| Fläche | Schwarz und Bild `ignoresSafeArea()` | Literal | `V/PlayerScreen.swift:240`, `:241` |
| Steuerleiste | Rand 60 rundum, Abstand 14, Verlauf Schwarz 80 % → klar (unten → oben) | Literal | `V/PlayerScreen.swift:509`, `:532`, `:533` |
| Steuerleiste Schrift | Titel `.title3.bold()`, Folge `.callout` + `.secondary`, Zeiten `.caption.monospacedDigit()`, Spurzeile `.caption`, Bedienhinweis `.caption2` + `.secondary` | Literal | `V/PlayerScreen.swift:510`, `:511`, `:522`, `:527`, `:530` |
| Technik-Plaketten | Kapsel Weiß 16 %, `.caption`, Rand 14/6, Abstand 12 | Literal | `V/Player/PlayerInfoBadges.swift:33`–`:39` |
| Seitenpanel-Hinweis | Kapsel `Palette.badgeFill`, `.caption.weight(.semibold)`, Rand 12/4 | gemischt | `V/Player/PlayerSidePanel.swift:212`–`:214` |
| Zeitleiste | 10 hoch, Weiß 25 % / 100 %, Marken Gelb 75 % / Cyan 60 % / Violett 60 %, Knopf 22, Strich 3 × 18 Weiß 60 % | Literal | `V/Player/PlayerScrub.swift:535`–`:559` |
| Spul-Vorschau | Karte 480 breit, Innenrand 14, `.ultraThinMaterial` Radius 18, Bild Radius 12 auf Schwarz 60 %, Zeit `.title3.monospacedDigit().bold()`, Hinweise `.caption`/`.caption2`, 0,15 s | Literal | `V/Player/PlayerScrub.swift:478`–`:517` |
| „Nächste Folge“ | 560 breit, Innenrand 28, `.ultraThinMaterial` Radius 20, Außenrand 60, `.headline`/`.callout`/`.caption`, Übergang `move(.trailing)` + Deckkraft, `withAnimation {}` ohne Angabe | Literal | `V/PlayerScreen.swift:255`, `:494`–`:502` |
| Karte nach dem Film | Innenrand 36, `.ultraThinMaterial` Radius 28, Außenrand 80/60, Poster 170×255 Radius 12, System-`.card` und Systemknöpfe | Literal | `V/Player/PostPlayCard.swift:28`–`:69` |
| Überspringen-Knopf | Systemknopf, `.headline`, Rand rechts 80 / unten 300, Ring 34 mit Strich 5 | Literal | `V/Player/SkipSegmentButton.swift:305`–`:316`, `:359`–`:365` |
| Szenen-Hinweis | Kapsel `.ultraThinMaterial`, `.callout.weight(.semibold)`, Rand 26/14, außen 80/80 | Literal | `V/Player/SkipSegmentButton.swift:294`–`:299` |
| Übergänge Skip/PostPlay | 0,25 s / 0,3 s `easeInOut`, Ring 0,5 s linear | Literal | `V/Player/SkipSegmentButton.swift:334`–`:336`, `:363` |
| Pausenkarte | Verlauf Schwarz 85 % → 35 % → klar (unten → oben) plus Schwarz 45 % → klar (oben → Mitte), Rand 80 / unten 70, max. 1100, Logo max. 560×180, `.largeTitle.bold()`, `.title3.weight(.semibold)`, `.callout` 90 %, `.caption`, `.caption2`; Ein 0,35 s, Aus 0,2 s | Literal + Palette | `V/Player/PlayerPauseCard.swift:47`, `:55`, `:94`–`:126` |
| Ladekarte | Schwarz 55 %, Radius 24, Rand 48/36, `ProgressView().scaleEffect(2)`, `.headline`, 0,2 s | Literal | `V/Player/PlayerLoadingSteps.swift:34`–`:48` |
| Fehlertext | Rot 80 %, Radius 16, Rand 30, Schrift ohne Angabe | Literal | `V/PlayerScreen.swift:247` |
| Netz-Hinweis | Orange 85 %, Radius 16, `.headline`, Rand 30/18, oben 60 | Literal | `V/Player/PlayerStability.swift:130`–`:133` |
| Spur-Leiste | Höhe ⅓ Bildschirm, Grund `.ultraThinMaterial` + `Palette.scrim`, Radius `overlayCard`, Spalten 780/660/230, Abstand 32, Zeilen `.callout`, Marken `ThemeBadge(.poster)` | Token + Core-Maße | `V/Player/PlayerTrackPanel.swift:157`–`:168`, `:477`–`:479`, `PC/Playback/TrackPanelLayout.swift:73`–`:76` |
| Spur-Menü | 720 breit, 6 Zeilen à 55, gleicher Grund | Core-Maße | `V/Player/PlayerTrackPanel.swift:346`–`:349`, `PC/Playback/TrackPanelStyle.swift:166`–`:170` |
| Seitenpanel | 720 breit, Randverlauf 160 breit klar → Schwarz 45 %, Grund Material + `scrim`, Titel `.title3.bold()`, Zeilen `.callout`/`.caption`, Bild 160×90 Radius 8, Zeilenabstand 2 | gemischt | `V/Player/PlayerSidePanel.swift:248`, `:283`–`:298`, `:564`–`:580` |
| Panel-Zeilenstil | `ThemeRowButtonStyle(minHeight: 0, restFill: .clear, verticalPadding: 8, maxFocusGrowth: 2)` | Token | `V/Player/PlayerSidePanel.swift:552`–`:555`, `V/Player/PlayerTrackPanel.swift:466`–`:469` |
| Untertitel | Größe 40/48/58/70, Umriss 0/1,5/2,5/4, Schatten Schwarz 55 % / 6 / y 2, Kasten Schwarz 62 % Radius 0,18 × Schrift, Rand 0,4/0,12 × Schrift, Breite 86 % | Einstellung + Literal | `PC/Playback/SubtitleStyle.swift:19`–`:22`, `:66`–`:69`, `V/Player/SubtitleTextView.swift:51`–`:56`, `V/Player/SubtitleOverlayView.swift:62` |
| Systemdialoge | `alert` für Fehler, „Noch da?“, App-Fehler | System | `V/Player/PlaybackErrorCard.swift:11`, `V/Player/StillWatchingPrompt.swift:44`, `App/Sources/PlayerApp.swift:88` |

### 1.6 Bereich 4 — Navigation und Einstellungen

| Art | Wert | Herkunft | Ort |
|---|---|---|---|
| Hauptnavigation | System-`TabView`, wahlweise `.sidebarAdaptable` | System | `App/Sources/PlayerApp.swift:94`, `:169` |
| Akzent | `.tint(accent.color)` auf der Wurzel; auf Hero, Detail, Quellenliste, Person wieder entfernt | Einstellung | `App/Sources/PlayerApp.swift:85`, `V/HomeHero.swift:301`, `V/DetailViews.swift:171`, `:834`, `V/PersonView.swift:45` |
| Uhr | `.title3.monospacedDigit().weight(.semibold)`, `.secondary`, oben 40 / rechts 80 | Literal | `V/ClockView.swift:14`, `:15`, `App/Sources/PlayerApp.swift:82` |
| Profilwahl | `.largeTitle.bold()`, Kreis 220 `.blue.gradient`, Initiale 90 bold, `.title3`, `.borderless`, Abstände 60/50 | Literal | `App/Sources/PlayerApp.swift:216`–`:229` |
| Einstellungsgrund | `Palette.surface`, `ignoresSafeArea()` nur für den Grund | Token | `V/Design/Theme.swift:308` |
| Zweispaltig | Spalte 560, Abstand `Space.xl`, Einträge `Space.xs`, Zeile mind. 72 | Token | `V/Design/CategoryList.swift:62`–`:87` |
| Gruppenkopf | Großbuchstaben, `rowDetail`, `tracking(1)` | Token + Literal 1 | `V/Design/CategoryList.swift:132`–`:134`, `V/Design/SettingsRow.swift:164`–`:166` |
| Einstellungszeile | Symbolkachel, `rowTitle`, `rowDetail` (2 Zeilen, nur bei Fokus), Wert `rowDetail`, Chevron semibold | Token | `V/Design/SettingsRow.swift:53`–`:75` |
| Statuskarte | `Palette.row`, Radius 20, Innenrand 20, Kreis 72; Aktionsknopf im Systemstil | Token + System | `V/Design/StatusCard.swift:56`–`:68` |
| Rückfrage | `scrim`, Karte `overlayCard` Radius 24 (nicht `continuous`), Breite 760, Innenrand 32 | Token | `V/Settings/SettingsKit.swift:292`–`:316` |
| Verwalter | Tokens; Verschiebe-Rahmen Gelb, Strich 6; Zeile mind. 64; Positionsspalte 56 | Token + Literal | `V/Home/HomeManagerView.swift:172`, `:173`, `:227`, `:299` |
| Untertitel-Vorschau | 2 Kacheln 440 breit, Radius 12, zwei RGB-Verläufe, 0,2 s `easeInOut` | Literal | `V/Settings/SubtitleStyleSettingsRows.swift:88`, `:114`–`:127` |
| QR-Seiten | QR 480 bzw. 360 auf Weiß, Radius 24 bzw. 20, Rand 80, `.title2.bold()`, `.largeTitle.bold()`, Code 90 bold monospaced, `.green`/`.red` direkt | Literal | `V/PhoneInputView.swift:97`–`:117`, `V/SyncLoginView.swift:20`–`:40` |
| Fokusanker | System-Knopfstil, `rowTitleEmphasis` | System + Token | `V/Design/FocusAnchor.swift:44`–`:50` |

### 1.7 Sichere Ränder

- `ignoresSafeArea` steht ausschließlich an Hintergründen, Verläufen, Videofläche und Panel-Gründen (`V/HomeHero.swift:151`, `V/DetailViews.swift:108`, `V/PlayerScreen.swift:240`, `:241`, `:277`, `V/Player/PlayerPauseCard.swift:96`, `:98`, `V/Player/PlayerTrackPanel.swift:168`, `V/Player/PlayerSidePanel.swift:285`, `:298`, `V/Design/Theme.swift:308`, `V/Settings/SettingsKit.swift:292`, `V/Home/HomeManagerView.swift:25`). Kein Text und kein Fokusziel liegt außerhalb der sicheren Fläche. Zwei Ausnahmen sind bewusst: die Startliste und das Genre-Raster zeichnen unten in den Rand, damit die angehobene Karte nicht beschnitten wird (`V/HomeView.swift:54`, `:142`, `V/GenrePageView.swift:73`), sowie Spul-Vorschau und Untertitel, die selbst positionieren (`V/Player/PlayerScrub.swift:515`, `V/Player/SubtitleOverlayView.swift:71`).
- Der Inhalt bekommt zusätzlich zur sicheren Fläche noch einmal `Space.edge` (80) bzw. 60/80 als Innenrand. Ob der sichtbare Rand damit 160 statt 80 beträgt, ist nur am Gerät zu klären (siehe „Am Gerät prüfen“). `PC/Playback/TrackPanelLayout.swift:70` rechnet ausdrücklich mit „1920 minus Sicherheitsrand 2 × 80“.

### 1.8 Verwendete Schriften mit Häufigkeit (App/Sources ohne `Theme.swift`)

| Schrift | Anzahl | | Schrift | Anzahl |
|---|---:|---|---|---:|
| Rolle `rowDetail` | 43 (+3 als `.font(Theme.TextRole.rowDetail…)`) | | `.caption2` | 5 |
| `.caption` | 22 | | Rolle `display` | 5 |
| Rolle `sectionTitle` | 10 | | `.title3.bold()` | 4 |
| `.headline` | 10 | | `.largeTitle.bold()` | 4 |
| `.callout` | 9 | | Rolle `rowTitle` | 4 |
| Rolle `rowTitleEmphasis` | 6 | | `.callout.weight(.semibold)` | 3 (+2 abhängig vom Zustand) |
| Rolle `pageTitle` | 6 | | `.caption.weight(.semibold)` / `.caption.bold()` | je 2 |
| `.title3` | 6 | | `.title3.monospacedDigit().bold()` | 2 |

Je einmal: `.title3.weight(.semibold)`, `.title3.monospacedDigit().weight(.semibold)`, `.title3.monospaced()`, `.title2.bold()`, `.title2`, `.title`, `.largeTitle`, `.body`, `.caption.monospacedDigit()`, `.caption.monospaced()`, `.callout.monospacedDigit()`, `.callout.bold()`. Freie Größen: 220 × Faktor black (2), 90 bold (2), 90 bold monospaced (1), 64 × Faktor semibold (1), Untertitel 40–70 semibold/bold.

Ergebnis: 7 Rollen im Token-System, daneben rund 30 weitere Kombinationen aus Stil und Gewicht. 77 Stellen nutzen eine Rolle, 95 Stellen eine freie Angabe.

---

## Teil 2 — Anpassbarkeit heute

### 2.1 Optionen

| Feld | Typ / Werte | Standard | Einstellung (Datei:Zeile) | Gelesen in |
|---|---|---|---|---|
| `Appearance.navigation` | `NavigationStyle`: `sidebar`, `top` | `sidebar` | `V/Settings/AppearanceSettings.swift:24`–`:27` | `App/Sources/PlayerApp.swift:83`, `:123`, `:168`; `V/HomeView.swift:60` |
| `Appearance.accent` | `AccentChoice`: `blue`, `purple`, `pink`, `orange`, `green`, `white` | `blue` | `V/Settings/AppearanceSettings.swift:29`–`:32` | `App/Sources/PlayerApp.swift:85` (Farbzuordnung `V/SettingsView.swift:107`–`:117`) |
| `Appearance.cardSize` | `CardSize`: `small` 0,85 / `medium` 1,0 / `large` 1,2 | `medium` | `V/Settings/HomeCategorySettings.swift:74`–`:77` (eingebunden `V/Settings/AppearanceSettings.swift:35`) | `V/RowViews.swift:203`, `:343`; `V/HomeView.swift:153`, `:164`; `V/GenrePageView.swift:44` |
| `Appearance.heroEnabled` | `Bool` | `true` | `V/Settings/HomeCategorySettings.swift:25`–`:27` | `PC/Models/Appearance.swift:78` über `V/HomeView.swift:26` |
| `Appearance.heroRowID` | `UUID?` (nil = automatisch) | `nil` | `V/Settings/HomeCategorySettings.swift:29`–`:32`, `:46`–`:48` | `PC/Models/Appearance.swift:79` |
| `Appearance.expandPosters` | `Bool` | `true` | `V/Settings/AppearanceSettings.swift:36`–`:38` | `V/RowViews.swift:344`, `:373`, `:384` |
| `Appearance.prefetchStreams` | `Bool` (kein Aussehen, liegt aber hier) | `true` | `V/Settings/SourceCategorySettings.swift:30`–`:32` | `App/Sources/StreamPrefetcher.swift:158` |
| `Appearance.tileAnimationSound` | `Bool` | `false` | `V/Settings/HomeSettings.swift:37`–`:39` | `V/RowViews.swift:125` |
| `Appearance.badges.style` | `BadgeStyle`: `text`, `logo` | `logo` | `V/Settings/AppearanceSettings.swift:51`–`:54` | `PC/Ranking/QualityBadges.swift:155`, `:178` |
| `Appearance.badges.{resolution, hdr, source, videoCodec, audio, channels, languages, size, cacheStatus}` | 9 × `Bool` | alle `true` außer `videoCodec` | `V/Settings/AppearanceSettings.swift:76`–`:90` | `PC/Ranking/QualityBadges.swift:74` ff.; `V/DetailViews.swift:1177`, `:1178`; `V/QualityBadges.swift:35` |
| `Appearance.titles.posterBadges` | `PosterBadgePlacement`: `off`, `topTrailing`, `bottom` | `off` | `V/Settings/TitleDisplaySettingsRows.swift:9`–`:13` | `V/QualityBadges.swift:36`, `:91`; `V/RowViews.swift:347`, `:601`; `V/HomeView.swift:151`, `:162`; `V/GenrePageView.swift:47`; `V/DetailViews.swift:1329` |
| `Appearance.titles.ratingSources` | `[String]` (MDBList-Schlüssel) | `RatingSelection.defaultSources` | `V/Settings/TitleDisplaySettingsRows.swift:41`–`:50` | `App/Sources/AppModel+MetaAddon.swift:115` |
| `Appearance.titles.addonImages` | `Bool` | `true` | `V/Settings/TitleDisplaySettingsRows.swift:73`–`:82` | `V/TilePosterImage.swift:22`; `App/Sources/AppModel+MetaAddon.swift:14` |
| `SourceSettings.appBadges` | `StreamListBadgeMode`: `off`, `compact` | `compact` | `V/Settings/StreamListSettingsRows.swift:29`–`:34` | `V/DetailViews.swift:1177` |
| `SourceSettings.order` | `StreamOrderMode`: `addon`, `smart` | `addon` | `V/Settings/StreamListSettingsRows.swift:12`–`:20` | `App/Sources/AppModel+SourceOrder.swift:20` |
| `SourceSettings.blurUnwatchedStills` | `Bool` | `false` | `V/Settings/SourceSettingsRows.swift:12` | `V/DetailViews.swift:603`; `V/Player/PlayerSidePanel.swift:111` |
| `SourceSettings.ratingIconSetURL` | `String?` | `nil` | `V/Settings/AppearanceSettings.swift:60`–`:64` | `App/Sources/RatingIconStore.swift:100` |
| `PlayerComfortSettings.trackPanelStyle` | `TrackPanelStyle`: `topBar`, `bottomBar`, `menu` | `topBar` | `V/Player/PlayerPictureSound.swift:304`–`:307` | `V/PlayerScreen.swift:537` |
| `PlayerComfortSettings.instantPlay` | `Bool` | `false` | `V/Settings/SourceCategorySettings.swift:24`–`:26` | `V/DetailViews.swift:481` |
| `Profile.subtitleStyle.size` | `small` 40 / `normal` 48 / `large` 58 / `extraLarge` 70 | `normal` | `V/Settings/SubtitleStyleSettingsRows.swift:39`, `:40` | `V/Player/SubtitleTextView.swift:68` über `V/PlayerScreen.swift:242` |
| `Profile.subtitleStyle.position` | `low` 40 / `standard` 70 / `raised` 120 / `high` 180 | `standard` | `V/Settings/SubtitleStyleSettingsRows.swift:41`–`:43` | `V/Player/SubtitleOverlayView.swift:69`, `:157` |
| `Profile.subtitleStyle.outline` | `none` 0 / `thin` 1,5 / `normal` 2,5 / `strong` 4 | `normal` | `V/Settings/SubtitleStyleSettingsRows.swift:44`, `:45` | `V/Player/SubtitleTextView.swift:37` |
| `Profile.subtitleStyle.background` | `none`, `box`, `shadow` | `shadow` | `V/Settings/SubtitleStyleSettingsRows.swift:46`, `:47` | `V/Player/SubtitleTextView.swift:51`–`:56` |
| `Profile.subtitleStyle.hdrBrightness` | `Int` aus 100/85/70/55/40, geklemmt 40…100 | 100 | `V/Settings/SubtitleStyleSettingsRows.swift:48`–`:51` | `PC/Playback/SubtitleStyle.swift:148`, `V/Player/SubtitleTextView.swift:76` |
| `HomeRow.style` (je Reihe) | `RowStyle`: `hero`, `poster`, `landscape`, `top10`, `logoTiles`, `collectionTiles` | je Reihe | `V/Home/HomeManagerView.swift:204`, `:205` | `PC/Models/PosterSize.swift:30`–`:37`, `V/RowViews.swift:195`–`:198` |

Optionen, die existieren, aber nirgends gelesen werden: keine gefunden. Zwei Auffälligkeiten:
- `Appearance.accent` wird nur an einer Stelle gelesen und auf vier Hauptbildschirmen wieder entfernt (D-14).
- `Appearance.prefetchStreams` ist ein Verhaltens-, kein Aussehensfeld und steht in den Einstellungen unter „Quellen“.

### 2.2 Dekodierung

| Struktur | Fehlendes Feld | Unbekannter Enum-Wert |
|---|---|---|
| `Appearance` (`PC/Models/Appearance.swift:58`–`:71`) | Standardwert (`decodeIfPresent ?? d.x`) | **wirft** (`try c.decodeIfPresent(NavigationStyle/AccentChoice/CardSize…)`, `:61`–`:63`) |
| `BadgeSettings` (`PC/Ranking/QualityBadges.swift:58`–`:72`) | Standardwert | **wirft** bei `style` (`:71`) |
| `TitleDisplaySettings` (`PC/Models/TitleDisplaySettings.swift:31`–`:37`) | Standardwert | `posterBadges` fällt auf Standard (`try?`, `:34`); `ratingSources` mit falschem Typ wirft (`:35`) |
| `SourceSettings` (`PC/Models/SourceSettings.swift:26`–`:34`) | Standardwert | fällt je Feld auf Standard (`try?`) |
| `PlayerComfortSettings` (`PC/Models/PlayerComfortSettings.swift:29`–`:38`) | Standardwert | fällt je Feld auf Standard, ausdrücklich kommentiert (`:35`) |
| `SubtitleStyle` (`PC/Playback/SubtitleStyle.swift:123`–`:131`) | Standardwert | fällt je Feld auf Standard; Helligkeit wird geklemmt |
| `Profile` (`PC/Models/Profile.swift:104`–`:111`) | Standardwert | `appearance` mit `try` (wirft durch), `sources`/`player`/`subtitleStyle`/`skip` mit `try?` |

Zwei Dekodier-Stile nebeneinander: die älteren Strukturen (`Appearance`, `BadgeSettings`) sind streng, die neueren nachsichtig.

### 2.3 Versionierung und Presets

- Einziges Versionsfeld: `StoredProfiles.schemaVersion` = 1 (`PC/Store/ProfileStore.swift:4`, `:5`); eine höhere Version wird abgelehnt (`:55`). Kein Versionsfeld in `Appearance` oder einer anderen Aussehens-Struktur.
- Presets: keine. Die einzige Rücksetzfunktion ist „Standard wiederherstellen“ für Untertitel (`V/Settings/SubtitleStyleSettingsRows.swift:52`–`:58`); der Zustand wird als „Standard“ oder „Eigener Stil“ angezeigt (`:16`).
- Kein Theme-Objekt zur Laufzeit: `Theme` ist ein `enum` mit `static let`. Dichte, Radien, Schrift, Flächenhelligkeit oder Bewegung lassen sich heute nicht umschalten, ohne `Theme` in eine Umgebungsgröße umzubauen.

---

## Teil 3 — Befunde

Schweregrade: hoch / mittel / niedrig. „Sicherheit“ sagt, ob der Befund im Code bestätigt ist oder ob die sichtbare Wirkung abgeleitet (plausibel) ist.

### D-1: Ein unbekannter Aussehens-Wert macht die ganze Profildatei unlesbar
- **Ort:** `PC/Models/Appearance.swift:61`, `:62`, `:63`, `PC/Ranking/QualityBadges.swift:71`, `PC/Models/Profile.swift:104`, `PC/Store/ProfileStore.swift:36`–`:39`
- **Beobachtung:** `navigation`, `accent`, `cardSize` und `badges.style` werden mit `try c.decodeIfPresent(Enum.self …)` gelesen. Ein unbekannter Rohwert wirft; `Profile` reicht den Fehler durch, `ProfileStore.load()` legt die Datei als `.bak` ab und liefert `makeDefault()`.
- **Szenario:** Ein neuerer Build speichert `accent: "gold"` oder ein Preset-Feld als neuen Enum-Fall; danach Start eines älteren Builds (Rückschritt über atvloadly) oder Import einer solchen Datei → alle Profile, Addons und Schlüssel erscheinen leer.
- **Warum es zählt:** Jede neue Farbe, Dichte oder Preset-Stufe wird damit zu einem Risiko für die gesamte Konfiguration. Die neueren Strukturen (`SubtitleStyle`, `PlayerComfortSettings`) zeigen bereits das richtige Muster.
- **Empfehlung:** Alle Aussehens-Enums nachsichtig dekodieren (`(try? …) ?? nil ?? Standard`), bevor neue Werte oder Presets eingeführt werden.
- **Priorität:** hoch · **Sicherheit:** bestätigt
- **Test:** PlayerCore-Test: JSON mit `"accent":"gold"` dekodieren und erwarten, dass das Profil mit `accent == .blue` lädt.

### D-2: Player-Overlays sind nicht gegen helle und HDR-Inhalte abgesichert
- **Ort:** `V/PlayerScreen.swift:500`, `:510`, `:533`, `V/Player/PlayerScrub.swift:510`, `V/Player/PostPlayCard.swift:67`, `V/Player/SkipSegmentButton.swift:297`, `V/Player/PlayerInfoBadges.swift:39`; Gegenbeispiel `V/Player/PlayerTrackPanel.swift:164`, `V/Player/PlayerSidePanel.swift:298`
- **Beobachtung:** Vier Karten liegen nur auf `.ultraThinMaterial`, ohne Abdunklung. Die Spur-Leiste und das Seitenpanel legen dagegen `Palette.scrim` (Schwarz 75 %) über das Material. Die Steuerleiste hat einen Verlauf Schwarz 80 % → klar von unten nach oben; der Titel (`.title3.bold()`) steht als oberstes Element dort, wo der Verlauf fast durchsichtig ist. Die Technik-Plaketten sind Weiß 16 % ohne eigenen dunklen Grund.
- **Szenario:** Schneeszene oder HDR-Spitzlicht hinter „Nächste Folge“, Spul-Vorschau oder Titel der Steuerleiste → weißer Text auf hellem, nur weichgezeichnetem Grund; sekundärer Text (`.secondary`) wird unleserlich.
- **Warum es billig wirkt:** Zwei verschiedene Glas-Rezepte im selben Bildschirm; Lesbarkeit hängt vom Filmbild ab.
- **Empfehlung:** Ein Token „Fläche über Video“ (Material + Scrim oder deckend dunkel) für alle Player-Karten; Steuerleisten-Verlauf höher ziehen oder Titel in den dunklen Teil legen. Die Untertitel haben bereits eine HDR-Helligkeit (`SubtitleStyle.hdrBrightness`); dieselbe Idee fehlt für weiße Fokusflächen und Text der Bedienelemente.
- **Priorität:** hoch · **Sicherheit:** bestätigt (Aufbau), plausibel (sichtbare Wirkung)
- **Test:** Am Gerät mit hellem HDR-Testbild jede Karte einblenden und fotografieren.

### D-3: Zwei Designwelten – migrierte und nicht migrierte Bildschirme
- **Ort:** `V/PersonView.swift:15`–`:64`, `V/DetailViews.swift:1243`–`:1257` (Suche), `App/Sources/PlayerApp.swift:216`–`:229` (Profilwahl), `V/SyncLoginView.swift:20`–`:40`, `V/PhoneInputView.swift:97`–`:117`, `V/TorBoxFilesRow.swift:40`–`:65`, `V/Player/PostPlayCard.swift:28`–`:69`, `V/PlayerScreen.swift:494`–`:502`
- **Beobachtung:** Diese Bildschirme nutzen keine Textrolle, keine Abstands-Tokens und Systemknöpfe; Beispiel Person: `.padding(80)`, `.font(.largeTitle.bold())`, `.foregroundStyle(.secondary)`, Abstände 40/50/16. Die Detailseite daneben nutzt `textRole(.display)`, `Space.edge`, `Palette.secondary`.
- **Szenario:** Von der Detailseite (Tokens) auf eine Person wechseln → anderer Rand, andere Überschriftengröße für Abschnitte (`.title3.bold()` statt `sectionTitle`), andere Sekundärfarbe (System-`.secondary`, die `Theme.swift:190` ausdrücklich meidet).
- **Warum es inkonsistent wirkt:** Der Nutzer sieht den Bruch als „unfertig“. Zusammen mit den Player-Dateien tragen diese Bildschirme den Großteil der 308 Farb- und Größenliterale (Tabelle 1.2).
- **Empfehlung:** Diese acht Stellen als geschlossene Migrationswelle auf Rollen, `Space`, `Palette` und die drei Knopfstile umstellen; erst danach lohnt sich ein umschaltbares Theme.
- **Priorität:** hoch · **Sicherheit:** bestätigt

### D-4: Typografie hat Rollen, aber keine sichtbare Hierarchie im Lesebereich
- **Ort:** `V/Design/Theme.swift:30`–`:36`; Abweichler z. B. `V/HomeHero.swift:220`, `V/DetailViews.swift:421`, `:1407`, `V/RowViews.swift:439`, `:472`, `V/Player/PlayerSidePanel.swift:566`, `PC/Playback/TrackPanelLayout.swift:78`
- **Beobachtung:** (a) `rowTitle`, `rowTitleEmphasis` und `rowDetail` sind laut Kommentar alle 29 pt; sie unterscheiden sich nur durch Gewicht und 65 % Deckkraft. (b) Es gibt keine Rolle für Fließtext, Hinweis, Kachelbeschriftung oder Überzeile; dafür werden frei `.callout` (9×), `.caption` (22×), `.headline` (10×), `.caption2` (5×) gesetzt. (c) `.callout` ist laut Code 31 pt (`TrackPanelLayout.swift:78`), also größer als der Zeilentitel `.body` mit 29 – eine Beschreibung ist größer gesetzt als ein Titel. (d) Laufweite kommt genau zweimal vor (`tracking(1)`), Zeilenabstand nie.
- **Warum es billig wirkt:** Systemstandard ohne Abstufung. Das Zielbild „editoriale Typografie“ lebt von klaren Sprüngen (großer Titel, kleine gesperrte Überzeile, ruhiger Fließtext); heute gibt es zwischen 38 und 76 keinen genutzten Zwischenschritt und unter 38 drei fast gleiche Größen.
- **Empfehlung:** Rollen erweitern auf etwa neun: `display`, `title`, `section`, `overline` (gesperrt, Großbuchstaben), `body` (Fließtext), `row`, `rowDetail`, `caption` (Hinweis), `badge`. Größen im Token festlegen statt Textstile zu erben, Gewichte auf zwei begrenzen, freie `.font(…)`-Aufrufe verbieten.
- **Priorität:** hoch · **Sicherheit:** bestätigt (Aufbau); die absoluten Punktgrößen siehe „Am Gerät prüfen“

### D-5: Text unter 29 pt an vielen Stellen, vor allem im Player
- **Ort:** `V/PlayerScreen.swift:497`, `:522`, `:527`, `:530`, `V/Player/PlayerScrub.swift:503`, `:507`, `V/Player/PlayerPauseCard.swift:117`, `:119`, `V/DetailViews.swift:1360`, `:1361`, `V/TilePosterImage.swift:36`, `V/Player/PlayerSidePanel.swift:568`, `:576`, `V/Player/PlayerTrackPanel.swift:445`, `V/Design/ThemeBadge.swift:29`
- **Beobachtung:** `.caption` (25 pt laut `Theme.swift:25`) 22×, `.caption2` (23 pt laut `TrackPanelLayout.swift:89`) 5× plus alle Poster-Plaketten. Die längste Zeile des Players, der Bedienhinweis mit sieben Angaben, ist `.caption2` in `.secondary` (`PlayerScreen.swift:530`).
- **Szenario:** 3 m Sitzabstand, Steuerleiste eingeblendet → Bedienhinweis und Spurzeile sind die kleinsten und blassesten Texte, obwohl sie erklären, wie man bedient.
- **Warum es billig wirkt:** Kleingedrucktes am Fernseher wirkt wie eine Entwickleranzeige.
- **Empfehlung:** Untergrenze 29 pt für alles, was gelesen werden soll; 25 pt nur für Plaketten und Zeitangaben. Den Bedienhinweis kürzen oder durch Symbole ersetzen (siehe D-10).
- **Priorität:** hoch · **Sicherheit:** bestätigt (Stile), plausibel (Punktgrößen)

### D-6: Fünf verschiedene Fokus-Darstellungen
- **Ort:** `V/RowViews.swift:313` (System `.card`), `V/Design/Theme.swift:368`–`:375` (weiße Zeile 1,02), `:402`–`:408` (weißer Knopf 1,06), `V/DetailViews.swift:665` (Weiß 14 %), `V/Design/StatusCard.swift:56`, `V/Design/FocusAnchor.swift:44`, `V/Player/PostPlayCard.swift:55`, `:59`, `V/Player/SkipSegmentButton.swift:304` (Systemknopf), `App/Sources/PlayerApp.swift:229` (`.borderless`), `V/FocusHelpers.swift:24`–`:36` (nur Textfarbe)
- **Beobachtung:** Poster heben sich mit System-Parallaxe; Zeilen und Knöpfe werden vollflächig weiß mit schwarzem Text; Beschreibungstexte bekommen einen blassen Schleier; mehrere Knöpfe behalten den tvOS-Standardstil; Hinweiszeilen wechseln nur die Textfarbe. Die Besetzungskachel wird als Ganzes weiß (`ThemeTileButtonStyle`), obwohl sie ein Bild trägt.
- **Szenario:** Detailseite von oben nach unten: Beschreibung (Schleier) → „Abspielen“ (weiß, 1,06) → Besetzung (weiße Kachel um rundes Foto) → Ähnliche Titel (System-Anheben) → „Über“ (System-`.card` ohne Aktion, `DetailViews.swift:1398`).
- **Warum es inkonsistent wirkt:** Der Fokus ist das wichtigste Signal einer 10-Fuß-Oberfläche; fünf Dialekte lesen sich als zusammengesetzte Oberfläche. Vollweiß ist außerdem die hellste Fläche des Bildschirms und im Player über HDR-Bild besonders kräftig.
- **Empfehlung:** Zwei Fokusformen festlegen: „Bild“ (Anheben, Rand oder Glanz, keine Farbumkehr) und „Bedienelement“ (eine Flächenform). Systemknöpfe, `.borderless` und die fokussierbare „Über“-Karte ersetzen; Helligkeit der Fokusfläche als Token (z. B. 92 % statt 100 %), im Player eigene, gedämpfte Variante.
- **Priorität:** hoch · **Sicherheit:** bestätigt

### D-7: Detailseite ohne Bildwirkung und mit schwachem Kontrast für Sekundärtext
- **Ort:** `V/DetailViews.swift:108`, `:111`–`:131`, `:414`–`:418`
- **Beobachtung:** Das Hintergrundbild wird vollflächig mit Schwarz 55 % überzogen; kein Verlauf, kein freier Bildbereich. Der Titel steht oben links direkt auf dieser Fläche. Die Startseite hat dagegen zwei gerichtete Verläufe (`V/HomeHero.swift:144`–`:149`).
- **Szenario:** Titel mit hellem Hintergrundbild (Himmel, Schnee): Fläche wird mittelgrau. Gerechnet: Weiß darauf etwa 4,7:1, `Palette.secondary` (Weiß 65 %) etwa 3:1 – Meta-Zeile, Tagline und Hinweise liegen unter 4,5:1.
- **Warum es billig wirkt:** Das Bild ist weder wirksam (überall gleich gedämpft) noch ruhig (überall sichtbar). Apple TV, Infuse und Kaleidescape lassen das Bild an einer Seite frei und legen den Text auf einen gerichteten, fast deckenden Verlauf.
- **Empfehlung:** Bild-Tokens einführen (`scrim.hero.leading`, `scrim.hero.bottom`, `scrim.page`) und die Detailseite wie den Hero aufbauen: Bild rechts/oben frei, Textspalte links auf Verlauf ≥ 85 %.
- **Priorität:** hoch · **Sicherheit:** bestätigt (Aufbau), plausibel (Kontrastwerte gerechnet, nicht gemessen)

### D-8: Titel auf Bildkacheln ohne Abdunklung
- **Ort:** `V/RowViews.swift:457` (Querformat), `:539` (Collection), Gegenbeispiele `V/RowViews.swift:431`, `:469`, `V/CalendarView.swift:94`
- **Beobachtung:** Querformat- und Collection-Kacheln legen den Titel (`.headline`) nur mit `shadow(radius: 6)` bzw. `4` auf das Bild. Aufgeklapptes Poster, Hero-Karte und Kalender-Kachel haben einen Verlauf (75 % bzw. 85 %).
- **Szenario:** „Weiterschauen“ im Querformat mit hellem Standbild → weißer Titel mit weichem Standardschatten, schlecht lesbar; daneben steht der Fortschrittsbalken (Weiß) im selben Bereich.
- **Warum es inkonsistent wirkt:** Gleiche Aufgabe (Titel auf Bild), drei Lösungen und zwei Verlaufsstärken.
- **Empfehlung:** Ein Baustein „Bildunterschrift“ mit festem Verlauf-Token; Schatten nur als Zusatz.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-9: Schatten ohne System
- **Ort:** `V/HomeHero.swift:223`, `V/RowViews.swift:439`, `:457`, `:488`, `:539`, `:627`, `V/CalendarView.swift:99`, `:118`, `V/DetailViews.swift:647`, `V/Design/Theme.swift:150`–`:152`, `V/Player/SubtitleTextView.swift:51`
- **Beobachtung:** Zehn Schatten außerhalb der Tokens mit Radius 4, 6, 8, 12 und teils Standardfarbe. Der Hero-Schatten (Schwarz 60 %, Radius 8) liegt auf dem ganzen Info-Block und trifft damit auch das Logo-Bild und die Plakettenflächen.
- **Warum es billig wirkt:** Schatten auf gefüllten Plaketten erzeugt einen schmutzigen Hof; uneinheitliche Radien lassen Texte unterschiedlich „schweben“.
- **Empfehlung:** Zwei Schatten-Tokens (Text auf Bild, angehobene Fläche); Hero-Schatten nur auf Textzeilen, nicht auf Plaketten und Logo.
- **Priorität:** mittel · **Sicherheit:** bestätigt (Aufbau), plausibel (Hof)

### D-10: Unicode-Zeichen und Emoji statt SF Symbols
- **Ort:** `V/DetailViews.swift:144`, `:493` („▶“), `V/RowViews.swift:473` („★“), `V/PhoneInputView.swift:108` („✓“), `V/PlayerScreen.swift:530` („◀▶ … ⏯“), `V/Player/PlayerScrub.swift:506`, `PC/Services/Ratings.swift:30`, `:31` („🍅“, „🍿“ als Markenname), Gegenbeispiel `V/HomeHero.swift:275`
- **Beobachtung:** „Abspielen“ trägt auf der Startseite ein SF Symbol (`play.fill`), auf der Detailseite das Textzeichen „▶“. Rotten Tomatoes erscheint als Emoji neben der Wortmarke „IMDb“.
- **Warum es billig wirkt:** Textzeichen haben andere Strichstärke, Höhe und Grundlinie als die Schrift; Emoji sind farbig und fallen aus der einfarbigen Plakettenreihe.
- **Empfehlung:** Durchgehend `Label` mit SF Symbol; Bewertungsmarken als einfarbige Wortmarke („RT 63 %“) oder über den vorhandenen Icon-Satz.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-11: Plaketten im Player folgen nicht dem einen Plakettentyp
- **Ort:** `V/Player/PlayerInfoBadges.swift:35`–`:39`, `V/Player/PlayerSidePanel.swift:212`–`:214`, `V/Player/PlayerScrub.swift:494`–`:496`, Regel `V/Design/ThemeBadge.swift:4`–`:9`
- **Beobachtung:** `ThemeBadge` ist laut eigenem Kommentar „einziger Plakettentyp der App“ (Rechteck, Radius 8, Weiß 18 %, fett). Im Player gibt es drei weitere Formen: Kapsel Weiß 16 % normal, Kapsel Weiß 18 % halbfett, Kapsel Weiß 18 % mit `.title3`.
- **Szenario:** „4K · DV · Atmos“ sieht auf der Detailseite eckig und fett aus, in der Steuerleiste rund und dünn.
- **Empfehlung:** Player-Plaketten auf `ThemeBadge(.tech(.sources), surface: .image)` umstellen; die Formregel (Technik eckig, Status Kapsel) bleibt dann überall gültig.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-12: Radien außerhalb der drei Tokens
- **Ort:** Radius 12: `V/DetailViews.swift:646`, `:665`, `V/Player/PlayerScrub.swift:482`, `:485`, `V/Player/PostPlayCard.swift:43`, `V/Settings/SubtitleStyleSettingsRows.swift:114`; 16: `V/PersonView.swift:18`, `V/PlayerScreen.swift:247`, `V/Player/PlayerStability.swift:132`; 18: `V/Player/PlayerScrub.swift:510`; 20: `V/PlayerScreen.swift:500`, `V/SyncLoginView.swift:26`; 24: `V/Player/PlayerLoadingSteps.swift:46`, `V/PhoneInputView.swift:100`; 28: `V/Player/PostPlayCard.swift:67`
- **Beobachtung:** Tokens kennen 8/20/24; im Code stehen zusätzlich 12, 16, 18, 28. Für Vorschaubilder (Poster auf der Detailseite, Standbild, Spul-Vorschau) fehlt ein Token; das Folgen-Standbild hat gar keinen Radius (`V/DetailViews.swift:605`), das im Seitenpanel 8 (`V/Player/PlayerSidePanel.swift:564`). Mehrere Rechtecke sind nicht `continuous`.
- **Empfehlung:** Viertes Token `Radius.media` (12) und alle Karten über Video auf `overlayCard`; `style: .continuous` in einem Hilfstyp festlegen.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-13: Bewegung ohne Skala
- **Ort:** 0,15 s: `V/Design/Theme.swift:154`, `V/DetailViews.swift:666`, `V/Player/PlayerScrub.swift:517`; 0,2 s: `V/DetailViews.swift:129`, `V/QualityBadges.swift:61`, `V/Player/PlayerLoadingSteps.swift:48`; 0,22 s: `V/Player/SubtitleOverlayView.swift:68`; 0,25 s: `V/RowViews.swift:406`, `V/Player/SkipSegmentButton.swift:334`; 0,3 s: `V/HomeHero.swift:224`, `V/Player/SkipSegmentButton.swift:335`; 0,35 s: `V/Player/PlayerPauseCard.swift:47`; 0,6 s: `V/HomeHero.swift:155`; ohne Angabe: `V/PlayerScreen.swift:296`, `:323`, `:328`, `:474`, `:480`, `:581`, `:829`, `:833`
- **Beobachtung:** Acht verschiedene Dauern, `easeOut` und `easeInOut` gemischt, im Player achtmal `withAnimation {}` mit Systemstandard. Tokens gibt es nur für den Fokus. Übergänge sind fast überall reine Überblendungen; zwei Karten schieben zusätzlich herein (`V/PlayerScreen.swift:255`, `V/Player/SkipSegmentButton.swift:331`).
- **Bewertung zum Zielbild:** Nichts ist verspielt (keine Federn, kein Überschwingen). Uneinheitlich ist, dass dieselbe Art Vorgang (Karte ein-/ausblenden) zwischen 0,15 s und Systemstandard schwankt.
- **Empfehlung:** Drei Bewegungs-Tokens (`fokus` 0,15 / `einblenden` 0,25 / `szene` 0,6) mit je einer Kurve; als Preset „Bewegung: ruhig / aus“ schaltbar.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-14: Akzentfarbe ist einstellbar, aber fast überall abgeschaltet
- **Ort:** `App/Sources/PlayerApp.swift:85`, `V/HomeHero.swift:301`, `V/DetailViews.swift:171`, `:834`, `V/PersonView.swift:45`, `V/Design/Theme.swift:285`–`:287`, `V/Settings/AppearanceSettings.swift:30`, `V/RowViews.swift:638`, `:639`
- **Beobachtung:** Die Akzentfarbe wird an der Wurzel als `.tint` gesetzt und auf Startseiten-Hero, Detailseite, Quellenliste und Person mit `.tint(Color?.none)` entfernt. Gezielt genutzt wird sie nur in der Akzentmarke der Kategorieliste. Die Beschreibung der Einstellung lautet „Markierungen und Fortschrittsbalken“, die Fortschrittsbalken auf Kacheln und im Player sind aber fest weiß.
- **Szenario:** Nutzer wählt „Orange“ → sichtbar ändert sich die Marke in den Einstellungen und das, was das System einfärbt (Tab-Auswahl, `ProgressView`); Start-, Detail- und Player-Ansicht bleiben unverändert.
- **Warum es inkonsistent wirkt:** Eine Option, deren Wirkung man suchen muss, wirkt wie ein Überbleibsel.
- **Empfehlung:** Akzent als Token mit festen Einsatzorten definieren (Fortschritt, gewählter Zustand, Hauptknopf) und in den eigenen Bausteinen ausdrücklich verwenden; die Abschaltungen entfallen dann.
- **Priorität:** mittel · **Sicherheit:** bestätigt (Code), plausibel (was das System noch einfärbt)

### D-15: Ränder uneinheitlich – 60, 70, 80 und Token gemischt
- **Ort:** `V/DetailViews.swift:161` (Token 80), `V/PersonView.swift:43` (80 rundum), `V/DetailViews.swift:1246`, `:1255`, `:1257` (Suche 60/40), `:684` (Blatt 60), `V/PlayerScreen.swift:501`, `:532` (60), `V/Player/PlayerPauseCard.swift:122` (80/70), `:126` (oben 50), `V/Player/PostPlayCard.swift:68` (80/60), `V/Player/SkipSegmentButton.swift:298`, `:316` (80/80, unten 300), `App/Sources/PlayerApp.swift:82` (Uhr oben 40)
- **Beobachtung:** Der linke Inhaltsrand springt zwischen Suche (60), Detail (80) und Person (80 inklusive oben/unten). Im Player sitzen Steuerleiste (60), Pausenkarte (80) und Karte nach dem Film (80) auf verschiedenen Fluchtlinien; die Uhr steht in der App bei 40, auf der Pausenkarte bei 50 von oben.
- **Warum es inkonsistent wirkt:** Fehlende optische Ausrichtung beim Wechsel zwischen Ansichten ist am Fernseher sofort sichtbar, weil die linke Kante die Leselinie ist.
- **Empfehlung:** `Space.edge`/`edgeVertical` überall; eigener Token für den Player-Rand; Uhr an einer festen Stelle.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-16: Gleiche Maße doppelt und an der Postergröße vorbei
- **Ort:** `V/PersonView.swift:64`, `V/DetailViews.swift:1249` (Raster 6 × 240, Abstand 40/50), `V/DetailViews.swift:1375` (Abstand 40), `V/CalendarView.swift:93`, `:101` (440×248 fest; `:116` mit Faktor), `V/PersonView.swift:36`, `V/Player/PlayerPauseCard.swift:121` (1100 statt `contentMaxWidth`), `V/RowViews.swift:608` (Mindestbreite ohne Faktor), Vorbild `V/GenrePageView.swift:44`–`:54`
- **Beobachtung:** Suche und Person bauen das Posterraster mit festen 240 pt und eigenen Abständen; die Genre-Seite rechnet dasselbe Raster aus `PosterSize` und der Einstellung „Postergröße“. `PosterCard` selbst skaliert nur innerhalb von `Strip` (Standardfaktor 1, `V/RowViews.swift:653`).
- **Szenario:** Postergröße „Groß“ → Startseite und Genre-Seite zeigen 288 breite Poster, Suche, Person und „Ähnliche Titel“ weiter 240.
- **Empfehlung:** Ein Baustein „Posterraster“ (aus der Genre-Seite herausgelöst) für Suche, Person und Genre; Kalender-Kachel über `Theme.Tile`.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-17: Farbliterale mit derselben Bedeutung wie vorhandene Tokens
- **Ort:** `V/RowViews.swift:519` (Weiß 8 % = `Tile.placeholder`), `V/Player/PlayerInfoBadges.swift:39` (Weiß 16 %), `V/Player/PlayerScrub.swift:496` (Weiß 18 % = `badgeFill`), Abdunklungen: `V/DetailViews.swift:108` (55 %), `V/Player/PlayerLoadingSteps.swift:46` (55 %), `V/Player/PlayerScrub.swift:482` (60 %), `V/Player/SubtitleTextView.swift:56` (62 %), `V/RowViews.swift:431` (75 %), `V/PlayerScreen.swift:533` (80 %), `V/RowViews.swift:469` (85 %); Sekundärtext `.secondary`: `V/PlayerScreen.swift:496`, `:497`, `:511`, `:518`, `V/PersonView.swift:22`, `V/DetailViews.swift:754`, `:770`, `:1361`, `:1402`
- **Beobachtung:** Sieben Abdunklungsstufen zwischen 55 % und 95 % ohne Token; System-`.secondary` an mindestens 20 Stellen, obwohl `Theme.swift:190` begründet, warum Weiß 65 % verwendet werden soll.
- **Empfehlung:** Scrim-Skala mit drei Stufen (leicht 45 %, mittel 65 %, stark 85 %) als Tokens; `.secondary` durch `Palette.secondary` ersetzen.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-18: Fehler- und Netzmeldungen im Player als Signalflächen
- **Ort:** `V/PlayerScreen.swift:247`, `V/Player/PlayerStability.swift:129`–`:133`, `V/Player/PlaybackErrorCard.swift:11`, `V/Player/StillWatchingPrompt.swift:44`
- **Beobachtung:** Ladefehler: Text mit Präfix „Fehler:“ auf Rot 80 %, Radius 16, ohne Schriftangabe. Netz-Hinweis: Orange 85 %. `Theme.Tone` sieht dagegen Zustandsfarbe nur als Tönung mit Symbol vor (`V/Design/Theme.swift:216`–`:217`, `ThemeBadge.swift:135`). Abbruch und „Noch da?“ erscheinen als Systemdialog.
- **Warum es billig wirkt:** Vollfarbige rote und orange Kästen über dem Film sind die grellsten Elemente der App und sehen nach Entwicklungsanzeige aus; der Systemdialog bricht den eigenen Stil (die App hat mit `SettingsConfirmationView` bereits eine eigene Rückfrage).
- **Empfehlung:** Ein Baustein „Hinweis über Video“ (dunkle Fläche, Symbol in Zustandsfarbe, Rollen-Schrift); Dialoge im Player über die eigene Rückfrage-Karte.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-19: Neun bunte Kategoriefarben in den Einstellungen
- **Ort:** `V/Design/Theme.swift:264`–`:279`, `V/Design/CategoryList.swift:160`, `V/Design/SettingsRow.swift:54`
- **Beobachtung:** Jede Kategorie und jede Zeile darin trägt eine Symbolkachel in Systemblau, -violett, -cyan, -orange, -pink, -grün, -türkis, -indigo oder -grau.
- **Warum es nicht zum Zielbild passt:** Das ist die Sprache der iOS-Einstellungen. Zusammen mit der frei wählbaren Akzentfarbe stehen bis zu zehn gesättigte Farben auf einer sonst schwarz-weißen Oberfläche; „Kino-Boutique“ arbeitet mit einer Farbe oder keiner.
- **Empfehlung:** Als Preset schaltbar machen: „farbig“ (heute) und „einfarbig“ (Symbol weiß auf `Palette.row`, aktive Kategorie im Akzent). Reine Token-Änderung in `CategoryTint.color`.
- **Priorität:** mittel · **Sicherheit:** bestätigt (Aufbau); die Bewertung ist eine Gestaltungsempfehlung

### D-20: Quellenzeile ist überladen
- **Ort:** `V/DetailViews.swift:1179`–`:1213`
- **Beobachtung:** Drei Spalten: Name (330 fest, halbfett, umbrechend) mit Status-Kapsel darunter; Addon-Text in `rowDetail` ohne Zeilengrenze plus Dateiname in nochmals 75 % Deckkraft; rechts Plaketten und Addon-Name. Auf der fokussierten Zeile ergibt der Dateiname Schwarz 45 % auf Weiß, gerechnet etwa 3,4:1.
- **Szenario:** AIOStreams mit langem Formatter-Text → Zeilen von 200 pt und mehr (der Fokusstil kennt dafür eigens `rowMaxGrowth`, `V/Design/Theme.swift:122`), vier bis fünf Zeilen pro Bildschirm.
- **Warum es billig wirkt:** Die wichtigste Entscheidungsliste der App zeigt Rohtext des Addons; Infuse zeigt an dieser Stelle Auflösung, HDR, Ton und Größe als feste Spalten.
- **Empfehlung:** Als Darstellungsoption (Preset „kompakt / ausführlich“): kompakt = eine Zeile mit Plaketten in festen Spalten und Größe rechts, Addon-Text erst bei Fokus.
- **Priorität:** mittel · **Sicherheit:** bestätigt (Aufbau), plausibel (Kontrast gerechnet)

### D-21: Besetzungskachel
- **Ort:** `V/DetailViews.swift:1356`–`:1365`, `V/Design/Theme.swift:415`–`:434`
- **Beobachtung:** Rundes Foto 180 auf einer rechteckigen Fläche (Weiß 10 %, Radius 20), Name `.caption.weight(.semibold)`, Rolle `.caption2` in System-`.secondary`. Bei Fokus wird die ganze Fläche weiß; die Rolle bleibt `.secondary` (nicht `secondaryOnFocus`), weil sie die Farbe fest setzt.
- **Szenario:** Fokus auf eine Besetzungskachel → Rollenname in hellem Systemgrau auf weißer Fläche, kaum lesbar; ohne Foto steht eine Initiale in `.title` ohne Hintergrundkreis-Farbe.
- **Empfehlung:** Rundes Bild ohne Trägerfläche, Fokus als Ring oder Anheben des Bildes, Text darunter in Rollen-Schrift ≥ 29 pt mit fokusabhängiger Farbe.
- **Priorität:** mittel · **Sicherheit:** bestätigt (Farbzuweisung), plausibel (Lesbarkeit)

### D-22: Keine Knopf-Hierarchie
- **Ort:** `V/Design/Theme.swift:384`–`:410`, `V/HomeHero.swift:274`–`:283`, `V/DetailViews.swift:142`–`:152`
- **Beobachtung:** `ThemeActionButtonStyle` kennt nur „ruhend“, „gewählt“ und „fokussiert“. „Abspielen“ und „Details“ bzw. „Abspielen“ und „Trailer“ sehen in Ruhe gleich aus (Weiß auf Weiß 10 %). Der Kommentar `Theme.swift:282` nennt einen „Hauptknopf“ im Akzent, den es nicht gibt.
- **Warum es billig wirkt:** Ohne Fokus ist die wichtigste Handlung der Seite nicht erkennbar; das „wirkungsvolle Hero“ der Vorbilder lebt von einem deutlich hervorgehobenen Hauptknopf.
- **Empfehlung:** Variante `primary` (gefüllt hell oder Akzent, auch in Ruhe) und `secondary` (heutige Form); je Bildschirm genau ein primärer Knopf.
- **Priorität:** mittel · **Sicherheit:** bestätigt

### D-23: Vier Fortschrittsanzeigen
- **Ort:** `V/RowViews.swift:638`–`:642` (Kapsel 6 pt weiß), `V/DetailViews.swift:614`, `V/TorBoxFilesRow.swift:113`, `V/Player/PlayerLoadingSteps.swift:42` (System-`ProgressView`), `V/Player/PlayerScrub.swift:535`–`:549` (10 pt weiß), `V/Player/SkipSegmentButton.swift:359`–`:365` (Ring)
- **Beobachtung:** Derselbe Sachverhalt („so weit gesehen“) ist auf der Kachel ein weißer 6-pt-Balken, in der Folgenliste ein Systembalken in Systemfarbe.
- **Empfehlung:** Ein Baustein „Fortschritt“ mit zwei Höhen (Kachel 6, Player 10) und Akzentfarbe aus dem Token.
- **Priorität:** niedrig · **Sicherheit:** bestätigt

### D-24: Vier „Gesehen“-Markierungen
- **Ort:** `V/RowViews.swift:625`–`:627` (Schwarz/Weiß mit Schatten), `V/DetailViews.swift:612` (Systemgrün, Standardgröße), `V/Player/PlayerSidePanel.swift:574` (`.caption`, Textfarbe), `V/TorBoxFilesRow.swift:117` (Label „Gesehen“ in `.secondary`); vorgesehen wäre die Status-Plakette (`V/Design/ThemeBadge.swift:210`)
- **Empfehlung:** Ein Symbol-Token (Form, Größe, Farbe) für „gesehen“; Grün nur, wenn die Zustandsfarbe überall gilt.
- **Priorität:** niedrig · **Sicherheit:** bestätigt

### D-25: Profilwahl im Rohzustand
- **Ort:** `App/Sources/PlayerApp.swift:216`–`:229`
- **Beobachtung:** Kreis mit `.blue.gradient` (unabhängig von der Akzentfarbe des Profils), Initiale 90 pt, Name `.title3`, `.buttonStyle(.borderless)`, kein Hintergrund-Token.
- **Warum es billig wirkt:** Es ist der erste Bildschirm bei mehreren Profilen und der einzige mit einem Standard-Farbverlauf.
- **Empfehlung:** Mit `StatusCard.Leading.initial` und der Akzentfarbe des jeweiligen Profils bauen; `display`-Rolle für die Frage.
- **Priorität:** niedrig · **Sicherheit:** bestätigt

### D-26: Gelber Rahmen als einziges Rahmensignal
- **Ort:** `V/Home/HomeManagerView.swift:172`, `:173`
- **Beobachtung:** Eine Reihe im Verschiebe-Modus bekommt einen 6 pt starken Rahmen in `Color.yellow`. Gelb ist kein Token und kommt sonst nur als Segmentfarbe der Zeitleiste vor.
- **Empfehlung:** Zustand „wird bewegt“ über Akzent oder `Tone.warn` mit Symbol; Strichstärke als Token.
- **Priorität:** niedrig · **Sicherheit:** bestätigt

### D-27: Abstandsskala hat Lücken unterhalb von 8 und zwischen den Stufen
- **Ort:** `V/Design/Theme.swift:48`–`:56`; `Space.xs / 2`: `V/Design/ThemeBadge.swift:101`, `:108`, `V/Design/SettingsRow.swift:55`, `V/Design/StatusCard.swift:41`, `:48`, `V/CalendarView.swift:95`; Literale 2 und 4: `V/Player/PlayerSidePanel.swift:334`, `:372`, `:378`, `V/Player/PlayerTrackPanel.swift:222`, `:235`; weitere: 10, 14, 16, 18, 22, 24, 26, 28, 30, 36, 40, 50
- **Beobachtung:** Der Wert 4 wird als Rechenausdruck oder Literal geschrieben; die Panels brauchen 2. Zwischen 20 und 32 sowie 32 und 48 werden 24/26/28/30/36/40 frei gesetzt.
- **Empfehlung:** `Space.xxs` (4) ergänzen; für Dichte-Presets („kompakt / normal / luftig“) die Skala als Faktor auf einer Umgebungsgröße führen.
- **Priorität:** niedrig · **Sicherheit:** bestätigt

### D-28: Aussehens-Optionen liegen verstreut, ohne Presets und ohne Laufzeit-Theme
- **Ort:** `PC/Models/Appearance.swift:23`–`:39`, `PC/Models/SourceSettings.swift:7`–`:13`, `PC/Models/PlayerComfortSettings.swift:12`, `PC/Models/Profile.swift:48`, `V/Design/Theme.swift:7`
- **Beobachtung:** Rund 30 sichtbare Einzeloptionen in vier Strukturen (`Appearance` samt `badges` und `titles`, `SourceSettings`, `PlayerComfortSettings`, `SubtitleStyle`) und in fünf Einstellungskategorien. `Theme` ist statisch; keine Option ändert Schriftgrößen, Dichte, Radien, Flächenhelligkeit, Fokusform, Verlaufsstärke oder Bewegung.
- **Szenario:** Wunsch „Preset Kino (ruhig, einfarbig, große Bilder)“ → heute müsste der Nutzer sechs bis acht Einzelschalter in drei Kategorien umstellen; die für den Eindruck entscheidenden Größen sind gar nicht einstellbar.
- **Empfehlung:** Eine Struktur `DesignSettings` (nachsichtig dekodiert, eigenes Versionsfeld) mit wenigen Achsen – Dichte, Schriftstufe, Fokusform, Farbigkeit, Bewegung, Bildabdunklung – und `Theme` als Umgebungswert, der daraus gebaut wird. Presets sind dann benannte Wertesätze; „Eigener Stil“ wie bei den Untertiteln.
- **Priorität:** mittel · **Sicherheit:** bestätigt

---

## Teil 4 — Bestandsliste der Komponenten

| Baustein | Varianten | Ort | Token-Stand |
|---|---|---|---|
| **Poster-Kachel** `PosterCard` | normal; aufgeklappt 16:9 (`ExpandedPoster`); mit Plakettenstreifen | `V/RowViews.swift:380`, `:420` | Maße Token, Inhalt Literal |
| **Posterbild** `TilePosterImage` | Addon-Poster, TMDB-Poster, Ersatztitel | `V/TilePosterImage.swift:10` | Literal |
| **Detail-Poster** `DetailPoster` | — | `V/DetailViews.swift:641` | Literal (Radius 12, Schatten) |
| **Querformat-Kachel** `LandscapeCard` | — | `V/RowViews.swift:449` | Maße Token, Inhalt Literal |
| **Hero-Karte** `HeroCard` | — | `V/RowViews.swift:463` | gemischt |
| **Top-10-Kachel** `Top10Card` | — | `V/RowViews.swift:481` | Literal |
| **Collection-/Logo-/Paket-Kachel** `FolderTile` | Logo, Bild, Paket-Verlauf, mit Fokusvideo/GIF | `V/RowViews.swift:494` | gemischt |
| **Kalender-Kachel** `CalendarTile`, `UpcomingTodayCard` | fest / mit Faktor | `V/CalendarView.swift:87`, `:106` | Schrift Token, Maße Literal |
| **TorBox-Kachel** | Datei, „mehr“ | `V/TorBoxFilesRow.swift:38`–`:65` | Literal |
| **Besetzungskachel** | Foto / Initiale | `V/DetailViews.swift:1354`–`:1365` | Stil Token, Inhalt Literal |
| **Platzhalter / Statuskachel** `TilePlaceholder`, `TileStatus` | je Kachelform; mit Rang; „erneut laden“ | `V/RowViews.swift:563`, `:591` | Token |
| **Kachelzustand** `CardStateOverlay` | Haken, Kapsel oben, Fortschritt | `V/RowViews.swift:615` | gemischt |
| **Reihe** `HomeRowView` + `Strip` | Poster, Quer, Top 10, Logo, Collection, Hero | `V/RowViews.swift:7`, `:331` | Token |
| **Posterraster** | Genre (Token), Suche, Person (Literal) | `V/GenrePageView.swift:128`–`:148`, `V/DetailViews.swift:1249`, `V/PersonView.swift:64` | uneinheitlich |
| **Hero** `HeroLayer`, `HeroBackdrop`, `HeroInfo`, `HeroButtons` | Diashow / fokussierte Kachel | `V/HomeHero.swift:88`, `:124`, `:194`, `:260` | gemischt |
| **Plakette** `ThemeBadge` | Technik (3 Größen × 3 Untergründe, Wortmarke), Bewertung, Status (4 Töne × Bild/Fläche) | `V/Design/ThemeBadge.swift:12` | Token |
| **Plakettenzeile** `InfoBadges`, `PosterQualityBadges`, `PosterBadgeBand` | Detail, Poster oben rechts, Streifen unten | `V/DetailViews.swift:1276`, `V/QualityBadges.swift:11`, `:85` | Token |
| **Player-Plaketten** `PlayerInfoBadges`, `SidePanelHint`, Geschwindigkeits-Kapsel | — | `V/Player/PlayerInfoBadges.swift:23`, `V/Player/PlayerSidePanel.swift:205`, `V/Player/PlayerScrub.swift:494` | Literal |
| **Meta-Zeile** `MetaLine` | — | `V/Design/ThemeBadge.swift:179` | Token |
| **Aktionsknopf** `ThemeActionButtonStyle` | ruhend, gewählt, fokussiert, gedrückt | `V/Design/Theme.swift:384` | Token |
| **Zeilenknopf** `ThemeRowButtonStyle` | Standard; Kategorie (72); Panel (klar, eng); Chip (260); hohe Zeile (`maxFocusGrowth`) | `V/Design/Theme.swift:331`, `V/Player/PlayerSidePanel.swift:552`, `:557` | Token |
| **Kachelknopf** `ThemeTileButtonStyle` | — | `V/Design/Theme.swift:415` | Token |
| **Systemknöpfe** | `.card`, `.plain` + `FocusHighlight`, `.borderless`, Standard | `V/RowViews.swift:313`, `V/DetailViews.swift:422`, `:659`, `App/Sources/PlayerApp.swift:229`, `V/Design/StatusCard.swift:56` | System |
| **Fokusanker** `FocusAnchor`, `quietFocusTarget` | Fertig / Zurück; unsichtbares Ziel | `V/Design/FocusAnchor.swift:7`, `V/FocusHelpers.swift:8` | gemischt |
| **Einstellungszeile** `SettingsRow`, `SettingsToggleRow`, `SettingsRowLabel` | ohne / Chevron / Wert / Wert + Chevron / An-Aus | `V/Design/SettingsRow.swift:40`, `:85`, `:107` | Token |
| **Einstellungs-Bausteine** | `SettingsPage`, `CategoryPage`, `SettingsSubpage`, `SettingsSection`, `SettingsFootnote`, `SettingsLinkRow`, `PhoneLinkRow`, `SettingsChoiceRow`, `SettingsChoicePage`, `SettingsInfoRow` | `V/Settings/SettingsKit.swift:9`, `:61`, `:78`, `:98`, `:116`, `:132`, `:156`, `:176`, `:225`, `:260` | Token |
| **Kopf / Abschnitt** `SettingsHeader`, `SettingsSectionLabel`, `CategoryGroupHeader` | — | `V/Design/SettingsRow.swift:141`, `:160`, `V/Design/CategoryList.swift:126` | Token |
| **Zweispaltige Liste** `CategoryList` | mit / ohne Kopf, Gruppen | `V/Design/CategoryList.swift:33` | Token |
| **Symbolkachel** `IconTile` | 9 Farben | `V/Design/Theme.swift:438` | Token |
| **Statuskarte** `StatusCard` | Initiale / Symbol, 0–3 Kennzahlen, Aktion | `V/Design/StatusCard.swift:7` | Token |
| **Rückfrage** `SettingsConfirmationView` | — | `V/Settings/SettingsKit.swift:278` | Token |
| **Systemdialoge** | `alert`, `sheet`, `fullScreenCover` | `App/Sources/PlayerApp.swift:88`, `V/Player/PlaybackErrorCard.swift:11`, `V/Player/StillWatchingPrompt.swift:44`, `V/PersonView.swift:46`, `V/DetailViews.swift:306`, `:307` | System |
| **Quellenzeile** `StreamRow`, `SourceFilterBar`, `StreamListSummaryLine` | mit / ohne Addon, fehlgeschlagen | `V/DetailViews.swift:1169`, `:1219`, `V/SourceFilterBar.swift:6` | Token |
| **Folgenzeile** | gesehen / Fortschritt / Spoilerschutz | `V/DetailViews.swift:601`–`:622` | gemischt |
| **Verwalterzeile** `ManagedRowLine`, `PositionPicker`, `CatalogEntryRow` | normal, neu, wird bewegt | `V/Home/HomeManagerView.swift:287`, `:318`, `V/Home/AddRowBrowser.swift:232` | Token |
| **Player-Steuerleiste** | Titel, Plaketten, Zeitleiste, Hinweise | `V/PlayerScreen.swift:505`–`:534` | Literal |
| **Zeitleiste** `PlayerTimeline` | normal / beim Spulen, Segmentmarken | `V/Player/PlayerScrub.swift:522` | Literal |
| **Spul-Vorschau** `ScrubPreviewCard` | mit / ohne Bild, Schnellsuchlauf | `V/Player/PlayerScrub.swift:469` | Literal |
| **Spur-Leiste / Spur-Menü** `PlayerTrackPanel`, `PlayerTrackMenu` | oben, unten, Menü | `V/Player/PlayerTrackPanel.swift:116`, `:280` | Token |
| **Seitenpanel** `PlayerSidePanel`, `SideRowLabel` | Folgen, Kapitel, Quellen, Infos | `V/Player/PlayerSidePanel.swift:232`, `:537` | gemischt |
| **Karten über Video** | „Nächste Folge“, `PostPlayCard`, Überspringen, Szenen-Hinweis, `PlayerLoadingSteps`, `PlayerNetworkBanner`, Fehlertext, `PlayerPauseCard` | `V/PlayerScreen.swift:493`, `V/Player/PostPlayCard.swift:27`, `V/Player/SkipSegmentButton.swift:290`, `V/Player/PlayerLoadingSteps.swift:28`, `V/Player/PlayerStability.swift:123`, `V/PlayerScreen.swift:247`, `V/Player/PlayerPauseCard.swift:92` | Literal |
| **Untertitel** `SubtitleTextView`, `SubtitleOverlayView`, `SubtitleStylePreview` | 4 Größen × 4 Lagen × 4 Umrisse × 3 Hintergründe | `V/Player/SubtitleTextView.swift:28`, `V/Player/SubtitleOverlayView.swift:19`, `V/Settings/SubtitleStyleSettingsRows.swift:83` | Einstellung |
| **Uhr** `ClockView` | App, Pausenkarte | `V/ClockView.swift:4` | Literal |
| **Spoilerschutz** `spoilerMark` | — | `V/SpoilerBlur.swift:12` | Literal |
| **QR-Seiten** | Handy-Eingabe, Dienst-Anmeldung | `V/PhoneInputView.swift:97`, `V/SyncLoginView.swift:20` | Literal |
| **Profilwahl** `ProfilePickerView` | — | `App/Sources/PlayerApp.swift:212` | Literal |

---

## Am Gerät prüfen

1. **Tatsächliche Punktgrößen der Textstile.** Die Kommentare in `V/Design/Theme.swift:13`–`:25` nennen title2 = 48, title3 = 38, headline = 29, subheadline = 29. Die tvOS-Typografietabelle von Apple führt eine Stufe versetzt (Title 3 = 48, Headline = 38, Body = 29, Callout = 31, Caption 1 = 25, Caption 2 = 23). Stimmt die Tabelle, wäre `rowDetail` (`.subheadline`) größer als `rowTitle` (`.body`). Mit einem Bildschirmfoto der Token-Vorschau (`Theme.swift:453`) messen.
2. **Sichtbarer Seitenrand.** Inhalte liegen in der sicheren Fläche und bekommen zusätzlich `Space.edge` (80). Prüfen, ob Reihentitel, Detailtext und Einstellungen bei 80 oder 160 pt vom Rand beginnen und ob Player-Steuerleiste (60) und Pausenkarte (80) auf derselben Linie stehen.
3. **Kontrast auf hellen Bildern.** Detailseite, Querformat-Kacheln und alle Player-Karten mit einem hellen und einem HDR-Testbild fotografieren (D-2, D-7, D-8).
4. **Weiße Fokusfläche bei HDR-Ausgabe.** Helligkeit der fokussierten Zeile in Spur-Leiste und Seitenpanel während Dolby-Vision-Wiedergabe beurteilen (D-6).
5. **Wirkung der Akzentfarbe.** Je Akzentfarbe festhalten, welche Elemente sich tatsächlich färben (Tab-Leiste, Seitenleiste, `ProgressView`), siehe D-14.
6. **System-`.card` neben eigenen Stilen.** Anheben und Neigung der Poster gegen das starre 1,06-Anheben der Knöpfe und Besetzungskacheln vergleichen (D-6); `Focus.cardLiftScale` 1,15 ist eine Schätzung (`Theme.swift:126`–`:129`).
7. **Schatten im Hero.** Prüfen, ob um Plaketten und Logo ein dunkler Hof sichtbar ist (D-9).
