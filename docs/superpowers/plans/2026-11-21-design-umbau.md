# Design-Umbau (im Stil gängiger tvOS-Streaming-Apps) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Umbau von Navigation, Startseite, Einstellungen und Aussehen im Stil gängiger tvOS-Streaming-Apps. Dazu zwei neue Tabs: Bibliothek und Kalender.

**Architecture:**
- Navigation und Einstellungen nutzen SwiftUI-Systembausteine:
  - `TabView` mit `Tab(…, systemImage:)`, wahlweise `.sidebarAdaptable`;
  - die Einstellungen als Kategorienliste links mit Detailbereich rechts.
- Hero mit Info-Ebene, Hintergrund nach Fokus und aufklappende Poster sind eigene Komponenten.
- Testbare Logik kommt nach PlayerCore: Appearance-Defaults, Hero-Quellwahl, Kalender-Gruppierung, Verlauf.

**Tech Stack:** Swift 6.2, SwiftUI tvOS 18, Swift Testing (Podman `swift:6.2`), GitHub Actions + `atv_install.mjs`.

**Spec:** `docs/superpowers/specs/2026-11-21-design-umbau-design.md`

## Global Constraints

- Mindestversion: tvOS 18.0. Das Repo ist öffentlich: keine Schlüssel, keine Namen, keine IPs.
- Neue Profilfelder bekommen Standardwerte in `Profile.init(from:)`; ältere Sicherungen müssen weiter laden.
- Bilder ausschließlich über `RemoteImage` / `ImagePipeline`.
- Kerntests: `cd Packages/PlayerCore && podman run --rm -v "$PWD":/pkg:Z -w /pkg docker.io/library/swift:6.2 swift test`.
  Zum Start sind 86 Tests grün.
- Ein Build pro Phase.
  - Push nur mit `git -C ~/tvos_player/app push`.
  - Commit-Identität `haskoman-beep`, mit den Trailer-Zeilen „Co-Authored-By“ und „Claude-Session“.
- Die Oberfläche ist auf Deutsch.

## Review Focus

1. Alte Profile ohne `appearance`: die App startet, die Startseite ist unverändert, eine vorhandene `.hero`-Reihe wird zur Hero-Quelle. Test: Task 1.
2. Leere Startseite oder keine Katalog-Reihe: es gibt keinen Hero und keinen Absturz. Test: Task 1 (`heroSource` → nil).
3. Fokus wechselt schnell über viele Poster: weder Hintergrund noch Aufklappen laden pro Zwischenschritt. Umsetzung über
   350 ms Entprellung (Task 3/4). Am Gerät mit der Log-Zeile „hero: Fokus-Hintergrund“ prüfen, höchstens eine pro Ruhepause.
4. Serie ohne kommende Folgen oder TMDB ohne Treffer: der Kalender lässt sie aus und zeigt eine leere Meldung statt eines Fehlers. Test: Task 5.
5. Fokus aus der ersten Reihe nach oben muss im Hero-Knopf landen, nicht in der Seitenleiste. Prüfung am Gerät (Task 3).

---

### Task 1: Appearance-Modell + Hero-Quelle (PlayerCore)

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift`
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift` (Feld + CodingKey + decodeIfPresent)
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift` (`SourceKind.upcoming`, `CatalogSource.upcoming`)
- Test: `Packages/PlayerCore/Tests/PlayerCoreTests/AppearanceTests.swift`

**Interfaces (Produces):**
- `enum NavigationStyle: String, Codable { case sidebar, top }`
- `enum AccentChoice: String, Codable, CaseIterable { case blue, purple, pink, orange, green, white }`
- `enum CardSize: String, Codable, CaseIterable { case small, medium, large }`, mit `var scale: CGFloat` = 0.85 / 1.0 / 1.2.
- `struct Appearance: Codable, Sendable, Hashable` mit:
  - `navigation = .sidebar`, `accent = .blue`, `cardSize = .medium`;
  - `heroEnabled = true`, `heroRowID: UUID? = nil`, `expandPosters = true`;
  - einem eigenen `init(from:)`, das fehlende Felder mit Standardwerten füllt.
- `Profile.appearance: Appearance`
- `extension HomeLayout { func heroSource(_ a: Appearance) -> HomeRow? }`. Reihenfolge:
  1. die Reihe mit `a.heroRowID`, falls vorhanden;
  2. sonst die erste Reihe mit `style == .hero`;
  3. sonst die erste `.list`-Reihe, die nicht `continueWatching` ist;
  4. sonst nil. Ist `heroEnabled == false`, ebenfalls nil.
- `extension HomeLayout { func rowsBelowHero(_ a: Appearance) -> [HomeRow] }` gibt alle Reihen zurück außer einer `.hero`-Reihe,
  die die Hero-Quelle ist.
- `SourceKind.upcoming`, `CatalogSource.upcoming = CatalogSource(id: "builtin.upcoming", title: "Heute neu", kind: .upcoming, mediaType: .series)`.

- [ ] **Step 1: Tests schreiben**
  - `appearanceDefaultsFromOldProfile`: Profil-JSON ohne `appearance` dekodieren, dann `navigation == .sidebar` und `heroEnabled`.
  - `heroSourcePrefersExplicitThenHeroStyleThenFirstList`: drei Layouts, erwartete Reihen-IDs.
  - `heroSourceNilWhenDisabledOrNoList`: liefert nil.
  - `rowsBelowHeroHidesHeroStyleRow`.
- [ ] **Step 2:** Tests laufen lassen. Erwartet: Kompilierfehler, weil `Appearance` fehlt.
- [ ] **Step 3:** Implementieren wie unter Interfaces beschrieben. `AppModel` behandelt `.upcoming` vorerst mit `[]`;
  Task 5 füllt das später.
- [ ] **Step 4:** Tests laufen lassen. Erwartet: alle grün (86 + 4).
- [ ] **Step 5: Commit** mit der Nachricht „Aussehen-Einstellungen im Profil, Hero-Quelle“.

### Task 2: Navigation + Einstellungs-Kategorien (App) → Build 23

**Files:**
- Modify: `App/Sources/PlayerApp.swift` (`RootView`)
- Create: `App/Sources/Views/ClockView.swift`
- Replace: `App/Sources/Views/SettingsView.swift` durch eine Kategorien-Ansicht
- Create: `App/Sources/Views/Settings/` mit den Dateien `ProfileSettings.swift`, `AddonSettings.swift`, `ServiceSettings.swift`,
  `HomeSettings.swift`, `AppearanceSettings.swift`, `PlaybackSettings.swift`, `AboutSettings.swift`
- Create: `App/Sources/Views/LibraryView.swift` und `CalendarView.swift`, zunächst als Platzhalter mit „Kommt in Build 26“

**Interfaces (Consumes):** `Profile.appearance` aus Task 1.

- [ ] **Step 1: `RootView`**
  - `TabView(selection: $tab)` mit `enum AppTab { home, search, library, calendar, settings }`.
  - Symbole: `house`, `magnifyingglass`, `books.vertical`, `calendar`, `gearshape`.
  - Ist `appearance.navigation == .sidebar`, kommt `.tabViewStyle(.sidebarAdaptable)` dazu. Sonst bleibt die Standard-Leiste
    und `ClockView` liegt als Overlay oben rechts (Format `HH:mm`, `TimelineView(.everyMinute)`).
  - Jeder Tab behält einen eigenen `NavigationPath` mit `.environment(\.navigate)`, wie heute.
  - Akzentfarbe: `.tint(appearance.accent.color)`.
- [ ] **Step 2: Einstellungen**
  - Linke Liste mit 7 Kategorien und Symbolen: `person.crop.circle`, `puzzlepiece`, `key`, `house`, `paintpalette`,
    `play.circle`, `info.circle`.
  - Das Fokussieren einer Kategorie zeigt rechts deren Inhalt.
  - Die bisherigen Einträge ziehen 1:1 in die jeweilige Kategorie um. Der QR-Eintrag liegt unter „Dienste“ und zusätzlich ganz oben.
  - „Aussehen“: Picker für Navigation, Akzentfarbe (6 Farbkreise) und Kartengröße; Toggles für Hero, Poster aufklappen.
    Hero-Quelle als Picker über die `.list`-Reihen.
  - „Über“: Version, Anzahl der Addons, Log-Hinweis.
- [ ] **Step 3:** Commit mit der Nachricht „Seitenleiste/obere Leiste mit Uhr, Einstellungen in Kategorien“. Danach pushen
  und mit dem Watcher Build 23 bauen und installieren.
- [ ] **Step 4: Am Gerät prüfen**
  - Beide Navigationsarten.
  - Zurück-Taste aus einem Tab.
  - Jede Einstellungs-Kategorie öffnet.

### Task 3: Hero mit Info-Ebene + Diashow (App) → Build 24

**Files:**
- Create: `App/Sources/Views/HomeHero.swift`
- Modify: `App/Sources/Views/HomeView.swift`, `RowViews.swift` (Fokus-Rückmeldung von den Kacheln)
- Modify: `App/Sources/AppModel.swift` (`heroItems(for row:) async -> [MetaPreview]`, nutzt den vorhandenen Reihen-Loader,
  höchstens 8 Einträge)

**Interfaces:**
- `@Observable final class HomeFocus { var item: MetaPreview?; var inRows: Bool }`, als Environment-Objekt in `HomeView`.
- Kacheln melden ihren Fokus über `.onFocusChange { if $0 { focus.set(item) } }`. `set` entprellt 350 ms per `Task`, ein neuer
  Fokus bricht die Wartezeit ab. Danach eine Log-Zeile `hero: Fokus-Hintergrund <id>`.

- [ ] **Step 1: Aufbau von `HomeView`**
  - Ein `ZStack`.
  - Hinten die Ebene `HeroBackdrop`: Vollbild-Hintergrund des angezeigten Titels, Überblendung 0,6 s, Verlauf unten und links.
  - Darüber `HeroInfo`:
    - Logo (`localized.logo`, sonst Name);
    - Metazeile Jahr · Laufzeit · FSK;
    - `InfoBadges` mit den Bewertungen;
    - Beschreibung in 2 Zeilen.
  - Darüber der `ScrollView` mit Abstand oben (ca. 560 pt), darin:
    - zuerst die Knopfzeile `[▶ Abspielen] [Details]` mit Diashow-Punkten;
    - danach die Reihen aus `rowsBelowHero`.
  - Angezeigter Titel: `focus.inRows ? focus.item : slides[index]`.
  - Diashow: Timer alle 10 s, nur wenn `!focus.inRows`.
- [ ] **Step 2: „Abspielen“** wiederholt die Weiterschauen-Logik aus `DetailView`.
  - Film: `PlayRequest(…, resumeLastSource: true)`.
  - Serie: die nächste offene Folge per `NextEpisode`, sonst S1F1. Die Metadaten werden erst beim Druck geladen.
  - Den vorhandenen Code in eine gemeinsame Funktion `AppModel.quickPlayRequest(for:) async -> PlayRequest?` ziehen.
- [ ] **Step 3:** Die alte `HeroCard`-Reihe wird nur noch angezeigt, wenn sie nicht die Hero-Quelle ist.
- [ ] **Step 4:** Commit mit der Nachricht „Startseite: Hero-Diashow, Info folgt dem Fokus“. Push, Build 24.
- [ ] **Step 5: Am Gerät prüfen**
  - Fokus wandert von der Reihe nach oben → landet auf dem Abspielen-Knopf.
  - Die Diashow pausiert, solange der Fokus in den Reihen liegt.
  - Pro Ruhepause erscheint höchstens eine Log-Zeile.

### Task 4: Poster aufklappen + Kartengröße (App) → Build 25

**Files:** Modify `App/Sources/Views/RowViews.swift` (`PosterCard`, `LandscapeCard`, Reihenabstände)

- [ ] **Step 1: `PosterCard`**
  - Bei Fokus, 350 ms Ruhe und `expandPosters`: die Breite wächst animiert (0,25 s) von Poster- auf Querformat (16:9, gleiche Höhe).
  - Gezeigt werden Hintergrundbild und Logo. Das Bild wird erst nach der Ruhezeit angefordert.
  - Die Reihe scrollt mit `scrollPosition`, verankert am fokussierten Element.
- [ ] **Step 2:** `cardSize.scale` auf die Kartenmaße aller Reihenstile anwenden.
- [ ] **Step 3:** Commit, Push, Build 25.
- [ ] **Step 4: Am Gerät prüfen**
  - Schnelles Durchscrollen klappt nichts auf.
  - Die Reihe springt nicht.

### Task 5: Bibliothek + Kalender + „Heute neu“ → Build 26

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift`
- Modify: `TMDBLocalized.swift` (`nextEpisodes(tmdbID:) -> [UpcomingEpisode]` über `/tv/{id}`:
  `next_episode_to_air` plus die Folgen der laufenden Staffel)
- Modify: `WatchProgress.swift` (`history(limit:) -> [WatchProgress]`)
- Modify: `App/Sources/Views/LibraryView.swift`, `CalendarView.swift`, `AppModel.swift`
- Test: `Packages/PlayerCore/Tests/PlayerCoreTests/UpcomingTests.swift`

**Interfaces (Produces):**
- `struct UpcomingEpisode: Sendable, Hashable` mit den Feldern:
  - `seriesID: String`, `seriesName: String`, `poster: String?`;
  - `season: Int`, `episode: Int`, `title: String?`, `airDate: String` (YYYY-MM-DD).
- `enum Upcoming`:
  - `static func days(_ eps: [UpcomingEpisode], today: Date, calendar: Calendar) -> [(label: String, items: [UpcomingEpisode])]`
    - Bereich: gestern bis heute + 14 Tage.
    - Labels: „Gestern“, „Heute“, „Morgen“, sonst „Mi 26.11.“.
    - Innerhalb eines Tages nach Serienname sortiert.
  - `static func seriesIDs(continueWatching: [WatchProgress], watchlist: [MetaPreview], limit: Int = 50) -> [String]`
    - nur Serien; ohne Duplikate; Weiterschauen zuerst.
- `ProgressBook.history(limit:)`: Einträge mit `finished == true`, absteigend nach `updated`.

- [ ] **Step 1: Tests**
  - `upcomingGroupsYesterdayTodayTomorrowDate`
  - `upcomingDropsOutOfRange`
  - `seriesIDsDedupContinueFirstLimit`
  - `historyFinishedNewestFirst`
  - `parseNextEpisodes` (JSON mit `next_episode_to_air` und leerem Fall)
- [ ] **Step 2:** Tests laufen lassen. Erwartet: Kompilierfehler.
- [ ] **Step 3: Implementieren**
  - `AppModel.upcoming() async -> [UpcomingEpisode]` geht über `seriesIDs` und `tmdbID` und ruft dann `nextEpisodes` auf.
  - Höchstens 4 Anfragen gleichzeitig. Cache 6 h im Speicher.
  - `.upcoming` in der Reihe zeigt die Einträge von heute als Kacheln (Serie, Folge als Label).
- [ ] **Step 4:** Tests laufen lassen. Erwartet: alle grün.
- [ ] **Step 5: Ansichten**
  - `LibraryView` hat drei Reihen: Weiterschauen, Merkliste, Verlauf, mit vorhandenen Kartenkomponenten.
  - `CalendarView` zeigt Tagesabschnitte mit Querformat-Kacheln (Still bzw. Poster, „S2 F5 · Titel“). Ein Klick öffnet die Detailseite.
  - Leerer Zustand: „Keine neuen Folgen in den nächsten 14 Tagen“.
  - `AddRowSheet` bietet zusätzlich `.upcoming` an.
- [ ] **Step 6:** Commit mit der Nachricht „Bibliothek, Kalender, Reihe ‚Heute neu‘“. Push, Build 26, am Gerät prüfen.

### Task 6: Abschluss

- [ ] `SITZUNG_UEBERGABE.md`: neuen Abschnitt „## STAND …“ vor „## Startprompt“ einfügen.
- [ ] Eine Prüfung des gesamten Zweigs mit einem frischen Reviewer (Opus).
