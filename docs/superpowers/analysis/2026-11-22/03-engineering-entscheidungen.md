# 03 · Engineering-Analyse der Entscheidungen und Planungen

Stand: Branch `integ`, Commit `b2188a2` (Build 249). Rein lesend und statisch erhoben; Laufzeitverhalten ist aus dem Code **abgeleitet**. Alle `Datei:Zeile`-Angaben beziehen sich auf diesen Commit.

Aufbau:

1. Soll-Ist-Tabelle aller 106 Entscheidungen aus Specs, Plänen, README und CHANGELOG
2. Zusammenfassung
3. Wichtigste Abweichungen
4. Widersprüche zwischen den Dokumenten, Zahlen aus der Git-Historie
5. Tragende Grundentscheidungen im ADR-Stil (sieben ADRs)
6. Bewertung des Planungsprozesses
7. Technische Schulden mit Priorität

Hinweis zu den Kennzeichen: In den Dokumenten des Repos steht **[U]** für eine Nutzerentscheidung; das entspricht
**[N]** in dieser Analyse. In Abschnitt 3 und 4 tragen Abweichungen die IDs `A-1` bis `A-9` und Widersprüche `W-1`
bis `W-20`; sie sind nicht mit den Bug-IDs `A-A-…`/`W-A-…` aus [02](02-bugs.md) zu verwechseln.

**Quellen-Kürzel**
- **S1** = `docs/superpowers/specs/2026-11-21-tvos-player-design.md`
- **S2** = `docs/superpowers/specs/2026-11-21-design-umbau-design.md`
- **P1** = `docs/superpowers/plans/2026-11-21-p1-kern-und-geruest.md`
- **P2** = `docs/superpowers/plans/2026-11-21-design-umbau.md`
- **R** = `README.md`, **CL** = `CHANGELOG.md`
- [U] = Nutzerentscheidung, [C] = Entscheidung des Assistenten (laut Dokument korrigierbar)

**Status-Definition:** umgesetzt · teilweise · abgewichen (anders gebaut, nicht als Änderung der Entscheidung dokumentiert) · vergessen · überholt (bewusst geändert und im CHANGELOG nachlesbar) · nicht prüfbar.

Hinweis zu Regel 3 des Briefings: Die Kontokennung des Repos (steckt im Bundle-ID-Präfix und in Links) wird hier nicht ausgeschrieben.

---

## 1. Tabelle

### A. Architektur und Struktur

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-1 | PlayerCore importiert nur Foundation (+ FoundationNetworking auf Linux) | S1 §5 [C], P1 Global Constraints | teilweise | `Packages/PlayerCore/Sources/PlayerCore/Playback/SubtitleGeometry.swift:2`, `Packages/PlayerCore/Sources/PlayerCore/Playback/SubtitleStyle.swift:2` | 132× `import Foundation`, 6× FoundationNetworking, 2× `CoreGraphics` (hinter `#if canImport`). Linux-Tests bleiben möglich; die Regel ist dem Wortlaut nach verletzt. |
| E-2 | Eigenes Paket `Packages/PlaybackKit` mit `PlayerEngine`-Protokoll + Aether-Adapter | S1 §5 [C], P1 Task 8 | abgewichen | `App/Sources/Playback/PlaybackEngine.swift:9`, `App/Sources/Playback/PlaybackEngine.swift:110` | Kein Paket `PlaybackKit` (unter `Packages/` nur `PlayerCore`, `AetherFEL`). Protokoll heißt `PlaybackEngine` und liegt in der App. CL 0.1.0 sagt nur „player behind its own playback interface“; der Wegfall des Pakets ist nirgends vermerkt. |
| E-3 | Engine hinter eigener Schnittstelle, damit ein zweites Backend ohne App-Umbau möglich bleibt | S1 §4 [C] | teilweise | `App/Sources/Views/PlayerScreen.swift:37`, `App/Sources/Views/PlayerScreen.swift:120`, `App/Sources/Views/Player/XRayProbeHook.swift:46`, `App/Sources/Views/Player/PlayerExit.swift:55` | Die Views sind generisch über `E: PlaybackEngine`, aber `PlayerScreen` hält konkret `AetherBackend`, 13 App-Dateien importieren `AetherFEL`, es gibt Downcasts und statische Zugriffe auf `AetherBackend`. Der Kommentar „Die App kennt nur dieses Protokoll“ (`PlaybackEngine.swift:6`) stimmt nicht mehr. |
| E-4 | AetherEngine 7.71.2; Engine auf feste Version gepinnt | P1 Tech Stack/Task 8 (`from:`), CL Wave B | umgesetzt | `Packages/AetherFEL/Package.swift:17` | `exact: "7.71.2"` – strenger als der Plan (`from:`). |
| E-5 | App als XcodeGen-Projekt, tvOS 18.0 Minimum, geplante Bundle-ID, Anzeigename „Player“ | P1 Global Constraints, S1 §5 | umgesetzt | `App/project.yml:5`, `App/project.yml:32`, `App/project.yml:46` | – |
| E-6 | Tech-Stack „Swift 6“ | P1 Tech Stack, P2 Tech Stack | abgewichen | `App/project.yml:47` | App-Target baut mit `SWIFT_VERSION: "5.0"` (kein Swift-6-Sprachmodus, keine strikte Nebenläufigkeitsprüfung in der App). PlayerCore: `swift-tools-version: 6.0`. Nicht dokumentiert. |
| E-7 | Ordner in PlayerCore: Models, Addons, Services, Import, Ranking, Sync, Store | S1 §5 [C] | umgesetzt | Verzeichnisse unter `Packages/PlayerCore/Sources/PlayerCore/` | Zusätzlich gewachsen: `Playback`, `Progress`, `Phone`, `Update`, `XRay`, `Logging`. |
| E-8 | Testbare Logik gehört nach PlayerCore, mit Tests | S2 §3, P2 Architecture | umgesetzt | `Packages/PlayerCore/Tests/PlayerCoreTests/` (76 Dateien, 965 `@Test`) | Plan P2 nennt 86 Tests als Startwert. |
| E-9 | CI baut nur die App; Kern-Tests laufen lokal im Container (Podman, `swift:6.2`) | P1 Architecture + Global Constraints, P2 Global Constraints | umgesetzt | `.github/workflows/build.yml:74` (kein Testschritt; `grep -n 'swift test\|podman' build.yml` ohne Treffer) | Wie geplant – Folge: 965 Tests sind kein Gate für ein Release; ein roter Kern kann als `build-N` erscheinen. |

### B. Persistenz und Geheimnisse

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-10 | Persistenz: Codable-JSON in Application Support | S1 §5 [C] | überholt | `App/Sources/DefaultsStorage.swift:14`, `App/Sources/DefaultsStorage.swift:20` | Jetzt: LZFSE-komprimiert in UserDefaults plus Dateien in Application Support (falls beschreibbar) und immer Caches. Dokumentiert in CL 0.2.0 (Fehler 513). S1 §5 wurde nicht nachgezogen. |
| E-11 | „JSON pro Profil“ | S1 §5 [C] | teilweise | `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:26` | Eine `profiles.json` für alle Profile (so steht es schon in P1 Task 3 – Widerspruch Spec/Plan). Fortschritt, Import-Daten und Kataloge liegen je Profil. |
| E-12 | `schemaVersion` im Dokument | S1 §5, P1 Global Constraints | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:4`, `:55` | `currentSchema` steht weiter auf 1, obwohl seit P1 viele Felder dazukamen und zwei wegfielen. Eine Datei mit höherer Version wird wie eine kaputte behandelt (Standardprofil + `.bak`), siehe Abschnitt 3. |
| E-13 | Atomares Schreiben | S1 §5, P1 Global Constraints | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Store/BlobStorage.swift:18`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:85` | Dateien `.atomic`; UserDefaults-Weg mit Gegenlesen. |
| E-14 | Kaputte/ältere Profildatei → Standardprofil, alte Datei bleibt als `.bak` | P1 Review Focus, Task 3 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:36`, `Packages/PlayerCore/Tests/PlayerCoreTests/StoreTests.swift:25`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:68` | `.bak` liegt nur als Datei (nie in UserDefaults). Ist Application Support nicht beschreibbar, liegt sie nur in Caches, die tvOS leeren darf. Ein zweiter Lesefehler überschreibt die erste `.bak`. |
| E-15 | Geheimnisse (Tokens, API-Schlüssel) in der Keychain | S1 §5 [C], S1 §7a | abgewichen | `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:25`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:31` | `apiKeys` und `syncTokens` stehen im Profil-JSON (UserDefaults + Dateien). `grep -rniE 'Keychain\|SecItem\|kSecClass'` über App/Packages: kein Treffer. Einzige „Doku“ ist der Code-Kommentar in Zeile 24 („bewusst im Profil“). |
| E-16 | Geheimnisse im Export verschlüsselt/optional | S1 §5 [C] | abgewichen | `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:45`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:121`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:191` | Export ist Klartext-JSON mit allen Schlüsseln und Tokens, abrufbar per `GET /export?t=…` über unverschlüsseltes HTTP im LAN. S1 §7a sagt selbst „also included in the export“ (Widerspruch innerhalb von S1). |
| E-17 | JSON-Export und -Import aller Profile als Sicherheitsnetz | S1 §7a, R Setup | umgesetzt | `App/Sources/AppModel.swift:556`, `App/Sources/AppModel.swift:590`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:142` | – |
| E-18 | Anti-Ziel: Einstellungen gehen bei Neuinstallation/Neu-Signieren nicht verloren | S1 §2, §7a | nicht prüfbar | – | Nur am Gerät klärbar. Abgeleitet: Daten liegen im App-Container (UserDefaults + Dateien); „Bild & Ton“ geht beim Zurückgehen auf einen älteren Build laut CL 249 bewusst verloren. |
| E-19 | Neue Profilfelder bekommen Standardwerte in `init(from:)` | S2 §3, P2 Global Constraints | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:81`, `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:58` | Durchgehend `decodeIfPresent`; neuere Felder zusätzlich mit `try?` (ein kaputtes Feld verwirft nicht das Profil). |
| E-20 | „Profile werden nie nur im Cache gehalten“ | CL Wave A (Fixed) | teilweise | `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:37`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:91`, `App/Sources/DefaultsStorage.swift:21`, `App/Sources/DefaultsStorage.swift:26` | Gilt nur, solange die Profile komprimiert ≤ 512 KB sind. Darüber: nur Datei; ist Application Support nicht beschreibbar, liegt sie dann ausschließlich in Caches. Es gibt dafür eine Fehler-Logzeile, aber keine Sperre. |
| E-21 | Große Datenblöcke als Dateien (Absturzschutz, UserDefaults < 1 MB) | CL Wave A | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:35`, `:39`, `:67` | 96 KB je Block, 640 KB gesamt. |
| E-22 | Katalog-Cache läuft nach 24 h ab | CL Wave A | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Store/TimedCache.swift:22`, `App/Sources/AppModel.swift:23` | – |
| E-23 | Keine API-Schlüssel im Repo; Eingabe nur zur Laufzeit | P1/P2 Global Constraints, R Setup | umgesetzt | `tools/check_ipa.sh:38`, `.github/workflows/build.yml:227` | Mustersuche nach Schlüssel-Zuweisungen in App/Packages/tools/.github ohne Treffer; CI prüft zusätzlich die IPA. |
| E-24 | Öffentliches Repo: keine Namen, keine IPs | S2 §3, P2 Global Constraints, R Setup („no … addresses“) | teilweise | `App/project.yml:3`, `App/Sources/RemoteLog.swift:11`, `docs/superpowers/plans/2026-11-21-design-umbau.md:27`, `Packages/PlayerCore/Tests/PlayerCoreTests/AppUpdateTests.swift:22`, `Packages/PlayerCore/Sources/PlayerCore/Logging/LogRedact.swift:148` | Die Kontokennung steht im Bundle-ID-Präfix, im Logger-Subsystem, in README-Links und sogar in den Plänen selbst (Zeile „Commit identity“). Adressen aus privaten Netzbereichen stehen als Beispielwerte in Tests und in einem Kommentar (Art: Testdaten, keine echten Geräte erkennbar). |
| E-25 | Logs schwärzen Schlüssel und Tokens vor dem Schreiben | R Setup, CL Wave A | umgesetzt | `App/Sources/RemoteLog.swift:42`, `App/Sources/PlayerApp.swift:90`, `Packages/PlayerCore/Tests/PlayerCoreTests/LogRedactTests.swift` | Einziger `Logger` der App sitzt in `RemoteLog`; auch der Fehlerdialog läuft durch `LogRedact`. |
| E-26 | Lange Texte/Schlüssel nie per Fernbedienung: Handy-Seite mit QR und lokalem Server | S1 §5 [C], R Setup | umgesetzt | `App/Sources/Views/PhoneInputView.swift:14`, `App/Sources/Views/PhoneInputView.swift:27`, `App/Sources/Views/PhoneInputView.swift:125` | – |
| E-27 | Kein iCloud/CloudKit (Nicht-Ziel); Datenmodell bleibt dafür offen | S1 §2 [U] | umgesetzt | `grep -rnEi 'CloudKit\|iCloud\|NSUbiquit'` ohne Treffer | Nicht-Ziel eingehalten. |

### C. Profile, Sprache, Ton und Bild

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-28 | Profile vollständig eigenständig (alle Einstellungen je Profil) | S1 §2 [U], R Features | überholt | `App/Sources/AppModel.swift:15`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:38` | „Bild & Ton“ gilt seit Build 249 je Gerät; in CL 249 ausführlich dokumentiert. README sagt weiter „each profile is self-contained“. |
| E-29 | Profilauswahl beim Start, wenn mehr als ein Profil | S1 §6 [C] | umgesetzt | `App/Sources/PlayerApp.swift:77`, `App/Sources/AppModel.swift:232` | – |
| E-30 | App-Sprache Deutsch/Englisch, je Profil umschaltbar | S1 §2 [U], R Features („interface is available in German and English“) | abgewichen | `App/Sources/AppModel.swift:346`, `App/Sources/Views/DetailViews.swift:523`, `App/Sources/Views/Settings/AppearanceSettings.swift:20`, `App/Sources/PlayerApp.swift:95` | `Profile.language` steuert nur die TMDB-Sprache und die Trailerwahl. Alle Oberflächentexte sind fest deutsch; `find App -name '*.strings' -o -name '*.xcstrings' -o -name '*.lproj'` ohne Treffer. Die Einstellung beschreibt sich selbst als „Sprache von Titeln, Beschreibungen und Katalogen“. P2 legt „The interface is in German“ fest – README widerspricht. |
| E-31 | Tonspur-Vorrang Deutsch → Englisch → Original | S1 §2 [C], P1 Global Constraints | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:52`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:213`, `App/Sources/Views/PlayerScreen.swift:432` | Standard unverändert; seit Build 144 zusätzlich Presets und Spur-Gedächtnis je Serie (hat Vorrang). |
| E-32 | Untertitel standardmäßig aus | S1 §2 [U], P1 Global Constraints | abgewichen | `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:53`, `Packages/PlayerCore/Sources/PlayerCore/Playback/SubtitlePicker.swift:85` | Standard ist `.forcedOnly`; bei fremder Tonsprache wählt diese Stufe eine volle Untertitelspur. CL Wave A nennt nur „automatic selection“, nicht den geänderten Standard. Eine [U]-Entscheidung. |
| E-33 | Fortschrittsquelle lokal/Trakt/Simkl; lokal wird immer geschrieben; andere Dienste werden mitgemeldet | S1 §2 [U/C] | umgesetzt | `App/Sources/AppModel.swift:74`, `App/Sources/AppModel.swift:186`, `App/Sources/AppModel.swift:202` | Scrobble geht an alle verbundenen Dienste, Abgleich nur von der gewählten Quelle. |
| E-34 | Autoplay der nächsten Folge mit gleicher Quelle (`bingeGroup`), Ton-/Untertitelwahl wird mitgenommen | S1 §2 [C], CL 0.2.0/Wave B | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Progress/NextEpisode.swift:35`, `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:173`, `App/Sources/Views/DetailViews.swift:1136` | Erweitert um Release-Abgleich (CL Wave B). |
| E-35 | TrueHD/DTS-HD werden zu Mehrkanal-PCM dekodiert | S1 §2 [U-Setup], R Features (Audio) | abgewichen | `Packages/PlayerCore/Sources/PlayerCore/Playback/AudioShapingSettings.swift:41`, `App/Sources/Views/Settings/DeviceCheckSettings.swift:58`, `App/Sources/Playback/PlayerAudioOptions.swift:21`, `App/Sources/Views/Settings/AudioSettings.swift:56` | Standard ist die Brücke `surroundCompat`: Umwandlung in Dolby Digital Plus 5.1. Mehrkanal-PCM gibt es nur mit der Option „verlustfrei“. Für den optischen Weg zur 5.1-Anlage ist das fachlich die passendere Lösung – README beschreibt aber den Options- als Normalfall. |
| E-36 | Atmos-Höhen/Bitstream-Passthrough ist Nicht-Ziel | S1 §2 [C] | abgewichen | `App/Sources/Views/Settings/DeviceCheckSettings.swift:57`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:207` | README wirbt mit „5.1 and Atmos as passthrough“; durchgereichte Spuren werden bei der Spurwahl sogar bevorzugt. Kein eigener Bau (Engine-Standard), aber das Nicht-Ziel ist stillschweigend zum Feature geworden. |
| E-37 | Dolby-Digital-Spuren werden bevorzugt | R Features, CL 0.4.0 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:207` | Innerhalb der gewählten Sprache. |
| E-38 | Dolby Vision P7 FEL: Zusatzschicht wird angewendet; Trait `DolbyVisionFelCurves` über `Packages/AetherFEL` | R Features/Structure, CL Build 108 | teilweise | `Packages/AetherFEL/Package.swift:20`, `App/Sources/Playback/PlaybackEngine.swift:133`, `App/Sources/Views/Settings/DeviceCheckSettings.swift:53` | Trait und Build-Wächter sind da. Die In-App-Tabelle „Was spielt wie“ behauptet aber weiter „bei FEL wird die Zusatzschicht verworfen“ – veralteter Text in der App. Wirkung am Bild nur am Gerät prüfbar. |
| E-39 | Bildschirmschoner bleibt während der Wiedergabe aus | CL Wave D | umgesetzt | `App/Sources/Views/Player/PlayerPictureSound.swift:35` | – |

### D. Quellen und Addons

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-40 | Stream-Reihenfolge von AIOStreams bleibt; die App filtert nur nicht Abspielbares | S1 §7a [C], P1 Global Constraints | überholt | `Packages/PlayerCore/Sources/PlayerCore/Models/SourceSettings.swift:17`, `App/Sources/AppModel+SourceOrder.swift:22`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamListDisplay.swift:6` | Anzeige-Standard ist „Wie Addon“, aber: Dubletten werden entfernt, „Smart (App)“ ist wählbar, und jede automatische Wahl (Beste Wahl, Ausweichquelle, nächste Folge) nutzt immer die App-Ordnung. Dokumentiert in CL Wave C, 144, 162. |
| E-41 | „`Ranking` bleibt klein“ | S1 §7a [C] | überholt | `Packages/PlayerCore/Sources/PlayerCore/Ranking/` (8 Dateien: SourceRanking, BestChoice, ReleaseMatch, SourceFilter, StreamListDisplay …) | Folge von E-40; CL Wave C/162/249. |
| E-42 | Keine direkte TorBox-Anbindung in der App (Login, Cache-Prüfung) – alles über AIOStreams | S1 §2 Nicht-Ziel [C] | abgewichen | `Packages/PlayerCore/Sources/PlayerCore/Services/TorBox.swift:27`, `App/Sources/Views/TorBoxFilesRow.swift:96`, `App/Sources/Views/TorBoxFilesRow.swift:126`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:102` | Scope-Drift: eigener TorBox-API-Client mit Schlüssel, Dateiliste und Abspiel-Link. CL Wave C führt es als Feature; dass damit ein Nicht-Ziel fällt, steht nirgends. README bewirbt es an zweiter Stelle der Feature-Liste. |
| E-43 | Stream ohne oder mit kaputter URL erscheint nicht, kein Absturz | P1 Review Focus | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:153`, `App/Sources/AppModel.swift:509` | Seit Build 198 fallen auch Addon-Hinweiseinträge heraus. |
| E-44 | Ein langsames Addon hält die anderen nicht auf | P1 Review Focus, CL Wave C | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:37`, `App/Sources/AppModel+StreamSearch.swift:42` | Zeitgrenze je Addon, einstellbar. |
| E-45 | Fehlgeschlagene Links werden 8 h gemieden | CL Wave C | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Playback/FailedLinks.swift:30` | – |
| E-46 | Profilwechsel während der Quellensuche mischt keine Ergebnisse | CL Wave D | umgesetzt | `App/Sources/AppModel.swift:252`, `App/Sources/AppModel+StreamSearch.swift:56` | Besitzer-Profil + Epoche je Suche. |
| E-47 | Nuvio-Import: Unbekanntes überspringen, Dubletten zusammenführen (16 → 9), Addon-Quellen vormerken | S1 §2/§7a, P1 Task 4 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Import/NuvioImport.swift:55`, `Packages/PlayerCore/Tests/PlayerCoreTests/NuvioImportTests.swift:12` | – |
| E-48 | Plattencache für den laufenden Film, standardmäßig aus | CL Wave B | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:34`, `App/Sources/Playback/DiskCacheProxy.swift:175` | – |
| E-49 | Collection-Link: höchstens 8 MB | CL Build 249 | umgesetzt | `App/Sources/CollectionLinkStore.swift:183`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:13` | – |

### E. Dienste

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-50 | TMDB: Metadaten de-DE, Rückfall en-US, Bilder w500/w1280 | S1 §2 [C], P1 Task 7 | umgesetzt | `App/Sources/AppModel.swift:346`, `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBClient.swift:11` | – |
| E-51 | TVDB liefert die Folgenreihenfolge | S1 §2 [U Dienst, C Rolle], §6.4, Phase P5 | vergessen | `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:102`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:180` | `grep -rniE 'tvdb'` findet nur das Schlüsselfeld der Handy-Seite, einen Profil-Kommentar und ein ID-Präfix. Kein Client, kein Aufruf. Die Handy-Seite nimmt einen TVDB-Schlüssel an, der nie benutzt wird. |
| E-52 | MDBList: Bewertungen | S1 §2 [C], R Features | umgesetzt | `App/Sources/AppModel.swift:550`, `Packages/PlayerCore/Sources/PlayerCore/Services/Ratings.swift:40` | – |
| E-53 | MDBList-Listen als Quelle/Import | S1 §2 [U], Phase P2, R Features („lists from TMDB, Trakt and MDBList are available“) | vergessen | `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift:8` | `SourceKind` hat keinen MDBList-Fall; `grep -rniE 'mdblist'` in `Import/`, `RowCatalog.swift`, `Phone/` findet nur das Schlüsselfeld. README sagt das Gegenteil. |
| E-54 | Trakt/Simkl: Geräte-Login, Scrobble-Regeln (80 %, Pause, 409), Wiederholung bei 401/429 | S1 §5, CL 0.2.0/0.4.0 | umgesetzt | `App/Sources/AppModel.swift:129`, `Packages/PlayerCore/Sources/PlayerCore/Sync/ScrobbleTracker.swift:18`, `Packages/PlayerCore/Sources/PlayerCore/Sync/APIRequest.swift:97`, `Packages/PlayerCore/Sources/PlayerCore/Sync/TraktClient.swift:71` | „Gesehen“ ab 0,92 (`WatchProgress.swift:32`), Scrobble-Start bis 0,8. |
| E-55 | Kalenderdaten aus TMDB (`next_episode_to_air`, Staffelfolgen) | S2 §2.6, P2 Task 5 | überholt | `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBLocalized.swift:213`, `App/Sources/AppModel+Airtimes.swift:12`, `App/Sources/AppModel+Upcoming.swift:56` | TMDB bleibt die Basis; Sendetag und -zeit kommen zusätzlich von TVmaze (abschaltbar). CL Wave C. |

### F. Startseite und Bearbeiten (Grund-Spec)

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-56 | Sechs Reihenstile (Hero, Poster, Querformat, Top 10, Logo-, Collection-Kacheln); erlaubte Stile je Inhalt | S1 §2 [U], P1 Task 2 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Home.swift:3`, `Packages/PlayerCore/Sources/PlayerCore/Models/Home.swift:23` | – |
| E-57 | Bearbeiten direkt auf dem TV: langer Druck greift die Reihe, ▲▼ verschieben, ◀▶ Stil, Play/Pause entfernt – „No menu per row“ | S1 §2 [U], P1 Task 6/9 | abgewichen | `App/Sources/Views/Home/HomeRowMenu.swift:19`, `App/Sources/Views/Home/HomeRowMenu.swift:30`, `App/Sources/Views/TileContextMenu.swift:19`, `App/Sources/Views/Home/HomeManagerView.swift:12` | Langer Druck öffnet jetzt ein Kontextmenü (Kachel- und Reihenaktionen); bearbeitet wird in der Verwalter-Seite „Reihen & Collections“ und am Handy. `HomeEditor` hat `cancel/commit/nextStyle/removeGrabbed` nicht mehr. CL 144/249 führen Verwalter und Menü als „Added“; dass damit die ausdrückliche [U]-Regel „kein Menü pro Reihe“ fällt, ist nirgends festgehalten. |
| E-58 | Plus-Kachel unter den Reihen, nur im Bearbeiten-Modus | S1 §2 [U] | überholt | `App/Sources/Views/Home/HomeManagerView.swift:145`, `App/Sources/Views/Home/AddRowBrowser.swift:202` | Ersetzt durch „Reihe hinzufügen“ im Verwalter mit Browser nach Kategorien (CL 144). |
| E-59 | Abbrechen stellt exakt den Zustand vor dem langen Druck wieder her | P1 Review Focus | teilweise | `Packages/PlayerCore/Sources/PlayerCore/Models/HomeManager.swift:230`, `App/Sources/Views/Home/HomeManagerView.swift:12` | Nur noch für einen laufenden Verschiebe-Zug (`cancelMove`); alle anderen Änderungen werden „sofort gespeichert“. Ersatz: Ausblenden ist umkehrbar, Löschen fragt nach. |
| E-60 | Zwei Fertigpakete (Streaming-Dienste, Genres) | S1 §2 [U], §9 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/RowCatalog.swift:24`, `Packages/PlayerCore/Sources/PlayerCore/Import/ReadyPackages.swift` | Commit eaaf46d nennt zusätzlich ein „Studios“-Paket. |
| E-61 | Kein eigener Collection-Editor (Nicht-Ziel) | S1 §2 [U] | umgesetzt | `App/Sources/Views/Home/HomeManagerView.swift:12` | Der Verwalter ordnet Reihen, bearbeitet aber keine Collection-Inhalte. Grenzfall: Import per Link/Code mit „Aktualisieren“. |
| E-62 | Suche über TMDB **und** Addon-Kataloge | S1 §6.6 [C] | teilweise | `App/Sources/Views/DetailViews.swift:1269`, `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBClient.swift:79` | Nur TMDB (`/search/multi`); ohne TMDB-Schlüssel bleibt die Suche leer. `grep -rnE 'catalog.*search\|extra.*search'` findet nur den Reihen-Browser. |
| E-63 | Kein Live-TV/DVR/Musik; Top Shelf „später“ | S1 §2, §5 | umgesetzt | `grep -rnEi 'Live ?TV\|DVR\|TopShelf'` ohne Treffer | Nicht-Ziele eingehalten. |

### G. Design-Umbau

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-64 | `TabView` mit `Tab(…, systemImage:)`; Tabs Start, Suche, Bibliothek, Kalender, Einstellungen mit den geplanten Symbolen | S2 §2.1 [U], P2 Task 2 | umgesetzt | `App/Sources/PlayerApp.swift:94`–`:107` | – |
| E-65 | `.sidebarAdaptable` oder obere Leiste, umschaltbar | S2 §2.1/§5 | umgesetzt | `App/Sources/PlayerApp.swift:167` | – |
| E-66 | Uhr oben rechts (`HH:mm`, `TimelineView(.everyMinute)`) bei oberer Leiste | S2 §5, P2 Task 2 | umgesetzt | `App/Sources/Views/ClockView.swift:7`, `App/Sources/Views/ClockView.swift:12`, `App/Sources/PlayerApp.swift:81` | – |
| E-67 | Jeder Tab behält seinen eigenen Navigationspfad | S2 §5 | umgesetzt | `App/Sources/PlayerApp.swift:63` | – |
| E-68 | Sechs feste Akzentfarben, per `.tint` | S2 §2.4, P2 Task 1/2 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:7`, `App/Sources/PlayerApp.swift:85`, `App/Sources/Views/SettingsView.swift:107` | – |
| E-69 | Kartengröße klein/mittel/groß = 0,85 / 1,0 / 1,2, für alle Reihenstile | P2 Task 1/4 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:13`, `Packages/PlayerCore/Sources/PlayerCore/Models/PosterSize.swift:43` | Der Stil „Hero“ skaliert bewusst nicht mit. |
| E-70 | `Appearance` mit Standardwerten (sidebar, blue, medium, Hero an, Aufklappen an) | P2 Task 1 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:41` | Vier Felder dazugekommen. |
| E-71 | `heroSource`-Reihenfolge: gewählte Reihe → erste `.hero`-Reihe → erste Liste außer Weiterschauen → nil; aus = nil | P2 Task 1, S2 §7a.4 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:77` | Zusätzlich wird „Heute neu“ ausgeschlossen. |
| E-72 | `.hero`-Reihe, die Hero-Quelle ist, erscheint nicht doppelt | S2 §7a.4, P2 Task 1 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:88` | – |
| E-73 | Stil heißt im Editor „Als Hero verwenden“ | S2 §7a.4 [C] | vergessen | `Packages/PlayerCore/Sources/PlayerCore/Models/Home.swift:8` | `grep -rn 'Als Hero verwenden'` ohne Treffer; der Stil heißt weiter „Hero“. Kosmetisch. |
| E-74 | Hero: höchstens 8 Folien | S2 §8, P2 Task 3 | umgesetzt | `App/Sources/AppModel.swift:612` | – |
| E-75 | Diashow alle 10 s; pausiert, solange der Fokus in den Reihen liegt | S2 §2.2/§7a.1, P2 Task 3 | umgesetzt | `App/Sources/Views/HomeHero.swift:107`, `App/Sources/Views/HomeHero.swift:110` | – |
| E-76 | Hintergrund folgt dem Fokus nach 350 ms Ruhe; Logzeile „hero: Fokus-Hintergrund <id>“ | S2 §2.2/§5, P2 Review Focus 3 | umgesetzt | `App/Sources/Views/HomeHero.swift:27`, `App/Sources/Views/HomeHero.swift:31` | – |
| E-77 | Überblendung 0,6 s; Info-Ebene mit Logo (sonst Name), Metazeile Jahr · Laufzeit · FSK, Bewertungen, 2 Zeilen Text | S2 §2.2, P2 Task 3 | umgesetzt | `App/Sources/Views/HomeHero.swift:166`, `App/Sources/Views/HomeHero.swift:210`, `App/Sources/Views/HomeHero.swift:216`, `App/Sources/Views/HomeHero.swift:220` | – |
| E-78 | „Abspielen“ im Hero = Weiterschauen-Logik (`quickPlayRequest`, `resumeLastSource`), Folgen erst beim Druck laden | S2 §7a.2 [U], P2 Task 3 | umgesetzt | `App/Sources/AppModel.swift:629`, `App/Sources/AppModel.swift:633`, `App/Sources/Views/HomeHero.swift:344` | – |
| E-79 | Poster klappt nach 350 ms Ruhe in 0,25 s auf; abschaltbar | S2 §2.2, P2 Task 4 | umgesetzt | `App/Sources/Views/RowViews.swift:410`, `App/Sources/Views/RowViews.swift:413`, `App/Sources/Views/RowViews.swift:344` | – |
| E-80 | Reihe scrollt per `scrollPosition`, verankert am fokussierten Element | P2 Task 4 | überholt | `App/Sources/Views/RowViews.swift:351`, `App/Sources/Views/RowViews.swift:371` | Die gebundene Position erzeugte Wackeln; jetzt nur noch schreibend, ein Scroll beim Aufklappen (CL 249 Fixed). |
| E-81 | Einstellungen: 7 Kategorien (Profil, Addons, Dienste, Startseite, Aussehen, Wiedergabe, Über), je eigene Datei | S2 §2.3, P2 Task 2 | überholt | `Packages/PlayerCore/Sources/PlayerCore/Models/SettingsTree.swift:10` | Heute 9 Kategorien in drei Gruppen plus System (CL 144 und 249). |
| E-82 | Bibliothek mit Weiterschauen, Merkliste, Verlauf | S2 §2.5 [U], P2 Task 5 | umgesetzt | `App/Sources/Views/LibraryView.swift:16`, `App/Sources/Views/LibraryView.swift:27` | Zusätzlich „Meine TorBox-Dateien“. |
| E-83 | Verlauf aus dem lokalen `ProgressBook` (`finished`, neueste zuerst) | S2 §7a.5 [C], P2 Task 5 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:193`, `App/Sources/Views/LibraryView.swift:42` | Trakt-/Simkl-Verlauf weiterhin offen („later“). |
| E-84 | Kalender-Zeitraum gestern bis +14 Tage, Beschriftung Gestern/Heute/Morgen/Datum | S2 §7a.3 [U], P2 Task 5 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift:37`, `Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift:61`, `Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift:80` | Sortierung innerhalb eines Tages jetzt nach Sendezeit, dann Name. |
| E-85 | Höchstens 50 Serien, Weiterschauen zuerst, ohne Doppelte | S2 §7a.3, P2 Task 5 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift:97` | – |
| E-86 | Höchstens 4 Abrufe gleichzeitig | P2 Task 5 | umgesetzt | `App/Sources/AppModel+Upcoming.swift:41` | – |
| E-87 | Kalender-Cache 6 h im Speicher | S2 §7a.3, P2 Task 5 | umgesetzt | `App/Sources/AppModel+Upcoming.swift:8` | Nach Fehlern nur 5 min (`:10`). |
| E-88 | Leerer Kalender zeigt „Keine neuen Folgen in den nächsten 14 Tagen“ statt Fehler | P2 Review Focus 4, Task 5 | umgesetzt | `App/Sources/Views/CalendarView.swift:31` | – |
| E-89 | `SourceKind.upcoming` / `CatalogSource.upcoming` („Heute neu“), im Hinzufügen-Dialog angeboten | S2 §7a.6 [C], P2 Task 1/5 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift:18`, `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift:45`, `Packages/PlayerCore/Sources/PlayerCore/Models/RowCatalog.swift:80` | – |
| E-90 | Bilder nur über `RemoteImage`/`ImagePipeline` | S2 §3, P2 Global Constraints | umgesetzt | `App/Sources/ImagePipeline.swift:386` | `grep -rn 'AsyncImage'` in der App ohne Treffer. Fokus-Videos laufen über einen eigenen `AVQueuePlayer` (`App/Sources/Views/FocusVideo.swift:166`) – keine Bilder, aber ein zweiter Medienweg neben der Engine. |
| E-91 | Eigener Bildlader mit 400 MB Platten-Cache | CL 0.4.0 | umgesetzt | `App/Sources/ImagePipeline.swift:49` | – |
| E-92 | Bild-Cache passt sich dem freien Speicher an | CL Wave A | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Services/ImageCacheBudget.swift:10`, `App/Sources/ImagePipeline.swift:150` | 16–160 MB, während der Wiedergabe höchstens 24 MB. |
| E-93 | Nicht-Ziele: Watch Party, IPTV, KI-Reihen, „Überraschung“, Ambient-Modus, eigene Schriften, 12 Farbthemen | S2 §2 | umgesetzt | `grep -rnEi 'watch ?party\|iptv\|surprise\|überrasch\|ambient'` und `'\.custom\(\|\.ttf\|\.otf'` ohne Treffer | Eingehalten. |
| E-94 | Nicht-Ziel: Trailer im Hero | S2 §2 | umgesetzt | `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift:68` | Eingehalten, aber vorbereitet: Importe speichern `heroVideo` („not played yet“), und Kacheln spielen seit Build 249 Fokus-Videos mit Ton. Der nächste Schritt wäre die Aufhebung. |
| E-95 | Nicht-Ziel: Stream-Listenstil-Editor | S2 §2 | teilweise | `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamListDisplay.swift:6`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamListDisplay.swift:21`, `App/Sources/Views/SourceFilterBar.swift` | Kein Editor, aber inzwischen Einstellungen für Sortierung und App-Plaketten sowie Filterchips – die Quellenliste ist konfigurierbar geworden. |

### H. CI, Release, Lizenz, Update

| ID | Entscheidung | Quelle | Status | Beleg | Anmerkung |
|---|---|---|---|---|---|
| E-96 | CI baut eine unsignierte IPA als Artefakt | P1 Task 9, R Installation | umgesetzt | `.github/workflows/build.yml:81`, `.github/workflows/build.yml:110`, `.github/workflows/build.yml:139` | – |
| E-97 | Runner macos-26, Xcode 26.3 | P1 Tech Stack | umgesetzt | `.github/workflows/build.yml:20`, `.github/workflows/build.yml:31` | Wählt Xcode 27, falls vorhanden, sonst 26.3. |
| E-98 | Rollendes Release `app-main` nur aus `main` | R Installation/Releases | umgesetzt | `.github/workflows/build.yml:152`, `.github/workflows/build.yml:187` | – |
| E-99 | Build-Nummer = CI-Laufnummer, in der App sichtbar | R Building/Releases, CL Wave A | umgesetzt | `.github/workflows/build.yml:80`, `App/project.yml:34`, `App/Sources/AppUpdater.swift:27` | – |
| E-100 | CI prüft den FEL-Trait und die Engine-Frameworks in der App | R Building, CL Build 108 | umgesetzt | `.github/workflows/build.yml:84`–`:101`, `.github/workflows/build.yml:112`–`:122`, `Packages/AetherFEL/Sources/AetherFEL/FelBuildGuard.swift` | Zusätzlich: kein direkter Engine-Import (`build.yml:102`). |
| E-101 | Jeder integ-/main-Build als Release `build-<n>`; vorher IPA-Prüfung auf Schlüssel/Adressen | R Releases, CL Build 174 | umgesetzt | `.github/workflows/build.yml:227`, `.github/workflows/build.yml:254`, `.github/workflows/build.yml:284` | – |
| E-102 | CI startet bei Änderungen unter `App/`, `Packages/`, Workflows und den Release-Tools; Tags starten nichts | R Building | teilweise | `.github/workflows/build.yml:5`, `.github/workflows/build.yml:6` | Die Pfadliste enthält zusätzlich `tools/xray_model/**`, das README nicht. Gebaut wird auf **jedem** Branch. |
| E-103 | „App aktualisieren“ vergleicht die installierte Build-Nummer mit dem Release | R Installation | teilweise | `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:152`, `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:156` | Entschieden wird zuerst über Commit-Gleichheit; die Build-Nummer dient nur dazu, einen neueren installierten Stand zu erkennen. Verglichen wird nur mit `main` – ein integ-Build meldet „neuer installiert“. |
| E-104 | Lizenzdateien: MIT für eigenen Code, `THIRD_PARTY_NOTICES.md`, Lizenzseite in der App | R License, CL Wave B | umgesetzt | `LICENSE:1`, `THIRD_PARTY_NOTICES.md` (1846 Zeilen), `App/Sources/Views/Settings/SystemSettings.swift:38` | – |
| E-105 | „Ein Build je Phase“ / Builds bündeln (Mac-Minuten) | S1 §3 [C], S2 §7, P2 Global Constraints | abgewichen | `.github/workflows/build.yml:5` | Build-Nummer 249 bei 319 Commits; gebaut wird bei jedem Push auf jedem Branch. Die Begründung (privates Repo, Minutenlimit) ist mit dem öffentlichen Repo entfallen – die offene Frage aus S1 §9 wurde nie im Dokument beantwortet. |
| E-106 | Im Plan genannte Hilfsmittel: `tools/atv_install.mjs`, `SITZUNG_UEBERGABE.md`, `mockups/widget-stile.html`, `mockups/prototyp.html` | P1 Task 9, P2 Tech Stack/Task 6, S1 §5 | vergessen | `ls tools` (nur `backfill_releases.sh`, `check_ipa.sh`, `logcollector.py`, `release_notes.sh`, `xray_model/`); kein `mockups/` | Liegen offenbar außerhalb des Repos; die Dokumente verweisen ins Leere. |

---

## 2. Zusammenfassung

| Status | Anzahl | IDs |
|---|---|---|
| umgesetzt | 71 | alle übrigen |
| teilweise | 11 | E-1, E-3, E-11, E-20, E-24, E-38, E-59, E-62, E-95, E-102, E-103 |
| abgewichen | 11 | E-2, E-6, E-15, E-16, E-30, E-32, E-35, E-36, E-42, E-57, E-105 |
| überholt | 8 | E-10, E-28, E-40, E-41, E-55, E-58, E-80, E-81 |
| vergessen | 4 | E-51, E-53, E-73, E-106 |
| nicht prüfbar | 1 | E-18 |
| **Summe** | **106** | (maschinell aus der Tabelle gezählt) |

Lesehilfe: Der Design-Umbau (S2/P2) ist nahezu vollständig und wortgetreu umgesetzt (32 Einträge: 28 umgesetzt, 2 überholt, 1 vergessen, 1 teilweise). Die Abweichungen sammeln sich in der Grund-Spec S1 – bei Sicherheit/Persistenz, Sprache, Ton und bei den Nicht-Zielen.

---

## 3. Wichtigste Abweichungen und Vergessenes

### A-1: Geheimnisse liegen im Profil-JSON statt in der Keychain; Export unverschlüsselt (E-15, E-16)
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:25`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:31`, `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:45`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:121`
- **Szenario:** Jemand im selben Netz kennt oder errät die Adresse der Handy-Seite samt `t=`-Parameter (steht in der URL, also in Browser-Verlauf und QR-Bild) → `GET /export` liefert alle Profile mit TMDB-/MDBList-/TorBox-Schlüsseln, Trakt-Client-Secret und Trakt-/Simkl-Tokens im Klartext über HTTP. Dieselben Werte liegen in UserDefaults und als Datei in Caches.
- **Ursache:** Spec verlangt Keychain + „encrypted/optional in the export“; gebaut wurde `apiKeys`/`syncTokens` als normale Profilfelder. S1 §7a widerspricht §5 bereits („also included in the export“).
- **Schweregrad:** hoch · **Sicherheit:** bestätigt (Speicherort und Export); plausibel (Angriffsweg im Heimnetz)
- **Fix-Idee:** Entweder die Spec ehrlich anpassen („bewusst im Profil, Gerät privat“) oder Tokens/Schlüssel in die Keychain legen und den Export mit Passwort verschlüsseln bzw. Geheimnisse abwählbar machen.
- **Test:** PlayerCore: Export eines Profils mit Schlüssel dekodieren und prüfen, dass kein Klartext-Schlüssel enthalten ist (heute rot).

### A-2: Direkte TorBox-Anbindung trotz Nicht-Ziel (E-42)
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Services/TorBox.swift:31`, `App/Sources/Views/TorBoxFilesRow.swift:96`
- **Szenario:** Die Spec schließt Login/Cache-Prüfung bei TorBox aus („everything goes through AIOStreams“). Heute gibt es einen eigenen API-Client, einen weiteren Schlüssel im Profil (und damit im Klartext-Export, siehe A-1), eine Bibliotheksreihe und Download-Fortschritt.
- **Ursache:** In Welle C als Feature ergänzt; das Nicht-Ziel wurde nie aufgehoben oder begründet.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Spec nachziehen (Nicht-Ziel streichen, Grund nennen) – der Code ist da und wird im README beworben.
- **Test:** Kein Codetest; Dokumentabgleich.

### A-3: „Oberfläche Deutsch und Englisch“ gibt es nicht (E-30)
- **Ort:** `App/Sources/AppModel.swift:346`, `App/Sources/Views/Settings/AppearanceSettings.swift:20`, `README.md:33`
- **Szenario:** Profil auf „en“ stellen → Titel und Beschreibungen kommen englisch von TMDB, jede Beschriftung der App (Tabs, Einstellungen, Dialoge, Player) bleibt deutsch.
- **Ursache:** `Profile.language` wird nur an TMDB und die Trailerwahl gereicht; es gibt keine Lokalisierungsdateien.
- **Schweregrad:** mittel (öffentliches README verspricht es) · **Sicherheit:** bestätigt
- **Fix-Idee:** README auf „Inhalte deutsch/englisch, Oberfläche deutsch“ korrigieren oder String-Katalog einführen.
- **Test:** Am Gerät: Sprache umstellen, Tableiste ansehen.

### A-4: Untertitel-Standard ist nicht „aus“ (E-32)
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:53`, `Packages/PlayerCore/Sources/PlayerCore/Playback/SubtitlePicker.swift:85`
- **Szenario:** Neues Profil, Film mit japanischer Tonspur → es erscheinen volle Untertitel, obwohl der Nutzer „standardmäßig aus“ entschieden hat ([U]).
- **Ursache:** Der Bool `subtitlesEnabled = false` wurde zu `SubtitleMode` mit Standard `.forcedOnly`; diese Stufe schaltet bei fremder Tonsprache volle Untertitel ein.
- **Schweregrad:** niedrig bis mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Im CHANGELOG/Spec als bewusste Änderung festhalten oder Standard auf `.off` setzen.
- **Test:** PlayerCore: `Profile.makeDefault().subtitleMode` und `SubtitlePicker` mit fremder Tonsprache.

### A-5: Direktes Bearbeiten der Startseite durch Menü + Verwalter ersetzt (E-57 bis E-59)
- **Ort:** `App/Sources/Views/Home/HomeRowMenu.swift:19`, `App/Sources/Views/Home/HomeManagerView.swift:12`
- **Szenario:** Der Kernschmerz der Spec war „Anordnen ist umständlich“, das Anti-Ziel „Menüs, viele Klicks je Schritt“. Heute: langer Druck → Menü → „Reihe bearbeiten“ → Verwalter-Seite → Aktion. Das ist genau die Menüform, die die [U]-Entscheidung „No menu per row“ ausschloss.
- **Ursache:** Welle F-b ersetzte den Greif-Modus; CL 144 beschreibt den Verwalter als Zugewinn, nicht als Ersatz einer Nutzerentscheidung.
- **Schweregrad:** mittel (betrifft das Hauptziel des Projekts) · **Sicherheit:** bestätigt (Code); ob es sich umständlicher anfühlt, nur am Gerät
- **Fix-Idee:** Mit dem Nutzer klären und die Spec nachziehen; „Ganz nach oben“ im Menü ist immerhin ein Ein-Klick-Weg.
- **Test:** Am Gerät: Klicks zählen für „Reihe drei Plätze nach oben“.

### A-6: TVDB und MDBList-Listen fehlen, werden aber angeboten bzw. beworben (E-51, E-53)
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:180`, `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift:8`, `README.md:25`
- **Szenario:** Nutzer trägt auf der Handy-Seite einen TVDB-Schlüssel ein → nichts ändert sich, Folgen kommen weiter in Addon-/TMDB-Ordnung. Nutzer will laut README eine MDBList-Liste als Reihe → es gibt keinen Weg.
- **Ursache:** Phase P5 (TVDB) und der MDBList-Teil von P2 wurden nie gebaut; Schlüsselfeld und README-Satz blieben.
- **Schweregrad:** niedrig bis mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** TVDB-Feld entfernen oder als „noch ohne Funktion“ kennzeichnen; README-Satz auf TMDB/Trakt kürzen.
- **Test:** `grep -rni tvdb` bzw. Fall in `SourceKind` suchen.

### A-7: Ton-Zusagen stimmen nicht mit dem Standard überein (E-35, E-36, E-38)
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Playback/AudioShapingSettings.swift:41`, `App/Sources/Views/Settings/DeviceCheckSettings.swift:53`, `App/Sources/Views/Settings/DeviceCheckSettings.swift:58`, `README.md:18`
- **Szenario:** README: „TrueHD and DTS-HD are decoded to multichannel PCM“ – der Standard wandelt in Dolby Digital Plus 5.1. In der App steht zugleich „bei FEL wird die Zusatzschicht verworfen“, während README und CL das Gegenteil zusagen. Drei Quellen, drei Aussagen.
- **Ursache:** README beschreibt die Option „verlustfrei“ als Normalfall; die Tabelle „Was spielt wie“ wurde nach dem FEL-Umbau nicht angepasst.
- **Schweregrad:** niedrig (Doku), aber irreführend bei der Fehlersuche · **Sicherheit:** bestätigt (Texte); Wirkung am Gerät nicht geprüft
- **Fix-Idee:** Eine Quelle der Wahrheit (die Tabelle in der App) aus den Geräte-Einstellungen ableiten und README daraus zitieren.
- **Test:** Am Gerät/Fern-Log: Zeile „ton: Ladeoptionen“ und Anzeige des Receivers.

### A-8: Schutzversprechen der Profildatei haben Lücken (E-12, E-14, E-20)
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:36`, `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:55`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:68`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:91`
- **Szenario 1:** Eine Sicherung aus einem künftigen Build mit `schemaVersion` 2 liegt im Speicher, ein älterer Build startet → `decode` wirft, `load()` legt `.bak` an und startet mit dem Standardprofil; die nächste Änderung überschreibt `profiles.json`. Die `.bak` liegt nur als Datei, bei nicht beschreibbarem Application Support nur in Caches.
- **Szenario 2:** Profile wachsen komprimiert über 512 KB (viele importierte Collections) → Eintrag in UserDefaults wird gelöscht, es bleibt nur die Datei; auf einem Gerät ohne beschreibbares Application Support ist das genau der Zustand „nur im Cache“, den CL Wave A ausschließt.
- **Ursache:** Feste Grenzen ohne harte Sperre; `currentSchema` wurde nie erhöht, es gibt also keinen erprobten Migrationsweg.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (Codepfad), plausibel (Eintreten am Gerät)
- **Fix-Idee:** `.bak` mit Zeitstempel und zusätzlich in UserDefaults, solange Platz ist; bei „nur Datei“ sichtbare Warnung statt nur Logzeile.
- **Test:** PlayerCore: `TieredBlobStorage` mit `writeDirectories` nur „Caches“ und Profil > `profileLimit`.

### A-9: Engine-Kapselung dünner als entschieden (E-2, E-3, E-6)
- **Ort:** `App/Sources/Views/PlayerScreen.swift:37`, `App/Sources/Views/Player/XRayProbeHook.swift:46`, `App/project.yml:47`
- **Szenario:** Ein zweites Backend (Ansatz B der Spec) müsste 13 Dateien mit `import AetherFEL`, mehrere `extension AetherBackend` in View-Dateien und statische Aufrufe ersetzen – „ohne App-Umbau“ gilt nicht mehr. Dazu: kein eigenes Paket, App im Swift-5-Modus.
- **Ursache:** Protokoll existiert, aber Erweiterungen (Scrub, Lade-Schritte, Bildmodus, X-Ray) wurden direkt am konkreten Typ gebaut.
- **Schweregrad:** niedrig (solange kein zweites Backend geplant ist) · **Sicherheit:** bestätigt
- **Fix-Idee:** Spec-Satz streichen oder die Erweiterungen als Protokollanforderungen mit Standardumsetzung führen (teils schon so gemacht).
- **Test:** `grep -rln 'import AetherFEL' App/Sources | wc -l` als Kennzahl.

---

## 4. Widersprüche zwischen den Dokumenten und veraltete Stellen

| Nr. | Stelle A | Stelle B | Was gilt im Code |
|---|---|---|---|
| W-1 | S1 §2 Nicht-Ziel „Atmos … bitstream passthrough“ | R Features: „5.1 and Atmos as passthrough“ | Passthrough ist Standard (`DeviceCheckSettings.swift:57`). S1 veraltet. |
| W-2 | S1 §2 Nicht-Ziel „Direct TorBox integration“ | R Features (2. Punkt), CL Wave C/D | TorBox-Client vorhanden. S1 veraltet. |
| W-3 | S1 §5 „Secrets … in the Keychain, encrypted/optional in the export“ | S1 §7a „Tokens are in the Keychain and are also included in the export“; P1 Task 2 `apiKeys` im Profil | Weder Keychain noch Verschlüsselung. S1 widerspricht sich selbst und dem eigenen Plan. |
| W-4 | S1 §5 „Codable JSON per profile in Application Support“ | P1 Task 3 „File `profiles.json`“ (eine Datei); CL 0.2.0 „kept in UserDefaults … tvOS does not allow writing to Application Support“ | UserDefaults + Dateien (Application Support wird trotzdem probiert: `DefaultsStorage.swift:18`). S1 und P1 veraltet; CL 0.2.0 ist seit Wave A selbst unvollständig. |
| W-5 | S1 §2 „app German/English, switchable per profile“ | P2 Global Constraints „The interface is in German“; R „interface is available in German and English“ | Oberfläche nur deutsch. README falsch. |
| W-6 | S1 §2 / P1 „subtitles off by default“ | CL Wave A „automatic selection“ | Standard `.forcedOnly`. S1/P1 veraltet, CL ungenau. |
| W-7 | S1 §7a / P1 „AIOStreams order is kept … `Ranking` stays small“ | CL Wave C „Ordering takes language, AV1 support and TorBox into account“; CL 144 „addon's order is the default, Smart can be selected“ | Beides: Anzeige wie Addon, Automatik nach App-Ordnung. S1/P1 veraltet. |
| W-8 | S2 §2.6 „series from continue watching/watchlist/**history**“ | S2 §7a.3 und P2 Task 5 „continue watching and the watchlist“ | Ohne Verlauf (`AppModel+Upcoming.swift:27`). §2.6 ist die veraltete Stelle. |
| W-9 | S2 §2.3 / P2 Task 2 „7 categories … Über“ | CL 144 „seven categories“ (andere sieben), CL 249 „three groups plus System“ | 9 Kategorien (`SettingsTree.swift:10`). S2/P2 veraltet. |
| W-10 | S1 §2 „No menu per row“ [U] | CL 144 Kontextmenü/Verwalter, CL 249 „Long-press menu on every poster and tile … row actions follow in the same menu“ | Menü. S1 veraltet, Entscheidung nie formell geändert. |
| W-11 | S1 §5 / P1 `Packages/PlaybackKit`, `PlayerEngine` | R Structure (nennt nur `PlayerCore`, `AetherFEL`) | Kein PlaybackKit. S1/P1 veraltet. |
| W-12 | R Features „TrueHD and DTS-HD are decoded to multichannel PCM“ | In-App-Tabelle: „in Dolby Digital Plus 5.1 umgewandelt“ | DD+ 5.1 als Standard. README ungenau. |
| W-13 | R/CL 108 „for FEL titles the enhancement layer is applied“ | In-App-Tabelle: „bei FEL wird die Zusatzschicht verworfen“ (`DeviceCheckSettings.swift:53`) | Trait aktiv; App-Text veraltet. |
| W-14 | R „`main` currently contains version 0.4.0 … stages from Wave A onwards are still on `integ`“ | CL: Builds 144–249 alle „(integ)“; `App/project.yml:33` weiter „0.4.0“ | Stimmt formal, zeigt aber: 9 veröffentlichte integ-Builds und ein Großteil der Funktionen tragen dieselbe Versionsnummer wie `main`; kein Stand wurde seit 0.4.0 als „am Gerät geprüft“ nach `main` gebracht. |
| W-15 | R „Each profile is self-contained … settings“ | CL 249 „Bild & Ton … stored per device instead of per profile“ | Je Gerät. README veraltet. |
| W-16 | S1 §3 „private repo … bundle builds“; S1 §9 [OPEN] öffentlich/privat | S2 §3, P2 „Public repo“; R „source code is public“ | Öffentlich. S1 §3/§9 nie geschlossen; ebenso [OPEN] App-Name, Pakete, Schlüssel. |
| W-17 | S2 §3 / P2 „Public repo: no keys, names, IPs“ | P2 Global Constraints nennt in derselben Liste die Commit-Identität; S1 §3/§7a nennen Kontokennung und Bundle-ID | Die Regel wird vom Dokument verletzt, das sie aufstellt. |
| W-18 | P1 Tech Stack „Swift 6“ / P2 „Swift 6.2“ | `App/project.yml:47` | App im Swift-5-Sprachmodus. |
| W-19 | CL-Kopf: „Sections are ordered by stage … Wave A … Wave D“ | Code-Kommentare und Commits nennen Wellen E, F (0, a–p), G, L, P, Q, S, U, W, X | Ab Build 144 führt das CHANGELOG nur noch Build-Abschnitte; die Wellenbezeichnungen ab E sind außerhalb von Code-Kommentaren nirgends erklärt. |
| W-20 | P2 Task 6 „SITZUNG_UEBERGABE.md“, P1 Task 9 „tools/atv_install.mjs“, S1 §5 „mockups/…“ | Repo-Inhalt | Dateien fehlen im Repo (E-106). |

Zusätzlich veraltet: Der Statuskopf von S1 („**Not yet approved by the user.**“) wurde nie aktualisiert, obwohl darauf rund 320 Commits aufbauen; die [C]-Entscheidungen gelten laut Dokument als „korrigierbar“ und sind formal nie bestätigt worden.

---

## 4a. Beobachtungen zum Planungsprozess aus Git (`origin/integ`)

Zahlen aus `git log origin/integ` (Betreffzeilen, automatisch per Muster gezählt; Überschneidungen zwischen Kategorien sind möglich).

**Umfang und Takt**
- 319 Commits, davon 68 Merges und 251 inhaltliche Commits.
- Zeitstempel: erster Commit 21.11. 10:02, letzter 22.11. 23:28 – rund 37,5 Stunden. Spitzen: 24 Commits in einer Stunde (21.11., 16 Uhr), 30 in einer Stunde (22.11., 22 Uhr).
- 67 Remote-Branches, überwiegend ein Branch je Teilwelle (`welle-a-a` … `welle-x2`).
- Build-Nummer 249 bei 319 Commits: Die CI lief im Schnitt bei etwa vier von fünf Commits (alle Branches zusammen). Veröffentlicht wurden 9 Releases (`build-144` bis `build-249`); `main` steht laut README bei 0.4.0 (Builds 12–39).

**Nachbesserungen**
- 92 der 251 inhaltlichen Commits (37 %) tragen im Betreff ein Nachbesserungs-Merkmal: „Nachbesserung/Nacharbeit/Nachtrag/Feinschliff“ (36), „Fix-Runde/Runde N/round N/Review“ (58), reine Bau-Reparaturen wie „CI-Fix“, „baut wieder“ (7).
- Typische Ketten direkt nach dem Feature-Commit:
  - Plattencache: 1 Feature-Commit, dann Fix-Runde 1, 2, 3, Merge, zwei „Nacharbeiten“ – 14 Commits mit dem Wort im Betreff, alle innerhalb von rund 100 Minuten.
  - Log-Schwärzung: Feature, Fix-Runde 1, Nachtrag 1, 2, 3 – 5 Commits in 51 Minuten.
  - Poster-Reihen (Aufklappen, Anker, Wackeln): mindestens 9 Commits über beide Tage (7c20576, b92fd6a, f9dbed6, ed6e769, b5c1f5d, 6f50215, 508fb54, 67275a2, 05c9c71); der geplante `scrollPosition`-Anker wurde am Ende wieder entfernt.
  - Obere Menüleiste nach dem Player: 5 Commits über die Builds 187, 214 und 249 (b3c55b5, e0a2099, bc8181e, 7d7e69d, a1d8238) – genau das in S2 §2 genannte Anti-Ziel „Fokus springt/hängt“ und Risiko §9.
  - Spur-Panel im Player: 7 Commits mit zwei vollständigen Umbauten (Reiter-Blatt → schmale Leiste oben → drei wählbare Stile).
  - „Kein Systemblau“: in 4 Betreffzeilen an zwei Tagen (abcb6e1, 23cc41e, 90cdafc, a704801).
- Einordnung: Der größere Teil der 58 „Runde/Review“-Commits verweist auf Befundnummern (I1, M1–M12, N1 …), also auf Code-Review-Runden ohne Gerät. Geräte-Schleifen sind dort erkennbar, wo dasselbe sichtbare Symptom über mehrere veröffentlichte Builds wiederkehrt (Menüleiste, Poster-Fokus, Blau, Spur-Panel). Sechs Commits reparieren nur den Build (z. B. zweimal dieselbe auf tvOS nicht verfügbare SwiftUI-Funktion: 243399b und 657a4a1).

**Commits je Thema (Betreff-Treffer)**
- Welle F (Oberfläche, Startseite, Einstellungen, Navigation): 45 – größter Block.
- Welle C: 14 · Plattencache: 14 · Player-0 bis Player-4 samt Integration: 14 · X-Ray: 14 · FEL: 13 · Welle B: 11 · Welle D: 10 · Welle E: 10 · Welle G: 9 · Welle A: 7 · Spur-Panel: 7 · Menüleiste: 6.

**Specs und Pläne**
- Im Repo liegen genau 4 Planungsdokumente (2 Specs, 2 Pläne). Sie decken Commits 1–3 (Grundgerüst) und den Design-Umbau ab – zusammen etwa die ersten 55 Commits bis Build 39.
- Nur 7 Commits berühren `docs/` überhaupt; die letzten beiden sind eine Wortlaut-Korrektur und die Übersetzung ins Englische. Kein Spec-Inhalt wurde nach dem 21.11., 13:24 Uhr fachlich geändert.
- Für die Wellen A bis G und L, P, Q, S, U, W, X (rund 265 Commits, über 80 % der Historie) gibt es im Repo keine Spec und keinen Plan. Es existieren aber welche außerhalb: Code-Kommentare und Commits verweisen auf „Plan §6.4“ (`App/Sources/PlayerApp.swift:135`), „Plan R6/N8“ (`App/Sources/Views/Home/HomeRowMenu.swift:4`), „§3.3“, „§4.5“, „Review F-c I2“, „Pfad im Plan“ (Commit 1fc288e). Diese Verweise sind für Außenstehende nicht auflösbar.
- Das CHANGELOG ist damit die einzige nachgeführte Entscheidungsquelle (63 Commits berühren es, 7 das README). Es dokumentiert neue Funktionen gut, hält aber nicht fest, welche frühere Entscheidung eine Funktion ablöst – deshalb sind in Abschnitt 1 elf Einträge „abgewichen“ statt „überholt“.
- Nicht-Ziele wurden in keinem Fall formell aufgehoben. Drei sind gefallen oder umgekehrt (TorBox-Anbindung, Atmos-Passthrough, „kein Menü pro Reihe“), eines ist vorbereitet (Video im Hero), eines aufgeweicht (Quellenlisten-Darstellung).
- Größter ungeplanter Zuwachs gemessen an den vier Dokumenten: X-Ray-Gesichtserkennung (14 Commits, eigenes Core-ML-Modell in der CI), Fokus-Videos mit Ton auf Kacheln, Plattencache-Proxy, App-Update über atvloadly, Fern-Log, TorBox-Bibliothek, Sync-Warteschlange, Seitenpanel und Pausenkarte im Player. Keines davon steht in einer Spec im Repo.

---

## 5. Tragende Grundentscheidungen im ADR-Stil

Methodik: Skill `engineering:architecture`. Jede Entscheidung nennt Kontext, Entscheidung, Folgen, Bewertung heute und
eine Empfehlung (behalten / anpassen / ersetzen). Umbau-Empfehlungen nennen Nutzen, Risiko, Aufwand (S/M/L) und einen
Migrationspfad, der bestehende Profile erhält. Die Befund-IDs verweisen auf [02](02-bugs.md), [05](05-code-review.md),
[06](06-security-review.md) und [07](07-design-analyse.md).

### ADR-1: Aufteilung App ↔ `PlayerCore`

- **Status:** angenommen, gelebt · **Empfehlung: behalten und die Grenze nachziehen**
- **Kontext:** Kein Mac, kein Simulator. Was unter Linux testbar ist, kostet 2 Minuten; alles andere 15 bis 20 Minuten
  je Versuch am Gerät.
- **Entscheidung (Spec §5):** Plattformunabhängige Logik in `Packages/PlayerCore` (nur Foundation), App als SwiftUI-Hülle,
  Engine hinter einem eigenen Paket `PlaybackKit`.
- **Folgen heute:** `PlayerCore` hat 132 Dateien, 20 000 Zeilen, 965 Tests, keine Singletons, Swift 6. Das ist die
  stärkste Entscheidung des Projekts. Zwei Abweichungen: `PlaybackKit` gibt es nicht (13 App-Dateien importieren
  `AetherFEL` direkt, E-2/E-3), und die **Ablauflogik** ist in der App geblieben: Rückfall auf die nächste Quelle,
  Autoplay, Up-next-Zeiten, Fokus-Entscheidungen, Fortsetzen (Q-3, Q-21).
- **Bewertung:** Die Bugs der Stufe 2 liegen fast alle auf der App-Seite der Grenze, also dort, wo kein Test hinkommt.
  Die Regeln selbst (`PlaybackRecovery`, `SkipPolicy`, `HomeTopEdge`) sind getestet und unauffällig. Das belegt den
  Nutzen der Grenze und zeigt, wo sie zu früh endet.
- **Empfehlung:**
  1. Regel festschreiben: „Jede Entscheidung, die sich als Funktion *Zustand + Ereignis → nächster Schritt* schreiben
     lässt, gehört nach `PlayerCore`.“ Die App führt nur aus.
  2. Drei Zustandsautomaten nachziehen: `PlaybackQueue` (Quellenwahl, Rückfall, nächste Folge), `UpNextPolicy`,
     `PlayerLocks` (welche Eingabe ist gerade gesperrt).
  3. `PlaybackKit` **nicht** nachbauen. Den Spec-Satz streichen. Ein zweites Backend ist nicht geplant; die Kapselung
     hätte heute nur Kosten.
- **Nutzen:** Wiedergabe-Abläufe ohne Gerät prüfbar; die Befunde W-A-1, W-A-3, F-B-1, W-B-2 wären als Tests
  formulierbar gewesen. **Risiko:** mittel, weil der Player angefasst wird. **Aufwand:** L, in drei Schritten.
- **Migrationspfad:** (1) Regel als reine Funktion mit Tests in `PlayerCore` anlegen, noch ohne Aufrufer. (2) Die View
  ruft die Regel auf und loggt nur, wenn ihr eigenes Ergebnis abweicht (ein Build im „Schattenbetrieb“). (3) Die View
  folgt der Regel, der alte Zweig entfällt. Profile sind nicht betroffen.

### ADR-2: `AppModel` als zentrales Modell, State-Management

- **Status:** angenommen, gewachsen · **Empfehlung: anpassen (schrittweise zerlegen, auf Observation umstellen)**
- **Kontext:** Ein Entwickler, schnelle Wellen. Ein zentrales `@MainActor`-Objekt ist der einfachste Weg, alles
  erreichbar zu machen.
- **Entscheidung (Plan P1, Task 9):** `AppModel` als `ObservableObject`, als `environmentObject` in alle Views.
- **Folgen heute:** 1 915 Zeilen in 14 Dateien, 31 gespeicherte Eigenschaften, 20 Erweiterungen (vier davon in
  View-Dateien), 70 Beobachter in 43 Dateien, dazu 19 Singletons mit eigenem Zustand. `ObservableObject` meldet jede
  Änderung an alle Beobachter: Jedes Fortschritts-Speichern (alle 10 s) und jede Katalog-Erneuerung wertet alle
  aufgebauten Karten neu aus. Der Profilwechsel leert zwölf Stellen von Hand; was fehlt, leckt zwischen Profilen
  (S-3, S-4, A-A-8, A-B-2).
- **Bewertung:** Für den Start richtig, heute die größte Quelle von Kopplung. Das Problem ist weniger die Größe als
  das Fehlen zweier Konzepte: feldgenaue Beobachtung und eine Profil-Epoche.
- **Empfehlung:**
  1. `@Observable` statt `ObservableObject` (tvOS 18 ist Mindestziel). Wirkung ohne weiteren Umbau: Views hängen nur
     noch an den Feldern, die sie lesen.
  2. `ProfileScope` einführen: eine Epoche, die bei Profilwechsel, Sicherungs-Import und Addon-Änderung steigt. Jede
     profilbezogene Aufgabe merkt sich die Epoche und verwirft ihr Ergebnis, wenn sie nicht mehr gilt.
  3. Dienste herausziehen, in dieser Reihenfolge nach Nutzen: `ProgressService` (mit Scrobble und Sync),
     `StreamService`, `CatalogService`, `ProfileService`, `MetaService`. `AppModel` bleibt als Fassade, die an die
     Dienste weiterreicht, bis die letzte View umgestellt ist.
- **Nutzen:** weniger Ruckeln bei Fokuswechseln (messbar über den `hitch`-Zähler), Profil-Lecks strukturell
  ausgeschlossen. **Risiko:** `@Observable` ändert, *wann* Views neu rechnen; ein versehentlich nicht mehr
  beobachtetes Feld zeigt veraltete Daten. **Aufwand:** M für 1 und 2, L für 3.
- **Migrationspfad:** Schritt 1 in einem eigenen Build ohne weitere Änderung, mit Testprotokoll „jede Seite reagiert
  noch auf Änderungen“. Schritt 2 danach, je Dienst ein Build-Bündel. Persistenz bleibt unberührt, weil `save()`
  weiter das ganze `StoredProfiles` schreibt.

### ADR-3: XcodeGen, Bauen nur in CI, unsignierte IPA, atvloadly als Update-Weg

- **Status:** angenommen · **Empfehlung: behalten, Kette absichern und Tests einhängen**
- **Kontext:** Kein Mac, kein Entwicklerkonto, kostenlose Apple-ID mit 7-Tage-Signatur.
- **Entscheidung:** Projekt aus `App/project.yml`, Build auf GitHub-Runnern, unsignierte IPA als Release, Signatur und
  Installation durch atvloadly im Heimnetz; die App stößt die Neuinstallation selbst an.
- **Folgen heute:** Der Weg funktioniert und ist gut automatisiert (gepinnte Actions, IPA-Inhaltsprüfung,
  FEL-Trait-Wächter, Geheimnis-Scan des IPA). Schwächen: **Die 965 Tests laufen nicht in CI** (Q-22); die App wird im
  Swift-5-Modus gebaut (Q-12); das Installationspaket hat weder Hash noch Signatur, und die App spricht atvloadly über
  HTTP ohne Anmeldung an (SEC-3, SEC-7); Engine und XcodeGen sind nicht auf Hashes festgelegt (SEC-15).
- **Bewertung:** Die Entscheidung ist unter den Rahmenbedingungen ohne Alternative. Die Lücken sind billig zu schließen.
- **Empfehlung (Reihenfolge):**
  1. Job `test` (Linux-Container, `swift test`), `build` und `release` hängen davon ab. Aufwand S.
  2. SHA-256 der IPA in den Release-Text; die App prüft Build, Commit und Hash, bevor sie atvloadly beauftragt. Aufwand M.
  3. Bestätigung am Fernseher mit Anzeige von Build und Commit vor jeder Installation; atvloadly-Adresse nie ohne
     Rückfrage aus der Bonjour-Suche übernehmen (SEC-11). Aufwand S.
  4. `Package.resolved` einchecken, XcodeGen als festes Archiv mit Prüfsumme. Aufwand S.
  5. `SWIFT_STRICT_CONCURRENCY: complete` zunächst als Warnungen, später `SWIFT_VERSION: "6.0"`. Aufwand L, verteilt.
- **Risiko:** gering; Punkt 2 braucht einen Build Vorlauf, in dem das Release den Hash schon trägt, die App ihn aber
  noch nicht verlangt. Profile sind nicht betroffen.

### ADR-4: Persistenzmodell und Migrationen

- **Status:** angenommen, abgewichen · **Empfehlung: anpassen (Schutz der Profile zuerst, Geheimnisse trennen)**
- **Kontext:** Spec: „Codable-JSON pro Profil in Application Support, Schema-Version, atomar; Geheimnisse in der
  Keychain.“ tvOS erlaubt kein verlässliches Schreiben nach Application Support, Caches darf das System löschen.
- **Entscheidung, wie gebaut:** ein Block `profiles.json` mit **allen** Profilen in UserDefaults (LZFSE, Vorbehalt
  512 KB) plus Dateikopien; Schlüssel und OAuth-Tokens stehen im selben JSON; `schemaVersion` ist 1 und wurde nie
  erhöht; Migration geschieht über `decodeIfPresent` mit Standardwerten.
- **Folgen heute:**
  - **Gut:** Die gestufte Ablage ist durchdacht und getestet; alte Profile laden (Fixture-Test).
  - **Datenverlust-Pfad:** Lässt sich `profiles.json` nicht dekodieren, startet die App mit einem Standardprofil, und
    das nächste Speichern überschreibt alle Profile. Die `.bak` liegt nur als Datei und wird nie zurückgelesen (S-1).
    Build 249 liest alles, was er selbst schreibt; der Auslöser ist ein Rückschritt auf einen älteren Build oder eine
    Sicherung aus einem neueren: Dann genügt ein unbekannter Enum-Wert in *einem* Profil (S-2, D-1). Genau dieser
    Fall tritt ein, sobald neue Aussehens-Optionen ausgeliefert werden.
  - **Geheimnisse:** im Klartext in UserDefaults, in Dateien unter Caches, im Export (SEC-14, E-15/E-16).
  - **Wachstum:** Fortschritt und verwaiste Blöcke können das UserDefaults-Budget sprengen; dann liegt der Stand nur
    noch unter Caches (S-9, S-10).
  - **Sicherung unvollständig:** Fortschritt, Fusion-Kit-Auswahl und Geräte-Einstellungen fehlen; das Einspielen
    löscht Kit-Reihen (S-12, A-B-1).
- **Bewertung:** Das Modell „ein JSON-Block“ trägt für diese App-Größe. Falsch ist die Fehlerbehandlung darum herum:
  *Lesen darf nie zum Überschreiben führen*, und Dekodierung darf an keiner Stelle wegen eines einzelnen Werts scheitern.
- **Empfehlung:**
  1. **Nie überschreiben, was nicht gelesen wurde.** Scheitert `load()`, geht die App in einen Zustand „Profile nicht
     lesbar“ mit drei Wegen: erneut versuchen, `.bak` bzw. letzte gute Fassung laden, bewusst neu anfangen. Bis zur
     Entscheidung wird nicht gespeichert. Zusätzlich hält die Ablage die letzten zwei guten Fassungen
     (`profiles.json.1`, `.2`) in UserDefaults, solange das Budget reicht. Aufwand M.
  2. **Dekodierung je Profil und je Feld nachsichtig.** `StoredProfiles` dekodiert Profile einzeln; ein kaputtes Profil
     wird übersprungen und gemeldet, die anderen laden. Alle Enums über `decodeLenient`. Aufwand S.
  3. **`schemaVersion` ernst nehmen.** Höhere Version: lesen, was bekannt ist, und beim Speichern unbekannte Felder
     erhalten (rohes JSON je Profil mitführen) oder das Speichern verweigern. Aufwand M.
  4. **Geheimnisse in die Keychain** (`SecretStore`), Profil hält nur noch Namen. Export standardmäßig ohne
     Geheimnisse. Aufwand M.
  5. **Sicherung vollständig machen:** Fortschritt, Kit-Auswahl, Collection-Links, Geräte-Einstellungen. Aufwand M.
- **Nutzen:** schließt das Anti-Ziel „Profile gehen verloren“ strukturell. **Risiko:** hoch, weil genau der Code
  angefasst wird, der die Profile hält; deshalb zuerst Tests mit echten alten Fixtures.
- **Migrationspfad, der Profile erhält:**
  1. Build A: nur lesende Härtung (Punkte 1 und 2) plus Fixtures aus jedem bisher veröffentlichten Build. Kein neues
     Format.
  2. Build B: Keychain. Beim ersten Start werden Schlüssel und Tokens in die Keychain kopiert, **bleiben aber noch im
     Profil** (doppelte Buchführung, gelesen wird aus der Keychain, bei Fehlen aus dem Profil).
  3. Build C: Schreiben ins Profil endet, `schemaVersion = 2`. Ein Zurückgehen auf Build B funktioniert noch, weil B
     die Keychain kennt. Der Export bietet „mit Geheimnissen“ nur nach Bestätigung am Fernseher an.
  4. Die 7-Tage-Neusignatur über atvloadly behält Bundle-ID und damit Keychain-Einträge (abgeleitet; **am Gerät
     prüfen**, bevor Build C erscheint).

### ADR-5: Eigener Webserver für die Handy-Eingabe

- **Status:** angenommen · **Empfehlung: behalten, aber das Sicherheitsmodell ersetzen**
- **Kontext:** Anti-Ziel der Spec: „lange URLs und Schlüssel mit der Fernbedienung tippen“. tvOS hat keinen Browser
  und keine Zwischenablage vom Handy außer der Systemtastatur.
- **Entscheidung:** `NWListener` auf Port 8765, HTML-Seite aus `PlayerCore`, QR-Code mit Adresse und Token.
- **Folgen heute:** Die Bedienung ist sehr gut gelöst und in `PlayerCore` getestet (Parser, Seite, Schnell-Import).
  Sicherheit: Klartext-HTTP; ein 10-Zeichen-Token in der URL ist das einzige Geheimnis und gibt **alles** frei:
  `GET /export` liefert sämtliche Schlüssel und Tokens, `backup_json` ersetzt alle Profile, beides ohne Rückfrage am
  Fernseher (SEC-1). Der Server puffert bis 8 MB je Verbindung vor der Token-Prüfung (SEC-5). Positiv: Der Server
  läuft nur, solange die Seite offen ist; kein XSS, kein CSRF ohne Token gefunden.
- **Bewertung:** Der Weg ist richtig, das Modell „wer das Token kennt, darf alles“ ist es unter dem Bedrohungsmodell
  nicht. TLS scheidet aus: ein selbst signiertes Zertifikat akzeptiert kein Handy-Browser ohne Warnung. Auch
  WebCrypto scheidet aus, weil Browser `crypto.subtle` nur in sicheren Kontexten anbieten, also nicht auf `http://`.
- **Empfehlung (zwei Stufen):**
  1. **Stufe 1 (Aufwand M, schließt den größten Teil):**
     - Der Fernseher ist die Vertrauensinstanz: Export mit Geheimnissen, Wiederherstellung, Addon-Änderungen und
       Schlüssel-Änderungen werden am Fernseher angezeigt und mit der Fernbedienung bestätigt.
     - Export standardmäßig **ohne** Geheimnisse.
     - Sitzung an das erste Gerät binden (Cookie nach dem ersten gültigen Aufruf, danach ist das URL-Token verbraucht);
       ein zweites Gerät braucht einen neuen QR-Code.
     - Token-Prüfung vor dem Lesen des Körpers, Limits für Verbindungen, Zeit und Größe.
  2. **Stufe 2 (Aufwand M):** Geheimnisse verlassen das Gerät nicht mehr im Klartext. Der Export wird auf dem
     Apple TV mit CryptoKit verschlüsselt; den Code dafür zeigt der Fernseher an, das Handy sieht nur die
     verschlüsselte Datei. Schlüssel und Tokens lassen sich zusätzlich über ein tvOS-Textfeld mit der
     iPhone-Tastatur eingeben (diese Strecke verschlüsselt Apple). Das Sitzungs-Token bekommt ein Ablaufdatum.
  3. **Stufe 3 (optional, Aufwand L):** Verschlüsselung der Formulardaten auf Anwendungsebene mit einem Schlüssel im
     URL-Fragment und einer mitgelieferten JavaScript-Routine. Nur nötig, wenn Addon-Adressen mit eingebetteten
     Zugangsdaten weiter über die Handy-Seite eingetragen werden sollen.
- **Risiko:** Stufe 1 verändert den Ablauf für den Nutzer um genau einen Druck auf der Fernbedienung bei heiklen
  Aktionen. **Migration:** keine Datenmigration; alte QR-Codes sind ohnehin Einmal-Adressen.

### ADR-6: Fern-Log als Diagnoseweg

- **Status:** angenommen · **Empfehlung: behalten und ausbauen, aber standardmäßig aus und mit festem Empfänger**
- **Kontext:** Ohne Xcode gibt es keine Konsole. Das Fern-Log ist das einzige Fenster ins laufende Gerät.
- **Entscheidung:** `RemoteLog` sucht per Bonjour nach `_playerlog._tcp` und sendet alle 5 s gepufferte Zeilen per
  HTTP an den **ersten** Treffer; `LogRedact` schwärzt Schlüssel und Adressen.
- **Folgen heute:** Der Weg hat die Entwicklung getragen (Messzeilen wie „Plaketten nach … ms“ sind vorhanden).
  Aber: Das Log ist immer an, und jedes Gerät im WLAN kann sich als Empfänger ankündigen und erhält Titel, IMDb-IDs,
  Hostnamen und Fehlertexte (SEC-2). `LogRedact` hat Lücken (SEC-8). Es gibt keinen Verlauf auf dem Gerät: Was vor
  dem Start des Empfängers geschah, ist nach 500 Zeilen verloren.
- **Bewertung:** Das wichtigste Werkzeug des Projekts, mit dem schwächsten Vertrauensmodell.
- **Empfehlung:**
  1. Standard aus; Einschalten am Fernseher zeigt den gefundenen Empfänger mit Namen und merkt ihn sich.
  2. Gemeinsames Geheimnis (über die Handy-Seite gesetzt), Zeilen per HMAC signiert; `logcollector.py` prüft es.
  3. **Ringpuffer auf dem Gerät** (z. B. 2 000 Zeilen in Caches) und eine Seite „Diagnose“ in den Einstellungen, die
     die letzten Fehler zeigt und das Log über die Handy-Seite abrufbar macht. Das verkürzt Geräte-Schleifen, weil ein
     Fehler nicht mehr mit laufendem Empfänger nachgestellt werden muss.
  4. Messpunkte als eigene Klasse `metric:` mit festen Namen (Liste in [04 §6](04-system-design.md)), damit sich
     Builds vergleichen lassen.
- **Aufwand:** S für 1, M für 2 bis 4. **Risiko:** gering. Keine Profilmigration.

### ADR-7: Ranking und Auswahl der Quellen

- **Status:** angenommen, erweitert · **Empfehlung: behalten, Parser härten, eine Wahrheit je Stream**
- **Kontext:** Spec: „Die Reihenfolge von AIOStreams bleibt, `Ranking` bleibt klein.“ Später kamen TorBox-Cache,
  „Beste Wahl“, Dubletten-Ausblendung, Release-Abgleich für die nächste Folge und die Option „Smart (App)“ dazu.
- **Entscheidung, wie gebaut:** Anzeige in Addon-Reihenfolge (Standard) oder „Smart“; automatische Wahl immer nach
  App-Rangfolge; Merkmale aus dem Freitext der Addons (`StreamTraits.parse`).
- **Folgen heute:** Die Trennung „Anzeige wie das Addon, Automatik nach eigener Regel“ ist eine gute Auflösung des
  Widerspruchs zur Spec. Die Regeln liegen in `PlayerCore` und sind gut getestet. Schwächen liegen im Parser, weil
  alles auf Freitext beruht: „UHD“ im Namen macht 1080p zu 4K (A-A-1), „5.1 GB“ wird als Tonkanäle gelesen (A-A-2),
  eine lange Ziffernfolge vor „GB“ bringt die App zum Absturz (A-A-3), Kommentarspuren gewinnen die Tonwahl (W-A-2).
  `parse` läuft je Quelle bis zu sechsmal auf dem Main-Thread.
- **Bewertung:** Fachlich richtig, technisch an einer Stelle fragil.
- **Empfehlung:**
  1. `StreamTraits` einmal je Stream berechnen und als Wert mitführen (`RankedStream`), statt an sechs Stellen neu zu
     parsen.
  2. Strukturierte Felder vor Freitext: AIOStreams liefert Auflösung, Größe und Cache-Status als eigene Felder; der
     Freitext ist nur noch Rückfall.
  3. Parser mit einer Tabelle echter Addon-Zeilen als Test (`@Test(arguments:)`), dazu ein Fuzz-Test „wirft nie,
     stürzt nie ab“ für beliebige Zeichenketten.
  4. Addons über ihre Manifest-ID unterscheiden, nicht über den Anzeigenamen (A-A-9).
- **Aufwand:** M. **Risiko:** gering, weil die Regeln schon in `PlayerCore` liegen. Keine Profilmigration.

---

## 6. Bewertung des Planungsprozesses

Zahlen aus der Git-Historie (Abschnitt 4 oben): 319 Commits in rund 37,5 Stunden, 249 CI-Läufe, 9 Releases; 37 % der
inhaltlichen Commits sind Nachbesserungen; vier Planungsdokumente decken etwa die ersten 55 Commits ab, über 80 % der
Historie haben keine Spec im Repo.

**Was gut funktioniert hat**

- Die beiden vorhandenen Specs sind konkret und prüfbar. Der Design-Umbau wurde zu 28 von 32 Punkten wortgetreu gebaut.
- Die Regel „testbare Logik nach `PlayerCore`“ wurde durchgehalten: 965 Tests, darunter für heikle Dinge wie
  `HomeTopEdge` und `FocusHeadroom`.
- Der Plan nennt je Task „Am Gerät prüfen“ und erwartete Log-Zeilen. Das ist genau die richtige Form für teure
  Gerätetests.
- Code-Review-Runden ohne Gerät (Befundnummern in den Commits) haben viel abgefangen.

**Was nicht funktioniert hat**

1. **Specs wurden nach dem ersten Tag nicht mehr gepflegt.** Nicht-Ziele wurden gebaut, ohne sie aufzuheben
   (TorBox, Atmos-Passthrough, Menü je Reihe). Der Spec-Kopf sagt bis heute „noch nicht vom Nutzer freigegeben“.
   README, CHANGELOG, Spec und die Tabelle in der App widersprechen sich an 20 Stellen.
2. **Die teuerste Prüfung fängt die billigsten Fehler.** Tests laufen nicht in CI. Sechs Commits reparieren nur den
   Build, zweimal dieselbe auf tvOS fehlende SwiftUI-Funktion.
3. **Geräte-Schleifen bei Fokus-Themen.** Dieselben Symptome kehren über mehrere veröffentlichte Builds wieder:
   obere Menüleiste nach dem Player (5 Commits über 3 Builds), Poster-Fokus (9 Commits), „kein Systemblau“ (4). Das
   ist das Anti-Ziel der Design-Spec, und es kostet am meisten Zeit.
4. **Kein Abnahme-Schritt.** `main` steht seit 0.4.0 still; neun veröffentlichte `integ`-Builds tragen dieselbe
   Versionsnummer. „Am Gerät geprüft“ ist nirgends festgehalten.
5. **Tempo vor Sicherheit.** Die Sicherheits- und Persistenz-Zusagen der Spec (Keychain, verschlüsselter Export) sind
   die einzigen, die als „abgewichen“ mit hohem Schweregrad dastehen.

**Was künftig anders laufen sollte**

| Maßnahme | Wirkung auf die 15 bis 20 Minuten je Gerätetest |
|---|---|
| `swift test` als erster CI-Job, Release hängt davon ab | Logikfehler fallen nach 2 Minuten auf, nicht nach 20 |
| Kompilier-Prüfung vor dem vollen Build (`xcodebuild build` ohne Paketieren, nur bei Änderungen in `App/`) | Build-Reparaturen kosten einen kurzen Lauf |
| **Bildschirmfotos aus dem tvOS-Simulator in CI** (UI-Test, der die Hauptseiten mit Beispieldaten öffnet und Bilder als Artefakt ablegt) | Aussehen, Abstände und viele Fokus-Zustände lassen sich ohne Gerät ansehen; das Gerät bleibt für Wiedergabe, Ton und echte Fokus-Wege |
| Ein Testprotokoll je Build als Datei im Repo (`docs/superpowers/geraetetests/build-NNN.md`) mit Häkchen und den erwarteten Log-Zeilen | jeder Gerätetest prüft alles, was der Build ändert, in einem Durchgang |
| Diagnose-Schalter in der App für Zeitwerte (Ruhezeit, Aufklapp-Dauer, Fokus-Skalierung) | Varianten lassen sich am Gerät vergleichen, ohne neuen Build |
| Ringpuffer-Log auf dem Gerät (ADR-6) | ein Fehler muss nicht mit laufendem Empfänger nachgestellt werden |
| Entscheidungsprotokoll statt großer Specs: eine Datei `docs/entscheidungen.md`, je Entscheidung drei Zeilen, bei jeder Abweichung im selben Commit geändert | Dokumente und Code laufen nicht mehr auseinander |
| Nicht-Ziele nur durch eine Zeile im Entscheidungsprotokoll aufheben | Scope-Drift wird sichtbar |
| `main` nur über ein abgehaktes Testprotokoll befüllen, Versionsnummer je Abnahme erhöhen | „am Gerät geprüft“ hat wieder eine Bedeutung |
| Bündel statt Einzel-Builds: ein Build je Thema mit 5 bis 10 Tasks | weniger Gerätetests bei gleicher Abdeckung (so ist der neue Plan geschnitten) |

---

## 7. Technische Schulden

Methodik: Skill `engineering:tech-debt`. Priorität = (Auswirkung + Risiko) × (6 − Aufwand), jeweils 1 bis 5.

| # | Schuld | Kategorie | Auswirkung | Risiko | Aufwand | Priorität | Beleg | Im Plan |
|---|---|---|---|---|---|---|---|---|
| 1 | Tests laufen nicht in CI | Infrastruktur | 4 | 5 | 1 | **45** | Q-22 | Build 1 |
| 2 | Dekodierfehler führt zum Überschreiben aller Profile | Architektur | 5 | 4 | 2 | **36** | S-1, S-2, D-1 | Build 1 |
| 3 | Handy-Seite: ein Token gibt alles frei, kein Bestätigen am TV | Architektur | 4 | 5 | 2 | **36** | SEC-1 | Build 1 |
| 4 | Fern-Log immer an, Empfänger ungeprüft | Infrastruktur | 3 | 4 | 1 | **35** | SEC-2 | Build 1 |
| 5 | Kein gemeinsamer HTTP-Client (Zeitgrenzen, Größenlimit, Zielprüfung) | Code | 3 | 4 | 2 | **28** | SEC-6, SEC-9, [04 §5](04-system-design.md) | Build 2 |
| 6 | Parser auf Freitext ohne Fuzz-Test, Absturzpfad | Test | 3 | 4 | 2 | **28** | A-A-1 bis A-A-3, SEC-10 | Build 2 |
| 7 | Dokumente widersprechen sich und dem Code (20 Stellen) | Dokumentation | 3 | 3 | 1 | **30** | Abschnitt 3 oben | Build 1 |
| 8 | Geheimnisse im Profil-JSON statt Keychain | Architektur | 3 | 4 | 3 | **21** | SEC-14, E-15 | Build 2 und 3 |
| 9 | Profilwechsel leert Zustand von Hand, keine Epoche | Architektur | 4 | 4 | 3 | **24** | S-3, S-4, A-A-8, A-B-2 | Build 3 |
| 10 | Ablauflogik in `PlayerControls` und `StreamListView` | Architektur | 5 | 4 | 4 | **18** | Q-1, Q-3, Q-21 | Build 6 |
| 11 | `AppModel` als Gott-Objekt, `ObservableObject` | Architektur | 4 | 3 | 4 | **14** | Q-5, Q-14 | Build 6 |
| 12 | App im Swift-5-Modus, rund 100 ungebundene Tasks | Code | 3 | 4 | 4 | **14** | Q-12, Q-13 | Build 6 |
| 13 | Zwei Designwelten, 135 Farb- und 173 Größen-Literale | Code | 3 | 2 | 3 | **15** | D-3, D-17 | Build 4 und 5 |
| 14 | `Theme` statisch, keine Presets, Optionen in vier Strukturen | Architektur | 3 | 2 | 3 | **15** | D-28 | Build 4 |
| 15 | Keine Lokalisierung, README verspricht sie | Dokumentation / Code | 2 | 2 | 1 (README) | **20** | Q-24 | Build 1 (README) |
| 16 | VoiceOver-Labels fehlen auf Kacheln und im Player | Code | 2 | 2 | 2 | **16** | Q-26, Q-27 | Build 5 |
| 17 | Build-Kette mit beweglichen Bezügen | Abhängigkeiten | 2 | 3 | 1 | **25** | SEC-15 | Build 1 |
| 18 | Duplikate (Zeitformat, Folgen-ID, Caches) | Code | 2 | 2 | 2 | **16** | Q-7, Q-8, Q-11 | Build 6 |
| 19 | 415 öffentliche Typen in `PlayerCore`, toter Code | Code | 1 | 1 | 3 | **6** | Q-17, Q-18 | später |
| 20 | Personenbezug in sechs Merge-Commits | Dokumentation | 2 | 3 | 2 | **20** | GIT-1 | eigene Entscheidung des Nutzers |

Lesart: Die ersten vier Zeilen kosten zusammen wenig und beseitigen die größten Risiken. Sie bilden Build 1 des Plans.
Die großen Architektur-Umbauten (10 bis 12) haben die niedrigste Priorität nach dieser Formel, weil sie teuer sind;
sie stehen am Ende des Plans und werden über Schattenbetrieb risikoarm eingeführt.

---

## Am Gerät prüfen
- E-18: Bleiben Profile und Schlüssel nach Neu-Signieren und nach Neuinstallation erhalten? In welchem Ordner liegen die Dateien (Fern-Log-Zeile „speicher: … Dateien in …“)?
- E-20/A-8: Meldet das Log je „Profile nur als Datei gespeichert“?
- E-35/E-38: Was zeigt der Receiver bei TrueHD (DD+ 5.1 oder PCM) und zeigt der Fernseher bei einem P7-FEL-Titel Dolby Vision?
- A-5: Wie viele Klicks braucht „Reihe verschieben“ heute im Vergleich zum Greif-Modus der Spec?
