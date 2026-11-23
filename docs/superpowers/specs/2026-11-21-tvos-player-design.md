# tvOS Player – Design (as of 21 Nov 2026)

Status: **historical.** This is the first design, written by Claude overnight after the user ended the question
phase ("move all decisions you need from me to tomorrow"). The app was built from it and has moved on since; where
the app differs, the list below and [docs/entscheidungen.md](../../entscheidungen.md) are the current state
(checked on 23 Nov 2026 against the code; analysis in `docs/superpowers/analysis/2026-11-22/`, contradictions
W-1 to W-20 in `03-engineering-entscheidungen.md`). Setup details of the user's home are written neutrally.
Markers: **[U]** = decided by the user, **[C]** = Claude's decision (can be corrected),
**[OPEN]** = needs the user.

**Where the app differs today**
- Non-goals lifted: direct TorBox integration (own client, library row, cached sources first; W-2) and audio
  passthrough (Dolby Digital, DD+ and Atmos in DD+ are passed through by default; W-1).
- Language: the interface is German only; the profile language sets titles, descriptions and trailers (W-5).
- Sound: TrueHD, DTS and DTS-HD MA are converted to Dolby Digital Plus 5.1 by default, not to multichannel PCM (W-12).
- Subtitles: default „Nur erzwungene“ (forced only) instead of off (W-6).
- Source order: the list shows the addon order (or „Smart (App)“), the automatic choice uses the app's ranking (W-7).
- Home screen editing: long-press menu and a row manager instead of the direct edit mode (W-10).
- Persistence: all profiles in one block in UserDefaults plus file copies, the last two versions kept, a recovery
  page instead of a silent reset (W-4). Keys are in the profile, not in the Keychain; the normal export has no keys,
  a backup with keys is encrypted with a 12-character code (three groups of four, `XXXX-XXXX-XXXX`) shown on the TV (W-3).
- Structure: no `PlaybackKit`/`PlayerEngine` package; the app uses the engine through `Packages/AetherFEL` (W-11).
  The app target builds in the Swift 5 language mode, `PlayerCore` in Swift 6 (W-18).
- Not built: TVDB episode order (the key field was removed) and MDBList lists as rows (E-51, E-53).
- The repository is public (W-16).

## 1. Intent and why

A personal Apple TV app, only for the user, to replace the Stremio-style clients in use today. [U]
The main pain today: **arranging** addons and collections on the home screen is clumsy (not the
setup). [U] The app should feel like a native Apple app, the home screen should be built from
collections chosen beforehand, and it should output all high-quality formats cleanly on the user's Dolby Vision TV
and 5.1 speaker system.

Success means: the user rearranges the home screen in a few clicks on the TV, starts a remux with
Dolby Vision, hears 5.1 from the speakers, and "continue watching" matches Trakt.

## 2. Goals, non-goals, anti-goals

**Goals**
- Stremio addon protocol; AIOStreams as the main source. [U]
- Home screen built from collections; widget style per row from 6 styles (hero, poster,
  landscape + progress, top 10, logo tiles, collection tiles). [U]
- Editing on the TV: long press → move the selected row directly (▲▼ move, ◀▶ change style live,
  Play/Pause = remove from the home screen, OK done, Back cancel); a plus tile below all rows, only
  in edit mode → list of the collections that are not on the home screen (including removed ones)
  with a preview, at the bottom "import new collection"; the new row appears above the plus tile,
  already selected. No menu per row. [U]
- Where collections come from: import (Trakt / MDBList / TMDB) + 2 ready-made packs; no editor of our
  own. [U] Import the Nuvio export `nuvio-collections-profile-1-tmdb.json` (16 collections, 7
  duplicates) and merge duplicates; adopt the data model collection → folder → sources. [C]
- Services: Trakt, Simkl, TMDB, TVDB, MDBList. [U] Roles [C]: Trakt = progress/continue watching,
  Simkl mirrored; TMDB = metadata de-DE (fallback en-US) including logos/backgrounds; TVDB =
  episode order; MDBList = ratings + lists.
- Setting "progress & watched": main source local / Trakt / Simkl, also reported to the others;
  local is always written as well. [U wish, C details]
- Profiles, each completely self-contained (all settings, home screen, addons, accounts, progress
  source). [U]
- Language: app German/English, switchable per profile [U]; audio track priority German → English →
  original [C, not objected to]; subtitles off by default, option available. [U]
- Picture/sound: Dolby Vision (P5, P8, P7→8.1) on a Dolby Vision TV; surround for a 5.1 speaker system that
  takes Dolby Digital from the TV over an optical link. [U setup]
- Autoplay of the next episode with the same source (Stremio `bingeGroup`), carrying over the audio
  and subtitle choice. [C]

**Non-goals (for now)**
- iPad app, a second Apple TV outside the home, iCloud/CloudKit sync, developer account. [U "only at
  home at first"] The data model must allow this later without a rebuild. [U]
- A collection editor of our own ("fiddly"). [U]
- ~~Direct TorBox integration in the app (login, cache check) – everything goes through AIOStreams. [C]~~
  Lifted: the app has its own TorBox client (W-2).
- ~~Atmos height channels / bitstream passthrough – the speakers cannot do it. [C from U setup]~~
  Lifted: passthrough is the default (W-1); height channels still depend on the sound system.
- Live TV, DVR, music.

**Anti-goals (would be a failure even if it works technically)**
- Arranging stays clumsy (menus, many clicks per step).
- Playback stutters / wrong picture (no DV logo) / only stereo on the speakers.
- Settings are lost on a reinstall (7-day signing).
- Having to type long URLs / API keys with the remote.

## 3. Constraints

- No Mac, no developer account. One Apple TV 4K on a current tvOS in the home network. [U]
- Signing + installing: a sideloading service (atvloadly) in the home network, Apple ID signing, automatic
  7-day refresh. [U] Free Apple ID: limited number of apps at the same time.
- Build: GitHub Actions macOS. At first a private repo, where macOS minutes count 10× (≈ 200 Mac
  minutes/month free) → bundle builds; test the platform-independent core locally on Linux (Swift
  container). [C] The repository is public today (W-16), and CI runs the core tests on Linux before every build.
- According to its own docs, AetherEngine requires Xcode 27 / Swift 6.4; compatibility with
  Xcode 26.3 is "best effort". GitHub's standard runners only have Xcode 26.x (as of the spike).
  → Risk, see §9.
- AetherEngine license: LGPL-3 with an App Store exception – no problem for private use.

## 4. Approaches (player engine)

| | Approach | Assessment |
|---|---|---|
| A | **AetherEngine alone** | DV P5/P8, P7→8.1, TrueHD/DTS-HD decoded, MKV; claims are self-reported |
| B | AetherEngine + AVPlayer | like A, double maintenance |
| C | KSPlayer | DV features are paid, marketing claims refuted in research |
| – | AVPlayer alone | no MKV/TrueHD/DTS-HD → out |

**Chosen: A, with a trial run first** (spike app "Player-Probe"). [U] The engine sits behind an
interface of our own, `PlayerEngine`, so B stays possible without rebuilding the app. [C]

## 5. Structure [C]

```
app/
  Packages/PlayerCore/        platform-independent, testable on Linux (Foundation only)
    Models/                   Profile, Collection/Folder/Source, HomeLayout, MediaItem, Progress
    Addons/                   Stremio protocol: Manifest, Catalog, Meta, Stream, Subtitles
    Services/                 TMDB, TVDB, MDBList, Trakt, Simkl (HTTP clients, token models)
    Import/                   Nuvio JSON, Trakt list, MDBList list, TMDB list/Discover, packs
    Ranking/                  stream ordering (language, resolution, DV/HDR, size, cache)
    Sync/                     progress: local + Trakt/Simkl, conflicts, offline queue
    Store/                    JSON files per profile, versioned, atomic
  Packages/PlaybackKit/       tvOS: PlayerEngine protocol + AetherEngine adapter
  App/                        SwiftUI tvOS app (XcodeGen project.yml)
```

- **Persistence:** Codable JSON per profile in Application Support, schema version in the document,
  atomic writes. Reason: testable on Linux, easy to back up, can later be mirrored as
  documents in CloudKit. Secrets (tokens, API keys) in the Keychain, encrypted/optional in the export.
  [C] (SwiftData rejected: not testable on Linux.)
- **Entering long text:** when needed, the app starts a small web server on the home network and shows
  a QR code; on the phone a page opens for pasting manifest URLs, API keys and import files (for
  example Nuvio JSON). Trakt/Simkl via their device-code login. [C]
- **Backup to a home server:** a phase after the core; a small service in the home network (its own
  sub-project). Until then: export/import via the phone page. [C]
- **Design language:** native tvOS focus engine, parallax, Top Shelf later; styles from the mockups
  `mockups/widget-stile.html` and `mockups/prototyp.html`.

## 6. Screens [C, home screen/editing U]

1. Profile selection (at launch, if there is more than 1 profile).
2. Home screen: rows from collections in the chosen style; continue watching row; editing as in §2.
3. Collection view: folders as tiles → a folder shows its sources as rows.
4. Detail page: hero with logo, ratings (MDBList), resume/play, seasons/episodes (TVDB order),
   source list (AIOStreams, ordered by the profile's preferences).
5. Player: AetherEngine surface, transport bar, audio/subtitle menu, next episode.
6. Search (TMDB + addon catalogs).
7. Settings per profile: addons, accounts, progress source, language, audio/subtitles, import
   collections, manage profile.

## 7. Phases [C]

- **P0** Spike: AetherEngine on the real TV (DV + 5.1). Running.
- **P1** Core: PlayerCore (models, store, Stremio client, TMDB, Nuvio import, ranking) with Linux tests;
  app skeleton: home screen (all 6 styles), detail, source list, player via PlaybackKit.
- **P2** Edit mode + plus selection + ready-made packs + Trakt/MDBList/TMDB import.
- **P3** Profiles + settings + phone input page (QR).
- **P4** Sync: Trakt/Simkl (device login, scrobble, continue watching), progress source.
- **P5** TVDB episodes, MDBList ratings, autoplay/bingeGroup, polish, home-server backup.

## 7a. Answers to the builder check [C]

- **Home screen row:** a row shows either a *list* (one source: TMDB Discover, Trakt list, addon
  catalog, continue watching, watchlist) in a title style (hero, poster, landscape, top 10) or a
  *collection* as folder tiles (style collection or logo tiles). If a folder has several sources, it
  opens a page with one row per source. The plus selection offers both.
- **Re-signing:** the same bundle ID and the same Apple ID give the same container, so the data is
  kept. Still, P1 already has a JSON export and import of all profiles (safety net). Tokens are in the
  Keychain and are also included in the export (the device is private).
- **Nuvio addon sources** (54 of 2224, `app.xperience.*`, no URL): the import skips them and remembers
  them. They become active as soon as an addon with this manifest ID is installed.
- **Duplicates:** same title → merge folders (same folder title → merge sources, sources deduplicated
  by `id`).
- **Stream order:** the AIOStreams order is kept (it is already configured there). The app only filters
  out streams that cannot be played and shows parsed attributes (resolution, DV/HDR, audio, size) as
  badges. So `Ranking` stays small.
- **Text input in P1:** via the tvOS system keyboard (the iPhone offers the input as a notification).
  The QR page comes in P3.
- **App slots:** a free Apple ID allows only a few apps at the same time (Player-Probe and the main app need two).
  The main app gets its own bundle ID `de.haskoman.player`; the probe can be removed after the test.

## 8. Left to the builder

Concrete type names, folder structure inside the packages, HTTP caching, image loader, exact focus
animations, error message texts, test split.

## 9. Risks and open points

- Xcode 27 for AetherEngine vs. Xcode 26.x on GitHub runners → if needed, pin an older AetherEngine
  version or use another runner. (The spike clarifies this.)
- DV/5.1 on real hardware not confirmed yet (the spike clarifies this, the user tests).
- ~~**[OPEN]** Make the repo public (unlimited Mac minutes) or keep it private (≈ 15–20 builds/month)?~~
  Closed: public.
- **[OPEN]** App name / icon.
- **[OPEN]** Which 2 ready-made packs? Proposal [C]: "Streaming services DE" (Netflix, Prime, Disney+,
  Apple TV+, WOW … from TMDB watch providers) and "Genres & moods".
- ~~**[OPEN]** API keys: the user's TMDB/MDBList/TVDB keys or our own? (TVDB requires its own key.)~~
  Closed: the user's own keys, entered on the phone page; TVDB is not used.
