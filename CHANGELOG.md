# Changelog

All notable changes to Player are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Sections are ordered by stage, newest first. "Build" is the CI run number, which the app shows as its build
number. A section marked **integ** is on the `integ` testing branch and only moves to `main` after device
testing. The app itself is in German; German labels are quoted with an English gloss, for example
„Abspielen“ (play).

Each build from `integ` (prerelease) and `main` (release) is also published as a GitHub release
`build-<number>` with its commit log and the IPA to download:
[Releases / version history](https://github.com/haskoman-beep/tvos-player/releases).
The "What's new" part of those release notes is the `[Unreleased]` section below, as it was in the
commit that was built. After a release, `[Unreleased]` is renamed to `[Build <number>]` and a new, empty
`[Unreleased]` section is started (see the README, "Releases / Version history").

## [Unreleased]

### Added
- Player: a new setting, Settings › Playback › "Ton & Untertitel öffnen", chooses how the audio and subtitle
  choice opens: the bar at the top (swipe down, as before), the same bar at the bottom (swipe up), or a small
  menu in the bottom right corner (swipe up) that shows audio, subtitles and offset first and then the list.
- Addons: anime catalogs (type „anime“) load as home screen rows and count as series catalogs.
- Addon install: links with a variant query (`…/manifest.json?v=…`), links to an addon's configure page
  (`…/configure`) and web install links with an `addon=` parameter are accepted. The query is kept and
  sent with every request to that addon.

### Fixed
- Home screen: the built-in packs (streaming services, genres) now show images. A tile takes its image
  from a collection you imported, otherwise from the home screen kit, which is loaded at runtime for this
  even when the kit is switched off. Tiles are matched by provider or genre ID or by name, for example
  Netflix, Prime Video, Disney+, „Komödie“ (comedy) or „Krimi“ (crime). If the image has an animated GIF
  (from an imported collection), it plays on the focused tile. A tile with such an image shows no extra
  title on top, since the name is part of the image. The gradient tile stays while an image loads and for
  services without an image; the „Krimi“ tile now shows a fingerprint instead of a magnifying glass.
- Addon catalogs no longer fail as a whole with „Antwort unlesbar“ (unreadable answer) when an item sends
  its year or rating as a number or has one broken field. Unreadable items are skipped and logged.
- Error, statistics and library-sync entries from aggregator addons are no longer listed or played as
  sources, and „Sofort abspielen“ (play now) never picks them. They only appear in the log.
- Error entries no longer appear as home screen tiles or as subtitle tracks.

### Changed
- Subtitles are never requested from AIOMetadata, because a subtitle request there marks the title as
  watched on your tracking services. The app does its own tracking.
- The metadata addon for posters and ratings is now one that names the IDs it serves (or AIOMetadata),
  not an aggregator that accepts every ID only because it is higher in the addon list.

## [Build 187] – 2026-11-22 (integ)

### Changed
- Player: the audio and subtitle panel is now a slim bar docked at the top (at most a third of the screen),
  so the video stays visible. „Ton“ (audio), „Untertitel“ (subtitles) and „Versatz“ (subtitle offset) are
  columns side by side; left/right switches column, up/down picks a track, a click applies it at once.
- Player: one line per track, for example „Englisch · Dolby Atmos 5.1“, with a small „Standard“ tag. Similar
  tracks always get distinct labels. White text on dark, black on white when focused, no system blue.
- Player: Menu closes only the panel; a swipe up from the top row closes it too.
- GitHub page: release notes, changelog, CI output and design documents are in English.

### Fixed
- Home screen: the top menu bar could become unreachable after scrolling and returning from playback. When a
  source list starts playback automatically, it now waits until the page transition has finished, and the
  bar stays visible while it has focus.
- Player: while a new audio track is loading, subtitles and offset are briefly locked („lädt…“, loading), so a
  subtitle choice is no longer silently undone. Switching back to the original audio track during the reload
  now works.
- Player: leaving the player after using the panel no longer keeps the player in memory.

## [Build 174] – 2026-11-22 (integ)

### Added
- Player: the audio and subtitle panel now also opens with a swipe down on the touch surface. Before, only
  a click on the bottom edge opened it.
- Home screen: the built-in packs (streaming services, genres) have their own tiles with a gradient, a
  symbol and a title. Images and animated focus GIFs come only from collections you import yourself.
- Home screen: a kit collection that failed to load shows a status tile instead of an empty row.
- Source list: the addon's formatter text is shown in full, with the cache badge on the left.
- Season buttons show a checkmark and leave room for the focus effect.
- Version history: every build from `integ` and `main` is published as a GitHub release `build-<number>`
  with its IPA. Before publishing, CI checks the IPA for keys, LAN addresses and personal data.

### Fixed
- Sources marked „Not Ready“ count as uncached, so they are no longer picked as the best choice.
- Cache detection is more robust: status words only count in status lines, not in release titles, and the
  🎫 symbol is no longer read as a cache marker.
- Detail page and home screen: buttons no longer turn system blue when focused.
- Cast tiles on the detail page no longer overlap.
- Posters no longer flash grey while scrolling, and tiles no longer show an old image after the blur
  setting changes.
- The audio and subtitle choice is locked while the player rebuilds the stream, so a choice is no longer
  lost during a reload.

## [Build 162] – 2026-11-22 (integ)

### Added
- Detail page (movies): a „Sofort abspielen“ (play now) card with the best source and its technical line,
  for example „4K DV · Deutsch 5.1 · 12,3 GB · TorBox ⚡“. The last played source comes first („Weiter mit
  letzter Quelle“, continue with last source); otherwise cached sources, resolution, Dolby Vision and
  5.1/7.1 audio decide. Links that failed recently are skipped. Without a source, the card opens the source
  list.
- Player: hold ◀ or ▶ to seek fast. The longer you hold, the faster the target moves (2× up to 64×), with
  a still-frame preview when the source provides one. The jump happens once, on Select or Play. Fast
  seeking stops 10 seconds before the end credits marker.
- Now Playing: title, episode and artwork appear in the system's Now Playing view, and the system's play,
  pause and skip commands control the player.
- New setting „Sprungweite“ (skip interval): 10 seconds (default) or 30 seconds.

### Fixed
- Play/Pause from the system is ignored while a stream is loading or seeking.
- Closing the player no longer starts the best choice again by itself.

## [Build 156] – 2026-11-22 (integ)

### Added
- Home screen: rows and collections can be deleted, not only hidden.
- The poster size can also be set from the home screen settings. It is the same setting as „Kartengröße“
  (card size) under „Aussehen“ (appearance).

### Changed
- New look for the home screen, detail page, source list, calendar and library: the same type sizes,
  margins and spacing everywhere.
- Badges: technical badges are filled with bold lettering and no logos; ratings show the brand name in its
  colour with the value; the cache status is a capsule, „sofort“ (instant) in green or „lädt erst“ (loads
  first) in orange. Badges have labels for VoiceOver.
- The source list header shows the number of sources and the search time, for example
  „161 Quellen · 8,4 s“ (161 sources · 8.4 s).
- The badges on the detail page stay in one row; when space runs out, ratings are left out from the end.

### Fixed
- Home screen: you can scroll past rows that are still loading. Before, focus got stuck below the
  watchlist until all rows had loaded. Loading rows show placeholder tiles, an empty row shows
  „Keine Einträge“ (no entries), and a failed row offers to retry.
- Home screen rows load in order, up to four at a time, and keep loading when they scroll out of view, so
  rows at the bottom and newly added rows appear sooner.

## [Build 149] – 2026-11-22 (integ)

### Changed
- Menu button: on every tab except „Start“ (home), Menu goes back to Start; on Start it leaves the app. In
  the settings, Menu goes from the content to the active category and then to Start.
- In the player, Menu first cancels Up next, then hides the control bar, and only then leaves the player.

### Fixed
- Focus returns to the right place after the player: on the detail page to the next unwatched episode
  (also across seasons, with the season switching along) or to „Abspielen“ (play) for a movie; in the
  source list to the source that was played, or after an error to the next playable source.
- Loading, error and empty pages always have something to focus, so the focus can no longer get lost.

## [Build 144] – 2026-11-22 (integ)

The first build in the version history. It contains all changes since Wave D (build 121); the CI builds in
between (127–139) were not published as releases.

### Added
- Settings in seven categories: „Profil & Konten“ (profile & accounts), „Addons & Quellen“ (addons &
  sources), „Startseite“ (home screen), „Aussehen“ (appearance), „Wiedergabe & Bild“ (playback & picture),
  „Ton & Untertitel“ (audio & subtitles) and „System“, with status cards, subpages and an
  „Am Handy einrichten“ (set up on phone) tile. Text fields such as addon URLs and keys moved to the phone
  page; the TV links to the right section there.
- Audio language presets: „Deutsch zuerst“, „Original zuerst“, „Englisch zuerst“ (German, original or
  English first).
- Confirmation before destructive actions, with the focus on „Behalten“ (keep), for example before
  clearing the remembered track choices or logging out.
- Home screen manager „Reihen & Collections“ (rows & collections): add rows, move them (to the top, to the
  bottom, step by step or to a position), change their style, and hide and restore them. New rows appear
  at the bottom. An add browser lists the available rows by category, plus import from the phone.
- Phone page: reorganized, with a new section „Startseite ordnen“ (arrange home screen). Hidden rows are
  kept and can be restored.
- Home screen kits: a kit file can bring a complete home screen; search also matches transliterated
  spellings; inserting a row skips duplicates.
- Posters: new setting „Qualität auf Postern“ (quality on posters: „Aus“ / „Oben rechts“ / „Unten“, i.e.
  off / top right / bottom), off by default. The genre and rating line always stays readable.
- Detail page: choose which ratings are shown (default: IMDb, Rotten Tomatoes, Trakt). At most five quality
  badges in one row, in this order: resolution, Dolby Vision/HDR, Atmos, audio format with channels, remux.
  The age rating stays in the text line.
- Images and ratings from the metadata addon (poster, background, logo) take precedence over TMDB; this can
  be turned off. TMDB rows also get the addon's posters for the visible tiles.
- Source list: the addon's order is the default, „Smart (App)“ can be selected. The addon's text is shown
  unchanged (up to four lines), the app's badges only in compact form, and duplicate sources are hidden.

### Changed
- A calm, dark design for settings rows, lists, status cards and badges, with a brighter error red for
  better contrast.
- Update texts in the settings without technical jargon.

### Fixed
- Settings: „Zurück“ (back) leaves the settings, and the page title scrolls with the content instead of
  covering the rows.
- Duplicate sources are detected per debrid service, so the same file on TorBox and Real-Debrid stays two
  rows.
- Requests to the metadata addon have a time limit, so a slow addon no longer holds up the home screen.

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
