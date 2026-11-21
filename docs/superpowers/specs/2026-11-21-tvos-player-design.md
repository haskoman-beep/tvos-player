# tvOS-Player – Design (Stand 21.11.2026)

Status: von Claude über Nacht geschrieben, nachdem der Nutzer die Fragen-Phase beendet hat
("Alle Entscheidungen die du von mir brauchst verschiebe auf morgen"). **Noch nicht vom Nutzer
freigegeben.** Markierung: **[N]** = vom Nutzer entschieden, **[C]** = Claudes Entscheidung
(korrigierbar), **[OFFEN]** = braucht den Nutzer.

## 1. Absicht und Warum

Eine eigene Apple-TV-App, nur für den Nutzer, als Ersatz für Nuvio / Stremio / Odin / Fusion. [N]
Hauptschmerz heute: **Ordnen** von Addons und Collections auf der Startseite ist klobig (nicht
das Einrichten). [N] Die App soll sich anfühlen wie eine Apple-App (Richtung Odin/Fusion), die
Startseite soll aus vorher gewählten Collections selbst gestaltet werden, und sie soll alle
hochwertigen Formate sauber am LG OLED und an der Z906 ausgeben.

Erfolg heißt: Der Nutzer stellt seine Startseite in wenigen Klicks am TV um, startet einen
Remux mit Dolby Vision und hört 5.1 aus der Z906, und "Weiterschauen" stimmt mit Trakt überein.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Stremio-Addon-Protokoll; AIOStreams als Hauptquelle (TorBox, Torrents + Usenet). [N]
- Startseite aus Collections; Widget-Stil pro Reihe aus 6 Stilen (Hero, Poster, Querformat+Fortschritt,
  Top 10, Logo-Kacheln, Collection-Kacheln). [N]
- Bearbeiten am TV: lang drücken → angefasste Reihe direkt bewegen (▲▼ verschieben, ◀▶ Stil live,
  Play/Pause = von der Startseite nehmen, OK fertig, Zurück abbrechen); Plus-Kachel unter allen
  Reihen nur im Bearbeiten-Modus → Liste der Collections, die nicht auf der Startseite sind (inkl.
  abgelegter) mit Vorschau, unten "Neue Collection importieren"; neue Reihe erscheint über dem
  Plus, schon angefasst. Kein Menü pro Reihe. [N]
- Collections-Herkunft: Import (Trakt / MDBList / TMDB) + 2 fertige Pakete; kein eigener Editor. [N]
  Nuvio-Export `nuvio-collections-profile-1-tmdb.json` (16 Collections, 7 doppelt) importieren,
  Dubletten zusammenführen; Datenmodell Collection → Ordner → Quellen übernehmen. [C]
- Dienste: Trakt, Simkl, TMDB, TVDB, MDBList. [N] Rollen [C]: Trakt = Fortschritt/Weiterschauen,
  Simkl gespiegelt; TMDB = Metadaten de-DE (Fallback en-US) inkl. Logos/Hintergründe; TVDB =
  Episodenreihenfolge; MDBList = Bewertungen + Listen.
- Einstellung "Fortschritt & Gesehen": Hauptquelle lokal / Trakt / Simkl, zusätzlich melden an
  die anderen; lokal wird immer mitgeschrieben. [N Wunsch, C Ausgestaltung]
- Profile, jedes komplett eigenständig (alle Einstellungen, Startseite, Addons, Konten,
  Fortschritt-Quelle). [N]
- Sprache: App Deutsch/Englisch umschaltbar pro Profil [N]; Tonspur-Vorrang Deutsch → Englisch →
  Original [C, nicht widersprochen]; Untertitel standardmäßig aus, Option vorhanden. [N]
- Bild/Ton: Dolby Vision (P5, P8, P7→8.1) am LG; TrueHD/DTS-HD im Gerät dekodieren, Ausgabe
  Mehrkanal-PCM → TV → optisch Dolby Digital 5.1 an die Z906 (Surround funktioniert heute). [N Setup]
- Autoplay nächste Folge mit gleicher Quelle (Stremio `bingeGroup`), Ton-/Untertitelwahl
  weitertragen. [C, Muster NuvioTVOS]

**Nicht-Ziele (jetzt)**
- iPad-App, zweites Apple TV außer Haus, iCloud/CloudKit-Sync, Entwicklerkonto. [N "Erst nur
  zu Hause"] Das Datenmodell muss das später ohne Umbau erlauben. [N]
- Eigener Collection-Editor ("friemelig"). [N]
- Direkte TorBox-Anbindung in der App (Login, Cache-Check) – alles über AIOStreams. [C]
- Atmos-Höhenkanäle / Bitstream-Passthrough – die Z906 kann es nicht. [C aus N-Setup]
- Live-TV, DVR, Musik.

**Anti-Ziele (wäre ein Fehlschlag, selbst wenn es technisch läuft)**
- Ordnen bleibt klobig (Menüs, viele Klicks pro Schritt).
- Wiedergabe ruckelt / falsches Bild (kein DV-Logo) / nur Stereo an der Z906.
- Einstellungen gehen bei einer Neuinstallation (7-Tage-Signierung) verloren.
- Lange URLs / API-Keys mit der Fernbedienung tippen müssen.

## 3. Rahmenbedingungen

- Kein Mac, kein Entwicklerkonto. Apple TV 4K, tvOS 26.6 (Heimnetz). [N]
- Signieren + Installieren: atvloadly auf dem Pi (Heimnetz), Apple-ID-Signierung,
  7-Tage-Refresh automatisch. [N] Freie Apple-ID: begrenzte Zahl gleichzeitiger Apps (VortX belegt
  schon einen Platz).
- Build: GitHub Actions macOS (privates Repo `haskoman-beep/…`). macOS-Minuten zählen in privaten
  Repos 10-fach (≈ 200 Mac-Minuten/Monat gratis) → Builds bündeln; plattformunabhängigen Kern
  lokal unter Linux (Swift-Container) testen. [C]
- AetherEngine verlangt laut eigener Doku Xcode 27 / Swift 6.4; Kompatibilität mit Xcode 26.3 ist
  "best effort". GitHub-Standard-Runner haben (Stand Spike) nur Xcode 26.x. → Risiko, siehe §9.
- Lizenz AetherEngine: LGPL-3 mit App-Store-Ausnahme – für privaten Gebrauch unproblematisch.

## 4. Ansätze (Player-Engine)

| | Weg | Bewertung |
|---|---|---|
| A | **AetherEngine allein** | DV P5/P8, P7→8.1, TrueHD/DTS-HD dekodiert, MKV; Angaben selbstberichtet |
| B | AetherEngine + AVPlayer | wie A, doppelte Pflege |
| C | KSPlayer | DV-Funktionen kostenpflichtig, Werbeaussagen in Recherche widerlegt |
| – | AVPlayer allein | kein MKV/TrueHD/DTS-HD → raus |

**Gewählt: A mit vorgeschaltetem Probelauf** (Spike-App "Player-Probe"). [N] Engine liegt hinter
einer eigenen Schnittstelle `PlayerEngine`, damit B ohne App-Umbau möglich bleibt. [C]

## 5. Aufbau [C]

```
app/
  Packages/PlayerCore/        plattformunabhängig, unter Linux testbar (Foundation only)
    Models/                   Profile, Collection/Folder/Source, HomeLayout, MediaItem, Progress
    Addons/                   Stremio-Protokoll: Manifest, Catalog, Meta, Stream, Subtitles
    Services/                 TMDB, TVDB, MDBList, Trakt, Simkl (HTTP-Clients, Token-Modelle)
    Import/                   Nuvio-JSON, Trakt-Liste, MDBList-Liste, TMDB-Liste/Discover, Pakete
    Ranking/                  Stream-Sortierung (Sprache, Auflösung, DV/HDR, Größe, Cache)
    Sync/                     Fortschritt: lokal + Trakt/Simkl, Konflikte, Warteschlange offline
    Store/                    JSON-Dateien pro Profil, versioniert, atomar
  Packages/PlaybackKit/       tvOS: PlayerEngine-Protokoll + AetherEngine-Adapter
  App/                        SwiftUI tvOS-App (XcodeGen project.yml)
```

- **Persistenz:** Codable-JSON pro Profil in Application Support, Schema-Version im Dokument,
  atomares Schreiben. Begründung: unter Linux testbar, einfach auf den Pi zu sichern, später als
  Dokumente in CloudKit spiegelbar. Geheimnisse (Tokens, API-Keys) in der Keychain, im Export
  verschlüsselt/optional. [C] (SwiftData verworfen: nicht unter Linux testbar.)
- **Eingabe langer Texte:** Die App startet bei Bedarf einen kleinen Web-Server im Heimnetz und zeigt
  einen QR-Code; am Handy öffnet sich eine Seite zum Einfügen von Manifest-URLs, API-Keys und
  Import-Dateien (z. B. Nuvio-JSON). Trakt/Simkl über deren Geräte-Code-Login. [C]
- **Sicherung auf den Pi:** Phase nach dem Kern; kleiner Dienst neben AIOStreams (eigenes Teilprojekt
  "AIOStreams auf dem Pi"). Bis dahin: Export/Import per Handy-Seite. [C]
- **Design-Sprache:** native tvOS-Fokus-Engine, Parallaxe, Top-Shelf später; Stile aus den Mockups
  `mockups/widget-stile.html` und `mockups/prototyp.html`.

## 6. Bildschirme [C, Startseite/Bearbeiten N]

1. Profilauswahl (beim Start, wenn > 1 Profil).
2. Startseite: Reihen aus Collections im gewählten Stil; Weiterschauen-Reihe; Bearbeiten wie §2.
3. Collection-Ansicht: Ordner als Kacheln → Ordner zeigt Quellen als Reihen.
4. Detailseite: Hero mit Logo, Bewertungen (MDBList), Fortsetzen/Abspielen, Staffeln/Folgen
   (TVDB-Reihenfolge), Quellenliste (AIOStreams, sortiert nach Profilvorlieben).
5. Player: AetherEngine-Fläche, Transportleiste, Ton/Untertitel-Menü, nächste Folge.
6. Suche (TMDB + Addon-Kataloge).
7. Einstellungen pro Profil: Addons, Konten, Fortschritt-Quelle, Sprache, Ton/Untertitel,
   Collections importieren, Profil verwalten.

## 7. Phasen [C]

- **P0** Spike: AetherEngine am echten TV (DV + 5.1). Läuft.
- **P1** Kern: PlayerCore (Modelle, Store, Stremio-Client, TMDB, Nuvio-Import, Ranking) mit Linux-Tests;
  App-Gerüst: Startseite (alle 6 Stile), Detail, Quellenliste, Player über PlaybackKit.
- **P2** Bearbeiten-Modus + Plus-Auswahl + fertige Pakete + Trakt/MDBList/TMDB-Import.
- **P3** Profile + Einstellungen + Handy-Eingabeseite (QR).
- **P4** Sync: Trakt/Simkl (Geräte-Login, Scrobble, Weiterschauen), Fortschritt-Quelle.
- **P5** TVDB-Folgen, MDBList-Bewertungen, Autoplay/bingeGroup, Feinschliff, Pi-Sicherung.

## 7a. Antworten auf den Builder-Check [C]

- **Startseiten-Reihe:** Eine Reihe zeigt entweder eine *Liste* (eine Quelle: TMDB-Discover, Trakt-Liste,
  Addon-Katalog, Weiterschauen, Watchlist) in einem Titel-Stil (Hero, Poster, Querformat, Top 10)
  oder eine *Collection* als Ordner-Kacheln (Stil Collection- oder Logo-Kacheln). Hat ein Ordner
  mehrere Quellen, öffnet er eine Seite mit einer Reihe pro Quelle. Die Plus-Auswahl bietet beides an.
- **Neu-Signieren:** Die gleiche Bundle-ID und die gleiche Apple-ID ergeben den gleichen Container, also bleiben die Daten
  erhalten. Trotzdem gibt es schon in P1 einen JSON-Export und -Import aller Profile (Sicherheitsnetz).
  Tokens liegen in der Keychain und sind zusätzlich im Export enthalten (das Gerät ist privat).
- **Nuvio-Addon-Quellen** (54 von 2224, `app.xperience.*`, keine URL): Der Import überspringt sie und
  merkt sie sich. Sie werden aktiv, sobald ein Addon mit dieser Manifest-ID installiert ist.
- **Dubletten:** gleicher Titel → Ordner vereinigen (gleicher Ordnertitel → Quellen vereinigen,
  Quellen nach `id` entdoppelt).
- **Stream-Reihenfolge:** Die Reihenfolge von AIOStreams bleibt (dort ist sie schon eingestellt). Die App filtert nur
  nicht abspielbare Streams aus und zeigt geparste Merkmale (Auflösung, DV/HDR, Ton, Größe) als
  Plaketten. `Ranking` bleibt also klein.
- **Texteingabe in P1:** über die tvOS-Systemtastatur (das iPhone bietet die Eingabe als Mitteilung an). Die QR-Seite
  kommt in P3.
- **App-Plätze:** Eine freie Apple-ID erlaubt 3 Apps (VortX, Player-Probe, Haupt-App). Die Haupt-App bekommt
  eine eigene Bundle-ID `de.haskoman.player`, die Probe kann nach dem Test weg.

## 8. Dem Builder überlassen

Konkrete Typnamen, Ordnerstruktur innerhalb der Pakete, HTTP-Caching, Bildlader, genaue
Fokus-Animationen, Fehlermeldungstexte, Testaufteilung.

## 9. Risiken und offene Punkte

- Xcode 27 für AetherEngine vs. Xcode 26.x auf GitHub-Runnern → ggf. ältere AetherEngine-Version
  pinnen oder anderen Runner nutzen. (Spike klärt.)
- DV/5.1 auf echter Hardware unbestätigt (Spike klärt, Nutzer testet).
- **[OFFEN]** Repo öffentlich machen (unbegrenzte Mac-Minuten) oder privat bleiben (≈ 15–20 Builds/Monat)?
- **[OFFEN]** App-Name / Icon.
- **[OFFEN]** Welche 2 fertigen Pakete? Vorschlag [C]: "Streaming-Dienste DE" (Netflix, Prime, Disney+,
  Apple TV+, WOW … aus TMDB Watch-Providers) und "Genres & Stimmungen".
- **[OFFEN]** API-Keys: TMDB/MDBList/TVDB-Keys des Nutzers oder eigene? (TVDB verlangt eigenen Key.)
