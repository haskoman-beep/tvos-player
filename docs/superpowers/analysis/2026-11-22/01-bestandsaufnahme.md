# 01 · Bestandsaufnahme

**[C] Analysierter Stand:** Der Arbeitsbranch dieser Analyse zweigt von `main` (Version 0.4.0) ab. Fast alle im Auftrag
genannten Funktionen (Dolby Vision FEL, „Noch da?“, App-Update, Intro überspringen, Kalender mit Sendezeiten, TorBox)
liegen nur auf `integ`, 280 Commits weiter. Analysiert wurde deshalb `integ`.

Die Liste der Entscheidungen aus Specs und Plänen (Grundlage für Stufe 3) steht mit Status und Beleg in
[03-engineering-entscheidungen.md](03-engineering-entscheidungen.md), Abschnitt 1. Architekturbild und Diagramme stehen in
[04-system-design.md](04-system-design.md).

Stand: Branch `integ`, Commit b2188a2 (Build 249). Rein lesend aus der Dateikopie ermittelt; nichts gebaut, nichts ausgeführt.
Alle `Datei:Zeile`-Angaben relativ zur Repo-Wurzel. Kurzformen: `App/…` = `App/Sources/…`, `Core/…` = `Packages/PlayerCore/Sources/PlayerCore/…`.
„(abgeleitet)“ = aus dem Code geschlossen, nicht direkt belegt. Keine Bewertung, keine Befunde.

## 1. Modul- und Dateikarte

### 1.1 Kennzahlen

| Kennzahl | Wert |
|---|---|
| App (`App/Sources`) | 107 Swift-Dateien, 20 041 Zeilen |
| PlayerCore (Quellen) | 132 Swift-Dateien, 20 064 Zeilen |
| PlayerCore (Tests) | 75 Swift-Dateien, 13 607 Zeilen, 965 `@Test` (Swift Testing), 2 Fixtures (JSON) |
| AetherFEL (Hülle) | 2 Swift-Dateien, 8 Zeilen + `Package.swift` (29 Zeilen) |
| Größte Dateien | `App/Views/DetailViews.swift` 1468 · `App/Views/PlayerScreen.swift` 840 · `App/Playback/DiskCacheProxy.swift` 783 · `Core/Update/AppUpdate.swift` 740 · `App/AppModel.swift` 716 |
| Ziel/Plattform | tvOS 18.0 (`App/project.yml:5`), PlayerCore zusätzlich iOS 18 / macOS 15 (`Packages/PlayerCore/Package.swift:6`) |
| Projektdatei | XcodeGen aus `App/project.yml`; `.xcodeproj` ist nicht eingecheckt (`.gitignore`) |
| Marketing-Version | 0.4.0 (`App/project.yml:33`); dieselbe Zahl fest in `Core/Sync/APIRequest.swift:76` |

Abhängigkeiten:

| Paket | Version/Pin | Beleg |
|---|---|---|
| AetherEngine (GitHub, öffentliches Release) | `exact: "7.71.2"`, Traits `DolbyVisionFelCurves`, `DolbyVisionStillReshaping` | `Packages/AetherFEL/Package.swift:15-21` |
| AetherFEL (lokal) | Hülle, `@_exported import AetherEngine`; Bauwächter `typealias FelBuildGuard = FelCurveFoldResult` | `Packages/AetherFEL/Sources/AetherFEL/AetherFEL.swift:2`, `FelBuildGuard.swift:4-6` |
| PlayerCore (lokal) | keine externen Abhängigkeiten | `Packages/PlayerCore/Package.swift:4-12` |
| App-Target | hängt an AetherFEL und PlayerCore | `App/project.yml:26-28` |
| Engine-Binärteile im IPA | Frameworks `AetherLib{avcodec,avformat,avutil,swresample,swscale,avfilter,zvbi,dav1d,zimg}` und `AetherEngine_AetherEngine.bundle` (von CI geprüft) | `.github/workflows/build.yml:119-122` |
| SFace-Modell (Core ML) | in CI erzeugt, nie eingecheckt; optional in `project.yml` | `App/project.yml:20-25`, `build.yml:34-71` |
| Python (nur CI, Modellumwandlung) | `tools/xray_model/requirements.lock` mit Hashes | `build.yml:62` |

Sonstige Dateien: `tools/logcollector.py` (Fern-Log-Empfänger), `tools/check_ipa.sh` (IPA-Prüfung), `tools/release_notes.sh`, `tools/backfill_releases.sh`, `tools/xray_model/convert_sface.py`; `README.md` (179 Zeilen), `CHANGELOG.md`, `THIRD_PARTY_NOTICES.md`, `docs/superpowers/{specs,plans}`.

### 1.2 App (`App/Sources`)

**`App/Sources/`** (25 Dateien, 4496 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AppModel+Airtimes.swift | 60 | TVmaze-Sendezeiten im Hintergrund nachziehen; `UpcomingRevision` (Neuzeichnen des Kalenders) |
| AppModel+CatalogCache.swift | 42 | 24-h-Katalog-Cache: Hintergrund-Erneuerung je Quelle, Anstoß bei Rückkehr in die App |
| AppModel+CatalogDisk.swift | 129 | Plattenstand der Startseiten-Kataloge je Profil lesen/schreiben (`CatalogDiskStore`) |
| AppModel+FusionKit.swift | 22 | Trakt nur mit Client ID (öffentliche Listen) und Import einer Fusion-Kit-URL |
| AppModel+HomeRows.swift | 54 | Laden und Vorladen der Startseiten-Reihen, eine Ladung je Quelle (`CatalogLoad`) |
| AppModel+MetaAddon.swift | 175 | Metadaten zusammenführen (Cinemeta + Metadaten-Addon + TMDB), Kachel-Poster, `AddonMetaCache` |
| AppModel+PhoneHome.swift | 91 | „Startseite ordnen“ von der Handy-Seite übernehmen, Reihen hinzufügen, Reihentitel |
| AppModel+Reresolve.swift | 26 | Abgelaufenen Link der laufenden Quelle beim selben Addon neu auflösen |
| AppModel+SourceOrder.swift | 49 | Quellenliste ordnen, Dubletten entfernen, „Beste Wahl“, AV1-Hardware-Abfrage |
| AppModel+StreamRevalidate.swift | 75 | Quellen-Cache: veralteten Stand zeigen und im Hintergrund erneuern, Warten für Autoplay |
| AppModel+StreamSearch.swift | 179 | Quellensuche je Addon mit Zeitgrenze, `StreamSearchStatus` (Zwischenstände), Status-Views |
| AppModel+SyncQueue.swift | 195 | Kachel-Aktionen (Merkliste, gesehen, Weiterschauen) und Abarbeiten der Sync-Warteschlange |
| AppModel+Upcoming.swift | 102 | Kalender/„Heute neu“: kommende Folgen aus TMDB, 6-h-Speichercache (`UpcomingCache`) |
| AppModel.swift | 716 | Zentraler App-Zustand: Profile, Fortschritt, Scrobble, Trakt/Simkl-Login, Kataloge, Quellen-Cache, Handy-Befehle |
| AppUpdater.swift | 190 | Zustand von „App aktualisieren“: GitHub-Prüfung, atvloadly-Start, Abfrage-Schleife, Bonjour-Suche |
| CollectionLinkStore.swift | 449 | Gespeicherte Collection-Links/-Codes je Profil: laden, erkennen, importieren, aktualisieren |
| DefaultsStorage.swift | 62 | App-Ablage: `TieredBlobStorage` über UserDefaults (LZFSE) plus Dateien in Application Support/Caches |
| FusionKitStore.swift | 425 | Fusion-Startseiten-Kit: Kit-Dateien zur Laufzeit laden, Auswahl je Profil, Abgleich mit der Startseite |
| ImagePipeline.swift | 572 | Bildlader (actor): URLCache auf Platte, Speichercache nach Bytes, Verkleinern, GIFs, `RemoteImage` |
| MainThreadWatchdog.swift | 62 | Hänger des Hauptthreads per Runloop-Beobachter messen und loggen |
| PlayerApp.swift | 234 | App-Einstieg (@main), `Route`/`PlayRequest`, `RootView` mit Tabs und je Tab eigenem NavigationStack, Profilwahl beim Start |
| RatingIconStore.swift | 108 | Bewertungs-Icon-Satz von einer Nutzer-Adresse laden, Plattencache 24 h |
| RatingsStore.swift | 61 | MDBList-Bewertungen (actor) mit Plattencache, Zusammenlegen gleicher Anfragen, Limit-Pause |
| RemoteLog.swift | 80 | Ereignis-Log: os_log plus Versand an Bonjour-Empfänger im Heimnetz, 500-Zeilen-Puffer |
| StreamPrefetcher.swift | 338 | Quellen vorladen: Fokus-Ruhe und sichtbare Kacheln, gemeinsames Budget, Pausen bei Player/Leerantworten |

**`App/Sources/Playback/`** (8 Dateien, 1598 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| DiskCacheProxy.swift | 783 | Lokaler HTTP-Proxy (127.0.0.1) mit Block-Plattencache für den laufenden Film |
| NowPlayingBridge.swift | 122 | Now-Playing-Karte und Systembefehle (Kontrollzentrum, iPhone-Fernbedienung) |
| PlaybackEngine.swift | 282 | Protokoll `PlaybackEngine`, `LoadPrefs` und das AetherEngine-Backend `AetherBackend` |
| PlaybackFailureMapping.swift | 25 | Engine-Fehler auf `PlaybackFailure` (Art/Code) abbilden |
| PlaybackStability.swift | 101 | App-weit: Netzpfad, Ton-Routenwechsel, kürzlich fehlgeschlagene Quellen (8 h) |
| PlayerAudioOptions.swift | 82 | Ton-/Bild-Ladeoptionen der Engine aus den Geräte-Einstellungen, HDMI-Modus halten |
| PlayerMemory.swift | 89 | Spur-Gedächtnis je Serie/Film und Fortschritt von Dateien ohne IMDb-ID, je Profil |
| XRayProfile5.swift | 114 | Dolby-Vision-Profil-5-Vorprüfung beim Laden (hält die Wiedergabe trotz Still-Trait unverändert) |

**`App/Sources/Views/`** (24 Dateien, 6093 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| CalendarView.swift | 134 | Kalender: Folgen aus Weiterschauen/Merkliste, gestern bis 14 Tage voraus |
| ClockView.swift | 19 | Uhr oben rechts (TimelineView, jede Minute) |
| DetailViews.swift | 1468 | Detailseite, Collection-/Ordnerseite, Quellenliste (`StreamListView`), Suche, Trailer, Zusatzinfos |
| FocusHelpers.swift | 37 | Fokusziele ohne Fokusrahmen für Hinweis-Seiten |
| FocusVideo.swift | 535 | Fokus-Videos auf Kacheln: Dateicache (actor), ein gemeinsamer AVPlayer, Overlay |
| GenrePageView.swift | 262 | Genre-Seite mit Filter Filme/Serien und endlosem Raster |
| HomeFocusMemory.swift | 50 | Fokus-Gedächtnis je Startseiten-Reihe (Environment) |
| HomeHero.swift | 379 | Startseiten-Hero: `HomeFocus` (350-ms-Ruhe), Folien, Hintergrund, Info, Knöpfe, Start-Fokus |
| HomeTopEdgeWatch.swift | 229 | Hält die obere Tab-Leiste vom obersten Element der Startseite erreichbar |
| HomeView.swift | 242 | Startseite: Hero oder Liste, Reihen, Vorladen, Verwalter-Einstieg, Kontextmenü-Aktionen |
| LibraryView.swift | 71 | Bibliothek: Weiterschauen, Merkliste, Verlauf |
| PersonView.swift | 85 | Personenseite: Foto, Biografie, Filmografie (TMDB) |
| PhoneInputView.swift | 129 | `PhoneServer` (NWListener, Port 8765) und Seite mit QR-Code für die Handy-Eingabe |
| PlayerScreen.swift | 840 | Vollbild-Player: `PlayerScreen` (Verdrahtung mit AppModel) und `PlayerControls` (Laden, Takt, Fehlerleiter, Up-next) |
| QualityBadges.swift | 166 | Qualitäts-Plaketten auf Postern, `QualityBadgeCache` |
| RowViews.swift | 679 | Eine Startseiten-Reihe im gewählten Stil, Kachel-Typen, `\.navigate` |
| SettingsView.swift | 121 | Einstellungen: Kategorienspalte und Zuordnung zu den Kategorieseiten |
| SourceFilterBar.swift | 49 | Filter-Chips über der Quellenliste |
| SpoilerBlur.swift | 19 | Spoilerschutz: Weichzeichnen von Folgenbildern |
| SyncLoginView.swift | 67 | Geräte-Login Trakt/Simkl mit Abfrage-Schleife |
| TabBarGuard.swift | 254 | Bindet die obere Tab-Leiste nach jedem Pop an die sichtbare Seite |
| TileContextMenu.swift | 60 | Langdruck-Menü einer Kachel (Merkliste, gesehen, Weiterschauen) |
| TilePosterImage.swift | 63 | Kachel-Poster: TMDB-Poster zuerst, dann Poster des Metadaten-Addons |
| TorBoxFilesRow.swift | 135 | Reihe „Meine TorBox-Dateien“ in der Bibliothek |

**`App/Sources/Views/Design/`** (6 Dateien, 1277 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| CategoryList.swift | 203 | Zweispaltige Kategorienliste (linke Spalte mit Gruppen) |
| FocusAnchor.swift | 64 | Sichtbares Fokusziel „Fertig/Zurück“ für Seiten ohne Fokusziele |
| SettingsRow.swift | 193 | Zeilen-Bausteine der Einstellungen (Zeile, Schalter, Kopf) |
| StatusCard.swift | 124 | Kopfkarte einer Kategorie |
| Theme.swift | 475 | Designsystem: Textrollen, Abstände, Radien, Farben, Button-Stile |
| ThemeBadge.swift | 218 | Einziger Plakettentyp der App, Meta-Zeile |

**`App/Sources/Views/Home/`** (4 Dateien, 846 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AddRowBrowser.swift | 284 | Hinzufügen-Browser für Reihen (Gruppen aus `RowCatalog`) |
| HomeManagerView.swift | 345 | Verwalter „Reihen & Collections“ |
| HomeRowMenu.swift | 38 | Kontextmenü einer Startseiten-Reihe |
| HomeRowsSession.swift | 179 | Zustand einer Verwalter-Sitzung (@Observable) |

**`App/Sources/Views/Player/`** (19 Dateien, 3851 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AddonSubtitleLoader.swift | 141 | Untertitel aus Addons holen, Datei-Hash der Quelle (OpenSubtitles) berechnen |
| PlaybackErrorCard.swift | 28 | Fehlermeldung, wenn die Fehlerleiter aufgibt |
| PlayerExit.swift | 81 | Geordneter Ausstieg (Moduswechsel abwarten), Ende der Datei, schwarze Abdeckung |
| PlayerInfoBadges.swift | 44 | Kopfzeile und Plaketten der Steuerleiste |
| PlayerLifecycle.swift | 103 | Szenenwechsel (TV aus, Home, Bildschirmschoner) an den Player melden, Bild wiederherstellen |
| PlayerLoadingSteps.swift | 54 | Anzeige der Lade-Schritte beim Start; Standardwerte für Backends ohne Startstand |
| PlayerPauseCard.swift | 131 | Pause-Karte (Logo/Titel nach ca. 2 s Pause) |
| PlayerPictureSound.swift | 321 | Untertitel-Versatz, Zeichensatz und Dateien der Addon-Untertitel, Bildschirmschoner-Sperre |
| PlayerScrub.swift | 595 | Spulen über die Touchfläche mit Vorschaubildern, Zeitleiste |
| PlayerSidePanel.swift | 598 | Seitenpanel im Player: Folgen, Kapitel, andere Quelle, Infos (`PlayerExtras`) |
| PlayerStability.swift | 139 | Lade-/Puffer-Wächter im Player (Takt, Netz weg/zurück, erstes Bild) |
| PlayerTrackPanel.swift | 557 | Ton- und Untertitel-Panel, Technik-Infos |
| PostPlayCard.swift | 127 | Karte ab Abspannbeginn eines Films, Weiterleitung danach |
| SkipSegmentButton.swift | 367 | IntroDB-Abfrage, Sprungbereiche, Überspringen-Knopf (`SkipSegmentController`) |
| SkipSettingsRows.swift | 54 | Einstellungen „Überspringen“ |
| StillWatchingPrompt.swift | 69 | Auto-Weiter-Zustand und „Noch da?“-Abfrage |
| SubtitleOverlayView.swift | 180 | Eigene Untertitel-Ebene über dem Bild |
| SubtitleTextView.swift | 84 | Zeichnen eines Untertitel-Blocks im Profil-Stil |
| XRayProbeHook.swift | 178 | Diagnose: Standbild bei Pause greifen und Gesichter prüfen (Entwicklerschalter) |

**`App/Sources/Views/Settings/`** (21 Dateien, 1880 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AddonSettings.swift | 99 | Kategorie „Addons“, Unterseite je Addon |
| AppearanceSettings.swift | 93 | Kategorie „Aussehen“ |
| AudioSettings.swift | 114 | Kategorie „Sprache & Untertitel“, Zeilen für Ton-Formung und Bildmodus |
| CollectionLinksView.swift | 70 | Seite „Collection-Link hinzufügen“ / Aktualisieren |
| DeviceCheckSettings.swift | 107 | Unterseite „Gerätecheck“ |
| FusionKitSettings.swift | 58 | Fusion-Kit an/aus, „Neu laden“ |
| HomeCategorySettings.swift | 79 | Kategorie „Startseite“ (Status, Postergröße) |
| HomeSettings.swift | 41 | Einstiege Verwalter, Fusion-Kit, Import am Handy |
| PictureSoundSettings.swift | 33 | Kategorie „Bild & Ton“ (je Gerät) |
| PlaybackSettings.swift | 41 | Kategorie „Wiedergabe“ |
| ProfileSettings.swift | 103 | Kategorie „Profil & Konten“: Profile wechseln/anlegen/löschen |
| ServiceSettings.swift | 53 | Zeilen „Konten“ und „Schlüssel“ (Trakt/Simkl, Schlüssel-Status) |
| SettingsKit.swift | 404 | Gemeinsame Bausteine der Einstellungsseiten (Seite, Abschnitt, Auswahl, Rückfrage) |
| SourceCategorySettings.swift | 36 | Kategorie „Quellen“ |
| SourceSettingsRows.swift | 59 | Spoilerschutz-Zeile, Seite Bewertungs-Icon-Satz |
| StreamListSettingsRows.swift | 36 | Zeilen „Quellen sortieren“ und Plaketten der Quellenliste |
| SubtitleStyleSettingsRows.swift | 129 | Einstellungen und Vorschau des Untertitel-Aussehens |
| SystemMaintenanceRows.swift | 57 | System: Diagnose (Ruckler-Log, Log-Empfänger) und Zwischenspeicher |
| SystemSettings.swift | 89 | Kategorie „System“: Version, Update, Lizenzen |
| TitleDisplaySettingsRows.swift | 90 | Zeilen Poster-Plaketten, Bewertungsquellen, Bilder vom Metadaten-Addon |
| UpdatePage.swift | 89 | Unterseite „App aktualisieren“ |

### 1.3 PlayerCore (`Packages/PlayerCore/Sources/PlayerCore`)

**`Packages/PlayerCore/Sources/PlayerCore/Addons/`** (10 Dateien, 1714 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AddonClient.swift | 176 | `HTTPFetching`/`URLSessionFetcher`, `InstalledAddon`, `AddonClient` (Manifest, Katalog, Meta, Streams) |
| AddonMetaFetch.swift | 102 | Abfrage beim Metadaten-Addon mit Zeitgrenzen (Aufrufer 3 s, Anfrage 10 s) |
| AddonNotices.swift | 98 | Fehlereinträge von Addons in Katalogen/Metas/Untertiteln erkennen |
| AddonSearch.swift | 186 | Quellensuche über mehrere Addons parallel mit Frist je Addon und Zwischenständen |
| AddonStreamKind.swift | 155 | Art eines Stream-Eintrags (Quelle oder Hinweis eines Aggregators) |
| AddonSubtitles.swift | 324 | Untertitel-Ressource der Addons, Auswahlplan, OpenSubtitles-Hash |
| AsyncLimiter.swift | 65 | actor: höchstens N gleichzeitige Arbeiten; Zähler der Wartenden |
| LenientJSON.swift | 95 | Nachsichtiges Dekodieren von Addon-Feldern (Zahl als Text usw.) |
| MetaImageChoice.swift | 63 | Bilder/Bewertungen vom Metadaten-Addon wählen und zusammenführen |
| StremioModels.swift | 450 | Stremio-Protokolltypen: Manifest, Katalog, Meta, Stream |

**`Packages/PlayerCore/Sources/PlayerCore/Import/`** (8 Dateien, 1648 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| CollectionImport.swift | 191 | Ein Einstieg für Collection-Importe, Format wird am Inhalt erkannt |
| FusionImport.swift | 368 | Fusion-Kit-Format (`fusionWidgets` v1) in Reihen übersetzen |
| FusionKitCatalog.swift | 224 | Verweise auf Kit-Dateien, Adressen, Kit-Einstellungen und Abgleich |
| NuvioImport.swift | 270 | Nuvio-Export einlesen, Ordner zusammenführen/auffrischen |
| PackageArt.swift | 283 | Standbilder und Fokus-GIFs der fertigen Pakete zuordnen |
| ReadyPackages.swift | 96 | Fertige Pakete (TMDB-Discover) für die Plus-Auswahl |
| TMDBLink.swift | 21 | TMDB-Link in eine Listenquelle übersetzen |
| TileMotion.swift | 195 | Regeln für bewegte Kacheln (Fokus-Video, Cache-Plan, MP4-Prüfung) |

**`Packages/PlayerCore/Sources/PlayerCore/Logging/`** (2 Dateien, 280 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| HitchDetector.swift | 70 | Hänger aus Runloop-Zeitpunkten erkennen |
| LogRedact.swift | 210 | Logzeilen entschärfen (Adressen, Schlüssel, Tokens) |

**`Packages/PlayerCore/Sources/PlayerCore/Models/`** (30 Dateien, 3773 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| Appearance.swift | 92 | Aussehen: Navigation, Akzent, Kartengröße |
| AudioLanguagePreset.swift | 136 | Feste Reihenfolgen für Ton-/Untertitelsprache |
| BadgeText.swift | 113 | Anzeige- und VoiceOver-Texte der Plaketten, Kopf der Quellenliste |
| Collection.swift | 90 | `CatalogSource`, `SourceKind`, `Folder`, `MediaCollection` |
| CollectionRowState.swift | 88 | Zustand einer Collection-Reihe, GIF-Bildplan |
| ContentKind.swift | 14 | Ob ein Typ Staffeln/Folgen hat |
| DesignText.swift | 55 | Textregeln des Designsystems |
| DetailLoad.swift | 97 | Fokus-Ruhezeit (350 ms), geteilte Nachschlage-Ergebnisse, Lade-Zeitleiste der Detailseite |
| DetailPage.swift | 66 | Reine Regeln der Detailseite (z. B. Fokus auf späte Karte) |
| DeviceSettings.swift | 104 | Geräte-Einstellungen (Bild & Ton) und `DeviceSettingsStore` mit einmaliger Migration |
| DiskCacheSettings.swift | 31 | Einstellung „Plattencache“ |
| FocusHeadroom.swift | 49 | Platzbedarf einer fokussierten Kachel |
| GenrePage.swift | 251 | Regeln der Genre-Seite (Filter, Quellen, Blättern, Raster) |
| Home.swift | 52 | `RowStyle`, `RowContent`, `HomeRow`, `HomeLayout` |
| HomeEditor.swift | 202 | Bearbeiten der Startseite (Verwalter und Handy-Seite) |
| HomeManager.swift | 293 | Zustand des Verwalters und des Hinzufügen-Browsers |
| HomeTopEdge.swift | 380 | Regeln für das oberste Fokusziel und die Tab-Leiste |
| ISODate.swift | 28 | Gemeinsamer ISO-8601-Datumsleser |
| NavigationRules.swift | 126 | Tabs, Menu-Kette, Fokusregeln für Folgen/Quellen/Player |
| PlayerComfortSettings.swift | 39 | Player-Einstellungen je Profil |
| PosterSize.swift | 122 | Kachelformen und -maße, Vorlade-Grenze der Reihen (4) |
| Profile.swift | 117 | `Profile` mit Standardwerten für fehlende Felder, Sprache, Fortschrittsquelle |
| RowCatalog.swift | 348 | Angebot des Hinzufügen-Browsers |
| SettingsSummary.swift | 249 | Zusammenfassungen und Wertetexte der Einstellungen |
| SettingsTree.swift | 99 | Kategorien, Gruppen und Geltungsbereich der Einstellungen |
| SourceSettings.swift | 35 | Einstellungen zu Quellen und Extras |
| TextChunks.swift | 39 | Langen Text in fokussierbare Stücke teilen |
| TilePosterChoice.swift | 42 | Welches Bild eine Poster-Kachel zeigt |
| TitleDisplaySettings.swift | 47 | Position der Qualitäts-Plaketten, Titel-Anzeige |
| VisiblePrefetchPlan.swift | 369 | Plan/Budget für das stille Vorladen sichtbarer Kacheln, Cache-Stufen |

**`Packages/PlayerCore/Sources/PlayerCore/Phone/`** (3 Dateien, 504 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| PhoneHome.swift | 143 | Abschnitte der Handy-Seite, Stand für „Startseite ordnen“ |
| PhoneImportDetect.swift | 59 | Erkennt, was im gemeinsamen Import-Feld eingefügt wurde |
| PhoneInput.swift | 302 | HTTP/1.1-Parser, Antwort, `PhoneCommand`, Seitenlogik mit Token (`PhoneInputPage`) |

**`Packages/PlayerCore/Sources/PlayerCore/Playback/`** (32 Dateien, 5359 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AudioShapingSettings.swift | 95 | Ton-Einstellungen für die Engine (je Gerät) |
| AudioSwitchWatch.swift | 67 | Verfolgt ein Ton-Neuladen bis zur neuen Spur |
| DiskCache.swift | 399 | Reine Logik des Plattencaches (Blockplan, Range, Verdrängung, Grenzen) |
| DisplayModeSettings.swift | 51 | Bildmodus-Einstellungen (je Gerät) |
| FailedLinks.swift | 135 | Urteil über die laufende Quelle, Buch fehlgeschlagener Quellen (8 h) |
| IdleTimerPolicy.swift | 39 | Bildschirmschoner-Regel im Player |
| LoadWatchdog.swift | 183 | Lade-/Puffer-Wächter, Routenwechsel-Fenster, Start-Zeitstempel |
| MediaLabels.swift | 208 | Klartext für Engine-Rohwerte |
| ModeSwitchExit.swift | 60 | Ausstieg mit Warten auf den Bildmodus-Wechsel |
| NowPlayingRules.swift | 145 | Regeln der Now-Playing-Karte und Fernbedien-Befehle |
| PauseCard.swift | 128 | Regel und Inhalt der Pause-Karte |
| PlaybackLifecycle.swift | 60 | App-Phasen aus Sicht des Players |
| PlaybackRecovery.swift | 278 | Fehlerklassen und Fehlerleiter (`RecoveryPlanner`) |
| PlayerInfoLabels.swift | 59 | Texte der Steuerleiste |
| ScrubPlanner.swift | 362 | Spul-Logik, schnelles Spulen, Vorschau-Cache |
| SidePanel.swift | 346 | Regeln des Seitenpanels im Player |
| SkipPolicy.swift | 222 | Was in einem überspringbaren Bereich passiert, Karte nach dem Film |
| SkipSegmentStore.swift | 176 | IntroDB-Antworten auf dem Gerät (400 Einträge) |
| SkipSegments.swift | 252 | Sprungbereiche, Kapitelmarken, Planung |
| StartupSteps.swift | 66 | Lade-Schritte beim Start (Spiegel der Engine-Stufen) |
| SubtitleCharset.swift | 179 | Zeichensatz von Addon-Untertiteln erkennen und umwandeln |
| SubtitleCueHold.swift | 41 | Sichtbare Untertitelzeile bis zu ihrem Ende halten |
| SubtitleGeometry.swift | 60 | Lage der Untertitel auf dem Bildschirm |
| SubtitleOffset.swift | 47 | Manueller Untertitel-Versatz |
| SubtitlePicker.swift | 141 | Automatische Untertitel-Wahl beim Start |
| SubtitleStyle.swift | 203 | Aussehen von Text-Untertiteln |
| TrackChoice.swift | 228 | Spur-Panel öffnen, Spurwahl beschriften |
| TrackMemory.swift | 156 | Spur-Wahl je Serie/Film (300 Einträge) |
| TrackPanelLayout.swift | 337 | Spalten des Spur-Panels |
| TrackPanelLogic.swift | 255 | Sprachgruppen und Info-Zeilen des Spur-Panels |
| TrackPanelStyle.swift | 171 | Art, wie Ton & Untertitel im Player öffnen |
| XRayProbe.swift | 210 | Diagnose-Probe bei Pause (Regeln, Schalter-Schlüssel) |

**`Packages/PlayerCore/Sources/PlayerCore/Progress/`** (5 Dateien, 453 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| FileProgress.swift | 47 | Fortschritt für Dateien ohne IMDb-ID (200 Einträge) |
| NextEpisode.swift | 54 | `EpisodeRef`: Folgen in Ausstrahlungsreihenfolge, nächste Folge |
| StillWatching.swift | 36 | Zähler für „Noch da?“ |
| Upcoming.swift | 115 | Kommende Folgen für Kalender und „Heute neu“ |
| WatchProgress.swift | 201 | `WatchProgress`, `ProgressBook`, `ProgressStore`, `LastSource` |

**`Packages/PlayerCore/Sources/PlayerCore/Ranking/`** (8 Dateien, 1317 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| BestChoice.swift | 149 | „Sofort abspielen / Beste Wahl“ |
| DetailQualityRow.swift | 78 | Technik-Werte für die Qualitätszeile der Detailseite |
| QualityBadges.swift | 225 | Plaketten-Typen, beste Werte je Titel |
| ReleaseMatch.swift | 176 | Release der laufenden Quelle für die nächste Folge wiederfinden |
| SourceFilter.swift | 146 | Filter-Chips der Quellenliste |
| SourceRanking.swift | 113 | Sortierung der Quellenliste (Sprache, Cache, Dekoder, Dienst) |
| StreamListDisplay.swift | 183 | Anzeige-Reihenfolge, Dubletten, Zeilentext der Quellenliste |
| StreamTraits.swift | 247 | Merkmale aus Name/Beschreibung eines Streams, `AudioTrackInfo` |

**`Packages/PlayerCore/Sources/PlayerCore/Services/`** (15 Dateien, 1642 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| FetchRetryGate.swift | 52 | Sperre nach gescheitertem Abruf und genau ein neuer Versuch |
| ImageCacheBudget.swift | 34 | Grenze des Bild-Speichercaches nach freiem Speicher |
| ImageSizing.swift | 96 | Zielgröße eines Bildes, URL-Varianten |
| IntroDB.swift | 121 | IntroDB-Abfrage (Sprungbereiche) mit Frist |
| RatingIconSet.swift | 88 | Format und Grenzen des Bewertungs-Icon-Satzes |
| RatingSelection.swift | 43 | Welche Bewertungen gezeigt werden und woher |
| Ratings.swift | 75 | `ExternalRatings`, MDBList-Adresse, Auswertung, Frische-Regel |
| TMDBClient.swift | 120 | TMDB v3: Listen, Discover, Suche, IMDb-ID |
| TMDBLocalized.swift | 238 | Texte/Bilder in Profilsprache, Staffeln, kommende Folgen |
| TMDBPerson.swift | 59 | Personenseite: Stammdaten und Filmografie |
| TMDBXRay.swift | 119 | TMDB-Abrufe für die X-Ray-Galerie (Besetzung, Profilbilder) |
| TVmaze.swift | 184 | TVmaze-Sendezeiten: Client, Ratenbremse (actor), Plattencache (actor) |
| TorBox.swift | 115 | TorBox-API: eigene Dateien und Abspiel-Link |
| Trailerio.swift | 141 | Trailer von trailerio.cc mit Frist |
| YouTubeResolver.swift | 157 | YouTube-Video-ID in eine abspielbare Adresse auflösen (Innertube) |

**`Packages/PlayerCore/Sources/PlayerCore/Store/`** (8 Dateien, 714 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| BlobStorage.swift | 21 | Protokoll `BlobStorage`, Datei-Ablage `FileBlobStorage` |
| CatalogSnapshot.swift | 86 | Plattenstand der Startseiten-Kataloge (Version 1, Größen- und Altersgrenzen) |
| ProfileStore.swift | 59 | `StoredProfiles` (schemaVersion) und `ProfileStore` (laden, speichern, Export/Import) |
| RevalidationPolicy.swift | 163 | Zeitregel frisch/veraltet/abgelaufen, Zusammenführen und Ablegen von Quellenlisten |
| RowFocusMemory.swift | 38 | Fokus-Gedächtnis je Reihe |
| TaskSlots.swift | 51 | Laufende Abfragen je Schlüssel zusammenlegen, Epoche für Profilwechsel |
| TieredBlobStorage.swift | 211 | Größenbegrenzte Ablage: kleine Blöcke in UserDefaults, alles als Datei; Migration |
| TimedCache.swift | 85 | Speicher-Cache mit Ablauf, Generation und Fehlschlag-Pause |

**`Packages/PlayerCore/Sources/PlayerCore/Sync/`** (6 Dateien, 933 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| APIRequest.swift | 107 | `APIRequest`/`APIResponse`, `APISending`, 429-Wiederholung, Scrobble-Wiederholung |
| ScrobbleTracker.swift | 71 | Scrobble-Regeln start/pause/stop für eine Sitzung |
| SimklClient.swift | 79 | Simkl-API: PIN-Login, Scrobble, Playback, Merkliste |
| SyncQueue.swift | 317 | Warteschlange lokaler Änderungen je Profil, Ergebnisklassen, `SyncQueueStore`, Kachel-Menü |
| SyncWrites.swift | 118 | Senden der Warteschlangen-Einträge an Trakt/Simkl |
| TraktClient.swift | 241 | `SyncToken`, Geräte-Login, Trakt-API v2 (Scrobble, Playback, Listen) |

**`Packages/PlayerCore/Sources/PlayerCore/Update/`** (1 Dateien, 740 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| AppUpdate.swift | 740 | Build-Info, GitHub-Abfragen, Update-Entscheidung, atvloadly (REST und MCP), `InstallWatch`, `AppUpdateClient` |

**`Packages/PlayerCore/Sources/PlayerCore/XRay/`** (4 Dateien, 987 Zeilen)

| Datei | Zeilen | Zweck |
|---|---:|---|
| FaceAlignment.swift | 223 | Gesichts-Ausrichtung (Geometrie) |
| FaceMatching.swift | 210 | Vergleich von Gesichts-Einbettungen mit der Besetzungs-Galerie |
| XRayCache.swift | 308 | Geräte-Cache der X-Ray-Galerie (`XRayStore`, actor) |
| XRayGallery.swift | 246 | Galerie im Hintergrund aufbauen (`XRayGalleryBuilder`, `RequestThrottle`) |

### 1.4 Tests (`Packages/PlayerCore/Tests/PlayerCoreTests`)

Rahmen: Swift Testing (`@Test`); kein XCTest-Import gefunden. Die App selbst hat kein Test-Target (`App/project.yml:14-54` nennt nur `Player`).

| Testdatei | @Test | Abgedeckt (aus Dateiname und Testnamen abgeleitet) |
|---|---:|---|
| AddonCompatTests.swift | 16 | Addon-Kompatibilität (nachsichtiges JSON, Hinweise, Manifest-Varianten) |
| AddonMetaFetchTests.swift | 5 | Zeitgrenzen der Metadaten-Addon-Abfrage |
| AddonSubtitleTests.swift | 15 | Addon-Untertitel: Auswahl, Namen, Hash |
| AddonTests.swift | 5 | AddonClient mit Fake-HTTP (Installieren, URLs, Streams) |
| AppUpdateTests.swift | 17 | Update-Entscheidung, atvloadly-Parsing, InstallWatch, MCP |
| AppearanceTests.swift | 5 | Aussehen-Modell |
| BadgeTextTests.swift | 5 | Plaketten-Texte |
| BestChoiceTests.swift | 19 | „Beste Wahl“ |
| CollectionRowStateTests.swift | 9 | Zustand von Collection-Reihen |
| DesignTextTests.swift | 6 | Textregeln |
| DetailLoadTests.swift | 6 | Lade-Zeitleiste der Detailseite |
| DetailPageTests.swift | 8 | Regeln der Detailseite |
| DeviceSettingsTests.swift | 7 | Geräte-Einstellungen und Migration |
| DiskCacheTests.swift | 19 | Plattencache-Logik |
| FollowUpTests.swift | 12 | Nacharbeiten (gemischt) |
| FusionKitTests.swift | 13 | Fusion-Kit-Import und Abgleich |
| GenrePageTests.swift | 14 | Genre-Seite |
| HeroPlayTests.swift | 5 | Hero-Abspielen |
| HomeEditorTests.swift | 10 | Startseiten-Bearbeitung |
| HomeManagerTests.swift | 16 | Verwalter |
| HomeTopEdgeTests.swift | 19 | Oberkante/Tab-Leiste |
| LegacyProfileTests.swift | 1 | Altes Profil-JSON (Fixture main-profiles-v1.json) |
| LogRedactTests.swift | 33 | Redaktion von Logzeilen |
| MediaLabelsTests.swift | 11 | Klartext-Labels |
| ModelTests.swift | 3 | Grundmodelle |
| NavigationRulesTests.swift | 19 | Menu-Kette, Fokusregeln |
| NowPlayingTests.swift | 11 | Now-Playing-Regeln |
| NuvioImportTests.swift | 11 | Nuvio-Import (Fixture nuvio.json) |
| P2Tests.swift | 9 | Pakete/Phase-2-Funktionen |
| PackageArtTests.swift | 11 | Paket-Kachelbilder |
| PhoneInputTests.swift | 9 | HTTP-Parser, Seitenlogik |
| PhoneTests.swift | 6 | Handy-Seite (Token, Befehle) |
| PictureSoundTests.swift | 24 | Bild/Ton-Regeln |
| PlaybackRecoveryTests.swift | 22 | Fehlerklassen und Fehlerleiter |
| PlayerComfortTests.swift | 25 | Player-Komfort (Spur-Gedächtnis, Versatz u. a.) |
| PlayerInfoLabelsTests.swift | 7 | Steuerleisten-Texte |
| PosterSizeTests.swift | 5 | Kachelmaße |
| PosterTileTests.swift | 12 | Poster-Kacheln |
| QualityBadgesTests.swift | 5 | Qualitäts-Plaketten |
| RatingsTests.swift | 9 | MDBList-Auswertung |
| ReleaseMatchTests.swift | 15 | Release-Abgleich nächste Folge |
| RowCatalogTests.swift | 12 | Hinzufügen-Browser |
| SettingsSummaryTests.swift | 14 | Einstellungs-Zusammenfassungen |
| SettingsTreeTests.swift | 4 | Einstellungsbaum |
| SidePanelTests.swift | 16 | Seitenpanel |
| SkipPolicyTests.swift | 17 | Überspringen-Regeln |
| SkipSegmentsTests.swift | 15 | Sprungbereiche |
| SourceFilterTests.swift | 5 | Quellen-Filter |
| SourceRankingTests.swift | 32 | Quellen-Sortierung |
| SpeedPictureTests.swift | 24 | Tempo-/Bild-Regeln (u. a. Katalog-Plattenstand, Revalidierung) |
| StabilityTests.swift | 27 | Lade-Wächter, fehlgeschlagene Quellen, Addon-Suche |
| StoreTests.swift | 6 | ProfileStore, ProgressStore |
| StreamCacheUpdateTests.swift | 6 | Ablegen im Quellen-Cache |
| StreamListDisplayTests.swift | 15 | Anzeige der Quellenliste |
| StreamTraitsTests.swift | 13 | Stream-Merkmale |
| SubtitlePickerTests.swift | 36 | Untertitel-Automatik |
| SubtitleStyleTests.swift | 6 | Untertitel-Aussehen |
| SyncQueueTests.swift | 20 | Sync-Warteschlange |
| SyncRetryTests.swift | 9 | 429-/Scrobble-Wiederholung |
| SyncTests.swift | 9 | Trakt/Simkl-Clients mit Fake-Sender |
| TMDBTests.swift | 4 | TMDB-Client |
| TieredStorageTests.swift | 30 | Größenbegrenzte Ablage und Migration |
| TileMotionTests.swift | 21 | Bewegte Kacheln |
| TitleDisplayTests.swift | 7 | Titel-Anzeige |
| TrackChoiceTests.swift | 11 | Spurwahl |
| TrackPanelLayoutTests.swift | 19 | Spur-Panel-Layout |
| TrackPanelLogicTests.swift | 13 | Spur-Panel-Logik |
| TrackPanelStyleTests.swift | 7 | Spur-Panel-Stil |
| TrailerPersonTests.swift | 8 | YouTube-Auflösung, Personenseite |
| TrailerioTests.swift | 8 | Trailerio |
| UpcomingTests.swift | 10 | Kommende Folgen |
| VisiblePrefetchTests.swift | 17 | Vorladen sichtbarer Kacheln |
| XRayCoreTests.swift | 17 | X-Ray: Ausrichtung, Abgleich, Cache |
| XRayGalleryTests.swift | 17 | X-Ray-Galerie |
| XRayProbeTests.swift | 11 | X-Ray-Probe |

Summe: 965 `@Test` in 75 Dateien.

## 2. Hauptabläufe

### (a) App-Start → Profil laden → Startseite bedienbar

1. `App/PlayerApp.swift:6` – `@StateObject private var model = AppModel()`; `RootView` bekommt es als `environmentObject` (`:10`).
2. `App/AppModel.swift:41` – `DefaultsStorage()` → `App/DefaultsStorage.swift:12-35`: `TieredBlobStorage` aus UserDefaults + Ordnern Application Support/Player und Caches/Player (Schreibprobe `isWritable`, `:18`), LZFSE-Kompression (`:22-23`), einmalige `migrate()` (`:29`), Log der Defaults-Größe (`:33`).
3. `App/AppModel.swift:43-56` – `DeviceSettingsStore.loadOrMigrate()` (`Core/Models/DeviceSettings.swift:83-95`), vor dem ersten Speichern der Profile.
4. `App/AppModel.swift:57-58` – `ProfileStore.load()` (`Core/Store/ProfileStore.swift:34-39`): fehlende Datei → Standardprofil; nicht dekodierbar → Kopie als `profiles.json.bak`, Standardprofil.
5. `App/AppModel.swift:59-60` – `ProgressStore.load(profile:)` (`Core/Progress/WatchProgress.swift:135-139`).
6. `App/AppModel.swift:61-64` – Singletons anhängen: `CollectionLinkStore`, `FusionKitStore`, `PlaybackStability` (startet `NWPathMonitor` und Routen-Beobachter, `App/Playback/PlaybackStability.swift:27-35`), `PlayerMemory`.
7. `App/AppModel.swift:66-68` – Start-Logzeile, `observeCatalogWake()` (`App/AppModel+CatalogCache.swift:33-41`), `restoreCatalogSnapshot()` → `Task.detached` liest `catalog-<Profil>.json` aus Caches/Player/Kataloge (`App/AppModel+CatalogDisk.swift:30-47`).
8. `App/PlayerApp.swift:10` – `.task` an `RootView`: `DiskCacheProxy.cleanupAtLaunch()` (`App/Playback/DiskCacheProxy.swift:459`), `MainThreadWatchdog.apply()` (`App/MainThreadWatchdog.swift:22`), `await model.syncRemoteProgress()` (`App/AppModel.swift:183-194`; zuerst `processSyncQueue()`, `:184`).
9. `App/PlayerApp.swift:77-78` – bei mehr als einem Profil zuerst `ProfilePickerView` (`:212-234`), sonst Tabs (`:93-115`).
10. `App/Views/HomeView.swift:71-79` – Hero-Folien über `model.heroItems` (`App/AppModel.swift:610-613`); `:82` `model.preloadHomeRows(rows)` (`App/AppModel+HomeRows.swift:38-53`, höchstens 4 gleichzeitig: `Core/Models/PosterSize.swift:121`).
11. `App/Views/RowViews.swift:43-47` – jede sichtbare Reihe lädt über `model.homeRowItems` (`App/AppModel+HomeRows.swift:19-33`, eine Ladung je Profil+Quelle) → `loadItems` (`App/AppModel.swift:356-393`).
12. `App/AppModel.swift:359` – `awaitCatalogSnapshot()` (`App/AppModel+CatalogDisk.swift:50-63`): erste Reihe übernimmt den Plattenstand in `cache` (`CatalogSnapshot.restore`, `Core/Store/CatalogSnapshot.swift:79-85`; Einträge gelten als `restored` = erneuerungsbedürftig, `Core/Store/TimedCache.swift:70-74`).
13. `App/AppModel.swift:360` – Cache-Treffer: sofort zurück, `refreshCatalogIfStale` stößt die Hintergrund-Erneuerung an (`App/AppModel+CatalogCache.swift:15-30`); danach `catalogRevisions[s.id] += 1` → Reihe lädt neu (`catalogStamp`, `:9-12`).
14. `App/AppModel.swift:364-380` – ohne Treffer Netzabruf je Quellart (TMDB, Addon-Katalog, Trakt-Liste, Merkliste); Ablage `:388-389`, `scheduleCatalogSave()` `:390` → gebündeltes Schreiben 3 s später (`App/AppModel+CatalogDisk.swift:90-128`, Kodieren und Schreiben in `Task.detached`).
15. Start-Fokus: `LaunchFocus` in `App/Views/HomeHero.swift` (Schleife `:321`).

### (b) Startseite → Detail → Quellen → Wiedergabe → Up-next → Ende → Sync

Vorladen und Detailseite
1. Fokus ruht 350 ms auf einer Kachel: `App/Views/RowViews.swift:77` → `HomeFocus.set` (`App/Views/HomeHero.swift:21-27`) → `StreamPrefetcher.request` (`App/StreamPrefetcher.swift:109-132`); Seiten ohne Hero: `requestAfterRest` (`:138-147`). Sichtbare Kacheln: `tile(...)` (`:234-244`) → `visiblePass` (`:258-271`). Grenzen `:19-27` (2 laufend, 2 wartend, 12 Suchen/60 s, Reserve 4, 5 min Pause nach „alle leer“, 2 s nach Player).
2. Auswahl → `\.navigate(.detail)` → `RouteView` (`App/PlayerApp.swift:203`) → `DetailView`.
3. `App/Views/DetailViews.swift:195-268` (`.task`): IMDb-ID (`:198`, `App/AppModel.swift:396-404`; TMDB→IMDb über `tmdb.imdbID`, RAM-Cache `imdbCache`).
4. Film: Technik-Plaketten aus dem Cache (`:200-204`, `cachedStreams` `App/AppModel.swift:520-524`), sonst eigener `Task` mit `model.streams` (`:211-218`).
5. Parallel: `async let` Bewertungen (`:220` → `App/AppModel.swift:549-552` → `RatingsStore`), TMDB-Lokalisierung als eigener `Task` (`:225-229`), Meta (`:231` → `mergedMeta`, `App/AppModel+MetaAddon.swift:8-15`: Cinemeta + Metadaten-Addon + TMDB).
6. Zweiter `.task` (`:269-274`): nach `DetailLoadTimeline.giveUpMilliseconds` Logzeile der Lade-Zeitleiste.

Quellen laden (`AppModel.streams`, `App/AppModel.swift:472-517`)
7. Cache-Blick `:476-481`: `streamCacheHit` (`App/AppModel+StreamRevalidate.swift:13-25`) nach `RevalidationPolicy.streams` = 90 s frisch, bis 30 min veraltet (`Core/Store/RevalidationPolicy.swift:34`); veraltet → sofort zurück plus `revalidateStreams` (`:28-43`).
8. Läuft schon eine Abfrage zur ID, wird auf sie gewartet (`:487-493`, `TaskSlots`, `Core/Store/TaskSlots.swift`).
9. Neue Abfrage als ungebundener `Task` (`:497-512`) → `searchAddons` (`App/AppModel+StreamSearch.swift:39-52`) → `AddonClient.streams(from:type:id:timeout:onUpdate:)` (`Core/Addons/AddonSearch.swift:156-185`): alle passenden Addons parallel in einer TaskGroup, je Addon `withDeadline` (`:133-149`), Zeitgrenze aus dem Profil (Standard 15 s `:89`, geklemmt 3–120 s `:101`), Zwischenstände an `StreamSearchStatus` (`App/AppModel+StreamSearch.swift:15-22`).
10. Einzelabruf: `GET {base}/stream/{type}/{id}.json[?query]` (`Core/Addons/AddonClient.swift:112-117`, URL-Bau `:149-160`), `URLSession.shared` (`:14`).
11. Ablage `storeStreams` (`App/AppModel.swift:667-701`) über `StreamCacheUpdate.apply` (`Core/Store/RevalidationPolicy.swift:91-103`): Addons ohne Antwort behalten alte Einträge (`StreamListMerge.keepingFailed`, `:58-74`), lückenhaft → nur 60 s frisch (`Core/Addons/AddonSearch.swift:93`), leer → alter Stand bleibt und 120 s Leer-Merker (`App/AppModel.swift:675`, `:703`); höchstens 40 Einträge, schwache Stufe zuerst raus (`:690-692`, `App/StreamPrefetcher.swift:27`).
12. Ranking: Anzeige `orderedStreams` (`App/AppModel+SourceOrder.swift:19-34`: `StreamDedupe.unique`, `StreamListOrder.ordered`); automatische Wahl `autoOrderedStreams` (`:46-48`); „Beste Wahl“ `bestChoice` (`:38-43` → `Core/Ranking/BestChoice.swift`), auf der Detailseite `updateChoice` (`App/Views/DetailViews.swift:460-467`).

Quellenliste und Start
13. „Abspielen“ → `navigate(.streams(PlayRequest))` (`App/Views/DetailViews.swift:146`, `:490`, `:503`, Folge `:598`) → `StreamListView`.
14. `App/Views/DetailViews.swift:837-899` (`.task`): `streams` bzw. bei Autostart `streamsForAutoplay` (`:841-843`; `App/AppModel+StreamRevalidate.swift:47-56` wartet auf die Erneuerung eines veralteten Stands); Folgenliste nachladen (`:845-849`); Weiterschauen mit letzter Quelle (`:852-866`, `resumeCandidate` `App/AppModel+StreamSearch.swift:153-162`); „Beste Wahl“ (`:867-883`); lückenhaften Stand nachziehen (`:888-898`). Zwischenstände erscheinen über `streamSearchPartials` (`:836`).
15. `playing` gesetzt → `rememberSource` (`:911-917`, `App/AppModel.swift:89-92`) → `fullScreenCover` mit `PlayerScreen` (`:918-927`).
16. `App/Views/PlayerScreen.swift:104-110`: `StreamPrefetcher.playerAppeared`, `PlayerExtras.attach`, `AetherBackend()` (`App/Playback/PlaybackEngine.swift:120-136`), `NowPlayingBridge.stage`.
17. `PlayerControls.onAppear` (`App/Views/PlayerScreen.swift:344-360`): Scrub anbinden, `NowPlayingBridge.route`, `loadTask = Task { await loadAndStart() }`.
18. `loadAndStart` (`:414-452`): `stabilityLoadBegins()`; `engine.load` (`:419`) → `AetherBackend.load` (`App/Playback/PlaybackEngine.swift:201-228`): `LoadOptions` (Probe 8 MiB / 5 s, `:208-209`), Ton/Bild-Optionen (`:211`), Plattencache-Route + DV-P5-Vorprüfung (`:214`), `engine.load` (`:220`), bei Fehler über den Cache direkte Adresse (`:221-226`).
19. Danach Platzhalter-Erkennung (`App/Views/PlayerScreen.swift:423-427`), Tonspur (`:432-435`), Untertitel-Automatik (`:438-439`), Addon-Untertitel als `Task` (`:440`), `playUnlessHeld()` (`:442`).
20. Lade-Schritte: Engine-Stufen über `startupStatus` (`App/Playback/PlaybackEngine.swift:31`), Abbildung in `Core/Playback/StartupSteps.swift`, Anzeige `App/Views/Player/PlayerLoadingSteps.swift`.

Während der Wiedergabe
21. 1-s-Takt: `Timer.publish` (`App/Views/PlayerScreen.swift:236`), Empfang `:334-341`: alle 10 Takte `saveProgress()` (`:821-824`) → `report` → `model.recordProgress` (`:62`, `App/AppModel.swift:73-80`): `ProgressBook.record`, ggf. `recordNextUp`, `progressStore.save`, `scrobbleProgress`.
22. Scrobble: `ScrobbleTracker.progress` (`Core/Sync/ScrobbleTracker.swift:36-52`; `start` nur unter 80 %, `stop` einmal ab `ProgressBook.finishedAt` = 0.92, `Core/Progress/WatchProgress.swift:32`) → `sendScrobble` (`App/AppModel.swift:200-218`): nur IMDb-Titel, verkettete Tasks (`scrobbleChain`), je verbundenem Dienst `trakt.scrobble`/`simkl.scrobble`.
23. Pause: `onPause` (`App/Views/PlayerScreen.swift:67`) → `scrobblePause` (`App/AppModel.swift:100-103`).
24. Im selben Takt: `upNextTick()`, `stabilityTick` (`App/Views/Player/PlayerStability.swift:87`, Regeln `Core/Playback/LoadWatchdog.swift:16-23`), `idleTick`.
25. Fehler: `engine.errorText` ändert sich (`App/Views/PlayerScreen.swift:371-374`) → `recover` (`:675`), Klassen und Schritte aus `Core/Playback/PlaybackRecovery.swift`; Link neu auflösen über `model.freshStream` (`:75`, `App/AppModel+Reresolve.swift:8-25`); Aufgabe → `onFallback` (`:695`, `:720`, `:763`).

Up-next, Ende, Verlassen
26. `upNextTick` (`App/Views/PlayerScreen.swift:465-482`): Karte ab `min(skip.upNextAt, duration − 20)`, Countdown 10 s; `onNextSoon` lädt die Quellen der nächsten Folge vor (`:69-72`); `startNext` (`:484-490`) → `leave { onEnded(true) }`.
27. Dateiende: `engine.isEnded` (`:382-385`) → `finishAtEnd` (`App/Views/Player/PlayerExit.swift:23-31`; HDMI-Modus halten oder `orderlyExit`, `:45`).
28. `StreamListView.ended` (`App/Views/DetailViews.swift:1103-1120`): `autoplayNext`, ggf. „Noch da?“; `startNext` (`:1122-1149`): `streamsForAutoplay`, Release-Abgleich (`ReleaseProfile`, `Core/Ranking/ReleaseMatch.swift`), `playing = s` nach 800 ms.
29. Rückfall auf die nächste Quelle: `fallback` (`:1076-1099`), höchstens 3 automatische Wechsel, 900 ms Verzögerung.
30. Verlassen: `PlayerControls.onDisappear` (`App/Views/PlayerScreen.swift:361-370`) speichert Fortschritt, bricht `loadTask`/`addonSubTask`/`recoverTask`/`lifeTask` ab; `PlayerScreen.onDisappear` (`:94-103`): `StreamPrefetcher.playerDisappeared`, `extras.cancel()`, `model.endPlayback` (`App/AppModel.swift:95-97`, `ScrobbleTracker.end` → `stop`) oder bei Quellenwechsel `scrobblePause`. `AetherBackend.stop` schließt die Cache-Sitzung (`App/Playback/PlaybackEngine.swift:269-274`).

Sync
31. Scrobbles gehen direkt (Schritt 22), nicht über die Warteschlange.
32. `SyncQueue` gilt für Kachel-Aktionen: `perform` (`App/AppModel+SyncQueue.swift:79-116`) → lokal ändern, `record`, speichern, `processSyncQueue` (`:119-167`) → `TraktClient.apply`/`SimklClient.apply` (`Core/Sync/SyncWrites.swift:37-52`, `:92-112`); Ergebnisklassen `Core/Sync/SyncQueue.swift:193-198`.
33. Abholen des Fern-Fortschritts: `syncRemoteProgress` (`App/AppModel.swift:183-194`), Aufrufstellen: App-Start (`App/PlayerApp.swift:10`), Profilwechsel (`App/AppModel.swift:267`), erfolgreicher Login (`:148`). Weitere Aufrufstellen wurden nicht gefunden (grep).

### (c) Handy-Eingabe

1. Einstiege: `App/Views/SettingsView.swift:70`, `Settings/SettingsKit.swift:168`, `Settings/HomeSettings.swift:19`, `Settings/FusionKitSettings.swift:39`, `Home/AddRowBrowser.swift:104`.
2. `PhoneInputView.onAppear` (`App/Views/PhoneInputView.swift:118`) → `PhoneServer.start` (`:16-29`): `NWListener` TCP auf Port 8765 (`:14`, `:20`), Token aus `PhoneInputPage.randomToken()` (`:11`; 10 Zeichen aus 31, `Core/Phone/PhoneInput.swift:106-109`).
3. Adresse `http://<lokale IPv4>:8765/?t=<Token>` (`:27`, IPv4-Suche `:68-83`); QR-Code über `CIFilter.qrCodeGenerator` (`:124-129`), optional Abschnitts-Anker (`:94`).
4. Verbindung: `serve`/`receive` (`:33-61`), Parser `HTTPRequest.parse` (`Core/Phone/PhoneInput.swift:15-38`; Kopf höchstens 64 KiB, Body höchstens 8 MiB `:13`); Antworten 413/400 (`App/Views/PhoneInputView.swift:54-57`).
5. `PhoneInputPage.handle` (`Core/Phone/PhoneInput.swift:112-159`): Token in Query oder Formular, sonst 403 (`:114-116`); `GET /` Seite, `GET /export` Profil-JSON, `POST /submit` → `PhoneCommand`-Liste und 303, `POST /home` → ein Zug für „Startseite ordnen“.
6. Übernahme: Startseiten-Züge synchron vor der Antwort (`App/Views/PhoneInputView.swift:50-51` → `applyHome`, `App/AppModel+PhoneHome.swift:28-56`), übrige Befehle danach (`:53` → `AppModel.apply`, `App/AppModel.swift:558-603`).
7. Wirkung je Befehl (`App/AppModel.swift:576-599`): Addon installieren (`:287-296`), Schlüssel in `profile.apiKeys` (`:579`), Collection-Link/-Code, TMDB-/Trakt-Link als Reihe, Fusion-Kit-URL, Icon-Satz.
8. Sicherung: `GET /export` liefert `backupData()` (`App/AppModel.swift:556`, `ProfileStore.exportData`, `Core/Store/ProfileStore.swift:45-49`, alle Profile, formatiert und sortiert).
9. Wiederherstellung: `importBackup` (`App/AppModel.swift:587-593`): `store.importData` (`Core/Store/ProfileStore.swift:51-58`), `save()`, Katalog-Cache und Katalogdateien aller alten und neuen Profile löschen, Fortschritt des aktiven Profils neu laden.
10. Stopp: `PhoneInputView.onDisappear` → `server.stop()` (`App/Views/PhoneInputView.swift:119`, `:31`).

### (d) App-Update

1. Auslöser: `App/Views/Settings/UpdatePage.swift:26` bzw. `Settings/SystemSettings.swift:30` → `AppUpdater.check()` (`App/AppUpdater.swift:53-67`).
2. Eigener Build: `AppBuildInfo(info: Bundle.main.infoDictionary)` (`App/AppUpdater.swift:27`); CI schreibt `CFBundleVersion` = Laufnummer, `PlayerBuildCommit`, `PlayerBuildBranch` (`App/project.yml:34-36`, `build.yml:80`).
3. `AppUpdateClient.check` (`Core/Update/AppUpdate.swift:667-674`): `GET api.github.com/repos/<repo>/actions/workflows/build.yml/runs?branch=main&status=success&per_page=1` (`:83`), dann `GET …/releases/tags/app-main` (`:85`); 404 beim Release ist zulässig.
4. Auswertung: `parseLatestRun` (`:110-115`), `parseRelease` (`:118-127`; Build-Nummer und Commit aus dem Release-Text „Build N · Commit SHA“, Asset muss genau unter der festen IPA-Adresse liegen).
5. Entscheidung `UpdateState.decide` (`:151-161`): zuerst Commit-Vergleich (`sameCommit`, `:164-168`, mindestens 7 Zeichen); Build-Nummer nur für „installiert ist neuer“ (`:156`); sonst `available`/`notPublished`.
6. atvloadly-Adresse: aus `profile.apiKeys["atvloadly"]` (`App/Views/Settings/UpdatePage.swift:14-18`, Schlüssel `Core/Update/AppUpdate.swift:175`), Eingabe über die Handy-Seite oder Bonjour-Suche `discover()` (`App/AppUpdater.swift:138-168`: `_workstation._tcp`, 3 s, dann `GET /api/version` je Kandidat mit 4 s, `:183-189`).
7. `install` (`App/AppUpdater.swift:82-104`) → `AppUpdateClient.start` (`Core/Update/AppUpdate.swift:696-714`): `GET api/apps/installing`, `GET api/apps`, `GET api/devices`, Wegwahl `InstallRoute.plan` (`:388`).
8. Weg „Quelle“: `POST api/apps/{id}/source/update` (`:705-708`). Weg „MCP“: `POST /mcp` initialize → `notifications/initialized` → Werkzeug `install_app` → `DELETE /mcp` (`:716-739`).
9. Beobachten: `watch` (`App/AppUpdater.swift:108-132`) fragt alle 3 s `api/apps/installing`; Auswertung `InstallWatch` (`Core/Update/AppUpdate.swift:412-479`: 60 s Gnadenfrist, 20 min Gesamtfrist, 10 Fehlabfragen).

### (e) Fern-Log

1. Entdeckung: `RemoteLog.init` (`App/RemoteLog.swift:19-31`): `NWBrowser` für `_playerlog._tcp`, erstes Ergebnis wird Ziel (`:24`); `NSBonjourServices` in `App/project.yml:39`.
2. Jede Zeile: `add` (`:41-47`): `LogRedact.text` (`:42`), `os_log` mit `privacy: .public` (`:43-44`), Puffer `pending` (höchstens 500, `:46`).
3. Versand: `flush` (`:49-74`) bei Zieländerung und alle 5 s (`Timer`, `:30`): ganzer Puffer als JSON-Array, `POST /log HTTP/1.1` über `NWConnection` (TCP, unverschlüsselt), Erfolg = Antwort enthält „ 200 “ (`:62`); nur dann wird der Puffer gekürzt (`:76-79`).
4. Redaktion: `Core/Logging/LogRedact.swift:3-8` (Adressen auf Schema+Host+letzte Pfadkomponente, Werte hinter Schlüsselwörtern, lange undurchsichtige Zeichenketten); Schlüsselwörter `:153`, Muster `:149-166`. Engine-Zeilen zusätzlich über `LogRedact.text` (`App/Playback/PlaybackEngine.swift:159`); Update-Texte über `AppUpdateLog.redact` (`Core/Update/AppUpdate.swift:604`).
5. Empfänger: `tools/logcollector.py` (HTTP-Server, Standard-Port 8770, meldet sich per `avahi-publish` als `_playerlog._tcp`, schreibt `logs/player-YYYY-MM-DD.log`, lehnt über 4 MB ab).
6. Status in den Einstellungen: `RemoteLog.shared.hasReceiver` (`App/RemoteLog.swift:34`, `App/Views/Settings/SystemMaintenanceRows.swift:14`, `:45`).

### (f) Profilwechsel

1. Aufrufer: `App/PlayerApp.swift:221` (Start-Auswahl), `App/Views/Settings/ProfileSettings.swift:30`; indirekt `addProfile` (`App/AppModel.swift:270-274`) und `deleteProfile` (`:276-283`).
2. `switchProfile` (`App/AppModel.swift:252-268`): gleiches Profil → nichts (`:254`).
3. `stored.activeProfileID = id; cache.removeAll(); save()` (`:255`; `removeAll` erhöht `generation`, `Core/Store/TimedCache.swift:65`).
4. Quellen-Zustand leeren: `streamCache`, `streamAddonFetchedAt` (`:257`), `streamTasks.reset()` (neue Epoche), `streamEmptyUntil`, `streamsAllEmptyAt`, `streamPartial` (`:260`), `streamTiers` (`:261`).
5. `StreamSearchStatus.shared.reset()`, `StreamPrefetcher.shared.reset()` (`:262`, `App/StreamPrefetcher.swift:58-67`), `HeroDetailsCache.all.removeAll()`, `AddonMetaCache.reset()` (`:264`).
6. `restoreCatalogSnapshot()` (`:265`), `progress = progressStore.load(profile: id)` (`:266`), `Task { await syncRemoteProgress() }` (`:267`).
7. Träge je Profil nachgeladen: Sync-Warteschlange (`App/AppModel+SyncQueue.swift:26-36`), Spur-Gedächtnis/Datei-Fortschritt (`App/Playback/PlayerMemory.swift:41-46`, `:63-68`), `UpcomingCache`-Schlüssel enthält die Profil-ID (`App/AppModel+Upcoming.swift:25`).
8. Laufende alte Suchen: Ergebnis wird verworfen, wenn Profil/Epoche nicht mehr passen (`App/AppModel.swift:502-505`, `searchStillCurrent` `App/AppModel+StreamSearch.swift:55-57`).
9. Profil löschen: zusätzlich Katalogdatei und Warteschlangen-Datei entfernen (`App/AppModel.swift:279-280`).

## 3. Externe Schnittstellen

Allgemein: `NSAllowsArbitraryLoads: true`, `NSAllowsLocalNetworking: true` (`App/project.yml:41-43`). Wo nichts anderes steht, läuft der Abruf über `URLSession.shared` ohne eigene Zeitgrenze (Systemstandard, abgeleitet).

| Dienst | Host / Basis | Endpunkte | Auth-Art | Timeout / Retry / Cache | Aufrufer |
|---|---|---|---|---|---|
| Stremio-Addons (u. a. AIOStreams) | Nutzer-Adresse; Manifest-Query wird an jede Anfrage gehängt | `/manifest.json`, `/{catalog,meta,stream,subtitles}/{type}/{id}[/{extra}].json` | Konfiguration/Schlüssel im Pfad oder in der Query der Addon-Adresse | Streams: Frist je Addon (15 s Standard); Katalog 24 h RAM + Platte; Meta-Addon 3 s Aufrufer / 10 s Anfrage, 6 h / 10 min | `Core/Addons/AddonClient.swift:104-160`, `Core/Addons/AddonSearch.swift:156-185`, `App/AppModel.swift:371`, `App/AppModel+MetaAddon.swift:24-30` |
| Cinemeta | `v3-cinemeta.strem.io` | `/meta/{type}/{id}.json` | keine | kein eigener Timeout; kein Cache außer über die Aufrufer | `App/AppModel.swift:35-38`, `App/AppModel+MetaAddon.swift:10`, `:17-19` |
| TorBox | `api.torbox.app/v1/api` | `/{art}/mylist[?bypass_cache=true]`, `/{art}/requestdl` | Bearer-Kopf; bei `requestdl` Token als Query-Parameter | 429 einmal nach `Retry-After` | `Core/Services/TorBox.swift:32`, `:56`, `:62`, `:90`; `App/Views/TorBoxFilesRow.swift:96`, `:126` |
| TMDB | `api.themoviedb.org/3`; Bilder `image.tmdb.org/t/p/{w185,w500,w1280,h632}` | `/discover/{movie,tv}`, `/list/{id}`, `/collection/{id}`, `/search/multi`, `/find/{imdb}`, `/tv/{id}`, `/tv/{id}/season/{n}`, `/person/{id}`, Credits-/Bild-Endpunkte | `api_key` als Query-Parameter | über `HTTPFetching`; RAM-Caches im AppModel (`imdbCache`, `localizedCache`, `seasonCache`) | `Core/Services/TMDBClient.swift:10-21`, `:29-93`; `TMDBLocalized.swift:53-69`, `:188-198`; `TMDBPerson.swift:17-22`; `TMDBXRay.swift:28-70`; `App/AppModel.swift:344-347` |
| MDBList | `api.mdblist.com` | `/imdb/…?apikey=` | Schlüssel als Query-Parameter | Plattencache 24 h, „nicht gefunden“ 6 h; Tageslimit → 1 h Pause | `Core/Services/Ratings.swift:39-48`, `:72`; `App/RatingsStore.swift:16-47` |
| Trakt | `api.trakt.tv` | `/oauth/device/code`, `/oauth/device/token`, `/oauth/token`, `/scrobble/{start,pause,stop}`, `/sync/playback`, `/sync/watchlist[/remove]`, `/sync/history[/remove]`, `/users/{u}/lists/{l}/items`, `/lists/{id}/items`, `/recommendations/{movies,shows}` | Kopf mit Client-ID; Bearer-Token (OAuth-Gerätefluss), Client-Secret im Token-Body | 429 einmal nach `Retry-After` (≤ 10 s); 401 einmal Token erneuern; Scrobble `stop` einmal wiederholen | `Core/Sync/TraktClient.swift:57-198`, `Core/Sync/SyncWrites.swift:35-58`, `App/AppModel.swift:114-117` |
| Simkl | `api.simkl.com` | `/oauth/pin`, `/oauth/pin/{code}`, `/scrobble/{…}`, `/sync/playback`, `/sync/all-items/{…}`, `/sync/add-to-list`, `/sync/history[/remove]` | Client-ID als Query und Kopf, App-Name/-Version, Bearer-Token | 429 einmal nach `Retry-After`; Scrobble `stop` einmal wiederholen | `Core/Sync/SimklClient.swift:8-78`, `Core/Sync/SyncWrites.swift:60-118`, `App/AppModel.swift:119-122` |
| TVmaze | `api.tvmaze.com` | `/lookup/shows?imdb=`, `/shows/{id}/episodes` | keine | höchstens 20 Abrufe je 10 s; 429 einmal; Plattencache: Zeitpunkte 6 h, „fehlt“ 7 Tage, Fehler 5 min | `Core/Services/TVmaze.swift:7-47`, `:77-103`; `App/AppModel+Airtimes.swift:14`, `:53` |
| IntroDB | `api.introdb.app` | `/segments` | keine | Frist 4 s; 404 = kein Treffer; Treffer im Plattencache (400 Einträge) | `Core/Services/IntroDB.swift:24-25`, `:35-38`, `:96-104`; `App/Views/Player/SkipSegmentButton.swift:108` |
| Trailerio | `trailerio.cc` | `…/meta/{movie,series}/{id}.json` | keine | Frist 2,5 s | `Core/Services/Trailerio.swift:58-62`, `:72-77`, `:125-131`; `App/Views/DetailViews.swift:524` |
| YouTube (Innertube) | `www.youtube.com/youtubei/v1` | `POST /player`, `/visitor_id` | keine | 6 s je Anfrage | `Core/Services/YouTubeResolver.swift:14`, `:71`, `:99`, `:109`; `App/Views/DetailViews.swift:540` |
| GitHub (Update) | `api.github.com`, `github.com` | Workflow-Läufe, Release nach Tag, Asset-Download-Adresse | keine (öffentlich), feste Kopfzeilen | kein eigener Timeout, kein Retry | `Core/Update/AppUpdate.swift:76-88`, `:667-674` |
| GitHub (Fusion-Kit) | `raw.githubusercontent.com`, `api.github.com`, Katalog-Seite `kit.betterer.cc` | Kit-JSON, Ordner-Listing | keine | Listing-Dateien im Caches-Ordner, bei Fehler alter Stand | `Core/Import/FusionKitCatalog.swift:19-26`; `App/FusionKitStore.swift:269`, `:300-309` |
| atvloadly | Nutzer-Adresse (Standard-Port 5533) | `GET /api/version`, `/api/apps`, `/api/apps/installing`, `/api/devices`, `POST /api/apps/{id}/source/update`, `POST`/`DELETE /mcp` | keine; Konto-Kennung als MD5 im MCP-Aufruf | 10 s je Anfrage; Probe 4 s; Abfrage alle 3 s | `Core/Update/AppUpdate.swift:173-178`, `:655-739`; `App/AppUpdater.swift:41-44`, `:108-132`, `:183-189` |
| Fern-Log-Empfänger | per Bonjour `_playerlog._tcp` | `POST /log` (rohes HTTP über TCP) | keine | 5-s-Takt, Puffer 500 Zeilen | `App/RemoteLog.swift:21-74` |
| Lokaler Webserver (Handy) | Apple TV, Port 8765, HTTP | `GET /`, `GET /export`, `POST /submit`, `POST /home` | Zufalls-Token in Query/Formular | Body ≤ 8 MiB; eine Anfrage je Verbindung; `Cache-Control: no-store` | `App/Views/PhoneInputView.swift:14-64`, `Core/Phone/PhoneInput.swift:13`, `:64`, `:112-159` |
| Lokaler Proxy (Plattencache) | `127.0.0.1:<freier Port>` | `/c/<Token>/media.<ext>` (Range) | Sitzungs-Token im Pfad | 4-MiB-Blöcke, Vorlauf bis 1 GB, bei Störung direkte Adresse | `App/Playback/DiskCacheProxy.swift:7-14`, `:486-578`, `:605-607` |
| Bildserver | `image.tmdb.org`, `images.metahub.space`, Adressen aus Addons/Importen | Bilddateien | keine | 15 s Leerlauf, 6 Verbindungen je Host, URLCache 400 MB Platte, `returnCacheDataElseLoad` | `App/ImagePipeline.swift:47-56`, `:216`, `:286`; `Core/Sync/APIRequest.swift:106-107` |
| Bewertungs-Icon-Satz | Nutzer-Adresse (JSON) | eine Datei | keine | 15 s, höchstens 256 KB, Plattencache 24 h | `App/RatingIconStore.swift:12`, `:50-63`; `Core/Services/RatingIconSet.swift:10-12` |
| Collection-Links | Nutzer-Adresse | JSON-Datei, dazu Medien-Proben | keine | 20 s (Link), 10 s (Proben), höchstens 8 MiB, 30 Links | `App/CollectionLinkStore.swift:69-72`, `:183-202`, `:217` |
| Fokus-Videos | Adressen aus Importen | MP4 | keine | 15 s, Dateicache in Caches/FocusVideos | `App/Views/FocusVideo.swift:35-49` |
| Addon-Untertitel-Dateien | Adressen aus Addons | Untertiteldatei; Kopf/Ende der Mediendatei für den Hash | Kopfzeilen der Quelle beim Hash | Datei 10 s Leerlauf, ≤ 5 MB; Hash 8 s / 4 s | `App/Views/Player/PlayerPictureSound.swift:155-195`; `App/Views/Player/AddonSubtitleLoader.swift:31`, `:57` |
| Nuvio-Import per URL | Nutzer-Adresse | JSON | keine | keiner | `App/AppModel.swift:300-305` |
| Medienquelle | Adresse aus dem Stream-Eintrag | Videodatei/HLS | Kopfzeilen aus `behaviorHints.proxyHeaders` | Engine-intern | `App/Views/DetailViews.swift:919-921`, `App/Playback/PlaybackEngine.swift:205`, `:220` |
| Bonjour | `_playerlog._tcp`, `_workstation._tcp` | – | – | – | `App/project.yml:39`, `App/RemoteLog.swift:21`, `App/AppUpdater.swift:144` |

Hinweise: Ein TVDB-Schlüssel wird angenommen und gespeichert (`Core/Phone/PhoneInput.swift:102`); ein Aufruf eines TVDB-Hosts wurde nicht gefunden (grep nach Hostnamen). `XRayStore`/`XRayGalleryBuilder` (PlayerCore) werden in `App/Sources` nicht instanziiert (grep); die App nutzt nur die Probe (`App/Views/Player/XRayProbeHook.swift`).

## 4. Persistenz

### 4.1 Speicherorte

Blöcke der App-Ablage (`DefaultsStorage` → `TieredBlobStorage`): UserDefaults-Schlüssel `blob.<Name>` (LZFSE-komprimiert), zusätzlich unkomprimierte Datei `<Name>` in jedem beschreibbaren Ordner (Application Support/Player, Caches/Player); gelesen wird zuerst UserDefaults, sonst die jüngste Datei (`Core/Store/TieredBlobStorage.swift:76-93`, `App/DefaultsStorage.swift:14-23`).

| Speicherort | Inhalt | Format | Grenze | Schreibt / liest | Lebensdauer |
|---|---|---|---|---|---|
| Block `profiles.json` | alle Profile inkl. Einstellungen, Addons, Collections, Startseite, API-Schlüssel, OAuth-Tokens | JSON; in UserDefaults LZFSE | UserDefaults-Vorbehalt 512 KB (`TieredBlobStorage.swift:37`), darüber nur Datei | `Core/Store/ProfileStore.swift:34-43`; `App/AppModel.swift:58`, `:240-242` | UserDefaults: dauerhaft (abgeleitet: übersteht Update bei gleicher Bundle-ID); Datei in Caches löschbar |
| Datei `profiles.json.bak` | unlesbare Profildatei | roh | nur Datei (`:68`) | `ProfileStore.swift:37` | wie Datei-Ablage |
| Block `device-settings.json` | Bild & Ton je Gerät | JSON | Vorbehalt 8 KB (`:31`) | `Core/Models/DeviceSettings.swift:83-99`; `App/AppModel.swift:46`, `:245-248` | wie oben |
| Block `progress-<Profil>.json` | `ProgressBook`: Fortschritt, letzte Quelle | JSON, Datum ISO-8601 | ≤ 96 KB komprimiert in UserDefaults, alle „übrigen“ zusammen ≤ 128 KB (`:35-41`), sonst nur Datei | `Core/Progress/WatchProgress.swift:129-145`; `App/AppModel.swift:60`, `:78`, `:85`, `:91`, `:192` | wie oben |
| Block `syncqueue-<Profil>.json` | Sync-Warteschlange | JSON | wie „übrige“; Einträge verfallen nach 30 Tagen | `Core/Sync/SyncQueue.swift:202-226`; `App/AppModel+SyncQueue.swift:26-42` | wie oben |
| Block `failed_links.json` | fehlgeschlagene Quellen | JSON | 8 h, 60 Titel | `Core/Playback/FailedLinks.swift:30-35`, `:125-133`; `App/Playback/PlaybackStability.swift:30`, `:99` | wie oben |
| Blöcke `trackmemory-<Profil>.json`, `fileprogress-<Profil>.json` | Spur-Wahl, Datei-Fortschritt | JSON | 300 bzw. 200 Einträge | `App/Playback/PlayerMemory.swift:72-88` | wie oben |
| Block `introdb-cache.json` | IntroDB-Treffer | JSON | 400 Einträge | `Core/Playback/SkipSegmentStore.swift:18-20`, `:93-99`; `App/Views/Player/SkipSegmentButton.swift:10`, `:72-76` | wie oben |
| Dateien `import-media-<Profil>-<id>.json` | Medien eines Collection-Imports | JSON | nur Datei (Präfix `import-`, `:44`) | `App/CollectionLinkStore.swift:89`, `:157` | Datei-Ablage |
| Block `linkpack-<Profil>-<id>.json` | Preview-Pack eines Links | JSON | wie „übrige“ | `App/CollectionLinkStore.swift:92`, `:127` | wie oben |
| UserDefaults `collectionlinkmeta.<Profil>` (alt: `collectionlinks.<Profil>`) | Liste der Collection-Links | JSON-Data | höchstens 30 Links | `App/CollectionLinkStore.swift:85-86`, `:99-109`, `:134-135` | dauerhaft |
| UserDefaults `fusionkit.<Profil>` | Fusion-Kit-Einstellungen | JSON-Data | – | `App/FusionKitStore.swift:208-222` | dauerhaft |
| UserDefaults `deviceSettingsMigrated.v1` | Merker der einmaligen Migration | Bool | – | `App/AppModel.swift:43-45` | dauerhaft |
| UserDefaults `diag.hitchLog`, `debug.xrayProbe` | Diagnose-Schalter | Bool (`@AppStorage`) | – | `App/MainThreadWatchdog.swift:11-19`; `App/Views/Settings/SystemMaintenanceRows.swift:9-10` | dauerhaft |
| UserDefaults `xray.profile5Sources` | gemerkte DV-P5-Quellen | JSON-Data | – | `App/Playback/XRayProfile5.swift:18-27` | dauerhaft |
| Caches/Player/Kataloge/`catalog-<Profil>.json` | Startseiten-Kataloge | JSON (Version 1), Datum als Sekunden | ≤ 4 MiB, 60 Reihen × 100 Einträge, 14 Tage | `App/AppModel+CatalogDisk.swift:21-24`, `:30-47`, `:90-128`; `Core/Store/CatalogSnapshot.swift:7-15` | tvOS darf löschen; dann leerer Start (`AppModel+CatalogDisk.swift:9`) |
| Caches/`ratings.json` | MDBList-Bewertungen | JSON | 4000 Einträge | `App/RatingsStore.swift:14`, `:49-60` | löschbar |
| Caches/`tvmaze.json` | TVmaze-IDs und Sendezeiten | JSON | 300 IDs | `App/AppModel+Airtimes.swift:14-15`; `Core/Services/TVmaze.swift:107`, `:151-162` | löschbar |
| Caches/`rating-icons.json` | Icon-Satz | JSON | 256 KB Quelle, 24 h | `App/RatingIconStore.swift:12`, `:32`, `:63` | löschbar |
| Caches/`images/` | Bild-Antworten (URLCache) | URLCache | 400 MB Platte, 20 MB RAM (4 MB bei Wiedergabe) | `App/ImagePipeline.swift:15-16`, `:47-49` | löschbar |
| Caches/`DiskCache/<Token>/` | Blöcke des laufenden Films | Binärblöcke | Einstellung 4/8/16/32 (`Core/Models/DiskCacheSettings.swift:10`); beim Start geleert | `App/Playback/DiskCacheProxy.swift:455-472` | nur während einer Wiedergabe |
| Caches/`FocusVideos/` | Fokus-Videos | MP4 | Byte-Grenze je Topf | `App/Views/FocusVideo.swift:35-53`, `:145-152` | löschbar |
| Caches/`AddonSubtitles/` | umgewandelte Untertiteldateien | UTF-8-Text | Aufräumen nach 24 h | `App/Views/Player/PlayerPictureSound.swift:160-166`, `:207`, `:253-258` | löschbar |
| Caches (Fusion-Kit) | Kit-Dateien, Listings | JSON | – | `App/FusionKitStore.swift:34`, `:156`, `:274`, `:305` | löschbar |
| Application Support (Fusion-Kit) | eingefügte Kit-Dateien (`import-paste-<Schlüssel>.json`) | JSON | – | `App/FusionKitStore.swift:37`, `:175-186` | abhängig von der Schreibbarkeit (tvOS, `App/DefaultsStorage.swift:6-7`) |
| Application Support/Player | Kopien aller Blöcke, falls beschreibbar | wie oben | – | `App/DefaultsStorage.swift:14-21` | wie oben |
| Documents | nicht benutzt (grep) | – | – | – | – |
| Keychain | nicht benutzt (grep nach `Keychain`/`SecItem` ohne Treffer) | – | – | – | – |
| Nur RAM | Katalog-Cache (`TimedCache`, 24 h), Quellen-Cache (40 Einträge, 90 s/30 min), `UpcomingCache` (6 h, Fehler 5 min), `AddonMetaCache` (300), `imdbCache`/`localizedCache`/`seasonCache`, `HeroDetailsCache`, `QualityBadgeCache` (400), `StreamSearchStatus` (30), Log-Puffer (500), Handy-Token | – | siehe links | `App/AppModel.swift:23`, `:533`; `App/AppModel+Upcoming.swift:8-16`; `App/AppModel+MetaAddon.swift:121-173`; `App/Views/QualityBadges.swift:109` | bis zum App-Ende |

### 4.2 Migrationen

| Mechanismus | Beleg |
|---|---|
| `StoredProfiles.schemaVersion` (aktuell 1); höhere Version → `StoreError.newerSchema`; leere Profilliste → `.empty`; in `load()` führt jeder Dekodierfehler zu `.bak` + Standardprofil | `Core/Store/ProfileStore.swift:4-5`, `:34-39`, `:53-58` |
| `Profile.init(from:)`: `decodeIfPresent` mit Standardwerten für alle Felder außer `id`; neuere Blöcke (`sources`, `player`, `hiddenRows`, `subtitleStyle`, `skip`) zusätzlich mit `try?` | `Core/Models/Profile.swift:81-112` |
| Altes Feld `subtitlesEnabled` → `subtitleMode` | `Core/Models/Profile.swift:78`, `:88-94` |
| Alte Profilfelder `audioShaping`/`displayMode` werden ignoriert und einmalig in die Geräte-Einstellungen übernommen (Merker in UserDefaults) | `Core/Models/Profile.swift:38-39`; `Core/Models/DeviceSettings.swift:29-33`, `:83-95`; `App/AppModel.swift:42-56` |
| `ProgressBook.schemaVersion = 1` (wird beim Lesen nicht geprüft); Dekodierfehler → leeres Buch; `sources` optional für alte Dateien | `Core/Progress/WatchProgress.swift:34-37`, `:135-139` |
| `SyncQueue.schemaVersion = 1`; zweiter Leseversuch mit ISO-8601-Daten, Schlüssel werden neu gebildet | `Core/Sync/SyncQueue.swift:67`, `:208-218` |
| `CatalogSnapshot.version` muss 1 sein, sonst wird die Datei gelöscht | `Core/Store/CatalogSnapshot.swift:7`, `:61-64`; `App/AppModel+CatalogDisk.swift:41-44` |
| `XRayCacheFormat.version = 1`, fremde Version → Datei löschen | `Core/XRay/XRayCache.swift:122`, `:246-247` |
| `TieredBlobStorage.migrate()` bei jedem Start: zu große/überzählige UserDefaults-Blöcke in Dateien verschieben | `Core/Store/TieredBlobStorage.swift:146-168`; `App/DefaultsStorage.swift:29-32` |
| Collection-Links: alter Schlüssel → neuer Schlüssel + Blöcke (`adoptMissing`) | `App/CollectionLinkStore.swift:99-109`; `Core/Store/TieredBlobStorage.swift:204-210` |
| Test mit altem Profil-JSON | `Packages/PlayerCore/Tests/PlayerCoreTests/LegacyProfileTests.swift`, Fixture `main-profiles-v1.json` |

### 4.3 Schlüssel und Tokens (nur Art)

- API-Schlüssel und Client-IDs/-Secret: `Profile.apiKeys` (Wörterbuch Dienst → Text) im Block `profiles.json` (`Core/Models/Profile.swift:24-25`); Dienste-Liste `Core/Phone/PhoneInput.swift:102`. Auch die atvloadly-Adresse liegt dort (`Core/Update/AppUpdate.swift:175`).
- OAuth-Tokens (Zugangs-, Erneuerungs-Token, Ablauf): `Profile.syncTokens` im selben Block (`Core/Models/Profile.swift:30-31`, `Core/Sync/TraktClient.swift:4-11`).
- Der Profil-Export (`GET /export`) enthält beides (`Core/Store/ProfileStore.swift:45-49`, Kommentar `Profile.swift:24`).
- Addon-Adressen (können Konfiguration/Schlüssel tragen) in `Profile.addons` (`Core/Addons/AddonClient.swift:28-41`).
- Im Repo selbst: laut README keine Schlüssel; CI prüft das IPA (`tools/check_ipa.sh`).

## 5. Nebenläufigkeitsmodell

### 5.1 Sprachmodus je Target

| Target | Einstellung | Beleg |
|---|---|---|
| App `Player` | `SWIFT_VERSION: "5.0"`; kein `SWIFT_STRICT_CONCURRENCY` gesetzt (Standard, abgeleitet) | `App/project.yml:47` |
| PlayerCore | `swift-tools-version: 6.0`, keine `swiftLanguageModes`/`swiftSettings` → Swift-6-Modus (abgeleitet) | `Packages/PlayerCore/Package.swift:1-12` |
| AetherFEL | `swift-tools-version: 6.1` | `Packages/AetherFEL/Package.swift:1` |

### 5.2 Typen und Isolation

| Typ | Isolation | Geteilte Daten | Ort |
|---|---|---|---|
| `AppModel` | `@MainActor`, `ObservableObject` | Profile, Fortschritt, alle RAM-Caches, Task-Tabellen | `App/AppModel.swift:5-6` |
| `CatalogDiskStore` | `@MainActor` | Lese-/Schreib-Tasks des Katalog-Plattenstands | `App/AppModel+CatalogDisk.swift:10-26` |
| `StreamSearchStatus`, `UpcomingRevision`, `UpcomingCache`, `SyncQueueHolder`, `AddonMetaCache` (enum mit statischem Zustand) | `@MainActor` | Suchstände, Kalender, Warteschlange, Meta-Antworten | `App/AppModel+StreamSearch.swift:5-6`; `+Airtimes.swift:5-6`; `+Upcoming.swift:5-6`; `+SyncQueue.swift:5-6`; `+MetaAddon.swift:121` |
| `StreamPrefetcher` | `@MainActor` | Laufende/wartende Vorlade-Jobs, Budget, Player-Kennzeichen | `App/StreamPrefetcher.swift:16-17` |
| `RemoteLog` | `@MainActor` | Log-Puffer, Bonjour-Ziel | `App/RemoteLog.swift:8-9` |
| `AppUpdater`, `PlaybackStability`, `PlayerMemory`, `PhoneServer`, `MainThreadWatchdog` (enum) | `@MainActor` | Update-Phase; Netz/Route/Fehlerbuch; Spur-Bücher; Listener; Runloop-Beobachter | `App/AppUpdater.swift:8-9`; `App/Playback/PlaybackStability.swift:11-12`; `App/Playback/PlayerMemory.swift:7-8`; `App/Views/PhoneInputView.swift:7-8`; `App/MainThreadWatchdog.swift:9-10` |
| `AetherBackend` / Protokoll `PlaybackEngine` | `@MainActor` | Engine-Instanz, Cache-Sitzung | `App/Playback/PlaybackEngine.swift:8-9`, `:109-110` |
| `CollectionLinkStore`, `FusionKitStore`, `RatingIconStore`, `QualityBadgeCache`, `TabBarGuard`, `FocusVideoPlayer` | `@MainActor`-Klassen mit `static let shared` | Importe, Kit-Auswahl, Icons, Plaketten, Leisten-Zustand, AVPlayer | `App/CollectionLinkStore.swift:53-54`; `App/FusionKitStore.swift:9-10`; `App/RatingIconStore.swift:6-7`; `App/Views/QualityBadges.swift:101`; `App/Views/TabBarGuard.swift:12`; `App/Views/FocusVideo.swift:164` |
| `RatingsStore` | `actor` | Einträge, laufende Anfragen, Pause | `App/RatingsStore.swift:6` |
| `ImagePipeline` | `actor`; `NSCache` als `nonisolated(unsafe)`; Hilfsklassen mit `NSLock` (`CacheCostTracker`, `CancelFlag`, `LockedKeys`, `CacheStats`, alle `@unchecked Sendable`) | Bildcache, laufende Ladungen | `App/ImagePipeline.swift:12`, `:21`, `:349`, `:367`, `:530`, `:538`, `:554` |
| `DiskCacheProxy`, `DiskCacheSession` | `actor`; eigene `DispatchQueue` für das Netz; `DiskCacheOriginFetcher` und `DiskCacheOnce` mit `NSLock`, `@unchecked Sendable` | Listener, Sitzung, Blockindex | `App/Playback/DiskCacheProxy.swift:45-46`, `:56`, `:75`, `:145`, `:435-440` |
| `FocusVideoCache` | `actor`; `FirstReplica` `@unchecked Sendable` | Videodateien | `App/Views/FocusVideo.swift:15`, `:421` |
| `XRayCancelFlag`, `XRayImage` | `OSAllocatedUnfairLock` bzw. `@unchecked Sendable` | Abbruch-Merker, Bild | `App/Views/Player/XRayProbeHook.swift:71-72`, `:143` |
| `HomeFocus`, `HeroSlides`, `HomeTopEdgeWatch`, `HomeRowsSession` | `@MainActor @Observable` | View-Zustand | `App/Views/HomeHero.swift:10`, `:45`; `App/Views/HomeTopEdgeWatch.swift:11`; `App/Views/Home/HomeRowsSession.swift:9` |
| `ProfileStore`, `DeviceSettingsStore` | `final class`, `@unchecked Sendable`, kein Lock (nur unveränderliche Felder) | Ablage | `Core/Store/ProfileStore.swift:24`; `Core/Models/DeviceSettings.swift:57` |
| `TieredBlobStorage`, `FileBlobStorage`, `ProgressStore`, `SyncQueueStore`, `AddonClient`, `TraktClient`, `SimklClient`, `TMDBClient`, `AppUpdateClient` | `struct`, `Sendable` | keine veränderlichen Daten | `Core/Store/TieredBlobStorage.swift:25`; `Core/Store/BlobStorage.swift:11`; `Core/Progress/WatchProgress.swift:130`; `Core/Sync/SyncQueue.swift:202`; `Core/Addons/AddonClient.swift:43`; `Core/Sync/TraktClient.swift:50`; `Core/Sync/SimklClient.swift:4`; `Core/Update/AppUpdate.swift:647` |
| `TimedCache`, `TaskSlots`, `SyncQueue`, `ProgressBook`, `ScrobbleTracker` | Wert-Typen, gehalten vom `@MainActor`-Modell | – | `Core/Store/TimedCache.swift:6`; `Core/Store/TaskSlots.swift:9`; `Core/Sync/SyncQueue.swift:62`; `Core/Sync/ScrobbleTracker.swift:17` |
| `AsyncLimiter`, `TVmazeGate`, `TVmazeAirtimes`, `XRayStore`, `XRayGalleryBuilder`, `RequestThrottle` | `actor` | Plätze, Ratenfenster, Plattencache, Galerie | `Core/Addons/AsyncLimiter.swift:5`; `Core/Services/TVmaze.swift:77`, `:100`; `Core/XRay/XRayCache.swift:176`; `Core/XRay/XRayGallery.swift:61`, `:118` |
| `MemoryKeyValueBlobs`, `ResumeOnce` | Klasse mit `NSLock`, `@unchecked Sendable` | Testspeicher; einmaliges Fortsetzen | `Core/Store/TieredBlobStorage.swift:188-190`; `Core/Addons/AddonMetaFetch.swift:81-82` |
| Statische Formatierer/Regex | `nonisolated(unsafe) static let` | `ISO8601DateFormatter`, `NSRegularExpression` | `Core/Models/ISODate.swift:6-12`; `Core/Logging/LogRedact.swift:149-166`; `Core/Ranking/StreamTraits.swift:110-115` |
| `ScrubPreviewCache` | `struct`, `@unchecked Sendable` | Vorschaubilder | `Core/Playback/ScrubPlanner.swift:320` |

### 5.3 Langlebige Tasks, Timer, Beobachter

| Was | Start | Ende / Abbruch |
|---|---|---|
| `RemoteLog`: `NWBrowser` und 5-s-`Timer` | `App/RemoteLog.swift:21-30` (erster Zugriff auf `shared`) | kein Stopp im Code (lebt bis App-Ende) |
| `PlaybackStability`: `NWPathMonitor`, zwei AVAudioSession-Beobachter | `App/Playback/PlaybackStability.swift:39-67` | kein Stopp |
| Katalog-Wake-Beobachter (`didBecomeActive`) | `App/AppModel+CatalogCache.swift:34` | Token wird verworfen (`_ =`), kein Abmelden |
| `ImagePipeline`: Speicherwarnungs-Beobachter | `App/ImagePipeline.swift:61-63` | kein Abmelden |
| `MainThreadWatchdog`: `CFRunLoopObserver` | `App/MainThreadWatchdog.swift:31-42` | `stop()` `:44-50` beim Umschalten |
| Katalog lesen (`Task.detached`) / schreiben (`saveTask`) | `App/AppModel+CatalogDisk.swift:39`, `:96` | `saveTask?.cancel()` in `restoreCatalogSnapshot` (`:35`), `clearCatalogCache` (`:70`), neuem `scheduleCatalogSave` (`:95`) |
| Katalog-Erneuerung je Quelle | `App/AppModel+CatalogCache.swift:18` | läuft aus; `catalogRefreshing` verhindert Doppelte |
| Reihen-Ladung | `App/AppModel+HomeRows.swift:24` | läuft bewusst weiter, auch wenn die Reihe verschwindet (`:13-14`) |
| Quellensuche | `App/AppModel.swift:497` | nicht abbrechbar durch die Seite; endet spätestens nach der Addon-Frist (`App/AppModel+StreamSearch.swift:35-36`); nach Profilwechsel wird das Ergebnis verworfen |
| Hintergrund-Erneuerung der Quellen | `App/AppModel+StreamRevalidate.swift:32` | läuft aus |
| Scrobble-Kette | `App/AppModel.swift:205` | läuft aus; nächster Task wartet auf den vorigen |
| Trakt-Token-Erneuerung | `App/AppModel.swift:167` | eine zur Zeit (`traktRefresh`) |
| Meta-Addon-Abfrage | `App/AppModel+MetaAddon.swift:145` | `leave` bricht ab, wenn keine Kachel mehr wartet (`:160-163`); `reset()` beim Profilwechsel (`:166-169`) |
| Vorladen: Fokus-Job, Ruhe-Task, Durchlauf, sichtbare Jobs | `App/StreamPrefetcher.swift:193`, `:140`, `:250`, `:290` | `cancelRest` (`:150`), `playerAppeared` (`:85-86`), `reset` (`:62`) |
| Update-Abfrage-Schleife | `App/AppUpdater.swift:110-131` | `poll?.cancel()` beim nächsten `watch` (`:109`); endet bei Endzustand |
| Kalender-Abruf, Sendezeiten | `App/AppModel+Upcoming.swift:36`; `App/AppModel+Airtimes.swift:21` | laufen aus |
| Handy-Server (`NWListener`) | `App/Views/PhoneInputView.swift:20-26` | `stop()` in `onDisappear` (`:119`) |
| Plattencache-Listener | `App/Playback/DiskCacheProxy.swift:605-641` | `close`/`giveUp` (`:548-565`); `AetherBackend.stop` (`App/Playback/PlaybackEngine.swift:273`) |
| Player: 1-s-`Timer.publish` | `App/Views/PlayerScreen.swift:236` | endet mit dem View |
| Player: `loadTask`, `addonSubTask`, `recoverTask`, `lifeTask`, `hideTask`, `seekTask`, `audioSwitchTick` | `App/Views/PlayerScreen.swift:359`, `:440`, `:749`, `:831`, `:652`, `:602` | `onDisappear` (`:368`), `orderlyExit` (`App/Views/Player/PlayerExit.swift:46`), `leave` (`App/Views/PlayerScreen.swift:457`) |
| Pause-Karte: 0,5-s-Timer | `App/Views/Player/PlayerPauseCard.swift:78` | endet mit dem View |
| Geräte-Login-Schleife | `App/Views/SyncLoginView.swift:46-56` | endet mit dem View-Task (abgeleitet) |
| Detailseite: `.task`-Ladungen, Trailer-Task | `App/Views/DetailViews.swift:195`, `:269`, `:275` | SwiftUI bricht `.task` beim Verschwinden ab; `trailerTask?.cancel()` (`:300`); der Quellen-`Task` (`:211`) ist ungebunden |

## 6. State-Management

| Punkt | Fakt | Beleg |
|---|---|---|
| Art | `ObservableObject` mit `@Published` (kein `@Observable`) | `App/AppModel.swift:5-6` |
| Gespeicherte Eigenschaften | 31 im Klassenrumpf, davon 7 `@Published` (`stored`, `lastError`, `notice`, `device`, `progress`, `catalogRevisions`, `catalogWake`) | `App/AppModel.swift:7-32`, `:108-112`, `:407`, `:419-421`, `:533-546` |
| Methoden | 50 `func` in `AppModel.swift` (inkl. der 3 Erweiterungen dort); in den 13 `AppModel+*.swift` weitere ca. 55–69 (grep, enthält einige Funktionen anderer Typen derselben Dateien) | grep `func` |
| Erweiterungen | 20 `extension AppModel`: 3 in `AppModel.swift` (`:608`, `:643`, `:709`), 13 in `AppModel+*.swift`, 4 in Views (`Views/SettingsView.swift:95`, `Views/Player/AddonSubtitleLoader.swift:11`, `Views/Player/SkipSegmentButton.swift:4`, `Views/Settings/SourceSettingsRows.swift:51`) | grep |
| Ausgelagerter Zustand | Sync-Warteschlange in `SyncQueueHolder.shared`, Kalender in `UpcomingCache.shared`, Meta-Antworten in `AddonMetaCache` (statisch) – jeweils „außerhalb der gespeicherten Eigenschaften“ | `App/AppModel+SyncQueue.swift:4-14`; `+Upcoming.swift:5-17`; `+MetaAddon.swift:121-127` |
| Einspeisung | einmal `@StateObject` in `PlayerApp`, weiter als `environmentObject`; `PlayerScreen` bekommt es im `fullScreenCover` erneut gesetzt | `App/PlayerApp.swift:6`, `:10`; `App/Views/DetailViews.swift:927` |
| Beobachter | 70 Deklarationen `@EnvironmentObject var model: AppModel` in 43 Dateien (u. a. `RootView`, `HomeView`, `DetailView`, `StreamListView`, `PlayerScreen`, alle Einstellungsseiten) | grep |
| Schreibweg Profil | `model.update { … }` → Kopie ändern → `save()` (ganzes `StoredProfiles`) | `App/AppModel.swift:234-242` |
| Weitere `ObservableObject` | `AppUpdater`, `StreamSearchStatus`, `UpcomingRevision`, `CollectionLinkStore`, `FusionKitStore`, `RatingIconStore`, `PlaybackStability`, `PlayerMemory`, `PhoneServer`, `SkipSegmentController`, `ScrubController`, `PlayerExtras`, `PauseCardState`, `PanelSwipe`, `AetherBackend` | grep `ObservableObject` |
| `@Observable` | `HomeFocus`, `HeroSlides`, `HomeTopEdgeWatch`, `HomeRowsSession` | siehe 5.2 |

Singletons (`static let shared`, 19): `RemoteLog`, `AppUpdater`, `StreamPrefetcher`, `StreamSearchStatus`, `UpcomingRevision`, `UpcomingCache`, `SyncQueueHolder`, `RatingsStore`, `RatingIconStore`, `ImagePipeline`, `CollectionLinkStore`, `FusionKitStore`, `PlaybackStability`, `PlayerMemory`, `DiskCacheProxy`, `QualityBadgeCache`, `TabBarGuard`, `FocusVideoCache`, `FocusVideoPlayer`. Dazu statischer Zustand ohne `shared`: `AddonMetaCache`, `HeroDetailsCache`, `LaunchFocus`, `MainThreadWatchdog`, `AppModel.airtimes` (`App/AppModel+Airtimes.swift:14`), `SkipSegmentController.disk` (`App/Views/Player/SkipSegmentButton.swift:68-69`). PlayerCore enthält kein `static let shared`.

## 7. CI / Release (`.github/workflows/build.yml`)

- Auslöser: Push auf jeden Branch, wenn sich `App/**`, `Packages/**`, `.github/workflows/**`, `tools/release_notes.sh`, `tools/check_ipa.sh` oder `tools/xray_model/**` ändert; Tags starten nichts; zusätzlich `workflow_dispatch` mit `release_dry_run` (`:2-12`).
- Rechte: standardmäßig `contents: read`; Schreibrecht nur in den Jobs `release` und `publish` (`:15-16`, `:155-156`, `:257-258`).
- Job `build` (`macos-26`, 40 min, `:18-21`): Actions auf Commit gepinnt (`:24`, `:46`, `:52`, `:134`).
  - Xcode-Wahl: höchste von `Xcode_27*` bzw. `Xcode_26.3*` (`:31`).
  - SFace-Modell: Cache-Schlüssel aus Skript-Hash + gepinntem ONNX-SHA-256, sonst Python 3.11, `pip --require-hashes`, Umwandlung und Prüfung (`:37-71`).
  - `xcodegen generate` (`:73`); `xcodebuild … Release -sdk appletvos`, ohne Signatur, mit `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`, `PLAYER_BUILD_COMMIT`, `PLAYER_BUILD_BRANCH` (`:78-83`).
  - Prüfungen: FEL-Bauwächter und Trait-Flags im Build-Log (`:84-101`), kein direktes `import AetherEngine` in `App/Sources` (`:102-105`), Engine-Frameworks, Ressourcen-Bundle und `SFace.mlmodelc` im IPA, Gewichtsdatei ≥ 15 MB (`:112-132`).
  - IPA packen (`:106-111`), Artefakt `Player-ipa` 14 Tage (`:139-144`), Build-Log nur bei Fehler (`:133-138`).
- Tests: kein Schritt führt `swift test` oder `xcodebuild test` aus (grep in `.github` und `tools` ohne Treffer); laut README laufen die PlayerCore-Tests lokal (`README.md:86-91`).
- Job `history` (`ubuntu-latest`, `:198-248`): Modus `publish` nur auf `integ`/`main` und ohne Dry-Run (`:217-226`); `tools/check_ipa.sh` (private LAN-Adressen, Linux-Home-Pfade, JWT, Hex-Schlüssel, optionale Denylist aus einem Secret; `tools/check_ipa.sh:34-65`); Release-Notizen aus `## [Unreleased]` der `CHANGELOG.md` (`tools/release_notes.sh`).
- Job `publish` (`:249-294`): Release `build-<Laufnummer>` mit `Player.ipa`; `integ` → Prerelease, `main` → Release „Latest“; vorhandenes Release bleibt, Entwurf wird ersetzt; bei Fehlschlag Hinweis auf `tools/backfill_releases.sh`.
- Job `release` (nur `main`, `:145-197`): rollendes Release `app-main` (nicht „Latest“); Text „Build N · Commit SHA · Branch main“ ist das Format, das die App liest (`:172-173`); erst Text, dann Paket (`:182-184`); Tag `app-main` wird nachgezogen, darf fehlschlagen (`:189-197`).
- Build-Nummer: `github.run_number` = `CFBundleVersion`; zählt jeden Lauf, veröffentlichte Builds haben Lücken (`README.md:120-124`).
- Branch-Modell: `main` = am Gerät getestet, Quelle von `app-main`; `integ` = Testzweig, Stufen werden dort zusammengeführt und nach Gerätetest nach `main` gebracht; Feature-Branches bauen, veröffentlichen aber nichts (`README.md:104-135`).

## 8. Fehler- und Retry-Strategie je Dienst

| Dienst | Timeout | Retry / Backoff | Rate-Limit | Offline / Fehler | Cache | Beleg |
|---|---|---|---|---|---|---|
| Addon-Streams | Frist je Addon aus dem Profil (15 s, wählbar 8–45 s, geklemmt 3–120 s); darunter `URLSession.shared` | keiner je Abruf; veralteter Stand wird im Hintergrund neu geholt | „alle Addons leer“ → 5 min kein Vorladen/keine Erneuerung; leere ID 120 s | Addon mit Fehler/Zeitüberschreitung behält alte Einträge; Statuszeile je Addon, Hinweis „Keine Netzverbindung“ | RAM: 90 s frisch, 30 min veraltet, lückenhaft 60 s, 40 Einträge | `Core/Addons/AddonSearch.swift:89-101`, `:133-149`; `App/AppModel.swift:508`, `:667-703`; `App/StreamPrefetcher.swift:24`; `Core/Store/RevalidationPolicy.swift:34-43`; `App/AppModel+StreamSearch.swift:69-73` |
| Addon-Katalog | keiner eigener | Hintergrund-Erneuerung; nach Fehlschlag frühestens nach 10 min | – | Fehler → `CatalogLoad(failed: true)`, Reihe zeigt „Laden fehlgeschlagen“; leere Erneuerung überschreibt keinen gefüllten Stand | RAM 24 h + Plattenstand (14 Tage) | `App/AppModel.swift:380`, `:387-389`; `App/AppModel+CatalogCache.swift:15-30`; `Core/Store/TimedCache.swift:22`, `:36-40`, `:81-84` |
| Addon-Meta (Metadaten-Addon) | Aufrufer wartet 3 s, Anfrage läuft bis 10 s | keiner | höchstens 4 Kachel-Abfragen gleichzeitig | Fehler → 10 min als „keine Antwort“ gemerkt; Abbrüche nicht gemerkt | RAM 6 h, 300 Einträge | `Core/Addons/AddonMetaFetch.swift:16-18`; `App/AppModel+MetaAddon.swift:127-133`, `:148-152`, `:172` |
| Cinemeta | keiner eigener | keiner | – | Fehler → `nil` (`try?`) | keiner | `App/AppModel+MetaAddon.swift:17-19` |
| TMDB | keiner eigener | Lokalisierung: Mitwartende fragen nach einem Fehlschlag einmal neu | – | Fehler geloggt, Ergebnis `nil`; Kalender merkt Fehler nur 5 min | RAM (IDs, Texte, Staffeln); Kalender 6 h | `App/AppModel.swift:424-454`; `App/AppModel+Upcoming.swift:8-10`, `:52` |
| MDBList | keiner eigener | keiner | HTTP 429 oder „limit“ im Fehlertext → 1 h Pause | Fehler/Pause → alter Wert | Platte 24 h, „nicht gefunden“ 6 h, 4000 Einträge | `App/RatingsStore.swift:20-21`, `:32-46`, `:56-59`; `Core/Services/Ratings.swift:48`, `:72` |
| Trakt | keiner eigener | 429: genau einmal nach `Retry-After` (0–10 s, Standard 1 s); 401: einmal Token erneuern; Scrobble `stop`: einmal nach 1,5 s; Warteschlange: `retry` bleibt bis zum nächsten Durchlauf | siehe links | Scrobble-Fehler nur geloggt; Abholen-Fehler → `lastError`; Warteschlange: 0/401/408/429/5xx → später, andere 4xx → verworfen | Warteschlange auf Platte, 30 Tage | `Core/Sync/APIRequest.swift:42-47`, `:80-100`; `Core/Sync/TraktClient.swift:72-78`; `Core/Sync/SyncQueue.swift:63-64`, `:193-198`; `App/AppModel.swift:193`, `:214`; `App/AppModel+SyncQueue.swift:146-162` |
| Simkl | keiner eigener | wie Trakt ohne 401-Erneuerung; Merklisten-Entfernen wird nicht gesendet (bleibt lokal gemerkt) | wie Trakt | wie Trakt | wie Trakt | `Core/Sync/SimklClient.swift:24-28`, `:51`; `Core/Sync/SyncWrites.swift:92-112` |
| TorBox | keiner eigener | 429 einmal nach `Retry-After` | siehe links | Fehlertext über `userMessage` | optional `bypass_cache` | `Core/Services/TorBox.swift:56`, `:74`, `:90` |
| TVmaze | keiner eigener | 429 einmal | Bremse 20 Abrufe / 10 s | Fehler → 5 min leer gemerkt | Platte: 6 h, „fehlt“ 7 Tage | `Core/Services/TVmaze.swift:46-47`, `:77-103`, `:139-146` |
| IntroDB | 4 s Gesamtfrist | keiner | – | Fehler werden nicht gemerkt; 404 = kein Treffer | Platte, 400 Einträge (nur Treffer) | `Core/Services/IntroDB.swift:25`, `:102-104`; `App/Views/Player/SkipSegmentButton.swift:67` |
| Trailerio | 2,5 s Gesamtfrist | keiner | – | Fehler → `nil` | keiner | `Core/Services/Trailerio.swift:62`, `:130-131` |
| YouTube | 6 s je Anfrage | keiner im Transport | – | `nil` | keiner | `Core/Services/YouTubeResolver.swift:14`, `:78` |
| GitHub (Update) | keiner eigener | keiner | – | Status ≠ 200 → Fehlertext in der Update-Seite | keiner | `Core/Update/AppUpdate.swift:667-674`; `App/AppUpdater.swift:61-65` |
| atvloadly | 10 s je Anfrage, Probe 4 s | Abfrage alle 3 s; 10 Fehlabfragen in Folge → „antwortet nicht mehr“; 60 s Gnadenfrist, 20 min Gesamtfrist | – | Fehlertext, App läuft weiter | keiner (`reloadIgnoringLocalCacheData` bei der Probe) | `Core/Update/AppUpdate.swift:444-447`, `:471-476`, `:655`; `App/AppUpdater.swift:115`, `:184-185` |
| Fern-Log | – | erneuter Versuch im 5-s-Takt; Puffer bleibt bis zur Bestätigung | – | ohne Empfänger nur RAM-Puffer (500 Zeilen, älteste fallen weg) | – | `App/RemoteLog.swift:30`, `:46`, `:67-69`, `:76-79` |
| Bilder | 15 s Leerlauf | Fehler „kurz gemerkt“ (`failed`) | 6 Verbindungen je Host, 3 Dekodierungen gleichzeitig | Kachel versucht ihr nächstes Bild (`TilePosterImage`) | URLCache 400 MB + RAM nach Budget | `App/ImagePipeline.swift:30-33`, `:51-55` |
| Icon-Satz | 15 s (plus Gesamtfrist) | Sperre nach Fehler und genau ein neuer Versuch (`FetchRetryGate`, 5 min; `App/RatingIconStore.swift:18`) | – | alter Stand | Platte 24 h | `Core/Services/RatingIconSet.swift:12`, `:73`; `Core/Services/FetchRetryGate.swift:9`; `App/RatingIconStore.swift:50` |
| Fusion-Kit | keiner eigener | keiner | – | Fehler → alter Stand aus dem Caches-Ordner | Dateien | `App/FusionKitStore.swift:300-309` |
| Collection-Links | 20 s / 10 s | keiner | – | Fehlertext | gespeicherte Importe | `App/CollectionLinkStore.swift:71`, `:184`, `:200-201` |
| Medienquelle (Wiedergabe) | Lade-Wächter: Start 30 s (hart 120 s), Stocken 25 s, Sprung 25 s | Fehlerleiter: gleiche Quelle neu laden, Link neu auflösen, dann nächste Quelle (höchstens 3 automatische Wechsel) | Klasse „Ratenlimit“ in der Fehlerleiter | ohne Netz wartet die Leiter (`NWPathMonitor`); fehlgeschlagene Quelle 8 h gemerkt | optional Plattencache | `Core/Playback/LoadWatchdog.swift:16-23`; `Core/Playback/PlaybackRecovery.swift`; `App/Views/PlayerScreen.swift:675-812`; `App/Views/DetailViews.swift:1083`; `App/Playback/PlaybackStability.swift:7-9`; `Core/Playback/FailedLinks.swift:30` |
| Plattencache-Proxy | Leerlauf- und Gesamtgrenze je Block | „fail open“: 307 auf den Ursprung, nach wiederholten Fehlern leitet die ganze Sitzung um | Drossel-Erkennung (`throttled`) | direkte Adresse | Blöcke auf Platte | `App/Playback/DiskCacheProxy.swift:12-14`, `:25-39`, `:85`, `:104` |

## Am Gerät prüfen (nicht aus dem Code klärbar)

- Ob Application Support auf dem Zielgerät beschreibbar ist (`isWritable`-Probe, `App/DefaultsStorage.swift:18`) und wo die Blöcke damit tatsächlich liegen (Logzeile „speicher“).
- Ob UserDefaults-Inhalte ein Update über atvloadly überstehen (hängt an Bundle-ID und Signatur-Weg).
- Wann tvOS den Caches-Ordner leert und wie sich das auf Katalog-Plattenstand, Bewertungen und Bildcache auswirkt.
- Tatsächliche Zeitgrenzen der Abrufe ohne eigenen Timeout (`URLSession.shared`).

---

## Anhang: Persistenz-Ist nach Gegenprüfung

Diese Fassung der Persistenz-Tabelle wurde in der Gegenprüfung der Stufe 2 Zeile für Zeile am Code geprüft und ergänzt.

**Ablage-Mechanik** (`App/Sources/DefaultsStorage.swift:12-35`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:66-93`): Jeder Block geht als unkomprimierte Datei nach `Application Support/Player` (nur wenn die Schreibprobe beim Start gelang) und immer nach `Caches/Player`; zusätzlich LZFSE-komprimiert unter dem UserDefaults-Schlüssel `blob.<Name>`, wenn er in die Grenze passt. Gelesen wird UserDefaults zuerst, sonst die jüngste Datei. „Datei(en)“ in der Tabelle meint diese ein bis zwei Ordner.

Pfade ohne Präfix liegen unter `Packages/PlayerCore/Sources/PlayerCore/`.

| Speicherort | Inhalt | Format | Grenze | Schreiber / Leser | Lebensdauer |
|---|---|---|---|---|---|
| `profiles.json` – UserDefaults `blob.profiles.json` + Datei(en) | Alle Profile: Einstellungen, Addons mit Manifest, Collections, Startseite, API-Schlüssel (`apiKeys`), OAuth-Tokens (`syncTokens`), Geräteadresse für das App-Update | JSON, `schemaVersion` 1, Datum als Zahl; UserDefaults LZFSE, Dateien Klartext | 512 KB komprimiert (eigener Vorbehalt); darüber nur Datei mit Fehler-Log | `Store/ProfileStore.swift:41-43` / `:34-39`; Aufrufer `App/Sources/AppModel.swift:240`, `:58` | dauerhaft, solange in UserDefaults oder Application Support |
| `profiles.json.bak` – nur Datei(en) | Rohdaten einer nicht lesbaren `profiles.json` (gleiche Schlüssel und Tokens) | Rohdaten | keine; nie in UserDefaults (`Store/TieredBlobStorage.swift:68`) | `Store/ProfileStore.swift:37` / kein Leser im App-Code | bis zum nächsten Lesefehler; unter Caches vom System löschbar |
| `device-settings.json` – UserDefaults + Datei(en) | Bild & Ton je Gerät | JSON | 8 KB (eigener Vorbehalt) | `Models/DeviceSettings.swift:97-99` / `:82-95`; Aufrufer `App/Sources/AppModel.swift:46`, `:247` | dauerhaft |
| `deviceSettingsMigrated.v1` – UserDefaults direkt | Einmal-Flag des Umzugs aus den Profilen | Bool | – | `App/Sources/AppModel.swift:45` / `:44` | dauerhaft |
| `progress-<Profil-ID>.json` – UserDefaults + Datei(en) | Fortschritt, Verlauf, zuletzt gespielte Quelle je Titel | JSON, `schemaVersion` 1 (ungeprüft), Datum ISO 8601 ohne Sekundenbruchteile | 96 KB je Block, 128 KB gemeinsam mit allen übrigen Blöcken; Einträge unbegrenzt | `Progress/WatchProgress.swift:141-144` / `:135-139`; Aufrufer `App/Sources/AppModel.swift:78`, `:85`, `:91`, `:192` / `:60`, `:266`, `:592` | dauerhaft, solange im Budget; sonst nur Datei. Wird nie gelöscht (S-9) |
| `syncqueue-<Profil-ID>.json` – wie oben | Wartende Kachel-Änderungen | JSON, `schemaVersion` 1 (ungeprüft), Datum als Zahl; alte ISO-Dateien lesbar | wie oben; Einträge verfallen nach 30 Tagen | `Sync/SyncQueue.swift:223-225` / `:208-219`; Aufrufer `App/Sources/AppModel+SyncQueue.swift:38-42` / `:26-36` | bis Profil gelöscht (`:178-183`) |
| `trackmemory-<Profil-ID>.json`, `fileprogress-<Profil-ID>.json` – wie oben | Spur-Wahl je Titel; Fortschritt von TorBox-Dateien | JSON | wie oben | `App/Sources/Playback/PlayerMemory.swift:83-88` / `:75-81` | dauerhaft; Spur-Gedächtnis über die Einstellung löschbar (`:33-37`), sonst nie |
| `failed_links.json` – wie oben | Zuletzt fehlgeschlagene Quellen | JSON | wie oben; 60 Titel | `Playback/FailedLinks.swift:132-134` / Laden in `App/Sources/Playback/PlaybackStability.swift:27-30` | Verfall nach Frist beim Schreiben |
| `introdb-cache.json` – wie oben | Sprungmarken (IntroDB) | JSON | wie oben; 400 Einträge, 60 Tage | `Playback/SkipSegmentStore.swift:98-100` | Verfall nach Frist |
| `linkpack-<Profil-ID>-<Link-ID>.json` – wie oben | Preview-Pack eines Imports | JSON | wie oben | `App/Sources/CollectionLinkStore.swift:365`, `:138-142` / `:127` | bis der Link entfernt wird (`:150`) |
| `import-media-<Profil-ID>-<Link-ID>.json`, `import-paste-<Schlüssel>.json` – nur Datei(en) | Medienadressen des letzten Imports; eingefügte Widget-Exporte | JSON | keine; Präfix `import-` nie in UserDefaults | `App/Sources/CollectionLinkStore.swift:89`, `:366`; `App/Sources/FusionKitStore.swift:175` | bis Link/Kit entfernt; unter Caches löschbar |
| `collectionlinkmeta.<Profil-ID>` (alt: `collectionlinks.<Profil-ID>`) – UserDefaults direkt | Liste der Import-Links (Adresse, Format, Ergebniszeile, Datum) | JSON | keine, außerhalb des Budgets | `App/Sources/CollectionLinkStore.swift:133-136` / `:99-127` | dauerhaft; bleibt nach Profil-Löschung |
| `fusionkit.<Profil-ID>` – UserDefaults direkt | Kit-Auswahl je Profil | JSON | keine, außerhalb des Budgets | `App/Sources/FusionKitStore.swift:210-213` / `:221-222` | dauerhaft; bleibt nach Profil-Löschung |
| `catalog-<Profil-ID>.json` – `Caches/Player/Kataloge` | Katalog-Stand der Startseite (auch Merkliste) | JSON mit `version`, Datum in Sekunden | 4 MB, 60 Reihen, 100 Einträge je Reihe | `Store/CatalogSnapshot.swift:45-57`; Ordner `App/Sources/AppModel+CatalogDisk.swift:21-25` | Cache; unlesbar oder alte Version → gelöscht (`:42`) |
| Kit-Inhalte – `Caches/fusionkit` (alt: `Application Support/fusionkit-paste`) | Geladene Kit-Dateien und Verzeichnislisten | JSON | – | `App/Sources/FusionKitStore.swift:34-38`, `:348-349` | Cache |
| `ratings.json`, `rating-icons.json`, `tvmaze.json` – `Caches` | Bewertungen, Icon-Satz, Sendezeiten | JSON | – | `App/Sources/RatingsStore.swift:14`; `App/Sources/RatingIconStore.swift:12`; `App/Sources/AppModel+Airtimes.swift:14-15` | Cache |
| `images/`, `DiskCache/`, `FocusVideos/`, `AddonSubtitles/` – `Caches` | Bild-Cache; Plattencache des laufenden Films; Fokus-Videos; Addon-Untertitel | Binär-/Textdateien | Plattencache: Einstellung 4–32 GB | `App/Sources/ImagePipeline.swift:47`; `App/Sources/Playback/DiskCacheProxy.swift:455`; `App/Sources/Views/FocusVideo.swift:35-36`; `App/Sources/Views/Player/PlayerPictureSound.swift:162-165` | Cache; Untertitel älter als 24 h werden entfernt |
| `diag.hitchLog`, `debug.xrayProbe`, `xray.profile5Sources` – UserDefaults direkt | Diagnose-Schalter; Liste erkannter Quellen | Bool / JSON | klein | `App/Sources/MainThreadWatchdog.swift:11`; `Playback/XRayProbe.swift:8`; `App/Sources/Playback/XRayProfile5.swift:18-28` | dauerhaft |

Korrekturen gegenüber der Tabelle des Erstberichts: Spalten Grenze und Lebensdauer ergänzt; `FocusVideos/` und `AddonSubtitles/` fehlten; `fusionkit.<id>` wird in `:210-213` geschrieben und in `:221-222` gelesen; die Geräteadresse für das App-Update liegt ebenfalls in `apiKeys` (`App/Sources/Views/Settings/UpdatePage.swift:87`). Die Namen `xray-index.json`, `xray-t-…`, `xray-p-…` sind in `XRay/XRayCache.swift:132-136` definiert; einen Schreiber in der App hat die Suche nicht gefunden.

**Migrationen.** `StoredProfiles.schemaVersion` steht fest auf 1 und wird nur auf „größer als bekannt“ geprüft (`Store/ProfileStore.swift:55`); Migrationsschritte je Version gibt es nicht. Formatänderungen laufen feldweise: `Profile.init(from:)` füllt fehlende Felder mit Standardwerten (`Models/Profile.swift:81-112`), ältere Felder über `try c.decodeIfPresent` (wirft bei unbekanntem Wert), neuere über `try?` (fällt auf den Standard zurück). Das alte Feld `subtitlesEnabled` wird einmalig auf `subtitleMode` abgebildet (`:88-94`); die entfernten Felder `audioShaping` und `displayMode` werden beim Lesen ignoriert und einmalig in `device-settings.json` übernommen, abgesichert durch das Flag `deviceSettingsMigrated.v1` (`Models/DeviceSettings.swift:82-95`). `ProgressBook.schemaVersion` und `SyncQueue.schemaVersion` werden geschrieben, aber nie geprüft; die Warteschlange liest zusätzlich das ältere ISO-Datumsformat und schlüsselt alte Einträge um (`Sync/SyncQueue.swift:210-217`). Der Katalog-Stand verwirft Dateien anderer Version, statt sie zu migrieren. Beim Start verschiebt `TieredBlobStorage.migrate()` zu große oder überzählige UserDefaults-Blöcke in Dateien (`Store/TieredBlobStorage.swift:146-168`), und `CollectionLinkStore` zieht einen alten UserDefaults-Schlüssel in Blöcke um (`App/Sources/CollectionLinkStore.swift:99-121`).

**Schlüssel und Tokens.** Es gibt keinen Schlüsselbund-Zugriff im App- oder Paketcode. API-Schlüssel (TMDB, MDBList, TorBox, Trakt Client-ID und -Secret, Simkl Client-ID) und OAuth-Tokens (Zugangs- und Erneuerungstoken mit Ablaufzeit) liegen ausschließlich in `profiles.json`: komprimiert in UserDefaults und im Klartext als Datei unter `Caches/Player` sowie `Application Support/Player`, falls beschreibbar. Dieselben Daten stehen in `profiles.json.bak` und in der Sicherung, die die Handy-Seite ausliefert (`App/Sources/AppModel.swift:556`). Die Entscheidung ist im Code als bewusst kommentiert (`Models/Profile.swift:24`); das Login-Log lässt Tokens aus (`App/Sources/AppModel.swift:143-144`).
