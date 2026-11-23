# 05 · Code-Review (Qualität)

Stand: Branch `integ`, Commit `b2188a2` (Build 249). Rein lesend und statisch erhoben; Laufzeitverhalten ist aus dem Code **abgeleitet**. Alle `Datei:Zeile`-Angaben beziehen sich auf diesen Commit.

Methodik: Skills `code-review` (Stufe `high`, gesamter Code statt Diff), `simplify` als reine Analyse und
`design:accessibility-review`. Bugs stehen in [02-bugs.md](02-bugs.md) und werden hier nicht wiederholt. Die
Umsetzung der Empfehlungen steht im [Plan](../../plans/2026-11-22-verbesserungen.md), vor allem in Build 1 (Q-22),
Build 5 (Q-26 bis Q-29) und Build 6 (Q-1 bis Q-21).

Umfang: `App/Sources` und `Packages/PlayerCore` (Quellen + Tests), dazu `App/project.yml`, `.github/workflows/build.yml`, `README.md`.
Methode: Metriken über alle Dateien (`wc`, `grep`, ein Skript für Typ-/`body`-/Funktionslängen), vollständig gelesen: `AppModel.swift`, `DetailViews.swift`, `PlayerApp.swift`, `Theme.swift`, `Profile.swift`, `DesignText.swift`, `ISODate.swift`; weitgehend gelesen: `PlayerScreen.swift` (Zeilen 1–600 ganz, Rest über Funktionsliste), `RowViews.swift` (1–130, 300–500, 585–652); über Deklarationsliste und gezielte Ausschnitte: alle `AppModel+*.swift`, `SettingsKit.swift`, `ImagePipeline.swift`, `AppUpdate.swift`, Stichproben aus allen Ordnern. Nichts gebaut, nichts ausgeführt. Kontrastwerte sind gerechnete Schätzungen, keine Messungen.

## Gesamteindruck

| Kennzahl | App | PlayerCore | Tests |
|---|---|---|---|
| Swift-Dateien | 107 | 132 | 75 |
| Zeilen (LOC inkl. Kommentare) | 20 041 | 20 064 | 13 607 |
| Kommentarzeilen (`//`, `///`) | 2 427 | 3 231 | – |
| `@Test` / `#expect` | – | – | 965 / 4 546 |
| TODO/FIXME/HACK, auskommentierter Code | 0 | 0 | 0 |
| `fatalError` / `try!` / `as!` | 0 / 0 / 1 | 0 / 8 / 2 | 2 / 6 / 2 |

Das Projekt ist deutlich besser als sein Dateizuschnitt vermuten lässt. Stärken: Die Hälfte des Codes liegt als reine, plattformfreie Logik in PlayerCore und ist dicht getestet (965 Tests, Verhalten statt Defaults, keine Netzabhängigkeit, Fakes für HTTP und Ablage). Es gibt ein echtes Designsystem (`Theme`, `ThemeBadge`, `SettingsRow`, `StatusCard`) mit eigener Kontrast- und VoiceOver-Überlegung. Kein toter Kommentar-Code, keine TODOs, praktisch keine Force-Unwraps (4 im ganzen Core, alle auf zuvor gefüllte Wörterbücher). Fehlerpfade sind fast überall geloggt.

Die Schwächen sind struktureller Art und hängen zusammen:

1. **Drei Großtypen tragen die App**: `PlayerControls` (721 Zeilen, 45 `@State`, 27 Parameter, über 8 Dateien verteilt), `AppModel` (599 Zeilen plus 1 199 Zeilen in 13 Erweiterungsdateien, 123 Funktionen) und `DetailView`/`StreamListView` (584 bzw. 242 Zeilen plus 218 Zeilen Erweiterung, 28 bzw. 19 `@State`). In ihnen steckt Ablauflogik (Fehlerleiter, Autoplay, Rückfall auf die nächste Quelle), die in Views nicht testbar ist.
2. **Die App läuft im Swift-5-Sprachmodus** (`SWIFT_VERSION: "5.0"`), das Paket im Swift-6-Modus. Die 19 Singletons und rund 23 `static var` der App werden vom Compiler nicht auf Datenrennen geprüft.
3. **Tests laufen nicht in CI.** `build.yml` baut nur das IPA; `swift test` kommt nicht vor.
4. **Es gibt keine Lokalisierung.** Die Oberfläche ist fest deutsch; das README verspricht „German and English“. Die Profilsprache steuert nur TMDB-Inhalte und Trailer.
5. **Barrierefreiheit ist zweigeteilt**: die Designsystem-Bausteine sind beschriftet, die Kacheln der Startseite und der gesamte Player nicht. „Bewegung reduzieren“ und „Transparenz reduzieren“ werden nirgends gelesen.

Zusammenfassung der Befunde: 29 (hoch 8 · mittel 14 · niedrig 7).

---

## 1. Größe und Verantwortlichkeiten

### Top 15 Dateien

| # | Datei | Zeilen |
|---|---|---|
| 1 | `App/Sources/Views/DetailViews.swift` | 1 468 |
| 2 | `App/Sources/Views/PlayerScreen.swift` | 840 |
| 3 | `App/Sources/Playback/DiskCacheProxy.swift` | 783 |
| 4 | `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift` | 740 |
| 5 | `App/Sources/AppModel.swift` | 716 |
| 6 | `App/Sources/Views/RowViews.swift` | 679 |
| 7 | `App/Sources/Views/Player/PlayerSidePanel.swift` | 598 |
| 8 | `App/Sources/Views/Player/PlayerScrub.swift` | 595 |
| 9 | `App/Sources/ImagePipeline.swift` | 572 |
| 10 | `App/Sources/Views/Player/PlayerTrackPanel.swift` | 557 |
| 11 | `App/Sources/Views/FocusVideo.swift` | 535 |
| 12 | `App/Sources/Views/Design/Theme.swift` | 475 |
| 13 | `Packages/PlayerCore/Sources/PlayerCore/Addons/StremioModels.swift` | 450 |
| 14 | `App/Sources/CollectionLinkStore.swift` | 449 |
| 15 | `App/Sources/FusionKitStore.swift` | 425 |

### Größte Typen, `body`-Funktionen und Funktionen

| Typ (Zeilen) | `body` (Zeilen) | Längste Funktionen (Zeilen) |
|---|---|---|
| `PlayerControls` 721 (`PlayerScreen.swift:120`) | `DetailView.body` 220 (`DetailViews.swift:106`) | `PlayerControls.recover` 129 (`PlayerScreen.swift:675`) |
| `AppModel` 599 (`AppModel.swift:6`) | `StreamListView.body` 187 (`DetailViews.swift:744`) | `FocusVideoPlayer.start` 83 (`FocusVideo.swift:206`) |
| `DetailView` 584 (`DetailViews.swift:46`) | `PlayerControls.body` 174 (`PlayerScreen.swift:238`) | `CollectionLinkStore.importData` 78 (`CollectionLinkStore.swift:302`) |
| `FusionKitStore` 417 | `HomeManagerContent.body` 81 | `TMDBClient.parseLocalized` 71 (`TMDBLocalized.swift:77`) |
| `CollectionLinkStore` 397 | `HomeView.body` 72 | `DiskCacheProxy.serve` 62 (`DiskCacheProxy.swift:670`) |
| `ImagePipeline` 352 | `PlayerScreen.body` 68 | `DetailView.episodes` 61 (`DetailViews.swift:568`) |

Zeilenlänge: 48 Zeilen der App sind länger als 160 Zeichen, die längste hat 450 (`PlayerScreen.swift:357`).

### Zustand je Großtyp

| Typ | `@State` | `@StateObject`/`@ObservedObject` | Parameter | Sonstiges |
|---|---|---|---|---|
| `PlayerControls` | 45 (22 davon nicht `private`) | 5 | 27 | 15 `.onChange`, 1-s-Timer, 6 gehaltene Tasks |
| `DetailView` | 28 | 1 (`model`) | 1 | 10 Lebenszyklus-Modifikatoren am `body` |
| `StreamListView` | 19 | 1 | 1 | 4 nicht gehaltene `Task { sleep … }` |
| `AppModel` | – | 7 `@Published` | – | 28 gespeicherte Eigenschaften, 123 Funktionen |
| `HomeRowView` | 4 + 2 `@FocusState` | 3 | 4 | `task(id:)` mit zusammengesetztem String-Schlüssel |

### Q-1: `PlayerControls` ist ein 721-Zeilen-View mit 45 `@State`, verteilt über 8 Dateien
- **Ort:** `App/Sources/Views/PlayerScreen.swift:120`, `App/Sources/Views/PlayerScreen.swift:150`–`236`, Erweiterungen in `App/Sources/Views/Player/PlayerExit.swift:10`, `PlayerLifecycle.swift:34`, `PlayerStability.swift:44`, `PlayerPictureSound.swift:49`, `PlayerScrub.swift:578`, `PlayerSidePanel.swift:136`, `AddonSubtitleLoader.swift:78`
- **Beobachtung:** Der View enthält Laden und Start (`loadAndStart`, `:414`), Fehlerleiter (`recover`, `:675`, 129 Zeilen), Up-next-Zähler (`upNextTick`, `:465`), Tonwechsel-Wächter, Bildschirmschoner, Scrobble, Spur-Gedächtnis, Now Playing, Seitenpanel. Damit die Erweiterungen in anderen Dateien an den Zustand kommen, sind 22 `@State` bewusst nicht `private` (z. B. `:151`, `:158`, `:172`, `:181`, `:198`, `:225`). Die Entscheidungsregeln selbst liegen bereits sauber in PlayerCore (`RecoveryPlanner`, `TrackLock`, `PlayerMenuStep`, `PauseCardRule`), das Zusammenspiel aber im View.
- **Auswirkung:** Jede Änderung an einer der Abläufe muss 45 Zustandsfelder und rund 20 Sperrbedingungen im Kopf behalten (`!leaving && !restorePending && !restoring && !showTracks && !sideOpen`, in Varianten an `:258`, `:267`, `:347`). Nichts davon ist testbar; SwiftUI wertet den 174-Zeilen-`body` bei jedem Takt neu aus (`let _ = tick`, `:506`).
- **Empfehlung:** Einen `@MainActor`-Zustandsträger `PlayerSession` (Observable) einführen, der Engine, Lebenszyklus, Fehlerleiter, Up-next und Sperren hält; `PlayerControls` zeichnet nur noch. Die Sperrbedingungen als eine berechnete `PlayerLocks`-Struktur (in PlayerCore, testbar). Schnitt: `PlayerSession.swift`, `PlayerSession+Recovery.swift`, `PlayerSession+UpNext.swift`, `PlayerOverlay.swift` (Steuerleiste), `PlayerInput.swift` (Tasten).
- **Priorität:** hoch · **Aufwand:** L · **Sicherheit:** bestätigt

### Q-2: `PlayerControls` hat 27 Aufrufparameter, 14 davon Closures
- **Ort:** `App/Sources/Views/PlayerScreen.swift:46`–`85`, `App/Sources/Views/PlayerScreen.swift:121`–`180`
- **Beobachtung:** `PlayerScreen.body` baut `PlayerControls` mit einem 40-Zeilen-Aufruf; `isTrailer`/`ownProgress` werden dabei neunmal einzeln ausgewertet (`:47`, `:48`, `:57`–`59`, `:62`, `:67`, `:68`, `:75`–`79`, `:85`).
- **Auswirkung:** Eine neue Abspielart (nach Trailer und TorBox-Datei) muss an neun Stellen richtig verzweigen; ein vergessener Zweig fällt erst am Gerät auf.
- **Empfehlung:** Eine Konfigurationsstruktur `PlaybackContext` mit Fabriken `.title(request:)`, `.trailer(…)`, `.ownFile(…)`, die alle abgeleiteten Werte einmal setzt; die Rückrufe als ein Protokoll `PlayerHost`.
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt

### Q-3: `StreamListView` enthält die Abspiel-Orchestrierung (Rückfall, Autoplay, nächste Folge)
- **Ort:** `App/Sources/Views/DetailViews.swift:690`–`931`, `App/Sources/Views/DetailViews.swift:933`–`1150`, `App/Sources/AppModel+StreamSearch.swift:151`
- **Beobachtung:** Der View entscheidet, welche Quelle automatisch startet (`:837`–`900`), wechselt bei Fehlern die Quelle (`fallback`, `:1076`), sucht und startet die nächste Folge (`startNext`, `:1122`), verwaltet „Noch da?“ und den Fokus nach dem Player. Vier nicht gehaltene Tasks mit festen Wartezeiten steuern die Übergänge (`:1060` 900 ms, `:1093` 900 ms, `:1109` 700 ms, `:1145` 800 ms), jeweils abgesichert nur durch `guard playing == nil`. Die Grenze „höchstens 3 Wechsel“ steht zweimal als Literal (`:1083`, `:1091`).
- **Auswirkung:** Der wichtigste Ablauf der App (Quelle versagt → nächste) ist nur am Gerät prüfbar. Die Tasks laufen nach dem Verlassen der Seite weiter, weil niemand sie abbricht.
- **Empfehlung:** Einen `PlaybackQueue`-Zustandsautomaten nach PlayerCore ziehen (Eingaben: Liste, `failed`, Ereignis; Ausgabe: nächster Schritt mit Wartezeit), dazu einen `@MainActor`-Koordinator in der App, der die Tasks hält und beim Verschwinden abbricht. Wartezeiten und Wechselgrenze als benannte Konstanten.
- **Priorität:** hoch · **Aufwand:** L · **Sicherheit:** bestätigt

### Q-4: `DetailViews.swift` bündelt 17 Typen und 5 Bildschirme
- **Ort:** `App/Sources/Views/DetailViews.swift:6`, `:23`, `:46`, `:641`, `:659`, `:671`, `:690`, `:1169`, `:1219`, `:1230`, `:1235`, `:1276`, `:1321`, `:1454`
- **Beobachtung:** Die Datei enthält Ordnerseite, Collection-Seite, Detailseite, Quellenliste, Suche, dazu Bausteine (`FocusHighlight`, `FullTextSheet`, `InfoBadges`, `StreamRow`) und die freie Funktion `timeText`. `DetailView` selbst hält 28 `@State`, davon 9 nur für Messung und Log (`appeared`, `badgesLogged`, `timeline`, `entryFocusAt` …, `:69`–`77`) und 8 nur für die Fokus-Rückkehr (`:91`–`100`). Der `.task` an `:195`–`267` ist 72 Zeilen lang und mischt Laden, Messen und Fokus.
- **Auswirkung:** Suche und Quellenliste sind nur über den Dateinamen „Detail“ zu finden; Änderungen an der Fokuslogik berühren denselben `body` wie das Laden.
- **Empfehlung:** Schnitt in `Views/Detail/DetailView.swift`, `DetailView+Loading.swift` (ein `DetailLoader`, Observable), `DetailView+Focus.swift`, `DetailEpisodes.swift`, `DetailExtras.swift`, `Views/Streams/StreamListView.swift`, `StreamRow.swift`, `Views/SearchView.swift`, `Views/CollectionViews.swift`, `Views/Design/FocusHighlight.swift`. Messzustand in eine Struktur `DetailLoadProbe` zusammenfassen.
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt

### Q-5: `AppModel` ist ein Gott-Objekt mit 1 915 Zeilen über 14 Dateien
- **Ort:** `App/Sources/AppModel.swift:6`, `App/Sources/AppModel.swift:532`–`546`, `App/Sources/AppModel+*.swift` (13 Dateien), `App/Sources/Views/SettingsView.swift:95`, `App/Sources/Views/Settings/SourceSettingsRows.swift:51`, `App/Sources/Views/Player/SkipSegmentButton.swift:4`, `App/Sources/Views/Player/AddonSubtitleLoader.swift:11`
- **Beobachtung:** Verantwortlichkeiten: Profile und Ablage, Fortschritt, Trakt/Simkl-Anmeldung und Scrobble, Katalog-Cache samt Plattenstand, Quellen-Cache mit Stufen und Teilständen, TMDB-Übersetzung, Kalender, Handy-Befehle, Import, Kachelbilder, Sync-Warteschlange. Die Erweiterungen brauchen Zugriff auf den Zustand, deshalb sind Felder ausdrücklich nicht `private` (`:532` „nicht privat, damit AppModel+StreamRevalidate den Stand lesen kann“). Zustand, der logisch dazugehört, liegt in Neben-Singletons (`SyncQueueHolder`, `UpcomingCache`, `AddonMetaCache`, `StreamSearchStatus`, `UpcomingRevision`). Vier weitere `extension AppModel` stehen in View-Dateien.
- **Auswirkung:** 69 Views hängen per `@EnvironmentObject` am ganzen Modell; jede `@Published`-Änderung (z. B. `progress` alle 10 s im Player) invalidiert alle. Der Profilwechsel muss 12 Zustände von Hand zurücksetzen (`:255`–`266`) – jeder neue Cache ist ein möglicher vergessener Eintrag.
- **Empfehlung:** In Dienste mit eigenem Zustand schneiden: `ProfileService`, `ProgressService` (+Scrobble), `SyncAccounts`, `CatalogService`, `StreamService` (Cache, Stufen, Suche), `MetaService`. Ein Protokoll `ProfileScoped { func profileChanged() }`, über das der Profilwechsel alle Dienste erreicht. `AppModel` bleibt als Fassade.
- **Priorität:** hoch · **Aufwand:** L · **Sicherheit:** bestätigt

### Q-6: Views und Modell-Erweiterungen liegen in den falschen Dateien
- **Ort:** `App/Sources/AppModel+StreamSearch.swift:61`, `:106`, `:122`, `:151`, `:166`, `App/Sources/PlayerApp.swift:16`, `App/Sources/PlayerApp.swift:36`
- **Beobachtung:** `AppModel+StreamSearch.swift` enthält drei Views/Modifier (`AddonSearchStatusLine`, `StreamSearchPartials`, `RecentlyFailedMark`), eine `extension StreamListView` und `AddonTimeoutPicker`. Die Domänentypen `Route` und `PlayRequest` stehen in `PlayerApp.swift`.
- **Auswirkung:** Suchen nach dem Dateinamen führt in die Irre; `PlayRequest.nextRequest` (`PlayerApp.swift:52`) ist reine Logik und in der App nicht testbar.
- **Empfehlung:** Views nach `Views/Streams/`, `Route`/`PlayRequest` in eine eigene Datei, `PlayRequest` samt `nextRequest` nach PlayerCore.
- **Priorität:** niedrig · **Aufwand:** S · **Sicherheit:** bestätigt

---

## 2. Duplikate

### Q-7: Zeitformat „1:02:03“ viermal implementiert
- **Ort:** `App/Sources/Views/DetailViews.swift:1230`, `App/Sources/Views/PlayerScreen.swift:837`, `App/Sources/Views/Player/PlayerScrub.swift:565`, `Packages/PlayerCore/Sources/PlayerCore/Playback/SidePanel.swift:228`
- **Beobachtung:** Vier wortgleiche Ausdrücke `t >= 3600 ? String(format: "%d:%02d:%02d", …)`. Nur die Fassung in `PlayerScrub.swift` fängt nicht endliche Werte ab (`s.isFinite ? s : 0`).
- **Auswirkung:** `Int(max(0, s))` stürzt bei `nan`/`inf` ab; drei der vier Fassungen haben den Schutz nicht.
- **Empfehlung:** Eine öffentliche `PlayerClock.text(_:)` in PlayerCore mit dem `isFinite`-Schutz und einem Test; die drei anderen ersetzen.
- **Priorität:** mittel · **Aufwand:** S · **Sicherheit:** bestätigt

### Q-8: Folgen-ID, Folgentitel und Folgen-`PlayRequest` an vier bis sechs Stellen von Hand gebaut
- **Ort:** `App/Sources/AppModel.swift:636`, `App/Sources/Views/DetailViews.swift:598`, `App/Sources/Views/DetailViews.swift:603`, `App/Sources/Views/DetailViews.swift:611`, `App/Sources/Views/Player/PlayerSidePanel.swift:38`, `App/Sources/Views/Player/PlayerSidePanel.swift:106`, `App/Sources/PlayerApp.swift:55`
- **Beobachtung:** `"\(imdb):\(season):\(episode)"` und `"\(name) S\(s)E\(e)"` werden jeweils neu zusammengesetzt; das Zerlegen (`id.split(separator: ":").first`) steht an `DetailViews.swift:845` und `PlayerApp.swift:54`. Verwandt: `hasPrefix("tt")` 12-mal in der App und 6-mal im Core, `hasPrefix("tmdb:")` 7-mal, Typvergleiche mit `"series"`/`"movie"` 33-mal in der App.
- **Auswirkung:** Das ID-Format ist Vertrag mit Addons, Fortschritt und Sync; eine Abweichung an einer Stelle (z. B. Staffel 0, fehlende Folge → `?? 0` an `:596`, `:603`, `:611`) erzeugt Schlüssel, die nirgends sonst passen.
- **Empfehlung:** In PlayerCore einen Werttyp `ContentID` (`.imdb`, `.tmdb`, `.episode(base:season:episode:)`) mit `stremioID`, `seriesID`, `isIMDb` und Fabrik `PlayRequest.episode(of:season:episode:episodes:)`; Tests für Hin- und Rückweg.
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt

### Q-9: Trakt/Simkl werden über Zeichenketten verzweigt
- **Ort:** `App/Sources/AppModel.swift:107`, `:124`, `:130`–`131`, `:139`–`140`, `:156`, `:186`, `:189`, `:193`, `:212`–`213`, `:225`–`226`, `App/Sources/AppModel+SyncQueue.swift:145`
- **Beobachtung:** `s == "trakt" ? … : …` kommt 12-mal in 4 Dateien vor; `hasClient` (`:124`) behandelt jeden unbekannten Namen als Simkl. Die API-Schlüssel liegen als Literale `apiKeys["trakt_id"]` usw. an 13 Stellen.
- **Auswirkung:** Ein dritter Dienst oder ein Tippfehler im Namen fällt still in den Simkl-Zweig.
- **Empfehlung:** In PlayerCore `enum SyncService: String` und ein Protokoll `SyncClient` (deviceCode, poll, scrobble, playback, watchlist), das `TraktClient` und `SimklClient` erfüllen; `enum APIKeyName`.
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt

### Q-10: Fokus-Nachfassschleife zweimal, Knopfstil-Effekt dreimal, Fortschrittsbalken zweimal
- **Ort:** `App/Sources/Views/DetailViews.swift:353`–`370` und `App/Sources/Views/DetailViews.swift:805`–`829`; `App/Sources/Views/Design/Theme.swift:371`–`375`, `:404`–`408`, `:428`–`432`; `App/Sources/Views/RowViews.swift:636`–`641` und `App/Sources/Views/Player/PlayerScrub.swift:534`–`541`
- **Beobachtung:** (a) „hinscrollen, 100 ms warten, Fokus setzen, 150 ms warten, prüfen, bis zu viermal“ ist in Detailseite und Quellenliste getrennt ausgeschrieben. (b) Die drei `ButtonStyle`-Körper wiederholen Skalierung, Schatten und beide Animationen wortgleich. (c) Der Kapsel-Balken (heller Grund, weiße Füllung über `GeometryReader`) ist zweimal gebaut, daneben gibt es dreimal `ProgressView(value:)`.
- **Auswirkung:** Korrekturen an der Fokus-Zeitabstimmung (ein häufiges Gerätethema laut Kommentaren) müssen doppelt erfolgen.
- **Empfehlung:** `FocusRetry.apply(target:scroll:set:isSet:)` als eine Hilfsfunktion; ein `ViewModifier` `themeFocusLift(scale:)`; ein Baustein `ThemeProgressBar` mit `accessibilityValue`.
- **Priorität:** niedrig · **Aufwand:** S · **Sicherheit:** bestätigt

### Q-11: Cache-, Datei- und Speichermuster mehrfach von Hand
- **Ort:** `App/Sources/AppModel.swift:407`, `:419`–`421`, `:533`–`546`, `App/Sources/AppModel+MetaAddon.swift:124`–`125`, `App/Sources/AppModel+Upcoming.swift:13`–`16`, `App/Sources/Views/HomeHero.swift:190`, `App/Sources/Views/TorBoxFilesRow.swift:17`–`19`; `App/Sources/AppModel.swift:78`, `:85`, `:91`; Caches-Verzeichnis an 11 Stellen (u. a. `App/Sources/RatingIconStore.swift:12`, `App/Sources/RatingsStore.swift:14`, `App/Sources/AppModel+CatalogDisk.swift:22`)
- **Beobachtung:** PlayerCore bietet `TimedCache` und `TaskSlots`; trotzdem gibt es mindestens sieben weitere handgebaute Wörterbuch-Caches mit je eigener Ablauf- und Verdrängungsregel, zwei davon ohne Obergrenze (`imdbCache`, `localizedCache`). „Laufende Abfrage teilen“ ist dreimal umgesetzt (`localizedFlights` `:420`, `AddonMetaCache.inFlight`, `UpcomingCache.running`). `do { try progressStore.save … } catch { lastError = … }` steht dreimal hintereinander; `FileManager.default.urls(for: .cachesDirectory, …)[0]` elfmal.
- **Auswirkung:** Jeder Cache braucht seinen eigenen Eintrag im Profilwechsel (siehe Q-5); unbegrenzte Wörterbücher wachsen über lange Sitzungen.
- **Empfehlung:** Ein generischer `SharedLookupCache<Key, Value>` in PlayerCore (Ablauf, Obergrenze, geteilte laufende Abfrage, `reset()`), ein `AppPaths.caches`, eine private `saveProgress()`.
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt

---

## 3. Swift-6-Idiome und Nebenläufigkeit

| Merkmal | App | PlayerCore | Tests |
|---|---|---|---|
| Sprachmodus | Swift 5 (`project.yml:46`) | Swift 6 (`Package.swift:1`, tools 6.0) | Swift 6 |
| `@unchecked Sendable` | 9 | 5 | 16 |
| `nonisolated(unsafe)` | 2 | 11 | 0 |
| `@preconcurrency` | 0 | 0 | 0 |
| `DispatchQueue` | 6 | 0 | 0 |
| `Task {` gesamt / ohne gehaltenen Handle | 159 / rund 100 | 19 | 14 |
| `Task.detached` | 12 | 0 | 0 |
| `Task { @MainActor in` | 60 | – | – |
| `ObservableObject`-Klassen / `@Observable`-Klassen | 15 / 4 | 0 | – |
| `@Published` / `@State` | 48 / 209 | 0 | – |
| `try?` (davon `try? await Task.sleep`) | 137 (63) | 150 (4) | 14 |
| `try!` / `fatalError` / `precondition` | 0 / 0 / 0 | 8 / 0 / 1 | 6 / 2 / 0 |
| Force-Unwrap `x!` | 0 | 4 | – |
| Singletons `static let shared` | 19 | 0 | – |
| veränderliche `static var` | rund 23 | 0 | – |

### Q-12: Die App wird im Swift-5-Modus gebaut – strenge Nebenläufigkeitsprüfung ist aus
- **Ort:** `App/project.yml:46`, `Packages/PlayerCore/Package.swift:1`
- **Beobachtung:** `SWIFT_VERSION: "5.0"`, kein `SWIFT_STRICT_CONCURRENCY`, kein `SWIFT_UPCOMING_FEATURE_*`. Das README nennt „Swift 6“. In der App stehen 19 Singletons, rund 23 veränderliche `static var` (z. B. `App/Sources/Views/RowViews.swift:282`, `App/Sources/Views/Player/PostPlayCard.swift:107`, `App/Sources/Views/TorBoxFilesRow.swift:17`–`19`, `App/Sources/Views/HomeHero.swift:190`, `App/Sources/Playback/PlayerAudioOptions.swift:36`–`37`), 9 `@unchecked Sendable` und 12 `Task.detached`. Ob jede `static var` in einem `@MainActor`-Typ liegt, prüft im Swift-5-Modus niemand.
- **Auswirkung:** Datenrennen zwischen Hauptthread und den Hintergrundwegen (`DiskCacheProxy`, `ImagePipeline`, `RemoteLog`, `XRayProbeHook`) werden nicht zur Übersetzungszeit gefunden. Das Risiko liegt genau in dem Teil, der nicht getestet ist.
- **Empfehlung:** Stufenweise: zuerst `SWIFT_STRICT_CONCURRENCY: complete` im Swift-5-Modus (nur Warnungen), Warnungen ordnerweise abbauen, dann `SWIFT_VERSION: "6.0"`. Vorab die `static var` in `@MainActor`-Typen oder Actors ziehen.
- **Priorität:** hoch · **Aufwand:** L · **Sicherheit:** bestätigt (Einstellung), plausibel (konkrete Rennen nicht untersucht)

### Q-13: Rund 100 `Task { }` ohne gehaltenen Handle, viele mit fester Wartezeit
- **Ort:** `App/Sources/Views/DetailViews.swift:211`, `:287`, `:1060`, `:1093`, `:1109`, `:1125`, `:1245`; `App/Sources/Views/PlayerScreen.swift:71`, `:380`; je 7–9 in `App/Sources/ImagePipeline.swift`, `App/Sources/Views/FocusVideo.swift`, `App/Sources/Playback/DiskCacheProxy.swift`, `App/Sources/FusionKitStore.swift`
- **Beobachtung:** Von 159 `Task`-Starts in der App werden 57 gespeichert, zurückgegeben oder direkt erwartet. Die übrigen laufen frei. In Views bedeutet das: Die Arbeit läuft nach dem Verschwinden weiter und schreibt in `@State` (z. B. `:211`–`218` setzt `best` und loggt nach dem Verlassen der Seite; `:287` startet je Staffelwechsel eine neue Übersetzung ohne die alte abzubrechen). 65 `Task.sleep` in der App, davon nur 16 mit benannter Dauer; die übrigen sind Literale von 50 ms bis 10 s.
- **Auswirkung:** Verspätete Ergebnisse überschreiben neueren Zustand; die Schutzbedingungen (`guard playing == nil`) fangen das nur dort ab, wo jemand daran gedacht hat. Zeitkonstanten sind nicht auffindbar und nicht abstimmbar.
- **Empfehlung:** In Views `.task(id:)` statt `Task {}` in `onChange`; für Abläufe über mehrere Schritte einen gehaltenen Handle je Zweck. Wartezeiten in ein `enum UITiming` (teilweise existiert das schon: `AutostartAfterPush.settleMs`, `DetailLoadTimeline.giveUpMilliseconds`).
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt

### Q-14: `ObservableObject` und `@Observable` gemischt; 69 Views beobachten das ganze `AppModel`
- **Ort:** `App/Sources/AppModel.swift:6`, `App/Sources/Views/Home/HomeRowsSession.swift:9`, `App/Sources/Views/HomeTopEdgeWatch.swift:11`, `App/Sources/Views/HomeHero.swift:10`, `App/Sources/Views/HomeHero.swift:45`
- **Beobachtung:** 15 Klassen nutzen `ObservableObject`/`@Published`, 4 neuere `@Observable`. `AppModel` wird 69-mal per `@EnvironmentObject` gelesen, `model.profile.` 83-mal in Views. `@Published private(set) var stored` (`AppModel.swift:7`) und `progress` (`:19`) ändern sich bei jeder Einstellung bzw. alle 10 s im Player.
- **Auswirkung:** Mit `ObservableObject` wertet jede Änderung alle 69 Views neu aus, auch die, die nur `profile.appearance` lesen. Kommentare belegen, dass das schon umgangen wird („Eigene View, damit nur sie dem Suchstand folgt“, `DetailViews.swift:1218`).
- **Empfehlung:** `AppModel` und die Stores auf `@Observable` umstellen (tvOS 18 ist Mindestziel, feldgenaue Beobachtung ohne weiteren Umbau). Voraussetzung ist Q-5 nicht, erleichtert ihn aber.
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** bestätigt (Mischung), plausibel (Messwert der Neuberechnungen fehlt)

### Q-15: `nonisolated(unsafe)` und `try!` für statische Regex; `as!` in `ProfileStore`
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Logging/LogRedact.swift:149`, `:158`, `:163`, `:166`; `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:110`, `:112`, `:114`, `:115`; `Packages/PlayerCore/Sources/PlayerCore/Models/ISODate.swift:6`, `:9`, `:12`; `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:30`–`31`; `Packages/PlayerCore/Sources/PlayerCore/Playback/DiskCache.swift:91`
- **Beobachtung:** Alle 11 `nonisolated(unsafe)` im Core und alle 8 `try!` hängen an `NSRegularExpression` bzw. `ISO8601DateFormatter`. `ProfileStore.fileURL`/`backupURL` casten `storage as! FileBlobStorage` („nur für Tests“) in Produktionscode; `DiskCache.swift:91` nutzt `precondition` für Eingabewerte.
- **Auswirkung:** Kein akutes Problem (Muster sind Literale, beide Typen sind laut Apple threadsicher), aber die Ausnahmen verdecken, wo wirklich Unsicheres stünde. Der `as!` stürzt ab, sobald jemand die Eigenschaft mit der gestuften Ablage der App aufruft.
- **Empfehlung:** Swift-`Regex`-Literale (zur Übersetzungszeit geprüft, `Sendable`) statt `NSRegularExpression`; `Date.ISO8601FormatStyle` statt Formatter; `fileURL` in eine Test-Erweiterung oder als `URL?`.
- **Priorität:** niedrig · **Aufwand:** M · **Sicherheit:** bestätigt

### Q-16: `try?` verschluckt Schreib- und Kodierfehler
- **Ort:** `App/Sources/RatingIconStore.swift:63`, `App/Sources/RatingsStore.swift:59`, `App/Sources/FusionKitStore.swift:274`, `App/Sources/FusionKitStore.swift:305`, `App/Sources/Views/FocusVideo.swift:41` (25 `try?` in dieser Datei), `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:107`–`111`
- **Beobachtung:** 287 `try?` insgesamt; 63 davon sind das übliche `try? await Task.sleep`, rund 69 betreffen Datei- oder JSON-Arbeit. An den genannten Stellen wird ein fehlgeschlagenes Schreiben weder geloggt noch gemeldet – ungewöhnlich für ein Projekt, das sonst 408 Log-Aufrufe hat. In `Profile.init(from:)` werfen ältere Felder bei falschem Typ (`try c.decodeIfPresent`, `:86`–`106`), neuere fallen still auf den Standard (`(try? …) ?? nil ?? d.x`, `:107`–`111`).
- **Auswirkung:** Ein voller Cache-Speicher zeigt sich nur als „Bewertungen laden jedes Mal neu“. Die zwei Dekodier-Stile bedeuten: ein beschädigtes `sources`-Feld setzt die Einstellungen kommentarlos zurück, ein beschädigtes `appearance`-Feld verwirft das ganze Profil.
- **Empfehlung:** Eine Hilfsfunktion `Log.attempt("kategorie") { try … }` für Dateiarbeit; in `Profile` eine einzige Dekodier-Hilfe `decodeLenient(_:forKey:default:)`, die den Rückfall meldet (Rückgabe einer Liste zurückgesetzter Felder).
- **Priorität:** mittel · **Aufwand:** S · **Sicherheit:** bestätigt

---

## 4. API-Fläche, Benennung, Magic Numbers, toter Code

### Q-17: PlayerCore exportiert fast alles – 415 öffentliche Typen, 3 169 `public`-Deklarationen
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/` (gesamt), Beispiele `Packages/PlayerCore/Sources/PlayerCore/XRay/FaceMatching.swift:161`, `Packages/PlayerCore/Sources/PlayerCore/XRay/FaceAlignment.swift:183`, `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:524`
- **Beobachtung:** Von 527 Typnamen im Core sind 415 `public`, nur 14 Top-Level-Typen intern; `package`-Zugriff wird nicht genutzt. 164 Core-Typen werden in der App nicht namentlich verwendet. Die Tests nutzen `@testable import`, bräuchten `public` also nicht.
- **Auswirkung:** Der Compiler kann nicht melden, was die App nicht mehr braucht; jede Hilfsfunktion ist Vertrag. Umbenennungen sind teurer als nötig.
- **Empfehlung:** Faustregel „`public` nur, was `App/Sources` aufruft“; den Rest auf intern zurücknehmen (mechanisch: `public` entfernen, App bauen, Fehler zurückdrehen). Als Dauerprüfung ein Werkzeug wie Periphery in CI.
- **Priorität:** niedrig · **Aufwand:** M · **Sicherheit:** bestätigt (Zahlen), plausibel (Anteil überflüssiger `public`)

### Q-18: Toter bzw. nur von Tests genutzter Code
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/XRay/FaceMatching.swift:161` (`FaceMatcher`), `:123` (`selectFaces`), `:198` (`assign`); `Packages/PlayerCore/Sources/PlayerCore/XRay/FaceAlignment.swift:183` (`FaceWarp`), `:162` (`pixelWidth`); `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:524` (`callTool`); `Packages/PlayerCore/Sources/PlayerCore/Playback/PlaybackRecovery.swift:275` (`exactURL`); `Packages/PlayerCore/Sources/PlayerCore/Playback/FailedLinks.swift:104` (`excludingFailed`); `Packages/PlayerCore/Sources/PlayerCore/Playback/TrackPanelLogic.swift:139`, `:164` (`audioRow`, `subtitleRow`); `Packages/PlayerCore/Sources/PlayerCore/Ranking/QualityBadges.swift:154` (`forStream`); `Packages/PlayerCore/Sources/PlayerCore/Models/FocusHeadroom.swift:37` (`liftedExtent`); `Packages/PlayerCore/Sources/PlayerCore/Models/PosterSize.swift:56` (`tileHeight`); `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncQueue.swift:168` (`playbackIDs`); `App/Sources/Playback/PlayerMemory.swift:39` (`trackMemoryCount`)
- **Beobachtung:** Wortgenaue Suche über App und Core: Die genannten Symbole kommen außerhalb ihrer Deklaration nur in Tests vor (`callTool` und `trackMemoryCount` gar nicht). Bei `FaceMatcher`/`FaceWarp` kann es Vorarbeit für eine spätere X-Ray-Stufe sein; die App nutzt aus dem X-Ray-Bereich derzeit `XRayProbe`, Vision-Anfragen und den Cache.
- **Auswirkung:** Rund 200 Zeilen plus ihre Tests werden gepflegt, ohne im Produkt zu laufen; Tests geben dort ein falsches Sicherheitsgefühl.
- **Empfehlung:** Je Symbol entscheiden: löschen oder mit einem Kommentar „für Stufe X, noch nicht angeschlossen“ markieren. Namenssuche erfasst keine Aufrufe über Protokolle – vor dem Löschen einmal bauen.
- **Priorität:** niedrig · **Aufwand:** S · **Sicherheit:** plausibel (Namenssuche, kein Compiler-Beleg)

### Q-19: Sprache gemischt – Kommentare, Log-Kategorien, nutzersichtbare Texte im Core
- **Ort:** `App/Sources/AppModel.swift:14` (englisch) neben `:18` (deutsch); `App/Sources/Views/Design/Theme.swift:63` neben `:57`; Log-Kategorien z. B. `App/Sources/AppModel.swift:66` (`"start"`), `:144` (`"sync"`), `:382` (`"katalog"`), `App/Sources/Views/DetailViews.swift:1020` (`"quellen"`) neben `App/Sources/AppModel.swift:478` (`"streams"`)
- **Beobachtung:** Bezeichner sind durchgehend englisch (gut). Kommentare wechseln innerhalb derselben Datei: grob 1 700 deutsche zu 1 080 englischen Kommentarzeilen (Heuristik über Artikel). Die rund 45 Log-Kategorien sind freie Zeichenketten in beiden Sprachen mit Überschneidungen: `streams`/`quellen`, `bild`/`bilder`, `play`/`player`, `cache`/`speicher`.
- **Auswirkung:** Filtern im Fern-Log verlangt, beide Namen zu kennen; ein Tippfehler in der Kategorie fällt nicht auf.
- **Empfehlung:** `enum LogCategory: String` (eine Sprache, eine Liste) und `RemoteLog.info(.streams, …)`. Für Kommentare eine Sprache festlegen und nur bei Berührung angleichen.
- **Priorität:** niedrig · **Aufwand:** S · **Sicherheit:** bestätigt

### Q-20: Magic Numbers außerhalb des Designsystems
- **Ort:** `App/Sources/Views/DetailViews.swift:113`, `:496`, `:605`, `:683`–`684`, `:1188`, `:1243`–`1257`, `:1291`, `:1356`–`1363`, `:1399`, `:1407`; `App/Sources/Views/PlayerScreen.swift:466`–`480`, `:494`–`501`, `:532`; `App/Sources/PlayerApp.swift:82`, `:216`–`225`; `App/Sources/AppModel+StreamSearch.swift:19`
- **Beobachtung:** `Theme.Space` wird 229-mal genutzt, daneben stehen 94 Zeilen mit rohen zweistelligen Abständen/Maßen in Views außerhalb von `Views/Design`. `SearchView` und `ProfilePickerView` nutzen keine Tokens (`padding(60)`, `spacing: 30`, `GridItem(.fixed(240))`, Kreis 220, `.blue.gradient`). Im Player stehen die Up-next-Regeln als Literale (300 s Mindestlänge, 20 s, 120 s, 100 s, Zähler 10). Textrollen: 82 `textRole`-Aufrufe gegen 83 rohe `.font(.title3 …)`.
- **Auswirkung:** Das Designsystem gilt nur für etwa die Hälfte der Oberfläche; Player und Suche sehen bei einer Token-Änderung nicht mit aus.
- **Empfehlung:** Up-next-Zeiten in eine PlayerCore-Regel `UpNextPolicy` (testbar, siehe Q-22); Suche, Profilwahl und Player-Karten auf `Theme.Space`/`textRole` umstellen; eine Lint-Regel gegen rohe `.font(.` außerhalb `Views/Design`.
- **Priorität:** niedrig · **Aufwand:** M · **Sicherheit:** bestätigt

---

## 5. Logik in der App, die nach PlayerCore gehört

### Q-21: Reine Logik in Views und App-Typen, dort nicht testbar
- **Ort:** siehe Tabelle
- **Beobachtung:**

| Funktion | Ort | Warum Core |
|---|---|---|
| `PlayRequest.nextRequest`, Typ `PlayRequest` | `App/Sources/PlayerApp.swift:36`–`57` | reine ID-/Titelrechnung, Grundlage für Autoplay; 0 Tests |
| `AppModel.quickPlayRequest` (Entscheidungsteil), `moviePlayRequest`, `progressItem` | `App/Sources/AppModel.swift:616`–`639` | „Film mit gemerkter Quelle, Serie nächste offene Folge, sonst S1F1“ |
| `StreamListView.fallbackCandidate` | `App/Sources/Views/DetailViews.swift:1046`–`1051` | Auswahlregel „gecachte unterhalb, dann oberhalb, dann unbekannte“ |
| `StreamListView.fallback`/`ended`/`startNext` (Entscheidung) | `App/Sources/Views/DetailViews.swift:1076`–`1149` | Zustandsautomat, siehe Q-3 |
| `DetailView.playbackFocusTarget` | `App/Sources/Views/DetailViews.swift:337`–`349` | Abbildung Folge → Fokusziel, nutzt bereits `EpisodeFocus` |
| `DetailView.seasons`, Folgen-Sortierung | `App/Sources/Views/DetailViews.swift:564`–`566`, `:591` | Listenableitung aus `MetaDetail` |
| `DetailExtras.aboutRows`, `money`, `statusText` | `App/Sources/Views/DetailViews.swift:1414`–`1449` | Formatierung und Übersetzungstabelle |
| `PlayerControls.upNextTick` (Regelteil) | `App/Sources/Views/PlayerScreen.swift:465`–`482` | Zeitregeln für Karte/Vorladen/Abbruch |
| `HomeHero.runtimeText` | `App/Sources/Views/HomeHero.swift:252`–`255` | Formatierung |
| `AppModel.loadItems` (Entscheidung „leer überschreibt nicht, außer Merkliste“) | `App/Sources/AppModel.swift:383`–`391` | Cache-Regel |
| `StreamSearchStatus.update` (Verdrängung „höchstens 30“) | `App/Sources/AppModel+StreamSearch.swift:15`–`22` | Verdrängungsregel |
| `AppModel.apply(_:)` Log-Zusammenfassung der Befehle | `App/Sources/AppModel.swift:559`–`573` | gehört als `logName` an `PhoneCommand` |

- **Auswirkung:** Diese Regeln bestimmen sichtbares Verhalten (welche Folge startet, welche Quelle als Nächstes kommt) und sind die einzigen ihrer Art ohne Test.
- **Empfehlung:** In der Reihenfolge der Tabelle verschieben; jeweils die Entscheidung als reine Funktion mit Eingabestruktur, die App behält nur das Auslösen.
- **Priorität:** hoch · **Aufwand:** M · **Sicherheit:** bestätigt

---

## 6. Testabdeckung PlayerCore

### Q-22: Tests laufen nicht in CI
- **Ort:** `.github/workflows/build.yml:74`–`81`, `README.md:86`–`91`
- **Beobachtung:** Der Workflow hat vier Jobs (Build IPA, Version history, Release app-main, Publish build-N). Keiner ruft `swift test` oder `xcodebuild test` auf. Das README beschreibt die Tests als lokal ausführbar („on Linux with Swift 6“).
- **Auswirkung:** 965 Tests schützen nur, wenn jemand sie von Hand startet. Ein Build auf `main` mit roten Tests wird als Release veröffentlicht.
- **Empfehlung:** Einen Job `test` auf `ubuntu-latest` (Swift-6-Container) mit `cd Packages/PlayerCore && swift test`, und `release`/`publish` davon abhängig machen (`needs`). Läuft parallel zum macOS-Build und kostet wenige Minuten.
- **Priorität:** hoch · **Aufwand:** S · **Sicherheit:** bestätigt

### Q-23: Testdateien sind nach Entwicklungsstufen statt nach Quelldateien geschnitten
- **Ort:** `Packages/PlayerCore/Tests/PlayerCoreTests/SpeedPictureTests.swift:18`–`326`, `Packages/PlayerCore/Tests/PlayerCoreTests/FollowUpTests.swift:9`–`199`, `Packages/PlayerCore/Tests/PlayerCoreTests/P2Tests.swift:5`, `Packages/PlayerCore/Tests/PlayerCoreTests/PlayerComfortTests.swift`
- **Beobachtung:** `SpeedPictureTests` prüft `TimedCache`, `CatalogSnapshot`, `RevalidationPolicy`, `ImageSizing`, `HitchDetector`, `RowFocusMemory` und `StreamListMerge`; `FollowUpTests` prüft `TaskSlots`, `FetchRetryGate`, `RatingIconSet`, `TVmaze` und Stream-Zusammenführung. Alle 965 Tests sind freie Funktionen: kein `@Suite`, keine parametrisierten Tests (`arguments:`), obwohl viele Tests Wertetabellen als `#expect`-Ketten ausschreiben (im Schnitt 4,7 `#expect` je Test). In Tests stehen `try!` und `!` (`P2Tests.swift:9`, `:14`, `:17`).
- **Auswirkung:** Zu einer Quelldatei ist nicht erkennbar, wo ihre Tests liegen und ob sie vollständig sind (Tests zu `TimedCache` liegen in 5 Dateien). Bricht ein `#expect` in einer Kette, zeigt der Bericht nicht, welcher Tabellenfall es war.
- **Empfehlung:** Neue Tests in `<Quelldatei>Tests.swift`; bestehende beim nächsten Anfassen umziehen. `@Suite` je Typ, Wertetabellen als `@Test(arguments:)`.
- **Priorität:** niedrig · **Aufwand:** M · **Sicherheit:** bestätigt

### Qualität und Umfeld der Tests (Feststellungen, kein Befund)

- **Verhalten statt Defaults:** Stichproben (`ModelTests`, `P2Tests`, `SpeedPictureTests`, `FollowUpTests`, `SyncTests`) prüfen Regeln mit Randfällen (Ablauf, Verdrängung, Rundung, Reihenfolge). Reine Standardwert-Tests sind die Ausnahme (`ModelTests.swift:14`).
- **Netz:** Kein Test braucht Netz. HTTP läuft über `FakeHTTP` (`AddonTests.swift:5`) bzw. `FakeSender` (`SyncTests.swift:5`), Ablage über `MemoryKeyValueBlobs`. URLs in Tests sind nur Eingabedaten.
- **Laufzeit:** 12 Stellen nutzen `Task.sleep`, davon drei mit 5–10 s als Gegenstück zu einer Zeitgrenze (`TrailerioTests.swift:64`, `FollowUpTests.swift:131`, `AddonSubtitleTests.swift:16`); sie werden durch die Zeitgrenze abgebrochen, sind aber auf langsamen CI-Maschinen ein möglicher Wackelkandidat.
- **Zuordnung:** Namensbasiert gibt es zu jeder der 132 Quelldateien mindestens einen Test, der einen ihrer Typen berührt, mit einer Ausnahme (`LenientJSON.swift`, nur indirekt über das Dekodieren der Stremio-Modelle).

### Tabelle: Quelldatei → Tests → Lücken (Auswahl der logikreichen Dateien)

Spalte „@Test“: Tests der genannten Hauptdatei(en). Lücken über Namenssuche der Funktion in allen Tests (0 Treffer).

| Quelldatei (Zeilen) | Haupt-Testdatei(en) | @Test | Nicht getestete, testwürdige Logik |
|---|---|---|---|
| `Sync/TraktClient.swift` (241) | `SyncTests`, `SyncRetryTests`, `SyncQueueTests` | 9 + 9 + 20 | `refresh(_:)` (Token-Erneuerung, rotierender Refresh-Token), `recommendations`, `isRecommendations` |
| `Sync/SimklClient.swift` (79) | `SyncTests`, `SyncRetryTests` | 9 + 9 | nur über 10 Zeilen berührt; Fehlerantworten beim Poll |
| `Sync/ScrobbleTracker.swift` (71) | `SyncRetryTests` | 9 | Folge pause → progress → end nur knapp (9 Treffer) |
| `Services/TMDBLocalized.swift` (238) | `TMDBTests`, `TrailerPersonTests` | 4 + 8 | `tmdbID(imdb:)`, `localized(tmdbID:)`, `season(tmdbID:)` als Abruf; `parseLocalized` (71 Zeilen) nur 2 Treffer |
| `Services/TMDBClient.swift` (120) | `TMDBTests`, `P2Tests` | 4 + 9 | `imdbID(tmdbID:)`, Fehlerantworten (401, 429) |
| `Services/TorBox.swift` (115) | – (gestreut) | – | `files(fresh:)` 1 Treffer, `link(for:)` 1 Treffer, `userMessage` |
| `Services/TVmaze.swift` (184) | `FollowUpTests` | 12 | `showID`, `airstamps` (Abruf), nur Zusammenführung/Ablage getestet |
| `Services/YouTubeResolver.swift` (157) | `TrailerPersonTests` | 8 | Client-Rückfallkette, `visitorData`, `qualityHeight` |
| `Addons/LenientJSON.swift` (95) | keine direkte | 0 | alle 7 Hilfen (`lenientInt`, `lenientBool`, `lenientStrings` …) – ideale Kandidaten für parametrisierte Tests |
| `Addons/AddonClient.swift` (176) | `AddonTests`, `AddonCompatTests` | 5 + 16 | `webInstallTarget` |
| `Addons/AsyncLimiter.swift` (65) | `AddonMetaFetchTests` | 5 | Abbruch eines Wartenden (`dropWaiter`), Reihenfolge |
| `Store/TaskSlots.swift` (51) | `FollowUpTests` | 2 von 12 | `finish` mit altem Ticket nach `reset` |
| `Store/ProfileStore.swift` (59) | `StoreTests`, `LegacyProfileTests` | 6 + 1 | Rückfall auf `.bak`, beschädigte Hauptdatei |
| `Models/Profile.swift` (117) | `ModelTests`, `LegacyProfileTests` | 3 + 1 | Dekodieren mit falschem Feldtyp (zwei Stile, siehe Q-16) |
| `Progress/WatchProgress.swift` (201) | gestreut (11 Dateien) | – | `rememberSource` 1 Treffer, `latest(forItem:)` 1 Treffer, `history` |
| `Progress/NextEpisode.swift` (54) | `HeroPlayTests`, `NavigationRulesTests` | 5 + 19 | `EpisodeRef.next` 2 Treffer; Staffelgrenze, Specials (Staffel 0) |
| `Update/AppUpdate.swift` (740) | `AppUpdateTests` | 17 | 740 Zeilen auf 17 Tests; `callTool` ungenutzt |
| `Phone/PhoneInput.swift` (302) | `PhoneInputTests`, `PhoneTests` | 9 + 6 | HTML-Erzeugung (`orderSection`, 51 Zeilen) nur über Befehls-Parsing |
| `Playback/ScrubPlanner.swift` (362) | `PlayerComfortTests`, `BestChoiceTests` | 25 (gemischt) | keine eigene Testdatei für 362 Zeilen |
| `Playback/DiskCache.swift` (399) | `DiskCacheTests` | 19 | gut abgedeckt |
| `Playback/PlaybackRecovery.swift` (278) | `PlaybackRecoveryTests`, `StabilityTests` | 22 + 27 | gut abgedeckt |
| `Ranking/*` (8 Dateien, 1 317) | `SourceRankingTests`, `BestChoiceTests`, `StreamTraitsTests`, `SourceFilterTests`, `ReleaseMatchTests` | 32 + 19 + 13 + 5 + 15 | gut abgedeckt |
| `Logging/LogRedact.swift` (210) | `LogRedactTests` | 33 | gut abgedeckt |
| `XRay/FaceMatching.swift`, `FaceAlignment.swift` (433) | `XRayCoreTests`, `XRayGalleryTests` | 17 + 17 | getestet, aber von der App nicht genutzt (Q-18) |

Nicht in PlayerCore und damit ganz ohne Test: `App/Sources/Playback/DiskCacheProxy.swift` (783 Zeilen, HTTP-Bereichslogik), `App/Sources/ImagePipeline.swift` (572), `App/Sources/StreamPrefetcher.swift` (338), `App/Sources/CollectionLinkStore.swift` (449), `App/Sources/FusionKitStore.swift` (425) und der HTTP-Server der Handy-Seite (`App/Sources/Views/PhoneInputView.swift:8`).

---

## 7. Lokalisierung

### Q-24: Keine Lokalisierung – die Oberfläche ist fest deutsch, das README verspricht Deutsch und Englisch
- **Ort:** `README.md:33`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:3`, `App/Sources/AppModel.swift:346`, `App/Sources/Views/Settings/AppearanceSettings.swift:20`–`21`, `App/Sources/PlayerApp.swift:95`–`107`, `App/Sources/Views/DetailViews.swift:144`, `:157`, `:509`, `:570`, `:581`, `:756`, `:1244`, `:1349`, `:1417`–`1426`
- **Beobachtung:** Es gibt keine `.xcstrings`-, `.strings`- oder `Localizable`-Datei und genau einen Treffer für `String(localized:`/`LocalizedStringKey` in der ganzen App. `AppLanguage` (`de`/`en`) wird an genau drei Stellen gelesen: TMDB-Sprache (`AppModel.swift:346`), Trailersprache (`DetailViews.swift:523`) und die Einstellungszeile selbst, deren Beschreibung es auch so sagt: „Sprache von Titeln, Beschreibungen und Katalogen“. Hart codierte deutsche Texte: 53 `Text("…")`, 13 `Button("…")`, 280 Argumente `title:`/`detail:`/`summary:` u. ä., 35 `SettingsSection("…")`, 30 Zuweisungen an `lastError`/`notice`/`nextNote`; insgesamt 261 Zeilen mit Umlaut-Literalen in der App (ohne Log) und 173 im Core (`SettingsSummary`, `BestChoice.noSourceText`, `MediaLabels`, `PlayerInfoLabels`).
- **Auswirkung:** Ein Profil mit Sprache „English“ bekommt englische Filmtexte in einer deutschen Oberfläche. Das README-Versprechen ist nicht erfüllt.
- **Empfehlung:** Kurzfristig das README richtigstellen („interface in German; titles and descriptions in German or English per profile“). Wenn Englisch gewollt ist: einen String-Katalog einführen und die Texte über eine eigene Nachschlagefunktion mit der Profilsprache auflösen (die Systemsprache reicht nicht, weil die Sprache je Profil gilt) – im Core als `Strings.text(.key, language:)`, damit es testbar bleibt.
- **Priorität:** hoch (Widerspruch zum README) · **Aufwand:** S (README) bzw. L (echte Lokalisierung) · **Sicherheit:** bestätigt

### Q-25: Datums-, Zahlen- und Pluralformen sind fest deutsch und teils unvollständig
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Models/ISODate.swift:23`, `Packages/PlayerCore/Sources/PlayerCore/Models/DesignText.swift:18`–`24`, `Packages/PlayerCore/Sources/PlayerCore/Playback/SidePanel.swift:343`–`345`, `Packages/PlayerCore/Sources/PlayerCore/Playback/MediaLabels.swift:45`, `Packages/PlayerCore/Sources/PlayerCore/Playback/PlayerInfoLabels.swift:57`, `App/Sources/Views/ClockView.swift:7`, `App/Sources/Views/DetailViews.swift:1423`, `:1435`, `:1438`–`1448`, `App/Sources/AppModel.swift:602`, `App/Sources/AppUpdater.swift:165`, `App/Sources/Views/Settings/CollectionLinksView.swift:40`
- **Beobachtung:** Datum per Zeichenkettenumstellung (`germanDay`), Dezimalkomma per `replacingOccurrences` an zwei Stellen (`DesignText.decimal` und ein zweites `decimal` in `SidePanel.swift:343`), Sprachnamen fest über `Locale(identifier: "de")`, Uhrzeit fest `HH:mm`, Geldbetrag „Mio. $“, TMDB-Status über eine Tabelle mit 7 Einträgen (unbekannte Werte erscheinen englisch). Demgegenüber nutzt `CollectionLinksView.swift:40` `formatted(date:time:)` mit der Systemsprache – auf einem englisch eingestellten Gerät steht dort ein US-Datum neben deutschen Texten. Plural: sauber an 6 Stellen (`n == 1 ? "1 Reihe" : "\(n) Reihen"`), als Klammerform in Nutzertexten an zwei („Eingabe(n)“, „Rechner(n)“), und halb an `DetailViews.swift:1423` („1 Staffel · 1 Folgen“ möglich).
- **Auswirkung:** Kleine sichtbare Fehler („1 Folgen“), gemischte Formate, und jede Stelle müsste bei einer zweiten Sprache einzeln angefasst werden.
- **Empfehlung:** Eine `enum Formats` in PlayerCore mit festem `Locale` je `AppLanguage` und `FormatStyle` für Datum, Zahl, Dauer, Währung; Plural über eine Hilfsfunktion `plural(n, one:, other:)`. Das zweite `decimal` entfernen.
- **Priorität:** niedrig · **Aufwand:** M · **Sicherheit:** bestätigt

---

## 8. Barrierefreiheit (WCAG 2.1 AA, soweit auf tvOS anwendbar)

| Modifikator | Anzahl (App) |
|---|---|
| `accessibilityLabel` | 22 |
| `accessibilityHint` | 6 |
| `accessibilityValue` | 3 |
| `accessibilityHidden` | 9 |
| `accessibilityAddTraits` | 27 |
| `accessibilityElement` | 12 |
| `accessibilityReduceMotion` / `reduceTransparency` / `differentiateWithoutColor` | 0 / 0 / 0 |
| `dynamicTypeSize` | 0 |
| feste Schriftgrößen `.font(.system(size:` | 9 |
| View-Dateien ohne jeden Accessibility-Modifikator | 51 von rund 75 |

Gut gelöst: Überschriften tragen `.isHeader`, gewählte Staffeln/Filter `.isSelected`; `SettingsRow`, `StatusCard`, `CategoryList`, `ThemeBadge`, `MetaLine` und `HomeManagerView` haben zusammengesetzte Labels mit Wert und Hinweis; Zustandsfarben haben Symbol und Namen (`Theme.swift:245`–`258`); der Fokus wird über weiße Fläche, Skalierung und Schatten gezeigt, nie nur über Farbe (`Theme.swift:368`–`373`). Schrift läuft überwiegend über Textstile (`Theme.TextRole`), also Dynamic-Type-fähig, soweit tvOS das anbietet.

### Q-26: Poster-Kacheln und Kachelzustand haben kein VoiceOver-Label
- **Ort:** `App/Sources/Views/RowViews.swift:380`–`416`, `App/Sources/Views/RowViews.swift:312`, `App/Sources/Views/RowViews.swift:615`–`649`, `App/Sources/Views/RowViews.swift:481`–`491`, `App/Sources/Views/TilePosterImage.swift:36`, `App/Sources/Views/DetailViews.swift:1251`, `:1377`
- **Beobachtung:** `PosterCard` besteht aus Bild und Overlays; der Titel wird nur gezeichnet, wenn kein Bild lädt (`TilePosterImage.swift:36`). `NavigationLinkish` (`:312`) setzt kein Label. Ordner-Kacheln haben eines (`RowViews.swift:505`), Poster nicht. `CardStateOverlay` zeichnet Haken (gesehen), Restzeit und Fortschrittsbalken ohne Label oder Wert; der Rang der Top-10-Kachel ist ein eigener Text neben dem Poster.
- **Auswirkung:** VoiceOver liest auf Startseite, Suche und „Ähnliche Titel“ für die meisten Kacheln voraussichtlich nur „Taste“ – der Hauptinhalt der App ist für Screenreader-Nutzer nicht benennbar (WCAG 1.1.1, 4.1.2).
- **Empfehlung:** In `NavigationLinkish` bzw. `PosterCard`/`LandscapeCard`: `.accessibilityElement(children: .ignore)`, `.accessibilityLabel(item.name)`, `.accessibilityValue(DesignText.accessibilityLabel([Jahr, "gesehen" | "noch 23 min", Rang, Qualitäts-Plaketten]))`. Die Textbausteine dafür gibt es schon (`DesignText.accessibilityLabel`, `ProgressBook.cardState`).
- **Priorität:** hoch · **Aufwand:** S · **Sicherheit:** plausibel (aus dem Code abgeleitet; am Gerät mit VoiceOver bestätigen)

### Q-27: Der Player ist für VoiceOver unbeschriftet
- **Ort:** `App/Sources/Views/PlayerScreen.swift:238`–`411` (kein Accessibility-Modifikator in der ganzen Datei), `App/Sources/Views/Player/PlayerScrub.swift:522`–`553`, `App/Sources/Views/PlayerScreen.swift:493`–`503`, `App/Sources/Views/PlayerScreen.swift:530`, `App/Sources/Views/Player/SkipSegmentButton.swift` (367 Zeilen, 0 Modifikatoren), `App/Sources/Views/Player/PostPlayCard.swift` (0), `App/Sources/Views/Player/PlayerLoadingSteps.swift:42`
- **Beobachtung:** Die Spielfläche ist ein fokussierbarer `ZStack` ohne Label, Wert oder Aktionen. `PlayerTimeline` ist reine Zeichnung ohne `accessibilityValue` (Position/Dauer). Die Up-next-Karte erscheint ohne Ansage; der Bedienhinweis an `:530` ist ein Fließtext mit Pfeilsymbolen. Sprungbereiche sind nur über Farbe unterschieden (gelb Intro/Rückblick, cyan Abspann, violett Vorschau, `PlayerScrub.swift:555`–`560`).
- **Auswirkung:** Position, Restzeit, Fehlerzustand und „Nächste Folge in n s“ sind ohne Sehen nicht erfahrbar; die Farbkodierung der Zeitleiste verletzt 1.4.1 (Farbe als einziger Träger), ist aber nur Zusatzinformation.
- **Empfehlung:** Spielfläche: `.accessibilityLabel(Titel)`, `.accessibilityValue("Position … von …, pausiert/spielt")`, `accessibilityAction` für Play/Pause und ±10 s. Zeitleiste `accessibilityHidden(true)` (Wert steht an der Fläche). Up-next und Fehler per `AccessibilityNotification.Announcement`. Die Wert-Texte in PlayerCore bilden (testbar).
- **Priorität:** mittel · **Aufwand:** M · **Sicherheit:** plausibel

### Q-28: „Bewegung reduzieren“ und „Transparenz reduzieren“ werden nicht beachtet
- **Ort:** `App/Sources/Views/RowViews.swift:404`–`414` (Aufklappen der Poster nach 350 ms), `App/Sources/Views/FocusVideo.swift:163` (Fokus-Video/GIF auf Kacheln), `App/Sources/Views/HomeHero.swift` (Hero-Wechsel), `App/Sources/Views/PlayerScreen.swift:255` (Einschub von rechts), `App/Sources/Views/PlayerScreen.swift:500`, `App/Sources/Views/Player/PlayerScrub.swift:510`, `App/Sources/Views/Player/PostPlayCard.swift:67`, `App/Sources/Views/Player/PlayerTrackPanel.swift:164`, `:348`, `App/Sources/Views/Player/PlayerSidePanel.swift:298`
- **Beobachtung:** 44 `withAnimation`/`.animation`-Stellen, automatisch startende Fokus-Videos und sich aufklappende Kacheln; kein einziger Zugriff auf `accessibilityReduceMotion`. Sechs Flächen nutzen `.ultraThinMaterial` ohne Rückfall bei `accessibilityReduceTransparency`. Für die Fokus-Animation gibt es eine eigene Einstellung (Ton der Kachel-Animation), aber keinen Schalter „Animation aus“ im geprüften Code.
- **Auswirkung:** Nutzer, die Bewegung im System abgeschaltet haben, bekommen trotzdem automatisch startende Bewegtbilder (WCAG 2.2.2 Pausieren/Stoppen, 2.3.3 Animation aus Interaktion).
- **Empfehlung:** Eine Umgebungs-Hilfe `Theme.Motion` (liest `accessibilityReduceMotion`): Fokus-Video und Aufklappen aus, Übergänge auf Überblenden; `Theme.Surface.glass` mit deckendem Rückfall (`Palette.overlayCard`) bei reduzierter Transparenz.
- **Priorität:** mittel · **Aufwand:** S · **Sicherheit:** bestätigt (kein Zugriff vorhanden)

### Q-29: Sekundärer Text auf Bild, Video und Glas unterschreitet 4,5:1
- **Ort:** siehe Tabelle; Grundsatz in `App/Sources/Views/Design/Theme.swift:190` („nicht `.secondary`, das auf Glas unter 3:1 fällt“)
- **Beobachtung:** Das Designsystem hat das Problem erkannt und `Palette.secondary` (Weiß 65 %) eingeführt. Trotzdem stehen 26 `.foregroundStyle(.secondary)` in 11 Dateien, überwiegend im Player und auf der Detailseite. Schätzung für den ungünstigen Fall (heller Bild- bzw. Videoinhalt dahinter); Textgröße 25–38 pt, auf tvOS zählt das als großer Text (Schwelle 3:1), bei Fließtext 4,5:1:

| # | Vordergrund → Hintergrund | Ort | Kontrast (geschätzt) | Bewertung |
|---|---|---|---|---|
| 1 | Titel Weiß, nur Schatten → Kachelbild ohne Verlauf | `App/Sources/Views/RowViews.swift:457` | 1,1–2:1 bei hellem Bild | kritisch |
| 2 | Titel/Folgenzeile `.secondary` → Video, oberer Rand des Verlaufs (Schwarz 80 % → klar) | `App/Sources/Views/PlayerScreen.swift:510`–`511`, `:533` | 1,3–2,5:1 | kritisch |
| 3 | `.secondary` (callout/caption) → `.ultraThinMaterial` über Video | `App/Sources/Views/PlayerScreen.swift:496`–`500` | 1,5–2,5:1 | kritisch |
| 4 | `.secondary` (caption2) → `.ultraThinMaterial` über Video | `App/Sources/Views/Player/PlayerScrub.swift:499`–`510` | 1,5–2,5:1 | kritisch |
| 5 | `.secondary` → `.ultraThinMaterial` über Video | `App/Sources/Views/Player/PostPlayCard.swift:34`, `:67` | 1,5–2,5:1 | kritisch |
| 6 | Weiß (headline) → Orange 85 % über Video | `App/Sources/Views/Player/PlayerStability.swift:129`–`132` | etwa 2,1:1 | unter 3:1 |
| 7 | Weiß 65 % (`rowDetail`, Meta-Zeile, Hinweise) → Hintergrundbild mit Schwarz 55 % | `App/Sources/Views/DetailViews.swift:108`, `:154`, `:414`, `:418` | etwa 3,0:1 bei hellem Bild (Weiß: 4,8:1) | Grenze |
| 8 | Weiß → Rot 80 % über Video (Fehlertext) | `App/Sources/Views/PlayerScreen.swift:247` | etwa 3–3,5:1 | Grenze |
| 9 | Uhr `.secondary` → Hero-Bild (oben rechts, Verlauf dort schwach) | `App/Sources/Views/ClockView.swift:15`, `App/Sources/PlayerApp.swift:82` | 1,5–3:1 | unter 3:1 möglich |
| 10 | Dateiname: Schwarz 60 % × 0,75 → weiße Fokuszeile | `App/Sources/Views/DetailViews.swift:1196` | etwa 3,4:1 (Ruhe: 4,6:1) | Grenze |

Nicht-Text: Fortschrittsbalken Weiß auf Weiß 30 % direkt auf dem Poster (`RowViews.swift:638`–`639`) und Zeitleisten-Marken Violett/Cyan 60 % auf Weiß 25 % (`PlayerScrub.swift:557`–`559`) liegen bei hellem Untergrund unter 3:1 (WCAG 1.4.11).
Unkritisch (gerechnet): `Palette.secondary` auf `surface` etwa 8,3:1; `secondaryOnFocus` auf Weiß etwa 5,7:1; Filter-Zähler mit `opacity(0.6)` (`SourceFilterBar.swift:40`) etwa 6:1.
- **Auswirkung:** Hinweise im Player (Folgentitel, Endzeit, „Klick: jetzt · Wischen: abbrechen“) sind über hellen Szenen schwer lesbar – auch ohne Sehbehinderung, aus Sofa-Entfernung.
- **Empfehlung:** `.secondary` im Player und auf Bildern durch `Theme.Palette.secondary` ersetzen und Karten über Video auf deckenden Grund stellen (`Palette.scrim` über dem Material, wie in `PlayerTrackPanel.swift:164` bereits gemacht). Verlauf der Steuerleiste oben nicht auf „klar“ auslaufen lassen, solange dort Text steht; `LandscapeCard` mit demselben Verlauf wie `HeroCard` (`RowViews.swift:469`). Orange/Rot-Banner mit schwarzer Schrift bzw. dunklerem Grund.
- **Priorität:** mittel · **Aufwand:** S · **Sicherheit:** plausibel (gerechnet, nicht gemessen)

**Feste Schriftgrößen:** 9 Stellen; unkritisch sind Symbolgrößen (`Theme.swift:445`, `StatusCard.swift:84`, `RowViews.swift:551`) und der skalierende Rang (`RowViews.swift:487`, `:571`). Echte Textstellen mit fester Größe: Anmeldecode 90 pt (`SyncLoginView.swift:32`), Initialen (`PlayerApp.swift:224`, `PersonView.swift:19`) und Untertitel (`SubtitleTextView.swift:68`, dort gewollt über die eigene Einstellung).

---

## 9. Build, Projekt, Kommentare

- **Warnungen:** Nicht per Einstellung unterdrückt (kein `SWIFT_SUPPRESS_WARNINGS`, kein `-suppress-warnings`). Sie gehen aber verloren: Der Build schreibt alles nach `build.log` und zeigt nur bei Fehlschlag die Zeilen mit `error:` (`.github/workflows/build.yml:78`–`80`); das Log wird nur bei Fehlschlag hochgeladen (`:133`–`138`). `SWIFT_TREAT_WARNINGS_AS_ERRORS` ist nicht gesetzt.
- **Lint/Format:** Keine `.swiftlint.yml`, keine `.swiftformat`, keine `.editorconfig`. Der Stil ist trotzdem einheitlich, mit zwei Ausnahmen: sehr lange Zeilen (48 über 160 Zeichen, eine mit 450) und mehrere Anweisungen je Zeile mit `;` (z. B. `AppModel.swift:255`, `:260`, `DetailViews.swift:778`, `PlayerScreen.swift:283`).
- **Empfehlung (ohne eigenen Befund):** In CI die Anzahl der Warnungen aus `build.log` zählen und als Hinweis ausgeben; `swift-format` oder SwiftLint mit wenigen Regeln (Zeilenlänge 160, keine rohen `.font(.` außerhalb `Views/Design`, kein `Task {` in `onChange`) als nicht blockierenden Schritt.

### Kommentar-Qualität

Die Kommentare sind die größte Stärke und zugleich eine Last. Sie erklären fast immer das Warum, oft mit Gerätebefund und Build-Nummer („Build 198 scrolled to the played row while it was still being dismissed“, `DetailViews.swift:987`). Das ist für ein Projekt, das nur am Gerät prüfbar ist, wertvoll und sollte bleiben.

Problematisch ist die Menge an Verweisen auf den Entstehungsprozess: 812 Kommentarstellen nennen Wellen, Runden oder Review-Nummern („Welle F-k R2 (m2)“, „Review Q I3/N1“, „Task 7“). Diese Kürzel sind ohne `docs/superpowers/plans` nicht auflösbar und altern. Veraltete Aussagen (Stichprobe):

- `App/Sources/Views/Design/Theme.swift:5` – „Noch an keiner bestehenden Stelle eingesetzt (Welle F-0)“; `Theme` wird inzwischen 229-mal genutzt.
- `App/Sources/AppModel.swift:642` – „liest die privaten Caches oben“; die Caches sind laut `:532` bewusst nicht mehr privat.
- `App/Sources/Views/DetailViews.swift:689` – „Reihenfolge von AIOStreams“; die Liste wird über `orderedStreams` nach Einstellung sortiert (`:836`, `:841`).
- `App/Sources/Views/PlayerScreen.swift:6` – „Kennt nur `PlaybackEngine`“; `PlayerScreen` legt `AetherBackend` selbst an (`:109`).

Empfehlung: Kürzel in neuen Kommentaren weglassen (die Begründung selbst reicht, die Herkunft steht im Git-Verlauf), und veraltete Kopf-Kommentare beim Schneiden der Großdateien (Q-1, Q-4, Q-5) mit bereinigen.

---

## Befundübersicht

| ID | Titel | Priorität | Aufwand |
|---|---|---|---|
| Q-1 | `PlayerControls`: 721 Zeilen, 45 `@State`, 8 Dateien | hoch | L |
| Q-2 | `PlayerControls`: 27 Parameter | mittel | M |
| Q-3 | Abspiel-Orchestrierung in `StreamListView` | hoch | L |
| Q-4 | `DetailViews.swift`: 17 Typen, 5 Bildschirme | mittel | M |
| Q-5 | `AppModel` als Gott-Objekt | hoch | L |
| Q-6 | Views/Erweiterungen in falschen Dateien | niedrig | S |
| Q-7 | Zeitformat viermal | mittel | S |
| Q-8 | Folgen-ID/-Titel/-Request mehrfach von Hand | mittel | M |
| Q-9 | Trakt/Simkl über Zeichenketten | mittel | M |
| Q-10 | Fokus-Schleife, Knopfstil, Balken doppelt | niedrig | S |
| Q-11 | Cache-/Datei-/Speichermuster mehrfach | mittel | M |
| Q-12 | App im Swift-5-Modus | hoch | L |
| Q-13 | Rund 100 freie `Task {}`, feste Wartezeiten | mittel | M |
| Q-14 | `ObservableObject`/`@Observable` gemischt | mittel | M |
| Q-15 | `nonisolated(unsafe)`/`try!`/`as!` | niedrig | M |
| Q-16 | `try?` verschluckt Schreibfehler; zwei Dekodier-Stile | mittel | S |
| Q-17 | PlayerCore exportiert fast alles | niedrig | M |
| Q-18 | Toter bzw. nur von Tests genutzter Code | niedrig | S |
| Q-19 | Sprache gemischt, Log-Kategorien als Zeichenketten | niedrig | S |
| Q-20 | Magic Numbers außerhalb des Designsystems | niedrig | M |
| Q-21 | Testbare Logik in der App | hoch | M |
| Q-22 | Tests laufen nicht in CI | hoch | S |
| Q-23 | Tests nach Stufen statt Quelldateien | niedrig | M |
| Q-24 | Keine Lokalisierung, README verspricht DE/EN | hoch | S / L |
| Q-25 | Formate und Plural fest deutsch, teils fehlerhaft | niedrig | M |
| Q-26 | Poster-Kacheln ohne VoiceOver-Label | hoch | S |
| Q-27 | Player für VoiceOver unbeschriftet | mittel | M |
| Q-28 | Bewegung/Transparenz reduzieren nicht beachtet | mittel | S |
| Q-29 | Sekundärtext auf Bild/Video/Glas unter 4,5:1 | mittel | S |

**Empfohlene Reihenfolge:** zuerst die kleinen mit großer Wirkung (Q-22 Tests in CI, Q-26 Kachel-Labels, Q-24 README, Q-7, Q-29), dann Q-21 (Logik nach PlayerCore) als Vorarbeit für die drei großen Schnitte Q-3, Q-1, Q-5, und parallel dazu Q-12 mit Warnstufe beginnen.

## Am Gerät prüfen

- VoiceOver auf Startseite, Suche und im Player: Was wird für eine Poster-Kachel mit Bild gelesen (Q-26), was für die Spielfläche (Q-27)?
- Kontrastpaare 1–6 aus Q-29 mit einer hellen Szene bzw. einem hellen Hintergrundbild fotografieren.
- Systemeinstellung „Bewegung reduzieren“ an: Starten Fokus-Videos und das Aufklappen der Poster weiterhin (Q-28)?
- Profil auf „English“ stellen: Welche Texte wechseln (erwartet: nur Titel, Beschreibungen, Trailer; Q-24)?
- Serie mit genau einer Folge: Zeile „Umfang“ im Abschnitt „Über“ (Q-25).

## Grenzen dieser Prüfung

- Nicht jede Zeile gelesen: `PlayerScreen.swift` ab Zeile 600, `RowViews.swift` 130–300, `SettingsKit.swift`, `ImagePipeline.swift`, `AppUpdate.swift` und die `AppModel+*`-Dateien nur über Deklarationen, Metriken und Ausschnitte.
- Toter Code und Testlücken beruhen auf wortgenauer Namenssuche, nicht auf einem Compiler- oder Coverage-Lauf.
- Typ-, `body`- und Funktionslängen stammen aus einem Skript, das Einrückung auswertet; einzelne Werte können um wenige Zeilen abweichen.
- Kontrastwerte sind für den ungünstigen Fall gerechnet; die Materialien von tvOS sind nicht exakt modellierbar.
