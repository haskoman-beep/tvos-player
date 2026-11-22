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

## [Build 249] – 2026-11-22 (integ)

<!-- X1 (maintainers): CI now converts the SFace face model to Core ML and bundles SFace.mlmodelc; no visible change yet. -->

### Added
- Groundwork for "who is in the picture" on pause (X-Ray, not visible yet): face alignment, comparison and
  matching logic, an on-device cache of cast face data (30 days per title, nothing is uploaded), and a
  background step that loads the full cast of a film or episode (including guest stars) and several TMDB
  portraits per person.
- Home: animated tiles from imports. A focused tile plays its focus video, else its focus GIF, else the still.
  The video starts 400 ms after focus, stops on focus loss and never runs while the player is open. Only imports
  fill tiles: the app ships no video addresses of its own.
- Import by link, in the app (Settings › Startseite › „Collection-Link hinzufügen“) and on the phone page: a widget
  export, a preview pack (a list of `title`/`videoURL`/`backgroundURL`, matched to tiles by title) or a public
  collection export (`focusVideoUrl`, `focusGifUrl`, `heroVideoUrl`). The format is detected from the content.
  Links are kept and can be fetched again („Aktualisieren“).
- Import by pasting the code (the JSON text) on the phone page, detected the same way.
- Every import shows a German result line, for example „Import: 3 Reihen, 42 Kacheln, 35 mit Video, 30 mit Ton“;
  invalid or unknown JSON gets a clear error.
- Settings › Startseite: „Ton bei Kachel-Animation“ (default off) plays a tile video's own sound once per focus,
  faded in to reduced volume and faded out after about 12 s or at the end of the first pass. The picture keeps
  looping muted.
- A collection link is read with a limit of 8 MB and a 20 s timeout and parsed once, off the main thread.
  „Aktualisieren“ takes the fresh video, GIF and image addresses of a collection export and keeps only your own
  changes. Pasted widget exports are kept in permanent storage. Preview packs match the exact title first, so
  „Paramount+“ and „Paramount“ each get their own video. The sound count follows the result line.
- Import data is stored in the app's size-bounded storage (Application Support if it is writable, always a second
  copy in Caches): the media addresses of a collection link and pasted widget exports as files, so the settings
  store stays small. Existing imports move over once. A failed write is logged, and the result line says when the
  oldest of 30 imports was dropped.
- Focus videos are cached on disk in two parts: silent clips (at most 50 MB, 20 MiB per file) and videos with a
  sound track (at most 150 MB, 30 MiB per file); only real video files are kept.
- Source list: filter chips above the list, „Alle“ (all) first, then only the qualities and features that some
  but not all sources have (4K, 1080p, Dolby Vision, HDR, Atmos, REMUX, „Deutsch“ (German), „Sofort bereit“
  (cached) and three size ranges), each with its count. One resolution and one size range at a time; the
  other chips combine. The filter only narrows the view; autostart, fallback and the next episode still use
  the full list.
- Source list: the full file name as its own wrapped line when the addon text cuts it or leaves it out.
- Settings › Sprache & Untertitel (language & subtitles): a new page „Untertitel-Aussehen“ (subtitle look) with size, position, outline,
  background (none, box, shadow) and a separate text brightness while the TV shows HDR or Dolby Vision (100 %
  down to 40 %), so white subtitles no longer blind at HDR peak. A live preview shows two sample lines over a dark and a
  bright picture; with the HDR row focused it shows the HDR brightness. The style is stored in the profile and
  the defaults are the previous look. It applies to text subtitles (SRT, WebVTT, ASS as text); image
  subtitles (PGS) only move up with a higher position.
- Developer test „Gesichter bei Pause prüfen (Test)“ (check faces on pause) in Settings › System ›
  Diagnose, off by default. When it is on, each pause takes the paused frame from the engine, looks for faces
  on the device and writes timings and face sizes to the event log (`xray:` lines). Nothing is shown or stored.
  This is the first step towards showing who is in the picture.
- Player: skip action per segment type. Settings › Wiedergabe (playback) › „Überspringen“ (skip) has one row each for intro,
  recap, credits and preview: „Aus“ (off), „Knopf“ (button) or „Automatisch“ (automatic). Defaults keep the old
  behaviour: intro and recap show the button, credits and preview are off. „Automatisch“ shows the button with a
  5-second countdown ring; OK skips at once, any other key stops the countdown and leaves the button, and a segment
  is skipped automatically only once per playback. Segments estimated from other episodes of the season never skip
  automatically, they only show the button. Previews are now detected from chapter names („Preview“,
  „Next Time“, „Vorschau“).
- Player: a scene after the credits is never skipped or covered. When the credits end before the file end with
  content after them, a hint „Szene nach dem Abspann“ (scene after the credits) shows and skipping the credits
  lands at that scene instead of the end.
- Player: card after a movie. Once a movie's credits start, a card shows two or three recommendations (TMDB, as in
  „Ähnliche Titel“), „Abspann weiterschauen“ (keep watching the credits) and „Zurück“ (back). A recommendation
  closes the player and opens its detail page; Menu closes the card. It needs credits marks from chapters or
  IntroDB and can be switched off („Karte nach dem Film“). IntroDB credits of a movie only count when they reach
  the file end, so marks from another cut or frame rate never show the card inside the film. Episodes keep the
  next-episode card.
- Player: a side panel on the right third of the screen (about 720 pt) while the picture keeps running. It opens
  with the vertical swipe or click that „Ton & Untertitel“ (audio & subtitles) leaves free (with the panel at the
  top: swipe or click up; at the bottom or as a menu: down); a pill in the control bar shows the way in. Its list
  holds „Folgen“ (episodes: season chips and the episode list, choosing one plays it), „Kapitel“ (chapters, with
  stills from already loaded data where possible, choosing one jumps there), „Andere Quelle“ (other source: the
  source list of the title, switching resumes at the current position) and „Infos“ (codec, HDR/Dolby Vision
  profile, audio, data rate, size, addon). Back goes up one level, then closes the panel.
- Player: a pause card. After about 2 s of pause without input it shows the logo (or the title), season and
  episode with the episode title, a short description, the cast line and the clock; any key hides it, Menu
  closes only the card. It leaves a slot for a later accessory (`PauseCardAccessory`).
- Genre page: opening a genre tile on the home screen now shows a filter „Filme“ / „Serien“ (films / series)
  and one endless poster grid instead of two rows. The page always opens on „Filme“. The grid loads one
  block at a time (one TMDB page or one addon `skip` page) and asks for the next block about two rows
  before the end, so you can scroll down until the source runs out. Titles already shown are dropped,
  the focus stays where it is while new blocks arrive, and a failed block ends the grid with a small
  „Erneut versuchen“ (try again) row instead of failing the page. Tiles use the poster size, rating and
  quality badges of the home rows. Folders with other shapes (for example the streaming folders with four
  lists) keep the page with one row per list.
- Long-press menu on every poster and tile (home rows, library, search, person page, similar titles, calendar):
  „Auf die Merkliste“ / „Von der Merkliste entfernen“ (watchlist on/off, when Trakt or Simkl is connected),
  „Als gesehen markieren“ / „Als ungesehen markieren“ (mark watched/unwatched), „Aus „Weiterschauen“
  entfernen“ (remove from Continue Watching, only in that row) and „Zur Detailseite“ (open the detail page).
  On home rows the row actions follow in the same menu. When the card leaves its row, focus moves to the
  neighbouring card (right first, then left).
- Sync queue: these changes show at once and are kept per profile until Trakt/Simkl confirm them, so a
  removed title no longer comes back with the next pull. One entry per title (IMDb ID first, so TMDB and
  IMDb tiles of the same title share it). Watchlist changes stay until a fresh watchlist pull after the
  confirmation is stored; other changes expire 5 minutes after confirmation; a Continue Watching removal
  that found nothing to delete remotely is kept for 30 days. Everything expires after 30 days at the latest.
  Simkl's watchlist is only changed safely: a removal stays local and is kept hidden for 30 days (Simkl has
  no call that does not also touch the watch history), and an add is skipped when the title is already on
  another Simkl list. An empty watchlist pull now replaces the cached list (last title removed).

### Changed
- Settings: the left column is regrouped into three groups with headers plus System at the end:
  „Inhalte“ (content: Profil & Konten, Addons, Quellen), „Oberfläche“ (interface: Startseite, Aussehen),
  „Wiedergabe“ (playback: Wiedergabe, Sprache & Untertitel, Bild & Ton) and „System“. „Addons & Quellen“ is
  split into „Addons“ and „Quellen“ (sources); the new page „Bild & Ton“ (picture and sound) collects HDMI
  mode, Dolby Vision, FEL, sound system, sound, audio offset and the device check. The „Erweitert“ (advanced)
  subpage is gone: its rows moved to their categories, diagnostics and the catalog cache now sit directly
  under System. All keys, TorBox included, are under Profil & Konten; „Postergröße“ (poster size) and the
  rating icon set appear only once, under Aussehen; „Sprache der App“ (app language) comes first there; the
  section „iPhone & Kontrollzentrum“ is now „Steuerung“ (controls). Each category says under its title
  whether it applies to this profile or to this device. „Sofort abspielen anzeigen“ (show instant play) moved from Wiedergabe › Detailseite to Quellen › Auswahl. Only the place of the rows changed: values, keys and
  defaults stay as they were.
- Settings › Bild & Ton (picture and sound): every setting there (Dolby Vision fixed, FEL, keep HDMI mode,
  sound system, always stereo, night mode, dialogue, loudness, audio offset) is now stored per device instead
  of per profile. On the first start after the update the app takes the values of the active profile once.
  Profile export, import and sync no longer carry them; old backups that still contain them load as before.
  The page says „Gilt für dieses Gerät“ (applies to this device). The move runs once per device (a flag
  remembers it); if the stored values are ever lost, the app starts with defaults and logs it instead of
  taking old profile values again. Going back to an older build resets these settings to their defaults, and
  restoring a backup on another Apple TV does not bring them along.
- Phone page: the TorBox key moved to „Konten & Schlüssel“ (accounts and keys), next to the other keys; the
  section „Addons & Quellen“ is now „Addons“. The TV row Profil & Konten › Schlüssel › TorBox opens it there.
- Source list: while sources are still arriving, the focus keeps its row position instead of following its
  source to a new place, so the list no longer jumps under the remote.
- Dolby Vision Profile 5: the engine is now built with its still reshaping part, so the face test above can take
  the paused frame of a Profile 5 source. Profile 5 otherwise keeps its earlier behaviour: no scrub previews and
  no background still pictures (no second connection to the source) once the player knows the source is
  Profile 5. It learns this from the first play and remembers it. Only while the face test is on, a source not
  checked yet is examined before it loads (at most 1.5 s, after the disk cache, through the cache when it is used;
  not for HLS/DASH), and the result is remembered (for sources that are not Profile 5, until the app restarts).
  With the face test off, playback starts exactly as before. There is no restart during playback.
- Accepted trade-off for Dolby Vision Profile 5: the picture held during an audio switch or reload is now decoded
  and converted on the processor (shown in SDR, up to 3 s) instead of through the system. The event log notes its
  time as `xray: P5 gehaltenes Bild per CPU (… ms)`.

### Fixed
- Poster rows: moving left and right quickly no longer makes the row wobble. An expanding poster still moves to
  the left edge (80 pt margin), with one scroll of that row only when it expands; the row no longer holds a
  bound scroll position that competed with the focus scroll on every move. The bottom room for the focus lift (build 214) is unchanged.
- Detail page: tech badges come from the source cache again when the page is opened from a genre or service
  page, a collection page or „Ähnliche Titel“ (similar titles). Tiles there now fetch their sources after the
  same 350 ms rest as on the home page; before, only home page tiles did, so the page waited 2–4 s for the
  sources.
- Detail page: the age rating, cast and similar titles no longer wait for the metadata addon; TMDB is asked in
  parallel (one shared request). A catalog entry without a description takes the TMDB text meanwhile, so the
  poster next to it shows early.
- Log: one line per detail page, „Ladezeiten <title> · ID · TMDB · Meta · Poster · Technik“ (load times, with
  the source of the tech badges: cache, prefetched cache or a new search).

## [Build 214] – 2026-11-22 (integ)

### Added
- Detail page: the title's poster now sits to the left of the meta line, badges and description, exactly as
  tall as that block. It uses the same picture as the poster tiles (metadata addon poster when that setting
  is on, otherwise the catalog or TMDB poster) and is left out when the block is too short for it.
- Settings › Playback › Detail page: a new setting „Sofort abspielen anzeigen“ (show instant play), off by
  default.

### Changed
- Detail page: „Abspielen“ (play) is the main button again and takes the focus on entry and on return from
  the player. The „Sofort abspielen“ (instant play) card is only shown, and its best source only chosen,
  when the new setting is on; with it on, everything behaves as in build 198.

### Fixed
- Top menu bar after the player, in every tab: the source list now waits until the player has fully closed
  before it scrolls back to the played source. Before, it scrolled while the player was still closing, the bar
  followed that list far above the screen and stayed there on the next page (home page, or the detail page and
  grid in the Library tab). As a safety net, after every step back, after the player closes and after a failed
  move up, the app checks whether the bar is stuck and tries to bind it to the visible page again and show it.
  Each step is logged (`nav: Leiste hing fest …`). The home page hands its list to that check, so the bar is never
  bound to a tall row of tiles.
- Home: a focused poster in the lowest visible row is no longer cut at the bottom. The home list now ends above
  the screen edge by the height of the focus lift and draws into that room. Without the hero, the list also
  leaves that room at the top and still clips there, so rows never draw into the menu bar area.

## [Build 198] – 2026-11-22 (integ)

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
- Home screen and „Ähnliche Titel“ (similar titles): a focused poster is no longer cut off, including its tag
  at the top edge and its shadow, at every poster size. Poster rows get a little more room above and below
  for this; a row keeps its height while its entries load.
- Poster tiles: when a poster image cannot be loaded, the tile tries the next one (the metadata addon's
  poster, then the TMDB poster). The title lies under the picture from the start, so a tile whose picture
  loads slowly or not at all shows its title instead of an empty grey card. A picture service that stops
  answering is given up after 15 seconds instead of 60.
- Quality badges on posters (when „Qualität auf Postern“ is on): every poster on screen now gets its
  badge, not only the ones that were focused. When scrolling stops, the app quietly looks up the sources
  of the visible titles (at most a few at a time and a few per minute, never while a video plays or a
  detail page loads its own sources, each title only once while its sources are cached) and fades the
  badge in. These lookups never push out the sources of titles you focused or opened, so those still
  open at once. Series without a started episode use their first
  episode.

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
