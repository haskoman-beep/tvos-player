# P1 Kern + App-Gerüst Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plattformunabhängiger Kern (PlayerCore) mit Linux-Tests plus lauffähiges tvOS-Gerüst: Startseite aus Collections, Detail, Quellenliste, Wiedergabe über AetherEngine.

**Architecture:** `Packages/PlayerCore` (Foundation only, `swift test` im Container `docker.io/library/swift:6.2`), `Packages/PlaybackKit` (tvOS, PlayerEngine-Protokoll + AetherEngine-Adapter), `App/` (SwiftUI, XcodeGen). CI baut nur App + PlaybackKit auf macOS.

**Tech Stack:** Swift 6 / Swift Testing, SwiftUI tvOS 18+, AetherEngine 7.71.2, XcodeGen, GitHub Actions macos-26 + Xcode 26.3.

**Spec:** `docs/superpowers/specs/2026-11-21-tvos-player-design.md`

## Global Constraints

- tvOS 18.0 Mindestversion; Bundle-ID `de.haskoman.player`; Anzeigename vorläufig "Player" (Name [OFFEN]).
- PlayerCore importiert nur Foundation (+ FoundationNetworking unter Linux).
- Persistenz: Codable-JSON pro Profil, `schemaVersion` im Dokument, atomares Schreiben.
- Tonspur-Vorrang Deutsch → Englisch → Original; Untertitel Standard aus.
- Stream-Reihenfolge von AIOStreams bleibt; nur nicht abspielbare Streams raus.
- Keine API-Keys im Repo; Keys werden zur Laufzeit eingegeben.
- Tests: `cd Packages/PlayerCore && podman run --rm -v "$PWD":/pkg:Z -w /pkg docker.io/library/swift:6.2 swift test`

## Review Focus

- Nuvio-Export mit unbekannten Feldern/Quelltypen → Import überspringt, bricht nicht ab (Task 4).
- Beschädigte oder ältere Profil-Datei → Laden fällt auf Standardprofil zurück, alte Datei bleibt als `.bak` (Task 3).
- Bearbeiten-Modus: Abbrechen stellt den Zustand vor dem langen Druck exakt wieder her (Task 6).
- Stream ohne `url` oder mit kaputter URL → nicht in der Liste, kein Absturz (Task 5).
- Addon antwortet langsam/gar nicht → andere Addons erscheinen trotzdem (Task 1, erledigt).

---

### Task 1: Stremio-Addon-Client — ERLEDIGT (1b85576)

**Produces:** `AddonClient.install(manifestURL:) -> InstalledAddon`, `.streams(_:type:id:)`, `.streams(from:type:id:)`, `.catalog(...)`, `.meta(...)`; `StreamItem`, `MetaPreview`, `MetaDetail`, `HTTPFetching`.

### Task 2: Modelle

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

- [ ] Test `profileRoundTrip`: Profil mit 1 Collection, 2 Reihen kodieren/dekodieren → gleich; `Profile.makeDefault(name:)` hat `audioPriority == ["de","en","orig"]`, `subtitlesEnabled == false`, `progressSource == .local`.
- [ ] Test `allowedStyles`: `.list(...)` enthält nicht `.collectionTiles`; `.collection` enthält nur `[.collectionTiles, .logoTiles]`.
- [ ] Implementieren, Tests grün, Commit.

### Task 3: ProfileStore

**Files:** Create `Sources/PlayerCore/Store/ProfileStore.swift`, Test `StoreTests.swift`

**Produces:** `struct StoredProfiles: Codable { schemaVersion: Int = 1, profiles: [Profile], activeProfileID: UUID? }`; `final class ProfileStore { init(directory: URL); func load() -> StoredProfiles; func save(_:) throws; func exportData(_:) throws -> Data; func importData(_ data: Data) throws -> StoredProfiles }`. Datei `profiles.json`, Schreiben mit `.atomic`.

- [ ] Tests: `saveThenLoad` (gleich); `missingFileGivesDefault` (1 Profil "Ich"); `corruptFileFallsBackAndKeepsBackup` (Müll in profiles.json → Default, `profiles.json.bak` existiert mit Müll); `exportImportRoundTrip`.
- [ ] Implementieren, grün, Commit.

### Task 4: Nuvio-Import

**Files:** Create `Sources/PlayerCore/Import/NuvioImport.swift`, Test `NuvioImportTests.swift` (Fixture `Fixtures/nuvio.json`)

**Produces:** `enum NuvioImport { static func parse(_ data: Data) throws -> NuvioImportResult }`; `struct NuvioImportResult { collections: [Collection], skippedSources: Int, pendingAddonSources: [CatalogSource] }`.

Abbildung: `provider tmdb` + `tmdbSourceType` DISCOVER→`.tmdbDiscover(filters)` (snake_case-Schlüssel behalten, Werte als String), LIST/COMPANY/COLLECTION → jeweilige Fälle mit `id` aus `tmdbId`/`listId`/`filters`; `trakt` → `.trakt`; `addon` → `.addon` und zusätzlich in `pendingAddonSources`. Unbekanntes → `skippedSources += 1`. Dubletten: gleicher Collection-Titel → Ordner vereinigen; gleicher Ordnertitel → Quellen vereinigen, nach `id` entdoppeln.

- [ ] Tests mit Fixture: 16 Rohcollections → 9 Titel; "Streaming" hat ≥ 22 Ordner; keine doppelten Quellen-IDs in einem Ordner; `pendingAddonSources.count == 54`; Netflix-Ordner, Quelle "New Movies" hat `with_watch_providers == "8|1796"`.
- [ ] Test `unknownFieldsIgnored`: Minimal-JSON mit Zusatzfeldern und `provider: "foo"` → 0 Collections-Fehler, `skippedSources == 1`.
- [ ] Implementieren, grün, Commit.

### Task 5: Stream-Merkmale

**Files:** Create `Sources/PlayerCore/Ranking/StreamTraits.swift`, Test `StreamTraitsTests.swift`

**Produces:** `struct StreamTraits: Equatable { resolution: String?, hdr: [String] (DV/HDR10+/HDR10/HDR), audio: [String] (Atmos/TrueHD/DTS-HD MA/DTS/DD+/DD/AAC), languages: [String], sizeBytes: Int64?, cached: Bool? }`; `StreamTraits.parse(_ s: StreamItem)`; `func playableStreams(_ s: [StreamItem]) -> [StreamItem]` (Reihenfolge bleibt).

- [ ] Tests: "Breaking.Bad.S01E02.2160p.DV.HDR.TrueHD.Atmos 🇩🇪 💾 45.2 GB" → 2160p, ["DV","HDR"], ["Atmos","TrueHD"], sizeBytes ≈ 45.2e9; name "[TB⚡]" → cached true, "[TB⏳]"/"[TB download]" → false; `playableStreams` entfernt infoHash-only und `url: "nicht eine url"`, behält Reihenfolge.
- [ ] Implementieren, grün, Commit.

### Task 6: Startseiten-Bearbeitung (Zustandsmaschine)

**Files:** Create `Sources/PlayerCore/Models/HomeEditor.swift`, Test `HomeEditorTests.swift`

**Produces:** `struct HomeEditor { private(set) var layout: HomeLayout; private(set) var grabbed: UUID?; init(layout:); mutating func grab(_ id: UUID); moveUp(); moveDown(); nextStyle(); previousStyle(); removeGrabbed(); add(_ content: RowContent) /* hinten, angefasst, erster erlaubter Stil */; func commit() -> HomeLayout; func cancel() -> HomeLayout /* Original */ ; func availableToAdd(collections: [Collection], extraLists: [CatalogSource]) -> [RowContent] /* nicht auf Startseite */ }`.

- [ ] Tests: moveUp an Position 0 bleibt; moveDown an letzter bleibt; nextStyle durchläuft nur `allowedStyles` zyklisch; removeGrabbed → `grabbed == nil`, Reihe weg; `add` → neue Reihe am Ende und angefasst; nach mehreren Änderungen `cancel()` == Original; `availableToAdd` enthält entfernte Collection wieder.
- [ ] Implementieren, grün, Commit.

### Task 7: TMDB-Client

**Files:** Create `Sources/PlayerCore/Services/TMDBClient.swift`, Test `TMDBTests.swift`

**Produces:** `struct TMDBClient { init(apiKey: String, language: String = "de-DE", http: HTTPFetching); func items(for source: CatalogSource, page: Int = 1) async throws -> [MetaPreview]; func imdbID(tmdbID: Int, type: MediaType) async throws -> String? }`. Bilder `https://image.tmdb.org/t/p/w500` (Poster) / `w1280` (Hintergrund). Discover: `/3/discover/{movie|tv}?api_key=…&language=…&page=…&<filters>`; `MediaType.both` → movie + tv gemischt. MetaPreview.id = `tmdb:<id>`, type movie/series.

- [ ] Tests mit FakeHTTP: Discover-URL enthält `with_watch_providers=8%7C1796` und `watch_region=DE`; Antwort mit 2 Ergebnissen → 2 MetaPreview mit Poster-URL; `imdbID` liest `external_ids.imdb_id`.
- [ ] Implementieren, grün, Commit.

### Task 8: PlaybackKit

**Files:** Create `Packages/PlaybackKit/Package.swift` (tvOS 18, Abhängigkeit AetherEngine `from: "7.71.2"`), `Sources/PlaybackKit/PlayerEngine.swift`, `AetherPlayerEngine.swift`

**Produces:** `@MainActor protocol PlayerEngine: ObservableObject { var isPlaying: Bool; var currentTime: Double; var duration: Double; var audioTracks: [AudioTrack]; func load(_ url: URL, start: Double) async throws; func play(); func pause(); func seek(_ t: Double) async; func selectAudio(_ id: Int); func stop() }`; `func preferredAudioTrack(_ tracks: [AudioTrack], priority: [String]) -> AudioTrack?` (in PlayerCore, Linux-getestet: de vor en vor erste Spur); `AetherPlayerEngine` + `PlayerSurface: View`.

- [ ] Test (PlayerCore) `preferredAudioTrackPicksGermanThenEnglish`.
- [ ] Adapter schreiben; Kompilieren nur in CI (Task 9). Commit.

### Task 9: App-Gerüst + CI

**Files:** `App/project.yml`, `App/Sources/{PlayerApp,AppModel,HomeView,RowViews,DetailView,StreamListView,PlayerView,SettingsView}.swift`, `.github/workflows/build.yml` (wie Spike: macos-26, Xcode 26.3, unsigniert, IPA-Artefakt).

- `AppModel` (@MainActor, ObservableObject): lädt `ProfileStore` aus Application Support, aktives Profil, speichert bei Änderung.
- Startseite: Reihen nach `RowStyle`; langer Druck → `HomeEditor` (▲▼/◀▶/Play-Pause/OK/Zurück wie Spec §2), Plus-Kachel nur im Bearbeiten-Modus.
- Detail → Streams (alle Addons, `playableStreams`, Plaketten aus `StreamTraits`) → Player.
- Einstellungen: Manifest-URL hinzufügen, TMDB-Key, Nuvio-JSON per URL importieren, Export.
- [ ] Push, CI grün, IPA per `tools/atv_install.mjs` installieren. Commit.
