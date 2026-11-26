# Verbesserungen nach der Qualitätsanalyse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die App bekommt eine sichere, datenverlustfreie und edel aussehende Grundlage, bevor neue Funktionen entstehen.

**Architecture:**
- Reihenfolge nach Priorität [N]: Sicherheit → Abstürze und Datenverlust → Bugs → Design → Struktur. Acht gebündelte
  Builds (1, 2, 3, 4, 5a, 5b, 5c, 6), jeder mit Testprotokoll fürs Gerät.
- Neue Logik entsteht als reine Funktion mit Tests in `PlayerCore`; die App führt nur aus. Umbauten laufen zuerst einen
  Build im Schattenbetrieb (neue Regel rechnet mit und loggt Abweichungen), bevor sie das Verhalten übernehmen.
- Das Aussehen wird über ein neues Profilfeld `look` (Vorlage plus Abweichungen) und ein Laufzeit-Theme in der
  Umgebung gesteuert. Die konkreten Werte kommen aus `docs/design/konfigurator/export.json`.
- **Entscheidung des Nutzers (23.11.):** Die App kennt genau eine Vorlage, „Mein Look“. Ihre Werte sind die der
  Konfigurator-Vorlage „Apple TV“ (`export.json`, `"preset": "appletv"`). **Alle 35 Optionen des Konfigurators** sind
  in der App unter Einstellungen › Aussehen einstellbar, jede mit allen Werten, die der Konfigurator anbietet
  (Liste: Anhang A). Die Vorlagen Edel, Infuse, Kino-Boutique und Streaming kommen nicht in die App.

**Tech Stack:** Swift 6.2, SwiftUI tvOS 18, Swift Testing (Podman `swift:6.2`), CryptoKit, Security (Keychain),
GitHub Actions, atvloadly.

**Spec:** Die Analyse unter `docs/superpowers/analysis/2026-11-22/` (Befund-IDs: `SEC-`, `GIT-`, `S-`, `W-A-`, `W-B-`,
`F-A-`, `F-B-`, `A-A-`, `A-B-`, `Q-`, `D-`; ADRs in `03-engineering-entscheidungen.md`; Modell `Look` in
`04-system-design.md` §8; Design-System und Schema in `07-design-analyse.md`).

**Ausgangsstand:** Branch `integ`, Commit `b2188a2` (Build 249). Alle `Datei:Zeile`-Angaben der Analyse beziehen sich
darauf. Dieser Plan liegt auf einem Branch, der von `main` abzweigt; vor Beginn wird er nach `integ` übernommen.

## Global Constraints

- Mindestversion: tvOS 18.0. Das Repo ist öffentlich: keine Schlüssel, keine Namen, keine IPs, keine privaten Hostnamen.
- Neue Profilfelder bekommen Standardwerte in `Profile.init(from:)`. Ab Build 1 gilt zusätzlich: **Dekodierung wirft
  nie wegen eines einzelnen Werts.** Jedes Enum wird über `decodeLenient` gelesen.
- Jede Änderung an gespeicherten Formaten bekommt einen Test mit einer Fixture des letzten veröffentlichten Builds
  (`Packages/PlayerCore/Tests/PlayerCoreTests/Fixtures/`). Fixtures sind synthetisch.
- Lesen darf nie zum Überschreiben führen: Nach einem gescheiterten Laden der Profile wird nicht gespeichert.
- Bilder ausschließlich über `RemoteImage` / `ImagePipeline`.
- Netzabrufe ab Build 2 ausschließlich über `HTTPClient` (Zeitgrenze, Größenlimit, Zielprüfung).
- Die Oberfläche ist auf Deutsch.
- Farben, Schriften, Abstände, Radien, Schatten und Dauern ab Build 4 nur noch über `@Environment(\.theme)`.
- Die fokussierte View ändert durch keine Option und kein Nachladen ihre Identität.
- Kerntests: `cd Packages/PlayerCore && podman run --rm -v "$PWD":/pkg:Z -w /pkg docker.io/library/swift:6.2 swift test`.
  Zum Start sind 965 Tests grün; jeder Task nennt die Zahl der neuen Tests.
- Ein Build je Abschnitt. Vor jedem Build die Deploy-Checkliste des Abschnitts abhaken. Zurück geht es immer über das
  vorige Release `build-<N>`; deshalb muss jeder Build die Daten des vorigen lesen **und** der vorige die des neuen.
- Messpunkte fürs Fern-Log tragen das Präfix `metric:` und feste Namen (Liste in `04-system-design.md` §6).

## Review Focus

1. Profil-JSON mit einem unbekannten Wert in `appearance.accent` oder `home.rows[].style`: Alle Profile laden, das
   Feld bekommt den Standardwert, eine Logzeile nennt das Feld. Test: Task 1.2.
2. `profiles.json` ist abgeschnitten oder kein JSON: Die App zeigt „Profile nicht lesbar“ und speichert nichts, bis der
   Nutzer entscheidet. Test: Task 1.3.
3. Ein zweites Gerät im WLAN ruft die Handy-Seite mit mitgelesenem Token auf: kein Export mit Geheimnissen, keine
   Wiederherstellung, keine Addon-Änderung ohne Bestätigung am Fernseher. Test: Task 1.4.
4. Addon liefert `"12345678901234567890 GB"` oder ein Bild mit 300 MB: kein Absturz, Eintrag bleibt ohne Größe bzw.
   Bild wird verworfen. Test: Tasks 1.7 und 2.3.
5. Profilwechsel, während Trakt-Erneuerung oder Fortschritts-Abgleich läuft: Das Ergebnis landet im richtigen Profil
   oder wird verworfen, nie im falschen. Test: Task 3.1.

---

## Build 1: Sicherheit und Schutz der Profile

Ziel: die vier größten Risiken schließen, ohne das gespeicherte Format zu ändern. Alles in diesem Build ist klein und
voneinander unabhängig.

### Task 1.1: Tests und Kettenprüfung in CI

**Befunde:** Q-22, SEC-15, SEC-17 · **Risiko:** gering · **Profile:** nicht betroffen

**Files:**
- Modify: `.github/workflows/build.yml` (neuer Job `test`; `build`, `release`, `publish` mit `needs: test`)
- Create: `Packages/AetherFEL/Package.resolved` (einchecken), `.gitignore` anpassen
- Modify: `.github/workflows/build.yml` (XcodeGen als festes Release-Archiv mit SHA-256 statt `brew install`;
  `IPA_DENYLIST` nur noch in Läufen auf `integ` und `main`)

- [ ] **Step 1:** Job `test` auf `ubuntu-latest` im Container `swift:6.2`: `cd Packages/PlayerCore && swift test`.
- [ ] **Step 2:** `needs: test` an `build`; `release` und `publish` hängen schon an `build`.
- [ ] **Step 3:** XcodeGen-Archiv mit festem Tag laden, `shasum -a 256 -c` gegen einen im Workflow stehenden Wert.
- [ ] **Step 4:** `xcodebuild … -onlyUsePackageVersionsFromResolvedFile`.
- [ ] **Step 5:** Bedingung `if: github.ref_name == 'integ' || github.ref_name == 'main'` am Schritt mit dem Geheimnis.
- [ ] **Step 6:** Push auf einen Wegwerf-Branch mit einem absichtlich roten Test. Erwartet: `test` rot, kein `build`.
- [ ] **Step 7:** Commit „CI: Kerntests vor dem Build, feste Bezüge“.

### Task 1.2: Dekodierung, die nie wirft

**Befunde:** S-2, D-1, Q-16 · **Risiko:** mittel (zentrale Modelle) · **Profile:** alte und neuere Stände laden; kein
neues Format

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Models/LenientDecoding.swift`
- Modify: `Models/Profile.swift`, `Models/Appearance.swift`, `Ranking/QualityBadges.swift` (`BadgeSettings`),
  `Models/Home.swift`, `Models/Collection.swift` (`SourceKind`, `RowStyle`), `Models/TitleDisplaySettings.swift`,
  `Store/ProfileStore.swift` (`StoredProfiles`)
- Test: `Tests/PlayerCoreTests/LenientDecodingTests.swift`, Fixture `Fixtures/future-profiles.json` (synthetisch)

**Interfaces (Produces):**
- `public struct DecodeReport: Sendable, Equatable { public var ignored: [String] }` (Pfade wie `profiles[1].appearance.accent`)
- `extension KeyedDecodingContainer { func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key, default: T, report: DecodeReportBox) -> T }`
- `final class DecodeReportBox` wird über `decoder.userInfo[.decodeReport]` gereicht.
- `StoredProfiles.init(from:)` dekodiert `profiles` elementweise (`[FailableDecodable<Profile>]`); ein nicht lesbares
  Profil wird übersprungen und im Bericht genannt.
- `HomeLayout.init(from:)` überspringt Reihen mit unbekanntem `style` oder `SourceKind` und legt ihr rohes JSON in
  `HomeLayout.unknownRows: [JSONValue]` ab; `encode` schreibt sie unverändert zurück.
- `ProfileStore.load()` gibt zusätzlich den `DecodeReport` zurück (siehe Task 1.3).

- [ ] **Step 1: Tests schreiben** (8 neue)
  - `unknownAccentFallsBackAndIsReported`: `"accent":"turquoise"` → `.blue`, Bericht enthält `appearance.accent`.
  - `unknownNavigationCardSizeBadgeStyleLanguageProgressSource`: je ein unbekannter Wert, Profil lädt.
  - `unknownRowStyleIsKeptAsRawAndWrittenBack`: Reihe mit `"style":"mosaic"` fehlt in `rows`, steht nach
    `encode` → `decode` wieder im JSON.
  - `oneBrokenProfileDoesNotBreakTheOthers`: zweites Profil ohne `id` → erstes und drittes laden, Bericht nennt `profiles[1]`.
  - `ratingSourcesWrongTypeFallsBack`.
  - `futureProfilesFixtureLoadsCompletely` (Fixture mit unbekannten Feldern und Werten auf jeder Ebene).
  - `legacyFixtureStillLoads` (`main-profiles-v1.json`, vorhandener Test bleibt grün).
  - `reportIsEmptyForCurrentData`.
- [ ] **Step 2:** Tests laufen lassen. Erwartet: Kompilierfehler.
- [ ] **Step 3:** Implementieren. Jedes `try c.decodeIfPresent(<Enum>.self …)` in den genannten Dateien wird zu
  `c.decodeLenient(…)`.
- [ ] **Step 4:** Tests laufen lassen. Erwartet: 965 + 8 grün.
- [ ] **Step 5:** Commit „Profile: Dekodierung wirft nie wegen eines einzelnen Werts“.

### Task 1.3: Laden überschreibt nie

**Befunde:** S-1, S-11 · **Risiko:** hoch (Start der App) · **Profile:** Format unverändert; neue Sicherungs-Blöcke
`profiles.json.1` und `.2`

**Files:**
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift`, `Store/TieredBlobStorage.swift`
  (Vorbehalt für die zwei Generationen), `Progress/WatchProgress.swift` (`ProgressStore.load`)
- Modify: `App/Sources/AppModel.swift` (Start, `save()`), `App/Sources/PlayerApp.swift` (`RootView`)
- Create: `App/Sources/Views/ProfileRecoveryView.swift`
- Test: `Tests/PlayerCoreTests/StoreRecoveryTests.swift`

**Interfaces (Produces):**
- `public enum ProfileLoad: Sendable { case loaded(StoredProfiles, DecodeReport), fresh(StoredProfiles), unreadable(reason: String, candidates: [RecoveryCandidate]) }`
- `public struct RecoveryCandidate: Sendable, Identifiable { public let id: String; public let label: String; public let profiles: Int; public let savedAt: Date? }`
  (Quellen: `profiles.json.1`, `profiles.json.2`, `profiles.json.bak`, Dateikopien).
- `ProfileStore.loadResult() -> ProfileLoad`; `ProfileStore.restore(_ id: String) throws -> StoredProfiles`;
  `ProfileStore.save(_:)` schiebt vor dem Schreiben die letzte gute Fassung nach `.1` und `.1` nach `.2`, höchstens
  einmal je 10 Minuten.
- `AppModel.storeState: StoreState` (`.ready`, `.unreadable`); `save()` ist bei `.unreadable` ein No-op mit Logzeile.
- `ProgressStore.load` gibt bei Dekodierfehler `nil` zurück statt eines leeren Buchs; der Aufrufer speichert dann
  erst nach dem nächsten Fortschritt und legt die unlesbare Datei als `progress-<Profil>.json.bak` ab.

- [ ] **Step 1: Tests** (7 neue): `missingFileIsFresh`, `garbageIsUnreadableAndNothingIsWritten`,
  `truncatedJsonListsGenerationsAsCandidates`, `restoreFromGeneration1`, `restoreFromBak`,
  `saveRotatesGenerationsAtMostEveryTenMinutes` (Uhr als Parameter), `unreadableProgressKeepsFileAsBak`.
- [ ] **Step 2:** Tests laufen lassen. Erwartet: Kompilierfehler.
- [ ] **Step 3:** Implementieren. `ProfileRecoveryView` zeigt Grund, Kandidaten mit Profilzahl und Datum sowie die
  Knöpfe „Erneut versuchen“, „Diese Fassung laden“, „Neu anfangen“ (mit Rückfrage). Startfokus auf „Erneut versuchen“.
- [ ] **Step 4:** Tests laufen lassen. Erwartet: 973 + 7 grün.
- [ ] **Step 5:** Commit „Profile: unlesbarer Stand wird nie überschrieben, letzte zwei Fassungen bleiben“.

### Task 1.4: Handy-Seite – der Fernseher bestätigt

**Befunde:** SEC-1, SEC-5, SEC-16 · **Risiko:** mittel (Einrichtung ändert sich um einen Druck) · **Profile:** nicht
betroffen

**Files:**
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift` (Parser, Routen, Sitzungsregeln)
- Create: `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneSession.swift`
- Modify: `App/Sources/Views/PhoneInputView.swift` (`PhoneServer`, Bestätigungs-Karte), `App/Sources/AppModel.swift`
  (`apply`, `backupData`, `importBackup`)
- Test: `Tests/PlayerCoreTests/PhoneSessionTests.swift`, bestehende `PhoneInputTests.swift` erweitern

**Interfaces (Produces):**
- `public struct PhoneSession: Sendable { public init(token: String, now: Date); public mutating func authorize(queryToken: String?, cookie: String?, peer: String, now: Date) -> PhoneAuth }`
  mit `enum PhoneAuth { case firstUse(setCookie: String), ok, denied }`. Regeln: Das URL-Token gilt genau einmal und
  höchstens 10 Minuten; danach zählt nur das Cookie; die Sitzung endet nach 30 Minuten oder beim Schließen der Seite.
- `HTTPRequest.parseHead(_ data: Data) -> HeadResult` (Anfragezeile und Kopf, bevor der Körper gelesen wird);
  `PhoneLimits.maxBody(for path: String) -> Int` (`/home`: 16 KiB, `/submit`: 8 MiB), `maxConnections = 4`,
  `requestDeadline = 10 s`.
- `public enum PhoneCommand.Sensitivity { case plain, needsConfirmation(summary: String) }`. Bestätigung verlangen:
  Wiederherstellung einer Sicherung, Addon hinzufügen oder entfernen, Schlüssel setzen, atvloadly-Adresse setzen.
- `GET /export` liefert die Sicherung **ohne** `apiKeys`, `syncTokens` und ohne den Zugangsteil der Addon-Adressen.
  `GET /export?secrets=1` löst eine Bestätigung am Fernseher aus und liefert danach eine mit CryptoKit
  (ChaChaPoly, Schlüssel aus einem am Fernseher gezeigten sechsstelligen Code plus Salz, HKDF) verschlüsselte Datei
  `player-sicherung.enc`. Die Wiederherstellung fragt den Code am Fernseher ab.
- `ProfileStore.exportData(_:includeSecrets: Bool)`; `BackupCrypto.seal(_:code:) / open(_:code:)` in `PlayerCore`
  (unter Linux über `swift-crypto` nur im Testziel, in der App CryptoKit; beide hinter `protocol BackupCipher`).

- [ ] **Step 1: Tests** (10 neue): Token nur einmal gültig; zweiter Aufruf ohne Cookie → `denied`; Ablauf nach
  10 Minuten; Körper wird bei falschem Token nicht gelesen; `/home` mit 20 KiB → 413; Export ohne Geheimnisse enthält
  keinen der Testschlüssel der Fixture; Export mit Geheimnissen ist ohne Code nicht lesbar; falscher Code → Fehler;
  `backup_json` erzeugt `needsConfirmation`; Addon-Befehl erzeugt `needsConfirmation`.
- [ ] **Step 2:** Tests laufen lassen. Erwartet: Kompilierfehler.
- [ ] **Step 3:** Implementieren. Die Bestätigungs-Karte liegt über dem QR-Code: Text aus `summary`, Knöpfe
  „Erlauben“ und „Ablehnen“, Startfokus auf „Ablehnen“, läuft nach 60 s ab.
- [ ] **Step 4:** Tests laufen lassen. Erwartet: 980 + 10 grün.
- [ ] **Step 5:** Commit „Handy-Seite: Einmal-Adresse, Bestätigung am Fernseher, Export ohne Schlüssel“.

### Task 1.5: Fern-Log nur mit bekanntem Empfänger

**Befunde:** SEC-2, SEC-8, SEC-12, SEC-13 · **Risiko:** gering; **Folge für die Entwicklung:** Das Log muss einmal
eingeschaltet werden · **Profile:** Geräte-Einstellungen bekommen zwei Felder mit Standardwerten

**Files:**
- Modify: `App/Sources/RemoteLog.swift`, `App/Sources/Views/Settings/SystemMaintenanceRows.swift`
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Models/DeviceSettings.swift` (`remoteLogEnabled = false`,
  `remoteLogReceiver: String?`), `Logging/LogRedact.swift`
- Create: `Packages/PlayerCore/Sources/PlayerCore/Logging/LogRing.swift`, `Logging/LogSignature.swift`
- Modify: `tools/logcollector.py`
- Test: `Tests/PlayerCoreTests/LogRedactTests.swift` (erweitern), `LogRingTests.swift`, `LogSignatureTests.swift`

**Interfaces (Produces):**
- `LogRing(capacity: 2000)` mit `append`, `snapshot() -> [LogLine]`, Ablage in Caches (`log-ring.json`, alle 30 s).
- `LogSignature.sign(body: Data, secret: String) -> String` (HMAC-SHA256, Kopfzeile `X-Player-Sig`).
- `RemoteLog` sendet nur, wenn `remoteLogEnabled` und der gefundene Dienstname gleich `remoteLogReceiver` ist. Das
  Einschalten zeigt die gefundenen Empfänger zur Auswahl. Das gemeinsame Geheimnis kommt über die Handy-Seite
  (`PhoneCommand.key("playerlog", …)`).
- `LogRedact`: letzter Pfadteil nur bei bekannter Dateiendung oder `tt<Ziffern>`; Zugangsdaten bis zum letzten `@`
  vor `?`/`#`; Schlüsselwörter um `auth`, `authorization`, `cookie`, `sig`, `signature`, `code`, `pin`, `hash`,
  `pass`, `pwd`, `session` ergänzt; `Basic <…>` wie `Bearer`.
- `logcollector.py`: Signatur prüfen, `Content-Length` als `0 ≤ n ≤ 4 MB`, `timeout = 10`, Steuerzeichen ersetzen,
  nur `dict`-Einträge.

- [ ] **Step 1: Tests** (9 neue): je ein Test pro neuer Schwärzungsregel (5), Ring läuft über und behält die
  neuesten, Ring übersteht Kodieren/Dekodieren, Signatur stimmt mit bekanntem Vektor, geänderter Körper → andere Signatur.
- [ ] **Step 2 bis 4:** rot → implementieren → 990 + 9 grün.
- [ ] **Step 5:** Seite „Diagnose“ unter System: letzte 200 Zeilen des Rings, Filter „nur Fehler“.
- [ ] **Step 6:** Commit „Fern-Log: aus per Standard, fester Empfänger, Signatur, Verlauf auf dem Gerät“.

### Task 1.6: Update nur nach Anzeige und Bestätigung

**Befunde:** SEC-3 (Teil in der App), SEC-7, SEC-11, F-B-6 · **Risiko:** mittel (Update-Weg) · **Profile:** nicht betroffen

**Files:**
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift` (`parseRelease`, `UpdateState.decide`)
- Modify: `App/Sources/AppUpdater.swift`, `App/Sources/Views/Settings/UpdatePage.swift`
- Modify: `.github/workflows/build.yml` (Release-Text um `· SHA256 <hex>` ergänzen)
- Test: `Tests/PlayerCoreTests/AppUpdateTests.swift` (erweitern)

**Interfaces (Produces):**
- `ReleaseInfo.sha256: String?`; `UpdateState.available(build:commit:sha256:)`.
- `AppUpdater.discover()` gibt Kandidaten zurück (`[AtvloadlyCandidate]` mit Name und Adresse) und speichert nichts.
  Die Seite zeigt sie zur Auswahl; eine vorhandene Adresse wird nie stillschweigend ersetzt.
- Vor `install`: Karte „Build N · Commit abcdefg installieren?“ mit Ziel-Adresse. Bei `http://` steht darunter ein
  Hinweis, dass die Verbindung zum Signier-Dienst unverschlüsselt ist. Der Knopf bleibt nach dem Druck sichtbar und
  wird nur deaktiviert dargestellt (F-B-6); der Fokus bleibt auf ihm.
- Die App lädt die IPA nicht selbst. Deshalb prüft sie den Hash nicht, zeigt ihn aber an und reicht ihn im Auftrag mit,
  wo atvloadly das unterstützt. **[C]** Die volle Prüfung (Signatur über Build, Commit und Hash mit einem öffentlichen
  Schlüssel in der App) steht in der Roadmap, weil sie eine Schlüsselverwaltung in CI verlangt.

- [ ] **Step 1: Tests** (5 neue): Release-Text mit und ohne Hash; Hash mit falscher Länge wird verworfen;
  `decide` unverändert bei fehlendem Hash; Kandidatenliste wird nicht gespeichert (reine Funktion `chooseCandidate`).
- [ ] **Step 2 bis 4:** rot → implementieren → 999 + 5 grün.
- [ ] **Step 5:** Commit „Update: Kandidaten wählen, Build und Commit bestätigen, Hash im Release“.

### Task 1.7: Absturzpfade durch Fremddaten schließen

**Befunde:** A-A-3, SEC-10 · **Risiko:** gering · **Profile:** nicht betroffen

**Files:**
- Modify: `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift` (`parseSize`),
  `Services/IntroDB.swift` (`parse`, Logtext)
- Create: `Packages/PlayerCore/Sources/PlayerCore/Models/SafeNumber.swift`
- Test: `Tests/PlayerCoreTests/SafeNumberTests.swift`, `StreamTraitsFuzzTests.swift`

**Interfaces (Produces):** `SafeNumber.int64(_ d: Double) -> Int64?`, `SafeNumber.int(_ d: Double) -> Int?`
(`nil` bei NaN, unendlich oder außerhalb des Bereichs). Segmente der IntroDB mit `end > 86_400` werden verworfen.

- [ ] **Step 1: Tests** (6 neue): Grenzwerte von `SafeNumber` (3); `parseSize("12345678901234567890 GB") == nil`;
  IntroDB-Segment mit `1e300` wird verworfen; Fuzz-Test `StreamTraits.parse` über 2 000 erzeugte Zeichenketten aus
  einem festen Startwert (Ziffernfolgen, Einheiten, Emoji, leere Felder) läuft ohne Absturz durch.
- [ ] **Step 2 bis 4:** rot → implementieren → 1004 + 6 grün. Danach `grep -rn "Int64(\|Int(" Packages/PlayerCore/Sources`
  auf weitere Umwandlungen von `Double` durchsehen und ersetzen.
- [ ] **Step 5:** Commit „Quellen-Parser und IntroDB: keine Abstürze durch Fremddaten“.

### Task 1.8: Messpunkte und Dokumente

**Befunde:** [04 §6], W-A-12, Q-24, E-30, E-51, E-53, W-1 bis W-20 in `03-engineering-entscheidungen.md` · **Risiko:** keines

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Logging/Metric.swift` (`enum Metric: String` mit den Namen aus
  `04-system-design.md` §6, `Metric.line(_:ms:fields:) -> String`)
- Modify: `App/Sources/AppModel.swift`, `App/Sources/Views/HomeHero.swift` (`LaunchFocus`),
  `App/Sources/Views/DetailViews.swift`, `App/Sources/Views/PlayerScreen.swift`, `App/Sources/Playback/PlaybackEngine.swift`
- Modify: `README.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-11-21-tvos-player-design.md` (Statuskopf,
  aufgehobene Nicht-Ziele, neutrale Formulierung der Setup-Angaben, GIT-4), `App/Sources/Views/Settings/DeviceCheckSettings.swift`
  (Tabelle „Was spielt wie“: FEL-Zeile)
- Create: `docs/entscheidungen.md` (Entscheidungsprotokoll, je Entscheidung drei Zeilen; Start mit den ADRs 1 bis 7)
- Test: `Tests/PlayerCoreTests/MetricTests.swift` (2 neue: Format, Namen eindeutig)

- [ ] **Step 1:** Messpunkte einbauen: `start.usable`, `start.profiles`, `start.catalog`, `detail.badges`,
  `streams.firstRow`, `streams.order`, `player.loadBegins`, `player.firstFrame`, `player.audioReload`, `sync.merged`.
- [ ] **Step 2:** README: Oberfläche deutsch, Inhalte deutsch oder englisch; TrueHD-Standard; kein MDBList-Listen-Import;
  TVDB-Feld aus der Handy-Seite entfernen (`PhoneInput.swift`, Dienste-Liste).
- [ ] **Step 3:** Commit „Messpunkte fürs Fern-Log, Dokumente an den Stand angeglichen“.

### Build 1 – Deploy-Checkliste

**Vor dem Build**
- [ ] `test`-Job grün (1012 Tests), `build` grün, IPA-Prüfung grün.
- [ ] Sicherung der Profile über die **alte** Handy-Seite gezogen und abgelegt (letzte Sicherung im alten Format).
- [ ] Rückweg notiert: Release `build-249`.

**Am Gerät prüfen** (ein Durchgang, etwa 20 Minuten)
- [ ] App startet, alle Profile, Startseiten und Anmeldungen sind da.
- [ ] Handy-Seite: QR scannen, Addon eintragen → am Fernseher erscheint die Bestätigung; „Ablehnen“ ändert nichts.
- [ ] Dieselbe Adresse auf einem zweiten Gerät öffnen → abgelehnt.
- [ ] Sicherung ohne Schlüssel laden; Sicherung mit Schlüsseln: Code am Fernseher, Datei ist nicht lesbar.
- [ ] Wiederherstellung der verschlüsselten Sicherung mit Code.
- [ ] Fern-Log: aus nach dem Update; einschalten, Empfänger wählen, Zeilen kommen an. Ein zweiter, falscher Empfänger
  im Netz bekommt nichts.
- [ ] Diagnose-Seite zeigt die letzten Zeilen ohne Empfänger.
- [ ] Update-Seite: „Im Netz suchen“ zeigt eine Auswahl; Installation zeigt Build und Commit.
- [ ] Zurück auf `build-249` und wieder vor: Profile bleiben erhalten (Generationen `.1`/`.2` stören den alten Build nicht).

**Erwartete Fern-Log-Zeilen**
- `metric: start.usable <ms>` genau einmal je Start.
- `speicher: Profile geladen · Bericht leer` bzw. `… · ignoriert: <Pfad>`.
- `handy: Sitzung gebunden`, `handy: Bestätigung <Art> erlaubt|abgelehnt|abgelaufen`.
- `log: Empfänger <Name> gewählt`.

**Rückfall-Auslöser:** Profile fehlen nach dem Start; „Profile nicht lesbar“ ohne erkennbaren Grund; die Handy-Seite
lässt sich nicht mehr öffnen.

---

## Build 2: Datenverlust und Netz-Härtung

### Task 2.1: Fortschritt mischt, statt zu ersetzen

**Befunde:** W-B-1, S-13 · **Risiko:** mittel (Weiterschauen) · **Profile:** Format unverändert

**Files:** Modify `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift`; Test `ProgressRecordTests.swift`

**Interfaces (Produces):** `ProgressBook.record(_ new: WatchProgress, now: Date)` mit den Regeln:
- Ein Eintrag mit `finished == true` verliert das Häkchen erst, wenn die neue Sitzung mehr als 5 % **und** mehr als
  120 s gelaufen ist.
- Der Hinweis auf die nächste Folge (`recordNextUp`) bleibt, bis die neue Folge selbst mehr als 120 s gelaufen ist.
- `remoteFraction`, Titel und Bilder des alten Eintrags bleiben erhalten, wenn der neue sie nicht mitbringt.
- `merge(remote:)` übernimmt Position und Zeitstempel, nicht aber leere Titel oder Bilder.

- [ ] **Step 1: Tests** (7 neue), u. a. `reopeningFinishedTitleFor15sKeepsCheckmark`,
  `leavingNextEpisodeInFirstMinuteKeepsSeriesInContinueWatching`, `remoteMergeKeepsLocalArtwork`.
- [ ] **Step 2 bis 4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit „Fortschritt: kurzes Öffnen löscht weder Häkchen noch nächste Folge“.

### Task 2.2: Geheimnisse in die Keychain, Stufe 1 (doppelte Buchführung)

**Befunde:** SEC-14, E-15 · **Risiko:** hoch · **Profile:** Format unverändert; Schlüssel stehen zusätzlich in der
Keychain. Ein Rückschritt auf Build 1 funktioniert, weil das Profil sie weiter enthält.

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Store/SecretStore.swift` (Protokoll und `MemorySecretStore`),
  `App/Sources/KeychainSecretStore.swift`
- Modify: `App/Sources/AppModel.swift` (Lesen von `apiKeys` und `syncTokens` über `secrets`, Schreiben in beide)
- Test: `Tests/PlayerCoreTests/SecretStoreTests.swift`

**Interfaces (Produces):**
- `public protocol SecretStore: Sendable { func get(_ name: String, profile: UUID) -> String?; func set(_ value: String?, name: String, profile: UUID) throws; func removeAll(profile: UUID) throws }`
- `KeychainSecretStore`: `kSecClassGenericPassword`, Dienst `<Bundle-ID>.secrets`, Konto `<Profil-UUID>/<Name>`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `SecretMigration.copyIntoStore(profiles:store:) -> Int` läuft bei jedem Start und ist wiederholbar.
- Leseregel: Keychain, sonst Profil. Schreibregel in diesem Build: beide.

- [ ] **Step 1: Tests** (5 neue) gegen `MemorySecretStore`: Kopieren ist wiederholbar; Lesen fällt auf das Profil
  zurück; Löschen eines Profils entfernt seine Einträge; Token-Rotation schreibt beide Orte; leerer Wert löscht.
- [ ] **Step 2 bis 4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit „Schlüssel und Tokens zusätzlich im Schlüsselbund“.

### Task 2.3: Ein HTTP-Client mit Grenzen

**Befunde:** SEC-6, SEC-9, SEC-4 (Teil), A-A-5, A-A-11, A-A-15 · **Risiko:** mittel (alle Abrufe) · **Profile:** nicht betroffen

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Net/HTTPClient.swift`, `Net/TargetPolicy.swift`
- Modify: `Addons/AddonClient.swift`, `Sync/APIRequest.swift`, `Services/TorBox.swift`, `App/Sources/AppModel+MetaAddon.swift`
  (Cinemeta), `App/Sources/FusionKitStore.swift`, `App/Sources/ImagePipeline.swift`, `App/Sources/Views/Player/PlayerPictureSound.swift`
- Modify: `App/project.yml` (`NSAllowsArbitraryLoads` entfernen, `NSAllowsLocalNetworking` behalten,
  `NSAllowsArbitraryLoadsForMedia: true`) **[C]:** erst nach dem Gerätetest dieses Builds, weil die Engine eigene
  Verbindungen öffnet
- Test: `Tests/PlayerCoreTests/TargetPolicyTests.swift`, `HTTPClientTests.swift`

**Interfaces (Produces):**
- `public struct HTTPLimits: Sendable { public var requestTimeout: TimeInterval = 10; public var resourceTimeout: TimeInterval = 20; public var maxBytes: Int }`
  mit `.json` (8 MiB), `.image` (20 MiB), `.subtitle` (5 MiB).
- `public protocol HTTPClient: Sendable { func data(_ request: URLRequest, limits: HTTPLimits, fresh: Bool) async throws -> (Data, HTTPURLResponse) }`.
  `fresh: true` setzt `reloadIgnoringLocalCacheData` (A-A-5). Die App-Umsetzung liest über `bytes(for:)` und bricht
  beim Überschreiten von `maxBytes` ab.
- `public enum TargetPolicy { public static func allows(_ url: URL, origin: URL?) -> Bool }`: nur `http`/`https`;
  private Ziele (RFC 1918, link-local, Loopback, `.local`, Namen ohne Punkt) nur, wenn `origin` denselben Host hat.
  Gilt für alle Adressen aus Addon-Antworten: Bilder, Streams, Untertitel, Kit-Dateien.
- `ProxyHeaderPolicy.filtered(_ headers: [String: String]) -> [String: String]`: nur `User-Agent`, `Referer`, `Origin`,
  `Accept`, `Accept-Language`, `Range`.
- Listen nach dem Dekodieren kappen: Katalog 500 Einträge, Streams 2 000.

- [ ] **Step 1: Tests** (12 neue): Tabelle erlaubter und verbotener Ziele (`file://`, Loopback, privates Netz mit
  fremdem Ursprung, privates Netz mit gleichem Ursprung, `.local`, öffentlicher Host); Kopfzeilen-Filter; Abbruch bei
  `maxBytes` mit einem Schein-Transport; `fresh` setzt die Cache-Regel.
- [ ] **Step 2 bis 4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit „Ein HTTP-Client: Zeitgrenzen, Größenlimit, Zielprüfung für Addon-Adressen“.

### Task 2.4: Sicherung vollständig, Wiederherstellung sauber

**Befunde:** A-B-1, S-9, S-12 · **Risiko:** mittel · **Profile:** Sicherung bekommt `backupVersion: 2`; Version 1 wird
weiter gelesen

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Store/Backup.swift`
- Modify: `Store/ProfileStore.swift`, `Import/FusionKitCatalog.swift` (`FusionKitSync.apply`),
  `App/Sources/AppModel.swift` (`backupData`, `importBackup`, `deleteProfile`), `App/Sources/FusionKitStore.swift`,
  `App/Sources/CollectionLinkStore.swift`
- Test: `Tests/PlayerCoreTests/BackupTests.swift`

**Interfaces (Produces):**
- `public struct Backup: Codable, Sendable { var backupVersion: Int; var profiles: StoredProfiles; var progress: [UUID: ProgressBook]; var fusionKits: [UUID: Data]; var collectionLinks: [UUID: Data]; var device: DeviceSettings? }`.
  `Backup.decode(_:)` erkennt ein altes `StoredProfiles` (Version 1) und füllt den Rest leer.
- `FusionKitSync.apply(settings:layout:) -> HomeLayout` entfernt Kit-Reihen nur, wenn `settings` **geladen** und die
  Kit-Auswahl ausdrücklich leer ist; bei „keine Einstellungen vorhanden“ bleibt das Layout unverändert.
- `AppModel.importBackup` ruft danach `profileScopeChanged()` (in diesem Build: alle Caches leeren, laufende Aufgaben
  verwerfen; in Build 3 durch `ProfileScope` ersetzt) und entfernt OAuth-Tokens, deren `expiresAt` vorbei ist.
- `AppModel.deleteProfile` löscht alle Blöcke `*-<Profil>.json` und die Keychain-Einträge des Profils.

- [ ] **Step 1: Tests** (7 neue): alte Sicherung lädt; Rundlauf Version 2; fehlende Kit-Einstellungen lassen
  Kit-Reihen stehen; ausdrücklich leere Auswahl entfernt sie; abgelaufene Tokens fallen weg; Löschen räumt alle Blöcke.
- [ ] **Step 2 bis 4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit „Sicherung: Fortschritt, Kits und Links enthalten; Einspielen löscht keine Reihen“.

### Task 2.5: Sync verliert nichts

**Befunde:** S-5, S-6, S-7, S-8, W-B-3, W-B-6, S-15 · **Risiko:** mittel · **Profile:** Warteschlange bekommt neue
Aktionsarten; alte Einträge werden weiter gelesen

**Files:** Modify `Sync/SyncQueue.swift`, `Sync/SyncWrites.swift`, `Sync/ScrobbleTracker.swift`,
`App/Sources/AppModel+SyncQueue.swift`, `App/Sources/AppModel.swift` (`sendScrobble`),
`App/Sources/Views/SyncLoginView.swift`; Test `SyncQueueTests.swift`, `SyncTests.swift` (erweitern)

**Interfaces (Produces):**
- `SyncAction.scrobbleStop(id:progress:at:)`: Ein gescheitertes `stop` wird als Verlaufseintrag in die Warteschlange gelegt.
- `SyncAction.resolveThen(tmdbID:type:action:)`: Aktionen auf `tmdb:`-Kacheln ohne Netz warten auf die ID-Auflösung.
- `SyncQueue.Entry.attempts: Int`; nach 8 Versuchen oder bei einem dauerhaften Fehler (4xx außer 401, 408, 429) wird
  der Eintrag in `deadLetters` verschoben und blockiert nichts mehr.
- `POST /sync/history` bekommt `watched_at` aus dem Eintrag; vor dem erneuten Senden prüft `SyncWrites`, ob der
  Eintrag schon im Verlauf steht (ein `GET /sync/history/{type}/{id}`).
- `ScrobbleTracker`: genau ein `stop` je Sitzung und Titel; ab 80 % gilt der Titel lokal als gesehen (Schwelle wie
  beim Dienst); in der Pause wird kein `start` gesendet.
- Gerätelogin: 5xx und Zeitüberschreitung zählen als „weiter warten“, erst der Ablauf des Codes beendet.

- [ ] **Step 1: Tests** (10 neue). **Step 2 bis 4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit „Sync: gesehen geht nicht verloren, Warteschlange ohne Dauerblockade“.

### Task 2.6: Fortschritt bleibt klein

**Befunde:** S-10 · **Risiko:** gering · **Profile:** alte Einträge werden beschnitten (nur fertige, älter als 18 Monate)

**Files:** Modify `Progress/WatchProgress.swift`, `Store/TieredBlobStorage.swift`; Test `ProgressPruneTests.swift`

**Interfaces (Produces):** `ProgressBook.pruned(now:keepFinished: 1500, keepOpen: 500) -> ProgressBook`; läuft vor
jedem Speichern. Fällt `progress-<Profil>.json` trotzdem aus UserDefaults, erscheint einmal eine Meldung unter
System → Diagnose.

- [ ] **Step 1: Tests** (4 neue). **Step 2 bis 4.** **Step 5:** Commit.

### Build 2 – Deploy-Checkliste

**Vor dem Build:** `test` grün; Sicherung über die neue Handy-Seite (mit Schlüsseln, Code notiert); Rückweg: Build 1.

**Am Gerät prüfen**
- [ ] Alle Anmeldungen (Trakt, Simkl, TorBox) funktionieren ohne neues Anmelden.
- [ ] Gesehenen Film 15 s öffnen und schließen → Häkchen bleibt.
- [ ] Nächste Folge startet automatisch, nach 30 s beenden → Serie steht weiter in „Weiterschauen“ mit dieser Folge.
- [ ] WLAN aus, Film „gesehen“ markieren, WLAN an → Eintrag erscheint bei Trakt genau einmal.
- [ ] Sicherung auf dem Gerät einspielen → Kit-Reihen bleiben; Fortschritt ist da.
- [ ] Ein Addon im Heimnetz über `http://` funktioniert weiter; Bilder und Wiedergabe unverändert.
- [ ] Dolby-Vision-Titel, TrueHD-Titel und ein Titel über den Plattencache starten (Engine-Verbindungen nach der ATS-Änderung).
- [ ] Zurück auf Build 1 und wieder vor: Anmeldungen bleiben.

**Erwartete Fern-Log-Zeilen:** `geheimnisse: <n> in den Schlüsselbund kopiert` (nur beim ersten Start),
`netz: verworfen <Grund>` nur bei absichtlich falschen Zielen, `sync: Warteschlange <n> offen · <n> abgelegt`,
`fortschritt: beschnitten <n>`.

**Rückfall-Auslöser:** Anmeldung verloren; Wiedergabe startet nicht; Bilder fehlen flächig.

---

## Build 3: Bugs in Wiedergabe, Quellen und Profilwechsel

### Task 3.1: Profil-Epoche

**Befunde:** S-3, S-4, A-A-8, A-A-12, A-B-2, F-B-10 · **Risiko:** mittel · **Profile:** nicht betroffen

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileScope.swift`
- Modify: `App/Sources/AppModel.swift` (`switchProfile`, `syncRemoteProgress`, `refreshTrakt`, `localizedCache`,
  `seasonCache`, Addon-Änderungen), `App/Sources/AppModel+MetaAddon.swift`, `App/Sources/Views/HomeHero.swift` (`HeroDetailsCache`)
- Test: `Tests/PlayerCoreTests/ProfileScopeTests.swift`

**Interfaces (Produces):**
- `public struct ProfileScope: Sendable, Hashable { public let profile: UUID; public let epoch: Int }`
- `public struct ScopeClock: Sendable { public private(set) var current: ProfileScope; public mutating func advance(to profile: UUID); public mutating func bump(); public func isCurrent(_ s: ProfileScope) -> Bool }`
- Regel in der App: Jede Funktion mit `await`, die Profil-Daten schreibt, merkt sich `let scope = scopes.current` und
  prüft danach `guard scopes.isCurrent(scope)`.
- `refreshTrakt`: Die laufende Erneuerung ist an `scope.profile` gebunden. Das Ergebnis wird **immer** in das Profil
  geschrieben, für das sie gestartet wurde (über die Profil-ID, auch wenn es nicht mehr aktiv ist).
- Schlüssel der Text-Caches: `(imdbID, language)`. `bump()` bei Sprachwechsel, Addon-Änderung, Sicherungs-Import.

- [ ] **Step 1: Tests** (6 neue) mit einem künstlichen Ablauf: Start in A, Wechsel nach B, Ergebnis von A trifft ein
  → verworfen bzw. bei der Token-Erneuerung nach A geschrieben.
- [ ] **Step 2 bis 4.** **Step 5:** Commit „Profil-Epoche: späte Ergebnisse landen nie im falschen Profil“.

### Task 3.2: Startlogik läuft nach jedem erfolgreichen Laden

**Befunde:** W-A-1, W-A-3, W-A-4, W-B-4, W-A-9 · **Risiko:** hoch (Player) · **Profile:** nicht betroffen

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Playback/StartSequence.swift`
- Modify: `App/Sources/Views/PlayerScreen.swift` (`loadAndStart`, `recover`), `App/Sources/Views/Player/PlayerStability.swift`
- Test: `Tests/PlayerCoreTests/StartSequenceTests.swift`

**Interfaces (Produces):**
- `public struct StartSequence: Sendable { public enum Step: Sendable, Equatable { case placeholderCheck, selectAudio(restore: Int?), subtitleAutomatic, addonSubtitles, seek(fraction: Double?), play } ; public mutating func afterSuccessfulLoad(isFirst: Bool, remembered: TrackMemory.Entry?, pendingFraction: Double?) -> [Step] }`
  Regeln: Der erste erfolgreiche Ladevorgang einer Sitzung liefert alle Schritte, egal ob er aus `loadAndStart` oder
  aus der Fehlerleiter kommt. Jeder spätere liefert `selectAudio(restore: zuletzt gewählte Spur)`,
  `seek(fraction:)` nur, solange der Sprung noch nicht ausgeführt wurde, und `play`.
- Die Leiter zählt nur Zeit als „gesund“, in der die Position fortschreitet (W-A-9).

- [ ] **Step 1: Tests** (8 neue). **Step 2 bis 4.**
- [ ] **Step 5:** In der View: ein Aufrufer `runStartSteps(_:)` für beide Wege. Logzeile `player: Startschritte <Liste>`.
- [ ] **Step 6:** Commit „Player: Tonwahl, Untertitel und Fortsetzen auch nach repariertem Ladefehler“.

### Task 3.3: Tonwahl ohne Kommentar und Hörfilm

**Befunde:** W-A-2 · **Risiko:** gering

**Files:** Modify `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift` (`audioScore`) bzw.
`Playback/TrackChoice.swift`; Test `TrackChoiceTests.swift` (3 neue): Kommentar in Dolby Digital verliert gegen
Hauptton in AAC; Hörfilm wird nur gewählt, wenn keine andere Spur der Sprache existiert; Spur-Gedächtnis darf
ausdrücklich eine Kommentarspur wiederwählen.

- [ ] **Steps 1 bis 5** wie üblich; Commit „Tonwahl: Kommentar- und Hörfilm-Spuren nie automatisch“.

### Task 3.4: Quellenliste folgt der laufenden Folge

**Befunde:** F-B-1, F-B-5 · **Risiko:** mittel

**Files:** Modify `App/Sources/Views/DetailViews.swift` (`StreamListView`: `.task(id: (current ?? request).id)`,
Autostart-Merker); Create `Packages/PlayerCore/Sources/PlayerCore/Playback/AutostartGate.swift`;
Test `AutostartGateTests.swift` (4 neue)

**Interfaces (Produces):** `AutostartGate.shouldStart(requestID: String, alreadyStarted: Set<String>, isRebuild: Bool) -> Bool`.
Die Lade-Aufgabe hängt an der ID der **aktuellen** Folge und lädt deren Quellen.

- [ ] **Steps;** Commit „Quellenliste: nach der automatischen Folge stehen deren Quellen da“.

### Task 3.5: Kleine Player-Fehler

**Befunde:** W-B-2, W-B-5, W-B-7, W-B-10, W-B-12, W-A-5, W-A-7 · **Risiko:** gering je Punkt

**Files:** Modify `App/Sources/Views/PlayerScreen.swift`, `App/Sources/StreamPrefetcher.swift`,
`App/Sources/Views/Player/PlayerScrub.swift`, `Packages/PlayerCore/Sources/PlayerCore/Progress/NextEpisode.swift`,
`Playback/SkipPolicy.swift`, `Playback/PlaybackRecovery.swift`, `App/Sources/Playback/DiskCacheProxy.swift`;
Tests in den vorhandenen Dateien (9 neue)

- [ ] `onDisappear` gibt Scrobble und Vorlader immer frei, unabhängig von `tracksOpen` (W-B-2).
- [ ] Sammelsprung: Die abgelöste Aufgabe prüft, ob sie noch die aktuelle ist, bevor sie das Ziel löscht (W-B-5).
- [ ] Spul-Vorschau blendet das alte Bild aus, sobald das Ziel mehr als einen Schritt abweicht (W-B-7).
- [ ] Nach Staffel 0 ist die nächste Folge die nächste in Staffel 0, sonst keine (W-B-10).
- [ ] „Überspringen“ springt nie rückwärts: Ziel = `max(position, min(segment.end, duration − 1))` (W-B-12).
- [ ] Unbekannte Transportfehler werden nicht 8 h gemerkt, nur klassifizierte (W-A-5).
- [ ] Ein Abbruch während der Cache-Probe sperrt die Quelle nicht (W-A-7).
- [ ] Commit „Player: sieben kleine Fehler“.

### Task 3.6: Quellen-Parser und Addon-Identität

**Befunde:** A-A-1, A-A-2, A-A-9, A-A-13, A-A-14, A-A-16 · **Risiko:** gering · **Profile:** `InstalledAddon` bekommt
`manifestID` und `instanceID` (Standard: aus der Adresse abgeleitet)

**Files:** Modify `Ranking/StreamTraits.swift`, `Addons/AddonClient.swift`, `Addons/StremioModels.swift`,
`Addons/AddonSearch.swift`; Test `StreamTraitsTableTests.swift` (Tabelle mit 40 echten Zeilenformen als
`@Test(arguments:)`), `AddonIdentityTests.swift` (4 neue)

- [ ] Auflösung: eine ausdrückliche Zeilenzahl (`2160p`, `1080p`) schlägt „UHD“/„4K“ im Namen.
- [ ] Kanäle: `5.1`, `7.1`, `2.0` zählen nicht, wenn direkt eine Größeneinheit folgt.
- [ ] Dienst-Erkennung nur an Wortgrenzen und nicht innerhalb von eckigen Qualitätsangaben.
- [ ] Addons werden über `instanceID` unterschieden, nie über den Anzeigenamen.
- [ ] Werte in `extra` nach der Stremio-Regel kodieren.
- [ ] Commit „Quellen: Auflösung, Kanäle und Dienst richtig erkannt; Addons über ihre ID“.

### Task 3.7: Quellensuche zeigt, was da ist

**Befunde:** A-A-4, A-A-6, A-A-7, A-A-17 · **Risiko:** mittel

**Files:** Modify `App/Sources/AppModel.swift` (`streams`, `streamsAllEmptyAt`), `App/Sources/AppModel+StreamSearch.swift`,
`App/Sources/AppModel+StreamRevalidate.swift`, `App/Sources/Views/DetailViews.swift`;
Create `Packages/PlayerCore/Sources/PlayerCore/Store/EmptyPause.swift`; Test `EmptyPauseTests.swift` (5 neue)

**Interfaces (Produces):** `EmptyPause` zählt aufeinanderfolgende leere Suchen über **verschiedene** Titel; erst ab 3
in 60 s pausiert das Vorladen, und nie die Suche einer geöffneten Seite. Die Quellenliste übernimmt beim Beitritt den
vorhandenen Zwischenstand (`onChange(initial: true)`). Plaketten der Detailseite entstehen aus dem ersten
Zwischenstand und werden beim Endstand höchstens ergänzt, nie entfernt (kein Springen). `streamsForAutoplay` wartet
höchstens 3 s auf die Erneuerung.

- [ ] **Steps;** Commit „Quellensuche: Zwischenstände sofort, Plaketten aus der ersten Antwort“.

### Task 3.8: Zwei billige Performance-Punkte

**Befunde:** [04 §6.5], [04 §6.2] · **Risiko:** gering

**Files:** Modify `App/Sources/Views/RowViews.swift` (`route(for:)`), `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift`
(`parseSize`: Regex einmal), `App/Sources/AppModel+SourceOrder.swift`

- [ ] „Weiterschauen“ wird einmal je Reihe berechnet (`[String: Route]`), nicht je Karte.
- [ ] `RankedStream` (Stream plus einmal berechnete `StreamTraits`) wird durch Ordnen, Beste Wahl und Plaketten gereicht.
- [ ] Vorher/nachher über `metric: streams.order` und den `hitch`-Zähler vergleichen.
- [ ] Commit „Weniger Arbeit je Fokusschritt und je Quellenliste“.

### Build 3 – Deploy-Checkliste

**Vor dem Build:** `test` grün; Messwerte aus Build 1 und 2 notiert (`start.usable`, `streams.order`, `player.firstFrame`).

**Am Gerät prüfen**
- [ ] Serie: Folge 1 starten, Folge 2 startet automatisch, Player schließen → Liste zeigt Quellen von Folge 2.
- [ ] Quelle mit abgelaufenem Link (ältere Sitzung fortsetzen) → nach der Reparatur stimmen Tonspur und Untertitel.
- [ ] Titel mit Kommentarspur in Dolby Digital → Hauptton wird gewählt.
- [ ] Profil A → B wechseln, direkt nach dem Start: Fortschritt von A erscheint nicht in B.
- [ ] Profil auf Englisch stellen → Detailseite sofort englisch.
- [ ] Detailseite eines Films: Plaketten erscheinen mit dem ersten Addon.
- [ ] Player mit offenem Ton-Panel über „Zurück“ verlassen → Vorladen funktioniert danach.
- [ ] „Überspringen“ 5 s vor dem Dateiende.

**Erwartete Fern-Log-Zeilen:** `player: Startschritte placeholderCheck,selectAudio,…` einmal je Sitzung, nach
Reparatur `player: Startschritte selectAudio(restore),play`; `profil: Ergebnis verworfen (Epoche)` nur beim
schnellen Wechsel; `metric: detail.badges <ms>` deutlich unter dem Wert aus Build 1.

**Rückfall-Auslöser:** Wiedergabe startet ohne Ton oder mit falscher Spur; Quellenliste bleibt leer.

---

## Build 4: Fokus-Fehler und Design-Infrastruktur

### Task 4.1: Fokus und Navigation

**Befunde:** F-A-1 bis F-A-8, F-A-11, F-A-12, F-B-2, F-B-3, F-B-7, F-B-8, F-B-9, A-B-3, A-B-5, A-B-6, A-B-8, A-B-10, A-B-11 · **Risiko:** mittel; jede
Änderung einzeln am Gerät prüfbar

**Files:** Modify `App/Sources/Views/HomeHero.swift`, `HomeView.swift`, `RowViews.swift`, `TorBoxFilesRow.swift`,
`TabBarGuard.swift`, `Home/AddRowBrowser.swift`, `Home/HomeManagerView.swift`, `PlayerApp.swift`, `PersonView.swift`,
`GenrePageView.swift`, `Settings/ServiceSettings.swift`, `Settings/FusionKitSettings.swift`, `ImagePipeline.swift`;
`Packages/PlayerCore/Sources/PlayerCore/Models/HomeManager.swift`, `Models/PosterSize.swift` (`HomeRowPhase`);
Create `Packages/PlayerCore/Sources/PlayerCore/Models/NavigationGuard.swift`; Tests (10 neue)

**Interfaces (Produces):**
- `NavigationGuard.mayPush(startedAt: NavigationStamp, now: NavigationStamp) -> Bool`. `NavigationStamp` enthält Tab
  und Pfadlänge. „Abspielen“ im Hero und in der TorBox-Reihe navigiert nach dem `await` nur, wenn der Stempel gleich ist.
- `HomeRowPhase` gilt auch für Collection-Reihen; `focusAfterLoad` liefert das Übergabeziel.
- `HomeManager.Outcome.focus` wird von allen Kontextmenü-Aktionen der Startseite angewendet.
- Reihen entdoppeln ihre Einträge nach `(type, id)`; `ForEach`-IDs enthalten den Typ.
- Scheitert die Hero-Quelle, bleibt der Hero-Rahmen mit einer Statuskachel stehen und versucht es beim nächsten
  `catalogWake` erneut; das Layout wechselt nicht.
- `pickedProfile` wird beim Anlegen eines Profils aus den Einstellungen gesetzt; die Profilwahl erscheint nur beim Start.
- Bedingte Zeilen (Handy-Seite, Login, Icon-Satz, Profil löschen) bleiben im Baum und werden nur deaktiviert dargestellt.
- „Heute neu“, Hero-Folien und Kit-Reihen mit Datumsfilter rechnen bei `catalogWake` und beim Tageswechsel neu
  (`Upcoming.days(today:)` bekommt das aktuelle Datum, nicht das des letzten Zerlegens). Der Kalender holt die laufende
  Staffel auch dann, wenn nur die letzte ausgestrahlte Folge im Fenster liegt.
- `ImagePipeline`: Netzfehler und Zeitüberschreitungen werden 20 s gemerkt, nur 404/410 fünf Minuten; sichtbare
  Kacheln versuchen es bei `NWPath` „wieder verbunden“ erneut.

- [ ] **Steps:** je Befund ein Commit, damit sich ein Rückfall am Gerät einzeln zurücknehmen lässt.

### Task 4.2: Modell `Look` mit der Vorlage „Mein Look“ und Migration

**Befunde:** D-28, D-1 · **Risiko:** mittel · **Profile:** neues Feld `look`; fehlt es, entsteht es aus den alten
Feldern. Die alten Felder werden weiter geschrieben.

**Files:**
- Create: `Packages/PlayerCore/Sources/PlayerCore/Models/Look.swift`, `Models/LookOptions.swift`,
  `Models/LookPresets.swift`, `Models/LookMigration.swift`, `Models/LookMetrics.swift`
- Modify: `Models/Profile.swift` (Feld, CodingKey, `decodeLenient`)
- Test: `Tests/PlayerCoreTests/LookTests.swift`, Fixture `Fixtures/konfigurator-export.json` (Kopie von
  `docs/design/konfigurator/export.json`)

**Interfaces (Produces):** wie in `04-system-design.md` §8.1 bis §8.2, mit diesen Abweichungen:
- `public enum LookPresetID: String { case appleTV = "appletv" }`. Anzeigename „Mein Look“. Ein anderer Rohwert
  (`edel`, `infuse`, `kino`, `streaming`, Unbekanntes) wird beim Dekodieren zu `.appleTV` und landet im
  `DecodeReport`.
- `LookPreset.values(.appleTV) -> LookValues` liefert genau `export.json`:
  - `global`: navigation `oben`, clock `false`, settingsLayout `spalten`, accent `weiss`, background `schwarz`,
    typeScale `standard`, typeCharacter `neutral`, motion `standard`
  - `home`: heroStyle `vollbild`, heroInfo `standard`, heroTitle `logo`, backdropFollowsFocus `true` (user decision 26.11.), cardShape
    `querformat`, cardSize `gross`, corners `rund`, rowSpacing `luftig`, rowTitle `standard`, cardTitles `immer`,
    expandPosters `false`, focusScale `kraeftig`, focusBorder `keiner`, focusShadow `tief`, focusGlow `true`
  - `detail`: layout `kino`, descriptionLines `2`, cast `kreise`, badgeStyle `text`, ratingStyle `text`,
    sourceList `kompakt`
  - `player`: controlBar `minimal`, badges `aus`, timeDisplay `rest`, trackPanel `unten`, upNext `karte`,
    stillWatching `dialog`
- Options-Enums mit genau den Rohwerten aus Anhang A (35 Optionen). `descriptionLines` ist ein `Int`-Enum (2, 3, 5).
- `Look.migrated(from:player:sources:)` rechnet Abweichungen gegen `.appleTV` (nicht `.edel`). Zuordnungstabelle wie
  `04` §8.2.4.
- `LookMetrics` (reine Tabellen, Punkte bei 1920 × 1080):

  | Funktion | Werte |
  |---|---|
  | `focusScale(_:)` | keine 1,0 · dezent 1,05 · kraeftig 1,12 |
  | `cornerRadius(_:)` | eckig 0 · leicht 8 · weich 14 · rund 26; `rowRadius` = +4, `panelRadius` = +8 |
  | `rowSpacing(_:) -> (card: CGFloat, row: CGFloat)` | eng 16/36 · normal 24/48 · luftig 32/64 |
  | `cardSize(_:shape:) -> CGSize` | Grundmaß Poster 240 × 360, Querformat 440 × 248; Faktor klein 0,85 · mittel 1,0 · gross 1,2 |
  | `expandedWidth(height:)` | `height * 16 / 9` |
  | `typeScale(_:)` | kompakt 0,9 · standard 1,0 · gross 1,12 |
  | `motion(_:)` | `focus` 0 / 0,18 / 0,22 s · `fade` 0 / 0,24 / 0,38 s · `backdrop` 0 / 0,5 / 0,7 s · `expand` 0 / 0,25 / 0,3 s (aus / dezent / standard) |
  | `rest` | backdrop 350 ms · expand 500 ms · prefetch 700 ms (unabhängig von `motion`) |
  | `focusShadow(_:)` | keiner · weich Schwarz 45 %, Radius 20, y 18 · tief Schwarz 75 %, Radius 35, y 34 |
  | `focusBorder` | 4 pt breit, 4 pt Abstand zur Karte |
  | `contentLeading(_ navigation:)` | seitenleiste 150 · oben 80 |
  | `descriptionLines(_:)` | 2 · 3 · 5 |

- [ ] **Step 1: Tests** (10 neue): die acht aus `04-system-design.md` §8.5 mit zwei Änderungen:
  `everyPresetResolvesCompletely` heißt `appleTVPresetResolvesCompletely`, `configuratorExportMatchesEdelPreset`
  heißt `configuratorExportMatchesAppleTVPreset` (liest die Fixture, vergleicht alle 35 Werte). Neu:
  `unknownPresetIDFallsBackToAppleTV` (`"preset":"edel"` → `.appleTV`, Bericht nennt `preset`) und
  `lookMetricsMatchConfigurator` (jede Zeile der Tabelle oben).
- [ ] **Step 2:** Tests laufen rot (`swift test --filter LookTests`), Typen fehlen.
- [ ] **Step 3:** Typen und Tabellen umsetzen.
- [ ] **Step 4:** `swift test` grün; Zahl der Tests +10.
- [ ] **Step 5:** Commit „Aussehen: Modell mit der Vorlage Mein Look und Abweichungen“.

### Task 4.3: Import aus dem Konfigurator

**Befunde:** [04 §8.4] · **Risiko:** gering

**Files:** Create `Packages/PlayerCore/Sources/PlayerCore/Models/LookImport.swift`; Modify `Phone/PhoneImportDetect.swift`,
`Phone/PhoneInput.swift` (Feld „Aussehen aus dem Konfigurator“, Rückmeldung), `App/Sources/AppModel.swift` (`apply`);
Test `LookImportTests.swift` (7 neue)

**Interfaces (Produces):** `LookImport.parse(_ data: Data) throws -> (look: Look, report: DecodeReport)`;
Fehler `LookImport.Failure.notAnExport`, `.foreignSchema(String)`; `PhoneCommand.look(Look)` mit
`Sensitivity.plain`; `PhoneImportDetect` erkennt `"schema":"player.appearance.preset"`.
- Das Feld `preset` der Datei wird nicht übernommen. `values` werden gegen `.appleTV` in Abweichungen umgerechnet. So
  lässt sich auch ein Export aus einer anderen Konfigurator-Vorlage einspielen; die App zeigt danach „Mein Look ·
  angepasst“.
- Rückmeldung auf der Handy-Seite: „Aussehen übernommen · <n> Abweichungen“ und, falls nötig, „<k> Werte kannte diese
  App-Version nicht“.

- [ ] **Step 1: Tests:** die sechs aus §8.5/§8.4 plus `importFromOtherPresetBecomesOverrides` (Edel-Beispiel aus
  `07` §5.2 → 26 Abweichungen gegenüber Apple TV, `preset == .appleTV`).
- [ ] **Step 2 bis 4:** rot, umsetzen, grün.
- [ ] **Step 5:** Commit „Aussehen: JSON aus dem Konfigurator über die Handy-Seite einspielen“.

### Task 4.4: Laufzeit-Theme

**Befunde:** D-3, D-9, D-12, D-13, D-15, D-17, D-27 · **Risiko:** mittel (viele Views, aber ohne sichtbare Änderung,
solange die Werte gleich bleiben)

**Files:**
- Create: `App/Sources/Views/Design/ThemeValues.swift`, `Design/ThemeEnvironment.swift`
- Modify: `App/Sources/Views/Design/Theme.swift` (statische Werte werden zu `ThemeValues.standard`),
  `App/Sources/PlayerApp.swift` (`.environment(\.theme, ThemeValues.make(look.resolved()))`)

**Interfaces (Produces):**
- `struct ThemeValues: Equatable { var color: Colors; var type: TypeScale; var space: Spacing; var radius: Radii; var elevation: Elevation; var focus: FocusStyle; var motion: Motion }`
  mit den Tokens aus `07-design-analyse.md` §3 und den Zahlen aus `LookMetrics` (Task 4.2).
- `static func make(_ values: LookValues, reduceMotion: Bool, reduceTransparency: Bool) -> ThemeValues`
- `extension EnvironmentValues { var theme: ThemeValues }`

**Farben je Akzent** (`accent` / `accent.on`):

| `global.accent` | `accent` | `accent.on` |
|---|---|---|
| champagner | `#D4B87A` | `#17140C` |
| weiss | `#F2F1EC` | `#111111` |
| eisblau | `#8FC7FF` | `#06121D` |
| blau | `#3B82F6` | `#FFFFFF` |
| rot | `#E5383B` | `#FFFFFF` |
| koralle | `#FF7A59` | `#1D0A04` |
| salbei | `#9FC5A8` | `#0B160E` |
| violett | `#A78BFA` | `#120A26` |

**Farben je Hintergrundton** (`bg.base` / `bg.surface` / `bg.raised`; `bg.raised` = `bg.surface` mit 5 % Weiß
überlagert, bei Graphit der Wert aus `07` §3.1). Verläufe (`image.gradient.*`, `bg.scrim`) laufen in `bg.base` aus.

| `global.background` | `bg.base` | `bg.surface` | `bg.raised` |
|---|---|---|---|
| schwarz | `#000000` | `#131314` | `#1F1F20` |
| graphit | `#0B0C0E` | `#17191D` | `#22252B` |
| tinte | `#070B14` | `#111827` | `#1E2432` |
| warm | `#0E0B08` | `#1C1713` | `#27231F` |

Feste Farben, unabhängig von der Wahl: `fg.primary` `#F4F3EF`, `fg.secondary` Weiß 68 %, `fg.tertiary` Weiß 45 %,
`fg.onFocus` `#111111`, `focus.fill` `#FFFFFF`, `bg.row` Weiß 8 %, `bg.scrim` `bg.base` 78 %.

**Schrift** (Größen × `typeScale`; Gewicht und Laufweite je `typeCharacter` neutral / editorial / technisch):

| Rolle | Größe | Gewicht | Laufweite | Zeilenhöhe |
|---|---|---|---|---|
| `display` | 76 | 700 / 300 / 800 | −1 % / −2,5 % / 0 | 1,02 |
| `pageTitle` | 48 | 600 / 500 / 700 | 0 / +0,5 % / +1 % | 1,1 |
| `title` | 38 | 600 / 500 / 700 | 0 / +0,5 % / +1 % | 1,15 |
| `sectionTitle` | 34 | 600 | 0 | 1,15 |
| `sectionLabel` | 27 | 500, Farbe Weiß 70 % | +2 % | 1,2 |
| `sectionLarge` | 44 | 700 | −1 % | 1,1 |
| `body` / `bodyEmphasis` | 29 | 400 / 600 | 0 | 1,32 |
| `meta` | 26 | 500, Farbe `fg.secondary` | +1 % / +3 % / +5 % | 1,25 |
| `badge` | 23 | 700 | +4 % | 1 |

Regel: Der Konfigurator zeichnet Namen unter Porträts und lange Quellentexte mit 21 bis 23 pt. In der App bekommen sie
`meta` (26 pt); nur Plaketten bleiben bei 23 pt (`07` §3.2: Lesetext nie unter 26).

- [ ] **Step 1:** `ThemeValues.standard` liefert exakt die heutigen Werte; ein Build mit Bildschirmfoto-Vergleich
  (siehe Roadmap) oder Sichtprüfung zeigt keine Änderung.
- [ ] **Step 2:** Test in `PlayerCore` für die reinen Zahlen (`lookMetricsMatchConfigurator` aus 4.2 deckt sie ab);
  die Farbtabellen liegen in der App und werden in 4.5 am Gerät geprüft.
- [ ] **Step 3:** Views der Einstellungen lesen die Umgebung (sie sind schon vollständig auf Tokens).
- [ ] **Step 4:** Commit „Theme zur Laufzeit aus dem Aussehen des Profils“.

### Task 4.5: Einstellungen „Aussehen“: alle 35 Optionen

**Befunde:** D-14, D-19, D-28 · **Risiko:** gering

**Files:** Modify `App/Sources/Views/Settings/AppearanceSettings.swift`, `Packages/PlayerCore/Sources/PlayerCore/Models/SettingsTree.swift`,
`Models/SettingsSummary.swift`; Create `App/Sources/Views/Settings/LookHeaderRow.swift`, `LookOptionRows.swift`,
`Packages/PlayerCore/Sources/PlayerCore/Models/LookOptionCatalog.swift`; Test `LookOptionCatalogTests.swift` (5 neue)

**Interfaces (Produces):**
- `LookOptionCatalog.all: [LookOptionEntry]` mit 35 Einträgen in der Reihenfolge von Anhang A.
  `LookOptionEntry { area: LookArea; group: String; key: String; label: String; help: String; choices: [(raw: String, label: String)]; availableFrom: LookBuild }`.
  `label`, `help` und die Wertnamen sind wörtlich die deutschen Texte aus Anhang A.
- `LookOptionCatalog.isEnabled(_ key: String, in values: LookValues) -> (enabled: Bool, reason: String?)` für die
  Abhängigkeiten unten.
- `enum LookBuild { case b4, b5a, b5b, b5c }`.

Aufbau der Seite:
- [ ] Oberste Zeile „Mein Look“ mit Wert „Apple TV“ oder „angepasst · <n>“. Aktion „Alles auf Apple TV
  zurücksetzen“ mit Rückfrage. Es gibt keine Vorlagenwahl.
- [ ] Darunter vier Bereiche wie im Konfigurator (Startseite & Hero, Detailseite, Player, Navigation &
  Einstellungen) mit den Gruppenköpfen aus Anhang A. Jede Option ist eine Zeile mit Wert; Auswahl öffnet die Liste
  aller Werte. Die Zeilenbeschreibung ist der Kurztext. Akzentfarbe und Hintergrundton zeigen ein Farbfeld je Wert.
- [ ] Abweichende Zeilen tragen einen Punkt in `accent`; das Kontextmenü (lange drücken) bietet „Auf Apple TV
  zurücksetzen“.
- [ ] Eine Änderung wirkt sofort, ohne Neustart. Der Fokus bleibt auf der geänderten Zeile.

Abhängigkeiten (`isEnabled`):
- [ ] `home.focusGlow = true` → `corners`, `focusScale`, `focusBorder`, `focusShadow` deaktiviert mit „Bei Glanz
  bestimmt tvOS Form, Größe und Schatten der Karte.“ (Systemstil `.buttonStyle(.card)`, `07` §4.2).
- [ ] `focusScale = keine`, `focusBorder = keiner`, `focusShadow = keiner`, `focusGlow = false` → Hinweis unter der
  Gruppe „Ohne Fokus-Zeichen setzt die App einen weißen Rahmen.“ `ThemeValues.make` erzwingt dann `focusBorder = weiss`.
- [ ] System „Bewegung reduzieren“ an → Hinweis bei `motion` und `expandPosters`: „Das System reduziert Bewegung; diese
  Einstellung wirkt erst, wenn das aus ist.“
- [ ] Optionen, deren Umsetzung in einem späteren Build kommt, sind sichtbar, aber deaktiviert mit „kommt mit Build
  5a/5b/5c“ (Spalte „ab Build“ in Anhang A). Ab Build 4 wirksam: `accent`, `background`, `typeScale`,
  `typeCharacter`, `motion` (über das Theme) sowie `navigation`, `cardSize`, `expandPosters`, `trackPanel` (über die
  bestehenden Felder, Zuordnung `04` §8.2.4).
- [ ] Die neun Kategoriefarben weichen der neutralen Symbolkachel.

Tests:
- [ ] `catalogHasAllConfiguratorOptions` (35 Schlüssel, gleich den Feldern von `LookValues`),
  `catalogChoicesMatchEnums` (jede Wahl ist ein gültiger Rohwert), `glowDisablesCardShapeOptions`,
  `noFocusSignForcesWhiteBorder`, `summaryCountsOverrides` („Mein Look · angepasst · 3“).
- [ ] Commit „Einstellungen: Aussehen mit allen Optionen des Konfigurators“.

### Build 4 – Deploy-Checkliste

**Vor dem Build:** `test` grün; `docs/design/konfigurator/export.json` liegt im Repo (Apple-TV-Werte).

**Am Gerät prüfen**
- [ ] Hero „Abspielen“ drücken und sofort eine Kachel öffnen → kein später Sprung.
- [ ] Reihe über das Kontextmenü ausblenden, löschen, nach oben schieben → Fokus landet sichtbar auf einer Reihe.
- [ ] Kit-Collection-Reihe während des Ladens fokussieren → Fokus geht auf die erste Kachel über.
- [ ] Zweites Profil in den Einstellungen anlegen → man bleibt in den Einstellungen.
- [ ] WLAN kurz aus und an → graue Kacheln füllen sich.
- [ ] Aussehen: alle acht Akzentfarben und alle vier Hintergrundtöne durchschalten → die Einstellungsseite färbt sich
  sofort um, der Fokus bleibt auf der Zeile.
- [ ] Schriftgröße und Schriftcharakter je einmal durchschalten → nichts wird abgeschnitten.
- [ ] Alle 35 Optionen sind sichtbar; die späteren tragen „kommt mit Build 5a/5b/5c“.
- [ ] „Alles auf Apple TV zurücksetzen“ → Zeile „Mein Look“ zeigt „Apple TV“.
- [ ] JSON aus dem Konfigurator (beliebige Vorlage) über die Handy-Seite einspielen → Werte stimmen, Anzeige
  „angepasst · <n>“.
- [ ] Zurück auf Build 3 und wieder vor: Profile laden, das Aussehen des alten Builds ist unverändert.

**Erwartete Fern-Log-Zeilen:** `navigation: später Sprung verworfen` nur im Testfall; `aussehen: Mein Look ·
<n> Abweichungen`; `aussehen: Import · ignoriert <n>`.

**Rückfall-Auslöser:** Fokus bleibt auf der Startseite hängen; Einstellungen lassen sich nicht bedienen.

---

## Builds 5a, 5b, 5c: Design-Umbau der Bildschirme

Jede Option wird **mit allen Werten** gebaut, die Anhang A nennt; die Apple-TV-Werte sind der Standard. Weil das drei
Bereiche mit eigener Fokus-Führung betrifft, ist der frühere Build 5 in drei Builds geteilt. Jeder lässt sich einzeln
am Gerät prüfen und zurücknehmen:

| Build | Inhalt | Tasks | Optionen |
|---|---|---|---|
| 5a | Startseite, Navigation, Einstellungs-Layout | 5.1, 5.2, 5.6 | 15 `home.*`, `navigation`, `clock`, `settingsLayout` |
| 5b | Detailseite, Quellenliste | 5.3 | 6 `detail.*` + 2 eigene (`episodes`, `titleArt`) |
| 5c | Player, übrige Bildschirme, Barrierefreiheit | 5.4, 5.5 | 6 `player.*` |

Ruling [C]: Die auf tvOS aufwendigen Werte (`heroStyle = karussell`, `settingsLayout = kacheln`,
`badgeStyle = logos`, `backdropFollowsFocus`, `expandPosters`) werden gebaut, weil der Nutzer alle Optionen will. Jeder
bekommt die unten genannte Absicherung. Kosten bei Fehleinschätzung: ein Rückfall je Build, nicht der ganze Umbau.

## Build 5a: Startseite, Navigation, Einstellungs-Layout

### Task 5.1: `ThemeCard` und Reihen

**Befunde:** D-6, D-8, D-16, D-23, D-24, Q-10, Q-26 · **Risiko:** hoch (Fokus der Startseite)

**Files:** Create `App/Sources/Views/Design/ThemeCard.swift`, `Design/ImageScrim.swift`, `Design/ThemeProgressBar.swift`,
`Design/WatchedMark.swift`; Modify `App/Sources/Views/RowViews.swift`, `TilePosterImage.swift`, `CalendarView.swift`,
`QualityBadges.swift`; `Packages/PlayerCore/Sources/PlayerCore/Models/FocusHeadroom.swift` (Platz aus `LookMetrics`),
Create `Packages/PlayerCore/Sources/PlayerCore/Models/CardLayout.swift`; Tests (12 neue)

**Interfaces (Produces):**
- `ThemeCard(kind:title:titleMode:content:)` mit Fokus-Stil aus `theme.focus` (`scale`, `border`, `shadow`, `glow`).
  Bei `glow == true` nutzt die Karte `.buttonStyle(.card)` und ignoriert die drei anderen Werte. Jede Karte trägt
  `accessibilityLabel` (Titel) und `accessibilityValue` (Jahr, Fortschritt, gesehen).
- `CardLayout.shape(for row: HomeRowKind, option: LookCardShape) -> CardShape`: `poster` → immer Poster;
  `querformat` → immer Querformat; `mischung` → Querformat für „Weiterschauen“, sonst Poster.
- `CardLayout.frame(shape:size:expanded:) -> CGSize` aus `LookMetrics.cardSize`; Querformat groß = 528 × 298.

Varianten:
- [ ] `cardShape` poster / querformat / mischung wie oben. Querformat nutzt Szenenbild, sonst Poster mit Verlauf.
- [ ] `cardSize` klein / mittel / gross (Faktor 0,85 / 1,0 / 1,2).
- [ ] `corners` eckig / leicht / weich / rund (0 / 8 / 14 / 26) für Karten, Vorschaubilder, Folgenbilder.
- [ ] `rowSpacing` eng / normal / luftig (Karte↔Karte 16 / 24 / 32, Reihe↔Reihe 36 / 48 / 64).
- [ ] `rowTitle` dezent (`sectionLabel` 27) / standard (`sectionTitle` 34) / gross (`sectionLarge` 44); Abstand
  zur Reihe 16.
- [ ] `cardTitles` immer / fokus / aus. Bei „fokus“ bleibt der Platz reserviert (Deckkraft 0 → 1 mit `motion.fade`),
  die Reihenhöhe ändert sich nie. Bei „aus“ entfällt der Platz für die ganze Reihe.
- [ ] `focusScale` 1,0 / 1,05 / 1,12; `focusBorder` keiner / weiß / Akzent (4 pt, 4 pt Abstand); `focusShadow` keiner /
  weich / tief; `focusGlow` Systemstil.
- [ ] `expandPosters`: Nach `rest.expand` (500 ms) Ruhe wird das fokussierte Poster `height × 16/9` breit, Übergang
  `motion.expand`. Die Karte behält ihre Identität; die Reihe scrollt so, dass die Karte ganz sichtbar bleibt. Aus bei
  „Bewegung reduzieren“.

Tests (`PlayerCore`):
- [ ] `FocusHeadroom` für die drei Skalierungen × drei Größen: nichts ragt in die Nachbarreihe (9).
- [ ] `cardShapeMixingUsesLandscapeOnlyForContinueWatching`, `expandedPosterWidthIs16by9`,
  `focusTitleModeKeepsRowHeight` (3).
- [ ] Schattenbetrieb entfällt hier; stattdessen ein Diagnose-Schalter „alte Karte“, der einen Build lang bleibt.
- [ ] Commit je Option-Gruppe (Form/Größe, Ecken/Abstände/Titel, Fokus, Aufklappen).

### Task 5.2: Hero-Varianten

**Befunde:** F-A-4, F-A-12, D-9 · **Risiko:** hoch

**Files:** Create `App/Sources/Views/Home/HeroLayout.swift`, `Home/HeroFullscreen.swift`, `Home/HeroBanner.swift`,
`Home/HeroCarousel.swift`, `Home/HeroInfo.swift`; Modify `App/Sources/Views/HomeHero.swift`, `HomeView.swift`;
`Packages/PlayerCore/Sources/PlayerCore/Models/HomeTopEdge.swift` (Maße je Stil); Tests (7 neue)

**Interfaces (Produces):** `HomeTopEdge.rowsTop(style: LookHeroStyle, info: LookHeroInfo) -> CGFloat`;
`HeroLayout` wählt je `heroStyle` genau eine View-Variante (keine `if`-Ketten in einer View).

Varianten (Maße bei 1920 × 1080, links `contentLeading`):
- [ ] `heroStyle = vollbild`: Bild füllt den Bildschirm hinter den Reihen, `image.gradient.leading` und `.bottom`.
  Info-Block oben bei 330 (minimal) / 210 (standard) / 150 (ausführlich); erste Reihe bei 640 (minimal) bzw. 700.
- [ ] `banner`: eigene Fläche von `contentLeading` bis 80 vom rechten Rand, oben 130, Höhe 460, Radius `panelRadius`;
  Info unten links 56/44 im Banner; erste Reihe bei 640.
- [ ] `karussell`: Fläche 1320 × 460 bei oben 130; rechts daneben (Abstand 32) der nächste Titel angeschnitten.
  Links/rechts auf dem Hero-Knopf wechselt den Titel (Übergang `motion.backdrop`); nach unten geht der Fokus in die
  erste Reihe. Eigene `focusSection`; der angeschnittene Titel ist nicht fokussierbar. Info um 0,8 verkleinert, Breite
  700.
- [ ] `aus`: kein Hero; die erste Reihe beginnt unter der Navigation.
- [ ] `heroInfo = minimal`: Logo/Titel und Knöpfe. `standard`: zusätzlich Metazeile (Jahr · Laufzeit · Freigabe ·
  Genre), Bewertungszeile im `ratingStyle`, Beschreibung 2 Zeilen, Breite 860. `ausfuehrlich`: zusätzlich Plaketten
  (4K, Dolby Vision, Atmos, Kanäle) im `badgeStyle`.
- [ ] `heroTitle = logo`: Titel-Logo aus den Metadaten, ohne Logo der Titel als `display`; `text`: immer `display`.
- [ ] `backdropFollowsFocus = true`: Nach `rest.backdrop` (350 ms) Ruhe auf einer Karte wechselt das Hero-Bild auf
  diesen Titel (Überblendung `motion.backdrop`). Höchstens ein Bild-Abruf je Ruhepause, der vorige wird abgebrochen;
  Bild in Bildschirmgröße aus der `ImagePipeline`. Gilt bei `vollbild`, `banner` und `karussell`.
- [ ] Ruhezeiten gestaffelt: Hintergrund 350 ms, Aufklappen 500 ms, Vorladen 700 ms (`theme.motion.rest`).

Tests:
- [ ] `HomeTopEdge` je Hero-Stil (4): Fokus von der ersten Reihe nach oben landet im Hero-Knopf; bei `aus` in der
  Navigation.
- [ ] `rowsTopPerInfoLevel`, `carouselWrapsAtEnds`, `backdropRequestsAtMostOncePerRest` (3).
- [ ] Commit je Hero-Stil, dann Info und Titel, dann Hintergrund nach Fokus.

### Task 5.6: Navigation, Uhr, Einstellungs-Layout

**Befunde:** D-19, D-28 · **Risiko:** mittel

**Files:** Modify `App/Sources/PlayerApp.swift` (Hauptnavigation), `App/Sources/Views/Settings/SettingsView.swift`;
Create `App/Sources/Views/Design/ClockOverlay.swift`, `Settings/SettingsTilesView.swift`, `Settings/SettingsListView.swift`;
Tests (3 neue)

- [ ] `navigation = seitenleiste`: Symbolleiste links, Inhalt beginnt bei 150; `oben`: Leiste mit Namen oben, Inhalt
  bei 80. Beide gibt es schon; sie lesen jetzt nur noch Tokens.
- [ ] `clock = true`: Uhrzeit oben rechts (rechts 80, oben 56), `meta`-Rolle 27 pt × `typeScale`, Gewicht 500,
  Weiß 75 %, Ziffern gleich breit; aktualisiert zur vollen Minute; im Player ausgeblendet.
- [ ] `settingsLayout = spalten`: heutige zwei Spalten. `kacheln`: Titel „Einstellungen“ (`pageTitle`), darunter ein
  Raster mit 4 Spalten, Abstand 26, Kachelhöhe 230, Radius `cornerRadius + 6`; Auswahl öffnet die Kategorie als eigene
  Seite. `liste`: eine Liste mit Kategorie-Köpfen, Kategorien untereinander.
- [ ] Tests: `settingsTreeIsSameForAllLayouts` (gleiche Zeilen in jedem Layout), `clockTextUsesLocale24h`,
  `contentLeadingFollowsNavigation`.
- [ ] Commit „Navigation, Uhr und Einstellungs-Layout nach Aussehen“.

### Build 5a – Deploy-Checkliste

**Vor dem Build:** `test` grün; Diagnose-Schalter „alte Karte“ vorhanden; in Task 4.5 stehen die 5a-Optionen auf
„aktiv“.

**Am Gerät prüfen:**
- [ ] Jede `home.*`-Option einmal durch alle Werte schalten → Startseite folgt sofort, der Fokus bleibt auf derselben
  Karte.
- [ ] Schnelles Durchlaufen einer Reihe mit 40 Karten bei Querformat groß: kein Ruckeln, Fokus springt nicht.
- [ ] Fokus von der ersten Reihe nach oben landet im Hero-Knopf (alle vier Hero-Stile).
- [ ] Karussell: links/rechts wechselt Titel, unten geht in Reihe 1.
- [ ] Hintergrund nach Fokus an: beim Scrollen kein Bildwechsel, erst beim Ruhen.
- [ ] Glanz an: Ecken/Skalierung/Rahmen/Schatten in den Einstellungen deaktiviert.
- [ ] Navigation, Uhr und die drei Einstellungs-Layouts durchschalten.

**Erwartete Fern-Log-Zeilen:** `hero: Fokus-Hintergrund <id>` höchstens einmal je Ruhepause; `hitch`-Zähler je Minute
nicht höher als in Build 4.

**Rückfall-Auslöser:** Fokus springt oder hängt auf der Startseite (dann zuerst der Diagnose-Schalter, erst danach
der Rückfall auf Build 4).

---

## Build 5b: Detailseite

### Task 5.3: Detailseite

**Befunde:** D-7, D-20, D-21, D-22, D-10, Q-4 · **Risiko:** mittel

**Files:** `App/Sources/Views/DetailViews.swift` wird dabei geteilt in `Views/Detail/DetailView.swift`,
`Detail/DetailHeader.swift`, `Detail/DetailEpisodes.swift`, `Detail/DetailExtras.swift`, `Views/Streams/StreamListView.swift`,
`Streams/StreamRow.swift`, `Views/Search/SearchView.swift`; Create `Design/ThemeButton.swift`, `Design/RatingRow.swift`,
`Detail/DetailLayout.swift`, `Detail/CastRow.swift`; Modify `Design/ThemeBadge.swift`, `PersonView.swift`; Tests (4 neue)

- [ ] Die Aufteilung der Datei geschieht in einem eigenen Commit **ohne** inhaltliche Änderung (reines Verschieben),
  danach erst der Umbau.
- [ ] Hauptknopf „Abspielen“ als `ThemeButton(.primary)`, alle anderen `.secondary`; SF Symbols statt Unicode-Zeichen.

Varianten:
- [ ] `layout = links`: Inhalt links ab `contentLeading`, Bild mit `image.gradient.leading` und `.bottom`.
  `zentriert`: Inhalt mittig zwischen 260 und 260 vom Rand, Verlauf von unten (`bg.base` 100 % → 80 % bei 45 % →
  25 % oben); Besetzung unten links (Breite 860), Quellen unten rechts (Breite 760). `kino`: Bild vollflächig, Verlauf
  von unten (96 % → 50 % bei 30 % → 0 bei 55 %), Info unten links (Breite 900, unten 70).
- [ ] `descriptionLines` 2 / 3 / 5; Fokus auf die Beschreibung öffnet den vollen Text.
- [ ] `cast = kreise`: Porträt 150 × 150 rund, Name darunter (`meta`), Abstand 26. `karten`: 170 breit, Rechteck mit
  `cornerRadius`, Name und Rolle. `text`: eine Zeile „Mit A, B, C“ (`meta`). `aus`: keine Besetzung.
- [ ] `badgeStyle` (gilt für alle Plaketten über `ThemeBadge`; Höhe 38, Innenabstand 12, Rolle `badge`):
  `umriss` 2 pt Rand Weiß 60 %, Text Weiß 90 %; `gefuellt` Fläche Weiß 20 %; `text` ohne Fläche, Weiß 75 %, Gewicht
  600; `logos` weiße Fläche, Text `#111111`, Radius 5, kursiver selbst gesetzter Schriftzug (keine fremden Logos,
  keine Markenbilder). Im Player wird `logos` als `gefuellt` gezeigt.
- [ ] `ratingStyle = symbole`: Symbol + Zahl je Quelle. `text`: „IMDb 7,9   Tomatometer 92 %   Trakt 81 %“ als
  `meta`. `kacheln`: kleine Kacheln mit Quelle oben, Wert unten. Die Quellenfarben bleiben, aber als Tokens in
  `RatingRow`.
- [ ] `sourceList = kompakt`: eine Zeile je Quelle (Name, Plaketten, Größe rechts). `ausfuehrlich`: Zeile „Sofort
  verfügbar · Name · Größe“ und darunter der volle Addon-Text (`meta`, umbrechend). `karten`: Karte je Quelle mit
  Plakettenzeile und Text getrennt.

Nutzerwünsche vom Gerätetest Build 1 (23.11.), zwei eigene Optionen **zusätzlich** zu den 35 des Konfigurators
(nicht in `export.json`, die Vorlage „Apple TV“ und `configuratorExportMatchesAppleTVPreset` bleiben unverändert).
Sie stehen in `LookValues.detail` als additive Felder; fehlen sie, gilt der Standard (keine Formatänderung). In
„Aussehen“ (Task 4.5) erscheinen sie unter Detail nach den 6 Konfigurator-Optionen:
- [ ] `episodes` „Folgen“: `reihe` Nebeneinander (waagerechte Reihe, Karte mit Vorschaubild 16:9, Titel „1. Name“
  darunter, Beschreibung erst bei Fokus als `meta`, Gesehen-Markierung auf dem Bild), `liste` Untereinander (heute).
  Standard `reihe`. Die Staffelleiste bleibt darüber; Staffelwechsel setzt die Reihe auf die erste ungesehene Folge.
- [ ] `titleArt` „Titel oben“: `logo` Titel-Logo aus den Metadaten anstelle des Posters, ohne Logo das Poster;
  `poster` immer das Poster (heute). Standard `logo`. Gilt für Film und Serie. Bild nur über `RemoteImage`.
- [ ] Tests: `episodesRowStartsAtFirstUnwatched`, `titleArtFallsBackToPosterWithoutLogo`,
  `missingDetailExtrasDecodeToDefaults`.
- [ ] Tests: `detailLayoutPicksOneVariant`, `descriptionLineLimit`, `castTextJoinsNames`,
  `logoBadgesFallBackToFilledInPlayer`.

### Build 5b – Deploy-Checkliste

**Am Gerät prüfen:**
- [ ] Jede `detail.*`-Option durch alle Werte schalten, je einmal bei Film und Serie.
- [ ] Rückkehr vom Player: Fokus und Scroll-Lage der Quellenliste bleiben (`playerDismissed`).
- [ ] Kino-Layout über einem hellen Bild: Text lesbar.

**Rückfall-Auslöser:** Detailseite öffnet nicht oder Fokus erreicht die Quellenliste nicht → Build 5a.

---

## Build 5c: Player und übrige Bildschirme

### Task 5.4: Player-Oberfläche

**Befunde:** D-2, D-5, D-11, D-18, Q-27, Q-29 · **Risiko:** mittel

**Files:** Create `App/Sources/Views/Design/OverlayCard.swift`; Modify `App/Sources/Views/PlayerScreen.swift`,
`Player/PlayerScrub.swift`, `Player/PostPlayCard.swift`, `Player/SkipSegmentButton.swift`, `Player/PlayerInfoBadges.swift`,
`Player/PlayerTrackPanel.swift`, `Player/PlayerSidePanel.swift`, `Player/StillWatchingPrompt.swift`,
`Player/PlaybackErrorCard.swift`, `Player/PlayerStability.swift`;
`Packages/PlayerCore/Sources/PlayerCore/Playback/TrackPanelStyle.swift` (Zuordnung zu `player.trackPanel`);
Create `Packages/PlayerCore/Sources/PlayerCore/Playback/PlayerTimeText.swift`, `Playback/PlayerBadgeSet.swift`;
Tests (6 neue)

**Interfaces (Produces):**
- `PlayerTimeText.make(position: TimeInterval, duration: TimeInterval, now: Date, mode: LookTimeDisplay) -> (leading: String, trailing: String)`:
  `rest` → („42:10“, „−1:25:50“); `gesamt` → („42:10“, „2:08:00“); `ende` → („42:10“, „Endet um 21:41“).
- `PlayerBadgeSet.make(_ info: StreamTechInfo, mode: LookPlayerBadges) -> [String]`: `aus` → []; `kompakt` →
  höchstens 3 (Auflösung, HDR-Art kurz „DV“/„HDR10“, Ton-Format); `voll` → bis zu 6 (zusätzlich Kanäle, Codec,
  Bitrate „61 Mbit/s“).

- [ ] Jede Fläche über Video ist eine `OverlayCard` (Material plus `bg.scrim`, `panelRadius`, `elevation.overlay`).
- [ ] Kein Text unter 26 pt außer Plaketten (23 pt); Plaketten nur noch über `ThemeBadge`.
- [ ] Spielfläche mit `accessibilityLabel`, `accessibilityValue` und Aktionen für Wiedergabe und ±10 s.

Varianten:
- [ ] `controlBar = minimal`: nur Zeitleiste und Zeiten, links/rechts 80, unten 60. `standard`: Verlauf von unten
  (Höhe 420, Schwarz 85 % → 0), Titel und Knöpfe über der Zeitleiste. `ausfuehrlich`: wie standard plus Kapitelmarken
  auf der Zeitleiste und Plaketten nach `player.badges`.
- [ ] `badges` aus / kompakt / voll über `PlayerBadgeSet`.
- [ ] `timeDisplay` über `PlayerTimeText`; Ziffern gleich breit.
- [ ] `trackPanel = seite`: Panel von rechts, 640 breit, volle Höhe, Innenabstand 80/50, Ton über Untertitel.
  `unten`: Fläche links/rechts 80, unten 60, Innenabstand 36, zwei Spalten (Ton | Untertitel), Abstand 40. `mitte`:
  Bild 45 % abgedunkelt, Karte 1000 breit mittig (oben 190), zwei Spalten. Die drei bestehenden Stile von
  `TrackPanelStyle` werden auf diese drei abgebildet; Bedienung (Gesten aus Build 198) bleibt.
- [ ] `upNext = karte`: unten rechts (Abstand 80), 640 breit, Vorschaubild 200 hoch, Titel, Knöpfe.
  `leiste`: links/rechts 80, unten 60, eine Zeile „Nächste Folge in 20 s · S1 F4 · Titel“ mit „Jetzt abspielen“
  (`ThemeButton(.primary)`) und „Abbrechen“. `vollbild`: Bild der nächsten Folge vollflächig, das laufende Video
  verkleinert auf 420 × 236 oben links (36/36), Info unten links.
- [ ] `stillWatching = dialog`: Bild 60 % abgedunkelt, Karte 800 breit mittig. `karte`: unten links (80/80),
  760 breit, ohne Abdunklung. Die B-c-Logik „Noch da?“ bleibt unverändert.
- [ ] Tests: `timeTextModes` (3), `badgeSetCompactHasAtMostThree`, `badgeSetFullHasAtMostSix`,
  `trackPanelMappingCoversAllStyles`.

### Task 5.5: Übrige Bildschirme und Barrierefreiheit

**Befunde:** D-3, D-25, D-26, Q-28, Q-20 · **Risiko:** gering

**Files:** Modify `App/Sources/PlayerApp.swift` (`ProfilePickerView`), `SyncLoginView.swift`, `PhoneInputView.swift`,
`TorBoxFilesRow.swift`, `Home/HomeManagerView.swift`

- [ ] Alle Literale für Farbe, Größe, Radius, Dauer und Schatten in diesen Dateien durch Tokens ersetzen.
- [ ] `accessibilityReduceMotion` und `accessibilityReduceTransparency` in `ThemeValues.make` berücksichtigen.
- [ ] CI-Prüfung: `grep` auf `.font(.system(size:` und `Color(red:` außerhalb von `Views/Design/` schlägt fehl.

### Build 5c – Deploy-Checkliste

**Vor dem Build:** `test` grün; Bildschirmfotos aus CI (falls schon vorhanden) durchgesehen.

**Am Gerät prüfen:**
- [ ] Jede `player.*`-Option durch alle Werte schalten, während ein Film läuft.
- [ ] Alle vier Player-Karten (Steuerleiste, Ton & Untertitel, Nächste Folge, „Noch da?“) über einer hellen HDR-Szene
  lesbar.
- [ ] VoiceOver liest Kacheln mit Titel und Zustand.
- [ ] „Bewegung reduzieren“ an: keine Überblendungen, kein Aufklappen.
- [ ] „Alles auf Apple TV zurücksetzen“ und danach jede der 35 Optionen einmal geändert: keine Seite bricht.

**Rückfall-Auslöser:** Player-Overlay verdeckt die Bedienung oder Ton-/Untertitelwahl geht nicht → Build 5b.

---

## Build 6: Struktur und Architektur

Jeder Task dieses Builds ändert kein sichtbares Verhalten. Die Reihenfolge folgt den ADRs in
`03-engineering-entscheidungen.md`.

### Task 6.1: `AppModel` auf Observation

**Befunde:** Q-14, [04 §6.5] · ADR-2 Schritt 1 · **Risiko:** mittel · **Profile:** nicht betroffen

**Files:** Modify `App/Sources/AppModel.swift` und alle 43 Dateien mit `@EnvironmentObject var model: AppModel`
(`@Environment(AppModel.self)`), `App/Sources/PlayerApp.swift`

- [ ] Eigener Commit, nichts sonst. Am Gerät: jede Seite reagiert weiter auf Änderungen (Protokoll unten).

### Task 6.2: Wiedergabe-Regeln nach `PlayerCore`

**Befunde:** Q-3, Q-21, Q-20 · ADR-1 · **Risiko:** mittel

**Files:** Create `Packages/PlayerCore/Sources/PlayerCore/Playback/PlaybackQueue.swift`, `Playback/UpNextPolicy.swift`,
`Playback/PlayerLocks.swift`; Tests `PlaybackQueueTests.swift`, `UpNextPolicyTests.swift`, `PlayerLocksTests.swift`

**Interfaces (Produces):**
- `PlaybackQueue.next(state: QueueState, event: QueueEvent) -> (QueueState, QueueStep)` mit
  `QueueEvent` = `.listLoaded`, `.failed(StreamID, FailureClass)`, `.ended(auto: Bool)`, `.userPicked(StreamID)` und
  `QueueStep` = `.play(StreamID, afterMs: Int)`, `.showList`, `.askStillWatching`, `.nextEpisode(PlayRequest)`, `.stop`.
- `UpNextPolicy.cardAt(duration:creditsStart:) -> Double?`, `.preloadAt`, `.countdownSeconds` (heute: 20 s vor Ende
  bzw. Abspann, Countdown 10 s, Vorladen 120 s vor Ende; kurze Videos unter 180 s bekommen keine Karte).
- `PlayerLocks.current(_ s: PlayerLockInputs) -> PlayerLocks` (welche Eingaben sind gesperrt).

- [ ] Schritt A (dieser Build): Regeln mit Tests; die Views rechnen mit und loggen `schatten: Abweichung <Regel> <alt> <neu>`.
- [ ] Schritt B (nächster Build nach einer Woche ohne Abweichungs-Zeilen): Views folgen den Regeln, alter Code entfällt.

### Task 6.3: `PlayerSession` und Dienste

**Befunde:** Q-1, Q-2, Q-5, Q-9, Q-11 · ADR-1, ADR-2 Schritt 3 · **Risiko:** hoch; deshalb in Teilschritten über
mehrere Builds, je Dienst ein Commit-Bündel

**Files:** Create `App/Sources/Playback/PlayerSession.swift`, `App/Sources/Services/ProgressService.swift`,
`Services/StreamService.swift`, `Services/CatalogService.swift`, `Services/ProfileService.swift`,
`Services/MetaService.swift`; `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncClient.swift` (Protokoll für Trakt und Simkl)

- [ ] Reihenfolge: `ProgressService` → `StreamService` → `CatalogService` → `ProfileService` → `MetaService` →
  `PlayerSession`. `AppModel` reicht nach jedem Schritt nur noch durch.
- [ ] Jeder Dienst erfüllt `ProfileScoped` und nutzt `ScopeClock` aus Task 3.1.

### Task 6.4: Strenge Nebenläufigkeit

**Befunde:** Q-12, Q-13, Q-15 · ADR-3 Punkt 5 · **Risiko:** gering je Schritt

**Files:** Modify `App/project.yml` (`SWIFT_STRICT_CONCURRENCY: complete`, später `SWIFT_VERSION: "6.0"`)

- [ ] Warnungen ordnerweise abbauen; CI zählt sie und schlägt fehl, wenn die Zahl steigt.
- [ ] `Task { }` in `onChange` durch `.task(id:)` ersetzen; je Ablauf ein gehaltener Handle.

### Task 6.5: Geheimnisse nur noch im Schlüsselbund

**Befunde:** SEC-14 · ADR-4 Schritt 3 · **Risiko:** hoch · **Profile:** `schemaVersion = 2`; Build 2 bis 5 lesen die
Schlüssel weiter aus der Keychain

**Voraussetzung:** Am Gerät bestätigt, dass Keychain-Einträge die 7-Tage-Neusignatur über atvloadly überstehen.

> **Konflikt (Schlussreview Build 2, I5):** Die Annahme „Build 2 bis 5 lesen die Schlüssel weiter aus der Keychain“
> stimmt so nicht. Seit Build 2 ist beim normalen Start das geladene Profil maßgeblich: Ein Profil ohne Geheimnisse
> *löscht* alle Keychain-Einträge dieses Profils (`SecretMigration.copyIntoStore`, `SecretStore.swift`). Außerdem
> lehnen Builds mit `currentSchema = 1` eine Datei mit `schemaVersion = 2` als „neuere Version“ ab
> (`ProfileStore.swift`). Der Weg zurück von Build 6 braucht deshalb vorher ein Release mit einer Markerregel:
> Sagt das Profil „Geheimnisse liegen im Schlüsselbund“, wird von dort gelesen und nie gelöscht; und dieses Release
> muss `schemaVersion = 2` lesen können.

- [ ] Schreiben von `apiKeys` und `syncTokens` ins Profil endet; `encode` schreibt leere Wörterbücher.
- [ ] Test: Export ohne Geheimnisse enthält keinen Schlüssel; Profil-JSON enthält keinen Schlüssel.

### Task 6.6: Performance nach Messung

**Befunde:** [04 §6] · **Risiko:** gering

- [ ] Tonspur vor dem Laden wählen (Engine-Option `audioSourceStreamIndex`), wenn das Spur-Gedächtnis sie kennt.
- [ ] Startposition in `load` übergeben statt nach der Laufzeit zu springen.
- [ ] `RemoteImage` gibt Bilder beim Verschwinden frei.
- [ ] `syncRemoteProgress` veröffentlicht nur bei Änderung und frühestens 2 s nach dem Start.
- [ ] Jede Änderung nur mit Vorher/Nachher-Wert aus dem Fern-Log übernehmen.

### Build 6 – Deploy-Checkliste

**Am Gerät prüfen**
- [ ] Jede Hauptseite reagiert auf Änderungen: Fortschritt nach dem Player, Merkliste, Profilwechsel, Aussehen.
- [ ] Ein vollständiger Abend: zwei Folgen mit Autoplay, ein Film mit Quellenwechsel, ein Abbruch.
- [ ] Nach der Neusignatur (7 Tage) sind alle Anmeldungen da.

**Erwartete Fern-Log-Zeilen:** keine Zeile `schatten: Abweichung`; `metric: player.firstFrame` und `start.usable`
nicht schlechter als in Build 5c.

**Rückfall-Auslöser:** veraltete Anzeige nach einer Aktion; Anmeldungen fehlen.

---

## Zuordnung Befund → Task

| Bereich | Befunde | Task |
|---|---|---|
| Sicherheit | SEC-1, SEC-5, SEC-16 | 1.4 |
| | SEC-2, SEC-8, SEC-12, SEC-13 | 1.5 |
| | SEC-3, SEC-7, SEC-11 | 1.6 (App-Teil); Betrieb von atvloadly: Roadmap |
| | SEC-4, SEC-6, SEC-9 | 2.3 |
| | SEC-10 | 1.7 |
| | SEC-14 | 2.2, 6.5 |
| | SEC-15, SEC-17 | 1.1 |
| | GIT-1 bis GIT-5 | Entscheidung des Nutzers, siehe `06-security-review.md`; GIT-4 teilweise in 1.8 |
| Datenverlust | S-1, S-2, S-11 | 1.2, 1.3 |
| | W-B-1, S-13 | 2.1 |
| | A-B-1, S-9, S-12 | 2.4 |
| | S-5 bis S-8, W-B-3, W-B-6, S-15 | 2.5 |
| | S-10 | 2.6 |
| Bugs | S-3, S-4, A-A-8, A-A-12, A-B-2, F-B-10 | 3.1 |
| | W-A-1, W-A-3, W-A-4, W-B-4, W-A-9 | 3.2 |
| | W-A-2 | 3.3 |
| | F-B-1, F-B-5 | 3.4 |
| | W-B-2, W-B-5, W-B-7, W-B-10, W-B-12, W-A-5, W-A-7 | 3.5 |
| | A-A-1, A-A-2, A-A-9, A-A-13, A-A-14, A-A-16 | 3.6 |
| | A-A-4, A-A-6, A-A-7, A-A-17 | 3.7 |
| | A-A-3 | 1.7 |
| | A-A-5, A-A-11, A-A-15 | 2.3 |
| | F-A-1 bis F-A-8, F-A-11, F-A-12, F-B-2, F-B-3, F-B-6 bis F-B-9, A-B-3 | 4.1 (F-B-6 in 1.6) |
| | A-B-5, A-B-6, A-B-8, A-B-10, A-B-11 | 4.1 (A-B-8 mit F-A-5: Entdoppeln; A-B-5, A-B-6, A-B-10: Erneuern bei `catalogWake` und Tageswechsel; A-B-11: Kalender-Fenster) |
| | S-16 | Roadmap (Abgleich im Hintergrund) |
| | W-A-6, W-A-10, W-B-8, W-B-9, F-B-4 | Roadmap (niedrig, erst nach Messung bzw. Gerätetest) |
| Design | D-1 | 1.2 |
| | D-2 bis D-28 | 4.2 bis 4.5 (Build 4), 5.1, 5.2, 5.6 (5a), 5.3 (5b), 5.4, 5.5 (5c) |
| Qualität | Q-22 | 1.1 |
| | Q-24 | 1.8 (README); echte Lokalisierung: Roadmap |
| | Q-26 bis Q-29 | 5.1, 5.4, 5.5 |
| | Q-1 bis Q-21, Q-23, Q-25 | 6.1 bis 6.4, sonst Roadmap |

## Self-Review

1. **Abdeckung:** Jeder bestandene Befund der Stufen 2, 5 und 6 steht in der Tabelle oben mit Task oder Roadmap-Verweis.
2. **Typen:** `DecodeReport` (1.2) wird in 1.3, 4.2 und 4.3 verwendet; `ProfileScope`/`ScopeClock` (3.1) in 6.3;
   `HTTPClient` (2.3) ab Build 2 überall; `Look`-Typen (4.2) in 4.3 bis 5.5; `SecretStore` (2.2) in 2.4 und 6.5.
3. **Review Focus:** Die fünf Punkte haben ihre Tests in 1.2, 1.3, 1.4, 1.7/2.3 und 3.1.
4. **Design-Werte:** Keine Platzhalter mehr. Alle Werte stammen aus der Apple-TV-Vorlage des Konfigurators
   (`docs/design/konfigurator/export.json`) und `07-design-analyse.md` §3; alle 35 Optionen stehen in Anhang A und
   haben je einen Task (4.5 Einstellungen, 5.1 bis 5.6 Umsetzung).

## Anhang A: Alle Optionen des Konfigurators

Quelle: Konfigurator, Schema `player.appearance.preset` Version 1. Spalte „Mein Look“ = Standardwert (Apple-TV-Vorlage).
Spalte „ab Build“ = ab wann die Option in den Einstellungen wirkt; vorher ist sie sichtbar und deaktiviert.

| Bereich · Gruppe | Option | Werte | Mein Look (Apple TV) | Kurztext | ab Build |
|---|---|---|---|---|---|
| global · Navigation | `navigation` „Hauptnavigation“ | `seitenleiste` Seitenleiste, `oben` Obere Leiste | `oben` | Seitenleiste links oder Leiste oben. | 4 |
| global · Navigation | `clock` „Uhr“ | `true` An, `false` Aus | `false` | Zeigt die Uhrzeit oben rechts. | 5a |
| global · Navigation | `settingsLayout` „Einstellungs-Layout“ | `spalten` Zwei Spalten, `kacheln` Kacheln, `liste` Liste | `spalten` | Zweispaltig mit Kategorien links, große Kacheln oder eine einzige Liste. | 5a |
| global · Farbe | `accent` „Akzentfarbe“ | `champagner` Champagner, `weiss` Weiß, `eisblau` Eisblau, `blau` Blau, `rot` Rot, `koralle` Koralle, `salbei` Salbei, `violett` Violett | `weiss` | Markiert Gewähltes und den Hauptknopf. Der Fokus selbst bleibt weiß. | 4 |
| global · Farbe | `background` „Hintergrundton“ | `schwarz` Schwarz (OLED), `graphit` Graphit, `tinte` Tinte (bläulich), `warm` Warm (bräunlich) | `schwarz` | Schwarz nutzt OLED voll aus. Die getönten Varianten wirken weicher. | 4 |
| global · Schrift und Bewegung | `typeScale` „Schriftgröße“ | `kompakt` Kompakt, `standard` Standard, `gross` Groß | `standard` | Skaliert alle Texte gemeinsam. | 4 |
| global · Schrift und Bewegung | `typeCharacter` „Schriftcharakter“ | `neutral` Neutral, `editorial` Editorial, `technisch` Technisch | `neutral` | Neutral entspricht tvOS. Editorial setzt große Titel leichter und enger. Technisch setzt Metadaten kräftiger und weiter. | 4 |
| global · Schrift und Bewegung | `motion` „Bewegung“ | `aus` Aus, `dezent` Dezent, `standard` Standard | `standard` | Dauer und Stärke der Übergänge. Aus schaltet Überblendungen ab. | 4 |
| home · Hero | `heroStyle` „Hero-Stil“ | `vollbild` Vollbild, `banner` Banner, `karussell` Karussell, `aus` Aus | `vollbild` | Vollbild füllt den ganzen Bildschirm hinter den Reihen. Banner ist eine eigene Fläche über den Reihen. Karussell zeigt den Nachbartitel angeschnitten. | 5a |
| home · Hero | `heroInfo` „Info-Ebene“ | `minimal` Minimal, `standard` Standard, `ausfuehrlich` Ausführlich | `standard` | Wie viel Text über dem Hero-Bild steht. | 5a |
| home · Hero | `heroTitle` „Logo oder Titel“ | `logo` Logo, `text` Titel als Text | `logo` | Logo nimmt das Titel-Logo aus den Metadaten, wenn es eines gibt. Titel setzt den Namen immer als Text. | 5a |
| home · Hero | `backdropFollowsFocus` „Hintergrund nach Fokus“ | `true` An, `false` Aus | `true` | Der Hintergrund wechselt auf den Titel, auf dem der Fokus kurz ruht. | 5a |
| home · Karten und Reihen | `cardShape` „Kartenform“ | `poster` Poster, `querformat` Querformat, `mischung` Mischung | `querformat` | Poster ist Hochformat, Querformat zeigt Szenenbilder. Mischung nutzt Querformat für Weiterschauen und Poster für den Rest. | 5a |
| home · Karten und Reihen | `cardSize` „Kartengröße“ | `klein` Klein, `mittel` Mittel, `gross` Groß | `gross` | Größere Karten wirken ruhiger, zeigen aber weniger Titel pro Reihe. | 4 |
| home · Karten und Reihen | `corners` „Ecken“ | `eckig` Eckig, `leicht` Leicht, `weich` Weich, `rund` Rund | `rund` | Radius der Karten und Flächen. | 5a |
| home · Karten und Reihen | `rowSpacing` „Abstände“ | `eng` Eng, `normal` Normal, `luftig` Luftig | `luftig` | Abstand zwischen Karten und zwischen Reihen. | 5a |
| home · Karten und Reihen | `rowTitle` „Reihentitel“ | `dezent` Dezent, `standard` Standard, `gross` Groß | `standard` | Dezent ist klein und zurückgenommen, Groß setzt kräftige Überschriften. | 5a |
| home · Karten und Reihen | `cardTitles` „Titel unter Karten“ | `immer` Immer, `fokus` Nur bei Fokus, `aus` Aus | `immer` | Zeigt den Namen unter der Karte: immer, nur bei Fokus oder nie. | 5a |
| home · Karten und Reihen | `expandPosters` „Poster aufklappen“ | `true` An, `false` Aus | `false` | Das fokussierte Poster wächst nach kurzer Ruhe zum Querformat mit Szenenbild. | 4 |
| home · Fokus-Effekt | `focusScale` „Skalierung“ | `keine` Keine, `dezent` Dezent, `kraeftig` Kräftig | `kraeftig` | Wie stark die fokussierte Karte wächst. | 5a |
| home · Fokus-Effekt | `focusBorder` „Rahmen“ | `keiner` Keiner, `weiss` Weiß, `akzent` Akzentfarbe | `keiner` | Ein Rahmen um die fokussierte Karte. | 5a |
| home · Fokus-Effekt | `focusShadow` „Schatten“ | `keiner` Keiner, `weich` Weich, `tief` Tief | `tief` | Schatten unter der fokussierten Karte. | 5a |
| home · Fokus-Effekt | `focusGlow` „Glanz“ | `true` An, `false` Aus | `true` | Ein Lichtreflex auf der fokussierten Karte, wie bei den Postern der Apple-TV-App. | 5a |
| detail · Aufbau | `layout` „Layout“ | `links` Links, `zentriert` Zentriert, `kino` Kino-Vollbild | `kino` | Links stellt Text und Knöpfe an den linken Rand. Zentriert setzt alles mittig. Kino-Vollbild zeigt fast nur das Bild und schiebt den Rest nach unten. | 5b |
| detail · Aufbau | `descriptionLines` „Beschreibungslänge“ | `2` 2 Zeilen, `3` 3 Zeilen, `5` 5 Zeilen | `2` | Wie viele Zeilen der Beschreibung sofort sichtbar sind. | 5b |
| detail · Aufbau | `cast` „Besetzung“ | `kreise` Kreise, `karten` Karten, `text` Textzeile, `aus` Aus | `kreise` | Runde Porträts, Karten mit Rolle, eine Textzeile oder gar nicht. | 5b |
| detail · Plaketten und Bewertungen | `badgeStyle` „Plakettenstil“ | `umriss` Umriss, `gefuellt` Gefüllt, `text` Nur Text, `logos` Logos | `text` | Umriss ist fein, Gefüllt ist gut lesbar, Text kommt ohne Fläche aus. Logos zeichnet die Schriftzüge nach. | 5b |
| detail · Plaketten und Bewertungen | `ratingStyle` „Bewertungen“ | `symbole` Symbol + Zahl, `text` Textzeile, `kacheln` Kacheln | `text` | Symbole mit Zahl, reine Textzeile oder kleine Kacheln mit Quelle. | 5b |
| detail · Quellenliste | `sourceList` „Darstellung“ | `kompakt` Kompakt, `ausfuehrlich` Ausführlich, `karten` Karten | `kompakt` | Kompakt zeigt eine Zeile pro Quelle. Ausführlich zeigt den Text des Addons. Karten trennt Plaketten und Text klar. | 5b |
| detail · Aufbau (eigene, nicht im Konfigurator) | `episodes` „Folgen“ | `reihe` Nebeneinander, `liste` Untereinander | `reihe` | Nebeneinander zeigt die Folgen als waagerechte Reihe mit Vorschaubild, Untereinander als Liste mit Beschreibung. | 5b |
| detail · Aufbau (eigene, nicht im Konfigurator) | `titleArt` „Titel oben“ | `logo` Logo, `poster` Poster | `logo` | Logo zeigt das Titel-Logo statt des Posters, wenn es eines gibt. Poster zeigt immer das Poster. | 5b |
| player · Steuerleiste | `controlBar` „Umfang“ | `minimal` Minimal, `standard` Standard, `ausfuehrlich` Ausführlich | `minimal` | Minimal zeigt nur Zeitleiste und Zeit. Standard ergänzt Titel und Knöpfe. Ausführlich zeigt zusätzlich Kapitelmarken und Technik. | 5c |
| player · Steuerleiste | `badges` „Plaketten“ | `aus` Aus, `kompakt` Kompakt, `voll` Alle | `aus` | Technik-Plaketten in der Steuerleiste. | 5c |
| player · Steuerleiste | `timeDisplay` „Zeitanzeige“ | `rest` Restzeit, `gesamt` Position / Dauer, `ende` Endet um | `rest` | Restzeit, Position und Gesamtdauer oder die Uhrzeit, zu der der Film endet. | 5c |
| player · Panels und Hinweise | `trackPanel` „Ton- und Untertitel-Panel“ | `seite` Seite, `unten` Unten, `mitte` Mitte | `unten` | Seite schiebt ein Panel von rechts herein. Unten legt es über die Steuerleiste. Mitte zeigt eine schwebende Karte. | 4 |
| player · Panels und Hinweise | `upNext` „Nächste Folge“ | `karte` Karte, `leiste` Leiste, `vollbild` Vollbild | `karte` | Karte unten rechts, schmale Leiste am unteren Rand oder Vollbild mit Vorschaubild. | 5c |
| player · Panels und Hinweise | `stillWatching` „„Noch da?““ | `dialog` Dialog, `karte` Karte | `dialog` | Dialog in der Mitte, der das Bild abdunkelt, oder eine ruhige Karte unten. | 5c |
