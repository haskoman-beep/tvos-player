# 02 · Bugs

Stand: Branch `integ`, Commit `b2188a2` (Build 249). Rein lesend und statisch erhoben; Laufzeitverhalten ist aus dem Code **abgeleitet**. Alle `Datei:Zeile`-Angaben beziehen sich auf diesen Commit.

Methodik: `superpowers:systematic-debugging` (Hypothese → Beleg im Code → Ursache statt Symptom), dazu ein
Code-Review über den gesamten Code. Vier Bereiche wurden mit gleicher Gründlichkeit von insgesamt sieben Agenten
untersucht. **Jeder Kandidat wurde danach von einem zweiten Agenten adversarial gegengeprüft** (Ist das Szenario
erreichbar? Stimmt die Zeile? Gibt es einen Guard, einen Test oder einen Kommentar, der das Verhalten als gewollt
festschreibt?). Nur bestandene Befunde stehen hier, mit dem Schweregrad und der Sicherheit **nach** der Gegenprüfung.

Lesehilfe: „bestätigt“ heißt, der Codepfad ist lückenlos belegt. „plausibel“ heißt, der Pfad ist belegt, aber ein
Glied hängt an Verhalten außerhalb des Repos (Fokus-Engine, AetherEngine, fremder Dienst) und gehört an das Gerät.

## Übersicht

| Bereich | kritisch | hoch | mittel | niedrig | Summe |
|---|---:|---:|---:|---:|---:|
| Wiedergabe | 0 | 2 | 5 | 14 | 21 |
| Fokus & Navigation | 0 | 1 | 7 | 12 | 20 |
| Sync & Profile | 0 | 0 | 8 | 7 | 15 |
| Addons & Startseite | 0 | 1 | 11 | 12 | 24 |
| **Summe** | 0 | 4 | 31 | 45 | **80** |

Es gibt keinen kritischen Befund. Von 93 Kandidaten haben 80 die Gegenprüfung bestanden, 13 wurden verworfen;
bei mehr als 20 wurde der Schweregrad oder die Sicherheit herabgesetzt.

Die vier Befunde mit Schweregrad „hoch“:

- A-B-1: Sicherung einspielen (anderes Gerät, Neuinstallation) löscht alle Fusion-Kit-Reihen von der Startseite
- F-B-1: Quellenliste lädt nach dem Player die Quellen der Start-Folge, obwohl schon die nächste läuft
- W-A-1: Fehler beim ersten Laden – die Fehlerleiter lädt nur neu, die Startlogik läuft nie
- W-B-1: Fortschritt überschreibt „nächste Folge“ und „gesehen“ ab der ersten Sekunde

Sicherheitsbefunde stehen in [06-security-review.md](06-security-review.md), Qualitätsbefunde in [05-code-review.md](05-code-review.md).

---

## Schweregrad: kritisch

Keine Befunde.

---

## Schweregrad: hoch

### A-B-1: Sicherung einspielen (anderes Gerät, Neuinstallation) löscht alle Fusion-Kit-Reihen von der Startseite
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Import/FusionKitCatalog.swift:189`, `Packages/PlayerCore/Sources/PlayerCore/Import/FusionKitCatalog.swift:210`, `App/Sources/FusionKitStore.swift:221`, `App/Sources/FusionKitStore.swift:405`, `App/Sources/AppModel.swift:590`
- **Szenario:** Ein Profil mit Kit-Reihen (Listen und Kit-Collections mit IDs `fusion.…`) wird als Sicherung exportiert und auf einem zweiten Apple TV oder nach einer Neuinstallation über die Handy-Seite eingespielt. Die Sicherung enthält das Layout mit den Kit-Reihen, aber nicht die Kit-Auswahl (die liegt je Profil in UserDefaults). Unmittelbar nach dem Einspielen entfernt der Abgleich jede Kit-Reihe aus dem Layout und speichert das gekürzte Profil. Position und Stil der Reihen sind weg, ohne Meldung an den Nutzer (nur Logzeile „kit Startseite: +0 −n Reihen“). Ein erneutes Einspielen derselben Sicherung führt zum selben Ergebnis.
- **Ursache:** `importBackup` setzt `stored`; die Beobachtung von `$stored` (`FusionKitStore.swift:51`) ruft `sync()`. `ensureSettings()` sieht eine neue Profil-ID, findet unter `fusionkit.<uuid>` nichts und nimmt `FusionKitSettings()` (aus, nichts gewählt). In `FusionKitSync.apply` bleiben `want` und `unknown` leer, weil beide nur bei `settings.enabled` gefüllt werden; jede Kit-Reihe fällt in den Entfernen-Zweig:
  ```swift
  } else if unknown.contains(id) { rows.append(row) }
  else { res.removed.append(id) }
  ```
  Danach schreibt `sync()` das Layout zurück (`model.update { $0.home = layout }`).
- **Schweregrad:** hoch · **Sicherheit:** bestätigt
- **Fix-Idee:** Kit-Einstellungen (und die Link-Liste der Collection-Importe) in die Sicherung aufnehmen, oder bei fehlendem Einstellungs-Eintrag die im Layout vorhandenen Kit-Reihen als gewählt übernehmen (Quelle aus der ID, `enabled = true`) statt sie zu entfernen.
- **Test:** PlayerCore: `FusionKitSync.apply` mit einem Layout voller Kit-Reihen und `FusionKitSettings()` liefert heute `removed == alle`; ein neuer Test für den Wiederherstellungsfall verlangt ein unverändertes Layout. Am Gerät: Sicherung auf frischer Installation einspielen, Fern-Log „kit Startseite: … −n Reihen“.
- **Gegenprüfung:** Pfad Zeile für Zeile nachvollzogen. Es gibt keinen Guard, der den Fall abfängt: `ensureSettings()` (`FusionKitStore.swift:216`–`227`) kennt keinen Zustand „Einstellungen fehlen“, und `ProfileStore.exportData` kodiert nur `StoredProfiles`. Der Test `fusionSyncAddsKeepsAndRemoves` (`Packages/PlayerCore/Tests/PlayerCoreTests/FusionKitTests.swift:198`–`201`) schreibt „Kit aus → alle Kit-Reihen weg“ ausdrücklich fest; das ist für das Ausschalten gewollt, der Wiederherstellungsfall ist nirgends bedacht. Einschränkung: Auf demselben Gerät mit erhaltenen UserDefaults (gleiche Profil-ID) tritt der Fehler nicht auf. Eingefügte Widget-Exporte (`paste:`) fehlen in der Sicherung ohnehin. Zeilen gegenüber dem Erstbericht präzisiert (210 statt 201, 221 statt 216, 590 statt 587). „hoch“ bleibt: stiller, dauerhafter Verlust in genau dem Fall, für den die Sicherung laut Spec gedacht ist (`docs/superpowers/specs/2026-11-21-tvos-player-design.md:144`); die Reihen lassen sich allerdings von Hand neu wählen.

### F-B-1: Quellenliste lädt nach dem Player die Quellen der Start-Folge, obwohl schon die nächste läuft
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/DetailViews.swift:841`, `App/Sources/Views/DetailViews.swift:1140`, `App/Sources/Views/DetailViews.swift:1142`, `App/Sources/Views/DetailViews.swift:919`, `App/Sources/Views/DetailViews.swift:795`
- **Szenario:** Serie, S1E1 aus der Quellenliste gestartet, „Nächste Folge automatisch“ an. E1 endet, `startNext` setzt `current = E2` und `streams =` Quellen von E2, E2 läuft. Der Nutzer schließt den Player während E2 (z. B. weil die Quelle ruckelt) und will eine andere Quelle wählen. Der Kopf zeigt „… S1E2“, die Zeilen sind wieder die Quellen von E1. Ein Druck auf eine Zeile spielt die Datei von E1, der Player bekommt aber `request: current ?? request` = E2: Fortschritt, „gesehen“, Scrobble und gemerkte letzte Quelle landen auf E2.
- **Ursache:** Die Lade-Aufgabe der Liste benutzt immer die ID der Route, nie die laufende Folge, und weist ohne Prüfung zu:
  ```swift
  streams = model.orderedStreams(autostart ? await model.streamsForAutoplay(type: request.type, id: request.id)
      : await model.streams(type: request.type, id: request.id))
  ```
  Kopf, Statuszeile, Player, Fehlergedächtnis und `rememberSource` benutzen dagegen `current ?? request` (Zeilen 758, 795, 799, 915, 919, 924). Die Nachbarstellen derselben Aufgabe sind gegen `current` abgesichert (836, 848, 888, 892), Zeile 841 nicht. Zweiter Weg ohne Schließen von Hand: nach dem Ende von E1 läuft die Aufgabe neu; ist der Cache von E1 abgelaufen, sucht sie neu, `model.streams` beachtet den Abbruch nicht (`App/Sources/AppModel.swift:514`, wartet auf eine freie `Task`), und ihr Ergebnis überschreibt die in Zeile 1142 gesetzte E2-Liste, während E2 schon spielt. Dann findet `fallback` die laufende Quelle nicht (`DetailViews.swift:1083`) und meldet „Bitte eine andere Quelle wählen“ statt zu wechseln.
- **Schweregrad:** hoch · **Sicherheit:** plausibel
- **Fix-Idee:** In der Aufgabe nur beim ersten Lauf laden (`guard current == nil || streams.isEmpty`) bzw. `let r = current ?? request` verwenden und nach dem `await` `Task.isCancelled` prüfen, bevor `streams` gesetzt wird.
- **Test:** Am Gerät: E1 auslaufen lassen, E2 startet, Player schließen; im Fern-Log folgt auf das Schließen eine `streams`-Zeile mit der ID von E1 (Cache-Treffer oder neue Suche), Kopf und Zeilen vergleichen.
- **Gegenprüfung:** Datenfluss Zeile für Zeile nachvollzogen: `PlayerScreen` kennt nur `request` (`PlayerScreen.swift:13`, `PlayerScreen.swift:486`–`490` ruft `onEnded(true)`), die neue Folge entsteht allein in `ended`/`startNext` (`DetailViews.swift:1105`, `1140`–`1142`); zurück in die Liste fließt sie nur über `current` und die einmalige Zuweisung in 1142. Der CHANGELOG-Eintrag „After automatically advancing to the next episode, the source list is correct“ (`CHANGELOG.md:456`) ist Commit c78bde4: er hat genau die Zuweisung in `startNext` eingeführt (plus `failed`/`fallbacks` zurücksetzen) und die Lade-Aufgabe nicht angefasst; der Fall hier ist dadurch nicht behoben. Einzige nicht aus dem Code beweisbare Annahme ist, dass `.task` nach dem Schließen des `fullScreenCover` neu läuft. Dafür spricht mehr als der Kommentar in Zeile 701: Commit 71d43fc hat `autostartDone` genau deswegen eingeführt, und `CHANGELOG.md:298` nennt das am Gerät sichtbare Symptom („Closing the player no longer starts the best choice again by itself“). Zeilenangaben des Erstberichts stimmen (843 ist die Fortsetzung von 841; 701 ist nur der Kommentar). Schweregrad bleibt hoch: Kernfunktion (Quelle wechseln bei laufender Serie) liefert falschen Inhalt und verbucht Fortschritt auf der falschen Folge.

### W-A-1: Fehler beim ersten Laden – die Fehlerleiter lädt nur neu, die Startlogik läuft nie
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:444-451`, `App/Sources/Views/PlayerScreen.swift:371-375`, `App/Sources/Views/PlayerScreen.swift:690-691`, `App/Sources/Views/PlayerScreen.swift:733-802`
- **Szenario:** Plattencache aus (Standard). Der erste `engine.load` scheitert mit einem Fehler, den die Leiter repariert: abgelaufener Link (403/404/410 → `.linkExpired` → `.reresolve`), kurzer Netzfehler oder unbekannter Fehler (`.retrySame`). Der zweite Versuch klappt, der Film läuft. Es fehlen aber für die ganze Wiedergabe: die Tonwahl der App (Spur-Gedächtnis, Dolby-Digital-Vorzug), die Untertitel-Automatik (auch erzwungene Untertitel), gemerkte Untertitel samt Versatz und die Platzhalter-Prüfung. Ein Platzhalter-Clip würde abgespielt, am Ende als gesehen gemeldet (`PlayerScreen.swift:384`) und die nächste Folge gestartet.
- **Ursache:** Ob der ganze Start wiederholt wird, hängt an `stab.loadInFlight || stab.startPending` (Zeile 690). Der `catch` in `loadAndStart` setzt `loadInFlight` zurück (Zeile 447), bevor `onChange(of: engine.errorText)` `recover` ruft. Dann ist `startAborted` false und es läuft der Zweig „an der Stelle neu laden“ (ab Zeile 733), der nur lädt und `playUnlessHeld()` ruft.
  ```swift
  stabilityLoadEnded()                                          // catch, Zeile 447
  let startAborted = stab.loadInFlight || stab.startPending     // recover, Zeile 690 → false
  ```
- **Schweregrad:** hoch · **Sicherheit:** plausibel (der App-Pfad ist lückenlos belegt; dass der `catch` vor `onChange` läuft, folgt aus dem Zusammenspiel mit der Engine und ist nicht am Gerät gesehen)
- **Fix-Idee:** Einen eigenen Zustand „Start noch nie abgeschlossen“ führen, der erst hinter der Platzhalter-Prüfung und der Spurwahl gelöscht wird, und in `recover` darauf prüfen statt auf `loadInFlight`; der `catch` darf ihn nicht löschen.
- **Test:** Die Entscheidung „ganzen Start wiederholen?“ als reine Funktion nach PlayerCore ziehen und den Fall „Fehler nach beendetem `load`, vor erstem Abschluss“ testen; im Fern-Log folgt auf „Laden fehlgeschlagen“ ein „Fehler eingeordnet … → reresolve/retrySame“ und danach nie „Geladen ·“ oder „Spielt ·“, obwohl der Film läuft.
- **Gegenprüfung:** Der Ablauf nach einem reparierten Erst-Ladefehler, Zeile für Zeile:
  1. `engine.load` wirft (Zeile 419). Der `catch` (444-451) ist nicht abgebrochen, ruft `stabilityLoadEnded()` und setzt `loadError`. `loadAndStart` ist damit zu Ende; Zeilen 423-443 (Platzhalter, Tonwahl, `subtitlePreferences`, gemerkte Untertitel, Addon-Untertitel) liefen nicht.
  2. `onChange(of: engine.errorText)` (371-375) ruft `recover`. Dort ist `startAborted` false, `stabilityResumes(false)` liefert false (`PlayerStability.swift:71-77`), also kein `loadAndStart`.
  3. Im Neuladen-Zweig: `pos = start ?? 0` (737), `engine.recover()` bzw. `engine.load(fresh.url, …)` (757-782), dann nur die Untertitel-Wiederwahl mit der vorigen Wahl (nil), `loadAddonSubtitles` (799) und `playUnlessHeld()` (801).
  4. Nachgeholt wird nichts: `isPlaceholderVideo` hat genau einen Aufrufer (`PlayerScreen.swift:423`), `engine.subtitlePreferences` wird nur in Zeile 438 gesetzt, `preferredAudioTrack`/`rememberedAudio` nur in Zeile 432. `loadAddonSubtitles` läuft zwar, aber `reconsiderSubtitles` bricht ohne `subtitlePreferences` sofort ab (`App/Sources/Playback/PlaybackEngine.swift:254-255`), und `applyPendingSubtitleMemory` braucht `subtitleMemoryPending`, das nur `applyRememberedSubtitles` setzt (`App/Sources/Views/Player/PlayerPictureSound.swift:85-110`).
  5. Es gibt keinen Test für diese Entscheidung (sie liegt im View). Der Kommentar in Zeile 736 („Vor dem ersten Bild (Fehler beim Start) gilt die gewünschte Startstelle“) zeigt, dass Startfehler diesen Zweig erreichen sollen – die Folge für die Startlogik ist dort nicht bedacht.
  6. Wann der Befund nicht greift: mit Plattencache-Sitzung wartet `AetherBackend.load` nach dem Fehler auf `giveUp` (`PlaybackEngine.swift:221-225`); in dieser Pause kann `onChange` bei noch gesetztem `loadInFlight` laufen, dann wird der Start richtig wiederholt. Ebenso beim Lade-Wächter (Fehler kommt, während `load` noch hängt).
  7. Offen bleibt allein die Reihenfolge „`catch` vor `onChange`“. Sie ist sehr wahrscheinlich (beides läuft auf dem Main-Actor, SwiftUI meldet Änderungen erst nach dem laufenden Schritt), hängt aber davon ab, dass die Engine den Fehlerzustand nicht deutlich vor dem Werfen veröffentlicht. Deshalb „plausibel“. Der Schweregrad bleibt hoch: Ein abgelaufener Link fällt am ehesten beim Start auf, also genau dort, wo die Stufe `.reresolve` am häufigsten greift.

### W-B-1: Fortschritt überschreibt „nächste Folge“ und „gesehen“ ab der ersten Sekunde
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:53`, `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:79`, `App/Sources/AppModel.swift:73`, `App/Sources/Views/PlayerScreen.swift:337`, `App/Sources/Views/PlayerScreen.swift:821`
- **Szenario:** (a) Folge 2 läuft zu Ende, Up-next startet Folge 3 (Eintrag `nextUp: true`, Serie steht in Weiterschauen). Der 10-s-Takt speichert, der Nutzer beendet bei 0:40. Der Eintrag von Folge 3 hat jetzt Position 40 s und `nextUp == nil`, Folge 2 ist `finished`. `continueWatching()` verlangt `position >= 60 || nextUp == true || remoteFraction > 0` → die Serie verschwindet aus Weiterschauen. „Abspielen“ auf der Detailseite findet Folge 3 weiterhin. (b) Ein gesehener Film wird geöffnet und nach 15 s verlassen → `finished` ist wieder `false`, Position 15 s: Häkchen weg, Eintrag aus dem Verlauf weg. (c) Gleiches Muster für einen Eintrag mit `remoteFraction` aus Trakt/Simkl: die erste gespeicherte Sekunde löscht den Anteil.
- **Ursache:** `record` ersetzt den Eintrag immer vollständig, ohne Mindestposition und ohne `nextUp`, `finished` oder `remoteFraction` zu erhalten. `recordNextUp` schützt echten Fortschritt, die Gegenrichtung fehlt:
  `entries[id] = WatchProgress(id: id, …, position: done ? 0 : position, duration: duration, updated: now, finished: done)`
- **Schweregrad:** hoch · **Sicherheit:** bestätigt
- **Fix-Idee:** In `record` unterhalb von `minimumSeconds` ein vorhandenes `nextUp`, `finished` bzw. `remoteFraction` behalten (nur `updated`/`duration` anfassen) oder solche Positionen gar nicht speichern.
- **Test:** PlayerCore: `recordNextUp` → `record(position: 40)` → `continueWatching()` muss die Serie noch enthalten; `record` mit 100 % → `record(position: 15)` → `isWatched` bleibt `true`.
- **Gegenprüfung:** Weg Takt/Ausstieg → `saveProgress` → `recordProgress` → `record` lückenlos gelesen; kein Guard, keine andere Stelle setzt `nextUp` neu, der Abgleich holt nur Angefangenes (und läge mit 40 s ebenfalls unter der Schwelle), kein Test schreibt das Überschreiben fest (`P2Tests` prüft nur die Richtung `recordNextUp` nach echtem Fortschritt).

---

## Schweregrad: mittel

### A-A-1: „UHD“ im Namen macht aus einem 1080p-Encode eine 4K-Quelle
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:36`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:37`
- **Szenario:** Dateiname `Film.2021.1080p.UHD.BluRay.DDP7.1.DoVi.x265-GRP.mkv` (1080p-Encode von der UHD-Scheibe). Nachgerechnet: `2160P` kein Treffer, `4K` kein Treffer, `UHD` steht zwischen zwei Punkten → `containsToken` wahr → `resolution = "2160p"`; `1080P` wird wegen `t.resolution == nil` nicht mehr geprüft. Folge: Plakette „4K“ in der Liste, bestes Ergebnis für Poster und Detailseite, Filter und automatische Wahl rechnen mit 4K.
- **Ursache:** Markenwörter stehen in der Prüfreihenfolge vor der ausdrücklichen Auflösung; der erste Treffer gewinnt.
  ```swift
  for (key, label) in [("2160P", "2160p"), ("4K", "2160p"), ("UHD", "2160p"), ("1440P", "1440p"), ("1080P", "1080p"), …
  where t.resolution == nil && containsToken(up, key) { t.resolution = label }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Zuerst ausdrückliche `\d{3,4}P`-Angaben auswerten, „4K“/„UHD“ nur als Rückfall ohne Zahl-Auflösung.
- **Test:** PlayerCore-Test `StreamTraits.parse(StreamItem(description: "X.1080p.UHD.BluRay.x265"))` erwartet `1080p`.
- **Gegenprüfung:** Die vorhandenen Tests enthalten „UHD“ nur zusammen mit „2160p“ (`RatingsTests.swift:48`, `SourceFilterTests.swift:93`); nichts schreibt das Fehlverhalten als gewollt fest.

### A-A-2: Dateigröße „5.1 GB“ / „7.1 GB“ / „2.0 GB“ wird als Tonkanäle gelesen
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:53`
- **Szenario:** Beschreibung `…DDP5.1…\n📦 7.1 GB`. Nachgerechnet: die Schleife prüft `7.1` zuerst; in „ 7.1 GB“ steht davor und dahinter ein Leerzeichen → `containsToken` wahr → `channels = "7.1"`. Ebenso Stereo-Quelle mit `💾 5.1 GB` → „5.1“. Weil das beste Ergebnis einer Liste die höchste vorkommende Kanalzahl nimmt (`Ranking/QualityBadges.swift:141`), genügt eine einzige solche Quelle in einer langen Liste für eine falsche „7.1“-Plakette auf Poster und Detailseite; die automatische Wahl bevorzugt die Quelle als Mehrkanal (`Ranking/BestChoice.swift:60`).
- **Ursache:** `containsToken` verlangt nur, dass kein Buchstabe und keine Ziffer angrenzt; eine folgende Größeneinheit wird nicht ausgeschlossen.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (tritt nur bei genau diesen Größen auf)
- **Fix-Idee:** Treffer verwerfen, wenn danach (nach optionalem Leerraum) `GB|MB|TB|GiB|Mbps` folgt, oder Größenangaben vor der Kanal-Erkennung aus dem Text entfernen.
- **Test:** PlayerCore-Test mit `description: "Film.1080p.AAC2.0 💾 5.1 GB"` erwartet `channels == "2.0"`.
- **Gegenprüfung:** Kein Test mit einer Größe „5.1/7.1/2.0 GB“; der Kommentar am Release-Muster (`StreamTraits.swift:113`) kennt das Problem nur für den Cache-Status, nicht für Kanäle.

### A-A-3: `parseSize` kann mit Addon-Text abstürzen (Double → Int64 außerhalb des Bereichs)
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:147`, Aufruf `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:68`
- **Szenario:** Eine Quelle ohne (oder mit verworfenem) `behaviorHints.videoSize`, deren Name, Titel, Beschreibung oder Dateiname eine lange Ziffernfolge direkt oder nur durch Leerraum getrennt vor `TB`, `GB` oder `MB` enthält, z. B. `…20231115123456 TB⚡`. Sobald `n * mult` ≥ 2^63 ist (vor „TB“ ab 9 223 373, also 7 Ziffern; vor „GB“ ab 10 Ziffern; vor „MB“ ab 13 Ziffern), bricht `Int64(…)` das Programm ab. `StreamTraits.parse` läuft für jede Quelle beim Ablegen im Cache und für Plaketten, also auch beim stillen Vorladen.
- **Ursache:** Ungeprüfte Umwandlung; das strukturierte Feld ist dagegen abgesichert (`StremioModels.swift:421`, `isFinite && < 9e18`), der Text-Rückfall nicht.
  ```swift
  let mult: Double = switch up[ur] { case "TB": 1e12; case "GB": 1e9; default: 1e6 }
  return Int64(n * mult)
  ```
- **Schweregrad:** mittel (Absturz durch Fremddaten, seltene Eingabe) · **Sicherheit:** bestätigt (Mechanismus); Auftreten in echten Listen plausibel
- **Fix-Idee:** Wie bei `videoSize` begrenzen (`isFinite`, `< 9e18`, sonst nil) und nur plausible Größen (z. B. < 1 PB) annehmen.
- **Test:** PlayerCore-Test `StreamTraits.parseSize("X 99999999999999 TB")` darf nicht abbrechen und liefert nil.
- **Gegenprüfung:** Kein Guard vor Zeile 147 und kein Test für `parseSize`; `??` wertet den Rückfall nur ohne `videoSize` aus, dann aber ungeschützt.

### A-A-4: Ein Titel ohne Quellen pausiert Vorladen und Hintergrund-Erneuerung (bis zu 5 Minuten oder bis zur nächsten Suche mit Treffern)
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel.swift:508`, `App/Sources/AppModel.swift:685`, `App/Sources/StreamPrefetcher.swift:161`, `Packages/PlayerCore/Sources/PlayerCore/Store/RevalidationPolicy.swift:41`, `App/Sources/AppModel+StreamRevalidate.swift:19`, `App/Sources/AppModel+StreamRevalidate.swift:50`, `App/Sources/StreamPrefetcher.swift:259`
- **Szenario:** Auf der Startseite steht eine Reihe mit noch nicht erschienenen oder seltenen Titeln. Das Vorladen sichtbarer Kacheln fragt einen davon ab, alle Addons antworten korrekt mit einer leeren Liste → `streamsAllEmptyAt = Date()`. Ab jetzt kein Fokus-Vorladen, kein Vorladen sichtbarer Kacheln (keine neuen Poster-Plaketten), keine Erneuerung veralteter Stände, und `streamsForAutoplay` (Weiterschauen, nächste Folge) startet aus dem bis zu 30 min alten Stand. Die Pause endet nach 300 s oder früher, sobald irgendeine Suche Treffer ablegt (`storeStreams` setzt `streamsAllEmptyAt = nil`): etwa eine noch laufende Parallel-Abfrage oder eine vom Nutzer geöffnete Detailseite. Läuft das Vorladen im Takt des Minuten-Budgets (meist eine Abfrage zur Zeit), bleibt die Pause stehen. Nach Ablauf plant nichts von selbst einen neuen Durchlauf der sichtbaren Kacheln, bis sich eine Kachel ändert. Derselbe Effekt, wenn kein Addon Typ/ID bedient (`all` leer, `allSatisfy` wahr).
- **Ursache:** Die Regel „alle Addons leer = vermutlich Ratenbegrenzung“ unterscheidet nicht zwischen „keine Quellen für diesen Titel“ und einem Ausfall.
  ```swift
  if !profile.addons.isEmpty, all.allSatisfy({ $0.streams.isEmpty }) { streamsAllEmptyAt = Date() }
  ```
- **Schweregrad:** mittel · **Sicherheit:** plausibel (die Regel und ihre Pausen sind bewusst so gebaut und kommentiert; die Fehlauslösung durch einen einzelnen quellenlosen Titel ist abgeleitet und hängt davon ab, ob die Addons dann wirklich eine leere Liste schicken)
- **Fix-Idee:** Pause nur setzen, wenn mindestens ein gefragtes Addon fehlschlug oder mehrere verschiedene Titel hintereinander leer blieben, und nicht, wenn kein Addon gefragt wurde; `streamsForAutoplay` von der Pause ausnehmen.
- **Test:** Fern-Log: nach einer Zeile mit `=0` für alle Addons prüfen, ob die Zeilen `prefetch →` und `Vorab-Quellen:` ausbleiben; die Regel nach PlayerCore ziehen und mit „1 Titel leer, Addons in Ordnung“ testen.
- **Gegenprüfung:** Korrigiert: der Erstbericht nannte feste 5 Minuten; tatsächlich hebt jeder abgelegte Treffer die Pause auf (`AppModel.swift:685`). Die Pause selbst ist dokumentierte Absicht (`AppModel.swift:506`–`507`, `StreamPrefetcher.swift:8`–`12`), bestanden hat nur die Fehlauslösung.

### A-A-5: „Frisch fragen“ kann eine Antwort aus dem HTTP-Cache liefern (Neuauflösen eines abgelaufenen Links, Erneuerung)
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:14`, `App/Sources/AppModel+Reresolve.swift:16`, `App/Sources/AppModel+StreamRevalidate.swift:35`
- **Szenario:** Wiedergabe scheitert an einem abgelaufenen Debrid-Link, der Player ruft `freshStream(for:)`. Die Anfrage geht über `URLSession.shared.data(from:)` mit der Standard-Cache-Regel. Schickt das Addon Cache-Kopfzeilen (`Cache-Control: max-age=…`), kann dieselbe gespeicherte Antwort mit demselben toten Link zurückkommen → Log „frischer Link“, Wiedergabe scheitert erneut. Gleiches gilt für `streams(revalidate: true)`: der „erneuerte“ Stand kann der alte sein, mit neuem Zeitstempel.
- **Ursache:** Der eigene Quellen-Cache wird umgangen, der `URLCache` der gemeinsamen Sitzung nicht; an anderen Stellen setzt die App bewusst `.reloadIgnoringLocalCacheData` (`App/Sources/AppUpdater.swift:185`, `App/Sources/Playback/DiskCacheProxy.swift:82`).
- **Schweregrad:** mittel · **Sicherheit:** plausibel (hängt von den Antwort-Kopfzeilen der eingerichteten Addons ab; nur am Gerät klärbar)
- **Fix-Idee:** Eigene `URLSession` für Addons mit `requestCachePolicy = .reloadIgnoringLocalCacheData`, mindestens für `stream`-Anfragen.
- **Test:** Gerät/Fern-Log: zwei Suchen desselben Titels im Abstand von über 90 s, Antwortzeit je Addon vergleichen (wenige ms deuten auf den HTTP-Cache); in PlayerCore nicht testbar, weil der Transport dort gefälscht ist.
- **Gegenprüfung:** Im Addon-Pfad gibt es keine Cache-Regel (Suche nach `cachePolicy`/`URLCache` ergab nur Update-Prüfung, Platten-Proxy und Bildlader); ob es wirkt, bleibt offen.

### A-A-6: Technik-Plaketten, „Sofort abspielen“ und Vorlade-Plätze warten auf das langsamste Addon
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/Views/DetailViews.swift:212`, `App/Sources/Views/DetailViews.swift:213`, `App/Sources/AppModel.swift:499`, `App/Sources/AppModel.swift:514`, `App/Sources/StreamPrefetcher.swift:195`, `App/Sources/Views/QualityBadges.swift:115`
- **Szenario:** Zwei Addons, A antwortet nach 800 ms, B hängt. Die Film-Detailseite setzt `best` und die Wahl erst nach Rückkehr von `model.streams(...)`, also nach der Addon-Frist (Standard 15 s, Auswahl 8–45 s). So lange keine Technik-Plakette und keine Karte „Sofort abspielen“, obwohl alle späteren Quellen von A schon da sind. Poster-Plaketten kommen erst mit `storeStreams` → `streamsStored`, und ein hängendes Addon hält jeden der 2 Fokus- bzw. 4 Kachel-Plätze die volle Frist besetzt.
- **Ursache:** Zwischenstände gibt es nur über `StreamSearchStatus` für die Quellenliste; Detailseite, Plaketten-Cache und Vorlader nutzen ausschließlich das Endergebnis.
- **Schweregrad:** mittel (Wartezeit, kein falsches Ergebnis) · **Sicherheit:** bestätigt
- **Fix-Idee:** Auf der Detailseite `StreamSearchStatus.progress[id]` beobachten und `best`/Wahl aus dem Zwischenstand bilden; optional den Zwischenstand nach dem ersten Addon vorläufig in den Plaketten-Cache melden.
- **Test:** Fern-Log: `Plaketten nach … ms` gegen die Zeile `Addon-Status A=… (800 ms), B=Zeitüberschreitung` halten.
- **Gegenprüfung:** Reiner Leistungsbefund; mit nur einem Addon oder ohne hängendes Addon ohne Wirkung. Siehe auch Performance-Tabelle.

### A-A-7: Quellenliste zeigt bereits eingetroffene Treffer nicht, wenn sie einer laufenden Suche beitritt
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel+StreamSearch.swift:113`, `App/Sources/Views/DetailViews.swift:836`, `App/Sources/Views/DetailViews.swift:841`
- **Szenario:** Die Film-Detailseite (oder das Vorladen) hat die Suche gestartet, Addon A ist fertig, Addon B läuft noch. Der Nutzer öffnet die Quellenliste. `streams()` tritt der laufenden Aufgabe bei (`App/Sources/AppModel.swift:487`–`492`) und kehrt erst am Ende zurück. Der Zwischenstand wird nur in `onChange(of: finishedCount)` übernommen; das feuert nicht für den Wert, der beim Erscheinen schon gilt. Bei zwei Addons bleibt die Liste leer („lädt“), bis B fertig ist oder seine Frist abläuft, obwohl die Statuszeile die Treffer von A meldet.
- **Ursache:** Keine Erstübernahme des vorhandenen Zwischenstands.
  ```swift
  content.onChange(of: search.progress[id]?.finishedCount ?? 0) { _, _ in
      guard loading else { return }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (abgeleitet; `onChange` ohne `initial: true` meldet den Anfangswert nicht)
- **Fix-Idee:** `onChange(…, initial: true)` oder zu Beginn der `.task` der Liste einmal `StreamSearchStatus.shared.partial(id)` übernehmen, solange `loading`.
- **Test:** Gerät mit zwei Addons, eines künstlich langsam: Detailseite öffnen, nach 2 s die Quellenliste öffnen; im Fern-Log `wartet auf laufende Abfrage` gegen den Zeitpunkt der ersten Zeile halten.
- **Gegenprüfung:** `partial(` wird in der App nur an dieser einen Stelle gelesen; es gibt keinen zweiten Weg, der den Zwischenstand beim Erscheinen setzt. Mit nur einem Addon wirkungslos.

### A-A-9: Addons werden über ihren Anzeigenamen unterschieden – zwei gleichnamige Instanzen vermischen sich
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel+StreamSearch.swift:41`, `App/Sources/AppModel+StreamSearch.swift:51`, `App/Sources/AppModel.swift:509`, `App/Sources/AppModel.swift:511`, `App/Sources/AppModel+Reresolve.swift:12`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamListDisplay.swift:57`
- **Szenario:** Zwei Instanzen desselben Aggregators mit gleichem `manifest.name` (unterschiedliche Manifest-Adresse; `installAddon` verhindert nur gleiche Adressen, `App/Sources/AppModel.swift:291`). (1) Instanz 1 läuft in die Zeitüberschreitung, Instanz 2 antwortet: `failed = gefragte Namen − beantwortete Namen` ist leer → Ergebnis gilt als vollständig (90 s frisch, kein Nachziehen, alte Einträge der ausgefallenen Instanz fallen weg). (2) Die gemerkte Quelle stammt von Instanz 2; `freshStream` fragt `profile.addons.first { name == last.addon }`, also Instanz 1 → „Datei nicht mehr da“, sofern Instanz 1 dieselbe Datei nicht auch führt. (3) Dubletten-Ausblendung und Zusammenführen arbeiten je Name, behandeln beide Instanzen also als ein Addon.
- **Ursache:** `(addon: String, stream:)` trägt überall `manifest.name` statt der eindeutigen Kennung `InstalledAddon.id` (Manifest-Adresse).
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (Logik); tritt nur bei gleichnamigen Instanzen auf
- **Fix-Idee:** Intern die Manifest-Adresse als Schlüssel führen und den Namen nur anzeigen; die gemerkte Quelle zusätzlich mit der Adresse ablegen.
- **Test:** PlayerCore: `StreamCacheUpdate.apply` mit `answered`/`failed` aus zwei gleichnamigen Addons; Gerät: Fern-Log `Neu auflösen bei …: Datei nicht mehr da` trotz vorhandener Quelle.
- **Gegenprüfung:** Kein Guard gegen doppelte Namen beim Installieren und kein Test mit zwei gleichnamigen Addons gefunden.

### A-A-12: TMDB-Texte bleiben nach Profil- oder Sprachwechsel in der alten Sprache
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel.swift:419`, `App/Sources/AppModel.swift:425`, `App/Sources/AppModel.swift:451`, `App/Sources/AppModel.swift:459`, `App/Sources/AppModel.swift:252`
- **Szenario:** Profil A (Deutsch) öffnet einen Titel, danach Wechsel auf Profil B (Englisch) oder Umstellen der Profilsprache (`App/Sources/Views/Settings/AppearanceSettings.swift:22`). `localized(imdb:)` liefert für denselben Titel sofort den Eintrag aus `localizedCache` – noch vor der Prüfung auf einen TMDB-Schlüssel –, also Titel, Text, Poster/Logo und Altersfreigabe in der alten Sprache; ebenso Folgennamen aus `seasonCache`. Hält bis zum Neustart. Beide Caches wachsen unbegrenzt.
- **Ursache:** Schlüssel ist nur die IMDb-ID (bzw. `imdb:staffel`), obwohl die Sprache je Profil gilt (`App/Sources/AppModel.swift:346`); `switchProfile` leert Katalog-, Quellen-, Hero- und Addon-Meta-Cache, diese beiden nicht.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Sprache in den Schlüssel aufnehmen oder beide Caches in `switchProfile` und beim Ändern der Sprache leeren; Größe begrenzen.
- **Test:** Gerät: Titel in Profil Deutsch öffnen, auf Profil Englisch wechseln, denselben Titel öffnen; im Fern-Log fehlt dann eine neue `tmdb`-Zeile.
- **Gegenprüfung:** `localizedCache` und `seasonCache` werden im gesamten App-Code nur an den genannten Zeilen gelesen und geschrieben, nirgends geleert.

### A-B-2: TMDB-Texte und Freigaben werden ohne Sprache und Profil gecacht und nie verworfen
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel.swift:419`, `App/Sources/AppModel.swift:425`, `App/Sources/AppModel.swift:451`, `App/Sources/AppModel.swift:458`, `App/Sources/AppModel.swift:252`, `App/Sources/AppModel.swift:360`, `App/Sources/Views/Settings/AppearanceSettings.swift:22`
- **Szenario:** (a) Profil A (Deutsch) öffnet einen Titel, danach Wechsel auf Profil B (Englisch): Detailseite und Hero zeigen für denselben Titel weiter deutschen Titel, Text, Logo und die deutsche Freigabe, bis die App neu startet. (b) „Sprache der App“ im selben Profil umstellen: schon geöffnete Titel und Staffeln bleiben in der alten Sprache; TMDB-Reihen der Startseite zeigen bis zu 24 h die alten Titel, und der Plattenstand in alter Sprache wird beim nächsten Start zuerst gezeigt.
- **Ursache:** `localizedCache` ist nur nach IMDb-ID, `seasonCache` nach `imdb:season` geschlüsselt; beide haben weder Ablauf noch Obergrenze und werden in `switchProfile` nicht geleert (dort werden Stream-Cache, `HeroDetailsCache` und `AddonMetaCache` geleert). Die Sprachwahl läuft über `model.binding(\.language)` → `update`, ohne `clearCatalogCache()`; der Katalog-Cache ist nach `source.id` geschlüsselt.
  ```swift
  if let c = localizedCache[imdb] { return c }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Schlüssel um `tmdb.language` erweitern (oder beide Caches bei Profil- und Sprachwechsel leeren) und beim Sprachwechsel `clearCatalogCache()` rufen; Obergrenze wie bei `AddonMetaCache`.
- **Test:** Am Gerät: Titel öffnen, Sprache umstellen, Titel erneut öffnen; im Fern-Log muss eine zweite Zeile „tmdb … · en-US · Titel …“ erscheinen. In PlayerCore testbar, wenn der Cache als kleiner Typ mit Sprachschlüssel herausgezogen wird.
- **Gegenprüfung:** Beide Caches werden im gesamten App-Code nur an den genannten Stellen gelesen und beschrieben, nirgends geleert. `clearCatalogCache()` hat sieben Aufrufer (Anmeldung, Addon, Schlüssel, Sicherung, Wartung), keiner hängt an der Sprache. Der Kalender-Cache zeigt, dass die Sprache als Schlüsselteil vorgesehen ist (`App/Sources/AppModel+Upcoming.swift:25`). „mittel“ passt: Randfall (zwei Profile mit verschiedener Sprache bzw. Sprachwechsel), dann aber bis zum Neustart sichtbar falsch.

### A-B-3: Jeder Bildfehler (auch „kein Netz“, Zeitüberschreitung) sperrt das Bild 5 min; eine sichtbare Kachel versucht es von selbst nicht erneut
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/ImagePipeline.swift:79`, `App/Sources/ImagePipeline.swift:91`, `App/Sources/ImagePipeline.swift:286`, `App/Sources/ImagePipeline.swift:445`, `App/Sources/Views/TilePosterImage.swift:28`
- **Szenario:** Das Netz fehlt kurz (Aufwachen, WLAN-Aussetzer) oder ein Bilddienst antwortet 15 s nicht. Alle Bilder, die nicht im Plattencache liegen, scheitern und werden 5 min als fehlgeschlagen gemerkt. Eine Kachel, die sichtbar bleibt, zeigt weiter Grau bzw. nur den Titel, auch wenn das Netz Sekunden später wieder da ist. Scrollt man die Kachel aus dem Bild und zurück oder kehrt von einer anderen Seite zurück, startet die Ladung neu, bekommt innerhalb der 5 min aber sofort wieder `nil`. Poster-Kacheln wechseln zusätzlich für die Lebenszeit der Kachel vom Addon-Poster auf das TMDB-Poster bzw. auf den Titel.
- **Ursache:** `fetch` unterscheidet nicht zwischen „Bild gibt es nicht“ (404, undekodierbar) und vorübergehenden Fehlern; `try?` verwirft die Fehlerart, danach gilt für alles dieselbe Sperre:
  ```swift
  guard let (data, resp) = try? await session.data(from: u), … else { … continue }
  …
  } else { failed[key] = Date() }
  ```
  `RemoteImage` lädt nur über `.task(id: LoadKey(url, target, blur))`; es gibt keinen Anlass „Netz wieder da“ oder „Sperre abgelaufen“. Die GIF-Ladung daneben trennt Abbruch von Fehlschlag (`ImagePipeline.swift:223`), der Standbild-Pfad nicht.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (Mechanik), plausibel (Häufigkeit)
- **Fix-Idee:** Nur HTTP-4xx und Dekodierfehler merken; `URLError` (offline, Zeitüberschreitung, Verbindung verloren) nicht merken und in `RemoteImage` nach kurzer Pause einmal neu versuchen (z. B. Zähler im `LoadKey`).
- **Test:** Am Gerät: Netz kurz trennen, Startseite scrollen, Netz verbinden; Kacheln bleiben grau, Fern-Log zeigt „bilder Kachelbild nicht geladen“. Die Fehlerklassifikation (dauerhaft/vorübergehend) ist als reine Funktion in PlayerCore testbar.
- **Gegenprüfung:** Korrigiert. Die Aussage „versucht es danach nie wieder“ des Erstberichts ist zu stark: `.task` läuft beim Wiedererscheinen einer Ansicht neu (Zelle im `LazyHStack` neu angelegt, Rückkehr von einer gepushten Seite), und `TilePosterImage` hält seine Fehlerliste nur in `@State`. Nach Ablauf der 5 min lädt eine wieder erscheinende Kachel also normal. Bestätigt bleibt: Solange die Kachel sichtbar ist, gibt es keinen neuen Versuch, und im Projekt reagiert keine Bildansicht auf Netz-Rückkehr (der einzige `NWPathMonitor` sitzt in `App/Sources/Playback/PlaybackStability.swift:40` und dient der Wiedergabe). Bereits geladene Bilder bleiben über `@State` und den Plattencache (`returnCacheDataElseLoad`) sichtbar; betroffen sind nur Bilder, die in der Störung erstmals angefordert werden. Ort 459 des Erstberichts durch 445 ergänzt (die Task-ID ist die Ursache).

### F-A-1: „Abspielen“ im Hero navigiert nach dem Warten ungeprüft (später Sprung in Quellenliste und Wiedergabe)
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/HomeHero.swift:340`, `App/Sources/Views/HomeHero.swift:343`, `App/Sources/Views/HomeHero.swift:351`, `App/Sources/Views/DetailViews.swift:840`, `App/Sources/Views/TorBoxFilesRow.swift:121`, `App/Sources/Views/TorBoxFilesRow.swift:129`
- **Szenario:** Fokus auf „Abspielen“, OK. `quickPlayRequest` wartet auf IMDb-ID und Metadaten (`AppModel.swift:629`). Der Knopf zeigt „Wird geladen …“, beide Knöpfe und die Reihen bleiben bedienbar. Drückt der Nutzer in dieser Zeit „Details“, öffnet eine Kachel oder wechselt den Tab, legt die Aufgabe nach der Antwort trotzdem `.streams(r)` auf den Start-Pfad. `r.resumeLastSource` ist immer `true`; die Quellenliste startet damit bei gemerkter Quelle selbst die Wiedergabe. Ergebnis: über der gerade geöffneten Seite erscheint ungefragt die Quellenliste bzw. der Player; nach einem Tab-Wechsel passiert das beim Zurückkehren auf Start. Das Fenster ist meist kurz, weil `HeroInfo.load` dieselben Metadaten für die gezeigte Folie schon lädt (`HomeHero.swift:232`, `:240`); lang wird es direkt nach einem Folienwechsel oder bei langsamer Addon-Antwort. Gleiches Muster bei TorBox: OK auf einer Datei, Menu (führt zum Start-Tab), danach setzt `play` `playing` in der nicht sichtbaren Bibliothek.
- **Ursache:** Ungebundene `Task` ohne Abbruch und ohne Prüfung, ob Seite und Fokus noch stimmen; `starting` verhindert nur den Doppelklick:
  ```swift
  Task { let r = await model.quickPlayRequest(for: m); starting = false
         … navigate(.streams(r)) }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (Hero-Codepfad); TorBox-Variante plausibel (ob ein Cover aus einem nicht sichtbaren Tab sofort oder erst beim Zurückkehren erscheint, entscheidet das System)
- **Fix-Idee:** Aufgabe speichern und bei Fokuswechsel aus der Knopfzeile, `onDisappear` und Tab-Wechsel abbrechen; vor `navigate` prüfen, dass der Start-Pfad leer ist und der Fokus noch auf „Abspielen“ liegt. TorBox analog (`resolving` beim Verschwinden verwerfen).
- **Test:** Am Gerät mit gedrosseltem Netz „Abspielen“, sofort „Details“; im Fern-Log folgt auf `→ detail …` ein `hero Abspielen … →` und `→ streams …`.
- **Gegenprüfung:** Kein Guard zwischen `await` und `navigate`, `push` hängt am Pfad-Binding und wirkt auch bei verdeckter Startseite; von „hoch“ auf „mittel“ gesenkt, weil eine Nutzeraktion im meist kurzen Ladefenster nötig ist.

### F-A-2: Kit-Collection-Reihe: Fokus auf Platzhalter hat beim Eintreffen der Kacheln kein Übergabeziel
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/RowViews.swift:45`, `App/Sources/Views/RowViews.swift:143`, `App/Sources/Views/RowViews.swift:136`, `App/Sources/Views/RowViews.swift:202`
- **Szenario:** Eine Fusion-Kit-Collection steht auf der Startseite, ihre Kit-Datei lädt noch (erster Abruf, nach Fehlschlag); die Reihe zeigt fokussierbare Platzhalter. Der Nutzer steht auf einem Platzhalter. Kommt die Datei, wechselt `content` vom Zweig `placeholders` auf den `Strip` mit `FolderTile`s (anderer `switch`-Zweig, neue Identität samt neuem horizontalem ScrollView): der fokussierte Knopf verschwindet, niemand setzt ein Ziel. Derselbe Fall nach OK auf der Statuskachel „Laden fehlgeschlagen – erneut versuchen“ einer Kit-Collection (`focusedPlaceholder = 0`, danach lädt die Datei).
- **Ursache:** Die Übergabe Platzhalter → fertige Reihe existiert nur für Listen-Reihen; die Aufgabe steigt für Collections sofort aus, ein Gegenstück für den Phasenwechsel `loading → tiles/failed/empty` (`CollectionRowPhase`) fehlt:
  ```swift
  guard case .list(let s) = row.content else { return }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (fehlende Übergabe), wohin der Fokus danach fällt plausibel
- **Fix-Idee:** `onChange` auf die Collection-Phase mit derselben Regel wie bei Listen: lag `focusedPlaceholder` an, im nächsten Runloop `focusedRoute` auf die Kachel an gleicher Stelle setzen (bzw. `focusedPlaceholder = 0` für die Statuskachel).
- **Test:** PlayerCore: `CollectionRowPhase` um `focusAfterLoad(placeholder:count:)` ergänzen und testen; am Gerät Kit-Datei verzögern und im Log die „Fokus“-Zeilen nach „Collection … Kacheln“ prüfen.
- **Gegenprüfung:** Kein anderer Mechanismus fängt den Fall ab (`defaultFocus` der Reihe greift nur bei einer neuen Fokussuche in die Reihe, `rememberedRoute` ist ohne früheren Besuch `nil`); dass für Listen eigens eine Übergabe gebaut wurde, stützt den Bedarf.

### F-A-3: Kontextmenü der Startseite: Ausblenden, Löschen und „Ganz nach oben“ setzen kein Fokusziel
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/HomeView.swift:88`, `App/Sources/Views/HomeView.swift:92`, `App/Sources/Views/HomeView.swift:174`, `App/Sources/Views/HomeView.swift:198`, `App/Sources/Views/Settings/SettingsKit.swift:356`
- **Szenario:** (a) Langer Druck auf eine Kachel, „Löschen …“ bzw. „Ausblenden …“, bestätigen. Die Rückfrage ist ein `fullScreenCover`, die Aktion läuft in `onDismiss`, also nachdem das System den Fokus auf die Kachel zurückgelegt hat. Dann entfernt `model.update` die Reihe: die fokussierte Kachel verschwindet ohne Ersatzziel. (b) „Ganz nach oben“ in einer weit unten liegenden Reihe: die Reihe wandert im `ForEach` an Index 0, der Scroll-Stand bleibt; je nach `LazyVStack` wird sie dort abgebaut (Fokus weg) oder die Seite springt ihr nach oben hinterher. Ohne ausdrückliche Hero-Reihe wird die verschobene Liste zusätzlich zur neuen Hero-Quelle (`Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:81`), die Folien laden neu. (c) „Reihe bearbeiten“, im Verwalter die Reihe löschen, Menu zurück: die zuvor fokussierte Kachel existiert nicht mehr.
- **Ursache:** `quick` wertet nur `Outcome.event` aus; das von `HomeManager` mitgelieferte Ziel `Outcome.focus` (`Packages/PlayerCore/Sources/PlayerCore/Models/HomeManager.swift:52`, im Verwalter über `set(…)` genutzt) wird verworfen:
  ```swift
  guard let e = action(&m).event else { return }
  model.update { $0.home = layout; $0.hiddenRows = hidden }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (kein Fokusziel), sichtbares Verhalten plausibel
- **Fix-Idee:** `Outcome.focus` auch auf der Startseite auswerten: nach Ausblenden/Löschen die nachrückende Reihe gezielt fokussieren (gemerkte bzw. erste Kachel), nach „Ganz nach oben“ bewusst entscheiden (an der Stelle bleiben oder nach oben scrollen und dort fokussieren).
- **Test:** `focusNear` ist in PlayerCore schon getestet; am Gerät je Aktion prüfen, wo der Fokus landet (Log „Oberer Rand fokussiert“ direkt nach „Reihe gelöscht … (Kontextmenü)“ belegt einen Sprung).
- **Gegenprüfung:** `quick` (`HomeView.swift:198`–`204`) enthält keinerlei Fokuszuweisung, und weder `HomeRowFocusMemory` noch `HomeTopEdgeWatch` setzen nach einer Layoutänderung ein Ziel.

### F-A-4: Hero-Quelle scheitert oder ist leer: Startseite wechselt das ganze Layout, Hero kommt erst beim nächsten Erscheinen zurück
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/HomeView.swift:28`, `App/Sources/Views/HomeView.swift:31`, `App/Sources/Views/HomeView.swift:71`, `App/Sources/Views/HomeView.swift:77`, `App/Sources/AppModel.swift:610`, `App/Sources/AppModel.swift:380`
- **Szenario:** Start ohne Katalog-Cache für die Hero-Reihe (erste Nutzung, neue Reihe, geleerter Cache), das Netz ist noch nicht da. Zuerst steht das Hero-Layout, „Abspielen“ holt sich den Startfokus. Die Ladung scheitert: `loadItems` liefert `CatalogLoad(items: [], failed: true)`, `heroItems` reicht nur `[]` weiter, `slides.loaded` wird `true`, `showsHero` kippt auf `false`. Der `Group`-Zweig wechselt, Knopfzeile und alle `HomeRowView`s werden neu aufgebaut, der Fokus ist weg. Die Quellreihe zeigt danach ihre Statuskachel; ein erfolgreicher Neuversuch dort bringt den Hero nicht zurück, weil der Schlüssel der Hero-Aufgabe weder `catalogStamp` noch einen Zähler enthält. Erst beim nächsten Erscheinen der Startseite (zurück von einer Detailseite) läuft die Aufgabe erneut, und das Layout kippt wieder auf Hero, genau dann, wenn der Fokus auf die vorher fokussierte Kachel zurückkehren soll.
- **Ursache:** Fehlschlag und „wirklich leer“ sind nicht unterscheidbar; abgesichert ist nur der Abbruch (`guard !Task.isCancelled`, Kommentar `HomeView.swift:74`):
  ```swift
  let showsHero = hero != nil && !(slides.loaded && slides.items.isEmpty)
  .task(id: hero.map { "\($0.id)|\($0.content.key)" } ?? "-") { … slides.set(items) }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (Layoutwechsel und fehlender Neuversuch); Auslöser (Fehlschlag ohne Cache) ist ein Randfall
- **Fix-Idee:** `failed` aus `homeRowItems` bis in `heroItems` durchreichen und bei Fehlschlag das Hero-Layout behalten; `catalogStamp` der Hero-Quelle in den Aufgaben-Schlüssel nehmen. Besser: beide Layouts teilen sich denselben ScrollView-Baum, nur die Hero-Ebene ist bedingt.
- **Test:** Am Gerät Netz trennen, Cache leeren, starten: Log „hero 0 Folien“ und Fokus außerhalb der Knopfzeile; nach Netz und Rückkehr von einer Detailseite „hero n Folien“ plus „Reihe geladen …“ der sichtbaren Reihen.
- **Gegenprüfung:** `homeRowItems` (`App/Sources/AppModel+HomeRows.swift:19`) behält einen Fehlschlag nicht, aber die Hero-Aufgabe startet mangels Schlüsseländerung nicht neu; der Kommentar dokumentiert nur den Abbruch als abgesichert.

### F-A-5: Doppelte IDs in einer Reihe (Katalog-Einträge werden nicht entdoppelt)
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/RowViews.swift:155`, `App/Sources/Views/RowViews.swift:256`, `App/Sources/Views/RowViews.swift:375`, `App/Sources/AppModel.swift:381`, `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBClient.swift:32`, `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBClient.swift:111`
- **Szenario:** TMDB-Discover-Reihe mit Medientyp „beides“: Film Nr. N und Serie Nr. N bekommen beide die ID `tmdb:N` (getrennte Nummernkreise bei TMDB, Kollision selten, aber möglich). Häufiger: ein Addon-Katalog liefert einen Eintrag doppelt (Mischkataloge). Die Reihe hat dann zwei Karten mit derselben `ForEach`-ID. Folgen: SwiftUI zeigt eine Karte doppelt oder verliert eine; `position.scrollTo(id:)` beim Aufklappen trifft die erste statt der fokussierten Karte; bei exakt gleichen Einträgen tragen zwei Karten dasselbe `.focused(equals:)`-Ziel, das Fokus-Gedächtnis (`items.first { $0.id == id }`) führt immer auf die erste.
- **Ursache:** `loadItems` begrenzt nur (`applyingLimit`), entdoppelt nicht; die Reihe identifiziert Karten allein über `m.id`. Die Genre-Seite entdoppelt dagegen ausdrücklich (`Packages/PlayerCore/Sources/PlayerCore/Models/GenrePage.swift:166`).
  ```swift
  ForEach(Array(displayed.enumerated()), id: \.element.id) { i, m in
  ```
- **Schweregrad:** mittel · **Sicherheit:** plausibel (fehlendes Entdoppeln und ID-Schema bestätigt; Auftreten hängt von den Daten ab)
- **Fix-Idee:** In `loadItems` nach `applyingLimit` stabil nach ID entdoppeln; für TMDB den Typ in die Reihen-Identität einbeziehen (`type|id`), da Film und Serie mit gleicher Nummer verschiedene Titel sind.
- **Test:** PlayerCore-Test für eine stabile Entdoppel-Funktion (erste gewinnt) und für `TMDBClient.items` mit `mediaType == .both` und gleicher Nummer in beiden Antworten.
- **Gegenprüfung:** Zwischen Abruf (`AppModel.swift:368`/`:371`) und `ForEach` gibt es keine Entdoppelung; von „bestätigt“ auf „plausibel“ gesenkt, weil doppelte Eingaben nicht aus dem Code folgen.

### F-A-7: „An Position …“: Fokus wird gesetzt, solange das Blatt noch offen ist, und der Auslöser wird gleichzeitig entfernt
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/Home/HomeManagerView.swift:125`, `App/Sources/Views/Home/HomeManagerView.swift:128`, `App/Sources/Views/Home/HomeManagerView.swift:130`, `App/Sources/Views/Home/HomeManagerView.swift:94`
- **Szenario:** Verwalter, Reihe 14 aufklappen, „An Position …“, Platz 3 wählen. `done` setzt `positionRow = nil`, `expanded = nil` und sofort `focus = .row(id)`. Zu diesem Zeitpunkt liegt der Fokus noch im Blatt; nach dem Schließen gibt das System ihn an den Auslöser zurück, den Knopf „An Position …“ der Aktionsleiste, die mit `expanded = nil` gerade entfernt wurde. Greift die vorzeitige Zuweisung nicht, fällt der Fokus auf `defaultFocus` der Seite (Einstiegsreihe bzw. „Reihe hinzufügen“) und die Liste scrollt von der verschobenen Reihe weg. Gleiches bei Menu im Blatt (`done(nil)`).
- **Ursache:** Die beiden Rückfragen derselben Seite führen Aktion und Fokus ausdrücklich erst in `onDismiss` aus (Kommentar `HomeManagerView.swift:111`, Begründung `SettingsKit.swift:336`); das Blatt hat diese Absicherung nicht:
  ```swift
  positionRow = nil; expanded = nil
  if let p { set(session.move(row.id, toPosition: p)) } else { set(.row(row.id)) }
  ```
- **Schweregrad:** mittel · **Sicherheit:** plausibel (Reihenfolge bestätigt; ob die Zuweisung trotzdem greift, zeigt nur das Gerät)
- **Fix-Idee:** Ergebnis merken und Verschieben samt Fokus in `onDismiss` des Blatts ausführen (wie `SettingsConfirmationModifier`).
- **Test:** Am Gerät: nach „An Position …“ muss der Fokus auf der verschobenen Reihe stehen; im Log folgt auf „Reihe verschoben 14→3“ keine Fokusbewegung nach oben.
- **Gegenprüfung:** Die Abweichung vom im selben Modul dokumentierten Muster ist belegt; die sichtbare Folge ist reines Fokus-Engine-Verhalten und bleibt deshalb „plausibel“ (in „Am Gerät prüfen“ aufgenommen).

### F-B-2: Erstes Zusatzprofil anlegen wirft aus den Einstellungen in „Wer schaut?“ und baut alle Tabs neu
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/PlayerApp.swift:77`, `App/Sources/PlayerApp.swift:68`, `App/Sources/AppModel.swift:270`, `App/Sources/Views/Settings/ProfileSettings.swift:57`, `App/Sources/AppModel.swift:590`
- **Szenario:** App mit genau einem Profil gestartet. Einstellungen › Profil & Konten › „Neues Profil …“ › Name › „Profil anlegen“. `addProfile` hängt das Profil an und wechselt bereits dorthin; `hasMultipleProfiles` wird wahr, `pickedProfile` ist noch `false`, weil die Auswahl mit einem Profil nie gezeigt wurde. RootView ersetzt die TabView durch `ProfilePickerView`, während das Blatt noch schließt, und fragt nach dem Profil, das eben gewählt wurde. Nach der Wahl entsteht die TabView neu: Tab, Pfade und Kategorie bleiben (liegen in RootView), der `@State` aller offenen Seiten, Scrollstand und Fokus sind weg. Gleicher Auslöser: Sicherung mit mehreren Profilen über die Handy-Seite einspielen; die Handy-Seite wird dabei zerstört und ihr `onDisappear` stoppt den Server (`PhoneInputView.swift:119`).
- **Ursache:** Die Bedingung wird laufend ausgewertet, nicht nur beim Start, und `pickedProfile` wird nirgends sonst gesetzt:
  ```swift
  if model.hasMultipleProfiles && !pickedProfile {
      ProfilePickerView { pickedProfile = true }
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt (Zweigwechsel; Fokus-Folgen abgeleitet)
- **Fix-Idee:** Die Auswahl einmal beim Start entscheiden (`pickedProfile` anfangs auf `!model.hasMultipleProfiles` setzen) oder beim Anlegen/Import `pickedProfile = true` setzen.
- **Test:** Am Gerät mit einem Profil ein zweites anlegen: „Wer schaut?“ erscheint; im Fern-Log folgt auf „Profil angelegt“ kein weiterer Eintrag der Einstellungen.
- **Gegenprüfung:** `pickedProfile` hat genau zwei Fundstellen (`PlayerApp.swift:68`, `77`–`78`), kein Guard, kein Kommentar zu einer bewussten Entscheidung. Korrekturen: Der Zustand der Seiten geht verloren, die Pfade nicht (der Erstbericht klang nach mehr). Die Aussage „zweites Profil über die Handy-Seite“ stimmt so nicht, `addProfile` hat nur den einen Aufrufer; der Handy-Weg ist der Import einer Sicherung (`AppModel.swift:590`). Mit zwei oder mehr Profilen beim Start tritt der Fall nicht auf (`pickedProfile` ist dann `true`).

### S-1: Nicht lesbare `profiles.json` wird durch ein Standardprofil ersetzt und beim nächsten Speichern überschrieben
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:34`, `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:55`, `App/Sources/AppModel.swift:58`, `App/Sources/AppModel.swift:240`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:68`
- **Szenario:** `profiles.json` ist vorhanden, lässt sich aber nicht dekodieren: `schemaVersion` größer als 1 oder ein unbekannter Enum-Wert (S-2), beides nach dem Rückschritt von einem neueren auf diesen Build. `load()` liefert ein frisches Profil „Ich“. Die App startet ohne Fehlermeldung und ohne Log-Zeile. Die erste Einstellungsänderung ruft `save()` und überschreibt alle Profile, Addons, Schlüssel und Anmeldungen in UserDefaults und in beiden Dateikopien.
- **Ursache:** Dekodierfehler und „neueres Schema“ werden wie „keine Datei“ behandelt:
  ```swift
  if let s = try? Self.decode(data) { return s }
  try? storage.write(Self.name + ".bak", data)
  return .makeDefault()
  ```
  `save()` (`ProfileStore.swift:41-43`) kennt den Fehlstart nicht. `.bak` hat die Grenze 0 (`TieredBlobStorage.swift:68`) und liegt deshalb nur als Datei: in Application Support, falls beschreibbar, sonst allein unter `Caches/Player`, das tvOS leeren darf. Im App- und Paketcode liest nichts `.bak` zurück (nur zwei Tests).
- **Schweregrad:** mittel (Folge Totalverlust, Auslöser Randfall) · **Sicherheit:** bestätigt
- **Fix-Idee:** `load()` gibt den Fehlerfall getrennt zurück; die App sperrt dann `save()` und zeigt „Profile nicht lesbar – wiederherstellen oder neu beginnen“. Die Rohdaten zusätzlich so ablegen, dass sie das Leeren von Caches überstehen.
- **Test:** PlayerCore: Datei mit `schemaVersion: 99` schreiben, `load()`, dann `save(Ergebnis)` – erwarten, dass die Originaldatei unverändert bleibt oder `save` verweigert.
- **Gegenprüfung:** Pfad Zeile für Zeile bestätigt. `AppModel.init` übernimmt das Ergebnis ungeprüft (`AppModel.swift:58`); die einzige Start-Meldung „Profile fehlen“ greift nur, wenn gar nichts lesbar ist (`App/Sources/DefaultsStorage.swift:34`), nicht bei einem Dekodierfehler. `TieredBlobStorage.write` (`TieredBlobStorage.swift:81-93`) ersetzt beim nächsten `save()` den UserDefaults-Eintrag und jede Datei. Der Test `newerSchemaIsNotOverwritten` (`Packages/PlayerCore/Tests/PlayerCoreTests/StoreTests.swift:33-39`) prüft nur, dass `.bak` existiert; sein Name verspricht mehr, als er absichert. Herabgestuft von hoch auf mittel: Alle in `Profile` eingebetteten Typen wurden auf Schreiben/Lesen im selben Build geprüft (`AddonManifest`, `AddonResource`, `CatalogDescriptor`, `CatalogExtra`, `HomeRow`, `CatalogSource`, `Folder`, `Appearance`, `BadgeSettings`, `TitleDisplaySettings`, `DiskCacheSettings`, `SyncToken`) – kein Weg gefunden, auf dem Build 249 etwas schreibt, das er nicht wieder liest. `schemaVersion` war in der Historie nie höher als 1, und kein Enum-Fall wurde je entfernt (Historie von `origin/integ`). Der Befund wird hoch, sobald ein Build das Schema erhöht oder einen Enum-Fall ergänzt und ein Rückschritt möglich bleibt (die Update-Prüfung kennt den Zustand „installiert ist neuer als main“, `App/Sources/AppUpdater.swift:76`). Korrektur am Erstbericht: Ein zweiter Fehlstart schreibt dieselben Rohdaten erneut nach `.bak`; überschrieben wird die Kopie erst, wenn nach einem `save()` wieder ein Lesefehler auftritt.

### S-2: Ein unbekannter Enum-Wert in einem Profil macht alle Profile undekodierbar
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:86`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:96`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:99`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:104`, `Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:61`, `Packages/PlayerCore/Sources/PlayerCore/Ranking/QualityBadges.swift:71`, `Packages/PlayerCore/Sources/PlayerCore/Models/Home.swift:38`, `Packages/PlayerCore/Sources/PlayerCore/Models/Collection.swift:8`
- **Szenario:** Ein neuerer Build führt einen weiteren `RowStyle`, eine weitere `SourceKind`, Akzentfarbe oder Fortschrittsquelle ein; der Nutzer geht auf Build 249 zurück oder spielt eine neuere Sicherung ein. Ein einziges Profil mit dem neuen Wert lässt `StoredProfiles` als Ganzes scheitern: beim Start folgt S-1, beim Einspielen „Sicherung ungültig“ (dort ohne Datenverlust).
- **Ursache:** Diese Felder werfen bei unbekanntem Wert:
  - in `Profile`: `language`, `progressSource`, `addons`, `collections`, `home`, `appearance`, `diskCache` (`try c.decodeIfPresent(…)`, `Profile.swift:86-105`);
  - in `Appearance`: `navigation`, `accent`, `cardSize` (`Appearance.swift:61-63`), `badges` und `titles` als Ganzes (`:68-69`);
  - in `BadgeSettings`: `style` (`QualityBadges.swift:71`);
  - synthetisierte Decoder ohne Rückfall: `HomeRow.style`, `RowContent`, `CatalogSource.kind`/`mediaType`, `SourceKind`, `Folder`, `MediaCollection`.

  Tolerant sind dagegen `subtitleMode` (`Profile.swift:88`), `sources`, `player`, `hiddenRows`, `subtitleStyle`, `skip` (`:107-111`), `TitleDisplaySettings.posterBadges` und die Felder von `SourceSettings`. `hiddenRows` und `home.rows` haben denselben Typ `HomeRow`, aber nur `hiddenRows` ist abgesichert.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Profile einzeln und fehlertolerant dekodieren (ein kaputtes überspringen und melden); Reihen und Quellen mit unbekanntem Stil oder Typ überspringen; Enums mit Rückfall auf den Standard.
- **Test:** PlayerCore: JSON mit `"style":"neu"` in einer Startseiten-Reihe bzw. `"accent":"red"` → `importData` muss das Profil mit Standardwert liefern.
- **Gegenprüfung:** Alle acht Zeilen stimmen. Beleg, dass der Fall real vorkommt: `SourceKind.upcoming` kam in Commit 711b000 dazu; ein Build davor kann ein Profil mit der Reihe „Heute neu“ nicht lesen. Kein Test deckt unbekannte Werte ab (`ModelTests`, `LegacyProfileTests`, `AppearanceTests` prüfen nur fehlende Felder und Hin-und-zurück). Schweregrad bleibt mittel; eigenständiger Schaden entsteht nur über S-1.

### S-3: Abgeholter Trakt/Simkl-Fortschritt landet nach Profilwechsel im falschen Profil
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/AppModel.swift:183`, `App/Sources/AppModel.swift:189`, `App/Sources/AppModel.swift:190`, `App/Sources/AppModel.swift:192`, `App/Sources/PlayerApp.swift:10`, `App/Sources/PlayerApp.swift:77`, `App/Sources/PlayerApp.swift:221`
- **Szenario:** Zwei Profile, A zuletzt aktiv, A nutzt Trakt oder Simkl als Fortschrittsquelle. Beim Start läuft `syncRemoteProgress()` für A, gleichzeitig zeigt die App die Profilwahl. Der Nutzer wählt B, bevor die Antwort von `/sync/playback` da ist. `switchProfile` setzt `progress` auf das Buch von B (`AppModel.swift:266`); die Antwort für A wird danach in dieses Buch gemischt und unter der ID von B gespeichert. B zeigt die angefangenen Titel von A in „Weiterschauen“, dauerhaft.
- **Ursache:** Nach dem `await` wird das Profil nicht erneut geprüft:
  ```swift
  let remote = s == "trakt" ? try await trakt?.playback(token: t) : …
  progress.merge(remote: applySyncQueue(remote ?? []))
  try progressStore.save(progress, profile: profile.id)
  ```
- **Schweregrad:** mittel · **Sicherheit:** Codepfad bestätigt, Auslöser plausibel (Zeitfenster = Dauer der Abfrage, länger bei langsamem Netz oder vorgeschalteter Token-Erneuerung)
- **Fix-Idee:** Profil-ID vor dem ersten `await` merken und danach vergleichen, wie es `perform` schon tut (`App/Sources/AppModel+SyncQueue.swift:81-83`).
- **Test:** Am Gerät: zwei Profile, Netz drosseln, beim Start sofort das andere Profil wählen; im Fern-Log folgt „trakt: N angefangene Titel geholt“ nach dem Wechsel. In PlayerCore nicht testbar (Logik liegt in `AppModel`).
- **Gegenprüfung:** Keine Generation und keine ID-Prüfung in `syncRemoteProgress` (`AppModel.swift:183-194`); die Absicherungen für Kataloge (`TimedCache.generation`) und Quellen (`TaskSlots`) greifen hier nicht. Die Profilwahl erscheint bei mehr als einem Profil bei jedem Start (`PlayerApp.swift:77`), parallel zur Start-Aufgabe (`PlayerApp.swift:10`). Herabgestuft von hoch auf mittel: enges Zeitfenster, kein Verlust, aber dauerhafte Vermischung. Gekürzt gegenüber dem Erstbericht: Die Aussage, `processSyncQueueOnce` sende Änderungen von A mit dem Token von B, hält nicht – zwischen `profileID` (`AppModel+SyncQueue.swift:131`) und dem Token-Abruf des ersten Dienstes (`:138`) liegt kein `await`, und nach jedem Senden prüft `:144`. Als Nebenpfad bleibt plausibel: `sendScrobble` bestimmt die Dienste sofort (`AppModel.swift:202`), Token und Client aber erst beim Ausführen (`:210`, `:212`); `installAddon` schreibt nach dem Laden in das dann aktive Profil (`:290`). Beides braucht einen Profilwechsel innerhalb einer hängenden Anfrage.

### S-4: Trakt-Erneuerung: rotiertes Token geht bei Profilwechsel verloren, laufende Erneuerung wird profilübergreifend geteilt
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/AppModel.swift:163`, `App/Sources/AppModel.swift:171`, `App/Sources/AppModel.swift:156`, `App/Sources/AppModel.swift:127`
- **Szenario 1 (Anmeldung verloren):** Profil A braucht beim Start eine Erneuerung. Während `/oauth/token` läuft, wählt der Nutzer in der Profilwahl B. Der Dienst hat das alte Erneuerungstoken verbraucht, das neue wird nicht gespeichert. Beim nächsten Start mit A scheitert jede Erneuerung; A muss sich neu anmelden. Der Nutzer sieht nur „Trakt nicht erreichbar“.
- **Szenario 2 (fremdes Konto):** B hat eine eigene Trakt-Anmeldung, deren Token ebenfalls fällig ist. `refreshTrakt` von B wartet auf die laufende Aufgabe von A und erhält das Token von A. Der anschließende Abgleich von B holt damit den Stand von A und mischt ihn in das Buch von B.
- **Szenario 3:** „Abmelden“ während einer laufenden Erneuerung: Die Aufgabe schreibt danach das neue Token zurück, die Anmeldung ist wieder da.
- **Ursache:**
  ```swift
  if let running = traktRefresh { return await running.value }
  …
  if self?.profile.id == profileID { self?.update { $0.syncTokens["trakt"] = n } }
  ```
  Das neue Token wird nur gespeichert, wenn das Startprofil noch aktiv ist; `traktRefresh` ist an kein Profil gebunden, und Zeile 163 prüft weder Profil noch `old`.
- **Schweregrad:** mittel · **Sicherheit:** Codepfad bestätigt, Auslöser plausibel (Zeitfenster = Dauer der Erneuerung)
- **Fix-Idee:** Das neue Token immer in das Profil mit `profileID` schreiben, auch wenn es nicht mehr aktiv ist (nur wenn dort noch das alte Token steht); die laufende Aufgabe zusammen mit der Profil-ID merken und nur Aufrufer desselben Profils mitwarten lassen.
- **Test:** Logik nach PlayerCore ziehen (kleiner „TokenRefresher“ mit Profil-ID): Erneuerung für A starten, aktives Profil wechseln, Ergebnis muss bei A gespeichert sein und B darf es nicht erhalten.
- **Gegenprüfung:** Die ID-Prüfung in Zeile 171 existiert, verhindert aber nur das Schreiben ins falsche Profil – sie verwirft dabei das einzige gültige Token. `update` schreibt ausschließlich ins aktive Profil (`AppModel.swift:234-238`), einen Weg in ein inaktives Profil gibt es nicht. Nach dem Verlust liefert `token()` das alte Token weiter (`?? t`, Zeile 156), jede Anfrage endet in 401 und einer weiteren gescheiterten Erneuerung (`TraktClient.swift:74`). Der Kommentar in Zeile 160 nennt die Rotation ausdrücklich als Annahme. Herabgestuft von hoch auf mittel wegen des Zeitfensters. Wie oft eine Erneuerung beim Start anfällt, hängt von der Lebensdauer des Zugangstokens ab (siehe „Am Gerät prüfen“); bei kurzer Lebensdauer läuft sie bei fast jedem Kaltstart genau während der Profilwahl.

### S-5: Kachel-Aktion auf TMDB-Kachel ohne Netz wird als „nur lokal“ sofort bestätigt und nie gesendet
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/AppModel.swift:401`, `App/Sources/AppModel+SyncQueue.swift:82`, `App/Sources/AppModel+SyncQueue.swift:109`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncQueue.swift:76`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncQueue.swift:119`
- **Szenario:** Kachel aus einer TMDB-Reihe (ID `tmdb:…`), deren IMDb-ID noch nicht nachgeschlagen wurde. Netz weg oder TMDB antwortet mit Fehler. Der Nutzer wählt „Auf die Merkliste“ oder „Als gesehen markieren“. Der Eintrag erscheint lokal, das Log sagt „nur lokal“. Kommt das Netz zurück, wird nichts nachgeholt. Bei der Merkliste verschwindet der Titel wieder, sobald ein Abruf gespeichert wird, der mindestens 5 Minuten nach der Aktion begann.
- **Ursache:** `imdbID(for:)` schluckt den Fehler (`try? await tmdb.imdbID(…)`) und liefert `nil`; `record` setzt dann `pending = []` und `confirmedAt = now`. „Keine IMDb-ID vorhanden“ und „Nachschlagen fehlgeschlagen“ sind nicht unterscheidbar.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Fehlgeschlagenes Nachschlagen als „IMDb-ID offen“ in der Änderung vermerken (Dienste bleiben `pending`) und die ID beim Abarbeiten der Warteschlange nachholen.
- **Test:** PlayerCore: `record(…, imdb: nil, services: ["trakt"])` mit einem neuen Merkmal „ID ungeklärt“ → `pendingCount == 1`; am Gerät: WLAN aus, TMDB-Kachel auf die Merkliste, Log-Zeile „nur lokal“ suchen.
- **Gegenprüfung:** Bestätigt. Das Kachelmenü bietet die Merkliste für `tmdb:`-Kacheln ausdrücklich an, weil sie auflösbar sind (`AppModel+SyncQueue.swift:56-59`); der Fehlerfall der Auflösung ist nirgends abgefangen. Der Test `SyncQueueTests.swift:67-69` schreibt „ohne IMDb sofort bestätigt“ als Soll fest – das ist für Titel ohne IMDb-ID gewollt, nicht für ein gescheitertes Nachschlagen. Das Verschwinden von der Merkliste folgt aus `notePull` (`SyncQueue.swift:119-126`).

### S-6: „Gesehen“-Scrobble (`stop`) geht bei Netzfehler oder 5xx verloren, keine Warteschlange
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Sync/APIRequest.swift:89`, `Packages/PlayerCore/Sources/PlayerCore/Sync/APIRequest.swift:97`, `App/Sources/AppModel.swift:214`
- **Szenario:** Folge zu Ende geschaut, der Dienst antwortet in diesem Moment mit 502/503, oder zwei Versuche im Abstand von 1,5 s scheitern am Netz. Lokal gilt die Folge als gesehen, beim Dienst nie; dort bleibt höchstens ein alter Pausenstand. Auf anderen Geräten erscheint die Folge weiter als angefangen.
- **Ursache:** `SyncRetry.scrobble` wiederholt `stop` nur nach einem geworfenen Netzfehler, genau einmal; ein Status außerhalb 2xx/409 wirft sofort. `sendScrobble` loggt den Fehler nur. Die Warteschlange (`SyncQueue`) kennt nur Kachel-Aktionen.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Ein gescheitertes `stop` oberhalb der Gesehen-Schwelle als `markWatched`-Änderung in die Warteschlange legen (braucht Staffel/Folge im `SyncChange`); 5xx wie Netzfehler behandeln.
- **Test:** PlayerCore: `SyncRetry.scrobble(.stop)` mit Antwort 503 → heute Fehler nach genau einer Anfrage; am Gerät: Fern-Log nach „trakt stop: status(5xx)“ durchsuchen.
- **Gegenprüfung:** Bestätigt. Der Test `scrobbleOtherStatusThrows` (`SyncRetryTests.swift:74-81`) schreibt „ein Versuch, dann Fehler“ für 404 fest; für 5xx gibt es keine bewusste Entscheidung im Code oder Kommentar. Kein späterer Abgleich holt den Stand nach: `syncRemoteProgress` liest nur, und der ältere Pausenstand des Dienstes überschreibt den lokalen nicht (`WatchProgress.swift:116`).

### S-9: Profil löschen / Sicherung einspielen lässt Fortschritts- und Merkdateien verwaist zurück
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/AppModel.swift:276`, `App/Sources/AppModel.swift:589`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:122`, `App/Sources/Playback/PlayerMemory.swift:72`, `App/Sources/CollectionLinkStore.swift:86`
- **Szenario:** Ein Profil wird gelöscht. `progress-<id>.json`, `trackmemory-<id>.json`, `fileprogress-<id>.json`, `linkpack-<id>-….json`, `import-media-<id>-….json` sowie die UserDefaults-Schlüssel `collectionlinkmeta.<id>` und `fusionkit.<id>` bleiben. Der verwaiste Fortschrittsblock belegt weiter das gemeinsame Budget von 128 KB aller Nicht-Profil-Blöcke; der Fortschritt des aktiven Profils passt dann früher nicht mehr in UserDefaults (S-10). Außerdem bleibt der Verlauf des gelöschten Profils auf dem Gerät. Gleiches nach „Sicherung wiederherstellen“ mit anderen Profil-IDs.
- **Ursache:** `deleteProfile` räumt nur Katalogdatei und Warteschlange ab (`AppModel.swift:279-280`); `importBackup` nur die Katalogdateien (`:591`). `fitsDefaults` zählt alle Blöcke mit Präfix `blob.`, auch verwaiste.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Eine Funktion „alle Blöcke eines Profils entfernen“ (Namensmuster an einer Stelle) in `deleteProfile` und nach `importBackup` für nicht mehr vorhandene IDs aufrufen; beim Start einmal verwaiste Blöcke aufräumen.
- **Test:** Am Gerät: Profil anlegen, etwas schauen, löschen, neu starten – die Start-Log-Zeile „Defaults … Blöcke: …“ listet `progress-<alte id>.json` weiter.
- **Gegenprüfung:** Bestätigt. `ProgressStore` hat gar keine Löschfunktion (`WatchProgress.swift:129-145`); die einzigen profilbezogenen Löschungen im App-Code sind `clearTrackMemory` (nur über die Einstellung, `PlayerMemory.swift:33-37`), einzelne Import-Links (`CollectionLinkStore.swift:150-151`), die Warteschlange und die Katalogdatei.

### S-10: Fortschritt wächst unbegrenzt und fällt dann aus UserDefaults – liegt danach ggf. nur noch unter Caches
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:35`, `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:58`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:35`, `Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:84`, `App/Sources/DefaultsStorage.swift:21`
- **Szenario:** Nach vielen geschauten Folgen (jede Folge ein Eintrag mit vollständigem `MetaPreview` samt Beschreibung) überschreitet `progress-<id>.json` komprimiert 96 KB, oder die Summe mit Warteschlange, Spur-Gedächtnis, IntroDB-Cache, Preview-Packs und den Blöcken anderer Profile 128 KB. `write` entfernt dann den UserDefaults-Eintrag und schreibt nur noch Dateien. Ist Application Support nicht beschreibbar, liegt der Fortschritt nur noch unter `Caches/Player`. Räumt tvOS den Cache, sind Weiterschauen, Verlauf und Warteschlange weg – ohne Log-Zeile, denn nur für `profiles.json` gibt es `onProfilesFileOnly`.
- **Ursache:** `ProgressBook.entries` hat keine Obergrenze (anders als `FileProgressBook`, `SkipSegmentStore.maxEntries`, `FailedLinkBook.maxTitles`); `history(limit:)` und `continueWatching(limit:)` begrenzen nur die Anzeige.
- **Schweregrad:** mittel · **Sicherheit:** plausibel (Wachstum und Verdrängung bestätigt; ab wann die Grenze erreicht wird und ob Application Support beschreibbar ist, entscheidet das Gerät)
- **Fix-Idee:** Gesehene Einträge kürzen (nur ID, Zeit, `finished`; `item` nur für die jüngsten N) und eine Obergrenze einführen; loggen, wenn der Fortschritt aus UserDefaults fällt.
- **Test:** PlayerCore: Buch mit 3000 Folgen-Einträgen über `TieredBlobStorage` mit Kompression schreiben und prüfen, ob der Block in `defaultsSizes()` bleibt; am Gerät Start-Log „Blöcke: …“ beobachten.
- **Gegenprüfung:** Kein Kürzen der Einträge im Paket oder in der App gefunden; `write` verhält sich wie beschrieben (`TieredBlobStorage.swift:81-93`). Der Kommentar in `DefaultsStorage.swift:6-7` nennt die Verweigerung von Application Support selbst als häufig. Bleibt „plausibel“, weil die Kette drei gerätabhängige Bedingungen hat. Einträge derselben Serie wiederholen dasselbe `item` und komprimieren deshalb gut; das gemeinsame Budget wird eher durch die Summe der Blöcke erreicht als durch ein einzelnes Buch.

### W-A-2: Automatische Tonwahl kann Kommentar- oder Hörfilm-Spur wählen
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Ranking/StreamTraits.swift:207-221`, `App/Sources/Views/PlayerScreen.swift:432-435`
- **Szenario:** Datei mit Hauptton in Stereo/Mono ohne Dolby Digital (AAC, FLAC, PCM, DTS 2.0 – häufig bei Remuxen älterer Filme) und einer Kommentarspur in AC-3 2.0 in derselben Sprache. Bewertung: Hauptton 2 Punkte, Kommentar 102 Punkte → die App schaltet beim Start auf den Kommentar. Gleiches gilt für eine Hörfilm-Spur in E-AC-3/AC-3 5.1 neben einem Hauptton in DTS/TrueHD (z. B. 1106 gegen 1006 bzw. 1008 Punkte).
- **Ursache:** `preferredAudioTrack` filtert nur nach Sprache; `audioScore` kennt weder `isCommentary` noch `isVisualImpaired`.
  ```swift
  return (ch >= 6 ? 1000 : 0) + (t.isPassthrough ? 100 : 0) + ch
  ```
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** In `preferredAudioTrack` Kommentar- und Hörfilm-Spuren nur nehmen, wenn es in der Sprache keine andere gibt.
- **Test:** PlayerCore-Test: `[AAC 2.0 de, AC-3 2.0 de Kommentar]` mit Vorrang `["de"]` muss die erste Spur liefern; ebenso `[TrueHD 7.1 en, E-AC-3 5.1 en Hörfilm]`.
- **Gegenprüfung:** Reine PlayerCore-Funktion, vollständig gelesen. Die Felder kommen aus der Engine an (`App/Sources/Playback/PlaybackEngine.swift:171`). Der Feldkommentar sagt ausdrücklich „Kommentarspur …; nie automatisch wählen“ (`StreamTraits.swift:171`), das Spur-Gedächtnis hält sich daran (`Packages/PlayerCore/Sources/PlayerCore/Playback/TrackMemory.swift:94`), die Automatik nicht. Kein Test in `StreamTraitsTests.swift`/`MediaLabelsTests.swift` schreibt das jetzige Verhalten für Kommentarspuren fest. Bei Punktgleichheit gewinnt die erste Spur (`max(by:)`), daher trifft es nicht jede Datei – Randfall, mittel passt. Nebenbei: Das Spur-Gedächtnis schließt nur Kommentar aus, nicht Hörfilm.

### W-A-3: Tonspur geht nach Ersatz-Laden verloren
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:744`, `App/Sources/Views/PlayerScreen.swift:766-800`
- **Szenario:** Der Nutzer wählt im Panel Englisch, oder die App hat beim Start auf die Dolby-Digital-Spur geschaltet. Später ein Fehler → `.reresolve` (frischer Link, `engine.load`) oder `engine.recover()` scheitert und der Rückfall `engine.load(…, start: pos)` läuft. Danach spielt die Vorwahl der Engine (erste passende Sprache aus `prefs.audioLanguages`), die gewählte Spur ist weg.
- **Ursache:** Vor dem Neuladen wird nur die Untertitel-Wahl gesichert und danach wieder gesetzt. `audioLanguage` wird gelesen (Zeile 744), aber nur an die Addon-Untertitel weitergegeben; `selectAudio` wird im ganzen Zweig nicht gerufen.
- **Schweregrad:** mittel · **Sicherheit:** plausibel (dass im Zweig keine Tonspur wiedergewählt wird, ist belegt; dass ein frisches `load` die Wahl nicht behält, ist Verhalten der Engine)
- **Fix-Idee:** Aktive Ton-ID und Sprache vor dem Abbau merken und nach einem Ersatz-Laden (`reloaded == true`) wieder wählen: ID, sonst Sprache über `preferredAudioTrack`.
- **Test:** Am Gerät den Ton umstellen und einen Link ablaufen lassen; im Fern-Log „Frischer Link · load ab …“ und danach die Tonspur-Zeile der Steuerleiste prüfen.
- **Gegenprüfung:** Zeilen 733-802 vollständig gelesen: einzige Spur-Aufrufe sind `selectSubtitle`/`autoSelectSubtitle` (793) und `loadAddonSubtitles` (799). Auch `escalate` und `restoreAndPlay` (`App/Sources/Views/Player/PlayerLifecycle.swift:66-96`) wählen keinen Ton. Für den Engine-Anteil spricht der Code selbst: Der Start muss nach `load` eigens `selectAudio` rufen (432-435), und der Kommentar in Zeile 738 hält fest, dass die Untertitel-Wahl nach dem Abbau weg ist. Bewiesen ist das ohne Engine-Quelltext nicht, daher „plausibel“ statt „bestätigt“.

### W-B-2: Player-Ende bei offenem Spur-/Seitenpanel überspringt Scrobble-Stopp und Vorlader-Freigabe
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:98`, `App/Sources/Views/Player/PlayerExit.swift:12`, `App/Sources/Views/Player/PlayerLifecycle.swift:98`, `App/Sources/StreamPrefetcher.swift:92`
- **Szenario:** Ton/Untertitel-Panel (oder Seitenpanel) ist offen, das Apple TV geht länger als 10 min in den Hintergrund (TV aus, Home). Bei der Rückkehr schließt `closeAfterBackground` den Player über `leaveWithModeSwitch` → `dismiss()`. `tracksOpen` in `PlayerScreen` bleibt `true`, weil nur `onEnded`, `onFallback` und die Links des Seitenpanels es zurücksetzen. `PlayerScreen.onDisappear` kehrt deshalb vorzeitig zurück: `StreamPrefetcher.playerDisappeared` läuft nie (das Token bleibt in `players`, Vorladen und Fokus-Video bleiben bis zum App-Neustart gesperrt), `model.endPlayback` läuft nie (kein Scrobble-`stop`; die Sitzung wird erst geschlossen, wenn ein anderer Titel startet), `extras.cancel()` entfällt.
- **Ursache:** `guard !tracksOpen else { return }` kennt den Ausgang über `dismiss()` nicht; `leave` meldet ihn nicht nach oben. `PlayerControls` selbst behandelt den Fall über `leaving`, `PlayerScreen` nicht.
- **Schweregrad:** mittel · **Sicherheit:** plausibel (Pfad im Code geschlossen; ob `handlePhase` unter dem Cover feuert, ob `dismiss()` beide Ebenen schließt und ob SwiftUI dabei `showTracks` noch rechtzeitig zurücksetzt, zeigt nur das Gerät)
- **Fix-Idee:** In `leave` immer `onTracksShown(false)` aufrufen (oder `PlayerScreen` einen eigenen „verlässt“-Rückruf geben), bevor geschlossen wird.
- **Test:** Am Gerät: Panel öffnen, Home, mehr als 10 min warten, zurück; im Fern-Log muss nach „Player schließt“ der Vorlader wieder arbeiten und ein Scrobble-`stop` erscheinen.
- **Gegenprüfung:** Alle Stellen gesucht, die `tracksOpen` zurücksetzen (`PlayerScreen.swift:65`, `:66`, `:74`, `:107`); der Weg über `dismiss()` ist nicht dabei, die Panels reagieren nicht auf den Szenenwechsel; Zeile der Vorlader-Freigabe korrigiert (`:92` statt `:80`).

### W-B-3: Scrobble: Verlassen zwischen 80 % und 92 % und späteres Fertigschauen sendet zwei `stop`
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Sync/ScrobbleTracker.swift:42`, `Packages/PlayerCore/Sources/PlayerCore/Sync/ScrobbleTracker.swift:68`
- **Szenario:** Folge bei 85 % verlassen → `end` → `close` sendet `stop` mit 85 % (der Dienst wertet `stop` ab 80 % als gesehen). Lokal ist die Folge nicht gesehen (Schwelle 92 %), Weiterschauen bietet sie bei 85 % an; der Abgleich holt nur Angefangenes, nicht den Verlauf, und gleicht das nicht aus. Beim Weiterschauen in einer neuen Sitzung gibt es kein `start` (≥ 80 %), bei 92 % aber wieder `stop` → zweiter Verlaufseintrag beim Dienst. Jedes weitere Verlassen zwischen 80 % und 92 % sendet erneut `stop`.
- **Ursache:** Zwei Schwellen (80 % für `stop`, 92 % für „fertig“), und `completed` lebt nur in der Sitzung:
  `guard !s.completed, s.active || s.fraction >= Self.startLimit else { return [] }`
- **Schweregrad:** mittel · **Sicherheit:** plausibel (Ereignisfolge im Code eindeutig; die Wirkung beim Dienst ist aus dessen Regeln abgeleitet, nicht gemessen)
- **Fix-Idee:** Lokal ab dem ersten `stop` ≥ 80 % als gesehen führen, oder beim Verlassen zwischen 80 % und `finishedAt` `pause` statt `stop` senden.
- **Test:** PlayerCore: neue Sitzung `progress(0.86)`, `end` → `stop`; danach neue Sitzung `progress(0.93)` → darf kein zweites `stop` liefern.
- **Gegenprüfung:** `SyncRetryTests` schreibt das `stop` beim Verlassen ab 80 % als gewollt fest („zählt als gesehen“) und sichert „genau einmal“ nur innerhalb einer Sitzung; der Fehler ist die fehlende lokale Entsprechung über Sitzungen hinweg, nicht das einzelne `stop`.

### W-B-4: Startstelle aus Trakt/Simkl geht nach einem frühen Fehler verloren, danach wird der Stand überschrieben
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:376`, `App/Sources/Views/PlayerScreen.swift:737`
- **Szenario:** Titel hat nur einen Anteil aus dem Sync (`startFraction`, `start == nil`). Die Laufzeit kommt, `fractionApplied = true`, der Sprung an 60 % löst einen Fehler aus (abgelaufener Link, Netz), bevor an der Zielstelle eine Sekunde gespielt wurde. `recover` lädt ab `lastGoodTime` bzw. `start ?? 0`, also ab dem Anfang; der Anteil wird nie wieder angewandt, weil `fractionApplied` gesetzt bleibt. Nach 10 s speichert der Takt Position 10 s: der Eintrag verliert `remoteFraction` (siehe W-B-1), ist lokal neuer als der entfernte Stand (der Abgleich überspringt ihn), und ein Scrobble-`start` bei ≈ 0 % geht hinaus.
- **Ursache:** `fractionApplied` wird vor dem Erfolg des Sprungs gesetzt, und die Fehlerleiter kennt den Anteil nicht:
  `let pos = lastGoodTime > 0 ? lastGoodTime : (start ?? 0)`
- **Schweregrad:** mittel · **Sicherheit:** plausibel (braucht einen Fehler im Fenster zwischen bekannter Laufzeit und erster gespielter Sekunde an der Zielstelle)
- **Fix-Idee:** Zielstelle `f * d` als Startstelle merken (z. B. in einem `pendingStart`) und in `recover` sowie beim wiederholten Start verwenden; `fractionApplied` erst nach gelungenem Sprung setzen.
- **Test:** Am Gerät/Fern-Log: Titel mit Sync-Anteil starten, Netz beim Start kurz trennen; „load ab … s“ bzw. „Start wird wiederholt“ darf nicht am Anfang landen.
- **Gegenprüfung:** Beide Wiederholungswege in `recover` gelesen (ganzer Start über `loadAndStart` mit `start`, Neuladen mit `pos`); keiner greift auf `startFraction` zurück, und der Kommentar bei `:736` deckt nur die feste Startstelle ab.

---

## Schweregrad: niedrig

### A-A-8: Quellen-Cache und laufende Suchen überleben Änderungen am Addon-Satz
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel.swift:287`, `App/Sources/Views/Settings/AddonSettings.swift:78`, `App/Sources/Views/Settings/AddonSettings.swift:95`, `App/Sources/AppModel.swift:590`, `App/Sources/AppModel.swift:476`
- **Szenario:** (a) Nutzer installiert ein weiteres Addon und öffnet einen Titel, der in den letzten 30 min schon gesucht wurde: Er sieht den alten Stand ohne das neue Addon; ist der Stand älter als 90 s, läuft die Erneuerung im Hintergrund, die offene Liste übernimmt sie aber nicht (erst die nächste Öffnung). (b) Addon entfernt: seine Quellen bleiben bis zur nächsten Erneuerung des jeweiligen Titels in der Liste und können automatisch gewählt werden. (c) Sicherung vom Handy eingespielt: Profile samt Addons werden ersetzt, `streamCache`, `streamTasks`, Leer-Pausen und Addon-Meta-Cache bleiben stehen. (d) Reihenfolge getauscht: Listenreihenfolge im Cache bleibt alt.
- **Ursache:** Der Cache-Schlüssel ist nur die Inhalts-ID; geleert wird ausschließlich in `switchProfile` (`App/Sources/AppModel.swift:257`–`264`). Installieren, Entfernen und Sicherungs-Import rufen nur `clearCatalogCache()` auf, Tauschen gar nichts.
- **Schweregrad:** niedrig (herabgestuft: seltene Handlung, heilt sich nach einer weiteren Öffnung bzw. spätestens nach 30 min) · **Sicherheit:** bestätigt
- **Fix-Idee:** Eine Funktion „Addon-Satz geändert“ (Quellen-Cache, `streamTasks.reset()`, Leer-Pausen, `StreamPrefetcher.reset()`, `AddonMetaCache.reset()`) bei Installieren, Entfernen, Tauschen und Sicherungs-Import aufrufen.
- **Test:** Fern-Log: nach „Addon hinzugefügt“ denselben Titel öffnen und auf `Cache-Treffer` ohne das neue Addon achten.
- **Gegenprüfung:** `clearCatalogCache()` (`App/Sources/AppModel+CatalogDisk.swift:68`–`75`) fasst den Quellen-Cache nachweislich nicht an; die Wirkung ist aber kürzer als im Erstbericht dargestellt, weil die Erneuerung den Stand vollständig ersetzt.

### A-A-11: Cinemeta-Abfrage ohne eigene Zeitgrenze bremst Detailseite und „Abspielen“ im Hero
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/AppModel+MetaAddon.swift:10`, `App/Sources/AppModel+MetaAddon.swift:13`, `App/Sources/AppModel+MetaAddon.swift:18`, `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:14`, `App/Sources/AppModel.swift:632`
- **Szenario:** Cinemeta antwortet nicht (Verbindung steht, keine Daten). Das Metadaten-Addon ist für Aufrufer auf 3 s Wartezeit begrenzt; die Cinemeta-Abfrage daneben läuft über `URLSession.shared` mit der Standardgrenze der Sitzung (abgeleitet: 60 s). `mergedMeta` wartet auf beide → `quickPlayRequest` (Hero „Abspielen“, auch für Filme, die Cinemeta gar nicht bräuchten), die Folgenliste der Serie und das Nachladen der Folgen in der Quellenliste (`App/Sources/Views/DetailViews.swift:847`) hängen so lange. Fehler werden nicht gemerkt, jeder Aufruf fragt erneut.
- **Ursache:** Nur der Zweig des Metadaten-Addons läuft über `AddonMetaFetch`; `fetchMeta` für Cinemeta ist ein nacktes `try? await client.meta(…)`.
- **Schweregrad:** niedrig (herabgestuft: setzt einen hängenden Fremddienst voraus) · **Sicherheit:** plausibel
- **Fix-Idee:** Cinemeta durch dieselbe begrenzte, geteilte Abfrage schicken (z. B. 8 s) und die Antwort kurz merken.
- **Test:** Am Gerät den Cinemeta-Host blockieren und die Zeit bis zur Folgenliste bzw. bis zum Start aus dem Hero im Fern-Log messen.
- **Gegenprüfung:** Der Aufrufer im Hero (`App/Sources/Views/HomeHero.swift:344`) hat keine eigene Frist; für Serien ändert eine kürzere Frist nur die Dauer bis zur Fehlanzeige, nicht das Ergebnis.

### A-A-13: Werte in `extra` werden nicht wie von Stremio verlangt kodiert (`&`, `=`, `+`, `,`)
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:98`, `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:154`
- **Szenario:** Katalog- oder Untertitel-Abfrage mit einem Wert wie `genre=Sci-Fi & Fantasy`. `encode` lässt alle im Pfad erlaubten Zeichen stehen → `…/genre=Sci-Fi%20&%20Fantasy.json`; das Addon liest einen abgeschnittenen Wert und einen zweiten, leeren Parameter. Heute übergibt die App nur `skip` (`App/Sources/Views/GenrePageView.swift:252`) und die Untertitel-Angaben (`App/Sources/Views/Player/AddonSubtitleLoader.swift:28`); der Fehler wird wirksam, sobald Genre-, Such- oder Dateinamenwerte durchgereicht werden.
- **Ursache:** `CharacterSet.urlPathAllowed` ohne `/?#` statt des Zeichensatzes von `encodeURIComponent`.
- **Schweregrad:** niedrig (derzeit ruhend) · **Sicherheit:** bestätigt
- **Fix-Idee:** Für Schlüssel und Werte von `extra` einen engeren Zeichensatz nehmen (Buchstaben, Ziffern, `-_.!~*'()`).
- **Test:** PlayerCore: `resourceURL(…, extra: ["genre": "A & B"])` erwartet `genre=A%20%26%20B`.
- **Gegenprüfung:** Aufrufer geprüft; welche Werte der Untertitel-Lader genau übergibt, wurde nicht im Einzelnen nachvollzogen (Dateiname wäre der kritische Fall).

### A-A-14: „[WEB-DL]“ im Quellennamen wird als Dienst Debrid-Link erkannt
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Ranking/ReleaseMatch.swift:171`
- **Szenario:** Quelle ohne `behaviorHints.service`, Name `1080p [WEB-DL]`. Nachgerechnet am Muster `(^|[^A-Z0-9])DL(\+|⚡|⏳|\])`: die Kürzel TB, RD, AD, PM treffen nicht; bei DL steht davor „-“ (kein Buchstabe, keine Ziffer) und dahinter „]“ → `service = "DL"`. Folge: falscher Dienst in Dubletten-Schlüssel, Rangfolge und Text der Karte „Sofort abspielen“.
- **Ursache:** Das Zeichen vor dem Kürzel darf ein Bindestrich sein; der Kommentar (`ReleaseMatch.swift:165`–`166`) schließt „WEB-DL“ aus, das gilt aber nur ohne schließende Klammer.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Vor dem Kürzel nur Zeilenanfang, Leerraum oder öffnende Klammer zulassen.
- **Test:** PlayerCore: `ReleaseName.service(StreamItem(name: "1080p [WEB-DL]"))` erwartet nil.
- **Gegenprüfung:** Der vorhandene Test deckt nur `AIO 1080p WEB-DL` ohne Klammer ab (`Tests/PlayerCoreTests/ReleaseMatchTests.swift:29`); nur das Feld `name` wird durchsucht.

### A-A-15: TorBox-Liste: unlesbare Antwort gilt als leeres Konto; drei Abfragen nacheinander ohne eigene Zeitgrenze
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Services/TorBox.swift:96`, `Packages/PlayerCore/Sources/PlayerCore/Services/TorBox.swift:48`, `App/Sources/Views/TorBoxFilesRow.swift:70`
- **Szenario:** (a) TorBox antwortet mit Status 200, aber anderem Aufbau oder `data: null` → `parseList` gibt `[]` zurück, alle drei Listen leer, kein Fehler → Anzeige „Keine fertigen Video-Dateien im Konto.“ statt „TorBox nicht erreichbar“, und der leere Stand wird 5 min gemerkt (`App/Sources/Views/TorBoxFilesRow.swift:94`, `98`). (b) Torrents, Usenet und Web-Downloads werden nacheinander geholt, je über `URLSession.shared` ohne eigene Frist und mit einmaligem Warten bei Status 429 → im schlechten Fall sehr langes „Lädt …“.
- **Ursache:** `try?` und `as?` verschlucken den Unterschied zwischen „leer“ und „unlesbar“; serielle `for`-Schleife.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** In `parseList` bei fehlendem `data`-Feld einen Dekodierfehler werfen; die drei Listen mit `async let` parallel und mit Frist holen.
- **Test:** PlayerCore: `parseList` mit `{"success":false}` soll werfen; Reihenfolge und Dauer mit gefälschtem `APISending` prüfen.
- **Gegenprüfung:** Korrigiert: Teil „keine Seitenabfrage“ des Erstberichts gestrichen, weil die Seitengröße des Dienstes aus dem Code nicht belegbar ist (siehe „Am Gerät prüfen“).

### A-A-16: Addon-Status zählt nicht abspielbare Einträge als „Quellen“
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonSearch.swift:52`
- **Szenario:** Ein Addon ohne Debrid liefert 40 Einträge nur mit `infoHash`. Statuszeile: „40 Quellen“, die Liste darunter bleibt leer, weil nur Einträge mit Web-Adresse abspielbar sind (`Addons/AddonStreamKind.swift:84`). Auch die Log-Zeile und die „alle leer“-Regel (A-A-4) rechnen mit der Rohzahl.
- **Ursache:** Gezählt wird `!addonKind.isNotice` statt `isPlayableVideo`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Abspielbare zählen und nicht abspielbare getrennt nennen.
- **Test:** PlayerCore: `AddonSearchProgress.finish` mit zwei `infoHash`-Einträgen erwartet `.ok(count: 0)`.
- **Gegenprüfung:** Die Tests mit `.ok(count:)` (`AddonCompatTests.swift:178`, `StabilityTests.swift:268`) verwenden nur abspielbare Einträge und schreiben das Verhalten nicht fest.

### A-A-17: YouTube-Rückfall für Trailer kann rund 24 s dauern
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Services/YouTubeResolver.swift:14`, `Packages/PlayerCore/Sources/PlayerCore/Services/YouTubeResolver.swift:80`, `Packages/PlayerCore/Sources/PlayerCore/Services/YouTubeResolver.swift:83`, `App/Sources/Views/DetailViews.swift:540`
- **Szenario:** YouTube antwortet nicht. Nach der Wartezeit für trailerio folgen nacheinander die Abfrage des Besucher-Tokens und bis zu drei Player-Abfragen mit je 6 s Grenze → bis etwa 24 s „Trailer wird geladen …“, bevor „Trailer nicht verfügbar“ erscheint. Ohne HLS-Adresse des ersten Clients werden immer alle drei gefragt, auch wenn schon eine MP4-Adresse vorliegt.
- **Ursache:** Serielle Schleife ohne Gesamtfrist.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (schlechtester Fall), Auftreten plausibel
- **Fix-Idee:** Gesamtfrist (z. B. 8 s) um `resolve` legen und bei vorhandener MP4-Adresse nach dem zweiten Client abbrechen.
- **Test:** PlayerCore mit gefälschtem `HTTPPosting`, das verzögert antwortet; Fern-Log-Zeilen `trailer` mit Zeitabstand.
- **Gegenprüfung:** Abbruch wird je Client geprüft (`YouTubeResolver.swift:84`); das Weiterfragen nach HLS ist Absicht (bessere Qualität), die fehlende Gesamtfrist nicht dokumentiert.

---

### A-B-5: „Heute neu“ bleibt nach Mitternacht bzw. nach dem Aufwachen auf dem Stand von gestern
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/Views/RowViews.swift:43`, `App/Sources/AppModel+CatalogCache.swift:37`, `App/Sources/AppModel+Upcoming.swift:81`
- **Szenario:** Die App steht abends auf der Startseite, das Apple TV schläft, am nächsten Tag wacht es auf der Startseite auf, bevor ein gezeigter Katalog-Eintrag 24 h alt ist. Die Reihe „Heute neu“ zeigt weiter die Folgen von gestern, bis man eine Seite öffnet und zurückkehrt oder die Reihe aus dem Bild und zurück scrollt.
- **Ursache:** Die `.task(id:)` der Reihe hängt für `.upcoming` nur an `catalogWake`, `catalogRevisions`, `upcomingRevision` und `retry`, nicht am Kalendertag. `catalogWake` steigt beim Aktivwerden nur, wenn ein Eintrag des 24-h-Katalog-Caches fällig ist; „Heute neu“ liegt nicht in diesem Cache (`AppModel.swift:358`) und zählt nie mit.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (Task-Schlüssel), plausibel (Verhalten beim Aufwachen)
- **Fix-Idee:** Den lokalen Kalendertag in die Task-ID der Reihe aufnehmen bzw. `catalogWake` beim Aktivwerden auch bei Tageswechsel erhöhen.
- **Test:** Am Gerät: Gerät über Nacht schlafen lassen; im Fern-Log fehlt nach dem Aufwachen eine neue Zeile „kalender n Serien …“. Ein Tagesschlüssel ist als reine Funktion in PlayerCore testbar.
- **Gegenprüfung:** `HomeView` hat keine eigene Beobachtung von `scenePhase` oder `didBecomeActive`; der einzige Anlass ist `observeCatalogWake`. Die Daten selbst wären richtig: `upcomingToday()` filtert bei jedem Aufruf nach dem aktuellen Tag, und das Abruffenster reicht von gestern bis +14 Tage. Es fehlt nur der Auslöser. Ist beim Aufwachen zufällig ein gezeigter Katalog über 24 h alt, lädt die Reihe mit; der Fehler tritt daher nicht jeden Tag auf.

### A-B-6: Hero-Folien übernehmen eine Hintergrund-Erneuerung ihrer Quelle nicht
- **Bereich:** Addons & Startseite
- **Ort:** `App/Sources/Views/HomeView.swift:71`, `App/Sources/AppModel.swift:610`, `App/Sources/AppModel+CatalogCache.swift:27`
- **Szenario:** Start aus dem Plattencache mit einer Hero-Quelle. `heroItems` liefert den alten Stand und stößt die Erneuerung an. Nach deren Ende laden nur Reihen neu, deren Task-ID `catalogStamp` enthält; die Diashow zeigt weiter den alten Stand (laut `CatalogSnapshot.maxAge` bis zu 14 Tage alt), bis die Startseite neu erscheint (Rückkehr von einer gepushten Seite).
- **Ursache:** Die Task-ID des Hero ist `"\(hero.id)|\(hero.content.key)"`; `model.catalogStamp(hero.content)` fehlt.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** `catalogStamp(hero.content)` an die Task-ID hängen und die Folien nur ersetzen, wenn sich die IDs geändert haben (sonst springt die Diashow auf Folie 1).
- **Test:** Am Gerät: Nach „katalog … im Hintergrund erneuert“ der Hero-Quelle erscheint im Fern-Log keine neue Zeile „hero n Folien“.
- **Gegenprüfung:** `HeroLayer`/`HeroButtons` lesen nur `slides`; `catalogRevisions` und `catalogWake` kommen in `HomeView.swift` und `HomeHero.swift` nicht vor. Ist die Hero-Quelle keine Reihe im Stil „Hero“, erneuert sich die Reihe darunter, die Folien trotzdem nicht. Kein Kommentar deutet auf Absicht.

### A-B-8: Reihen können doppelte Titel-IDs enthalten (Trakt-Listen mit Staffel-/Folgen-Einträgen, TMDB-Film und -Serie mit gleicher Nummer)
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Sync/TraktClient.swift:200`, `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBClient.swift:111`, `App/Sources/AppModel.swift:381`, `App/Sources/Views/RowViews.swift:155`
- **Szenario:** (a) Eine Trakt-Liste oder -Merkliste enthält eine Serie und zusätzlich eine Staffel oder Folge derselben Serie; `TraktClient.items` macht aus jedem Eintrag mit `show`-Objekt dieselbe Serienkachel mit derselben IMDb-ID. (b) Eine gemischte TMDB-Liste enthält Film 1399 und Serie 1399: beide bekommen `tmdb:1399`. Die Reihe nutzt `ForEach(…, id: \.element.id)`; doppelte IDs führen im `LazyHStack` zu vertauschten oder fehlenden Karten.
- **Ursache:** `loadItems` kürzt nur (`applyingLimit`) und entfernt keine Doppelten; `MetaPreview.id` aus TMDB enthält den Typ nicht.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (kein Entfernen im Pfad), plausibel (Auftreten in echten Listen)
- **Fix-Idee:** In `loadItems` nach dem Abruf nach ID entdoppeln (erstes Vorkommen bleibt); in `TraktClient.items` Staffel-/Folgen-Einträge überspringen.
- **Test:** PlayerCore: `TraktClient.items` mit `[{type:"show",show:X},{type:"episode",show:X,episode:…}]` liefert heute zwei Einträge mit gleicher ID.
- **Gegenprüfung:** `TraktClient.items` (`:200`–`:206`) prüft nur auf die Schlüssel `movie`/`show`, nicht auf `type`. `applySyncQueue(_:_:)` (`App/Sources/AppModel+SyncQueue.swift:66`) wirkt nur auf die Merkliste und entdoppelt nicht. Die sichtbare Wirkung doppelter IDs in SwiftUI ist nur am Gerät klärbar; der Datenpfad ist belegt.

### A-B-10: Kit-Reihen mit „schon erschienen“ frieren das Datum des letzten Zerlegens ein
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Import/FusionImport.swift:283`, `Packages/PlayerCore/Sources/PlayerCore/Import/FusionImport.swift:139`, `App/Sources/FusionKitStore.swift:248`, `App/Sources/FusionKitStore.swift:59`
- **Szenario:** Eine Kit-Reihe mit `releaseStatus: "released"` bekommt beim Zerlegen der Kit-Datei den Filter `…date.lte = <heutiger Tag>`. Zerlegt wird nur beim App-Start, beim Einschalten des Kits, beim Wählen einer Reihe, beim Profilwechsel und in den Kit-Einstellungen. Läuft die App wochenlang, fragt die 24-h-Erneuerung des Katalogs weiter mit dem alten Stichtag: neu erschienene Titel fehlen in diesen Reihen, bis die App neu startet.
- **Ursache:** Das Datum wird beim Zerlegen in die Quelle eingebrannt (`f[key] = ctx.today`) statt beim Abruf gesetzt; `load` kehrt bei vorhandenem Inhalt und frischer Datei sofort zurück, und kein Anlass im laufenden Betrieb ruft `refresh()`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Platzhalter im Filter (z. B. `"$today"`), der in `TMDBClient.items`/`page` ersetzt wird, oder beim Aktivwerden nach Tageswechsel `refresh()` mit erneutem Zerlegen.
- **Test:** PlayerCore: `FusionImport.parse(…, now: Tag1)` liefert Filter mit Tag 1; ein Test „Abruf an Tag 2 nutzt Tag 2“ fehlt und würde heute scheitern.
- **Gegenprüfung:** Aufrufer von `refresh()` gezählt: `attach` (`:59`), `setEnabled` (`:103`), `choose` (`:120`), `ensureSettings` nach Profilwechsel (`:226`) und die Einstellungsseite; kein Timer, kein `didBecomeActive`. Der Filter landet über `FusionKitSync.apply` (`FusionKitCatalog.swift:205`) im Layout und wird von dort abgerufen. Zeile gegenüber dem Erstbericht präzisiert (283 statt 279). Titel korrigiert: maßgeblich ist das letzte Zerlegen, nicht zwingend der App-Start.

### A-B-11: Kalender holt die Staffel nicht, wenn die nächste Folge außerhalb des Fensters liegt, die letzte aber darin
- **Bereich:** Addons & Startseite
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Services/TMDBLocalized.swift:192`
- **Szenario:** Gestern liefen zwei Folgen einer Serie (Doppelfolge), die nächste ist erst in mehr als 14 Tagen angekündigt. `next` existiert, liegt aber nach `through` → `anchor = nil` → es bleibt bei `last_episode_to_air` und `next_episode_to_air`. Unter „Gestern“ (bzw. in „Heute neu“) steht nur die letzte der beiden Folgen. Ebenso, wenn die nächste Folge im Fenster liegt, aber zu einer anderen Staffel gehört als die gestrige Doppelfolge.
- **Ursache:** Der Zweig „letzte Folge ab `from`“ wird nur ohne nächste Folge geprüft:
  ```swift
  if let next = … { anchor = next.airDate <= (through ?? next.airDate) ? next : nil }
  else if let last = … { anchor = from.map { last.airDate >= $0 } == true ? last : nil }
  ```
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Beide Bedingungen unabhängig prüfen und bei Bedarf beide Staffeln holen (höchstens zwei Abrufe).
- **Test:** PlayerCore (`UpcomingTests`): Stub mit `last` = gestern (S1F9), `next` = +30 Tage, Staffel 1 mit F8 und F9 am gestrigen Tag → erwartet 2 Folgen, heute 1.
- **Gegenprüfung:** Der Doc-Kommentar (`TMDBLocalized.swift:185`–`186`) beschreibt die Regel genau so („oder, ohne nächste Folge, wenn die letzte ab `from` lief“); das Verhalten ist also dokumentiert, die Lücke aber nirgends begründet. Die vorhandenen Tests (`UpcomingTests.swift:93`–`95`, `:125`–`:136`) decken „nächste zu spät, ohne `from`“ und „keine nächste“ ab, nicht die Kombination. Knapp bestanden; seltener Fall mit kleiner Wirkung (eine fehlende Folge).

---

### F-A-6: Hinzufügen-Browser: Abschnitte über `\.offset` identifiziert, Zeilen wechseln beim Nachladen der Kit-Dateien die Identität
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/Home/AddRowBrowser.swift:126`, `App/Sources/Views/Home/AddRowBrowser.swift:42`, `Packages/PlayerCore/Sources/PlayerCore/Models/RowCatalog.swift:239`
- **Szenario:** „Reihe hinzufügen“ öffnen; beim Erscheinen startet `kit.refresh(all: true)`. Der Nutzer steht in der Gruppe „Fusion-Kit“ auf einem Eintrag. Eine neu eintreffende Kit-Datei fügt Themen-Abschnitte ein, sortiert nach Rang und Name, also auch vor dem Abschnitt mit dem fokussierten Eintrag. Dessen Abschnitt bekommt einen neuen Offset: die fokussierte Zeile wird im alten Container entfernt und im nächsten neu angelegt, der Fokus kann dabei verloren gehen.
- **Ursache:**
  ```swift
  ForEach(Array(g.sections.enumerated()), id: \.offset) { _, section in
  ```
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Identitätswechsel bestätigt, Fokusverlust folgt daraus nur wahrscheinlich)
- **Fix-Idee:** Abschnitte über einen stabilen Schlüssel identifizieren (Thema/Titel, `RowCatalogSection: Identifiable`), nicht über die Position.
- **Test:** PlayerCore: `RowCatalogSection` eine stabile ID geben und testen, dass sie beim Einfügen eines früheren Abschnitts gleich bleibt; am Gerät mit langsamem Kit-Server im Browser stehen bleiben.
- **Gegenprüfung:** Von „mittel“ auf „niedrig“ gesenkt (nur beim ersten Laden neuer Kit-Themen); die behauptete Folge „Menu springt auf die linke Spalte statt zu schließen“ gestrichen, das ist aus der rechten Spalte das gewollte Verhalten (`App/Sources/Views/Design/CategoryList.swift:105`).

### F-A-8: TabBarGuard: Seiten außerhalb des Pfads und der TorBox-Player lösen keine Prüfung aus und beginnen keinen neuen Besuch
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/TabBarGuard.swift:50`, `App/Sources/Views/TabBarGuard.swift:77`, `App/Sources/Views/TabBarGuard.swift:222`, `App/Sources/PlayerApp.swift:148`, `App/Sources/Views/TorBoxFilesRow.swift:75`, `Packages/PlayerCore/Sources/PlayerCore/Models/HomeTopEdge.swift:159`
- **Szenario:** Navigation „oben“. (1) Rückkehr aus dem Verwalter (`navigationDestination(item:)`), dem Hinzufügen-Browser, einer Einstellungs-Unterseite (`NavigationLink`) oder aus dem TorBox-Player (eigener `fullScreenCover`): keiner dieser Wege ändert `depth` oder ruft `check(.playerClosed)`; die Leiste wird dort nicht vorsorglich geprüft, sondern erst nach einem gescheiterten ▲ bzw. am oberen Rand der Startseite. (2) Wurden auf der Seite schon beide Schritte verbraucht (`lastRepair == .reshow`) und hängt die Leiste nach einem solchen Weg oder nach einem Tab-Wechsel erneut, liefert `TabBarRepair.next(after: .reshow)` `nil`: einmal „alle Reparaturen versucht“, danach weder Reparatur noch Log, bis ein Pop im Pfad oder die Quellenlisten-Wiedergabe den Stand zurücksetzt.
- **Ursache:** `lastRepair`/`loggedExhausted` werden nur bei `trigger.startsVisit` geleert; `visit(_:popped:)` setzt bei Tab-Wechsel nur den Seitennamen, und `popped` verlangt eine kleinere `NavigationPath`-Tiefe im selben Tab.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Logiklücke bestätigt; ob die Leiste auf diesen Wegen überhaupt hängen bleibt, ist offen)
- **Fix-Idee:** Jeden Wechsel der sichtbaren Seite als Besuch werten (Tab-Wechsel in `visit`, `onAppear` der Wurzelseiten für Rückkehr von Seiten außerhalb des Pfads) und `check(.playerClosed)` auch nach dem TorBox-Player aufrufen.
- **Test:** PlayerCore: Besuchslogik als reine Funktion (`startsVisit(old:new:)`) testen; am Gerät im Log „Leiste hängt weiter … alle Reparaturen versucht“ ohne vorangehende „Leiste hing fest“-Zeilen desselben Besuchs suchen.
- **Gegenprüfung:** `Packages/PlayerCore/Tests/PlayerCoreTests/HomeTopEdgeTests.swift:239`–`240` schreiben „Schritte je Besuch“ als gewollt fest, nicht aber, dass Tab-Wechsel und Seiten außerhalb des Pfads kein Besuch sind; von „mittel“ auf „niedrig“ gesenkt, weil das Versagen ein zweites Festhängen voraussetzt und ein erstes weiter über ▲ repariert wird.

### F-A-11: Ohne Hero gibt es keinen Startfokus-Anspruch
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/HomeHero.swift:309`, `App/Sources/Views/HomeHero.swift:316`, `App/Sources/Views/HomeView.swift:34`
- **Szenario:** Darstellung „Hero aus“ (oder keine Hero-Quelle), Navigation „Seitenleiste“ (Standard), Kaltstart. Laut Kommentar an `LaunchFocus` (`HomeHero.swift:356`) nimmt sich die Seitenleiste beim ersten Fokusdurchlauf den Fokus und klappt auf, `.defaultFocus` greift dabei nicht. Das Zurückholen (`claimLaunchFocus`) hängt allein an `HeroButtons`; im Layout ohne Hero ruft es niemand auf, und der Zweig hat auch kein eigenes `defaultFocus`. Die App startet mit Fokus in der Seitenleiste statt in der ersten Reihe. Derselbe Effekt, wenn der Hero beim Start wegfällt (F-A-4).
- **Ursache:** `.task { await claimLaunchFocus() }` existiert nur in `HeroButtons`; `LaunchFocus` wird außerhalb von `HomeHero.swift` nirgends verwendet.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Verhalten der Seitenleiste nur aus dem Code-Kommentar)
- **Fix-Idee:** Den Anspruch nach `HomeView` ziehen und je nach `HomeTopEdge` das oberste Element fokussieren (erste Reihe: gemerkte bzw. erste Kachel/Platzhalter 0; leere Seite: Aktionsknopf).
- **Test:** Am Gerät Hero ausschalten, App beenden, starten; im Log fehlt jede „fokus Start: …“-Zeile.
- **Gegenprüfung:** Suche nach `LaunchFocus`/`claimLaunchFocus` findet nur `HomeHero.swift`; nicht-Standard-Einstellung (Hero ist ab Werk an), daher „niedrig“ belassen.

### F-A-12: Diashow bleibt angehalten und der Hintergrund veraltet, wenn der Fokus die Reihen in Richtung Leiste oder unteren Knopf verlässt
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/HomeHero.swift:22`, `App/Sources/Views/HomeHero.swift:37`, `App/Sources/Views/HomeHero.swift:302`, `App/Sources/Views/HomeHero.swift:107`, `App/Sources/Views/RowViews.swift:70`, `App/Sources/Views/HomeView.swift:190`
- **Szenario:** Fokus auf einer Kachel (`inRows = true`), dann in die Seitenleiste bzw. Leiste oben oder ▼ bis auf „Reihen & Collections“. `inRows` bleibt `true`, weil nur die Hero-Knöpfe `leaveRows()` aufrufen. Der Hero zeigt weiter Bild und Info der zuletzt fokussierten Kachel, die Diashow steht, bis der Fokus einmal über „Abspielen“/„Details“ gelaufen ist. Wer die App in der Seitenleiste stehen lässt, sieht dauerhaft ein Standbild.
- **Ursache:** `HomeRowView` meldet den Fokusverlust nicht an `HomeFocus` (`onChange(of: focusedRoute)` kehrt bei `r == nil` nach `cancelRest` zurück); `FocusReportingButton` meldet nur an `topWatch`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** `HomeFocus` um „Fokus außerhalb von Reihen und Knopfzeile“ erweitern (z. B. über die Fokusmeldungen von `HomeTopEdgeWatch`) und dann nach kurzer Ruhe `leaveRows()` aufrufen.
- **Test:** Am Gerät Kachel fokussieren, in die Seitenleiste, 30 s warten; im Log erscheint kein Folienwechsel.
- **Gegenprüfung:** `leaveRows()` hat genau einen Aufrufer (`HomeHero.swift:303`); der Dateikopf verspricht die Pause nur, „solange der Fokus in den Reihen liegt“, das Verhalten weicht also vom dokumentierten ab und ist kosmetisch.

---

### F-B-3: Handy- und Login-Seite hängen an bedingten Zeilen, die ihr eigener Erfolg entfernt
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/Settings/ServiceSettings.swift:20`, `App/Sources/Views/Settings/ServiceSettings.swift:24`, `App/Sources/Views/Settings/ServiceSettings.swift:29`, `App/Sources/Views/Settings/FusionKitSettings.swift:37`, `App/Sources/Views/SyncLoginView.swift:55`, `App/Sources/AppModel.swift:146`
- **Szenario:** (a) Zeile „Trakt“ im Zustand `.missingClient` öffnet die Handy-Seite. Der Nutzer sendet Client ID und Secret und will weitere Schlüssel eintragen. Sobald beide gespeichert sind, wird der Zustand `.connectable`, der `switch` baut an der Stelle eine andere Zeile, die NavigationLink hinter der offenen Seite gibt es nicht mehr. Poppt SwiftUI die Seite, stoppt `onDisappear` den Server und weitere Eingaben am Handy schlagen fehl. Gleich bei „Trakt Client ID fehlt“ unter Fusion-Kit (dort reicht die ID allein). (b) Trakt-/Simkl-Login: `pollLogin` speichert das Token, die auslösende Link-Zeile wird durch eine `SettingsRow` ersetzt; die Seite schließt, bevor „Verbunden ✓“ zwei Sekunden steht.
- **Ursache:** Unterseiten sind View-NavigationLinks ohne Pfadeintrag, ihr Zustand lebt in der Zeile, und die Zeile steht in einem Zweig, den der Erfolg der Unterseite umschaltet:
  ```swift
  case .connectable: SettingsLinkRow(…) { SyncLoginView(service: s) }
  case .missingClient: PhoneLinkRow(section: .keys, …)
  ```
- **Schweregrad:** niedrig · **Sicherheit:** plausibel
- **Fix-Idee:** Eine Zeile mit stabiler Identität je Dienst, deren Ziel über `navigationDestination(item:)` außerhalb des Zweigs geöffnet wird; Wert und Detail nur als Parameter wechseln.
- **Test:** Am Gerät Trakt-ID und -Secret über die Zeile „Trakt“ senden und prüfen, ob die QR-Seite offen bleibt und eine zweite Eingabe ankommt.
- **Gegenprüfung:** Zweigwechsel und Zeilen belegt. Korrektur: `hasClient("trakt")` verlangt ID und Secret (`AppModel.swift:115`), der Wechsel kommt also erst mit beiden Werten. Ob der Wegfall der Link-Zeile die Seite poppt, ist reines SwiftUI-Verhalten und nur am Gerät sicher. Herabgestuft von mittel: selbst wenn es so kommt, ist die Folge eine zu früh geschlossene Seite, die mit einem Druck wieder offen ist; Teil (c) des Erstberichts (Fokus nach „Abmelden“) ist gestrichen, weil er nur ein unbestimmtes Fokusziel behauptet. Die Verzögerung durch `await syncRemoteProgress()` (`AppModel.swift:148`) stimmt, ist aber kein eigener Fehler.

### F-B-4: Folgentitel der Startstaffel bleiben unübersetzt, wenn die Seite gleich nach dem Laden verlassen wird
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/DetailViews.swift:250`, `App/Sources/Views/DetailViews.swift:266`, `App/Sources/Views/DetailViews.swift:196`, `App/Sources/Views/DetailViews.swift:287`, `App/Sources/AppModel.swift:461`
- **Szenario:** Serien-Detailseite, die Startstaffel ist Staffel 1 (neue Serie oder Stand in Staffel 1). Die Folgenliste erscheint, der Nutzer drückt innerhalb von etwa einer halben Sekunde OK auf einer Folge oder öffnet eine Unterseite. Nach der Rückkehr stehen Namen, Texte und Standbilder dieser Staffel in der Sprache des Addons, bis die Staffel gewechselt oder die Seite neu geöffnet wird.
- **Ursache:** `loaded = true` steht vor der Übersetzung, die als letzter Schritt an derselben abbrechbaren Aufgabe hängt:
  ```swift
  loaded = true                  // 250
  …
  await translateSeason()        // 266, nach 50 ms und applyFocus
  ```
  In der abgebrochenen Aufgabe scheitert `try? await tmdb.season(…)`, `localizedSeason` liefert `[:]` und cacht nichts; beim nächsten Erscheinen steigt `.task` in Zeile 196 sofort aus.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel
- **Fix-Idee:** Übersetzung in eine eigene `.task(id: season)` legen, die bei jedem Erscheinen prüft, ob die Staffel schon übersetzt ist.
- **Test:** Am Gerät Serie mit Stand in Staffel 1 öffnen, sofort OK auf der fokussierten Folge, zurück: Folgentitel prüfen; im Fern-Log fehlt die Erfolgszeile der TMDB-Staffel.
- **Gegenprüfung:** Eingeschränkt und herabgestuft. `season` startet mit 1 (`DetailViews.swift:52`); weicht die berechnete Startstaffel davon ab, löst Zeile 248 `.onChange(of: season)` aus, und dessen freie `Task` (Zeile 287) übersetzt unabhängig vom Abbruch. Der Fehler trifft also nur Staffel 1 als Startstaffel, in einem Fenster von rund 0,3 bis 0,7 s, und kostet eine Übersetzung für einen Seitenbesuch. Der Nebenbefund „Eintrittsfokus wird nie gesetzt“ ist gestrichen: in dem Fall hat der Nutzer die Seite schon verlassen, die Rückkehr regelt eigener Code.

### F-B-5: Neuaufbau der TabView startet den Autostart einer offenen Quellenliste erneut
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/DetailViews.swift:703`, `App/Sources/Views/DetailViews.swift:840`, `App/Sources/PlayerApp.swift:167`, `App/Sources/PlayerApp.swift:77`
- **Szenario:** Start-Tab: „Fortsetzen ab …“ oder „Sofort abspielen“ öffnet die Quellenliste mit Autostart, der Nutzer beendet den Player, die Liste bleibt im Stapel. Über die Leiste in die Einstellungen, Aussehen › Navigation umstellen (oder F-B-2). Die TabView entsteht neu, die Pfade bleiben, der `@State` der Seiten nicht. Zurück auf Start entsteht `StreamListView` mit `autostartDone == false` und startet die Wiedergabe von selbst.
- **Ursache:** Der Schutz gegen den zweiten Autostart ist `@State` der Seite, die Autostart-Absicht steckt dauerhaft in der Route im erhaltenen Pfad:
  ```swift
  let autostart = (request.resumeLastSource || request.bestChoice != nil) && playing == nil && !autostartDone
  ```
- **Schweregrad:** niedrig · **Sicherheit:** plausibel
- **Fix-Idee:** Verbrauchte Autostarts außerhalb der View merken (z. B. Kennung der Route im `AppModel`) oder die Route nach dem Start durch eine ohne Autostart ersetzen.
- **Test:** Am Gerät wie beschrieben; im Fern-Log erscheint nach dem Tab-Wechsel erneut „Autostart nach Push“.
- **Gegenprüfung:** Code stimmt: `styled` verzweigt per `if` (anderer Zweig = neue Identität), Pfade liegen in RootView (`PlayerApp.swift:63`–`67`), kein Merker außerhalb der View. Herabgestuft von mittel: nötig sind eine im anderen Tab offen gelassene Autostart-Liste und ein Wechsel der Navigationsart bzw. das erste Zusatzprofil, beides selten. Ob die Seiten eines nicht gewählten Tabs nach dem Neuaufbau sofort oder erst beim Wechsel entstehen, entscheidet nur, wann der Start kommt.

### F-B-6: „Build … installieren“ verschwindet beim Drücken unter dem Fokus
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/Settings/UpdatePage.swift:29`, `App/Sources/Views/Settings/UpdatePage.swift:34`, `App/Sources/Views/Settings/UpdatePage.swift:36`, `App/Sources/AppUpdater.swift:84`
- **Szenario:** System › App aktualisieren, Update gefunden, OK auf „Build N installieren“. `install` setzt `phase = .starting`; die Zeile steht nur im Zweig `.checked(.available)` und wird sofort entfernt, der Fokus springt auf eine andere Zeile. Nach einem Fehler (`.failed`) gibt es keine Installieren-Zeile, bis neu gesucht wurde.
- **Ursache:** Die Zeile hängt an genau der Phase, die ihre Aktion beendet; `.settingsUnavailable(updater.busy)` in Zeile 36 kann dadurch nie greifen:
  ```swift
  if case .checked(.available(let release, _)) = updater.phase {
  ```
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (Entfernen; Fokusziel abgeleitet)
- **Fix-Idee:** Das gefundene Release in eigenem Zustand halten und die Zeile auch in `.starting`, `.installing` und `.failed` zeigen (abgeschwächt bzw. als „Erneut versuchen“).
- **Test:** Am Gerät OK auf Installieren und Fokusziel beobachten; atvloadly kurz abschalten und prüfen, ob nach dem Fehler eine Installieren-Zeile bleibt.
- **Gegenprüfung:** Alle vier Zeilen stimmen; `phase = .starting` wird synchron im Druck gesetzt. Kein Guard, kein Kommentar zu einer bewussten Entscheidung.

### F-B-7: Personenseite: Fehlerzustand wird nie zurückgesetzt
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/PersonView.swift:55`, `App/Sources/Views/PersonView.swift:48`, `App/Sources/Views/PersonView.swift:31`, `App/Sources/Views/PersonView.swift:32`
- **Szenario:** Personenseite lädt, der Nutzer wechselt über die Leiste den Tab (Aufgabe abgebrochen, der Abruf wirft, `failed = true`) oder der erste Abruf scheitert am Netz. Beim nächsten Erscheinen läuft `.task` neu (`person == nil`) und gelingt. Die Seite zeigt Foto, Biografie und Filmografie und zusätzlich „Person konnte nicht geladen werden.“ samt „Zurück“.
- **Ursache:** `failed` wird nur gesetzt, ein Abbruch zählt als Fehler:
  ```swift
  } catch {
      failed = true
  ```
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Zu Beginn der Aufgabe `failed = false`; eine abgebrochene Aufgabe nicht als Fehler werten.
- **Test:** Am Gerät Personenseite öffnen, sofort Tab wechseln und zurück; im Fern-Log „laden fehlgeschlagen“ gefolgt von der Erfolgszeile.
- **Gegenprüfung:** `failed` hat keine Stelle, die es auf `false` setzt; `personCredits` wirft bei Abbruch (`TMDBPerson.swift:18`). Der Fall „TMDB-Schlüssel fehlt“ aus dem Erstbericht gehört nicht dazu (ohne Schlüssel gelingt auch der zweite Lauf nicht).

### F-B-8: Genre-Seite: `retrying` gilt für alle Filter und bleibt nach Filterwechsel stehen
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/GenrePageView.swift:33`, `App/Sources/Views/GenrePageView.swift:160`, `App/Sources/Views/GenrePageView.swift:214`, `App/Sources/Views/GenrePageView.swift:230`, `App/Sources/Views/GenrePageView.swift:242`
- **Szenario:** Filme: ein Block scheitert, „Erneut versuchen“ gedrückt (`retrying = true`). Vor der Antwort wechselt der Nutzer auf Serien. Die Antwort für Filme setzt `retrying` nicht zurück (`f == filter` ist in beiden Zweigen falsch). Beim nächsten Nachladen im Serien-Raster steht statt des stillen Spinners ein fokussierbarer Knopf „Erneut versuchen“ mit Spinner; liegt der Fokus darauf, springt er beim Eintreffen des Blocks auf den ersten neuen Titel.
- **Ursache:** Ein `Bool` für die ganze Seite, zurückgesetzt nur für den sichtbaren Filter:
  ```swift
  if retrying, f == filter { retrying = false … }
  ```
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** `retrying` je Filter führen (`Set<GenreFilter>`) oder in `GenrePaging` aufnehmen.
- **Test:** In PlayerCore testbar, sobald der Merker in `GenrePaging` liegt (retry → Antwort → `footer`); sonst am Gerät mit getrenntem Netz.
- **Gegenprüfung:** Zeilen stimmen. Der Zustand heilt sich mit dem ersten Block des neuen Filters selbst (Zeile 230), die Wirkung ist ein einmalig falscher Fußbereich; niedrig ist richtig.

### F-B-9: Zeilen, die ihre eigene Aktion entfernt (Icon-Satz, Profil löschen)
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/Views/Settings/SourceSettingsRows.swift:37`, `App/Sources/Views/Settings/SourceSettingsRows.swift:39`, `App/Sources/Views/Settings/ProfileSettings.swift:39`, `App/Sources/Views/Settings/ProfileSettings.swift:65`
- **Szenario:** (a) Aussehen › Bewertungs-Icon-Satz › „Eingebaute Plaketten verwenden“: OK setzt die Adresse auf nil, die fokussierte Zeile verschwindet (`if current != nil`). (b) Zwei Profile, „Profil … löschen …“ bestätigt: der Fokus kehrt auf die Zeile zurück, dann läuft die Aktion, `hasMultipleProfiles` wird falsch, die Zeile wird entfernt. tvOS wählt ein neues Ziel; welches, ist nicht festgelegt.
- **Ursache:** Bedingte Zeile ohne Fokus-Umzug vor der Aktion. An anderer Stelle macht der Code es ausdrücklich richtig (`focus = .size` vor dem Zurücksetzen, `App/Sources/Views/Settings/SubtitleStyleSettingsRows.swift:55`; „Filter aufheben“, `App/Sources/Views/DetailViews.swift:1033`).
- **Schweregrad:** niedrig · **Sicherheit:** plausibel
- **Fix-Idee:** Vor der Aktion den Fokus per `@FocusState` auf eine bleibende Zeile setzen oder die Zeile abgeschwächt stehen lassen (`settingsUnavailable`).
- **Test:** Am Gerät beide Wege; prüfen, ob der Fokus in der rechten Spalte bleibt.
- **Gegenprüfung:** Das Entfernen ist belegt, ein Schaden nicht: tvOS setzt den Fokus beim Wegfall meist auf einen Nachbarn. Sicherheit deshalb von „bestätigt“ auf plausibel gesenkt; bleibt nur als Abweichung vom sonst im Projekt geübten Muster stehen.

### F-B-10: Profilwechsel lässt offene Seiten anderer Tabs mit dem Stand des alten Profils stehen
- **Bereich:** Fokus & Navigation
- **Ort:** `App/Sources/AppModel.swift:252`, `App/Sources/PlayerApp.swift:63`, `App/Sources/Views/DetailViews.swift:196`, `App/Sources/Views/DetailViews.swift:466`
- **Szenario:** Mindestens zwei Profile. Start-Tab mit offener Film-Detailseite (Profil A, „Sofort abspielen anzeigen“ an). In den Einstellungen auf Profil B wechseln, zurück auf Start. Die Seite lädt nicht neu (`loaded`) und zeigt Technik-Plaketten, Bewertungen, Texte in der Sprache von A sowie die Karte „Sofort abspielen“ mit einer Quelle aus den Addons von A.
- **Ursache:** `switchProfile` leert die Caches, aber nicht die Navigationspfade; die Seiten halten ihren Stand in `@State`:
  ```swift
  guard let all = list ?? model.cachedStreams(id: id) else { return }   // alte Wahl bleibt
  ```
- **Schweregrad:** niedrig · **Sicherheit:** plausibel
- **Fix-Idee:** Beim Profilwechsel die Pfade der anderen Tabs leeren oder die Stacks mit `.id(profile.id)` neu aufbauen.
- **Test:** Am Gerät wie beschrieben; Karte und Plaketten vor und nach dem Wechsel vergleichen.
- **Gegenprüfung:** `switchProfile` (`App/Sources/AppModel.swift:252`–`268`) fasst keinen Pfad an, RootView beobachtet den Profilwechsel nicht. Die Wirkung bleibt Anzeige: ein Druck auf die alte Karte führt in die Quellenliste, die mit den Addons von B neu lädt und die Wahl neu trifft (`DetailViews.swift:872`–`873`), es spielt also nichts Falsches. Beim ersten Zusatzprofil tritt der Fall nicht auf (F-B-2 baut dann ohnehin alles neu).

### S-7: `POST /sync/history` wird nach Netzfehler blind wiederholt → doppelte Verlaufseinträge
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:44`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:51`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:105`, `App/Sources/AppModel+SyncQueue.swift:159`
- **Szenario:** „Als gesehen markieren“ für eine Serie. Der Dienst verarbeitet die Anfrage, die Antwort geht verloren (Zeitüberschreitung). `apply` liefert `.retry`, der nächste Durchlauf sendet dieselbe Anfrage erneut. Legt der Dienst bei jedem `POST /sync/history` neue Wiedergaben an, entsteht für jede Folge ein zweiter Eintrag.
- **Ursache:** Jeder geworfene Fehler wird zu `.retry` (`catch { return .retry }`), ebenso Status 0, 408 und 5xx (`SyncQueue.swift:195`), ohne zu unterscheiden, ob die Anfrage den Dienst erreicht haben kann. Der Body enthält kein `watched_at`. Für Merkliste und Entfernen ist die Wiederholung unschädlich.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Verhalten des Dienstes nicht geprüft)
- **Fix-Idee:** `markWatched` mit festem `watched_at` (= `createdAt` der Änderung) senden oder vor einer Wiederholung prüfen, ob der Titel schon im Verlauf steht.
- **Test:** PlayerCore: Sender, der beim ersten Aufruf wirft und beim zweiten 201 liefert; Body beider Anfragen vergleichen (heute identisch, ohne `watched_at`).
- **Gegenprüfung:** Codepfad bestätigt, Body bestätigt (`SyncWrites.swift:6-10`). Herabgestuft von mittel auf niedrig: seltener Auslöser (verlorene Antwort), Folge sind doppelte Zähler beim Dienst, kein Verlust.

### S-8: Warteschlange: ein dauerhaft scheiternder Teilschritt zählt als „später erneut“ und blockiert alle jüngeren Änderungen des Dienstes
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:47`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:51`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:75`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SyncWrites.swift:111`, `App/Sources/AppModel+SyncQueue.swift:162`
- **Szenario:** Die älteste Änderung für einen Dienst ist „aus Weiterschauen entfernen“ (Trakt, Simkl) oder „auf die Merkliste“ (Simkl). Der vorgeschaltete Abruf (`/sync/playback` bzw. `/sync/all-items/…`) scheitert jedes Mal – dauerhafter 4xx, unlesbare Antwort, wiederkehrende Zeitüberschreitung bei großer Bibliothek. `apply` macht daraus `.retry`, die Schleife bricht für diesen Dienst ab. Alle später angelegten Änderungen werden bis zu 30 Tage lang nicht gesendet, weil die älteste immer zuerst drankommt. Der Nutzer erfährt davon nichts außer im Log.
- **Ursache:** `SyncWriteResult.classify` greift nur für die eigentliche Schreibanfrage. Fehler in Teilschritten werden pauschal zu `.retry`; es gibt keinen Versuchszähler und kein Überspringen (`if r == .retry { break }`).
- **Schweregrad:** niedrig · **Sicherheit:** Codepfad bestätigt, Auslöser plausibel
- **Fix-Idee:** Geworfene `APIError.status` durch `classify` schicken; bei einem dauerhaften Fehler zur nächsten Änderung weitergehen und nur bei Netzfehler oder 429 abbrechen.
- **Test:** PlayerCore: `TraktClient.apply(.removeFromContinue)` mit 403 auf `/sync/playback` → erwartet `.rejected(403)`, heute `.retry`.
- **Gegenprüfung:** Reihenfolge „älteste zuerst“ (`SyncQueue.swift:129-131`) und Abbruch bestätigt; Ablauf nach 30 Tagen über `prune` (`SyncQueue.swift:108`). Herabgestuft von mittel auf niedrig: Ein dauerhafter Fehler, der nur den Lesezugriff trifft, während Schreibanfragen durchgingen, ist selten; bei einer widerrufenen Anmeldung (401) scheitern ohnehin alle Änderungen. Gestrichen: der Vorwurf, ein 403 auf die Schreibanfrage werde endgültig verworfen – das ist laut Kommentar gewollt („other 4xx; stop asking“, `SyncQueue.swift:186`) und wird als Fehler geloggt.

### S-11: Unlesbare Fortschrittsdatei wird stillschweigend durch ein leeres Buch ersetzt
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:138`, `App/Sources/AppModel.swift:60`, `App/Sources/AppModel.swift:78`, `App/Sources/AppModel.swift:266`
- **Szenario:** `progress-<id>.json` enthält einen Eintrag, den der Decoder ablehnt (neueres Format nach einem Rückschritt, ein fehlendes Pflichtfeld, ein Datum in anderem Format). `load` liefert ein leeres Buch. Die nächste Fortschrittsmeldung – 10 s nach Wiedergabestart – speichert es; Verlauf und „Weiterschauen“ des Profils sind überschrieben. Kein Log, keine Kopie.
- **Ursache:**
  ```swift
  return (try? dec.decode(ProgressBook.self, from: d)) ?? ProgressBook()
  ```
  Anders als `ProfileStore` (`.bak`), `SyncQueueStore` (`failed`-Rückruf) und `PlayerMemory` (Log-Zeile) gibt es hier weder Sicherung noch Meldung. `WatchProgress` hat einen synthetisierten Decoder, `MetaPreview` verlangt eine nicht leere `id` (`Packages/PlayerCore/Sources/PlayerCore/Addons/StremioModels.swift:235`): Ein einzelner fehlerhafter Eintrag verwirft das ganze Buch. `ProgressBook.schemaVersion` wird nie geprüft.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Einträge einzeln dekodieren (fehlerhafte überspringen); bei Totalausfall Rohdaten beiseitelegen und loggen.
- **Test:** PlayerCore: Datei mit einem gültigen und einem Eintrag ohne `updated` schreiben → `load` soll den gültigen behalten (heute: leer).
- **Gegenprüfung:** Pfad bestätigt. Herabgestuft von mittel auf niedrig: Im aktuellen Build wurde kein Weg gefunden, einen nicht wieder lesbaren Eintrag zu schreiben – Datumsformat beim Schreiben und Lesen gleich (`WatchProgress.swift:137`, `:142`), alle `MetaPreview`-Erzeuger liefern eine nicht leere ID, nicht endliche Zahlen lassen das Kodieren scheitern, statt eine kaputte Datei zu erzeugen. Offen bleibt das Hin-und-zurück von `Date.distantPast` (siehe „Am Gerät prüfen“ Nr. 8); bestätigt es sich als Lesefehler, steigt der Befund auf hoch.

### S-12: Sicherung wiederherstellen übernimmt alte OAuth-Tokens und setzt den Laufzeit-Zustand nicht zurück
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/AppModel.swift:587`, `App/Sources/AppModel.swift:590`, `App/Sources/AppModel.swift:556`
- **Szenario 1 (veraltete Tokens):** Eine Sicherung, die älter ist als die letzte Trakt-Erneuerung, enthält ein bereits verbrauchtes Erneuerungstoken. Wiederherstellen auf demselben Gerät ersetzt das gültige Token durch das alte; ab der nächsten Erneuerung meldet Trakt Fehler, eine Neuanmeldung ist nötig.
- **Szenario 2 (laufender Zustand):** `importBackup` ersetzt `stored` direkt, ohne den Weg von `switchProfile`: Quellen-Cache, laufende Suchen, `HeroDetailsCache`, `AddonMetaCache` und Vorlader bleiben vom alten Stand stehen; `restoreCatalogSnapshot()` und `syncRemoteProgress()` laufen nicht. Bis zum nächsten Start oder Profilwechsel kann die App Quellen von Addons zeigen, die das eingespielte Profil nicht mehr hat.
- **Ursache:** `importBackup` ruft nur `save()`, `clearCatalogCache()`, `removeCatalogFiles` und lädt den Fortschritt (`AppModel.swift:588-593`); `switchProfile` setzt dagegen zehn weitere Zustände zurück (`:255-267`).
- **Schweregrad:** niedrig · **Sicherheit:** Szenario 2 bestätigt, Szenario 1 plausibel (setzt Token-Rotation des Dienstes voraus)
- **Fix-Idee:** Nach dem Einspielen denselben Rücksetz-Weg wie beim Profilwechsel durchlaufen; für Profile mit gleicher ID das jüngere Token behalten.
- **Test:** Am Gerät: sichern, Trakt-Token erneuern lassen, wiederherstellen, im Log „Trakt-Erneuerung fehlgeschlagen“ suchen. In PlayerCore nicht testbar (Logik liegt in `AppModel`).
- **Gegenprüfung:** Herabgestuft von mittel auf niedrig und gekürzt. Gestrichen: „Sicherung enthält nur die Profile“ – die Handy-Seite beschriftet den Export als „Alle Profile herunterladen“ und das Einspielen als „ersetzt alle Profile!“ (`Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:191-192`); dass Fortschritt und Verlauf fehlen, ist Funktionsumfang und kein Fehler. Gestrichen: `backupData()` liefere leere Daten – das Kodieren eines gültigen `StoredProfiles` scheitert nur bei einer nicht endlichen `addonTimeout`, wofür kein Weg belegt ist.

### S-13: `merge(remote:)` ersetzt den lokalen Eintrag samt Titel und Bildern durch den Stand des Dienstes, sobald dieser jünger ist
- **Bereich:** Sync & Profile
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:116`, `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:121`, `Packages/PlayerCore/Sources/PlayerCore/Sync/TraktClient.swift:211`
- **Szenario:** Film bei 40 % verlassen. Lokal wird `updated = jetzt` gespeichert, danach geht `stop` an den Dienst; dieser setzt `paused_at` auf seine Empfangszeit, also später. Beim nächsten Abruf gilt der Stand des Dienstes als neuer und ersetzt den lokalen Eintrag vollständig, einschließlich `item`. Die Kachel in „Weiterschauen“ trägt danach den Titel aus dem Dienst, das Metahub-Poster, kein Logo und keine Beschreibung statt der lokalisierten Angaben.
- **Ursache:** `if let l = entries[r.id], l.updated >= r.updated { continue }` vergleicht ohne Toleranz; der Ersatz übernimmt `item: r.item` statt nur Position und Zeit.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Codepfad bestätigt; ob die Startseite den Titel anschließend wieder lokalisiert, wurde nicht verfolgt)
- **Fix-Idee:** Beim Zusammenführen das vorhandene `item` behalten, wenn es dieselbe ID hat; kleine Toleranz beim Zeitvergleich (wie `SyncQueue.clockTolerance`).
- **Test:** PlayerCore: lokaler Eintrag mit deutschem Namen, Remote-Eintrag 1 s jünger mit englischem Namen → nach `merge` soll der Name unverändert sein.
- **Gegenprüfung:** Bestätigt am Code; die Tests (`SyncTests.swift:99-106`, `SyncQueueTests.swift:155`) prüfen Position und Vorrang, nicht den Erhalt von `item`. Korrektur am Erstbericht: Der Fall tritt nicht nur bei „Sekundenbruchteilen“ auf, sondern immer, wenn der Dienst den `stop` nach der letzten lokalen Speicherung verbucht – das ist der Normalfall. Rein kosmetisch, daher niedrig.

### S-15: Gerätelogin bricht bei vorübergehenden Serverfehlern mit irreführender Meldung ab
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/Views/SyncLoginView.swift:60`, `Packages/PlayerCore/Sources/PlayerCore/Sync/TraktClient.swift:104`, `Packages/PlayerCore/Sources/PlayerCore/Sync/SimklClient.swift:39`
- **Szenario:** Während der Nutzer den Code am Handy eingibt, antwortet Trakt einmal mit 502/503 oder Simkl mit 429. `poll` liefert `.failed`, die Seite zeigt „Fehler 502 – Client ID/Secret prüfen.“ und fragt nicht weiter; der Nutzer muss die Seite schließen und mit neuem Code beginnen.
- **Ursache:** `default: return .failed(s)` bzw. `return s == 404 ? .expired : .failed(s)` unterscheiden nicht zwischen dauerhaft und vorübergehend; die Ansicht beendet die Schleife bei `.failed`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** 5xx, 429 (Simkl) und 0 wie `.pending`/`.slowDown` behandeln; nur 401/403 als Schlüsselfehler melden.
- **Test:** PlayerCore: `TraktClient.poll` mit Status 503 → erwartet „weiter warten“, heute `.failed(503)`.
- **Gegenprüfung:** Bestätigt. Geworfene Netzfehler sind dagegen abgefangen (`AppModel.swift:142` liefert `.pending`). Die Tests decken `pending`, `slowDown`, `success`, `expired` ab (`SyncTests.swift:26-31`, `:86-87`), 5xx nicht. Gestrichen: „jede 400 gilt als wartet“ – das entspricht der Bedeutung, die der Code dem Status bewusst gibt (`TraktClient.swift:100`).

### S-16: Abgleich mit Trakt/Simkl läuft nur bei Start, Login und Profilwechsel
- **Bereich:** Sync & Profile
- **Ort:** `App/Sources/PlayerApp.swift:10`, `App/Sources/AppModel.swift:148`, `App/Sources/AppModel.swift:267`, `App/Sources/Playback/PlaybackStability.swift:49`, `App/Sources/AppModel+CatalogCache.swift:34`, `Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:114`
- **Szenario:** Die App bleibt tagelang im Speicher. Am Handy weitergeschaute Folgen erscheinen erst nach einem echten Neustart in „Weiterschauen“. Eine wegen Netzausfall wartende Kachel-Änderung wird erst beim nächsten Start oder bei der nächsten Kachel-Aktion gesendet. Außerdem fügt `merge` nur hinzu: Ein anderswo zu Ende geschauter Titel fehlt im Abruf, bleibt lokal aber als angefangen stehen.
- **Ursache:** `syncRemoteProgress()` hat genau drei Aufrufer; `networkChanged` und der `didBecomeActive`-Beobachter rufen weder ihn noch `processSyncQueue()`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Beim Zurückkehren in die App (mit Mindestabstand) und bei „Netz wieder da“ `syncRemoteProgress()` aufrufen; lokale, nicht fertige Einträge aus einem früheren Abruf entfernen, wenn sie im aktuellen fehlen.
- **Test:** Am Gerät: App im Hintergrund lassen, am Handy über Trakt eine Folge anfangen, App wieder öffnen – Log zeigt keine Zeile „trakt: N angefangene Titel geholt“.
- **Gegenprüfung:** Aufruferliste per Suche bestätigt (drei für `syncRemoteProgress`, dazu `perform` für `processSyncQueue`). Der Kommentar in `AppModel+CatalogCache.swift:32` hält selbst fest, dass tvOS Apps selten beendet, und löst das nur für Kataloge. Kein Datenverlust, daher niedrig.

### W-A-4: Fortsetzen nach Anteil (Trakt/Simkl) kann bei einem Fehler direkt nach dem Start verloren gehen
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:376-381`, `App/Sources/Views/PlayerScreen.swift:222`, `App/Sources/Views/PlayerScreen.swift:737`
- **Szenario:** Der Titel hat nur einen Stand aus dem Sync-Dienst (`start == nil`, `startFraction == 0.6`). Die Laufzeit kommt, der Sprung auf 60 % wird abgesetzt. Bevor dort eine Sekunde gespielt wurde, wiederholt die Leiter den ganzen Start oder lädt per Rückfall-`load` neu. Der Film beginnt bei 0; nach 10 s überschreibt `saveProgress` den Stand, die Fortsetz-Stelle ist weg (lokal und per Scrobble).
- **Ursache:** `fractionApplied` wird beim ersten Sprung gesetzt und nie zurückgesetzt; der wiederholte `loadAndStart` lädt mit `start == nil`, und der Neuladen-Zweig nimmt `lastGoodTime > 0 ? lastGoodTime : (start ?? 0)`.
  ```swift
  guard d > 0, !fractionApplied, start == nil, let f = startFraction else { return }
  fractionApplied = true
  ```
- **Schweregrad:** niedrig · **Sicherheit:** plausibel
- **Fix-Idee:** Das Sprungziel (`f * d`) merken und als Startstelle für jede Wiederholung verwenden; `fractionApplied` in `stabilityLoadBegins` zurücksetzen.
- **Test:** Die Startstellen-Wahl für Wiederholungen nach PlayerCore ziehen (`PlayerStartChoice`) und den Fall „Anteil angewandt, dann Neustart“ testen.
- **Gegenprüfung:** Der Fehler im App-Code stimmt: `fractionApplied` hat genau eine Schreibstelle (379), kein Rücksetzen. Herabgesetzt wurde aus zwei Gründen. Erstens ist das Fenster schmal: Sobald nach dem Sprung ein Takt gespielt wurde, hält `lastGoodTime` (Zeile 336) die Stelle. Zweitens hängt jeder der beiden Wege von der Engine ab – der ganze Neustart nur, wenn die Laufzeit schon vor dem Ende von `load` bekannt ist, der Rückfall-`load` nur, wenn `engine.recover()` wirft. Beim Weg aus W-A-1 (Fehler vor bekannter Laufzeit) greift der Anteil-Sprung dagegen noch. Verwandt und ebenfalls nur plausibel: Jeder `saveProgress` mit bekannter Laufzeit vor Ankunft des Sprungs (Verlassen oder Quellenwechsel in der ersten Sekunde) ersetzt den Eintrag durch eine Stelle unter einer Minute; danach liefern `resumeFraction` und `resumePosition` beide nil (`Packages/PlayerCore/Sources/PlayerCore/Progress/WatchProgress.swift:108-109`, `:70-71`).

### W-A-5: URL-Fehler unter AVFoundation −11800 wird nie ausgewertet; Transportfehler außerhalb der sieben Codes gelten als `.unknown` und werden 8 h gemerkt
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Playback/PlaybackFailureMapping.swift:17-18`, `Packages/PlayerCore/Sources/PlayerCore/Playback/PlaybackRecovery.swift:143`, `Packages/PlayerCore/Sources/PlayerCore/Playback/PlaybackRecovery.swift:160-168`, `Packages/PlayerCore/Sources/PlayerCore/Playback/FailedLinks.swift:62`
- **Szenario:** Das Internet fällt aus, das WLAN steht (Netzpfad bleibt „satisfied“, also keine Einordnung `.offline`). Kommt der Abriss als AVFoundation-Fehler −11800 an oder mit einem anderen als den sieben gelisteten URL-Codes, lautet die Einordnung `.unknown`: einmal neu laden, dann nächste Quelle. Jede so weitergeschaltete Quelle gilt 8 h als fehlgeschlagen und wird von der automatischen Wahl übersprungen, obwohl sie in Ordnung ist.
- **Ursache:** `PlaybackFailure.underlyingURLCode` wird in der App nie gesetzt, der dafür gebaute Zweig ist tot:
  ```swift
  return PlaybackFailure(kind: i.kind.rawValue, domain: i.underlyingDomain, code: i.underlyingCode,
                         ffmpegCode: i.ffmpegErrorCode, message: i.message)   // ohne underlyingURLCode
  ```
  Dazu kennt `urlClass` nur wenige Codes der Domäne `NSURLErrorDomain`; alles andere fällt auf `.unknown`, und `remembers(.unknown)` ist true.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt für den toten Zweig; plausibel für die Folge (welche Domänen und Codes die Engine bei einem Abriss liefert, zeigt nur das Gerät)
- **Fix-Idee:** `underlyingURLCode` im Backend füllen (oder den Zweig streichen), POSIX-Fehler und weitere URL-Codes als `.network` einordnen und `.unknown` nur merken, wenn die Quelle nie ein erstes Bild hatte.
- **Test:** PlayerCore-Test für `classify` mit `NSPOSIXErrorDomain`/54 und `NSURLErrorDomain`/−1017; im Fern-Log nach „Fehler eingeordnet: unknown (…)“ während eines Internet-Ausfalls suchen.
- **Gegenprüfung:** Suche über das ganze Repo: `underlyingURLCode` wird nur in der Typdefinition, im Klassifizierer und in einem Test gesetzt (`Packages/PlayerCore/Tests/PlayerCoreTests/PlaybackRecoveryTests.swift:49`), nie im App-Code – der Test prüft also einen Weg, den die App nicht erreicht. Dass `.unknown` gemerkt wird, ist eine bewusste Entscheidung (Kommentar `FailedLinks.swift:57-59`: Fehler „an der Quelle selbst“); der Befund betrifft nur Netzfehler, die fälschlich dort landen. Die üblichen Codes (−1001, −1005, −1009, −1003, −1004, −1006) sind abgedeckt, deshalb von mittel auf niedrig herabgesetzt. Der Erstbericht nannte `PlayerScreen.swift:694` als Ort; das ist nur die Weitergabe des Urteils und wurde durch die Stelle der Ursache ersetzt.

### W-A-6: Plattencache – eine Leseposition für alle Verbindungen
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Playback/DiskCacheProxy.swift:699-701`, `App/Sources/Playback/DiskCacheProxy.swift:264-275`, `App/Sources/Playback/DiskCacheProxy.swift:423-430`, `App/Sources/Playback/XRayProfile5.swift:7`
- **Szenario:** Plattencache an. Die Engine liest den Film über Verbindung A. Ein zweiter Leser auf derselben Adresse (laut Kommentar in `XRayProfile5.swift:7` ist die Standbild-Leiter ein „second reader on the source“) fragt entfernte Stellen an. Jede Anfrage ab 4 MiB, auch eine offene `bytes=X-`, setzt `readPosition` um, und jedes gesendete 512-KiB-Stück setzt sie erneut. Der Vorlauf springt dann zwischen beiden Stellen, die Verdrängung rechnet von der jeweils letzten, und solange der zweite Leser auf einen Block wartet, startet kein Vorlauf.
- **Ursache:** `readPosition` ist ein einzelner Wert der Sitzung; `beginRead(at:)` und `noteRead` unterscheiden die Verbindungen nicht.
  ```swift
  let moves = Int64(bytes.count) >= policy.blockSize
  if moves { await s.beginRead(at: bytes.lowerBound) }
  ```
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (ob und wie groß der zweite Leser anfragt, ist Verhalten der Engine)
- **Fix-Idee:** Leseposition je Verbindung führen und den Vorlauf an der Verbindung ausrichten, die fortlaufend die meisten Bytes zieht.
- **Test:** Die Regel „welche Verbindung bestimmt die Leseposition“ als Typ nach `DiskCache.swift` ziehen und mit zwei abwechselnden Lesern testen; am Gerät die Zeile „Plattencache geschlossen · …“ mit Dolby-Vision-Profil-5-Quelle (Leiter aus) und anderer Quelle (Leiter an) vergleichen.
- **Gegenprüfung:** Der Aufbau ist belegt: ein Zähler je Sitzung, kein Bezug zur Verbindung, und die Bedingung `readerFetches == 0` in `pump()` gilt für jeden Leser. Der Entwurf geht erkennbar von einem Leser plus kleinen Proben aus (Kommentar Zeile 263). Herabgesetzt von mittel auf niedrig: Die Wirkung ist schlechtere Cache-Ausnutzung in einer abschaltbaren Zusatzfunktion, kein Fehlbild; ohne Messung ist die Größe offen. Dass jeder kleine Zugriff einen ganzen Block kostet, ist Entwurf und kein Teil des Befunds mehr.

### W-A-7: Abbruch während der Cache-Probe sperrt die Quelle für den Cache
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Playback/DiskCacheProxy.swift:539-544`, `App/Sources/Playback/DiskCacheProxy.swift:498-501`, `App/Sources/Playback/DiskCacheProxy.swift:100-111`
- **Szenario:** Plattencache an. Der Nutzer startet einen Film und drückt in den ersten Sekunden Menü (die Probe lädt gerade Block 0, Grenze 13 s). Startet er dieselbe Quelle mit derselben Adresse erneut, läuft sie bis zum App-Neustart ohne Cache; im Log steht „Quelle schon einmal am Plattencache gescheitert“.
- **Ursache:** Der Task-Abbruch beendet den Abruf mit einem Fehler, der im allgemeinen `catch` von `route` landet; dieser trägt die Adresse in `failedOrigins` ein, ohne Abbruch von echtem Scheitern zu trennen.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Im `catch` bei `Task.isCancelled`, `CancellationError` oder URL-Fehler −999 nicht in `failedOrigins` eintragen.
- **Test:** Am Gerät: Film mit Cache starten, sofort zurück, erneut starten; Fern-Log-Kategorie „cache“ prüfen.
- **Gegenprüfung:** Kette vollständig im Repo: Menü vor dem ersten Bild führt zu `leaveWithModeSwitch` → `orderlyExit` bricht `loadTask` ab (`App/Sources/Views/Player/PlayerExit.swift:46`). `route` läuft in genau diesem Task (`App/Sources/Playback/XRayProfile5.swift:48`), der Abbruch erreicht `withTaskCancellationHandler` (Zeile 100-111), `open` wirft, der `catch` (539-544) trägt die Adresse ein. Kein Guard dazwischen. `failedOrigins` wird nirgends geleert. Niedrig stimmt: Es fehlt nur der Cache, die Wiedergabe läuft direkt.

### W-A-9: Fehlerleiter zählt Pufferzeit als gesunde Spielzeit
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:336`, `App/Sources/Views/Player/PlayerStability.swift:90`, `Packages/PlayerCore/Sources/PlayerCore/Playback/PlaybackRecovery.swift:218-222`
- **Szenario:** Wackelige Quelle: Fehler → neu laden → danach überwiegend Nachpuffern (jeweils unter 25 s, also kein Wächter). Nach 120 Takten setzt sich die Leiter zurück, obwohl kaum gespielt wurde; das Budget von vier Versuchen und der Schritt „nächste Quelle“ greifen dann später oder nie.
- **Ursache:** `notePlaying()` prüft nur `isPlaying` und `errorText`; die „stabil“-Zählung direkt daneben schließt `buffering` aus.
  ```swift
  if engine.isPlaying, engine.errorText == nil { lastGoodTime = engine.currentTime; recoveryPlan.notePlaying() }
  ```
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (unter der im Repo dokumentierten Annahme, dass der Zustand beim Nachpuffern „spielt“ bleibt, `PlayerStability.swift:9`)
- **Fix-Idee:** `notePlaying()` nur rufen, wenn `!engine.loadActivity.buffering`, wie in `stabilityTick`.
- **Test:** Am Gerät/Fern-Log prüfen, ob „Versuch n/4“ nach langen Pufferphasen wieder bei 1 beginnt.
- **Gegenprüfung:** Beide Zählungen gelesen; der Unterschied ist eindeutig. Die Doku des Planers verlangt „echt gespielte Sekunden“ (`PlaybackRecovery.swift:172-173`). Kein Test deckt den Aufrufer ab (View-Code). Niedrig stimmt: nötig ist eine Quelle, die zwei Minuten lang puffert, ohne einen Fehler oder den Wächter auszulösen.

### W-A-10: Profil-5-Gedächtnis – der Schlüssel enthält den Pfad
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Playback/XRayProbe.swift:79-83`, `App/Sources/Playback/XRayProfile5.swift:21-34`, `App/Sources/Playback/XRayProfile5.swift:50-51`
- **Szenario:** Dolby-Vision-Profil-5-Film über einen Dienst, dessen Link das wechselnde Token im Pfad trägt. Der Schlüssel ändert sich bei jedem Auflösen, die Quelle gilt nie als „bekannt P5“: Die Standbild-Leiter läuft bei jedem Start (bzw. mit X-Ray wird jedes Mal neu geprobt) – genau das soll die Regel „Profil 5 bleibt wie vorher“ verhindern. Außerdem liegt der Pfad samt Token dauerhaft in UserDefaults.
- **Ursache:** `sourceKey` entfernt nur Query, Fragment und Anmeldedaten, nicht den Pfad.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (hängt von der Link-Form des Dienstes ab)
- **Fix-Idee:** Den Schlüssel aus Titel-ID plus Quellen-Fingerabdruck bilden wie `FailedLinkBook.key`, nicht aus der Adresse.
- **Test:** PlayerCore-Test: zwei Adressen derselben Datei mit unterschiedlichem Token im Pfad müssen denselben Schlüssel ergeben.
- **Gegenprüfung:** Der Kommentar über `sourceKey` nennt „scheme, host, port and path“ ausdrücklich und begründet nur das Weglassen der Query – der Pfad ist also bewusst drin, der Fall „Token im Pfad“ aber nicht bedacht. Das widerspricht dem Grundsatz an anderer Stelle im selben Paket („Schlüssel ist nie der Link“, `Packages/PlayerCore/Sources/PlayerCore/Playback/FailedLinks.swift:25`). Die Menge ist auf 200 Einträge begrenzt (`XRayProbe.swift:190-209`), wächst also nicht unbegrenzt. Betroffen sind nur Profil-5-Quellen; niedrig stimmt.

### W-A-12: README und Standard-Tonbrücke widersprechen sich
- **Bereich:** Wiedergabe
- **Ort:** `README.md:18`, `Packages/PlayerCore/Sources/PlayerCore/Playback/AudioShapingSettings.swift:11-16`, `App/Sources/Playback/PlayerAudioOptions.swift:21`
- **Szenario:** Frische Installation, TrueHD- oder DTS-HD-Spur. Laut README wird sie „decoded to multichannel PCM“. Im Standard (`bridge = .surroundCompat`) läuft die Brücke nach E-AC-3; verlustfrei gibt es erst mit umgestellter Einstellung.
- **Ursache:** `audioBridgeMode = .lossless` wird nur bei `bridge == .lossless` gesetzt, der Standard ist `.surroundCompat`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (Widerspruch zwischen README und Repo-Kommentar; das Verhalten der Engine selbst ist nicht im Repo)
- **Fix-Idee:** README an den Standard anpassen oder den Standard ändern (Entscheidung des Nutzers).
- **Test:** Fern-Log-Zeile „Geladen · … Ton <Dekoder> (<Auslieferung>)“ bei einer TrueHD-Spur ohne geänderte Einstellung.
- **Gegenprüfung:** Standardwert im Initialisierer geprüft (`AudioShapingSettings.swift:41`); der Enum-Kommentar nennt E-AC-3 als „Standard der Engine“ und FLAC/PCM nur für `.lossless`. Reiner Dokumentationsfehler, kein Fehlverhalten.

---

### W-B-5: ±10-s-Sammelsprung: abgelöste Aufgabe löscht das neue Ziel
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/PlayerScreen.swift:652`, `App/Sources/Views/Player/PlayerExit.swift:46`
- **Szenario:** ▶ drücken, nach 450 ms beginnt `engine.seek`. Während der Sprung läuft, ▶ erneut: `pendingSeek = Ziel + 10`, die alte Aufgabe wird abgebrochen. Kehrt deren `seek` zurück, setzt sie trotzdem `pendingSeek = nil`. Die Zeitleiste springt zurück; ein dritter Druck in diesem Fenster rechnet ab `engine.currentTime` statt ab dem gesammelten Ziel → ein Druck geht verloren. Nebenbefund (plausibel): `seekTask` wird beim Ausstieg nicht abgebrochen, ein gesammelter Sprung kann bis 450 ms nach `leave` noch auf die pausierte Engine gehen.
- **Ursache:** Abbruchprüfung nur vor dem `await`, nicht danach:
  `await engine.seek(target)` / `pendingSeek = nil`
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Nach dem `await` `guard !Task.isCancelled` setzen; `seekTask?.cancel()` in `leave` bzw. `orderlyExit` aufnehmen.
- **Test:** Am Gerät: dreimal ▶ im Abstand von ca. 0,6 s bei einer Fernquelle; Fern-Log „Sprung a → b“ muss am Ende +30 s ergeben.
- **Gegenprüfung:** `queueSeek` und alle Stellen gelesen, die `pendingSeek` setzen oder löschen; nach dem `await` gibt es keine Prüfung, `orderlyExit` bricht `loadTask`, `recoverTask` und `addonSubTask` ab, `seekTask` nicht.

### W-B-6: Fortschritt speichern in der Pause sendet Scrobble-`start`
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Sync/ScrobbleTracker.swift:45`, `App/Sources/Views/PlayerScreen.swift:362`, `App/Sources/Views/Player/PlayerExit.swift:15`, `App/Sources/AppModel.swift:79`
- **Szenario:** (a) Pause (→ `pause` an den Dienst), dann das Ton/Untertitel-Panel öffnen. Das Cover löst `onDisappear` von `PlayerControls` aus → `saveProgress()` → `recordProgress` → `scrobbler.progress`: Sitzung nicht aktiv, Anteil unter 80 % → `start`. Der Dienst zeigt „schaut gerade“, obwohl pausiert ist. (b) Aus der Pause mit Menü verlassen: `leaveWithModeSwitch` ruft `saveProgress()` → `start`, danach `endPlayback` → `stop`. Der Test `scrobblePausedBelowEightyEndsSilently` erwartet für diesen Fall ein stilles Ende, die App erreicht es nicht.
- **Ursache:** `progress` unterscheidet nicht zwischen „spielt“ und „Stand sichern“:
  `} else if !s.active && fraction < Self.startLimit { out.append(ScrobbleEvent(action: .start, …`
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt für (b); (a) plausibel (hängt daran, dass das Cover `onDisappear` auslöst, was die Kommentare im Code als beobachtet beschreiben); Wirkung beim Dienst abgeleitet
- **Fix-Idee:** `recordProgress` einen Parameter „spielt gerade“ geben und `start` nur dann senden (oder in der Pause nur lokal speichern).
- **Test:** PlayerCore: `progress(0.3)`, `pause`, `progress(0.3)` als reines Sichern → kein `start`.
- **Gegenprüfung:** Alle Aufrufer von `saveProgress` verglichen: Takt (`:337`) verlangt `engine.isPlaying`, Play/Pause und Szenenwechsel speichern vor `onPause`; nur `onDisappear` und der Ausstieg speichern ohne diese Bedingung. Szenario um Weg (b) ergänzt.

### W-B-7: Spul-Vorschau zeigt ein altes Bild unter der neuen Zielzeit
- **Bereich:** Wiedergabe
- **Ort:** `App/Sources/Views/Player/PlayerScrub.swift:277`, `App/Sources/Views/Player/PlayerScrub.swift:257`, `App/Sources/Views/Player/PlayerScrub.swift:498`
- **Szenario:** Zügig über mehrere Minuten wischen. Jedes grobe Bild wird verworfen, sobald das Ziel das 2-s-Feld verlassen hat; angezeigt bleibt das Bild vom Beginn (oder der letzte Cache-Treffer), daneben steht die aktuelle Zielzeit. Erst 300 ms nach dem Stillstand kommt das richtige Bild. `previewTime` wird gesetzt, aber nirgends angezeigt oder zum Ausblenden benutzt.
- **Ursache:** `if ScrubPreviewCache<ScrubStill>.key(target) == key { preview = img.image; … }` – kein Ersatz (nächstliegendes Bild, Abdunkeln) für den Fall „Ziel weitergezogen“.
- **Schweregrad:** niedrig (kosmetisch) · **Sicherheit:** bestätigt
- **Fix-Idee:** Jedes fertige grobe Bild zeigen, solange kein besseres da ist, oder das Bild abdunkeln/leeren, wenn `previewTime` mehr als einige Sekunden vom Ziel abweicht.
- **Test:** Am Gerät: langer Wisch über ein Kapitel hinweg; Bild und Zeit in der Karte vergleichen.
- **Gegenprüfung:** `requestPreview`/`runPreview` und die Karte gelesen; `preview` wird während der Bewegung nur bei Feld-Treffer ersetzt und nie geleert, `previewTime` hat außer den drei Zuweisungen und dem Zurücksetzen keinen Leser.

### W-B-8: Rastpunkte beim Spulen halten langsame Wischbewegungen fest
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Playback/ScrubPlanner.swift:244`
- **Szenario:** Ziel steht auf einer Kante (Kapitelanfang, Intro-Ende). Jeder Wisch-Schritt bis 1,5 s wird wieder auf die Kante gezogen, `move` meldet „keine Änderung“. Bei einem 2-h-Film entspricht das einem Punkt je Ereignis, bei 45 min bis zu zwei Punkten, bei kurzen Videos bis zu sechs. Die Teilwege summieren sich nicht: mit langsamen, feinen Bewegungen kommt man von der Kante nicht weg. Drehrad und ◀/▶ während des Spulens rasten nicht und führen heraus.
- **Ursache:** Gerastet wird das gespeicherte Ziel selbst, es gibt kein ungerastetes Rohziel:
  `var t = Self.clamp(target + seconds, …)` / `if snaps { t = Self.clamp(Self.snap(t, edges: snapEdges), …) }`
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (Logik); wie oft es stört, hängt von den Schrittweiten der Fernbedienung ab
- **Fix-Idee:** Rohziel getrennt mitführen und nur die Anzeige rasten, oder nach dem Einrasten in dieselbe Richtung nicht erneut rasten.
- **Test:** PlayerCore: Ziel auf Kante, zehnmal `pan` mit 1 s Weg in eine Richtung → Ziel muss sich bewegen.
- **Gegenprüfung:** `pan` → `move` → `snap` und den Aufrufer in `PlayerScrub.swift` (Delta je Recognizer-Ereignis, kein Aufsummieren) gelesen; der Test `scrubClampsToFileAndSnaps` prüft nur das Einrasten, nicht das Verlassen der Kante.

### W-B-9: Untertitel in anderen Alt-Zeichensätzen werden still als Windows-1252 gelesen
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Playback/SubtitleCharset.swift:41`, `App/Sources/Views/Player/PlayerPictureSound.swift:203`
- **Szenario:** Addon-Untertitel in Polnisch/Tschechisch (CP1250), Russisch (CP1251), Griechisch (CP1253) oder Türkisch (CP1254), nicht UTF-8. `detect` fällt auf CP1252, die App schreibt die Datei als UTF-8 und gibt sie der Engine: falsche Buchstaben in jeder Zeile. Die Sprache des Untertitels ist bekannt, wird aber nicht benutzt. Deutsche, englische, französische und spanische Dateien sind nicht betroffen.
- **Ursache:** `return (decodeCP1252(b), .cp1252)` als einziger Rückfall, `decode(_:)` ohne Sprachhinweis. Der Kopfkommentar der Datei nennt diese Reihenfolge ausdrücklich; es ist eine Lücke im Umfang, kein Versehen.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Umwandlung bestätigt; ob die Engine die Rohdatei besser läse, ist hier nicht geprüft)
- **Fix-Idee:** `decode` um die Sprache erweitern und danach die Codepage wählen; bei unbekannter Zuordnung nicht umwandeln, sondern der Engine die Adresse lassen.
- **Test:** PlayerCore: CP1250-Bytes für „Żółć“ mit Sprache „pl“ → richtiger Text.
- **Gegenprüfung:** `detect` und `AddonSubtitleFiles.fetch` gelesen; nach UTF-8 gibt es nur den CP1252-Zweig und die Datei wird immer lokal ersetzt. Sicherheit gesenkt, weil die Aussage über die Engine nicht belegbar ist.

### W-B-10: Nach einer Folge aus Staffel 0 gilt S1E1 als „nächste Folge“
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Progress/NextEpisode.swift:30`, `App/Sources/PlayerApp.swift:53`, `Packages/PlayerCore/Sources/PlayerCore/Progress/NextEpisode.swift:52`
- **Szenario:** Ein Special (z. B. S0E3 aus dem Trakt/Simkl-Abgleich in Weiterschauen) wird gespielt. Die Folgenliste enthält bewusst keine Staffel 0, `next(after: 0, 3)` liefert daher das erste Element: S1E1. Up-next zählt herunter und startet S1E1, `recordNextUp` trägt S1E1 ein; „Abspielen“ auf der Detailseite (`nextOpenEpisode`) springt nach dem gesehenen Special ebenfalls auf S1E1, auch wenn der Nutzer in Staffel 4 ist.
- **Ursache:** `list.first { ($0.season, $0.episode) > (season, episode) }` ohne Prüfung, ob die Ausgangsfolge überhaupt in der Liste liegt.
- **Schweregrad:** niedrig · **Sicherheit:** plausibel (Logik bestätigt; die Detailseite bietet Staffel 0 nicht an, der Weg führt nur über abgeglichene Einträge)
- **Fix-Idee:** Für `season <= 0` (oder Folge nicht in der Liste) `nil` liefern.
- **Test:** PlayerCore: `EpisodeRef.next(after: 0, 3, in: [S1E1, S1E2])` muss `nil` sein.
- **Gegenprüfung:** `EpisodeRef.list` filtert `s > 0`, die Staffelwahl der Detailseite ebenfalls; `TraktClient.playback` und `SimklClient.playback` übernehmen Staffel 0 ungefiltert, damit ist der Zugang offen. Zeile in `PlayerApp.swift` korrigiert (`:53` statt `:52`).

### W-B-12: „Überspringen“ kurz vor dem Dateiende springt rückwärts
- **Bereich:** Wiedergabe
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Playback/SkipSegments.swift:238`, `Packages/PlayerCore/Sources/PlayerCore/Playback/SkipSegments.swift:192`
- **Szenario:** Abspann oder Vorschau reicht bis ans Dateiende, Aktion „Knopf“ oder „Automatisch“ (nicht Standard), keine Karte deckt ihn ab (letzte Folge, Autoplay aus). Der Knopf steht bis 1 s vor dem Ende; das Sprungziel wird aber auf `duration - 5` gekappt. Drückt man in den letzten 5 s, springt die Wiedergabe bis zu 4 s zurück. Einmalig, weil der Bereich danach als erledigt gilt.
- **Ursache:** `if duration > 10 { target = min(target, duration - 5) }` ohne Vergleich mit der aktuellen Position; die Knopf-Grenze nutzt `s.end - endMargin`.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** In `candidate` keinen Knopf/Countdown mehr zeigen, wenn das gekappte Ziel nicht mindestens 1–2 s hinter der Position liegt.
- **Test:** PlayerCore: Bereich `[d-30, d]`, `candidate`/`evaluate` bei `d-3` → kein Knopf bzw. `beginSkip` ≥ Position.
- **Gegenprüfung:** `candidate`, `beginSkip`, `SkipPolicy.action`/`target` und `jump` in `SkipSegmentButton.swift` gelesen; nirgends wird das Ziel mit der Position verglichen, `SkipSegmentsTests` sichert nur „nie hinter das Dateiende“.

---

---

## Verworfene Kandidaten

Nach der Gegenprüfung verworfen, jeweils mit Grund. Zeilen mit ID „–“ sind Hypothesen, die schon der Erstgutachter selbst verworfen hat.

### Wiedergabe (wiedergabe-a)

| ID | Titel | Grund |
|---|---|---|
| W-A-8 | Proxy bemerkt abgebrochene Leser nicht | Der verwaiste Abruf schadet nur, wenn ein 4-MiB-Block länger als 14 s braucht (`readerAttempts = 1`, Leerlauf-Grenze 6 s, harte Grenze 14 s); bei einem so langsamen Ursprung leiten Lesergrenze und `slowAction` die Sitzung ohnehin um – kein eigenständiges Fehlbild belegt. |
| W-A-11 | 1-s-Takt als `let` im View | Ob `onReceive` bei einem neu angelegten Publisher neu abonniert, ist Verhalten von SwiftUI und statisch nicht belegbar; die behauptete Wirkung (Zähler laufen etwas langsamer als die Uhr) ist klein und nur am Gerät messbar. |
| – | `errorText` bleibt nach geglücktem Neuaufbau stehen | Vom Erstbericht verworfen; stützt sich auf Engine-Verhalten, hier nicht erneut belegbar. |
| – | `engine.load` läuft nach `stop()` weiter | Vom Erstbericht verworfen; `stopped`-Prüfung mit Sitzung gesehen (`App/Sources/Playback/PlaybackEngine.swift:215-218`), Rest ist Engine-Verhalten. |
| – | Endlosschleife der Fehlerleiter | Bestätigt verworfen: höchstens 4 Versuche über alle Klassen (`PlaybackRecovery.swift:199-204`), Netz-Warten zählt nicht. |
| – | Doppelte Starts | Bestätigt verworfen: `guard loadTask == nil` (`PlayerScreen.swift:358`), jede Wiederholung bricht den Vorgänger ab, `recoverGen` schützt `recovering`. |
| – | Schließen des alten Players stoppt den Listener des neuen | Bestätigt verworfen: `close` prüft das Token (`DiskCacheProxy.swift:548-549`). |
| – | Retain-Zyklus Engine → Now Playing → View | Vom Erstbericht verworfen; `leave` ruft `NowPlayingBridge.detach` (`PlayerScreen.swift:459`). |
| – | Überlauf in der Range-Mathematik | Vom Erstbericht verworfen; nicht erneut geprüft. |
| – | Data Races in den `@unchecked Sendable`-Typen | Bestätigt verworfen für `DiskCacheOnce` und `DiskCacheOriginFetcher` (Sperre bzw. serielle Delegate-Queue, `DiskCacheProxy.swift:45-49`, `:86-88`). |
| – | Speicher voll | Bestätigt verworfen: Blöcke gehen weiter an die Engine, der Vorlauf ruht 30 s (`DiskCacheProxy.swift:416-420`). |
| – | Bildschirmschoner bleibt gesperrt | Bestätigt verworfen: Besitzer-Kennung, Freigabe in `leave` und beim Verschwinden (`PlayerPictureSound.swift:30-47`). |
| – | Spur-Erinnerung je Serie falsch verschlüsselt | Vom Erstbericht verworfen; nicht erneut geprüft. |

---

### Wiedergabe (wiedergabe-b)

| ID | Titel | Grund |
|---|---|---|
| W-B-11 | Folgen mit reinem Datum gelten ab Mitternacht UTC als ausgestrahlt | Dokumentierte Wahl in `ISODate.parse` („Mitternacht UTC“); ein Datum ohne Uhrzeit trägt die Information nicht, und Zeitstempel auf Mitternacht verhalten sich genauso – Datengenauigkeit des Addons, kein Codefehler (als Geräteprüfung übernommen). |
| – | Doppelter Start der nächsten Folge (Countdown und Video-Ende gleichzeitig) | `startNext` und `finishAtEnd` prüfen `leaving`, `leave` setzt es synchron (nachgelesen); doppelte 100 % fängt `completed` ab. |
| – | Auto-Skip-Schleife nach Zurückspulen ins Intro | `autoDone` merkt den Bereich, danach nur noch der Knopf. |
| – | Segmente außerhalb der Dauer / falsche IntroDB-Zeiten | `merge` verwirft bzw. kürzt sie, Filme zusätzlich über `alignedMovieIntroDB` (nachgelesen). |
| – | „Kaputte Umlaute reparieren“ zerstört richtigen Text | Reparatur nur bei genug typischen Treffern; kein realistischer Fehlgriff gefunden (Erstbericht). |
| – | Hash bei Dateien < 128 KB | Fehlerpfade enden alle in „ohne Hash“ (Erstbericht). |
| – | Riesige oder gepackte Untertiteldateien | 5-MB-Grenze mit Bytezähler, 15-s-Frist, gzip/zip werden nicht angefasst (nachgelesen). |
| – | Ungültige Indizes im Spur-Panel nach Spurwechsel | Panel arbeitet mit Spur-IDs und sucht bei jeder Wahl neu (Erstbericht). |
| – | Force-Unwraps/Indexzugriffe in PlayerCore | Jeweils direkt vorher gesetzt bzw. auf leer geprüft (Erstbericht). |
| – | Up-next bei kurzen Videos | Erst ab 300 s Laufzeit, an `nextTitle` gebunden (nachgelesen). |
| – | Weiterschauen ohne Folgenliste → kein Up-next | `StreamListView` lädt die Folgenliste nach (nachgelesen, `App/Sources/Views/DetailViews.swift:845`). |
| – | Fortschritt bei Dauer 0 / im falschen Profil | `record` und `saveProgress` verlangen Dauer > 0 (nachgelesen); Profilwechsel bei offenem Player ist nicht vorgesehen. |
| – | „Noch da?“-Zähler | Jeder Tastendruck setzt zurück; ohne Antwort startet nichts (Erstbericht). |
| – | Observer-Lecks in `RemoteTouchInput` | `stop()` räumt auf, `detach()` läuft bei jedem `onDisappear` (Erstbericht). |
| – | Countdown läuft hinter offenem Panel ab und springt sofort | Panel öffnet nicht bei stehendem Knopf, `canSkip` verlangt `!showTracks`, jede Taste bricht den Countdown ab (nachgelesen). |

„Nachgelesen“ = in dieser Gegenprüfung am Code bestätigt; „Erstbericht“ = unverändert übernommen, nicht erneut geprüft.

---

### Fokus & Navigation (fokus-a)

| ID | Titel | Grund |
|----|-------|-------|
| F-A-9 | Neu aufgebaute Reihe verliert ihr Fokus-Gedächtnis | Für Reihen mit Cache-Stand liefert `homeRowItems` ohne Netz sofort (`AppModel.swift:360`), `rememberedRoute` wird nach dem Laden neu ausgewertet; das behauptete Zeitfenster zwischen Aufbau und Fokusankunft ist nicht belegt, die Aussage „wirkt nur für nie abgebaute Reihen“ ist überzogen. |
| F-A-10 | „Erneut versuchen“ setzt das Fokusziel im selben Durchlauf | Die Übergabe ist ausdrücklich vorgesehen (`focusedPlaceholder = 0`, Statuskachel und Platzhalter 0 tragen denselben Fokuswert); ob sie greift, ist reines Fokus-Engine-Verhalten ohne Codebeleg → nur „Am Gerät prüfen“. |
| F-A-13 | Umschalten Seitenleiste ↔ Leiste oben baut die `TabView` neu auf | Im Kommentar `PlayerApp.swift:164`–`166` als bewusste Entscheidung dokumentiert und für Tab, Pfade und Kategorie abgefangen; verbleibende Fokusfrage → „Am Gerät prüfen“. |
| – | 350-ms-Entprellung überschreibt Neueres mit Altem | `HomeFocus.set` bricht die wartende Aufgabe ab, alles auf dem MainActor, Abbruchprüfung nach dem Schlaf. |
| – | Diashow-Timer läuft unter Detailseite/Player weiter | `.task(id:)` der `HeroLayer` endet mit dem Verschwinden der Startseite. |
| – | Folienwechsel während „Abspielen“ startet den falschen Titel | `play()` hält `m` fest; „Details“ liest `slides.current` beim Druck. |
| – | Ladezustand ersetzt Inhalt beim Erneuern einer Listen-Reihe | `loaded` bleibt `true`, abgebrochene Ladungen setzen nichts (`RowViews.swift:48`). |
| – | Veraltete IDs im Fokus-Gedächtnis nach Reload | `rememberedRoute` sucht die ID in den aktuellen Einträgen, sonst `nil`. |
| – | `.id()`-Wechsel auf fokussierten Views | Keiner gefunden; `HomeTopEdgeWatch.topID` konstant, Verwalter nutzt stabile Reihen-ID. |
| – | Mehrere Fokus-Videos gleichzeitig / Player-Leck | Ein Player, Besitzer/Generation sichern jede Wartestelle ab. |
| – | Einträge im Browser wechseln beim Umschalten den Abschnitt | Abschnitte sind nach Typ/Thema gebildet, nicht nach Status. |
| – | `disabled` auf fokussierter View im Verwalter | Gesperrt werden nur die anderen Zeilen (`HomeManagerView.swift:178`). |
| – | Löschen/Ausblenden im Verwalter ohne Fokusziel | `focusNear` und Ausführung in `onDismiss`. |
| – | Beobachter-Leck in `HomeTopEdgeWatch`/`TabBarGuard` | `stop()` meldet ab, der Wächter installiert genau einen Beobachter (`TabBarGuard.swift:32`). |
| – | Derselbe Titel in zwei Reihen kollidiert im Fokus | `@FocusState` ist je Reihe. |

---

### Fokus & Navigation (fokus-b)

| ID | Titel | Grund |
|---|---|---|
| F-B-11 | Besetzung: ForEach-ID (TMDB-Personen-ID) nicht eindeutig gemacht | Der Auslöser (dieselbe Person doppelt unter den ersten 20 Einträgen von `credits.cast`) ist eine unbelegte Annahme über TMDB-Daten; bei Serien ist `aggregate_credits` je Person eindeutig. |
| F-B-12 | Suche: abgeschickte Suche kann ein neueres Ergebnis überschreiben | Die Antwort für den alten Text müsste länger brauchen als Tastatur neu öffnen, weitertippen, 600 ms Entprellung und die neue Antwort zusammen; das Leeren bei Abbruch geschieht hinter der Vollbild-Tastatur und wird 600 ms später ersetzt. |
| – | F-B-3 Teil (c): Fokus springt nach „Abmelden“ | Nur ein unbestimmtes Fokusziel nach einem Zeilentausch behauptet, kein falsches Ergebnis belegt. |
| – | F-B-4 Nebenbefund: Eintrittsfokus wird nie gesetzt | Tritt nur auf, wenn der Nutzer die Seite bereits verlassen hat; die Rückkehr hat eigenen Fokus-Code (`DetailViews.swift:173`–`182`, `275`–`286`). |
| – | Doppelte ForEach-IDs in der Quellenliste | Im Erstbericht verworfen: `StreamDedupe.unique` und `StreamListMerge.additions` lassen keine doppelte `id` zu. |
| – | Doppelte Titel auf Personenseite / im Genre-Raster | Im Erstbericht verworfen: `parsePerson` und `GenrePaging.seen` entdoppeln. |
| – | Trailer-Doppeldruck / Auflösung überlebt die Seite | Im Erstbericht verworfen, hier bestätigt: Sperre in `DetailViews.swift:511` und `519`, Abbruch in `300`, Prüfung in `527` und `544`. |
| – | Detailseite lädt bei jeder Rückkehr neu / Fokus springt ohne Wiedergabe | Im Erstbericht verworfen, hier bestätigt: `loaded`, `didInitialFocus`, Vergleich `playbackStamp != openedPlaybackStamp`. |
| – | Späte Ergebnisse eines alten Titels in einer neuen Detailseite | Im Erstbericht verworfen: jede Route hat eigenen `@State`, das Modell verwirft Suchen nach Profilwechsel. |
| – | Plakettenzeile ändert die Höhe | Im Erstbericht verworfen: fester Platzhalter, `DetailPage.shouldUpdate` bremst die Rückkopplung. |
| – | Staffelwechsel-Rennen in `translateSeason` | Im Erstbericht verworfen: jede Antwort wird nur auf ihre eigene Staffel angewendet. |
| – | Filter leert die Liste unter dem Fokus / Chip verschwindet | Im Erstbericht verworfen: „Filter aufheben“ mit Fokuswunsch, `dropMissingChips`. |
| – | `disabled` auf fokussierter Zeile in den Einstellungen | Im Erstbericht verworfen: durchgehend `settingsUnavailable`. |
| – | „Standard wiederherstellen“ entfernt sich selbst | Im Erstbericht verworfen: Fokus wird vorher umgesetzt. |
| – | Abfrage-Schleifen ohne Abbruch | Im Erstbericht verworfen, für SyncLogin hier bestätigt (`SyncLoginView.swift:51`–`52`); `PhoneServer` stoppt in `onDisappear`. |
| – | Einstellungs-Kategorie geht beim Wechsel der Navigationsart verloren | Im Erstbericht verworfen, hier bestätigt: `settingsCategory` liegt in RootView (`PlayerApp.swift:70`). |
| – | Rückfragen (eigene Überlagerung) | Im Erstbericht verworfen: Aktion läuft erst nach dem Schließen. |

### Sync & Profile (sync)

| ID | Titel | Grund |
|---|---|---|
| S-14 | Alle 10 s Wiedergabe: ganzes Fortschrittsbuch kodieren, komprimieren und mehrfach schreiben, auf dem Hauptthread | Der Ablauf stimmt (`App/Sources/Views/PlayerScreen.swift:337`), aber eine spürbare Auswirkung ist nicht belegt; das ist eine Optimierung, kein Fehler (siehe „Am Gerät prüfen“ Nr. 3). |
| – | Älterer Remote-Stand überschreibt neueren lokalen | `merge` überspringt bei `l.updated >= r.updated` (`WatchProgress.swift:116`); geprüft. |
| – | Zeitzonen / ISO 8601 mit und ohne Millisekunden | Beide Formate werden gelesen (`Models/ISODate.swift`); kein Gegenbeleg gefunden. |
| – | `confirm(createdAt:)` passt nach Neustart nicht mehr | Warteschlange nutzt das Standard-Datumsformat mit Sekundenbruchteilen, alte ISO-Dateien werden gelesen (`SyncQueue.swift:210-217`); geprüft. |
| – | Polling läuft nach Schließen der Login-Seite weiter | `.task` wird abgebrochen, `Task.sleep` wirft (`SyncLoginView.swift:41`, `:52`); geprüft. |
| – | Parallele Anfragen lösen mehrere Erneuerungen aus | Innerhalb eines Profils bündelt `traktRefresh` (`AppModel.swift:163-165`); der Profilbezug ist S-4. |
| – | 429 führt zu doppelten Einträgen | Genau eine Wiederholung nach `Retry-After` (`APIRequest.swift:42-47`); geprüft. |
| – | `stop`-Wiederholung erzeugt doppelten Verlauf | 409 gilt als Erfolg (`APIRequest.swift:97`); geprüft. |
| – | Warteschlange geht beim App-Ende verloren | Synchrones Speichern nach Aufnahme und nach jeder Bestätigung (`AppModel+SyncQueue.swift:111`, `:163`, `:166`); geprüft. |
| – | Warteschlange wächst unbegrenzt | Ein Eintrag je Titel und Art, Ablauf nach 30 Tagen (`SyncQueue.swift:79`, `:108`); geprüft. |
| – | UserDefaults über 1 MB | Budget 640 KB plus 8 KB Geräteblock (`TieredBlobStorage.swift:31-41`); die direkten Schlüssel sind klein. Messung am Gerät bleibt offen. |
| – | Nicht atomare Dateischreibvorgänge | `.atomic` in `BlobStorage.swift:18`; geprüft. |
| – | Späte Quellen-/Katalogergebnisse im falschen Profil | Generation im Katalog-Cache (`AppModel.swift:388`) und Zurücksetzen der Suchen beim Wechsel (`:260`); geprüft. |
| – | Kachel-Aktion schreibt nach Profilwechsel ins falsche Profil | `perform` prüft das Profil nach dem `await` (`AppModel+SyncQueue.swift:83`); geprüft. |
| – | Force-Unwraps | `as! FileBlobStorage` nur in Test-Hilfen (`ProfileStore.swift:30-31`), `imdb!` durch `imdb != nil &&` gedeckt (`SyncQueue.swift:79`); geprüft. |
| – | `processSyncQueueOnce` sendet Änderungen von A mit dem Token von B (Teil von S-3) | Kein `await` zwischen Profil-ID und Token-Abruf des ersten Dienstes, Prüfung nach jedem Senden (`AppModel+SyncQueue.swift:131-144`). |
| – | Sicherung unvollständig (Teil von S-12) | Als „Alle Profile“ beschriftet; Funktionsumfang, kein Fehler. |
| – | Nuvio-Import erzeugt Dubletten; Geräte-Einstellungen wandern erneut | Vom Erstbericht selbst verworfen; nicht erneut geprüft. |

### Addons & Startseite (addons-a)

| ID | Titel | Grund |
|---|---|---|
| A-A-10 | Dubletten-Ausblendung behält den ersten Eintrag, auch wenn der spätere sofort bereit ist | „Der erste Eintrag bleibt“ ist dokumentierte und getestete Regel (`StreamListDisplay.swift:37`, Test `dedupeByFilenameAndSizeKeepsFirstAndIds`); das Schadensszenario setzt voraus, dass ein Addon dieselbe Datei beim selben Dienst erst ungecacht und danach gecacht liefert, was nicht belegt ist. Bleibt als testwürdige Lücke. |
| A-A-15 (Teil) | TorBox: keine Seitenabfrage bei `mylist` | Seitengröße des Dienstes aus dem Code nicht belegbar; nur am Gerät klärbar. |
| – | Ein hängendes Addon blockiert die Liste / ein Fehler verwirft alles | Jedes Addon läuft in eigener Kind-Aufgabe mit eigener Frist, Fehler werden zu `.failed` (`AddonSearch.swift:164`–`180`); nachgeprüft. |
| – | `AsyncLimiter` verliert Plätze bei Abbruch | Vom Erstbericht verworfen; hier nicht erneut geprüft. |
| – | Vergleichsfunktion verletzt strikte schwache Ordnung | Vom Erstbericht verworfen (Index als letztes Kriterium); nicht erneut geprüft. |
| – | Force-Unwraps im Ranking | Vom Erstbericht als gedeckt verworfen; die `try!` in `StreamTraits.swift:110`–`115` sind konstante Muster (nachgeprüft). |
| – | Ein unlesbarer Eintrag verwirft die ganze Liste | Nachsichtige Dekodierung je Feld (`StremioModels.swift:405`–`429`); nachgeprüft für `behaviorHints`. |
| – | „DV“ in Wörtern, HDR10+ gegen HDR | `containsToken` und die Prüfreihenfolge in `StreamTraits.swift:39`–`42` verhindern das; nachgerechnet. |
| – | Profilwechsel während der Suche | Besitzer und Epoche werden gemerkt, alte Ergebnisse verworfen (`AppModel.swift:484`, `502`, `516`); nachgeprüft. |
| – | Abgelaufene Debrid-Links aus dem Cache | 90 s frisch, bis 30 min mit Erneuerung (`RevalidationPolicy.swift:34`); in sich schlüssig, Einschränkungen siehe A-A-4, A-A-5, A-A-8. |
| – | Wachstum des Quellen-Caches | Auf 40 Einträge begrenzt, abgelaufene fliegen beim Ablegen heraus (`AppModel.swift:686`–`692`); nachgeprüft. |
| – | Sturm von Anfragen beim Scrollen | Entprellung, 2 + 4 Plätze, gemeinsames Budget 12 Suchen/60 s (`StreamPrefetcher.swift:19`–`24`); nachgeprüft. |
| – | TorBox: endloses Polling | Es gibt kein Polling; nur fertige Einträge werden gelistet (`TorBox.swift:100`); nachgeprüft. |
| – | Trailerio hängt | Feste Wartezeit mit anschließendem YouTube-Rückfall; vom Erstbericht verworfen, nur der Aufrufpfad geprüft. |

### Addons & Startseite (addons-b)

| ID | Titel | Grund |
|---|---|---|
| A-B-4 | Nach jedem Start aus dem Plattencache wird jede Reihe unter dem Fokus ersetzt | Das Erneuern übernommener Reihen ist dokumentierte Absicht (`TimedCache.swift:11`, `AppModel+CatalogDisk.swift:6`–`7`); der behauptete Schaden (Fokussprung) ist aus dem Code nicht belegbar, da `ForEach` die Karten über stabile IDs führt. Als Geräteprüfung und Performance-Punkt P-3 übernommen. |
| A-B-7 | Eine dauerhaft fehlschlagende Serie setzt den ganzen Kalender auf 5 min Gültigkeit | Ein dauerhafter Fehler ist nicht belegt: Kalender-IDs sind IMDb-IDs, `tmdbIDs` lebt nur im Speicher und wird je Sitzung neu über `/find` ermittelt; die kurze Gültigkeit nach Fehlern ist laut Kommentar gewollt (`AppModel+Upcoming.swift:9`). |
| A-B-9 | Bewertungs-Icons erscheinen zuerst als Text; ein Cache für alle Profile | (a) ist ein rein optischer Effekt, der sich nur am Gerät zeigen lässt; (b) braucht zwei Profile mit verschiedenen eigenen Icon-Sätzen ohne Netz und kostet sonst nur einen erneuten Abruf. Kein Fehlverhalten belegt; (a) als Geräteprüfung übernommen. |
| – | Startseite zeigt Daten eines anderen Profils aus dem Plattencache | Datei je Profil, Übernahme nur bei passendem Profil und unveränderter Cache-Generation (`AppModel+CatalogDisk.swift:54`–`60`); nachgeprüft. |
| – | Korrupte Cache-Datei führt zum Absturz | `try?` beim Dekodieren, unlesbare Datei wird gelöscht (`AppModel+CatalogDisk.swift:41`–`42`); nachgeprüft. |
| – | JSON- oder Bild-Dekodierung auf dem Main-Thread | Beides in `Task.detached` (`AppModel+CatalogDisk.swift:39`, `ImagePipeline.swift:292`); nachgeprüft. Ausnahme Kit-Dateien beim Start, siehe P-1. |
| – | TMDB 401/429 ergibt leere Liste, die 24 h gecacht wird | `URLSessionFetcher` wirft bei Nicht-2xx (`Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:15`), `loadItems` legt Fehlschläge nicht ab (`AppModel.swift:380`); nachgeprüft. |
| – | `MediaType.both` mischt Filme und Serien falsch | Laut Erstbericht erzeugt keine Stelle eine Discover-Quelle mit `.both`; nicht eigens nachgeprüft, als verworfen übernommen. |
| – | Falsches Bild in wiederverwendeter Ansicht | Anzeige nur bei gleicher Adresse und gleichem Weichzeichner (`ImagePipeline.swift:428`); nachgeprüft. |
| – | Doppelte Downloads derselben Bildadresse und Zielgröße | `inFlight` je Schlüssel (`ImagePipeline.swift:80`); nachgeprüft. |
| – | RatingsStore: parallele Doppelabrufe, unbegrenztes Wachstum, fehlender Schlüssel | `inFlight` je Titel, Obergrenze 4000 (`App/Sources/RatingsStore.swift:22`, `:56`), ohne Schlüssel keine Anfrage (`AppModel.swift:550`); nachgeprüft. |
| – | HomeEditor/HomeManager: Index außerhalb, Ränder, Abbrechen | Aus dem Erstbericht übernommen, nicht eigens nachgeprüft. |
| – | Kalender: Sommerzeit/Mitternacht bei der Gruppierung | Tagesabstand über `startOfDay` im gregorianischen Kalender der Gerätezeitzone (`Packages/PlayerCore/Sources/PlayerCore/Progress/Upcoming.swift:53`); nachgeprüft. |
| – | „Heute neu“ ignoriert nachgezogene TVmaze-Zeiten | `upcomingRevision` steckt in der Task-ID (`RowViews.swift:44`); nachgeprüft. |
| – | Profilwechsel während laufender Abrufe legt Daten im falschen Profil ab | Katalog über die Cache-Generation (`AppModel.swift:361`, `:388`), Kalender über den Schlüssel mit Profil und Sprache; nachgeprüft. |
| – | Retain-Zyklen in `ImagePipeline`/Stores | Singletons, `[weak self]` in den Beobachtern; stichprobenhaft nachgeprüft. |
| – | Leere Erneuerung überschreibt gefüllte Reihe | `storeRefreshed` verhindert das (`TimedCache.swift:82`), bewusste Abwägung laut Kommentar; nachgeprüft. |

---

---

## Am Gerät prüfen

Was sich nur am Apple TV klären lässt. Die gebündelte Fassung steht in [00-uebersicht.md](00-uebersicht.md).

### Wiedergabe (wiedergabe-a)

1. **W-A-1 (wichtigster Punkt):** Eine Quelle mit abgelaufenem Link starten (Quellenliste lange offen lassen). Erwartung laut Befund: Der Film läuft, im Log fehlen „Geladen ·“ und „Spielt ·“, Untertitel-Automatik und Dolby-Digital-Vorzug greifen nicht. Damit ist auch die offene Reihenfolge „`catch` vor `onChange`“ geklärt.
2. **W-A-3:** Ton umstellen, dann Link ablaufen lassen oder das Netz so lange trennen, bis der Rückfall auf `load` greift; Tonspur danach prüfen.
3. **W-A-5:** Internet am Router trennen, WLAN stehen lassen; im Log die Zeile „Fehler eingeordnet: …“ lesen (Domäne und Code) und prüfen, ob Quellen als fehlgeschlagen gemerkt werden.
4. **W-A-8 (verworfen, zur Sicherheit):** Mit gedrosselter Leitung mehrfach hintereinander weit springen; Log auf „Plattencache: Leser direkt, Vorlauf gestoppt“ prüfen.
5. **W-A-11 (verworfen, zur Sicherheit):** Up-next-Countdown gegen die Uhr messen, während die nächste Folge vorgeladen wird.
6. **W-A-6:** Abrufzahlen in „Plattencache geschlossen · …“ mit und ohne Standbild-Leiter vergleichen.
7. **Ladefehler ohne Engine-Fehler:** Wirft `engine.load`, ohne den Fehlerzustand zu setzen, bleibt nur der rote Text (`loadError`), keine Leiter, kein Quellenwechsel (`PlayerScreen.swift:450`). Im Log: „Laden fehlgeschlagen“ ohne folgendes „Fehler eingeordnet“.
8. **Gesammelter Sprung beim Verlassen:** ▶ drücken und binnen 450 ms Menü. `seekTask` wird weder in `orderlyExit` (`PlayerExit.swift:46`) noch in `onDisappear` (`PlayerScreen.swift:368`) abgebrochen und ruft `engine.seek` nach `stop()`; prüfen, dass die gestoppte Engine das ignoriert.
9. **TV aus während des Ladens:** Kommt `engine.load` zurück, wenn die Engine im Hintergrund abbaut? Sonst bleibt `loadInFlight` stehen.
10. **Langer Ruhezustand mit Plattencache:** Meldet der Listener `.failed`, wenn tvOS den Socket einzieht? Sonst kostet der Weg zur direkten Adresse zwei Leiter-Versuche.
11. **Live-Quellen:** Laufzeit und Stelle gehen durch `Int(…)` (`PlayerScreen.swift:373`, `:424`, `:428`); einmal mit einem Live-Stream prüfen, dass die Laufzeit nie unendlich oder NaN ist (sonst Absturz).
12. **Kurzes „inaktiv“ beim Start** (Kontrollzentrum, Siri, HDMI-Moduswechsel): Danach bleibt die Wiedergabe pausiert („Bleibt pausiert (App war inaktiv)“).
13. **W-A-2:** Einen Remux mit Stereo-Hauptton und AC-3-Kommentar starten.
14. **Debrid-Ausfall (5xx):** Jede Quelle geht über „Kein frischer Link → nächste Quelle“ als `.failed(.debrid)` ins 8-h-Gedächtnis (`PlayerScreen.swift:719`, `:762`); nach dem Ausfall prüfen, ob die automatische Wahl die guten Quellen noch nimmt.

---

### Wiedergabe (wiedergabe-b)

1. **Sekundentakt im Player:** `PlayerControls` hält `Timer.publish(...).autoconnect()` als gewöhnliche Eigenschaft (`App/Sources/Views/PlayerScreen.swift:236`, ebenso `App/Sources/Views/Player/PlayerPauseCard.swift:78`). `PlayerScreen.body` baut `PlayerControls` bei jeder Änderung von `AppModel` neu. Falls SwiftUI dabei neu abonniert, verschiebt jede Änderung den Takt; bei dichter Folge von Änderungen (Hintergrund-Abgleich, Katalog lädt) könnten Up-next-Countdown und 10-s-Speichern stocken. Im Fern-Log prüfen: Abstand „Up-next“ → „Nächste Folge startet“ muss 10 s betragen.
2. **W-B-2:** Panel offen → Hintergrund länger als 10 min → Rückkehr. Zusätzlich beobachten, ob der Player unter dem offenen Panel überhaupt schließt und ob danach Vorladen und Fokus-Video wieder laufen.
3. **W-B-6 (a):** Pause, dann Spur-Panel öffnen; im Fern-Log bzw. beim Dienst prüfen, ob „Verlassen (Panel offen)“ erscheint und ein `start` hinausgeht.
4. **W-B-4:** Titel mit reinem Sync-Anteil starten und prüfen, ob der Sprung an die Zielstelle auch dann ankommt, wenn die Laufzeit schon während des Ladens bekannt wird (der Sprung startet aus `onChange(of: engine.duration)`, möglicherweise vor Ende von `engine.load`).
5. **Up-next per Wisch abbrechen:** Die Karte sagt „Wischen: abbrechen“. Senkrecht führt der Weg über `openTracks` → `.cancelUpNext`; waagerecht nur, wenn tvOS den Wisch als `onMoveCommand` meldet (`canScrub` ist während der Karte `false`). Beide Richtungen probieren.
6. **Untertitel-Versatz, auch negativ:** Mit ±5 s prüfen, dass nicht doppelt verschoben wird und nach einem Rücksprung keine alte Zeile stehen bleibt.
7. **Hash-Abgleich:** Bei Debrid-Links, die auf Range-Abrufe mit 200 statt 206 antworten, muss im Log die Zeile „Datei-Hash“ fehlen und die Abfrage trotzdem laufen; die 4-s-Frist darf den Start nicht spürbar verzögern.
8. **Addon-Untertitel ohne Endung, aber WebVTT-Inhalt:** `formatHint` fällt auf „srt“; ob die Engine die als `.srt` geschriebene VTT-Datei liest, ist nur am Gerät zu sehen.
9. **Addon-Untertitel in CP1250/CP1251 (W-B-9):** Prüfen, ob die Engine die Rohdatei richtig läse; davon hängt ab, ob „nicht umwandeln“ als Fix genügt.
10. **Vorschaubild nach Spul-Ende:** `end()` gibt die Still-Dekoder frei, während eine abgebrochene Abfrage noch laufen kann (`App/Sources/Views/Player/PlayerScrub.swift:232`); bei schnellem Spulen–Abbrechen–Spulen auf Hänger oder schwarze Vorschau achten.
11. **„Noch da?“ nach 60 s ohne Antwort:** Alert schließt, nichts startet; prüfen, dass der Fokus danach in der Quellenliste steht und der Bildschirmschoner wieder greift.
12. **Folgen mit reinem Datum (aus W-B-11):** Bei einem Metadaten-Addon, das `released` ohne Uhrzeit liefert, am Ausstrahlungstag prüfen, ob Up-next eine noch nicht verfügbare Folge anbietet und in „Keine Quelle gefunden“ endet.

### Fokus & Navigation (fokus-a)

1. **Reihenfolge `onAppear` der Startseite gegen Fokus-Rückkehr nach Pop** (`HomeView.swift:63`, `RowViews.swift:73`): Kommt die Fokusmeldung nach `covered = false` und legt das System den Fokus kurz auf einen Nachbarn, merkt sich die Reihe den Nachbarn.
2. **Weiterschauen nach der Wiedergabe**: Die gespielte Kachel rückt an Platz 1, ihr Ziel wechselt von `.detail` auf `.streams` (`RowViews.swift:245`). Folgt der Fokus der Kachel, scrollt die Reihe mit?
3. **Wechsel des `.focused(equals:)`-Werts unter dem Fokus**: Erneuert sich ein Katalog im Hintergrund und ändert sich ein Feld des fokussierten `MetaPreview`, ändert sich der `Route`-Wert der Karte. Bleibt der Fokus?
4. **Aufklappende Poster**: ▶ von einer aufgeklappten Karte (Zuklappen links, 350 ms später Aufklappen und Verankern): Doppelbewegung? Ebenso letzte Karten einer Reihe (`RowViews.swift:369`) und Top-10-Reihen.
5. **Snap nach ganz oben** (`HomeTopEdgeWatch.swift:84`): fällt die Eigenbewegung auf, kollidiert sie mit horizontalem Weiterblättern?
6. **`reshow`-Schritt** (`TabBarGuard.swift:111`): `setTabBarHidden(true/false)` am von SwiftUI verwalteten Controller; bleibt die Leiste danach dauerhaft?
7. **Leere Startseite → Verwalter → Browser** (`HomeManagerView.swift:100`): `open()` im `onAppear` schiebt die zweite Seite, während die erste noch einfährt (verschluckter Push, hängende Leiste?).
8. **Verschiebemodus**: Kann der Fokus mit ◀ in die Seitenleiste entkommen, wohin kehrt er zurück; beendet ein Kit-Abgleich (`adoptProfile`, `HomeManagerView.swift:102`) den Modus kommentarlos?
9. **Fokus-Video**: Ton an, schnell zwischen zwei Video-Kacheln wechseln; nach Speicherwarnung bzw. Bildschirmschoner prüfen, ob die leere Ebene wirklich durchsichtig ist.
10. **Programmatischer Wechsel zum Start-Tab bei Menu** (`PlayerApp.swift:159`): wo landet der Fokus, merkt sich der verlassene Tab seinen Fokus?
11. **Diashow im Hintergrund**: endet die Schleife der `HeroLayer` auch beim Tab-Wechsel und beim Bildschirmschoner?
12. **`LazyHStack`/`LazyVStack` auf tvOS 18**: werden weggescrollte Zellen wirklich abgebaut? Davon hängen F-A-3 (b) und P9 ab.
13. **(neu, aus F-A-10)** „Erneut versuchen“ auf der Statuskachel einer Listen- und einer Kit-Reihe (`RowViews.swift:223`, `:136`): bleibt der Fokus in der Reihe, wenn Statuskachel und Platzhalter 0 im selben Durchlauf getauscht werden?
14. **(neu, aus F-A-13)** Navigationsart in „Darstellung“ umschalten (`App/Sources/Views/Settings/AppearanceSettings.swift:26`, `PlayerApp.swift:167`): bleibt der Fokus auf der Umschaltzeile, bleibt die Seite offen, wie lange lädt die Startseite danach neu?
15. **(neu, aus F-A-9)** Fokus-Gedächtnis nach weitem Scrollen: Reihe 3 auf Kachel 9 verlassen, bis Reihe 15 und zurück; landet der Fokus wieder auf Kachel 9?
16. **(neu, zu F-A-7)** „An Position …“ im Verwalter: steht der Fokus nach dem Schließen des Blatts auf der verschobenen Reihe?
17. **(neu, zu F-A-1)** TorBox: OK auf einer Datei, sofort Menu: öffnet sich der Player über dem Start-Tab, erst bei Rückkehr in die Bibliothek oder gar nicht?
18. **(neu, zu F-A-3)** „Ganz nach oben“ auf einer Liste ohne ausdrücklich gewählte Hero-Reihe: wechselt dabei sichtbar die Hero-Quelle (`Packages/PlayerCore/Sources/PlayerCore/Models/Appearance.swift:81`)?

---

### Fokus & Navigation (fokus-b)

1. **`.task` der Quellenliste nach dem Vollbild-Player** (entscheidet F-B-1): E1 auslaufen lassen, während E2 den Player schließen; im Fern-Log nach einer `streams`-Zeile mit der ID von E1 direkt nach dem Schließen suchen und Kopf gegen Zeilen halten. Zusätzlich E1 länger als die Cache-Dauer laufen lassen und prüfen, ob die Liste schon während E2 zurückspringt (dann scheitert der automatische Quellenwechsel in E2).
2. **Poppt eine gepushte Seite, wenn ihre NavigationLink-Zeile verschwindet?** (entscheidet F-B-3): Trakt-ID und -Secret über die Zeile „Trakt“ am Handy senden; Trakt-Login abschließen und beobachten, ob „Verbunden ✓“ stehen bleibt. Gleicher Mechanismus bei „Addon entfernen“ (`App/Sources/Views/Settings/AddonSettings.swift:78`–`81`): bleibt es bei einem Schritt zurück?
3. **Erstes Zusatzprofil anlegen** (F-B-2): erscheint „Wer schaut?“ über dem schließenden Blatt, und wo sitzt der Fokus danach?
4. **Wechsel der Navigationsart mit offener Autostart-Liste im Start-Tab** (F-B-5): startet beim Zurückwechseln die Wiedergabe von selbst? Und wo landet der Fokus in den Einstellungen nach dem Neuaufbau?
5. **Serie mit Startstaffel 1, sofort OK auf der fokussierten Folge, zurück** (F-B-4): sind die Folgentitel übersetzt?
6. **Fokusziel nach wegfallender Zeile** (F-B-6, F-B-9): „Build … installieren“, „Eingebaute Plaketten verwenden“, „Profil löschen“; bleibt der Fokus in der rechten Spalte?
7. **Doppeldruck auf „Abspielen“, Folgenzeile oder Kachel:** `navigate` hängt bei jedem Druck eine Route an (`App/Sources/PlayerApp.swift:187`), ohne Sperre; zwei „→ …“-Zeilen direkt hintereinander im Fern-Log wären der Beleg.
8. **Detailseite ohne IMDb-ID mit Beschreibung:** `applyFocus` setzt viermal `focus = .play`, obwohl kein View dieses Ziel trägt (`App/Sources/Views/DetailViews.swift:257`, `361`); bleibt der Fokus auf der Beschreibung?
9. **Quellenliste nach langer Wiedergabe:** kommt die neu geladene Liste in anderer Ordnung, verschiebt `keepFocusPosition` den Fokus von der gespielten Quelle auf die Zeile am selben Platz (`App/Sources/Views/DetailViews.swift:910`, `1004`)? Hängt am selben Neulauf wie Punkt 1.
10. **Trailer wird aufgelöst, während das Blatt „ganzer Text“ offen ist** (`App/Sources/Views/DetailViews.swift:306`–`307`): erscheint der Trailer nach dem Schließen, gar nicht, oder bleibt `trailer` hängen?

### Sync & Profile (sync)

1. **Gegenlesen nach `UserDefaults.set`** (`Packages/PlayerCore/Sources/PlayerCore/Store/TieredBlobStorage.swift:85-87`): Das Gegenlesen trifft den Prozess-Cache. Großen Block schreiben, App hart beenden, neu starten – steht der neue Stand in UserDefaults? Ein alter Stand dort gewänne beim Lesen gegen die jüngere Datei (`:77`).
2. **Ist Application Support beschreibbar?** Start-Log „Dateien in Application Support + Caches“ oder nur „Caches“ (`App/Sources/DefaultsStorage.swift:33`). Davon hängt ab, wie schwer S-1 (`.bak`) und S-10 wiegen.
3. **Reale Blockgrößen und Schreibdauer:** Start-Log „Defaults … Blöcke: …“ nach einigen Wochen; liegt `progress-…` noch darin? Mit „Ruckler protokollieren“ auf Einträge im 10-Sekunden-Abstand während der Wiedergabe achten (verworfener Kandidat S-14).
4. **Profilwahl gegen den Start-Abgleich** (S-3, S-4): mit gedrosseltem Netz sofort ein anderes Profil wählen; Log-Reihenfolge von Erneuerung, „angefangene Titel geholt“ und Profilwechsel.
5. **Lebensdauer des Trakt-Zugangstokens:** Wie oft erscheint eine Erneuerung im Log – bei jedem Kaltstart? Davon hängt die Häufigkeit von S-4 ab.
6. **Rotiert Trakt das Erneuerungstoken wirklich?** Nach einer Erneuerung das alte Token noch einmal verwenden lassen (S-4 Szenario 1, S-12 Szenario 1).
7. **Titel in „Weiterschauen“ nach Verlassen und Neustart** (S-13): wechselt die Kachel auf Titel und Poster aus dem Dienst?
8. **`Date.distantPast` im Fortschritt:** Ein Remote-Eintrag ohne lesbares `paused_at` wird mit `distantPast` gespeichert (`TraktClient.swift:143`, `SimklClient.swift:58`). Lässt sich die Datei danach wieder lesen? Wenn nicht, löst das S-11 im Normalbetrieb aus. Lässt sich auch als PlayerCore-Test klären.
9. **Unendliche Laufzeit** (Live-/HLS-Quelle): `record` prüft `duration > 0`, nicht `isFinite` (`WatchProgress.swift:55`). Liefert die Engine `inf`, scheitert jede weitere Speicherung der Sitzung mit „Fortschritt nicht gespeichert“.
10. **Schwellen 80 % / 92 %:** Bei 85 % verlassen – der Dienst verbucht ggf. „gesehen“, lokal bleibt der Titel angefangen (`ProgressBook.finishedAt = 0.92`). Gewollt?
11. **Apple TV schläft während der Wiedergabe ein / App wird beendet:** Es geht kein `stop`/`pause` hinaus; bleibt beim Dienst ein „schaut gerade“ stehen?

### Addons & Startseite (addons-a)

1. **HTTP-Cache der Addons (A-A-5):** Antwort-Kopfzeilen der eingerichteten Addons ansehen; zwei Suchen desselben Titels im Abstand von über 90 s, Antwortzeit je Addon im Fern-Log vergleichen. Danach einen Link bewusst ablaufen lassen und prüfen, ob „Neu auflösen … frischer Link“ wirklich spielt.
2. **Leere Antwort bei quellenlosen Titeln (A-A-4):** Schicken die eingerichteten Addons für unveröffentlichte Titel wirklich eine leere Liste (oder einen Hinweis-Eintrag)? Startseite mit einer Reihe unveröffentlichter Titel, Poster-Plaketten an; Abstände der Zeilen `Vorab-Quellen:` und `prefetch →` beobachten.
3. **Beitritt zu laufender Suche (A-A-7):** zwei Addons, eines langsam; Film-Detailseite → sofort Quellenliste.
4. **Hauptthread-Last großer Listen:** Titel mit mehreren hundert Quellen öffnen; ruckelt der Übergang in die Quellenliste?
5. **Ratenbegrenzung der Addons:** 12 Suchen/Minute beim Blättern; im Fern-Log auf Fehlereinträge in `… Hinweise:` achten.
6. **Größen „5.1 GB“/„7.1 GB“ (A-A-2) und „UHD“-1080p (A-A-1):** in echten Listen nach falschen Plaketten suchen.
7. **TorBox-Konto mit sehr vielen Downloads:** Anzahl im Log `… Video-Dateien im Konto` gegen die Weboberfläche halten (Seitengröße der Liste).
8. **Zeitgrenze und Abbruch:** Addon-Host blockieren; endet die Suche pünktlich nach der eingestellten Frist?
9. **Zwei gleichnamige Addon-Instanzen (A-A-9):** eine davon blockieren und prüfen, ob die Liste als vollständig gilt.

### Addons & Startseite (addons-b)

1. **Reihe wird unter dem Fokus ersetzt (aus A-B-4):** App beenden, starten, sofort in der ersten Reihe navigieren. Springt der Fokus oder die Scrollposition, wenn „katalog … im Hintergrund erneuert“ kommt? Messpunkt: Zeit zwischen dieser Zeile und der nächsten „Fokus …“-Zeile des Watchdogs. Zeigt sich ein Sprung, ist A-B-4 ein Befund (mittel).
2. **A-B-3:** Wie oft Bilder direkt nach dem Aufwachen scheitern (Log „bilder Kachelbild nicht geladen“ in den ersten 30 s nach dem Aktivwerden) und ob die Kacheln danach grau bleiben.
3. **A-B-5:** Ob die Startseite nach dem Schlaf über Nacht ohne Navigation „Heute neu“ neu lädt (Log „kalender n Serien …“).
4. **A-B-8:** Trakt-Liste mit Serie plus Folge derselben Serie anlegen; Verhalten der Reihe und des Fokus beobachten.
5. **Bewertungs-Icons (aus A-B-9):** Hero-Diashow mit eigenem Icon-Satz in Zeitlupe aufnehmen: Erscheint bei jedem Folienwechsel kurz die Textplakette vor dem Icon?
6. **TMDB-Listen über 20 Einträge:** `tmdbList` wird für Reihen nur mit `page=1` geholt (`Packages/PlayerCore/Sources/PlayerCore/Services/TMDBClient.swift:40`). Im Log „katalog <Liste>: n Einträge“ gegen die Listenlänge prüfen.
7. **Größenvarianten des TMDB-Bilddienstes:** Log „bilder Größenvariante nicht geladen“ zeigt, ob eine Stufe für einen Bildtyp fehlt (dann je Bild ein vergeblicher Abruf).
8. **Speicher während der Wiedergabe:** Logzeile „bilder Grenze … · belegt … (Wiedergabe)“: sinkt `belegt` nach dem Leeren wirklich (siehe P-9)?
9. **Start-Zeitachse:** „katalog Plattencache: n Reihen sofort gezeigt (ms)“, „home Vorladen: n Reihen in ms“, „home Reihe geladen … ms“ und Watchdog-Meldungen in den ersten 5 s (P-1 bis P-4).
10. **Trakt-Listen mit sehr vielen Einträgen:** Scroll-Flüssigkeit und Speicher (P-11).
11. **tvOS löscht Caches:** Nach vollem Speicher Kit-Reihen und Paket-Bilder: Platzhalter, dann Inhalte.

---

---

## Ungetestete, aber testwürdige Logik

### Sync & Profile (sync)

Spalte „Abgedeckt?“ wurde an den Tests unter `Packages/PlayerCore/Tests/PlayerCoreTests/` geprüft.

| Logik | Ort | Warum testwürdig | Abgedeckt? |
|---|---|---|---|
| `save()` nach fehlgeschlagenem `load()` | `Store/ProfileStore.swift:34-43` | Kern von S-1 | nein – `StoreTests.swift:33-39` prüft nur `.bak` |
| Unbekannte Enum-Werte in `Profile`, `Appearance`, `HomeRow`, `SourceKind` | `Models/Profile.swift:81-112` | S-2 | nein |
| Ein kaputtes von mehreren Profilen | `Store/ProfileStore.swift:53-58` | Totalausfall statt Teilausfall | nein |
| `ProgressStore.load` mit teilweise kaputter Datei | `Progress/WatchProgress.swift:135-139` | S-11 | nein |
| ISO-8601-Hin-und-zurück von `Date.distantPast` | `Progress/WatchProgress.swift:137`, `:142` | könnte S-11 im Normalbetrieb auslösen | nein |
| `record` mit nicht endlicher Laufzeit | `Progress/WatchProgress.swift:55` | verhindert jede weitere Speicherung | nein |
| `ProgressBook`-Größe / fehlende Obergrenze | `Progress/WatchProgress.swift:53-60` | S-10 | nein |
| `merge(remote:)`: Erhalt von `item`, fast gleiche Zeit | `Progress/WatchProgress.swift:114-125` | S-13 | teilweise (`SyncTests.swift:99-106`: nur Vorrang und Position) |
| `SyncRetry.scrobble(.stop)` bei 5xx | `Sync/APIRequest.swift:89-100` | S-6 | nur 404 (`SyncRetryTests.swift:74`) |
| `apply` mit dauerhaftem 4xx im Teilschritt | `Sync/SyncWrites.swift:37-52`, `:92-112` | S-8 | nein |
| Reihenfolge und Abbruch in `processSyncQueueOnce` | `App/Sources/AppModel+SyncQueue.swift:130-167` | S-8; liegt in der App | nein |
| Token-Erneuerung mit Profilbezug | `App/Sources/AppModel.swift:162-180` | S-4; liegt in der App | nein |
| Profilprüfung nach `await` in `syncRemoteProgress` | `App/Sources/AppModel.swift:183-194` | S-3; liegt in der App | nein |
| `record(…, imdb: nil, …)` nach gescheitertem Nachschlagen | `Sync/SyncQueue.swift:74-82` | S-5 | als Soll festgeschrieben (`SyncQueueTests.swift:67-69`) |
| `notePull` für sofort bestätigte lokale Merklisten-Einträge | `Sync/SyncQueue.swift:119-126` | Eintrag verschwindet nach Abruf (S-5) | nein |
| `TraktClient.poll` / `SimklClient.poll` bei 5xx, 429, 401/403 | `Sync/TraktClient.swift:95-106`, `Sync/SimklClient.swift:37-43` | S-15 | nur `pending`, `slowDown`, `success`, `expired` |
| `TraktClient.token` ohne `expires_in` | `Sync/TraktClient.swift:117-123` | Token läuft dann „nie ab“ (`expiresAt == nil`) | nein |
| `TieredBlobStorage.read`, wenn UserDefaults älter ist als die Datei | `Store/TieredBlobStorage.swift:76-79` | UserDefaults gewinnt immer | nein |
| Budget mit verwaisten Blöcken gelöschter Profile | `Store/TieredBlobStorage.swift:119-126` | S-9 | nein |

Pfade ohne Präfix liegen unter `Packages/PlayerCore/Sources/PlayerCore/`.

### Addons & Startseite (addons-a)

Übernommen und stichprobenhaft gegen `Packages/PlayerCore/Tests` geprüft (Suche nach den jeweiligen Bezeichnern):
- `StreamTraits.parse`: Auflösung bei mehreren Angaben (A-A-1), Kanäle neben Größen (A-A-2), `parseSize` (kein eigener Test; Grenzen, „GiB“, „TB“ als Dienst-Kürzel, Komma-Dezimal).
- Sprache: nur sieben Flaggen und „GERMAN/DEUTSCH/GER/MULTI“ werden erkannt (`StreamTraits.swift:63`–`66`); „Dual“ und ausgeschriebene Sprachen nicht – kein Test schreibt das fest.
- `ReleaseName.service` mit Klammer-Formen (`[WEB-DL]`, `[AD]`, `[EN+]`) – A-A-14.
- `AddonClient.encode`/`resourceURL` mit Sonderzeichen in `extra` und in IDs.
- `AddonClient.parseManifest`: Manifest-Adresse, deren Pfad selbst `?addon=` oder `#` enthält.
- `AddonSearch.withDeadline`: Abbruch des Aufrufers gegen Fristablauf; Verhalten, wenn `op` den Abbruch ignoriert.
- `AddonMetaFetch.wait`/`value`/`limited` (Wettlauf Ergebnis gegen Frist gegen Abbruch) und `AsyncLimiter` unter Abbruch – vom Erstbericht genannt, hier nicht nachgeprüft.
- `StreamDedupe.unique` mit unterschiedlichem Cache-Zustand der Dubletten (verworfener Kandidat A-A-10) und gleichem `infoHash` ohne `fileIdx` bei verschiedenen Dateien.
- Zwei gleichnamige Addons in `StreamCacheUpdate.apply` und `StreamDedupe.unique` (A-A-9).
- Die Regel „alle Addons leer“ (A-A-4) liegt in der App und ist ungetestet; ebenso der gesamte Ablauf von `AppModel.streams` (Beitritt, Epoche, Rückgabe nach Profilwechsel) und `StreamPrefetcher`.
- `TorBoxClient.parseList` mit fehlerhaften Antworten; der Filter „sample“ wirft auch echte Dateien mit diesem Wort im Namen weg (`TorBox.swift:108`).
- `YouTubeResolver.resolve`: Reihenfolge der Clients, Abbruch, Gesamtzeit.

### Addons & Startseite (addons-b)

Übernommen und gegen den Code geprüft (vorhandene Tests: `FusionKitTests.swift`, `UpcomingTests.swift`):

- `FusionKitSync.apply` mit leeren Einstellungen und vorhandenen Kit-Reihen (A-B-1). `FusionKitTests` deckt „Kit aus bei vorhandener Auswahl“ und „Quelle nicht geladen“ ab, nicht „Einstellungen fehlen“.
- `TMDBClient.nextEpisodes`: `next` außerhalb des Fensters bei `last` im Fenster (A-B-11); `next` in anderer Staffel als `last`.
- `TraktClient.items` mit Staffel-/Folgen-Einträgen (A-B-8); Entdoppeln in der Reihen-Ladung.
- `FusionImport.parse` mit eingespritztem `now`: Datumsfilter bei `releaseStatus: "released"` (A-B-10); unerwartete Feldtypen (`limit` als Text, numerische `id`).
- `TimedCache`: `restore` + `needsRefresh` + `markFailed` im Zusammenspiel, `keysNeedingRefresh(includingRestored:)`.
- `CatalogSnapshot.init(entries:)`: Verdrängen der Startseiten-Reihen durch 60 jüngere Quellen (P-5).
- `ImageURLVariant.tmdb` an den Stufengrenzen: benötigte Breite 512 bei `w500` (P-6).
- `Upcoming.today` am Tageswechsel mit eingespritztem `today` (Grundlage für den Tagesschlüssel aus A-B-5).
- Fehlerklassifikation für Bilder (dauerhaft/vorübergehend, A-B-3) und ein Cache-Typ mit Sprachschlüssel (A-B-2): beide müssten erst als reine Logik nach PlayerCore gezogen werden.
- Aus dem Erstbericht ohne eigene Nachprüfung übernommen: `TVmazeAirtimes.stamps`/`tidy` und `TVmazeGate.wait` mit eingespritzter Uhr, `GenrePaging.receive` mit vorbelegtem ersten Block, `RatingIconSet.withDeadline`/`collect`, `FetchRetryGate`, `MDBList.parse` für „ungültiger Schlüssel“.

---
