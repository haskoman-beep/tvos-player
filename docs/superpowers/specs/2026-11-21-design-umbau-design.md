# Design-Umbau im Stil gängiger tvOS-Streaming-Apps – Design

Stand 21.11.2026. Kennzeichnung: **[N]** = Nutzerentscheidung, **[C]** = Entscheidung von Claude (korrigierbar).

## 1. Absicht und Warum

Der Player ersetzt Nuvio/Stremio auf dem Apple TV. Funktional ist vieles da (Quellen, DV, Ton, Bewertungen, TMDB-Anreicherung),
aber Oberfläche und Bedienung wirken noch wie ein Prototyp: drei Text-Tabs oben, statische Hero-Kachel, Einstellungen als eine
lange Liste. Ziel: Aussehen und Aufbau wie **NuvioTVOS** [N], damit sich der Umstieg nicht wie ein Rückschritt anfühlt.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele** (alle vier Teile [N]):
1. **Navigation:** Seitenleiste links (tvOS 18 `.sidebarAdaptable`) *oder* obere Leiste mit Uhr – umschaltbar unter
   Einstellungen → Aussehen [N]. Tabs: Start, Suche, Bibliothek, Kalender, Einstellungen [N], mit SF-Symbolen.
2. **Startseite:** Vollbild-Hero-Diashow oben (wechselt alle 10 s, Überblendung, Logo statt Titeltext wenn vorhanden,
   Metazeile Jahr · Laufzeit · FSK, Bewertungszeile MDBList, Beschreibung 2 Zeilen, Knöpfe „Abspielen“ / „Details“).
   Hintergrund folgt dem Fokus: fokussierte Kachel in einer Reihe setzt nach 350 ms Ruhe den Vollbild-Hintergrund.
   Fokussiertes Poster klappt nach 350 ms Ruhe zu Querformat mit Logo auf (wie NuvioTVOS `PosterCard`).
3. **Einstellungen:** Kategorien links mit Symbolen, Inhalt rechts (wie NuvioTVOS `SettingsCategory`):
   Profil, Addons, Dienste & Schlüssel, Startseite, Aussehen, Wiedergabe, Über. Bestehende Einträge werden nur einsortiert.
4. **Aussehen-Optionen** (neue Kategorie): Navigation Seitenleiste/oben, Akzentfarbe (6 feste Farben),
   Kartengröße (klein/mittel/groß), Hero an/aus, Hero-Quelle (welche Startseiten-Reihe), Poster aufklappen an/aus.
5. **Bibliothek-Tab** [N]: Weiterschauen, Merkliste, Verlauf (zuletzt gesehen). Quelle wie heute (Trakt/Simkl/lokal).
6. **Kalender-Tab** [N]: kommende Folgen der Serien aus Weiterschauen/Merkliste/Verlauf, gruppiert nach Tag
   (Heute, Morgen, Datum), Daten aus TMDB (`/tv/{id}` → `next_episode_to_air`, Staffel-Folgen). Dazu optionale
   „Heute neu“-Reihe für die Startseite.

**Nicht-Ziele:** Watch Party, IPTV, KI-Reihen, Überraschung, Ambient-Modus, eigene Schriften, 12 Farbthemen,
Stream-Listenstil-Editor, Trailer im Hero (bewusst gestrichen, Plan von heute).

**Anti-Ziele** (wäre trotz Funktion ein Fehlschlag):
- Fokus springt, geht verloren oder hängt (Nuvios größte Fehlerquelle – tausende Zeilen Fokus-Reparatur).
- Startseite ruckelt beim Scrollen, weil Hintergrund/Aufklappen bei jedem Fokuswechsel Bilder lädt.
- Bestehende Profile/Startseiten gehen beim Update verloren.

## 3. Rahmenbedingungen

- tvOS 18, SwiftUI, Build nur über GitHub Actions (kein Mac); jeder Test kostet einen Build + Installation (~15–20 min).
- Öffentliches Repo: keine Schlüssel, Namen, IPs.
- Neue Profilfelder mit Standardwerten in `init(from:)` (alte Sicherungen bleiben ladbar).
- Bildlader `ImagePipeline`/`RemoteImage` wird genutzt (Vorladen, Downsampling).
- Logik, die sich testen lässt (Kalender-Gruppierung, Hero-Auswahl, Einstellungs-Defaults), kommt in PlayerCore mit Tests.

## 4. Ansätze

| Ansatz | Kurz | Abwägung |
|---|---|---|
| **Hybrid** [N] | Navigation + Einstellungen mit Apple-Bausteinen, Hero-Diashow und aufklappende Poster selbst gebaut | stabiler System-Fokus, wenig Code; das Nuvio-Gefühl kommt aus Hero + Poster |
| Alles nativ | nur Apple-Bausteine, kein Aufklappen | schnell, sieht weniger nach Nuvio aus |
| Alles eigen | eigene Seitenleiste und Fokuslogik | am nächsten an Nuvio, aber genau die Fokusfehler, die wir vermeiden wollen |

## 5. Aufbau [C]

- `RootView`: `TabView(selection:)` mit `Tab(…, systemImage:)`; `.tabViewStyle(.sidebarAdaptable)` wenn
  `appearance.navigation == .sidebar`, sonst Standard-Leiste oben plus Uhr-Überlagerung rechts oben.
  Jeder Tab behält seinen eigenen `NavigationStack`-Pfad (wie heute).
- Neues Profilfeld `appearance: Appearance` (navigation, accent, cardSize, heroEnabled, heroRowID?, expandPosters).
- `HomeView`: oben `HeroCarousel` (eigene Komponente), darunter Reihen wie heute. Hintergrund über eine
  `@State focusedBackdrop`-URL mit Überblendung; Entprellung 350 ms über `Task.sleep`, abgebrochen bei Fokuswechsel.
- `PosterCard` bekommt `expanded`-Zustand (Fokus + 350 ms) → Breite wächst animiert auf Querformat, Bild wird erst
  nach der Ruhezeit geladen.
- `SettingsView` → `NavigationSplitView`-artig: Kategorienliste links, Inhalt rechts; Unterseiten pro Kategorie
  als eigene kleine Views (statt eine große Datei wie Nuvio).
- `LibraryView`, `CalendarView` neu; Kalenderlogik `UpcomingEpisodes` in PlayerCore (Gruppierung, Filter, Tests).

## 6. Bildschirme (Skizze)

```
Seitenleiste:                      Startseite:
┌──────┐ ┌─────────────────────────────────────────────┐
│ ⌂    │ │ [LOGO]                       Hintergrund     │
│ 🔍   │ │ 2010 · 1 h 42 · FSK 6 · IMDb 6.0 🍅 64 %     │
│ 📚   │ │ Fünf Freunde …                               │
│ 📅   │ │ [▶ Abspielen] [Details]          ● ○ ○ ○     │
│ ⚙    │ │ Weiterschauen ▸ [▭][▭][▭]                    │
└──────┘ │ Beliebt ▸ [▯][▭▭ aufgeklappt][▯][▯]           │
         └─────────────────────────────────────────────┘
Einstellungen:  [Profil | Addons | Dienste | Startseite | Aussehen | Wiedergabe | Über]  →  rechts Inhalt
```

## 7. Phasen [C] (je ein Build)

1. Navigation + Aussehen-Profilfeld + Einstellungs-Kategorien.
2. Hero-Diashow + Hintergrund folgt Fokus.
3. Poster aufklappen + Kartengröße/Akzentfarbe anwenden.
4. Bibliothek + Kalender (+ „Heute neu“-Reihe).

## 7a. Antworten auf den Builder-Check

1. **Hero und Reihen [N]:** Die Info-Ebene oben (Hintergrund, Logo, Metazeile, Bewertungen, Beschreibung) zeigt immer den
   fokussierten Titel, wie bei Nuvio. Solange der Fokus in den Reihen liegt, pausiert die Diashow und läuft weiter, sobald
   der Fokus wieder im Hero ist. Umsetzung: eine gemeinsame Hintergrund- und Info-Ebene hinter dem ScrollView. Der Hero ist
   kein eigener Scroll-Abschnitt.
2. **„Abspielen“ im Hero [N]:** verhält sich wie Weiterschauen.
   - Film: die gemerkte Quelle startet direkt (`resumeLastSource`), sonst öffnet die Quellenliste.
   - Serie: die nächste offene Folge laut Fortschritt, sonst S1F1.
   - Folgen werden erst beim Druck geladen, nicht pro Folie.
3. **Kalender [N]:** Serien aus Weiterschauen und Merkliste, höchstens 50. Zeitraum: „Gestern“ bis 14 Tage voraus.
   Gecacht 6 h, wie die anderen TMDB-Daten.
4. **Bestehender Stil `.hero` [C]:**
   - Die erste vorhandene `.hero`-Reihe wird beim ersten Start automatisch `heroRowID`.
   - Sie wird nicht doppelt als Reihe gezeigt. Der Stil bleibt lesbar, wird im Editor aber zu „Als Hero verwenden“.
   - Ist `heroRowID` leer: die erste Katalog-Reihe; ohne Katalog-Reihe gibt es keinen Hero.
5. **Verlauf [C]:** Quelle ist der lokale `ProgressBook` (Einträge mit `finished`, neueste zuerst). Trakt- und
   Simkl-Verlauf kommen später.
6. **„Heute neu“ [C]:** neue `SourceKind.upcoming` / `CatalogSource.upcoming`. Sie lässt sich im Startseiten-Editor wie
   Weiterschauen hinzufügen und verschieben. Alte Profile kennen den Fall nicht; das ist kein Problem, weil nur neu
   hinzugefügt wird.

## 8. Dem Builder überlassen

Genaue Abstände, Schriftgrößen, Animationskurven, Symbolwahl, Platzierung der Uhr, Anzahl Hero-Folien (Vorschlag 8).

## 9. Risiken

- `.sidebarAdaptable` auf tvOS 18 frisst die Zurück-Taste bzw. öffnet die Leiste beim Linksdrücken am Rand –
  gewollt, aber Reihen müssen ganz links fokussierbar bleiben.
- Hero oben + Reihen: Fokus von Reihe nach oben muss im Hero landen, nicht in der Leiste.
- Aufklappen verändert Reihenbreite → Scrollposition darf nicht springen (feste Ankerung am fokussierten Element).
