# Prompt: Gesamtanalyse, Design-Konfigurator und Verbesserungsplan

Stand 22.11.2026. Den Block zwischen den Linien als Ganzes in eine neue Claude-Code-Session im Repo `tvos-player` kopieren.
Anhang B ist der Folge-Prompt, den du nach dem Export aus dem Konfigurator benutzt.

---

## Rolle und Auftrag

Du bist ein Senior-Team aus tvOS-/Swift-Ingenieur, Software-Architekt, Security-Reviewer und Produktdesigner für
10-Fuß-Oberflächen. Du analysierst die App **Player** (dieses Repo) vollständig und lieferst am Ende einen konkreten,
priorisierten Umsetzungsplan.

**Anlass:** Qualität vor dem Weiterbau. Die App soll eine solide, sichere und edel aussehende Grundlage bekommen,
bevor neue Features entstehen.

## Harte Regeln (gelten für alle Stufen)

1. **Kein Code wird geändert.** Weder in `App/` noch in `Packages/`, auch nicht „nur kurz“. Es werden keine Tests
   geschrieben oder ausgeführt. Die Analyse ist rein lesend und statisch. Du schreibst ausschließlich neue Dateien unter
   `docs/` (Berichte, Plan und HTML-Konfigurator).
2. **Durchlaufen ohne Pause.** Arbeite alle Stufen nacheinander bis zum fertigen Plan ab, ohne auf Freigaben zu warten.
   Wenn eine Entscheidung offen ist, triff sie selbst, kennzeichne sie mit **[C]** und begründe sie in einem Satz.
   Die Entscheidungen des Nutzers sind mit **[N]** gekennzeichnet und gelten als fest.
3. **Skills nutzen, aber ohne deren Rückfrage-Schleifen.** Lade zu jeder Stufe die unten genannten Skills und arbeite
   nach ihrer Methodik. Wenn ein Skill Fragen stellen, eine Freigabe einholen oder Code ändern will (zum Beispiel
   Brainstorming, TDD oder `--fix`), überspringe genau diesen Teil. Die Fragen sind durch dieses Dokument beantwortet.
4. **Subagenten sind erlaubt [N].** Verteile unabhängige Teile parallel (Skill `superpowers:dispatching-parallel-agents`).
   Gib jedem Agenten die harten Regeln, die betroffenen Dateien und das erwartete Befundformat mit. Verifiziere seine
   Befunde, bevor du sie übernimmst.
5. **Das Repo ist öffentlich.** In den Berichten stehen keine Schlüssel, Tokens, Namen, E-Mail-Adressen oder IPs. Wenn
   du ein Geheimnis findest, nennst du nur Commit, Datei und Art, niemals den Wert.
6. **Umgebung:** Linux-Container ohne Xcode, ohne Simulator und ohne Gerät. Laufzeitverhalten leitest du aus dem Code
   ab und markierst es als „abgeleitet“. Was sich nur am Gerät klären lässt, kommt in die Liste „Am Gerät prüfen“.
7. **Sprache:** Alle Berichte sind auf Deutsch, wie die bestehenden Specs. Code-Bezeichner bleiben im Original.
8. **Belege:** Jeder Befund nennt `Datei:Zeile`, ein konkretes Fehlerszenario (Eingabe/Zustand → falsches Ergebnis),
   den Schweregrad (kritisch / hoch / mittel / niedrig) und die Sicherheit der Aussage (bestätigt / plausibel).
   Was du nicht belegen kannst, kommt nicht hinein.

## Ablage

Alle Ergebnisse liegen unter `docs/superpowers/analysis/2026-11-22/`:

| Datei | Stufe |
|---|---|
| `00-uebersicht.md` | Zusammenfassung, Top-10-Befunde, Links auf alles |
| `01-bestandsaufnahme.md` | Stufe 1 |
| `02-bugs.md` | Stufe 2 |
| `03-engineering-entscheidungen.md` | Stufe 3 |
| `04-system-design.md` | Stufe 4 |
| `05-code-review.md` | Stufe 5a |
| `06-security-review.md` | Stufe 5b |
| `07-design-analyse.md` | Stufe 6 |
| `../../design/konfigurator/index.html` | Stufe 6, HTML-Konfigurator |
| `docs/superpowers/plans/2026-11-22-verbesserungen.md` | Stufe 7, Umsetzungsplan |
| `08-roadmap-und-ideen.md` | Stufe 7, Weiterentwicklung |

Am Ende committest du alles auf den aktuellen Arbeitsbranch. Der Commit enthält nur Dateien unter `docs/`.

---

## Stufe 1: Bestandsaufnahme

Lies zuerst `README.md`, `CHANGELOG.md`, alle Dateien unter `docs/superpowers/specs/` und `docs/superpowers/plans/`,
`App/project.yml`, `Packages/PlayerCore/Package.swift` und `.github/workflows/build.yml`. Danach liest du den Code
vollständig.

Liefere:
- eine Karte der Module und Dateien mit Zweck in je einer Zeile;
- die Hauptabläufe als Sequenz: App-Start → Profil laden → Startseite → Detailseite → Quellen → Wiedergabe →
  Up-next → Scrobble/Sync, außerdem Handy-Eingabe und App-Update;
- die externen Schnittstellen: Stremio-Addons/AIOStreams, TorBox, TMDB, MDBList, Trakt, Simkl, YouTube, atvloadly,
  Fern-Log, den lokalen Webserver;
- die Persistenz: was wo gespeichert wird (UserDefaults, Blob-Speicher, Keychain?) und wie Migrationen laufen;
- eine Liste der Entscheidungen aus Specs und Plänen, die im Code umgesetzt sein sollten. Diese Liste ist die Grundlage
  für Stufe 3.

## Stufe 2: Bug-Suche mit systematischem Debugging

**Skills:** `superpowers:systematic-debugging` (Methodik: Hypothese → Beleg im Code → Ursache statt Symptom),
`engineering:debug`, `code-review` auf Stufe `high` über den gesamten Code statt über einen Diff.

Es sind keine Bugs bekannt [N], du suchst selbst. Prüfe vier Bereiche mit gleicher Gründlichkeit [N], gern mit je
einem Subagenten:

1. **Wiedergabe:** `PlaybackEngine`, `PlayerScreen`, Dolby Vision (P5/P7/P8, Umwandlung P7 → 8.1, FEL), Tonauswahl
   (Atmos-Passthrough, TrueHD/DTS-HD → PCM, DD-Vorzug), Untertitel (Hash-Abgleich, Versatz, Zeichensatz),
   Scrubbing mit Vorschau, Intro überspringen, Up-next (Vorladen 2 min vor Ende, Countdown 20 s, Abbruch, nicht
   ausgestrahlte Folgen), „Noch da?“, die Spur-Erinnerung pro Serie.
2. **Fokus & Navigation:** Seitenleiste und obere Leiste, gepushte Seiten, Fokus-Rückkehr, Hero-Diashow,
   Hintergrund nach Fokus (350 ms), aufklappende Poster, Einstellungs-Kategorien, Personenseite, Trailer-Player.
   Das größte Anti-Ziel aus der Design-Spec ist: Fokus springt, geht verloren oder hängt.
3. **Sync & Profile:** `TraktClient`, `SimklClient`, `ScrobbleTracker`, `APIRequest`/Retry, Gerätelogin,
   Token-Erneuerung, Wahl der Quelle für Fortschritt (lokal/Trakt/Simkl), `ProfileStore`, `BlobStorage`,
   `DefaultsStorage`, Sicherung und Wiederherstellung, Abwärtskompatibilität von `Profile.init(from:)`, Nuvio-Import.
4. **Addons & Startseite:** `AddonClient`, `StremioModels`, AIOStreams-Extrafelder, `StreamTraits` (Ranking,
   gecachte TorBox-Quellen zuerst), Reihen-Editor, fertige Pakete, Listen aus TMDB/Trakt/MDBList, `ImagePipeline`,
   `RatingsStore`, Kalender und „Heute neu“.

Prüfe in jedem Bereich gezielt:
- Nebenläufigkeit unter Swift 6: Actor-Isolation, `@MainActor`, Data Races, Tasks ohne Abbruch, Tasks, die eine
  zerstörte View überleben, doppelte Starts;
- den Lebenszyklus: App in den Hintergrund und zurück, Profilwechsel während laufender Abrufe, Netzabbruch,
  leere oder fehlerhafte API-Antworten;
- Randfälle: keine Quellen, eine einzige Folge, Staffel 0/Specials, fehlende Bilder, sehr lange Titel, Zeitzonen beim
  Kalender, Datumsgrenzen um Mitternacht;
- Speicher: Retain-Zyklen in Closures, wachsende Caches ohne Grenze, Beobachter, die nicht entfernt werden;
- Fehlerbehandlung: verschluckte Fehler, `try?` an kritischen Stellen, Force-Unwraps, `fatalError`.

**Verifikation:** Jeder Kandidat wird von einem zweiten Agenten adversarial geprüft: Ist das Szenario wirklich
erreichbar? Nur Befunde, die bestehen, kommen in `02-bugs.md`, sortiert nach Schweregrad. Verworfene Kandidaten
listest du am Ende kurz mit Grund auf.

## Stufe 3: Engineering-Analyse der Entscheidungen und Planungen

**Skills:** `engineering:architecture` (ADR-Format), `engineering:tech-debt`.

- Prüfe jede Entscheidung aus der Liste in Stufe 1: Ist sie umgesetzt, teilweise umgesetzt, abgewichen oder vergessen?
  Erstelle dazu eine Tabelle mit Beleg.
- Bewerte die tragenden Grundentscheidungen im ADR-Stil (Kontext, Entscheidung, Folgen, Bewertung heute,
  Empfehlung: behalten / anpassen / ersetzen):
  - Aufteilung App ↔ `PlayerCore` und was davon testbar ist;
  - `AppModel` als zentrales Modell und State-Management mit SwiftUI-Observation;
  - XcodeGen, Bauen nur in CI, unsignierte IPA, atvloadly als Update-Weg;
  - Persistenzmodell und Migrationen;
  - eigener Webserver für die Handy-Eingabe;
  - Fern-Log als Diagnoseweg;
  - Ranking und Auswahl der Quellen.
- Große Umbauten sind erlaubt, wenn der Nutzen klar belegt ist [N]. Jede Umbau-Empfehlung nennt Nutzen, Risiko,
  Aufwand (S/M/L) und einen schrittweisen Migrationspfad, der bestehende Profile erhält.
- Bewerte den Planungsprozess selbst: Wie gut haben Specs, Pläne und Builds zusammengearbeitet? Was sollte künftig
  anders laufen, gerade weil jeder Gerätetest 15 bis 20 Minuten kostet?
- Bewerte die technischen Schulden mit Kategorie, Auswirkung und Priorität.

## Stufe 4: System-Design

**Skill:** `engineering:system-design`.

Ergebnis ist `04-system-design.md` mit:
- einem Architekturdiagramm (Mermaid) des Ist-Zustands: Schichten, Module, externe Dienste;
- Datenflüssen und Zuständen für die Hauptabläufe, Sequenzdiagramme für Wiedergabe-Start und Sync;
- einem Nebenläufigkeitsmodell: Wer läuft auf welchem Actor, wo werden Daten geteilt?
- der Fehler- und Retry-Strategie pro externem Dienst, einschließlich Rate-Limits, Timeouts und Offline-Verhalten;
- **Performance [N]:** Startzeit bis zur bedienbaren Startseite, Zeit bis zur ersten Quelle und bis zur ersten
  Plakette, Bild-Pipeline (Dekodierung, Größen, Cache-Grenzen), Speicher bei langen Reihen, Arbeit pro Fokuswechsel.
  Alles ist aus dem Code abgeleitet. Nenne für jeden Engpass Ursache, geschätzte Wirkung und Vorschlag, und schlage
  Messpunkte für das Fern-Log vor, mit denen sich das am Gerät belegen lässt.
- einem Soll-Bild: wie die Architektur nach den empfohlenen Umbauten aussieht, als zweites Diagramm;
- einer **Architektur für die Anpassbarkeit des Aussehens:** Wie bildet das Modell (`Appearance` in `PlayerCore`)
  künftig viele, gruppierte Optionen und Vorlagen-Presets ab [N]? Wie bleiben die Optionen versioniert, testbar und
  mit alten Sicherungen kompatibel? Wie wird ein JSON-Export aus dem Konfigurator direkt als Preset importiert, etwa
  über die Handy-Eingabeseite?

## Stufe 5a: Code-Review

**Skills:** `code-review` (Stufe `high`, gesamter Code), `simplify` nur als Analyse ohne Anwenden.

Prüfe Lesbarkeit, Duplikate, zu große Dateien und Views, Benennung, Swift-6-Idiome, Zugriffsmodifikatoren,
Testabdeckung von `PlayerCore` (welche Logik ist ungetestet und sollte getestet sein?), Lokalisierung (DE/EN
vollständig?) und Barrierefreiheit (VoiceOver-Labels, Kontraste, Fokus-Reihenfolge; Skill
`design:accessibility-review`). Bugs stehen in Stufe 2, hier geht es um Qualität. Nichts doppelt aufführen.

## Stufe 5b: Security-Review

**Skills:** `security-review`, die Methodik von `claude-security:scan` (Threat-Model → Recherche → adversarial
Verifikation), ohne Patches zu erzeugen.

**Bedrohungsmodell [N]:** Ein Angreifer befindet sich im selben WLAN. Er darf weder Schlüssel lesen noch Einstellungen,
Addons oder Profile ändern, noch die App zu Aktionen bringen. Zusätzlich gelten Addon-Antworten und Antworten externer
Dienste als nicht vertrauenswürdige Eingaben.

Prüfe mindestens:
1. **Webserver der Handy-Eingabe:** Authentifizierung (Token, PIN, QR-Geheimnis?), Lebensdauer des Servers, Bindung an
   Interfaces, CSRF und DNS-Rebinding, Eingabevalidierung, Größenlimits, ob Sicherungen mit allen Schlüsseln über das
   Netz abrufbar sind, Transport (HTTP im Klartext?).
2. **Speicherung von Geheimnissen:** API-Schlüssel und OAuth-Tokens. Liegen sie in UserDefaults oder im Blob-Speicher
   statt im Keychain? Sind sie in Sicherungen, Logs oder Crash-Pfaden enthalten?
3. **Fern-Log und `tools/logcollector.py`:** welche Daten das Log verlässt (Schlüssel, URLs mit Tokens, Titel), ob
   sich das Ziel manipulieren lässt und wie das Skript eingehende Daten verarbeitet.
4. **App-Update über atvloadly:** Kann jemand im WLAN eine Neuinstallation auslösen oder eine fremde IPA unterschieben?
   Wie werden Build-Nummer und Release geprüft?
5. **Addons und Netzwerk:** URL-Konstruktion, Injection in Pfade/Query, Weiterleitungen, ATS-Ausnahmen in
   `project.yml`/Info.plist, Zertifikatsprüfung, `YouTubeResolver`, User-Agent-Tricks, Parsing großer oder bösartiger
   Antworten.
6. **CI/Supply-Chain:** `build.yml` (Rechte, ungepinnte Actions, `brew install` ohne Version), Release-Veröffentlichung.
7. **Git-Historie [N]:** Durchsuche alle Commits nach Schlüsseln, Tokens, Namen, E-Mail-Adressen, IPs und
   Hostnamen, zum Beispiel mit `git log -p --all` und gezielten Mustern. Nenne nur Commit und Datei, niemals den Wert,
   und schlage eine Bereinigung vor (Schlüssel rotieren, gegebenenfalls Historie umschreiben). Umgesetzt wird nichts.

Jeder Befund nennt Angriffsszenario, Voraussetzung, Auswirkung, Schweregrad und eine konkrete Gegenmaßnahme.

## Stufe 6: Design-Analyse und HTML-Konfigurator

**Skills:** `frontend-design:frontend-design`, `design:design-critique`, `design:design-system`, `artifact-design`
(für den Konfigurator), `artifact-capabilities`, falls der Konfigurator Zustand speichern oder exportieren soll.

**Feste Vorgaben [N]:**
- **Ziel:** edel und hochwertig, eine Mischung aus Apple-TV-App (Ruhe, Raum, große Bilder), Infuse (technisch,
  starke Metadaten und Plaketten), Kaleidescape/Mubi (Kino-Boutique, zurückhaltend, editoriale Typografie) und
  Netflix/Disney+ (wirkungsvolles Hero, kräftige Reihen).
- **Aufbau bleibt** nach NuvioTVOS-Vorbild (Navigation, Startseite, Einstellungs-Kategorien). Der Look wird neu.
- **Bewegung:** ruhig und dezent, weiche Überblendungen, tvOS-Parallax, nichts Verspieltes.
- **Schrift:** Systemschrift (SF Pro), aber mit klarer Typo-Hierarchie, Gewichten, Laufweiten und Abständen.
- **Anpassbarkeit:** viele Optionen, gut gruppiert, mit einem edlen Standard und Vorlagen-Presets als Einstieg.
- Die Anti-Ziele aus `docs/superpowers/specs/2026-11-21-design-umbau-design.md` gelten weiter: kein Fokusspringen,
  kein Ruckeln durch Bildladen bei jedem Fokuswechsel, keine verlorenen Profile.

### 6a: Design-Analyse (`07-design-analyse.md`)

- Ist-Zustand aus dem Code, je Bereich: Startseite & Hero, Detailseite, Player-Oberfläche, Navigation &
  Einstellungen. Zu jedem Bereich: Farben, Typografie, Abstände, Ecken, Schatten, Fokus-Effekte, Animationen,
  Inkonsistenzen (hart codierte Werte, abweichende Größen) und was „billig“ wirkt, mit Begründung.
- Ein **Design-System als Vorschlag:** Tokens für Farben (dunkel, mit Akzent), Typo-Skala für 1920×1080 bei
  10-Fuß-Abstand, Abstandsraster, Radien, Elevation, Fokus-Zustände, Bewegungskurven und Dauern.
- tvOS-Regeln beachten: sichere Bildschirmränder, Mindestgrößen, Fokus-Engine, Lesbarkeit auf Bildern (Verläufe,
  Abdunklung), HDR-Inhalte hinter der Oberfläche.

### 6b: HTML-Konfigurator (`docs/design/konfigurator/index.html`)

Eine eigenständige, interaktive Seite, auf der der Nutzer das gewünschte Aussehen zusammenstellt, damit am Ende genau
umgesetzt wird, was er will. Anforderungen:

- **Vorschau im Format 16:9** (1920×1080, skaliert), die wie ein Apple-TV-Bildschirm aussieht, mit Platzhalterbildern.
  Keine echten Poster, Logos oder Marken.
- **Vier Bereiche [N]**, jeweils mit Live-Vorschau:
  1. **Startseite & Hero:** Hero-Stil (Vollbild, Banner, Karussell, aus), Info-Ebene, Logo oder Titel,
     Kartenform (Poster, Querformat, Mischung), Kartengröße, Ecken, Abstände, Reihentitel, Fokus-Effekt (Skalierung,
     Glanz, Rahmen, Schatten), Hintergrund nach Fokus an/aus, aufklappende Poster an/aus.
  2. **Detailseite:** Layout (links ausgerichtet, zentriert, Kino-Vollbild), Plakettenstil, Bewertungsdarstellung,
     Besetzung, Darstellung der Quellenliste, Beschreibungslänge.
  3. **Player-Oberfläche:** Steuerleiste (minimal bis ausführlich), Plaketten, Ton- und Untertitel-Panel,
     Up-next-Countdown, „Noch da?“-Dialog.
  4. **Navigation & Einstellungen, global:** Seitenleiste oder obere Leiste, Uhr, Einstellungs-Layout, Akzentfarbe,
     Hintergrundton, Typo-Skala, Bewegungsintensität.
- **Vorlagen-Presets** als Einstieg, mindestens „Apple TV“, „Infuse“, „Kino-Boutique“, „Streaming“ und ein eigener
  empfohlener Standard „Edel“. Danach lässt sich jede Einstellung frei verändern.
- **Export:** Ein Knopf erzeugt JSON mit Versionsfeld, Preset-Basis und allen Werten, zum Kopieren und als
  Datei-Download. Ein Import lädt das JSON zurück. Das Schema entspricht dem Anpassbarkeits-Modell aus Stufe 4 und
  wird in `07-design-analyse.md` dokumentiert.
- Jede Option hat einen Kurztext, der erklärt, was sie bewirkt. Optionen, die auf tvOS schwierig oder teuer sind,
  sind markiert.
- Nur erlaubte CDNs, dunkles Theme, alles in einer Datei. Wenn das Artifact-Tool verfügbar ist, veröffentliche die
  Seite zusätzlich als private Artifact-Seite und nenne den Link in `00-uebersicht.md`.

## Stufe 7: Umsetzungsplan und Weiterentwicklung

**Skills:** `superpowers:writing-plans` (Format wie `docs/superpowers/plans/2026-11-21-design-umbau.md`),
`engineering:deploy-checklist` für die Build-Bündel, `superpowers:verification-before-completion` vor dem Abschluss.

### 7a: Plan (`docs/superpowers/plans/2026-11-22-verbesserungen.md`)

- **Priorität [N]:** Sicherheit → Abstürze und Datenverlust → Bugs → Design → Struktur/Architektur. Innerhalb einer
  Stufe nach Schweregrad und Nutzen/Aufwand.
- **Geschnitten in wenige gebündelte Builds [N]**, weil jeder Gerätetest 15 bis 20 Minuten kostet. Jeder Build enthält
  zusammengehörige Tasks, ein Testprotokoll fürs Gerät („Am Gerät prüfen“) und die erwarteten Fern-Log-Zeilen.
- Jeder Task enthält: betroffene Dateien, Befund-ID aus den Berichten, Änderung in Sätzen, Tests für `PlayerCore`
  (mit dem bestehenden Podman-Befehl), Risiko, Abwärtskompatibilität der Profile und Checkbox-Schritte.
- **Design-Tasks mit Platzhalter [N]:** Die Infrastruktur plant er konkret aus (Tokens, Anpassbarkeits-Modell,
  Preset-Import, Komponenten-Umbau). Die konkreten Werte und Varianten verweisen auf
  `docs/design/konfigurator/export.json`, das es noch nicht gibt. Diese Tasks werden mit dem Folge-Prompt aus
  Anhang B fertiggestellt.
- Die Architektur-Umbauten aus Stufe 3 kommen mit Migrationspfad, aufgeteilt auf die Builds.
- Am Anfang des Plans stehen „Global Constraints“ wie im bestehenden Plan: tvOS 18, öffentliches Repo, Defaults in
  `Profile.init(from:)`, Bilder nur über `ImagePipeline`, Oberfläche auf Deutsch.

### 7b: Weiterentwicklung (`08-roadmap-und-ideen.md`)

- Eine Roadmap nach Jetzt / Danach / Später, die auf dem Plan aufbaut.
- Prozessverbesserungen: Testbarkeit, Diagnose, CI, schnellere Prüfungen am Gerät.
- **Ideenliste neuer Features [N]**, getrennt vom Plan und bewertet nach Nutzen, Aufwand und Risiko. Ausgeschlossen
  bleiben die bisherigen Nicht-Ziele: Watch Party, IPTV, KI-Reihen, Überraschung, Ambient-Modus und Trailer im Hero.

## Abschluss

1. Schreibe `00-uebersicht.md`: in fünf Sätzen, wo die App steht; die Top-10-Befunde über alle Stufen; die Liste
   „Am Gerät prüfen“; alle [C]-Entscheidungen gesammelt; Links auf alle Dateien und den Konfigurator.
2. Prüfe vor dem Commit: Es wurde nichts außerhalb von `docs/` geändert (`git status`). In keinem Bericht steht ein
   Geheimnis, ein Name oder eine IP (per grep prüfen). Jeder Befund hat `Datei:Zeile`.
3. Committe auf den Arbeitsbranch und pushe.
4. Antworte im Chat nur kurz: die wichtigsten drei Erkenntnisse, den Link zum Konfigurator und den Hinweis, dass der
   Nutzer dort exportieren und danach den Folge-Prompt verwenden soll.

---

## Anhang A: Getroffene Nutzerentscheidungen (Kurzfassung)

| Thema | Entscheidung |
|---|---|
| Code ändern | Nein, nur analysieren und planen |
| Ablauf | Komplett durchlaufen bis zum fertigen Plan, ohne Pause |
| Agenten | Subagenten erlaubt |
| Ausgabe | Markdown im Repo |
| Bug-Fokus | Wiedergabe, Fokus & Navigation, Sync & Profile, Addons & Startseite |
| Bekannte Bugs | Keine, selbst suchen |
| Tests | Keine schreiben oder ausführen, nur lesen |
| Logs | Keine vorhanden |
| Architektur | Große Umbauten erlaubt, wenn begründet |
| Performance | Mitbewerten |
| Bedrohungsmodell | Angreifer im WLAN |
| Git-Historie | Mitprüfen |
| Design-Vorbild | Mischung aus Apple TV, Infuse, Kaleidescape/Mubi und Netflix/Disney+ |
| Aufbau | Bleibt nach Nuvio-Vorbild, der Look wird neu |
| Bewegung | Ruhig und dezent |
| Schrift | Systemschrift, besser gesetzt |
| Design-Ergebnis | HTML-Konfigurator und eine hoch anpassbare App |
| Konfigurator-Umfang | Startseite/Hero, Detailseite, Player, Navigation/Einstellungen |
| Optionen in der App | Viele, gut gruppiert, mit Presets |
| Priorität | Sicherheit zuerst |
| Plan-Form | Wenige gebündelte Builds |
| Design im Plan | Platzhalter, die nach dem Konfigurator-Export gefüllt werden |
| Neue Features | Als Ideenliste, bisherige Nicht-Ziele ausgeschlossen |
| Anlass | Qualität vor Weiterbau |

## Anhang B: Folge-Prompt nach dem Konfigurator-Export

> Ich habe im Konfigurator mein Aussehen zusammengestellt. Der Export liegt unter
> `docs/design/konfigurator/export.json`. Lies `docs/superpowers/analysis/2026-11-22/07-design-analyse.md` und den
> Plan `docs/superpowers/plans/2026-11-22-verbesserungen.md`. Ersetze alle Design-Platzhalter im Plan durch konkrete
> Tasks mit den Werten aus dem Export: Tokens, Komponenten, das Standard-Preset „Mein Look“ und die Optionen, die in
> der App einstellbar bleiben sollen. Code wird nicht geändert. Passe die Build-Bündelung an, wenn nötig, und committe
> den aktualisierten Plan.
