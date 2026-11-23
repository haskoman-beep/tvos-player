# 08 · Roadmap, Prozess und Ideen

Stand: Branch `integ`, Commit `b2188a2` (Build 249). Dieses Dokument baut auf dem
[Umsetzungsplan](../../plans/2026-11-22-verbesserungen.md) auf. Die Ideenliste am Ende ist ausdrücklich **nicht** Teil
des Plans.

Methodik: Skill `product-management:roadmap-update` (Jetzt / Danach / Später), Bewertung der Ideen nach Nutzen,
Aufwand und Risiko.

## 1. Roadmap

### Jetzt (Builds 1 bis 3 des Plans)

| Ziel | Inhalt | Woran man merkt, dass es erreicht ist |
|---|---|---|
| Niemand im WLAN liest Schlüssel oder ändert Profile | Bestätigung am Fernseher, Einmal-Adresse, Export ohne Schlüssel, Fern-Log mit festem Empfänger, Update nur nach Anzeige | Die acht Prüfpunkte der Deploy-Checkliste von Build 1 |
| Profile gehen nicht verloren | Dekodierung wirft nie, unlesbarer Stand wird nie überschrieben, zwei gute Fassungen bleiben | Fixture eines künftigen Builds lädt; Hin- und Rückweg zwischen zwei Builds erhält alles |
| Kein Release mit roten Tests | `swift test` als erster CI-Job | ein absichtlich roter Test verhindert den Build |
| Fortschritt und Sync stimmen | kurzes Öffnen löscht nichts, „gesehen“ geht offline nicht verloren, kein Mischen zwischen Profilen | Prüfpunkte der Builds 2 und 3 |
| Wiedergabe startet immer vollständig | Tonwahl und Untertitel auch nach repariertem Ladefehler; Quellenliste folgt der laufenden Folge | Logzeile `player: Startschritte …` |
| Messwerte liegen vor | zehn `metric:`-Zeilen | Tabelle mit Ausgangswerten in `docs/superpowers/geraetetests/` |

### Danach (Builds 4 bis 6 des Plans)

| Ziel | Inhalt | Abhängigkeit |
|---|---|---|
| Der Look ist wählbar | Modell `Look`, fünf Vorlagen, Import aus dem Konfigurator, Laufzeit-Theme | `docs/design/konfigurator/export.json` |
| Die App sieht edel aus | eine Karte, ein Fokus-Stil, Hero- und Detail-Varianten, Player-Karten über HDR lesbar | Export; Build 4 |
| Fokus ist verlässlich | zehn Fokus-Befunde, gestaffelte Ruhezeiten | Build 4 |
| Abläufe sind testbar | `PlaybackQueue`, `UpNextPolicy`, `PlayerLocks` in `PlayerCore`; Dienste statt `AppModel` | Schattenbetrieb über einen Build |
| Schlüssel nur noch im Schlüsselbund | `schemaVersion = 2` | Gerätetest: Keychain übersteht die Neusignatur |

### Später (nach dem Plan)

| Thema | Inhalt | Auslöser |
|---|---|---|
| Signiertes Update | CI signiert „Build · Commit · SHA-256“, die App prüft mit einem öffentlichen Schlüssel | sobald ein Schlüssel in CI verwaltet werden kann |
| atvloadly absichern | Firewall-Regel oder Proxy mit Token vor dem Dienst; in der App `https://` und Auth-Kopf | Ergebnis der Netzprüfung zu SEC-3 |
| Abgleich im Hintergrund | Fern-Fortschritt alle 30 Minuten und beim Aufwachen holen (S-16) | nach Build 3 |
| Git-Historie bereinigen | Autorfelder von sechs Merge-Commits, optional Session-Trailer und Setup-Angaben (GIT-1, GIT-2, GIT-4) | Entscheidung des Nutzers; ändert alle Hashes, Tags und Releases |
| Englische Oberfläche | String-Katalog, Formate je Sprache (Q-24, Q-25) | nur wenn gewünscht; sonst bleibt das README bei „Oberfläche deutsch“ |
| Fortschritt in Blöcken | Aufteilung nach Jahr oder SQLite | ab etwa 2 000 Einträgen je Profil |
| API-Fläche von `PlayerCore` verkleinern | `public` nur, was die App braucht; toter Code (Q-17, Q-18) | bei Gelegenheit |
| Niedrige Wiedergabe-Befunde | W-A-6, W-A-10, W-B-8, W-B-9, F-B-4 | nach Gerätetest bzw. Messung |

## 2. Prozessverbesserungen

Begründung und Zahlen stehen in [03, Abschnitt 6](03-engineering-entscheidungen.md). Hier die Maßnahmen, geordnet
danach, wie viel Gerätezeit sie sparen.

### 2.1 Schnellere Prüfungen ohne Gerät

| Maßnahme | Aufwand | Wirkung |
|---|---|---|
| **Kerntests in CI** (Plan, Task 1.1) | S | Logikfehler nach 2 Minuten statt nach 20 |
| **Bildschirmfotos aus dem tvOS-Simulator in CI.** Ein UI-Test-Ziel öffnet Startseite, Detailseite, Quellenliste, Einstellungen und die Player-Oberfläche mit festen Beispieldaten (ein `DemoProfile` und ein Schein-`HTTPClient`), legt Bilder als Artefakt ab und vergleicht sie mit dem letzten Stand. | M | Aussehen, Abstände, Typografie und viele Fokus-Zustände lassen sich am Rechner ansehen. Das Gerät bleibt für Wiedergabe, Ton und echte Fokus-Wege. Für den Design-Umbau ist das der größte Hebel. |
| **Kompilier-Prüfung vor dem vollen Build** (nur `build`, ohne Paketieren und IPA-Prüfung, bei Änderungen in `App/`) | S | Build-Reparaturen kosten einen kurzen Lauf |
| **Lint mit wenigen Regeln**: keine rohen `.font(.system(size:`/`Color(red:` außerhalb von `Views/Design/`, kein `Task {` in `onChange`, Zeilenlänge 160 | S | die zwei Designwelten wachsen nicht wieder auseinander |
| **Fuzz- und Tabellentests** für alles, was Fremddaten liest (Stream-Texte, Addon-JSON, Untertitel, IntroDB) | S | Absturzpfade fallen vor dem Gerät auf |
| **Fixture je veröffentlichtem Build** (`profiles.json`, Fortschritt, Warteschlange, synthetisch) und ein Test „jeder alte Stand lädt“ | S | Kompatibilität wird geprüft statt gehofft |

### 2.2 Bessere Diagnose am Gerät

| Maßnahme | Aufwand | Wirkung |
|---|---|---|
| **Log-Verlauf auf dem Gerät** und Diagnose-Seite (Plan, Task 1.5) | M | ein Fehler muss nicht mit laufendem Empfänger nachgestellt werden |
| **Messpunkte mit festen Namen** (`metric:`) und ein kleines Skript `tools/metrics.py`, das zwei Logdateien vergleicht | S | Performance-Aussagen werden zu Zahlen |
| **Diagnose-Schalter** unter System: Ruhezeiten, Fokus-Skalierung, „alte Karte“, Schattenbetrieb an/aus | S | Varianten am Gerät vergleichen ohne neuen Build |
| **Fokus-Protokoll**: bei eingeschaltetem Schalter jede Fokusbewegung mit Quelle, Ziel und Dauer loggen | S | „Fokus springt“ wird aus dem Log lesbar statt aus der Erinnerung |
| **Absturz-Notiz**: beim Start prüfen, ob der letzte Lauf sauber endete; wenn nicht, die letzten 50 Ring-Zeilen als „letzter Absturz“ ablegen | S | Abstürze ohne Xcode nachvollziehbar |

### 2.3 Planung und Abnahme

| Maßnahme | Wirkung |
|---|---|
| **Testprotokoll je Build als Datei** (`docs/superpowers/geraetetests/build-NNN.md`, Häkchen plus erwartete Log-Zeilen) | jeder Gerätetest prüft alles, was der Build ändert, in einem Durchgang; das Ergebnis bleibt nachlesbar |
| **Entscheidungsprotokoll** `docs/entscheidungen.md` (drei Zeilen je Entscheidung; Abweichung im selben Commit eintragen) | Specs, README und Code laufen nicht mehr auseinander |
| **Nicht-Ziele nur ausdrücklich aufheben** | Scope-Drift wird sichtbar |
| **Bündel statt Einzel-Builds**, 5 bis 10 Tasks je Build | weniger Gerätetests bei gleicher Abdeckung |
| **Abnahme nach `main`** nur über ein abgehaktes Testprotokoll, Versionsnummer je Abnahme | „am Gerät geprüft“ hat wieder eine Bedeutung |
| **Schattenbetrieb für Umbauten** (neue Regel rechnet mit und loggt Abweichungen) | Architektur-Umbauten ohne Verhaltensrisiko |
| **Sicherheits-Checkliste je Build**: neue Netzadressen? neue gespeicherte Geheimnisse? neue Eingaben von außen? | die Lücken dieser Analyse entstehen nicht neu |

## 3. Ideenliste neuer Funktionen

Getrennt vom Plan. Ausgeschlossen bleiben die bisherigen Nicht-Ziele: Watch Party, IPTV, KI-Reihen, Überraschung,
Ambient-Modus und Trailer im Hero.

Bewertung: Nutzen und Aufwand je 1 (klein) bis 5 (groß), Risiko niedrig / mittel / hoch. Reihenfolge nach
Nutzen geteilt durch Aufwand.

| # | Idee | Nutzen | Aufwand | Risiko | Anmerkung |
|---|---|:-:|:-:|---|---|
| 1 | **Top Shelf**: „Weiterschauen“ und „Heute neu“ auf dem Apple-TV-Startbildschirm | 5 | 2 | niedrig | eigene Erweiterung, liest nur den Fortschritt; in der ersten Spec schon als „später“ genannt |
| 2 | **Suche über die Siri-Fernbedienung diktieren und Suchverlauf** | 3 | 1 | niedrig | Systemtastatur kann es; Verlauf lokal je Profil |
| 3 | **„Später ansehen“ und „Gesehen“ direkt im Player-Ende** (Karte nach dem Film) | 3 | 1 | niedrig | die Karte gibt es; fehlt nur die Aktion über die Warteschlange |
| 4 | **Quellen-Vorlieben je Titel oder Serie** (bevorzugte Release-Gruppe, Sprache, Größe als Regel) | 4 | 2 | niedrig | `ReleaseMatch` und `BestChoice` sind da; es fehlt die gespeicherte Regel |
| 5 | **Sammlungen und Filmreihen auf der Detailseite** (TMDB-Collection: „Teil 2 von 4“) | 3 | 2 | niedrig | Quelle `tmdbCollection` existiert schon |
| 6 | **Kapitel-Liste im Player** mit Vorschaubild | 3 | 2 | niedrig | Kapitelmarken und Spul-Vorschau sind vorhanden |
| 7 | **Schlaf-Timer** („nach dieser Folge stoppen“, „in 30 Minuten“) | 3 | 1 | niedrig | passt zur „Noch da?“-Logik |
| 8 | **Statistik-Seite je Profil** (gesehene Stunden, Serien in Arbeit, Jahresrückblick aus dem lokalen Verlauf) | 2 | 2 | niedrig | rein lokal, keine neuen Dienste |
| 9 | **Automatische Sicherung auf einen Rechner im Heimnetz** (verschlüsselt, nachts) | 4 | 3 | mittel | in der ersten Spec als „Sicherung auf den Pi“ vorgesehen; erst nach Build 2 (verschlüsselte Sicherung) |
| 10 | **Profil-PIN und Kinderprofil** (Altersfreigabe als Filter für Reihen und Suche) | 4 | 3 | mittel | Freigaben kommen schon von TMDB; PIN nur am Fernseher |
| 11 | **Benachrichtigung „neue Folge“ in der App** (Marke an der Kachel, Zähler im Kalender-Tab) | 3 | 2 | niedrig | Daten liefert der Kalender bereits |
| 12 | **MDBList-Listen als Reihen** | 3 | 2 | niedrig | im README zugesagt, aber nicht gebaut (E-53); schließt eine Lücke statt Neues zu bauen |
| 13 | **Trakt- und Simkl-Verlauf in der Bibliothek** | 3 | 2 | niedrig | in der Design-Spec als „später“ markiert |
| 14 | **Folgen-Reihenfolge nach TVDB** (Anime, Specials) | 3 | 3 | mittel | in der ersten Spec vorgesehen, nie gebaut (E-51); braucht einen eigenen Schlüssel |
| 15 | **Eigene Untertitel-Quelle** (Suche nach Hash und Name bei einem Untertitel-Dienst, wenn das Addon nichts liefert) | 3 | 3 | mittel | neuer Dienst, neuer Schlüssel; nur über `HTTPClient` |
| 16 | **Bild-im-Bild-Vorschau beim Blättern in der Quellenliste** | 2 | 4 | hoch | zweite Engine-Sitzung, Speicher und Debrid-Limits; eher nicht |
| 17 | **Fernsteuerung über die Handy-Seite** (Titel suchen und auf dem Fernseher öffnen) | 3 | 3 | hoch | widerspricht dem Bedrohungsmodell, solange die Handy-Seite über HTTP läuft; frühestens nach Stufe 3 von ADR-5 |
| 18 | **iCloud-Abgleich der Profile zwischen zwei Apple TVs** | 3 | 5 | hoch | bisher Nicht-Ziel („erst nur zu Hause“); braucht ein Entwicklerkonto und ein anderes Persistenzmodell |

**Empfehlung für die erste Runde nach dem Plan:** 1 (Top Shelf), 4 (Quellen-Vorlieben), 3 und 7 (kleine
Player-Komfortpunkte) sowie 12 (zugesagte MDBList-Listen). Sie bringen viel, bauen auf vorhandener Logik in
`PlayerCore` auf und öffnen keine neue Angriffsfläche.
