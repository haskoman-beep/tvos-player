# P1 Core + App Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A platform-independent core (PlayerCore) with Linux tests plus a working tvOS skeleton: home screen from collections, detail, source list, playback via AetherEngine.

**Architecture:** `Packages/PlayerCore` (Foundation only, `swift test` in the container `docker.io/library/swift:6.2`), `Packages/PlaybackKit` (tvOS, PlayerEngine protocol + AetherEngine adapter), `App/` (SwiftUI, XcodeGen). CI only builds the app + PlaybackKit on macOS.

**Tech Stack:** Swift 6 / Swift Testing, SwiftUI tvOS 18+, AetherEngine 7.71.2, XcodeGen, GitHub Actions macos-26 + Xcode 26.3.

**Spec:** `docs/superpowers/specs/2026-11-21-tvos-player-design.md`

## Global Constraints

- tvOS 18.0 minimum; bundle ID `de.haskoman.player`; display name "Player" for now (name [OPEN]).
- PlayerCore imports only Foundation (+ FoundationNetworking on Linux).
- Persistence: Codable JSON per profile, `schemaVersion` in the document, atomic writes.
- Audio track priority German → English → original; subtitles off by default.
- The AIOStreams stream order is kept; only streams that cannot be played are removed.
- No API keys in the repo; keys are entered at runtime.
- Tests: `cd Packages/PlayerCore && podman run --rm -v "$PWD":/pkg:Z -w /pkg docker.io/library/swift:6.2 swift test`

## Review Focus

- Nuvio export with unknown fields/source types → the import skips them and does not abort (Task 4).
- Damaged or older profile file → loading falls back to the default profile, the old file is kept as `.bak` (Task 3).
- Edit mode: cancel restores exactly the state before the long press (Task 6).
- Stream without `url` or with a broken URL → not in the list, no crash (Task 5).
- An addon answers slowly or not at all → the other addons still appear (Task 1, done).

---

### Task 1: Stremio addon client — DONE (1b85576)

**Produces:** `AddonClient.install(manifestURL:) -> InstalledAddon`, `.streams(_:type:id:)`, `.streams(from:type:id:)`, `.catalog(...)`, `.meta(...)`; `StreamItem`, `MetaPreview`, `MetaDetail`, `HTTPFetching`.

### Task 2: Models

**Files:** Create `Sources/PlayerCore/Models/{Collection,Home,Profile}.swift`, Test `Tests/PlayerCoreTests/ModelTests.swift`

**Produces:**
- `struct CatalogSource: Codable, Identifiable, Hashable { id, title, kind: SourceKind, mediaType: MediaType }`
- `enum SourceKind: Codable { tmdbDiscover(filters: [String: String]), tmdbList(id: String), tmdbCompany(id: String), tmdbCollection(id: String), trakt(user: String?, list: String), addon(addonId: String, catalogId: String, type: String), continueWatching, watchlist }`
- `enum MediaType: String, Codable { movie, series, both }`
- `struct Folder { id, title, image: String?, sources: [CatalogSource] }`, `struct Collection { id, title, folders: [Folder] }`
- `enum RowStyle: String, Codable, CaseIterable { hero, poster, landscape, top10, logoTiles, collectionTiles }`
- `enum RowContent: Codable, Hashable { list(CatalogSource), collection(id: String) }`; `RowContent.allowedStyles: [RowStyle]` (list → hero/poster/landscape/top10; collection → collectionTiles/logoTiles)
- `struct HomeRow { id: UUID, content: RowContent, style: RowStyle }`, `struct HomeLayout { rows: [HomeRow] }`
- `struct Profile { id: UUID, name, language: AppLanguage (.de/.en), audioPriority: [String] = ["de","en","orig"], subtitlesEnabled = false, progressSource: ProgressSource (.local/.trakt/.simkl), addons: [InstalledAddon], collections: [Collection], home: HomeLayout, apiKeys: [String: String] }`

- [ ] Test `profileRoundTrip`: encode/decode a profile with 1 collection and 2 rows → equal; `Profile.makeDefault(name:)` has `audioPriority == ["de","en","orig"]`, `subtitlesEnabled == false`, `progressSource == .local`.
- [ ] Test `allowedStyles`: `.list(...)` does not contain `.collectionTiles`; `.collection` contains only `[.collectionTiles, .logoTiles]`.
- [ ] Implement, tests green, commit.

### Task 3: ProfileStore

**Files:** Create `Sources/PlayerCore/Store/ProfileStore.swift`, Test `StoreTests.swift`

**Produces:** `struct StoredProfiles: Codable { schemaVersion: Int = 1, profiles: [Profile], activeProfileID: UUID? }`; `final class ProfileStore { init(directory: URL); func load() -> StoredProfiles; func save(_:) throws; func exportData(_:) throws -> Data; func importData(_ data: Data) throws -> StoredProfiles }`. File `profiles.json`, written with `.atomic`.

- [ ] Tests: `saveThenLoad` (equal); `missingFileGivesDefault` (1 profile „Ich“ (me)); `corruptFileFallsBackAndKeepsBackup` (garbage in profiles.json → default, `profiles.json.bak` exists with the garbage); `exportImportRoundTrip`.
- [ ] Implement, green, commit.

### Task 4: Nuvio import

**Files:** Create `Sources/PlayerCore/Import/NuvioImport.swift`, Test `NuvioImportTests.swift` (fixture `Fixtures/nuvio.json`)

**Produces:** `enum NuvioImport { static func parse(_ data: Data) throws -> NuvioImportResult }`; `struct NuvioImportResult { collections: [Collection], skippedSources: Int, pendingAddonSources: [CatalogSource] }`.

Mapping: `provider tmdb` + `tmdbSourceType` DISCOVER → `.tmdbDiscover(filters)` (keep the snake_case keys, values as strings), LIST/COMPANY/COLLECTION → the matching cases with `id` from `tmdbId`/`listId`/`filters`; `trakt` → `.trakt`; `addon` → `.addon` and also into `pendingAddonSources`. Anything unknown → `skippedSources += 1`. Duplicates: same collection title → merge folders; same folder title → merge sources, deduplicate by `id`.

- [ ] Tests with the fixture: 16 raw collections → 9 titles; "Streaming" has ≥ 22 folders; no duplicate source IDs in one folder; `pendingAddonSources.count == 54`; Netflix folder, source "New Movies" has `with_watch_providers == "8|1796"`.
- [ ] Test `unknownFieldsIgnored`: minimal JSON with extra fields and `provider: "foo"` → 0 collection errors, `skippedSources == 1`.
- [ ] Implement, green, commit.

### Task 5: Stream attributes

**Files:** Create `Sources/PlayerCore/Ranking/StreamTraits.swift`, Test `StreamTraitsTests.swift`

**Produces:** `struct StreamTraits: Equatable { resolution: String?, hdr: [String] (DV/HDR10+/HDR10/HDR), audio: [String] (Atmos/TrueHD/DTS-HD MA/DTS/DD+/DD/AAC), languages: [String], sizeBytes: Int64?, cached: Bool? }`; `StreamTraits.parse(_ s: StreamItem)`; `func playableStreams(_ s: [StreamItem]) -> [StreamItem]` (order is kept).

- [ ] Tests: "Breaking.Bad.S01E02.2160p.DV.HDR.TrueHD.Atmos 🇩🇪 💾 45.2 GB" → 2160p, ["DV","HDR"], ["Atmos","TrueHD"], sizeBytes ≈ 45.2e9; name "[TB⚡]" → cached true, "[TB⏳]"/"[TB download]" → false; `playableStreams` removes infoHash-only streams and `url: "nicht eine url"` (not a URL), keeps the order.
- [ ] Implement, green, commit.

### Task 6: Home screen editing (state machine)

**Files:** Create `Sources/PlayerCore/Models/HomeEditor.swift`, Test `HomeEditorTests.swift`

**Produces:** `struct HomeEditor { private(set) var layout: HomeLayout; private(set) var grabbed: UUID?; init(layout:); mutating func grab(_ id: UUID); moveUp(); moveDown(); nextStyle(); previousStyle(); removeGrabbed(); add(_ content: RowContent) /* at the end, grabbed, first allowed style */; func commit() -> HomeLayout; func cancel() -> HomeLayout /* original */ ; func availableToAdd(collections: [Collection], extraLists: [CatalogSource]) -> [RowContent] /* not on the home screen */ }`.

- [ ] Tests: moveUp at position 0 stays; moveDown at the last position stays; nextStyle cycles only through `allowedStyles`; removeGrabbed → `grabbed == nil`, row gone; `add` → new row at the end and grabbed; after several changes `cancel()` == original; `availableToAdd` contains a removed collection again.
- [ ] Implement, green, commit.

### Task 7: TMDB client

**Files:** Create `Sources/PlayerCore/Services/TMDBClient.swift`, Test `TMDBTests.swift`

**Produces:** `struct TMDBClient { init(apiKey: String, language: String = "de-DE", http: HTTPFetching); func items(for source: CatalogSource, page: Int = 1) async throws -> [MetaPreview]; func imdbID(tmdbID: Int, type: MediaType) async throws -> String? }`. Images `https://image.tmdb.org/t/p/w500` (poster) / `w1280` (background). Discover: `/3/discover/{movie|tv}?api_key=…&language=…&page=…&<filters>`; `MediaType.both` → movie + tv mixed. MetaPreview.id = `tmdb:<id>`, type movie/series.

- [ ] Tests with FakeHTTP: the Discover URL contains `with_watch_providers=8%7C1796` and `watch_region=DE`; a response with 2 results → 2 MetaPreview with a poster URL; `imdbID` reads `external_ids.imdb_id`.
- [ ] Implement, green, commit.

### Task 8: PlaybackKit

**Files:** Create `Packages/PlaybackKit/Package.swift` (tvOS 18, dependency AetherEngine `from: "7.71.2"`), `Sources/PlaybackKit/PlayerEngine.swift`, `AetherPlayerEngine.swift`

**Produces:** `@MainActor protocol PlayerEngine: ObservableObject { var isPlaying: Bool; var currentTime: Double; var duration: Double; var audioTracks: [AudioTrack]; func load(_ url: URL, start: Double) async throws; func play(); func pause(); func seek(_ t: Double) async; func selectAudio(_ id: Int); func stop() }`; `func preferredAudioTrack(_ tracks: [AudioTrack], priority: [String]) -> AudioTrack?` (in PlayerCore, tested on Linux: de before en before the first track); `AetherPlayerEngine` + `PlayerSurface: View`.

- [ ] Test (PlayerCore) `preferredAudioTrackPicksGermanThenEnglish`.
- [ ] Write the adapter; compiling only in CI (Task 9). Commit.

### Task 9: App skeleton + CI

**Files:** `App/project.yml`, `App/Sources/{PlayerApp,AppModel,HomeView,RowViews,DetailView,StreamListView,PlayerView,SettingsView}.swift`, `.github/workflows/build.yml` (as in the spike: macos-26, Xcode 26.3, unsigned, IPA artifact).

- `AppModel` (@MainActor, ObservableObject): loads `ProfileStore` from Application Support, the active profile, saves on change.
- Home screen: rows by `RowStyle`; long press → `HomeEditor` (▲▼/◀▶/Play-Pause/OK/Back as in spec §2), plus tile only in edit mode.
- Detail → streams (all addons, `playableStreams`, badges from `StreamTraits`) → player.
- Settings: add a manifest URL, TMDB key, import Nuvio JSON via URL, export.
- [ ] Push, CI green, install the IPA via `tools/atv_install.mjs`. Commit.
