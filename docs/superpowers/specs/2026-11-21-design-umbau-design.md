# Design rework in the style of common tvOS streaming apps – Design

As of 21 Nov 2026. Markers: **[U]** = user decision, **[C]** = decision by Claude (can be corrected).

## 1. Intent and why

The player replaces the Stremio-style clients used on the Apple TV so far. Much of the functionality is there (sources,
DV, audio, ratings, TMDB enrichment), but the interface and handling still feel like a prototype: three text tabs at the
top, a static hero tile, settings as one long list. Goal: a look and structure on par with established tvOS streaming
apps [U], so that switching does not feel like a step back.

## 2. Goals, non-goals, anti-goals

**Goals** (all four parts [U]):
1. **Navigation:** sidebar on the left (tvOS 18 `.sidebarAdaptable`) *or* a top bar with a clock – switchable under
   „Einstellungen → Aussehen“ (settings → appearance) [U]. Tabs: „Start“ (home), „Suche“ (search), „Bibliothek“
   (library), „Kalender“ (calendar), „Einstellungen“ (settings) [U], with SF Symbols.
2. **Home screen:** full-screen hero slideshow at the top (changes every 10 s, cross-fade, logo instead of the title text
   when available, meta line year · runtime · FSK age rating, MDBList rating line, 2-line description, buttons
   „Abspielen“ (play) / „Details“).
   The background follows the focus: a focused tile in a row sets the full-screen background after 350 ms of rest.
   A focused poster expands to landscape with a logo after 350 ms of rest.
3. **Settings:** categories on the left with symbols, content on the right:
   profile, addons, services & keys, home screen, appearance, playback, about. Existing entries are only sorted in.
4. **Appearance options** (new category): navigation sidebar/top, accent colour (6 fixed colours),
   card size (small/medium/large), hero on/off, hero source (which home screen row), expand posters on/off.
5. **Library tab** [U]: continue watching, watchlist, history (recently watched). Source as today (Trakt/Simkl/local).
6. **Calendar tab** [U]: upcoming episodes of the series from continue watching/watchlist/history, grouped by day
   (today, tomorrow, date), data from TMDB (`/tv/{id}` → `next_episode_to_air`, season episodes). Plus an optional
   „Heute neu“ (new today) row for the home screen.

**Non-goals:** watch party, IPTV, AI rows, surprise me, ambient mode, custom fonts, 12 colour themes,
stream list style editor, trailers in the hero (dropped on purpose, plan of today).

**Anti-goals** (would be a failure despite working):
- Focus jumps, gets lost or hangs (a common source of bugs in tvOS apps, which can take thousands of lines of focus
  repair).
- The home screen stutters while scrolling because the background/expansion loads images on every focus change.
- Existing profiles/home screens are lost in the update.

## 3. Constraints

- tvOS 18, SwiftUI, builds only via GitHub Actions (no Mac); every test costs a build + installation (~15–20 min).
- Public repo: no keys, names, IPs.
- New profile fields with default values in `init(from:)` (old backups stay loadable).
- The image loader `ImagePipeline`/`RemoteImage` is used (preloading, downsampling).
- Logic that can be tested (calendar grouping, hero selection, settings defaults) goes into PlayerCore with tests.

## 4. Approaches

| Approach | In short | Trade-off |
|---|---|---|
| **Hybrid** [U] | navigation + settings with Apple building blocks, hero slideshow and expanding posters built ourselves | stable system focus, little code; the polished feel comes from the hero + posters |
| All native | only Apple building blocks, no expansion | fast, looks less polished |
| All custom | own sidebar and focus logic | the most freedom, but exactly the focus bugs we want to avoid |

## 5. Structure [C]

- `RootView`: `TabView(selection:)` with `Tab(…, systemImage:)`; `.tabViewStyle(.sidebarAdaptable)` when
  `appearance.navigation == .sidebar`, otherwise the standard top bar plus a clock overlay at the top right.
  Each tab keeps its own `NavigationStack` path (as today).
- New profile field `appearance: Appearance` (navigation, accent, cardSize, heroEnabled, heroRowID?, expandPosters).
- `HomeView`: `HeroCarousel` at the top (own component), the rows below as today. Background via a
  `@State focusedBackdrop` URL with a cross-fade; 350 ms debounce via `Task.sleep`, cancelled on a focus change.
- `PosterCard` gets an `expanded` state (focus + 350 ms) → the width grows animated to landscape; the image is only
  loaded after the rest period.
- `SettingsView` → like a `NavigationSplitView`: category list on the left, content on the right; subpages per category
  as small views of their own (instead of one big file).
- `LibraryView`, `CalendarView` new; calendar logic `UpcomingEpisodes` in PlayerCore (grouping, filters, tests).

## 6. Screens (sketch)

The sketch shows the German UI labels: „Abspielen“ = play, „Weiterschauen“ = continue watching, „Beliebt“ = popular,
„aufgeklappt“ = expanded, „Hintergrund“ = background, „Einstellungen“ = settings.

```
Sidebar:                           Home screen:
┌──────┐ ┌─────────────────────────────────────────────┐
│ ⌂    │ │ [LOGO]                       Hintergrund     │
│ 🔍   │ │ 2010 · 1 h 42 · FSK 6 · IMDb 6.0 🍅 64 %     │
│ 📚   │ │ Fünf Freunde …                               │
│ 📅   │ │ [▶ Abspielen] [Details]          ● ○ ○ ○     │
│ ⚙    │ │ Weiterschauen ▸ [▭][▭][▭]                    │
└──────┘ │ Beliebt ▸ [▯][▭▭ aufgeklappt][▯][▯]           │
         └─────────────────────────────────────────────┘
Einstellungen:  [Profil | Addons | Dienste | Startseite | Aussehen | Wiedergabe | Über]  →  content on the right
```

## 7. Phases [C] (one build each)

1. Navigation + appearance profile field + settings categories.
2. Hero slideshow + background follows focus.
3. Expand posters + apply card size/accent colour.
4. Library + calendar (+ „Heute neu“ (new today) row).

## 7a. Answers to the builder check

1. **Hero and rows [U]:** the info layer at the top (background, logo, meta line, ratings, description) always shows the
   focused title. While the focus is in the rows, the slideshow pauses, and it continues as soon as the focus is back in
   the hero. Implementation: one shared background and info layer behind the ScrollView. The hero is not a scroll
   section of its own.
2. **„Abspielen“ (play) in the hero [U]:** behaves like continue watching.
   - Movie: the remembered source starts directly (`resumeLastSource`), otherwise the source list opens.
   - Series: the next open episode according to progress, otherwise S1E1.
   - Episodes are only loaded on the press, not per slide.
3. **Calendar [U]:** series from continue watching and the watchlist, at most 50. Time range: „Gestern“ (yesterday) up
   to 14 days ahead. Cached for 6 h, like the other TMDB data.
4. **Existing style `.hero` [C]:**
   - The first existing `.hero` row automatically becomes `heroRowID` at the first launch.
   - It is not shown twice as a row. The style stays readable, but in the editor it becomes „Als Hero verwenden“
     (use as hero).
   - If `heroRowID` is empty: the first catalog row; without a catalog row there is no hero.
5. **History [C]:** the source is the local `ProgressBook` (entries with `finished`, newest first). Trakt and Simkl
   history come later.
6. **„Heute neu“ (new today) [C]:** new `SourceKind.upcoming` / `CatalogSource.upcoming`. It can be added and moved in
   the home screen editor like continue watching. Old profiles do not know the case; that is no problem, because it is
   only ever added.

## 8. Left to the builder

Exact spacing, font sizes, animation curves, choice of symbols, placement of the clock, number of hero slides
(proposal: 8).

## 9. Risks

- `.sidebarAdaptable` on tvOS 18 swallows the back button or opens the sidebar when pressing left at the edge –
  intended, but rows must stay focusable at the far left.
- Hero at the top + rows: focus moving up from a row must land in the hero, not in the sidebar.
- Expanding changes the row width → the scroll position must not jump (fixed anchoring on the focused element).
