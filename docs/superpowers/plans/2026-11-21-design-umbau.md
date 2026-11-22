# Design Rework (in the style of common tvOS streaming apps) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework navigation, home screen, settings and appearance in the style of common tvOS streaming apps. Plus two new tabs: library and calendar.

**Architecture:**
- Navigation and settings use SwiftUI system building blocks:
  - `TabView` with `Tab(…, systemImage:)`, optionally `.sidebarAdaptable`;
  - the settings as a category list on the left with a detail area on the right.
- The hero with its info layer, the background that follows the focus and the expanding posters are custom components.
- Testable logic goes into PlayerCore: appearance defaults, hero source choice, calendar grouping, history.

**Tech Stack:** Swift 6.2, SwiftUI tvOS 18, Swift Testing (Podman `swift:6.2`), GitHub Actions + `atv_install.mjs`.

**Spec:** `docs/superpowers/specs/2026-11-21-design-umbau-design.md`

## Global Constraints

- Minimum version: tvOS 18.0. The repo is public: no keys, no names, no IPs.
- New profile fields get default values in `Profile.init(from:)`; older backups must still load.
- Images only via `RemoteImage` / `ImagePipeline`.
- Core tests: `cd Packages/PlayerCore && podman run --rm -v "$PWD":/pkg:Z -w /pkg docker.io/library/swift:6.2 swift test`.
  86 tests are green at the start.
- One build per phase.
  - Push only with `git -C ~/tvos_player/app push`.
  - Commit identity `haskoman-beep`, with the trailer lines "Co-Authored-By" and "Claude-Session".
- The interface is in German.

## Review Focus

1. Old profiles without `appearance`: the app starts, the home screen is unchanged, an existing `.hero` row becomes the hero source. Test: Task 1.
2. Empty home screen or no catalog row: there is no hero and no crash. Test: Task 1 (`heroSource` → nil).
3. Focus moves quickly across many posters: neither the background nor the expansion loads for every intermediate step.
   Implemented with a 350 ms debounce (Task 3/4). Check on the device with the log line „hero: Fokus-Hintergrund“ (focus
   background): at most one per rest period.
4. A series without upcoming episodes or TMDB without a match: the calendar leaves it out and shows an empty message instead of an error. Test: Task 5.
5. Focus moving up from the first row must land on the hero button, not in the sidebar. Check on the device (Task 3).

---

### Task 1: Appearance model + hero source (PlayerCore)

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift`
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift` (field + CodingKey + decodeIfPresent)
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift` (`SourceKind.upcoming`, `CatalogSource.upcoming`)
- Test: `Packages/PlayerCore/Tests/PlayerCoreTests/AppearanceTests.swift`

**Interfaces (Produces):**
- `enum NavigationStyle: String, Codable { case sidebar, top }`
- `enum AccentChoice: String, Codable, CaseIterable { case blue, purple, pink, orange, green, white }`
- `enum CardSize: String, Codable, CaseIterable { case small, medium, large }`, with `var scale: CGFloat` = 0.85 / 1.0 / 1.2.
- `struct Appearance: Codable, Sendable, Hashable` with:
  - `navigation = .sidebar`, `accent = .blue`, `cardSize = .medium`;
  - `heroEnabled = true`, `heroRowID: UUID? = nil`, `expandPosters = true`;
  - its own `init(from:)` that fills missing fields with default values.
- `Profile.appearance: Appearance`
- `extension HomeLayout { func heroSource(_ a: Appearance) -> HomeRow? }`. Order:
  1. the row with `a.heroRowID`, if present;
  2. otherwise the first row with `style == .hero`;
  3. otherwise the first `.list` row that is not `continueWatching`;
  4. otherwise nil. If `heroEnabled == false`, also nil.
- `extension HomeLayout { func rowsBelowHero(_ a: Appearance) -> [HomeRow] }` returns all rows except a `.hero` row that is
  the hero source.
- `SourceKind.upcoming`, `CatalogSource.upcoming = CatalogSource(id: "builtin.upcoming", title: "Heute neu", kind: .upcoming, mediaType: .series)` („Heute neu“ = new today).

- [ ] **Step 1: Write the tests**
  - `appearanceDefaultsFromOldProfile`: decode profile JSON without `appearance`, then `navigation == .sidebar` and `heroEnabled`.
  - `heroSourcePrefersExplicitThenHeroStyleThenFirstList`: three layouts, expected row IDs.
  - `heroSourceNilWhenDisabledOrNoList`: returns nil.
  - `rowsBelowHeroHidesHeroStyleRow`.
- [ ] **Step 2:** Run the tests. Expected: compile error, because `Appearance` is missing.
- [ ] **Step 3:** Implement as described under Interfaces. `AppModel` handles `.upcoming` with `[]` for now;
  Task 5 fills it in later.
- [ ] **Step 4:** Run the tests. Expected: all green (86 + 4).
- [ ] **Step 5: Commit** with the message „Aussehen-Einstellungen im Profil, Hero-Quelle“ (appearance settings in the profile, hero source).

### Task 2: Navigation + settings categories (app) → build 23

**Files:**
- Modify: `App/Sources/PlayerApp.swift` (`RootView`)
- Create: `App/Sources/Views/ClockView.swift`
- Replace: `App/Sources/Views/SettingsView.swift` with a category view
- Create: `App/Sources/Views/Settings/` with the files `ProfileSettings.swift`, `AddonSettings.swift`, `ServiceSettings.swift`,
  `HomeSettings.swift`, `AppearanceSettings.swift`, `PlaybackSettings.swift`, `AboutSettings.swift`
- Create: `App/Sources/Views/LibraryView.swift` and `CalendarView.swift`, at first as placeholders with „Kommt in Build 26“ (coming in build 26)

**Interfaces (Consumes):** `Profile.appearance` from Task 1.

- [ ] **Step 1: `RootView`**
  - `TabView(selection: $tab)` with `enum AppTab { home, search, library, calendar, settings }`.
  - Symbols: `house`, `magnifyingglass`, `books.vertical`, `calendar`, `gearshape`.
  - If `appearance.navigation == .sidebar`, `.tabViewStyle(.sidebarAdaptable)` is added. Otherwise the standard bar stays
    and `ClockView` sits as an overlay at the top right (format `HH:mm`, `TimelineView(.everyMinute)`).
  - Each tab keeps its own `NavigationPath` with `.environment(\.navigate)`, as today.
  - Accent colour: `.tint(appearance.accent.color)`.
- [ ] **Step 2: Settings**
  - A list on the left with 7 categories and symbols: `person.crop.circle`, `puzzlepiece`, `key`, `house`, `paintpalette`,
    `play.circle`, `info.circle`.
  - Focusing a category shows its content on the right.
  - The existing entries move 1:1 into their category. The QR entry sits under „Dienste“ (services) and also at the very top.
  - „Aussehen“ (appearance): pickers for navigation, accent colour (6 colour circles) and card size; toggles for the hero
    and for expanding posters. The hero source is a picker over the `.list` rows.
  - „Über“ (about): version, number of addons, log hint.
- [ ] **Step 3:** Commit with the message „Seitenleiste/obere Leiste mit Uhr, Einstellungen in Kategorien“ (sidebar/top bar
  with clock, settings in categories). Then push, and build and install build 23 with the watcher.
- [ ] **Step 4: Check on the device**
  - Both navigation styles.
  - The back button from a tab.
  - Every settings category opens.

### Task 3: Hero with info layer + slideshow (app) → build 24

**Files:**
- Create: `App/Sources/Views/HomeHero.swift`
- Modify: `App/Sources/Views/HomeView.swift`, `RowViews.swift` (focus reporting from the tiles)
- Modify: `App/Sources/AppModel.swift` (`heroItems(for row:) async -> [MetaPreview]`, uses the existing row loader,
  at most 8 entries)

**Interfaces:**
- `@Observable final class HomeFocus { var item: MetaPreview?; var inRows: Bool }`, as an environment object in `HomeView`.
- Tiles report their focus via `.onFocusChange { if $0 { focus.set(item) } }`. `set` debounces 350 ms with a `Task`; a new
  focus cancels the wait. After that, a log line `hero: Fokus-Hintergrund <id>` (focus background).

- [ ] **Step 1: Structure of `HomeView`**
  - A `ZStack`.
  - At the back, the layer `HeroBackdrop`: full-screen background of the shown title, 0.6 s cross-fade, gradient at the
    bottom and left.
  - Above it, `HeroInfo`:
    - logo (`localized.logo`, otherwise the name);
    - meta line year · runtime · FSK age rating;
    - `InfoBadges` with the ratings;
    - the description in 2 lines.
  - Above that, the `ScrollView` with a top inset (about 560 pt), containing:
    - first the button row `[▶ Abspielen] [Details]` (play, details) with slideshow dots;
    - then the rows from `rowsBelowHero`.
  - Shown title: `focus.inRows ? focus.item : slides[index]`.
  - Slideshow: a timer every 10 s, only when `!focus.inRows`.
- [ ] **Step 2: „Abspielen“ (play)** repeats the continue watching logic from `DetailView`.
  - Movie: `PlayRequest(…, resumeLastSource: true)`.
  - Series: the next open episode via `NextEpisode`, otherwise S1E1. The metadata is only loaded on the press.
  - Move the existing code into a shared function `AppModel.quickPlayRequest(for:) async -> PlayRequest?`.
- [ ] **Step 3:** The old `HeroCard` row is only shown when it is not the hero source.
- [ ] **Step 4:** Commit with the message „Startseite: Hero-Diashow, Info folgt dem Fokus“ (home screen: hero slideshow,
  info follows the focus). Push, build 24.
- [ ] **Step 5: Check on the device**
  - Focus moving up from the row → lands on the play button.
  - The slideshow pauses while the focus is in the rows.
  - At most one log line appears per rest period.

### Task 4: Expand posters + card size (app) → build 25

**Files:** Modify `App/Sources/Views/RowViews.swift` (`PosterCard`, `LandscapeCard`, row spacing)

- [ ] **Step 1: `PosterCard`**
  - On focus, after 350 ms of rest and with `expandPosters`: the width grows animated (0.25 s) from poster to landscape
    (16:9, same height).
  - The background image and logo are shown. The image is only requested after the rest period.
  - The row scrolls with `scrollPosition`, anchored on the focused element.
- [ ] **Step 2:** Apply `cardSize.scale` to the card sizes of all row styles.
- [ ] **Step 3:** Commit, push, build 25.
- [ ] **Step 4: Check on the device**
  - Scrolling through quickly expands nothing.
  - The row does not jump.

### Task 5: Library + calendar + „Heute neu“ (new today) → build 26

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift`
- Modify: `TMDBLocalized.swift` (`nextEpisodes(tmdbID:) -> [UpcomingEpisode]` via `/tv/{id}`:
  `next_episode_to_air` plus the episodes of the current season)
- Modify: `WatchProgress.swift` (`history(limit:) -> [WatchProgress]`)
- Modify: `App/Sources/Views/LibraryView.swift`, `CalendarView.swift`, `AppModel.swift`
- Test: `Packages/PlayerCore/Tests/PlayerCoreTests/UpcomingTests.swift`

**Interfaces (Produces):**
- `struct UpcomingEpisode: Sendable, Hashable` with the fields:
  - `seriesID: String`, `seriesName: String`, `poster: String?`;
  - `season: Int`, `episode: Int`, `title: String?`, `airDate: String` (YYYY-MM-DD).
- `enum Upcoming`:
  - `static func days(_ eps: [UpcomingEpisode], today: Date, calendar: Calendar) -> [(label: String, items: [UpcomingEpisode])]`
    - Range: yesterday to today + 14 days.
    - Labels: „Gestern“, „Heute“, „Morgen“ (yesterday, today, tomorrow), otherwise „Mi 26.11.“ (weekday and date).
    - Sorted by series name within a day.
  - `static func seriesIDs(continueWatching: [WatchProgress], watchlist: [MetaPreview], limit: Int = 50) -> [String]`
    - series only; no duplicates; continue watching first.
- `ProgressBook.history(limit:)`: entries with `finished == true`, descending by `updated`.

- [ ] **Step 1: Tests**
  - `upcomingGroupsYesterdayTodayTomorrowDate`
  - `upcomingDropsOutOfRange`
  - `seriesIDsDedupContinueFirstLimit`
  - `historyFinishedNewestFirst`
  - `parseNextEpisodes` (JSON with `next_episode_to_air` and the empty case)
- [ ] **Step 2:** Run the tests. Expected: compile error.
- [ ] **Step 3: Implement**
  - `AppModel.upcoming() async -> [UpcomingEpisode]` goes through `seriesIDs` and `tmdbID` and then calls `nextEpisodes`.
  - At most 4 requests at the same time. 6 h cache in memory.
  - `.upcoming` in the row shows today's entries as tiles (series, episode as the label).
- [ ] **Step 4:** Run the tests. Expected: all green.
- [ ] **Step 5: Views**
  - `LibraryView` has three rows: continue watching, watchlist, history, with the existing card components.
  - `CalendarView` shows day sections with landscape tiles (still or poster, „S2 F5 · Titel“, i.e. season 2 episode 5 ·
    title). A click opens the detail page.
  - Empty state: „Keine neuen Folgen in den nächsten 14 Tagen“ (no new episodes in the next 14 days).
  - `AddRowSheet` also offers `.upcoming`.
- [ ] **Step 6:** Commit with the message „Bibliothek, Kalender, Reihe ‚Heute neu‘“ (library, calendar, „Heute neu“ row).
  Push, build 26, check on the device.

### Task 6: Wrap-up

- [ ] `SITZUNG_UEBERGABE.md` (session handover): insert a new section „## STAND …“ (status) before „## Startprompt“ (start prompt).
- [ ] A review of the whole branch with a fresh reviewer (Opus).
