# Changelog

All notable changes to Player are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Sections are ordered by stage. "Build" is the CI run number, which the app shows as its build number.
A section marked **integ** is on the `integ` testing branch and only moves to `main` after device
testing.

Each build from `integ` (prerelease) and `main` (release) is also published as a GitHub release
`build-<number>` with its commit list and the IPA to download:
[Releases / version history](https://github.com/haskoman-beep/tvos-player/releases).

## [Unreleased]

Work in progress, not yet on `integ`.

### Added
- Wave E, based on feedback after device testing:
  - Posters: new setting „Qualität auf Postern“ (quality on posters: Aus / Oben rechts / Unten, i.e. off / top right /
    bottom), off by default. The genre and rating line always stays readable.
  - Detail page: choose which ratings are shown (default: IMDb, Rotten Tomatoes, Trakt). At most
    5 quality badges in one row, in this order: resolution, Dolby Vision/HDR, Atmos,
    audio format with channels, remux. The age rating stays in the text line.
  - Images and ratings from the metadata addon (poster, background, logo) take precedence over TMDB; this can be turned off.
  - Source list: the addon's order is the default, „Smart (App)“ can be selected. The addon's text
    is shown unchanged (up to 4 lines), the app's badges only in compact form, and duplicate sources are
    hidden.

### Fixed
- Settings: a fix is in progress.

## [Wave D] – 2026-11-21 (integ, Build 121)

Video and audio in the player.

### Added
- Track memory per series or title: audio language, subtitles and subtitle offset are carried over
  next time.
- Adjustable subtitle offset, including negative values.
- Character-encoding detection for subtitles (such as Windows-1252) and repair of broken umlauts.
- The screen saver stays off during playback.
- Progress display for TorBox downloads.

### Fixed
- Switching profiles during a source search no longer mixes results between profiles.
- A partially loaded source list now fills in the rest.
- The rating icon set no longer flickers on restart.
- Air times are matched more accurately and cached more compactly.

## [Wave C] – 2026-11-21 (integ, Build 116)

Stability, speed, player comfort, plus sources and extras.

### Added
- Scrubbing via the touch surface with a preview thumbnail, intro markers on the timeline.
- Settings for audio (audio output) and picture mode (Dolby Vision display mode); clean exit from the
  player.
- TorBox: cached sources are detected and preferred, and „Meine TorBox-Dateien“ (my TorBox files) is in the library.
- Sources: AIOStreams fields are parsed. Ordering takes language, AV1 support and
  TorBox into account. Subtitle fields (forced, SDH, label) are read.
- Trakt recommendations as a home-screen row; Fusion options `limit` and `hideTitle`.
- Spoiler protection for episode thumbnails.
- Calendar with air date and air time via TVmaze.
- „Über“ (about): device check (match content, TV HDR, audio output, AV1 hardware) and the
  „Was spielt wie“ (what plays how) table.
- Phone page: a single quick-import field that recognizes what was pasted.
- Custom icon set for ratings, via URL.

### Changed
- The home screen appears instantly from the disk cache. Sources come from a cache that is refreshed in the
  background.
- Images are loaded at the size they are displayed. Each row remembers its focus.

### Fixed
- The addon search has timeouts, so a slow addon no longer holds everything up.
- A loading watchdog detects stalled starts. Failed links are avoided for 8 hours.
- The app waits for the network instead of giving up, and reacts to audio route changes.
- Added a hang watchdog for the UI.

## [Dolby Vision FEL] – 2026-11-21 (integ, Build 108)

### Added
- Dolby Vision Profile 7 FEL: the enhancement layer is applied during Profile 8.1 playback instead of
  being lost. To do this, the new `Packages/AetherFEL` package enables the engine trait
  `DolbyVisionFelCurves`.
- CI verifies that the trait is active in the build and that all engine frameworks are included in the app.

## [Wave B] – 2026-11-21 (integ, Builds 92–100)

### Added
- Pause when the TV turns off or the app goes to the background. Playback is then cleanly
  rebuilt.
- An error escalation ladder depending on the error type: reload, re-resolve, switch source.
- Visible loading steps when a movie starts.
- „Intro überspringen“ (skip intro) via IntroDB and chapter markers.
- The next episode comes from the same release (group, language, quality), plus the „Noch da?“ (still there?)
  prompt after several episodes without input.
- Disk cache for the currently playing movie via a local proxy (off by default).
- License notices: `THIRD_PARTY_NOTICES.md`, „Danksagungen / Lizenzen“ (acknowledgements / licenses) under „Über“
  (about), MIT License for the app's own source code.

### Changed
- The playback engine is pinned to a fixed version.
- Error messages no longer show links.

### Fixed
- After automatically advancing to the next episode, the source list is correct.

## [Wave A] – 2026-11-21 (integ, Builds 32–80)

New player, home-screen rework and first expansion stage.

### Added
- Home screen: hero slideshow, info follows focus, posters expand after a short pause, card size for all
  rows.
- Library, calendar and the „Heute neu“ (new today) row.
- Sources are preloaded in the background as soon as focus rests briefly on a tile.
- Player: readable names for tracks and formats, info badges instead of raw engine text, a panel with the tabs
  Info · Ton · Untertitel (info · audio · subtitles).
- Subtitles: custom overlay, automatic selection, subtitles from addons (Stremio `subtitles` resource,
  also via file hash).
- Redesigned quality badges: neutral, configurable, with drawn lettering, also on posters.
- Trailers via Trailerio first, YouTube as fallback; the profile language is preferred.
- Fusion or betterer home-screen kits as home-screen rows.
- „App aktualisieren“ (update app) in the settings; the build number comes from CI.

### Changed
- Logs no longer contain keys or tokens.
- The image cache size adapts to available memory.

### Fixed
- Memory crash protection: large data blobs are stored as files, profiles are never kept only in the cache, and the
  catalog cache expires after 24 hours.
- Navigation: initial focus is on „Abspielen“ (play), the home-screen buttons are no longer blue, and „Zurück“ (back)
  in the calendar leads to the sidebar.

## [0.4.0] – 2026-11-21 (main, Builds 12–39)

### Added
- Placeholder streams are detected, and the app then switches source automatically. On errors it reloads.
- Loading options (languages, proxy headers); Dolby Digital and DD+ audio tracks are preferred.
- Info line on the detail page: ratings via MDBList (IMDb, Rotten Tomatoes, Metacritic, Letterboxd,
  Trakt, TMDB and others), age rating, tech badges (4K, Dolby Vision, HDR, Atmos, 7.1/5.1).
- Stream badges: REMUX/BluRay/WEB-DL, HEVC/AV1/H.264 with 10-bit, DTS:X, HLG, channels.
- Tile state: progress bar, remaining time, episode (such as S1 F3), checkmark for watched.
- German text and images from TMDB: title, description, poster, logo, genres, age rating and episode names.
- Up next: sources for the next episode are preloaded, and a countdown runs shortly before the end. Episodes that
  have not aired yet are skipped.
- Detail page: trailers in the app's own player, cast with person page, similar titles, details under „Über“
  (about: director, studio, original title, budget).
- New design: sidebar and top bar with clock, settings in categories, appearance settings
  per profile, selectable hero source.

### Changed
- „Weiterschauen“ (continue watching) starts the last played source directly.
- When switching sources, cached sources come first.
- Custom image loader with a 400 MB disk cache instead of the system component.
- Trakt/Simkl: login is renewed in time, retries on 401/429, scrobble rules
  (80 %, pause, 409).
- On the detail page, sources load immediately and in parallel. The tech badges appear instantly from the
  cache without the row jumping.

### Fixed
- Many individual seeks in a row no longer use up the engine's restarts; they are batched.
- Play/pause follows the player's actual state.
- Focus is kept when returning to the detail page.

## [0.3.0] – 2026-11-21 (Builds 8–11)

### Added
- Remote log: the app sends events via Bonjour to `tools/logcollector.py` on the local network.

### Changed
- A click on the touchpad pauses playback. The log shows error details and seeks.

## [0.2.0] – 2026-11-21 (Builds 4–7)

### Added
- Automatic next episode (same `bingeGroup`), with an autoplay toggle. „Weiterschauen“ (continue watching) shows the
  next episode.
- Trakt and Simkl: device login, scrobbling, Continue Watching sync, watchlist, Trakt lists as rows.
  The progress source is selectable.

### Fixed
- Storage on tvOS: profiles are now kept in UserDefaults (compressed), because tvOS does not allow writing to the
  "Application Support" folder.
- Profiles load even when fields are missing.

## [0.1.0] – 2026-11-21 (Builds 1–3)

### Added
- Trial run in a separate spike: AetherEngine verified on Apple TV with Dolby Vision and 5.1 audio.
- `PlayerCore`: Stremio addon client, models, profiles, collection import, stream attributes, TMDB.
- App skeleton: home screen with edit mode (long press, then move rows, change style, remove from the
  home screen), detail page, source list, player behind its own playback interface,
  settings, CI with unsigned IPA.
- Ready-made packs (streaming services, genres), TMDB links as a row, search, „Weiterschauen“ (continue watching) with resume.
- Phone input page: QR code, local server, profile backup.
