# 00 · Übersicht der Qualitätsanalyse vom 22.11.2026

Analysierter Stand: Branch `integ`, Commit `b2188a2` (Build 249). Die Analyse ist rein lesend und statisch: Es wurde
kein Code geändert, nichts gebaut und kein Test ausgeführt. Laufzeitverhalten ist aus dem Code abgeleitet und so
gekennzeichnet.

## Wo die App steht

Die App ist funktional weit: Wiedergabe bis Dolby Vision FEL, Quellensuche über Addons, Sync mit Trakt und Simkl,
eine frei gestaltbare Startseite, und das alles mit einem sauber getrennten, gut getesteten Logik-Paket (`PlayerCore`,
965 Tests). Es gibt keinen kritischen Befund, aber vier Stellen, an denen Daten verloren gehen oder falsch verbucht
werden können, und zwei Wege, auf denen ein Angreifer im WLAN an Schlüssel kommt oder Profile ersetzt. Die meisten
Fehler liegen dort, wo kein Test hinkommt: in drei sehr großen App-Typen, die die Abläufe der Wiedergabe und des
Profilwechsels von Hand steuern. Für das Aussehen gibt es schon ein ordentliches Token-System, es deckt aber erst die
Hälfte der Bildschirme ab und ist nicht zur Laufzeit umschaltbar. Der wichtigste Schritt vor jedem Weiterbau ist
klein: Tests in die CI, die Handy-Seite vom Fernseher bestätigen lassen und dafür sorgen, dass ein unlesbarer
Profilstand nie überschrieben wird.

## Zahlen

| Stufe | Ergebnis |
|---|---|
| Bugs (Stufe 2) | 93 Kandidaten, 80 nach Gegenprüfung bestanden: 0 kritisch, 4 hoch, 31 mittel, 45 niedrig; 13 verworfen |
| Entscheidungen (Stufe 3) | 106 geprüft: 71 umgesetzt, 11 teilweise, 11 abgewichen, 8 überholt, 4 vergessen, 1 nicht prüfbar |
| Code-Qualität (Stufe 5a) | 29 Befunde: 8 hoch, 14 mittel, 7 niedrig |
| Sicherheit (Stufe 5b) | Code: 2 hoch, 3 mittel, 12 niedrig. Git-Historie: 1 mittel, 4 niedrig, keine Zugangsdaten |
| Design (Stufe 6) | 28 Befunde: 7 hoch, 16 mittel, 5 niedrig |
| Umfang | App 107 Dateien / 20 041 Zeilen, `PlayerCore` 132 / 20 064, Tests 75 / 13 607 |

## Top-10-Befunde über alle Stufen

| # | Befund | Schweregrad | Bericht | Im Plan |
|---|---|---|---|---|
| 1 | **SEC-1:** Die Handy-Seite läuft über Klartext-HTTP. Ein mitgelesenes Token liefert über `/export` alle Schlüssel und Tokens und erlaubt, alle Profile zu ersetzen, ohne Rückfrage am Fernseher (`App/Sources/Views/PhoneInputView.swift:27`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:121`). | hoch, bestätigt | [06](06-security-review.md) | Task 1.4 |
| 2 | **S-1, S-2, D-1:** Lässt sich `profiles.json` nicht dekodieren, startet die App mit einem Standardprofil und überschreibt beim nächsten Speichern alle Profile. Dafür genügt ein unbekannter Enum-Wert in einem einzigen Profil (`Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:36`, `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:61`). Der Auslöser ist heute ein Rückschritt auf einen älteren Build; mit neuen Aussehens-Optionen wird er alltäglich. | mittel (Folge: Totalverlust), bestätigt | [02](02-bugs.md), [07](07-design-analyse.md) | Tasks 1.2, 1.3 |
| 3 | **SEC-3:** Die App spricht atvloadly ohne Anmeldung über HTTP an. Ob ein Dritter im WLAN ein fremdes Paket installieren kann, hängt am Dienst (`Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:184`). | hoch, plausibel | [06](06-security-review.md) | Task 1.6, Roadmap |
| 4 | **W-B-1:** `ProgressBook.record` ersetzt den Eintrag ganz. 15 Sekunden erneutes Öffnen löschen das „Gesehen“-Häkchen; wer die automatisch gestartete nächste Folge in der ersten Minute beendet, verliert die Serie aus „Weiterschauen“ (`Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:53`). | hoch, bestätigt | [02](02-bugs.md) | Task 2.1 |
| 5 | **A-B-1:** Eine Sicherung auf einem anderen Gerät oder nach einer Neuinstallation einzuspielen löscht alle Fusion-Kit-Reihen von der Startseite (`Packages/PlayerCore/Sources/PlayerCore/Import/FusionKitCatalog.swift:201`, `App/Sources/FusionKitStore.swift:405`). | hoch, bestätigt | [02](02-bugs.md) | Task 2.4 |
| 6 | **F-B-1:** Nach „Nächste Folge automatisch“ lädt die Quellenliste wieder die Quellen der ersten Folge. Eine Auswahl spielt dann die falsche Datei und bucht den Fortschritt auf die neue Folge (`App/Sources/Views/DetailViews.swift:841`). | hoch, plausibel | [02](02-bugs.md) | Task 3.4 |
| 7 | **W-A-1:** Scheitert das erste Laden und repariert die Fehlerleiter es, entfallen Tonwahl, Untertitel-Automatik und Platzhalter-Prüfung (`App/Sources/Views/PlayerScreen.swift:444`). | hoch, plausibel | [02](02-bugs.md) | Task 3.2 |
| 8 | **Q-22, Q-12:** Die 965 Tests laufen nicht in CI; ein Build mit roten Tests würde veröffentlicht. Die App wird im Swift-5-Modus gebaut, die Hälfte des Codes ist nicht auf Data Races geprüft (`.github/workflows/build.yml`, `App/project.yml:47`). | hoch | [05](05-code-review.md) | Tasks 1.1, 6.4 |
| 9 | **SEC-2, GIT-1:** Das Fern-Log ist immer an und geht an jeden, der sich im WLAN als Empfänger ankündigt (`App/Sources/RemoteLog.swift:21`). Sechs Merge-Commits tragen einen Vornamen und eine E-Mail-Adresse mit Rechner- und Routernamen. | mittel, bestätigt | [06](06-security-review.md) | Task 1.5; GIT-1 ist Entscheidung des Nutzers |
| 10 | **Q-1, Q-3, Q-5, D-2, D-3:** Die Ablauflogik steckt in drei untestbaren Großtypen (`PlayerControls`, `StreamListView`, `AppModel`). Im Design gibt es zwei Welten: Einstellungen und Startseite auf Tokens, Player und sechs weitere Seiten mit 135 Farb- und 173 Größen-Literalen; vier Player-Karten sind über hellen HDR-Bildern nicht sicher lesbar. | hoch (Struktur und Design) | [05](05-code-review.md), [07](07-design-analyse.md) | Builds 4 bis 6 |

## Am Gerät prüfen

Gebündelt aus allen Berichten. Die vollständigen Listen stehen am Ende der einzelnen Berichte.

**Entscheidet über einen Befund**
1. Läuft `.task` einer Seite nach dem Schließen des Vollbild-Players erneut? Entscheidet F-B-1 und F-B-5.
2. Reihenfolge „`catch` vor `onChange`“ beim ersten Ladefehler der Engine. Entscheidet W-A-1.
3. Nimmt atvloadly Aufträge von jedem Gerät im WLAN an, und was steht in den Antworten (Apple-ID-Bezug)? Entscheidet SEC-3.
4. Lässt sich ein Fortschrittseintrag mit `Date.distantPast` wieder lesen? Wenn nicht, steigt S-11 auf „hoch“.
5. Hält tvOS weggescrollte Zellen eines `LazyHStack`? Entscheidet, ob lange Reihen den Speicher füllen.
6. Wohin fällt der Fokus, wenn eine Kit-Collection-Reihe vom Platzhalter zu Kacheln wechselt (F-A-2) und wenn eine
   Reihe über das Kontextmenü verschwindet (F-A-3)?
7. Läuft der Handy-Server weiter, wenn der Bildschirmschoner startet (SEC-16)?

**Vor dem Umbau der Persistenz**
8. Ist „Application Support“ auf dem Gerät beschreibbar, und wo liegen die Blöcke tatsächlich (Logzeile „speicher“)?
9. Überstehen UserDefaults und Keychain-Einträge die 7-Tage-Neusignatur und ein Update über atvloadly?
10. Wann leert tvOS den Caches-Ordner?

**Wiedergabe**
11. Tatsächliche Tonausgabe bei TrueHD (Standard wandelt in Dolby Digital Plus 5.1) und Wirkung von FEL.
12. Zeit vom Druck bis zum ersten Bild, aufgeteilt nach den Messpunkten aus [04 §6.3](04-system-design.md).
13. Spulen mit langsamen Wischbewegungen (W-B-8) und „Überspringen“ kurz vor dem Dateiende (W-B-12).

**Design**
14. Lesbarkeit der vier Player-Karten über einer hellen HDR-Szene (D-2).
15. Echte Punktgrößen der tvOS-Textstile und der sichtbare Seitenrand mit Seitenleiste (80 oder 160 pt).
16. VoiceOver auf Kacheln und im Player (Q-26, Q-27).

## Alle [C]-Entscheidungen

Entscheidungen, die ich selbst getroffen habe, jeweils mit Begründung in einem Satz. Alle sind korrigierbar.

| # | Entscheidung | Begründung |
|---|---|---|
| 1 | Analysiert wurde `integ` (Commit `b2188a2`), nicht der Stand von `main`, von dem der Arbeitsbranch abzweigt. | Fast alle im Auftrag genannten Funktionen (FEL, „Noch da?“, App-Update, Intro überspringen) gibt es nur auf `integ`, 280 Commits weiter. |
| 2 | Die Berichte liegen auf dem Arbeitsbranch und verweisen auf Dateien von `integ`; `integ` wurde nicht hineingemischt. | Der Commit soll nur Dateien unter `docs/` enthalten; die neuen Dateien lassen sich ohne Konflikt nach `integ` übernehmen. |
| 3 | Schweregrad und Sicherheit der Befunde sind die Werte **nach** der Gegenprüfung, auch wo sie niedriger sind als im Erstbericht. | Die Gegenprüfung hat die Erreichbarkeit jedes Szenarios am Code nachvollzogen und ist damit die bessere Quelle. |
| 4 | Die Zahl „965 Tests“ stammt aus dem Zählen der `@Test`-Markierungen, nicht aus einem Testlauf. | Tests durften nicht ausgeführt werden. |
| 5 | Die Bereinigung der Git-Historie (GIT-1) steht nicht im Plan. | Sie ändert alle Hashes, Tags und Releases und ist deshalb eine eigene Entscheidung des Nutzers. |
| 6 | Das Aussehen wird als Vorlage plus Abweichungen gespeichert, nicht als vollständiger Wertesatz. | Alte Sicherungen laden ohne Migration, und eine nachgeschärfte Vorlage wirkt bei allen, die den Wert nicht angefasst haben. |
| 7 | Der Fokus bleibt in jeder Vorlage weiß; die Akzentfarbe markiert nur „gewählt“ und den Hauptknopf. | Der Fokus darf nie von einer wählbaren Farbe abhängen, sonst ist er bei manchen Kombinationen kaum zu sehen. |
| 8 | Die Vorlage „Edel“ schaltet „Poster aufklappen“ aus und nutzt eine eigene Karte statt des Systemstils. | Das Aufklappen ist laut Historie die häufigste Ursache für springenden Fokus (9 Commits), und nur die eigene Karte erlaubt wählbare Ecken, Rahmen und Schatten. |
| 9 | `trackPanelStyle` `topBar` wird der neuen Option `trackPanel = seite` zugeordnet. | `topBar` hat im Konfigurator keine genaue Entsprechung; die Zuordnung wird nach dem Export geprüft. |
| 10 | `PlaybackKit` (Engine hinter einem eigenen Paket) wird nicht nachgebaut, der Satz in der Spec wird gestrichen. | Ein zweites Wiedergabe-Backend ist nicht geplant; die Kapselung hätte heute nur Kosten. |
| 11 | Die Handy-Seite wird nicht über TLS oder WebCrypto abgesichert, sondern über Bestätigung am Fernseher und verschlüsselten Export. | Ein selbst signiertes Zertifikat erzeugt eine Browser-Warnung, und WebCrypto steht auf `http://`-Seiten nicht zur Verfügung. |
| 12 | Die App prüft den Hash der IPA nicht selbst, sondern zeigt Build, Commit und Hash vor der Installation an; die signierte Prüfung steht in der Roadmap. | Die App lädt das Paket nicht selbst, und eine Signatur verlangt eine Schlüsselverwaltung in CI. |
| 13 | `NSAllowsArbitraryLoads` wird erst nach dem Gerätetest von Build 2 entfernt. | Die Engine öffnet eigene Verbindungen; ob die Medien-Ausnahme genügt, zeigt nur das Gerät. |
| 14 | Der Plan hat sechs Builds; Build 5 darf in 5a und 5b geteilt werden. | Weniger Builds wären je Gerätetest zu groß, und der Umfang von Build 5 steht erst mit dem Export fest. |
| 15 | In Build 5 werden je Option nur die gewählte Variante und die der Vorlage „Edel“ gebaut. | Jede weitere Variante mit eigener Fokus-Führung (Karussell, Kachel-Einstellungen) kostet Gerätetests, ohne dass sie jemand nutzt. |
| 16 | Der Konfigurator speichert seinen Stand im Browser und nutzt in der veröffentlichten Fassung nur die Fähigkeit „Datei speichern“. | Mehr braucht ein Werkzeug für eine Person nicht; als lokale Datei funktioniert der normale Download. |
| 17 | Architektur-Umbauten laufen einen Build im Schattenbetrieb (neue Regel rechnet mit, alte entscheidet). | So lassen sich Abweichungen im Fern-Log finden, bevor sich das Verhalten ändert. |

## Dateien

| Datei | Inhalt |
|---|---|
| [01-bestandsaufnahme.md](01-bestandsaufnahme.md) | Modul- und Dateikarte, Hauptabläufe, externe Schnittstellen, Persistenz, Nebenläufigkeit, CI |
| [02-bugs.md](02-bugs.md) | 80 gegengeprüfte Bugs nach Schweregrad, verworfene Kandidaten, Geräteprüfungen, ungetestete Logik |
| [03-engineering-entscheidungen.md](03-engineering-entscheidungen.md) | Soll-Ist-Tabelle der 106 Entscheidungen, sieben ADRs, Planungsprozess, technische Schulden |
| [04-system-design.md](04-system-design.md) | Ist- und Soll-Architektur, Sequenzdiagramme, Nebenläufigkeit, Fehlerstrategie, Performance, Modell für das Aussehen |
| [05-code-review.md](05-code-review.md) | 29 Qualitätsbefunde, Testabdeckung, Lokalisierung, Barrierefreiheit |
| [06-security-review.md](06-security-review.md) | Threat-Model, 17 Befunde im Code, 5 in der Git-Historie, Gegenmaßnahmen |
| [07-design-analyse.md](07-design-analyse.md) | Ist-Zustand je Bereich, Design-System, tvOS-Regeln, JSON-Schema, vollständiges Inventar |
| [08-roadmap-und-ideen.md](08-roadmap-und-ideen.md) | Roadmap Jetzt / Danach / Später, Prozessverbesserungen, 18 bewertete Ideen |
| [historie-bereinigen.sh](historie-bereinigen.sh) | Skript, das Namen und E-Mail-Adresse aus den sechs Merge-Commits entfernt (GIT-1); lokal auszuführen |
| [Umsetzungsplan](../../plans/2026-11-22-verbesserungen.md) | sechs Builds mit Tasks, Tests, Deploy-Checklisten und Geräteprotokollen |
| [Konfigurator (Datei)](../../../design/konfigurator/index.html) | eigenständige HTML-Seite, im Browser öffnen |
| [Konfigurator (veröffentlicht, privat)](https://claude.ai/artifact/MhQGZEjKmV9HQQng21oAmX) | dieselbe Seite als private Artifact-Seite |

## So geht es weiter

1. Im Konfigurator eine Vorlage wählen, anpassen und das JSON exportieren.
2. Die Datei als `docs/design/konfigurator/export.json` ins Repo legen.
3. Den Folge-Prompt aus Anhang B der Aufgabenstellung verwenden. Er füllt die Platzhalter der Design-Tasks
   (Builds 4 und 5) mit den gewählten Werten und Varianten.
4. Unabhängig davon kann Build 1 des Plans sofort beginnen; er hängt nicht am Export.
