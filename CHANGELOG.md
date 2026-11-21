# Versionsverlauf

Alle nennenswerten Änderungen an Player stehen in dieser Datei. Das Format folgt
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

Die Abschnitte sind nach Stufen geordnet. „Build“ ist die CI-Laufnummer, die die App als Build-Nummer anzeigt.
Ein Abschnitt mit dem Vermerk **integ** liegt auf dem Testzweig `integ` und kommt erst nach dem Gerätetest
auf `main`.

## [Unveröffentlicht]

In Arbeit, noch nicht auf `integ`.

### Hinzugefügt
- Welle E, aus Rückmeldungen nach dem Gerätetest:
  - Poster: neue Einstellung „Qualität auf Postern“ (Aus / Oben rechts / Unten), standardmäßig aus. Die Zeile
    mit Genre und Bewertung bleibt immer lesbar.
  - Detailseite: wählbar, welche Bewertungen erscheinen (Standard: IMDb, Rotten Tomatoes, Trakt). Höchstens
    5 Qualitäts-Plaketten in einer Zeile, in dieser Reihenfolge: Auflösung, Dolby Vision/HDR, Atmos,
    Tonformat mit Kanälen, Remux. Die Altersfreigabe bleibt in der Textzeile.
  - Bilder und Bewertungen vom Metadaten-Addon (Poster, Hintergrund, Logo) gehen vor TMDB, abschaltbar.
  - Quellenliste: die Reihenfolge des Addons gilt als Standard, „Smart (App)“ ist wählbar. Die Texte des Addons
    werden unverändert gezeigt (bis 4 Zeilen), die App-Plaketten nur kompakt, und doppelte Quellen werden
    ausgeblendet.

### Behoben
- Einstellungen: eine Korrektur ist in Arbeit.

## [Welle D] – 2026-11-21 (integ, Build 121)

Bild und Ton im Player.

### Hinzugefügt
- Spur-Gedächtnis je Serie bzw. Titel: Tonsprache, Untertitel und Untertitel-Versatz werden beim nächsten
  Mal übernommen.
- Untertitel-Versatz einstellbar, auch negativ.
- Zeichensatz-Erkennung für Untertitel (etwa Windows-1252) und Reparatur kaputter Umlaute.
- Der Bildschirmschoner bleibt während der Wiedergabe aus.
- Fortschrittsanzeige für TorBox-Downloads.

### Behoben
- Ein Profilwechsel während der Quellensuche mischt keine Ergebnisse mehr zwischen den Profilen.
- Eine nur teilweise geladene Quellenliste füllt sich nach.
- Der Icon-Satz für Bewertungen flackert beim Neustart nicht mehr.
- Sendezeiten werden genauer abgeglichen und kompakter zwischengespeichert.

## [Welle C] – 2026-11-21 (integ, Build 116)

Stabilität, Tempo, Player-Komfort sowie Quellen und Extras.

### Hinzugefügt
- Spulen über die Touchfläche mit Vorschaubild, Intro-Marken auf der Zeitleiste.
- Einstellungen für Ton (Tonausgang) und Bildmodus (Dolby-Vision-Anzeigemodus); geordneter Ausstieg aus dem
  Player.
- TorBox: gecachte Quellen werden erkannt und bevorzugt, und „Meine TorBox-Dateien“ steht in der Bibliothek.
- Quellen: AIOStreams-Felder werden ausgewertet. Die Reihenfolge berücksichtigt Sprache, AV1-Fähigkeit und
  TorBox. Untertitel-Felder (forced, SDH, label) werden gelesen.
- Trakt-Empfehlungen als Startseiten-Reihe; Fusion-Optionen `limit` und `hideTitle`.
- Spoilerschutz für Folgenbilder.
- Kalender mit Sendetag und Sendezeit über TVmaze.
- „Über“: Geräte-Check (Inhalt anpassen, HDR des Fernsehers, Tonausgang, AV1-Hardware) und die Tabelle
  „Was spielt wie“.
- Handy-Seite: ein gemeinsames Schnell-Import-Feld, das erkennt, was eingefügt wurde.
- Eigener Icon-Satz für die Bewertungen, per URL.

### Geändert
- Die Startseite erscheint sofort aus dem Plattencache. Quellen kommen aus einem Cache, der im Hintergrund
  erneuert wird.
- Bilder werden in der Größe geladen, in der sie angezeigt werden. Jede Reihe merkt sich den Fokus.

### Behoben
- Die Addon-Suche hat Zeitgrenzen, sodass ein langsames Addon nicht mehr alles aufhält.
- Ein Lade-Wächter erkennt hängende Starts. Gescheiterte Links werden 8 Stunden gemieden.
- Die App wartet auf das Netz, statt abzubrechen, und reagiert auf Wechsel der Ton-Route.
- Ein Hänger-Wächter für die Oberfläche wurde ergänzt.

## [Dolby Vision FEL] – 2026-11-21 (integ, Build 108)

### Hinzugefügt
- Dolby Vision Profil 7 FEL: Die Erweiterungsschicht wird in die Profil-8.1-Wiedergabe eingerechnet, statt
  verloren zu gehen. Dafür schaltet das neue Paket `Packages/AetherFEL` den Engine-Trait
  `DolbyVisionFelCurves` ein.
- Die CI weist nach, dass der Trait im Build aktiv ist und dass alle Engine-Frameworks in der App stecken.

## [Welle B] – 2026-11-21 (integ, Builds 92–100)

### Hinzugefügt
- Pause, wenn der Fernseher ausgeht oder die App in den Hintergrund wechselt. Danach wird die Wiedergabe sauber
  neu aufgebaut.
- Eine Fehlerleiter je nach Fehlerart: neu laden, neu auflösen, andere Quelle.
- Sichtbare Lade-Schritte beim Start eines Films.
- „Intro überspringen“ über IntroDB und Kapitelmarken.
- Die nächste Folge kommt aus demselben Release (Gruppe, Sprache, Qualität), dazu die Abfrage „Noch da?“ nach
  mehreren Folgen ohne Eingabe.
- Plattencache für den laufenden Film über einen lokalen Proxy (standardmäßig aus).
- Lizenzhinweise: `THIRD_PARTY_NOTICES.md`, „Danksagungen / Lizenzen“ unter „Über“, MIT-Lizenz für den
  eigenen Quelltext.

### Geändert
- Die Wiedergabe-Engine ist auf eine feste Version festgelegt.
- Fehlertexte zeigen keine Links mehr.

### Behoben
- Nach dem automatischen Weiterschalten zur nächsten Folge stimmt die Quellenliste.

## [Welle A] – 2026-11-21 (integ, Builds 32–80)

Neuer Player, Startseiten-Umbau und erste Ausbaustufe.

### Hinzugefügt
- Startseite: Hero-Diashow, Info folgt dem Fokus, Poster klappen nach kurzer Ruhe auf, Kartengröße für alle
  Reihen.
- Bibliothek, Kalender und die Reihe „Heute neu“.
- Quellen werden im Hintergrund vorgeladen, sobald der Fokus kurz auf einer Kachel ruht.
- Player: lesbare Namen für Spuren und Formate, Info-Plaketten statt Engine-Rohtext, Panel mit den Reitern
  Info · Ton · Untertitel.
- Untertitel: eigenes Overlay, automatische Auswahl, Untertitel aus Addons (Stremio-Ressource `subtitles`,
  auch per Datei-Hash).
- Qualitäts-Plaketten neu gestaltet: neutral, einstellbar, mit gezeichneten Schriftzügen, auch auf Postern.
- Trailer zuerst über Trailerio, YouTube als Rückfall; die Profilsprache wird bevorzugt.
- Fusion- bzw. betterer-Startseiten-Kits als Startseiten-Reihen.
- „App aktualisieren“ in den Einstellungen; die Build-Nummer kommt aus der CI.

### Geändert
- Protokolle enthalten keine Schlüssel und Token mehr.
- Der Bildspeicher richtet sich nach dem freien Arbeitsspeicher.

### Behoben
- Speicher-Absturzschutz: Große Datenblöcke werden als Datei abgelegt, Profile liegen nie nur im Cache, und der
  Katalog-Cache läuft nach 24 Stunden ab.
- Navigation: Der Startfokus liegt auf „Abspielen“, die Knöpfe der Startseite sind nicht mehr blau, und „Zurück“
  im Kalender führt in die Seitenleiste.

## [0.4.0] – 2026-11-21 (main, Builds 12–39)

### Hinzugefügt
- Platzhalter-Streams werden erkannt, und die App wechselt dann automatisch die Quelle. Bei Fehlern lädt sie neu.
- Ladeoptionen (Sprachen, Proxy-Kopfzeilen); Dolby-Digital- und DD+-Tonspuren werden bevorzugt.
- Infozeile auf der Detailseite: Bewertungen über MDBList (IMDb, Rotten Tomatoes, Metacritic, Letterboxd,
  Trakt, TMDB und weitere), Altersfreigabe, Technik-Plaketten (4K, Dolby Vision, HDR, Atmos, 7.1/5.1).
- Stream-Plaketten: REMUX/BluRay/WEB-DL, HEVC/AV1/H.264 mit 10 Bit, DTS:X, HLG, Kanäle.
- Kachelzustand: Fortschrittsbalken, Restzeit, Folge (etwa S1 F3), Haken für „gesehen“.
- Deutsche Texte und Bilder aus TMDB: Titel, Beschreibung, Poster, Logo, Genres, Freigabe und Folgennamen.
- Up-next: Die Quellen der nächsten Folge werden vorgeladen, kurz vor Ende läuft ein Countdown. Noch nicht
  ausgestrahlte Folgen werden übersprungen.
- Detailseite: Trailer im eigenen Player, Besetzung mit Personenseite, ähnliche Titel, Angaben unter „Über“
  (Regie, Studio, Originaltitel, Budget).
- Neues Design: Seitenleiste und obere Leiste mit Uhr, Einstellungen in Kategorien, Aussehen-Einstellungen
  je Profil, wählbare Hero-Quelle.

### Geändert
- „Weiterschauen“ startet die zuletzt gespielte Quelle direkt.
- Beim Quellenwechsel kommen gecachte Quellen zuerst.
- Eigener Bildlader mit 400 MB Plattencache statt der Systemkomponente.
- Trakt/Simkl: Die Anmeldung wird rechtzeitig erneuert, Wiederholung bei 401/429, Scrobble-Regeln
  (80 %, Pause, 409).
- Auf der Detailseite laden die Quellen sofort und parallel. Die Technik-Plaketten erscheinen sofort aus dem
  Cache, ohne dass die Zeile springt.

### Behoben
- Viele einzelne Sprünge hintereinander verbrauchen die Neustarts der Engine nicht mehr; sie werden gesammelt.
- Play/Pause folgt dem echten Zustand des Players.
- Der Fokus bleibt bei der Rückkehr zur Detailseite erhalten.

## [0.3.0] – 2026-11-21 (Builds 8–11)

### Hinzugefügt
- Fern-Log: Die App schickt Ereignisse per Bonjour an `tools/logcollector.py` im lokalen Netz.

### Geändert
- Ein Klick auf das Touchpad pausiert die Wiedergabe. Das Log zeigt Fehlerdetails und Sprünge.

## [0.2.0] – 2026-11-21 (Builds 4–7)

### Hinzugefügt
- Nächste Folge automatisch (gleiche `bingeGroup`), mit einem Schalter für Autoplay. „Weiterschauen“ zeigt die
  nächste Folge.
- Trakt und Simkl: Geräte-Login, Scrobbling, Abgleich von „Weiterschauen“, Merkliste, Trakt-Listen als Reihen.
  Die Fortschritt-Quelle ist wählbar.

### Behoben
- Speichern unter tvOS: Profile liegen jetzt in den UserDefaults (komprimiert), weil tvOS den Ordner
  „Application Support“ nicht beschreiben lässt.
- Profile laden auch, wenn Felder fehlen.

## [0.1.0] – 2026-11-21 (Builds 1–3)

### Hinzugefügt
- Probelauf in einem eigenen Spike: AetherEngine auf dem Apple TV mit Dolby Vision und 5.1-Ton geprüft.
- `PlayerCore`: Stremio-Addon-Client, Modelle, Profile, Import von Collections, Stream-Merkmale, TMDB.
- App-Gerüst: Startseite mit Bearbeiten-Modus (lange drücken, dann Reihen verschieben, Stil wechseln, von der
  Startseite nehmen), Detailseite, Quellenliste, Player hinter einer eigenen Wiedergabe-Schnittstelle,
  Einstellungen, CI mit unsignierter IPA.
- Fertige Pakete (Streaming-Dienste, Genres), TMDB-Links als Reihe, Suche, „Weiterschauen“ mit Fortsetzen.
- Handy-Eingabeseite: QR-Code, lokaler Server, Sicherung der Profile.
