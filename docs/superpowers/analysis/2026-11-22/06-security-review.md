# 06 · Security-Review

Stand: Branch `integ`, Commit `b2188a2` (Build 249). Rein lesend und statisch erhoben; Laufzeitverhalten ist aus dem Code **abgeleitet**. Alle `Datei:Zeile`-Angaben beziehen sich auf diesen Commit.

Methodik: Skill `security-review` und die Methodik von `claude-security:scan` (Threat-Model → Recherche →
adversariale Verifikation), ohne Patches. Teil A ist der Review des Codes nach der Gegenprüfung durch einen zweiten
Gutachter. Teil B ist die Durchsuchung der gesamten Git-Historie. In diesem Bericht steht kein Geheimniswert, kein
Name, keine E-Mail-Adresse und keine IP; bei Funden sind nur Commit, Datei und Art genannt.

**Bedrohungsmodell [N]:** Ein Angreifer befindet sich im selben WLAN. Er darf weder Schlüssel lesen noch Einstellungen,
Addons oder Profile ändern, noch die App zu Aktionen bringen. Addon-Antworten und Antworten externer Dienste gelten als
nicht vertrauenswürdig.

## Ergebnis in Kürze

| Schweregrad | Code (Teil A) | Git-Historie (Teil B) |
|---|---:|---:|
| kritisch | 0 | 0 |
| hoch | 2 (SEC-1, SEC-3) | 0 |
| mittel | 3 (SEC-2, SEC-4, SEC-6) | 1 (GIT-1) |
| niedrig | 12 | 4 |

- **SEC-1:** Die Handy-Seite läuft über Klartext-HTTP. Wer das Token mitliest, bekommt über `/export` alle Schlüssel und
  kann alle Profile ersetzen, ohne Rückfrage am Fernseher.
- **SEC-3:** Die App spricht atvloadly ohne Anmeldung über HTTP an. Ob ein Dritter im WLAN damit ein fremdes Paket
  installieren kann, hängt am Dienst selbst und muss am Netz geprüft werden.
- **GIT-1:** Sechs Merge-Commits tragen einen Vornamen und eine E-Mail-Adresse mit Rechner- und Routernamen.
- **Keine Zugangsdaten** in 1 670 Datei-Ständen aller 320 Commits und 78 Refs; keine hart codierten Schlüssel im Code.

Gegenmaßnahmen im [Plan](../../plans/2026-11-22-verbesserungen.md): Build 1 (Tasks 1.1, 1.4 bis 1.7) und Build 2
(Tasks 2.2, 2.3). **[C]** Die Bereinigung der Git-Historie (GIT-1) ist nicht Teil des Plans, weil sie alle Hashes,
Tags und Releases ändert; sie ist eine eigene Entscheidung des Nutzers (Vorgehen unter GIT-1).

---

# Teil A: Code

Zweitgutachten zum Erstbericht des Code-Reviews. Rein lesend; Laufzeitverhalten ist aus dem Code abgeleitet, nichts wurde gebaut oder ausgeführt. Keine Schlüssel, Namen oder Adressen im Bericht.

**Ergebnis:** 15 Befunde des Erstberichts geprüft – keiner ganz widerlegt, 4 herabgestuft (SEC-2, SEC-5, SEC-7, SEC-8), 3 Teil-Aussagen bzw. Gegenmaßnahmen verworfen (zu SEC-1, SEC-4, SEC-7). 2 neue Befunde (SEC-16, SEC-17).
Stand danach: **2 hoch, 3 mittel, 12 niedrig, 0 kritisch.**

**Selbst vollständig gelesen:** `Phone/PhoneInput.swift`, `Phone/PhoneHome.swift`, `Phone/PhoneImportDetect.swift`, `PhoneInputView.swift`, `AppModel+PhoneHome.swift`, `RemoteLog.swift`, `LogRedact.swift`, `AppUpdate.swift`, `AppUpdater.swift`, `App/project.yml`, `build.yml`, `tools/logcollector.py`, `ProfileStore.swift`. In Ausschnitten (zitierte Stellen plus Umfeld): `DiskCacheProxy.swift` (Zeilen 480–530, 595–783), `AppModel.swift` (535–605), `UpdatePage.swift`, `SystemMaintenanceRows.swift`, `ImagePipeline.swift`, `AddonClient.swift`, `AddonSubtitles.swift`, `AddonStreamKind.swift`, `PlayerPictureSound.swift`, `IntroDB.swift`, `DefaultsStorage.swift`, `Profile.swift`, `Packages/AetherFEL/Package.swift`.

---

## Threat-Model

**Angreifer:** Gerät im selben WLAN. Er kann mitlesen (bei WPA2-PSK mit bekanntem Passwort nach mitgehörtem Handshake, sonst per ARP-Spoofing), Verkehr umleiten und verändern, Bonjour-Dienste und `.local`-Namen ankündigen. Addon- und Dienst-Antworten gelten als nicht vertrauenswürdig.
**Schutzziele:** keine Schlüssel lesen, keine Einstellungen/Addons/Profile ändern, keine Aktionen der App auslösen. Reine Verfügbarkeit (Absturz) liegt außerhalb dieser Ziele und wird deshalb höchstens „niedrig“ gewertet.

**Assets**
- API-Schlüssel `Profile.apiKeys` – `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:25`
- OAuth-Tokens Trakt/Simkl `Profile.syncTokens` – `Profile.swift:31`
- Addon-Adressen mit eingebetteten Zugangsdaten `Profile.addons` – `Profile.swift:21`
- Alles zusammen im Export: `App/Sources/AppModel.swift:556` → `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:45-49`
- Sehgewohnheiten (Titel, IDs, Reihen der Startseite), Hostnamen privater Dienste
- Apple-ID des atvloadly-Eintrags (kommt im Klartext über die Leitung, `AppUpdate.swift:321`)
- Integrität der installierten App (Update-Weg)

**Angriffsflächen**

| Was | Wo | Erreichbar | Schutz laut Code |
| --- | --- | --- | --- |
| Handy-Eingabe, HTTP-Server Port 8765 | `App/Sources/Views/PhoneInputView.swift:14`, `:20` | alle Interfaces (IPv4 und IPv6), Klartext | Token 10 Zeichen aus 31 (≈ 49,5 Bit, System-Zufall) in der Adresse, `Phone/PhoneInput.swift:106-109`, `:114`; Listener von `onAppear` bis `onDisappear`, `PhoneInputView.swift:118-119` – **ohne Ablaufzeit** (SEC-16) |
| Fern-Log, ausgehend an Bonjour `_playerlog._tcp` | `App/Sources/RemoteLog.swift:21-25`, `:54-56` | jeder Ankündiger im WLAN | keiner; Zeilen laufen durch `LogRedact.text` (`:42`) |
| atvloadly-Suche, Bonjour `_workstation._tcp` + fester Probename | `App/Sources/AppUpdater.swift:144-161`, `AppUpdate.swift:178`, `:239-246` | jeder Ankündiger bzw. mDNS-Antworter | nur `GET /api/version` |
| atvloadly-Aufrufe (REST + MCP), ausgehend | `AppUpdate.swift:678-680`, `:706-707`, `:716-737` | Klartext-HTTP als Standard (`:184`, `:188`) | keine Anmeldung; Paketadresse ist eine Konstante (`:87`, `:697`) |
| Plattencache-Proxy | `App/Sources/Playback/DiskCacheProxy.swift:605-609` | nur 127.0.0.1 | Loopback-Bindung, `acceptLocalOnly`, Gegenstellenprüfung (`:671`), UUID-Token (`:520`, `:680`), 10-s-Frist (`:674`) |
| Log-Empfänger (Entwicklerwerkzeug) Port 8770 | `tools/logcollector.py:35` | 0.0.0.0 | keiner |
| Addon-/Dienst-Antworten | `Addons/AddonClient.swift:14`, `App/Sources/ImagePipeline.swift:286` | über Addon oder MITM bei HTTP-Addon | ATS abgeschaltet (`App/project.yml:42`) |

**Vertrauensgrenzen (korrigiert)**
1. WLAN ↔ Apple TV: Handy-Seite, Bonjour, atvloadly – alles Klartext und ohne Gegenstellen-Nachweis. Korrektur zum Erstbericht: Verschlüsselung im Browser (WebCrypto) steht auf einer per `http://<IP>` geladenen Seite nicht zur Verfügung; TLS mit eigenem Zertifikat erzeugt am Handy eine Warnung. Die Grenze lässt sich daher nur über **Bestätigung am Fernseher** und über **Eingabe von Geheimnissen außerhalb der Webseite** halten.
2. Internet-Dienste ↔ App: HTTPS mit Standardprüfung, kein eigener TLS-Delegate. GitHub-Abfragen mit festem Pfad (`AppUpdate.swift:82-87`).
3. Addons ↔ App: beliebige http(s)-Hosts; das Addon bestimmt Bild-, Stream-, Untertitel-Adressen und Anfrage-Kopfzeilen.
4. CI ↔ Gerät: unsigniertes IPA aus einem Release, ohne Prüfsumme auf Geräteseite. Korrektur: Wer Schreibrecht im Repo hat, kann Release-Dateien auch direkt ersetzen; die Stelle der `if`-Bedingung im Workflow ist dafür unerheblich.

---

## Bestandene Befunde

### SEC-1: Handy-Eingabe über Klartext-HTTP – das mitgelesene Token gibt alle Schlüssel frei und erlaubt das Ersetzen aller Profile
- **Ort:** `App/Sources/Views/PhoneInputView.swift:27`, `:20`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:114`, `:121-123`, `:142`, `:177`, `:191`, `App/Sources/AppModel.swift:556`, `:587-593`
- **Angriffsszenario:**
  1. Angreifer liest im WLAN mit oder setzt sich per ARP-Spoofing zwischen Handy und Apple TV.
  2. Nutzer scannt den QR-Code; die erste Anfrage `GET /?t=<Token>` steht im Klartext auf der Leitung, ebenso jede weitere (`/submit?t=…`, `/home?t=…`, `/export?t=…`).
  3. Angreifer ruft mit dem Token `GET /export` ab und erhält alle Profile mit API-Schlüsseln, Trakt/Simkl-Tokens und Addon-Adressen.
  4. Oder er sendet `POST /submit` mit `backup_json`: `AppModel.swift:587-590` ersetzt ohne Rückfrage alle Profile (eigene Addons, eigene atvloadly-Adresse). Einzelne Schlüssel und Addons gehen genauso.
  5. Ohne eigenes Zutun: Alles, was der Nutzer eintippt (`key_trakt_secret`, `key_torbox`, Addon-Adresse mit Zugangsdaten), und ein vom Nutzer geladener Export laufen im Klartext mit.
  6. Aktive Variante: Der Angreifer verändert die ausgelieferte Seite (eigenes Skript) und liest Eingaben direkt am Handy ab.
- **Voraussetzung:** Mitlesen oder MITM im WLAN, während die Ansicht am Fernseher offen ist. Das Token gilt bis zum Schließen der Ansicht, beliebig oft, von jedem Gerät (SEC-16). Erraten ist bei ≈ 49,5 Bit nicht nötig und nicht realistisch.
- **Auswirkung:** Abfluss aller Geheimnisse auf einmal; vollständige Übernahme der Konfiguration. Beide Schutzziele (lesen, ändern) verletzt.
- **Schweregrad · Sicherheit:** hoch · bestätigt (Klartext, Reichweite des Tokens, Restore ohne Rückfrage); das Mitlesen selbst hängt vom WLAN ab (plausibel).
- **Gegenmaßnahme (auf tvOS machbar):**
  1. **Bestätigung am Fernseher** für alles, was liest oder überschreibt: Export, „Sicherung wiederherstellen“, Schlüssel setzen, Addon hinzufügen, atvloadly-Adresse. Die Ansicht hat bereits ein fokussierbares Element (`PhoneInputView.swift:112`); dort einen Dialog mit Zusammenfassung zeigen („Sicherung ersetzt 3 Profile“, „Addon von Host …“, „TorBox-Schlüssel endet auf …“). Immer nur eine offene Anfrage; ohne Bestätigung innerhalb von 60 s verfällt sie.
  2. **Export nur verschlüsselt:** Der Fernseher verschlüsselt mit CryptoKit (ChaChaPoly) unter einem Zufallsschlüssel, den er am Bildschirm als Code zeigt; beim Wiederherstellen wird der Code am Fernseher eingegeben. Auf der Leitung und in den Downloads des Handys liegt dann nur Chiffrat.
  3. **Geheimnisse nicht über die Webseite:** Für Schlüssel ein Textfeld am Fernseher anbieten; tvOS blendet dafür die Tastatur am iPhone ein (Einfügen möglich, Übertragung über Apples eigenes gekoppeltes Protokoll). Die Webseite bleibt für Unkritisches (Startseite ordnen, Listen-Links).
  4. **Token entwerten:** Ablaufzeit (z. B. 10 Minuten), Bindung an die Adresse des ersten Geräts (hält reine Mitleser ab, keinen ARP-Angreifer), Stopp bei inaktiver App (SEC-16).
  Nicht tragfähig: Verschlüsselung im Browser über WebCrypto (auf `http://<IP>` nicht verfügbar) und TLS mit eigenem Zertifikat (Browser-Warnung) – siehe „Verworfene Kandidaten“.
- **Gegenprüfung:** Selbst nachvollzogen: Jede Route hängt allein an `r.query["t"] == token || r.form["t"] == token`, das Token steht in jeder Anfragezeile, und `importBackup` weist `stored` ohne Rückfrage und ohne Sicherungskopie zu – kein übersehener Schutz gefunden.

### SEC-3: Update-Weg spricht mit atvloadly ohne Anmeldung über Klartext-HTTP – Apple-ID lesbar, Fremd-Paket im WLAN auslösbar
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:184`, `:188`, `:678-680`, `:700-702`, `:706-707`, `:716-731`, `:321`, `:403`
- **Angriffsszenario:**
  - **A (ohne die App, Eigenschaft des Dienstes):** Angreifer fragt `GET /api/apps` und `/api/devices` am Pi ab, bildet md5 der dort gelieferten Apple-ID und ruft `install_app` mit eigener `ipa_url` auf – genau die Aufrufe, die die App ohne jeden Auth-Kopf sendet.
  - **B (MITM):** ARP-Spoofing zwischen Apple TV und Pi; im `POST /mcp` das Feld `ipa_url` austauschen. Die Prüfung in `:697` schützt nur den Wert, den die App absendet.
  - **C (passiv):** Beim Update liest der Angreifer die Antwort auf `/api/apps` mit; sie enthält das Feld `account` (Apple-ID) im Klartext.
- **Voraussetzung:** Gerät im WLAN, Pi erreichbar; für B und C ein vom Nutzer gestartetes Update. Für A muss atvloadly Aufrufe ohne Anmeldung annehmen – der App-Code belegt das für ihre eigenen Aufrufe, das Verhalten des Dienstes selbst liegt nicht im Repo.
- **Auswirkung:** Fremder Code auf dem Apple TV. Trägt das Paket dieselbe Bundle-ID und wird mit demselben Konto signiert, ersetzt es die App und erbt deren Ablage mit allen Schlüsseln (SEC-14). Dazu Offenlegung der Apple-ID.
- **Schweregrad · Sicherheit:** hoch · plausibel (A hängt am Dienst; C ist aus dem App-Code bestätigt, sobald der Dienst das Feld liefert – die App liest es selbst aus).
- **Gegenmaßnahme:** Vorrangig Betrieb: Port des Dienstes am Pi per Firewall nur für das Apple TV öffnen, oder Reverse-Proxy mit Token davor. In der App: optionales Feld „atvloadly-Token“ und `Authorization`-Kopf in jeder Anfrage (`AppUpdateClient.get`, `start`, `mcpInstall`), `https://` unterstützen, bei `http://` einen Hinweis in der Update-Seite. Paket-Integrität siehe SEC-7.
- **Gegenprüfung:** In `AppUpdate.swift` gibt es an keiner Stelle einen Auth-Kopf für atvloadly, und `normalize` setzt ohne Schema `http://` – der Befund hält; Variante A bleibt bis zur Probe am Netz „plausibel“.

### SEC-2: Fern-Log geht ungefragt an jeden, der `_playerlog._tcp` im WLAN ankündigt
- **Ort:** `App/Sources/RemoteLog.swift:21-25`, `:30`, `:49-56`, `:62`, `:76-77`, `App/Sources/Views/Settings/SystemMaintenanceRows.swift:29-32`, `App/project.yml:39`
- **Angriffsszenario:**
  1. Angreifer kündigt den Dienst an und beantwortet `POST /log` mit einer Zeile, die ` 200 ` enthält.
  2. Die App schickt innerhalb von 5 s den Puffer (bis 500 Zeilen) und danach laufend alles; nach „Erfolg“ löscht sie die Zeilen (`:77`), der echte Empfänger sieht sie nie.
  3. Bei zwei Ankündigern entscheidet `results.first` einer ungeordneten Menge – nicht vorhersagbar, der Angreifer gewinnt zumindest zeitweise.
- **Voraussetzung:** Gerät im WLAN, mDNS erlaubt. Keine Nutzeraktion; der Browser läuft ab dem ersten Log-Aufruf dauerhaft, einen Schalter gibt es nicht (die Einstellungen zeigen nur den Zustand).
- **Auswirkung:** Sehgewohnheiten (Titel, IDs, Addon- und Quellennamen), Hostnamen privater Dienste, Einstellungsänderungen; dazu, was `LogRedact` durchlässt (SEC-8). Außerdem lässt sich die Diagnose unterdrücken. Schlüssel stehen bestimmungsgemäß nicht im Log.
- **Schweregrad · Sicherheit:** mittel (Erstbericht: hoch) · bestätigt. Herabgestuft, weil das Log nach Entwurf keine Schlüssel enthält und kein Schutzziel „ändern/auslösen“ berührt ist; gelten Sehgewohnheiten als gleichrangig schutzwürdig, ist „hoch“ vertretbar.
- **Gegenmaßnahme:** Fern-Log standardmäßig aus, Schalter in Einstellungen → System → Diagnose. Beim Einschalten den gefundenen Empfänger mit Namen anzeigen und per Fernbedienung bestätigen; gemerkt wird Dienstname plus ein gemeinsames Geheimnis (einmal am Fernseher eingegeben oder vom Empfänger im TXT-Record als Prüfwert angeboten und am Bildschirm verglichen). Jede Sendung trägt einen HMAC (CryptoKit); der Empfänger verwirft Fremdes. Ohne gekoppelten Empfänger nur der Speicherpuffer.
- **Gegenprüfung:** Der Code enthält weder Schalter noch Bindung an einen Empfänger; die Erfolgsprüfung ist ein Textvergleich auf ` 200 ` – Befund hält, Schweregrad angepasst.

### SEC-4: ATS vollständig abgeschaltet – HTTP-Addons senden ihre Adresse samt Zugangsdaten im Klartext
- **Ort:** `App/project.yml:42`, `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:64`, `:14`
- **Angriffsszenario:**
  1. Ein Addon ist als `http://…/<Konfiguration>/manifest.json` eingetragen (der in `project.yml:40` genannte Fall „im Heimnetz“).
  2. Jede Katalog- und Quellen-Anfrage trägt die Konfiguration (Debrid-/Indexer-Schlüssel) im Pfad; der Mitleser im WLAN sieht sie und die Antworten mit Direktlinks.
  3. Aktiv: Antworten fälschen und eigene Stream-, Bild- und Untertitel-Adressen einschleusen (führt zu SEC-6 und SEC-9).
- **Voraussetzung:** Mindestens ein Addon über `http://`; Mitlesen oder MITM im WLAN.
- **Auswirkung:** Verlust der im Addon hinterlegten Schlüssel; Manipulation der angezeigten Inhalte.
- **Schweregrad · Sicherheit:** mittel · bestätigt (Konfiguration und Annahme von `http://`), Ausnutzung plausibel.
- **Gegenmaßnahme:** Beim Eintragen einer `http://`-Addon-Adresse am Fernseher warnen („Zugangsdaten gehen unverschlüsselt durchs WLAN“) und für Hosts außerhalb des Heimnetzes ablehnen (Regel `AtvloadlyAddress.isHomeNetwork` wiederverwenden). `NSAllowsArbitraryLoads` entfernen und `NSAllowsLocalNetworking` behalten – das sperrt HTTP nur zu fremden Hosts; **der Heimnetz-Fall bleibt Klartext**. Dafür hilft nur HTTPS vor dem Addon (Reverse-Proxy mit gültigem Zertifikat). Vor dem Entfernen prüfen, ob HTTP-Quellen über `URLSession` (Plattencache-Abruf) noch laufen.
- **Gegenprüfung:** `parseManifest` nimmt `http://` gleichwertig an und es gibt nirgends einen Hinweis; die vom Erstbericht genannte ATS-Änderung allein schließt die Lücke im WLAN nicht (siehe „Verworfene Kandidaten“).

### SEC-6: Addon-Antworten lenken Anfragen des Apple TV auf beliebige Ziele im Heimnetz
- **Ort:** `App/Sources/ImagePipeline.swift:284-287`, `:216-217`, `App/Sources/Views/DetailViews.swift:920`, `App/Sources/AppModel+Reresolve.swift:20`, `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonStreamKind.swift:49-52`, `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonSubtitles.swift:117`, `App/Sources/Views/Player/PlayerPictureSound.swift:193-194`
- **Angriffsszenario:**
  1. Ein fremd betriebenes Addon (oder ein per MITM verändertes HTTP-Addon, SEC-4) liefert im Katalog eine Bild-Adresse auf ein Gerät im Heimnetz.
  2. Beim Anzeigen der Reihe ruft das Apple TV sie ab – ohne Auswahl durch den Nutzer; der Bildlader prüft weder Schema noch Ziel, Antworten ohne HTTP-Status zählen als Erfolg (`?? true`).
  3. Beim Abspielen: Stream-Adresse auf einen Dienst im Heimnetz, Kopfzeilen frei aus `behaviorHints.proxyHeaders.request` (auch `Authorization`, `Cookie`, `Host`).
  4. Untertitel-Adressen ohne http(s) gehen unverändert an die Engine (`return (address, nil, nil)`).
- **Voraussetzung:** Nicht vertrauenswürdige Addon-Antwort (laut Auftrag anzunehmen).
- **Auswirkung:** Blinde GET-Anfragen aus dem Heimnetz heraus mit Kopfzeilen nach Wahl des Addons – die App wird zu einer Aktion gebracht. Keine Rückgabe der Antwort an das Addon; lokale Dateien höchstens als Bild oder Untertitel am Bildschirm.
- **Schweregrad · Sicherheit:** mittel · bestätigt für Bilder und Streams; Verhalten der Engine bei `file://` plausibel (nicht im Repo).
- **Gegenmaßnahme:** Eine reine Funktion in PlayerCore (`AddonURLPolicy.allows(url, from: addonBase)`): nur `http`/`https`; private Ziele (RFC 1918, link-local, Loopback, `.local`, Namen ohne Punkt) nur, wenn das liefernde Addon denselben Host hat. `proxyHeaders.request` auf eine Namensliste begrenzen (`User-Agent`, `Referer`, `Origin`). Untertitel-Adressen ohne http(s) verwerfen. Aufrufer: Bildlader, Stream-Start, Untertitel, Plattencache.
- **Gegenprüfung:** Alle vier zitierten Stellen gelesen; die einzige Schema-Prüfung (`hasWebURL`) lässt jedes http(s)-Ziel zu, eine Zielprüfung gibt es nicht.

### SEC-5: Handy-Server puffert bis zu 8 MB je Verbindung vor der Token-Prüfung, ohne Verbindungs- oder Zeitlimit
- **Ort:** `App/Sources/Views/PhoneInputView.swift:38-45`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:13`, `:27-31`, `:114`
- **Angriffsszenario:**
  1. Angreifer findet Port 8765 offen (Ansicht am Fernseher offen).
  2. Viele Verbindungen, je `POST` mit `Content-Length` knapp unter 8 MB und unvollständigem Körper; `parse` meldet `incomplete`, der Puffer bleibt.
  3. Speicher läuft voll oder – bei sehr kleinen Stücken – die Oberfläche hängt, weil jedes Stück den ganzen Puffer kopiert und neu parst (alles auf dem MainActor).
- **Voraussetzung:** Ansicht offen; Gerät im WLAN. Kein Token nötig.
- **Auswirkung:** Absturz oder Einfrieren der App; eine laufende Eingabe geht verloren. Kein Lesen, kein Ändern.
- **Schweregrad · Sicherheit:** niedrig (Erstbericht: mittel) · bestätigt (Ablauf), Wirkung am Gerät plausibel. Herabgestuft: nur Verfügbarkeit, nur solange die Ansicht offen ist.
- **Gegenmaßnahme:** Kopf zuerst auswerten und das Token aus der Anfragezeile prüfen, bevor ein Körper angenommen wird; höchstens 4 gleichzeitige Verbindungen; 10 s Frist je Anfrage (Muster: `DiskCacheProxy.swift:674`); Körper für `/home` auf wenige KB begrenzen; Empfang auf eigener Queue.
- **Gegenprüfung:** Die Token-Prüfung steht ausschließlich in `handle`, das erst nach `.complete` läuft; ein Zeit- oder Verbindungslimit existiert nicht.

### SEC-7: Installationspaket ohne Prüfsumme oder Signatur; Build und Commit stammen aus dem frei editierbaren Release-Text
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:118-127`, `:697`, `:705-709`, `.github/workflows/build.yml:155-156`, `:184`, `:257-258`
- **Angriffsszenario:**
  1. Jemand mit Schreibrecht im Repo (gestohlenes Token, kompromittierte Build-Abhängigkeit, SEC-15) ersetzt `Player.ipa` im Release und setzt den Text „Build N · Commit …“.
  2. Nutzer wählt „Nach Update suchen“ und installiert; atvloadly lädt und signiert, was unter der festen Adresse liegt.
  3. Nebenweg: Über `sourceUpdate` wählt atvloadly selbst das Release; die Prüfung in `:697` greift dort nicht, es kann ein anderes Paket installiert werden als das angezeigte.
- **Voraussetzung:** Schreibzugriff auf Repo oder Releases. Nicht aus dem WLAN erreichbar (GitHub über HTTPS, fester Pfad).
- **Auswirkung:** Fremder Code auf allen Geräten, die aktualisieren.
- **Schweregrad · Sicherheit:** niedrig (Erstbericht: mittel) · bestätigt (Ablauf). Herabgestuft: liegt außerhalb des WLAN-Modells und setzt eine Kompromittierung des Repos voraus.
- **Gegenmaßnahme:** In der CI SHA-256 des IPA in den Release-Text schreiben und „Build · Commit · SHA-256“ mit Ed25519 signieren; öffentlicher Schlüssel in der App, Prüfung mit CryptoKit vor dem Auftrag an atvloadly. Release-Jobs an ein GitHub-Environment mit Branch-Beschränkung binden, Tag-Regeln für `app-main` und `build-*`. Die Bindung „geprüftes Paket = installiertes Paket“ bleibt lückenhaft, solange atvloadly selbst lädt – deshalb zusätzlich SEC-3.
- **Gegenprüfung:** `parseRelease` vergleicht nur Name und Adresse des Assets und liest Zahlen aus dem Text; eine Rückstufung auf niedrigere Build-Nummern ist dagegen abgefangen (`:156`).

### SEC-8: `LogRedact` lässt einzelne Muster durch
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Logging/LogRedact.swift:80-81`, `:92-94`, `:153`, `:158-160`, `:166-167`, `:199-207`
- **Angriffsszenario:**
  1. Angreifer empfängt das Fern-Log (SEC-2).
  2. Eine Zeile enthält eine Adresse, deren letzter Pfadteil ein kurzes Kennzeichen ist (unter 16 Zeichen gemischt bzw. unter 32 Zeichen) – es bleibt stehen.
  3. Weitere Lücken: Zugangsdaten mit „/“ im Passwort werden zum „Host“; Namen wie `auth=`, `sig=`, `code=`, `Cookie:`, `Basic …` sind nicht in der Liste; Hostnamen und Dateinamen (Titel) bleiben immer sichtbar.
- **Voraussetzung:** SEC-2 oder Zugriff auf die Logdatei; ein Dienst, dessen Kennzeichen eines der Muster trifft.
- **Auswirkung:** Einzelne Kennzeichen und private Hostnamen im Log.
- **Schweregrad · Sicherheit:** niedrig (Erstbericht: mittel) · bestätigt (von Hand an den Regeln nachvollzogen, nicht ausgeführt). Herabgestuft: Query und alle Pfadteile außer dem letzten fallen immer weg; eine Logstelle, die tatsächlich einen Schlüssel in dieser Form schreibt, wurde nicht gefunden.
- **Gegenmaßnahme:** Letzten Pfadteil nur zeigen, wenn er wie ein Dateiname mit bekannter Endung oder eine `tt…`-ID aussieht, sonst „…“. Schlüsselwortliste um `auth`, `authorization`, `cookie`, `sig`, `signature`, `code`, `pin`, `session`, `pass`, `pwd` erweitern; `Basic` wie `Bearer` behandeln; bei „@“ im Pfad die ganze Adresse auf den Host kürzen.
- **Gegenprüfung:** Beide Beispiel-Eingaben des Erstberichts ergeben nach den Regeln in `redactAfterScheme` und `looksSecret` genau die genannten Ausgaben.

### SEC-9: Antworten von Addons, Kit-Dateien und Bildquellen ohne Größenlimit im Speicher
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Addons/AddonClient.swift:14`, `App/Sources/ImagePipeline.swift:216`, `:286`, `App/Sources/FusionKitStore.swift:269`, `:303`
- **Angriffsszenario:** (1) Addon oder MITM bei HTTP-Addon liefert für einen Katalog der Startseite einen stark gepackten, entpackt sehr großen Körper. (2) `URLSession` entpackt, die App dekodiert den ganzen Block. (3) tvOS beendet die App; nach dem Neustart lädt dieselbe Reihe erneut.
- **Voraussetzung:** Nicht vertrauenswürdige Addon- oder Dienst-Antwort.
- **Auswirkung:** Verfügbarkeit, mögliche Absturzschleife.
- **Schweregrad · Sicherheit:** niedrig · bestätigt (fehlendes Limit), Absturz plausibel.
- **Gegenmaßnahme:** Gemeinsamer begrenzter Abruf über `bytes(for:)` mit Zähler (Muster: `App/Sources/CollectionLinkStore.swift:251-265`): 8 MB für JSON, 20 MB für Bilder; Listenlängen nach dem Dekodieren kappen.
- **Gegenprüfung:** `URLSessionFetcher.data(from:)` gibt den vollständigen Körper ohne Zähler zurück; an den genannten Bildstellen ebenso.

### SEC-10: Präparierte IntroDB-Antwort beendet die App beim Abspielen
- **Ort:** `Packages/PlayerCore/Sources/PlayerCore/Services/IntroDB.swift:117`, `:59`, `:74`, `App/Sources/Views/Player/SkipSegmentButton.swift:108`
- **Angriffsszenario:** (1) Der Dienst liefert `start_sec` = 2^63 − 1024 und `end_sec` = 2^63. (2) Beide sind endlich, die Differenz 1024 s besteht die Prüfung in `:59`. (3) Die Logzeile bildet `Int($0.end)` – der Wert liegt außerhalb von `Int`, Laufzeitfehler. Jeder Start dieses Titels beendet die App.
- **Voraussetzung:** Manipulierte Antwort des Dienstes (HTTPS – nicht aus dem WLAN).
- **Auswirkung:** Absturz bei bestimmten Titeln.
- **Schweregrad · Sicherheit:** niedrig · bestätigt (abgeleitet).
- **Gegenmaßnahme:** In `parse` eine Obergrenze (`end <= 86_400`); im Log `Int(exactly:)` oder vorher begrenzen.
- **Gegenprüfung:** Die Zeichenkette wird vor dem Aufruf von `log` gebildet, der Absturz hängt also nicht davon ab, ob jemand das Log liest.

### SEC-11: „Pi im Netz suchen“ speichert den ersten passenden Antworter ohne Rückfrage als atvloadly-Adresse
- **Ort:** `App/Sources/AppUpdater.swift:144-161`, `:183-189`, `App/Sources/Views/Settings/UpdatePage.swift:49`, `:86-88`, `Packages/PlayerCore/Sources/PlayerCore/Update/AppUpdate.swift:178`, `:239-246`
- **Angriffsszenario:** (1) Angreifer kündigt `_workstation._tcp` an **oder** beantwortet nur den mDNS-Namen des festen Probe-Hosts (`fallbackHosts`), falls es den im Netz nicht gibt. (2) Nutzer tippt „Pi im Netz suchen“. (3) Der erste Rechner, der `/api/version` passend beantwortet, wird sofort gespeichert und überschreibt einen vorhandenen Eintrag. (4) Dieselbe Umleitung gelingt bei einer schon gespeicherten `.local`-Adresse über gefälschte mDNS-Antworten.
- **Voraussetzung:** Gerät im WLAN; Nutzer löst die Suche aus.
- **Auswirkung:** Eine Einstellung wird aus dem WLAN heraus verändert; Updates lassen sich unbemerkt verhindern; Text des Angreifers erscheint in den Einstellungen. Kein Paket-Unterschieben und kein Abfluss von Geheimnissen an die falsche Adresse (die App sendet dorthin nur die feste Paketadresse und Werte, die die Gegenstelle selbst geliefert hat).
- **Schweregrad · Sicherheit:** niedrig · bestätigt.
- **Gegenmaßnahme:** Treffer mit Name und Adresse anzeigen und per Fernbedienung bestätigen lassen; vorhandene Adresse nie stillschweigend ersetzen; bei mehreren Treffern Auswahl; Echtheit über das Token aus SEC-3.
- **Gegenprüfung:** `Task { if let u = await updater.discover() { save(u) } }` – zwischen Fund und Speichern liegt kein Schritt.

### SEC-12: `logcollector.py` nimmt Zeilen von jedem im Netz an und schreibt sie ungefiltert
- **Ort:** `tools/logcollector.py:35`, `:12-26`, `:25`
- **Angriffsszenario:** (1) Angreifer findet den Dienst per Bonjour. (2) `POST /log` mit Zeilenumbruch oder ESC-Folgen im Feld `m`. (3) Gefälschte Zeilen in der Tagesdatei, Steuerzeichen im Terminal beim Ansehen, Platte füllt sich.
- **Voraussetzung:** Log-Programm läuft; Gerät im selben Netz.
- **Auswirkung:** Integrität der Diagnose, Verfügbarkeit des Log-Rechners. Kein Zugriff auf die App.
- **Schweregrad · Sicherheit:** niedrig · bestätigt.
- **Gegenmaßnahme:** HMAC mit dem Geheimnis aus SEC-2 prüfen; Zeilenumbrüche und Zeichen unter 0x20 sowie 0x7f ersetzen; Tagesdatei begrenzen; an eine Schnittstelle binden.
- **Gegenprüfung:** Die f-Zeichenkette in `:25` schreibt alle fünf Felder roh.

### SEC-13: `logcollector.py`: negative oder unlesbare `Content-Length` umgeht das Limit; keine Zeitgrenzen
- **Ort:** `tools/logcollector.py:15-19`, `:24-25`, `:35`
- **Angriffsszenario:** (1) `Content-Length: -1` besteht die Prüfung `n > 4_000_000`. (2) `rfile.read(-1)` liest bis zum Verbindungsende in den Speicher. (3) Offene Verbindungen ohne Körper halten je einen Thread ohne Frist; ein Körper, der kein Array aus Objekten ist, wirft nach dem Öffnen der Datei eine unbehandelte Ausnahme.
- **Voraussetzung:** Log-Programm läuft; Gerät im selben Netz.
- **Auswirkung:** Ausfall des Log-Rechners bzw. -Dienstes.
- **Schweregrad · Sicherheit:** niedrig · bestätigt (aus dem Verhalten von `http.server` abgeleitet).
- **Gegenmaßnahme:** `0 <= n <= Limit` prüfen, sonst 400; `timeout = 10` als Klassenattribut; Einträge mit `isinstance(e, dict)` prüfen.
- **Gegenprüfung:** `int(...)` steht außerhalb des `try`, eine Untergrenze fehlt.

### SEC-14: Alle Geheimnisse unverschlüsselt in UserDefaults und Dateien, kein Keychain
- **Ort:** `App/Sources/DefaultsStorage.swift:14-21`, `Packages/PlayerCore/Sources/PlayerCore/Models/Profile.swift:24-25`, `:31`, `Packages/PlayerCore/Sources/PlayerCore/Store/ProfileStore.swift:37`, `:45-49`
- **Angriffsszenario:** Aus dem WLAN nicht direkt erreichbar. Wirksam über (1) Export der Handy-Seite (SEC-1), (2) fremdes Paket mit gleicher App-Identität (SEC-3, SEC-7), (3) Zugriff auf den App-Container eines gekoppelten Geräts.
- **Voraussetzung:** Einer dieser Wege.
- **Auswirkung:** Abfluss aller Zugangsdaten auf einmal; die Kopie `profiles.json.bak` wird nie gelöscht.
- **Schweregrad · Sicherheit:** niedrig · bestätigt (Suche nach `SecItem`/`Keychain` im Quelltext: kein Treffer).
- **Gegenmaßnahme:** `apiKeys`, `syncTokens` und den Zugangsteil der Addon-Adressen in die Keychain (auf tvOS verfügbar; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), im Profil nur Verweise; `.bak` nach erfolgreichem Start löschen. Hinweis: Gegen ein Fremd-Paket mit gleicher Identität schützt auch die Keychain nicht – dafür SEC-3.
- **Gegenprüfung:** Der Kommentar in `Profile.swift:24` nennt die Ablage im Profil eine bewusste Entscheidung; der Befund ist damit ein akzeptiertes Risiko, kein Versehen.

### SEC-15: Build-Kette mit beweglichen Bezügen
- **Ort:** `.github/workflows/build.yml:73`, `:20`, `:153`, `Packages/AetherFEL/Package.swift:16-17`
- **Angriffsszenario:** (1) Upstream-Konto der Engine oder die Homebrew-Formel wird übernommen bzw. das Versions-Tag versetzt. (2) Der nächste Push auf `main` baut und veröffentlicht das veränderte Paket. (3) Geräte installieren es (SEC-7).
- **Voraussetzung:** Kompromittierte Abhängigkeit; nicht aus dem WLAN.
- **Auswirkung:** Fremder Code im offiziellen Paket.
- **Schweregrad · Sicherheit:** niedrig · bestätigt (kein `Package.resolved` im Baum, `brew install` ohne Version).
- **Gegenmaßnahme:** Engine per `revision:` binden oder `Package.resolved` einchecken und im Build `-onlyUsePackageVersionsFromResolvedFile` setzen; XcodeGen als Release-Archiv mit SHA-256 laden.
- **Gegenprüfung:** Actions sind auf Commits gepinnt, Python-Pakete mit Hashes gesperrt – nur diese Bezüge sind offen.

### SEC-16 (neu): Token der Handy-Seite ohne Ablauf, ohne Gerätebindung, beliebig oft verwendbar; Server läuft, solange die Ansicht offen ist
- **Ort:** `App/Sources/Views/PhoneInputView.swift:11`, `:118-119`, `:106`, `Packages/PlayerCore/Sources/PlayerCore/Phone/PhoneInput.swift:114`, `:147`, `:154`
- **Angriffsszenario:**
  1. Nutzer öffnet die Ansicht, scannt, trägt etwas ein und lässt den Fernseher auf der Ansicht stehen.
  2. Das einmal mitgelesene Token (SEC-1) bleibt gültig: kein Zeitlimit, keine Bindung an das erste Gerät, kein Verbrauch nach Benutzung; jede Antwort wiederholt es in `Location` und in der Seite.
  3. Der Listener endet nur in `onDisappear`. Im geprüften Code reagiert die Ansicht auf keinen Wechsel des App-Zustands (Bildschirmschoner, Inaktivität); der Angreifer kann also auch lange nach der Eingabe exportieren oder überschreiben.
  4. Die Adresse samt Token steht zusätzlich als Text am Bildschirm (`:106`) und im Verlauf des Handy-Browsers.
- **Voraussetzung:** Token bekannt (mitgelesen oder vom Bildschirm abgelesen); Ansicht noch offen.
- **Auswirkung:** Verlängert das Zeitfenster von SEC-1 von Sekunden auf beliebig lange.
- **Schweregrad · Sicherheit:** niedrig (verstärkt SEC-1) · bestätigt für fehlenden Ablauf und fehlende Bindung; Weiterlaufen bei Bildschirmschoner plausibel (am Gerät prüfen).
- **Gegenmaßnahme:** Ablauf nach 10 Minuten ohne Anfrage mit Hinweis „QR-Code erneuern“ (neues Token); Bindung an die Adresse der ersten gültigen Anfrage; `scenePhase` beobachten und den Listener bei „nicht aktiv“ stoppen; offene Verbindungen in `stop()` schließen; Adresse am Bildschirm ohne Token zeigen (der QR-Code trägt es).
- **Gegenprüfung:** `stop()` schließt nur den Listener; es gibt weder Zeitgeber noch Zustandsbeobachtung in `PhoneServer` oder `PhoneInputView`.

### SEC-17 (neu): CI-Geheimnis `IPA_DENYLIST` steht jedem Branch-Lauf zur Verfügung, der Prüfcode kommt aus dem Branch
- **Ort:** `.github/workflows/build.yml:5`, `:198-230` (Job `history`, Schritt „Check IPA“ `:227-230`), `tools/check_ipa.sh:45`
- **Angriffsszenario:**
  1. Der Job `history` läuft bei jedem Push auf jeden Branch (keine `if`-Bedingung) und checkt den Code dieses Branches aus.
  2. Er führt `bash tools/check_ipa.sh` aus dem Branch aus und übergibt das Geheimnis als Umgebungsvariable `EXTRA_DENY`.
  3. Wer in irgendeinen Branch pushen darf, ändert Skript oder Workflow so, dass der Inhalt (verschleiert, um die Log-Maskierung zu umgehen) ausgegeben wird.
- **Voraussetzung:** Schreibrecht auf einen beliebigen Branch. Nicht aus dem WLAN; Forks lösen nichts aus (kein PR-Trigger).
- **Auswirkung:** Offenlegung der Sperrliste – nach ihrem Zweck private Namen und Adressen, die gerade nicht öffentlich werden sollen.
- **Schweregrad · Sicherheit:** niedrig · bestätigt (Ablauf im Workflow); Inhalt des Geheimnisses nicht einsehbar.
- **Gegenmaßnahme:** Das Geheimnis als Environment-Secret an ein GitHub-Environment mit Branch-Beschränkung (`main`, `integ`) binden und den Schritt nur dort mit Geheimnis ausführen; auf anderen Branches läuft die Prüfung ohne Zusatzliste.
- **Gegenprüfung:** Der Schritt hat keine eigene Bedingung, und der Job-Modus (`dry-run`/`publish`) ändert nichts an der Übergabe des Geheimnisses.

---

## Verworfene Kandidaten

| ID | Titel | Grund |
| --- | --- | --- |
| SEC-1 (Teil) | Gegenmaßnahme „Formulardaten und Export per WebCrypto mit Schlüssel aus dem URL-Fragment verschlüsseln“ | `crypto.subtle` gibt es nur in sicheren Kontexten; auf `http://<IP>` fehlt es. Eine mitgelieferte JS-Krypto hielte nur passive Mitleser ab – ein aktiver Angreifer ersetzt das Skript der Klartext-Seite. |
| SEC-1 (Teil) | Gegenmaßnahme „TLS mit selbst erzeugtem Zertifikat, Fingerabdruck im QR“ | Handy-Browser zeigen eine Warnung und werten keinen Fingerabdruck aus dem QR aus; der Nutzer lernt, Warnungen wegzutippen. Ersatz: Bestätigung am Fernseher, verschlüsselter Export, Eingabe von Geheimnissen über die tvOS-Tastatur am iPhone. |
| SEC-4 (Teil) | „`NSAllowsArbitraryLoads` entfernen“ als Lösung | Schließt nur HTTP zu fremden Hosts. Der vorgesehene Fall (Addon im Heimnetz) bleibt über `NSAllowsLocalNetworking` Klartext – genau dort sitzt der WLAN-Angreifer. Als Zusatz sinnvoll, nicht als Lösung. |
| SEC-7 (Teil) | „Die Schutzregel für `app-main` steht im Workflow des jeweiligen Branches“ als eigene Schwäche | Wer in einen Branch pushen darf, hat Schreibrecht und kann Release-Dateien auch direkt ersetzen; die Stelle der Bedingung ändert daran nichts. Übrig bleibt die fehlende Prüfsumme/Signatur. |
| – | Token erratbar oder per Brute-Force | ≈ 49,5 Bit aus `SystemRandomNumberGenerator`; je Ansicht neu (`@StateObject`). Unrealistisch. |
| – | Zeitangriff auf den Token-Vergleich (`==`) | Server auf dem MainActor, Netzrauschen im WLAN, 10 Zeichen – kein praktischer Wert. |
| – | `/export` ohne Token | Dieselbe Prüfung vor jeder Route (`PhoneInput.swift:114`); ohne Token 403. |
| – | CSRF oder DNS-Rebinding gegen die Handy-Seite | Kein Host-/Origin-Check, aber jede Route verlangt das Token, das ein fremder Ursprung nicht lesen kann; `no-referrer` verhindert die Weitergabe über den externen Link (`:286`). |
| – | XSS über Profil-, Reihen- oder Katalognamen | Durchgängig `escape`, alle Attribute mit Nutzdaten in doppelten Anführungszeichen (`:166`, `:198`, `:212-216`, `:224`); Rückmeldungen nur über feste Tabelle. |
| – | Pfad-Parsing umgeht die Prüfung (`//export`, absolute Form, Groß/Klein) | Die Token-Prüfung liegt vor dem Routing; unbekannte Pfade enden in 404. |
| – | Token im Fern-Log | `AppModel.swift:559-573` loggt nur Befehlsarten und Hosts; Fehlertexte des Servers enthalten es nicht. |
| – | Server läuft nach Schließen der Ansicht weiter | `onDisappear` → `stop()`; das Objekt wird freigegeben, wartende Rückrufe laufen wegen `[weak self]` ins Leere. (Offen bleibt nur der Fall „Ansicht offen, App inaktiv“ – SEC-16.) |
| – | Update-Prüfung akzeptiert niedrigere Build-Nummer | `UpdateState.decide` meldet `newerInstalled`, wenn der installierte CI-Build höher ist (`AppUpdate.swift:156`). |
| – | Fremde Paketadresse über gefälschtes GitHub-Ergebnis oder atvloadly-Adresse | Asset-Adresse muss exakt der Konstante entsprechen (`:120`, `:697`); `normalize` entfernt Query und Fragment (`:192-193`). |
| – | Gefälschter atvloadly erhält Geheimnisse | Die App sendet nur die feste Paketadresse und Werte, die die Gegenstelle selbst geliefert hat. Übrig: SEC-11. |
| – | Plattencache-Proxy als offener Proxy oder Leck im WLAN | Loopback-Bindung, `acceptLocalOnly`, Gegenstellenprüfung, UUID-Token, nur GET/HEAD, 10-s-Frist, Kopf höchstens 64 KB. |
| – | Gefälschte GitHub-Antwort aus dem WLAN | HTTPS mit Standardprüfung, fester Pfad. |
| – | Fork-Pull-Requests erreichen Secrets oder Schreibrechte | Kein `pull_request`-Trigger. |
| – | Vergiftung des Actions-Cache für das Gesichtsmodell von einem Nebenbranch | Caches eines Nebenbranches sind für `main` nicht sichtbar; Restrisiko nur über den Standard-Branch (Repo-Einstellung, am Netz prüfen). |
| – | Hart codierte Schlüssel, unsicheres Modell-Laden, Zip-/Gzip-Bombe über Untertitel, Dekodier-Bombe über Bildmaße, Debrid-Links im Fortsetzungs-Cache, Absturz durch kaputte Addon-JSON-Felder | Aus dem Erstbericht übernommen; die dort genannten Schutzstellen stichprobenhaft bestätigt (`PlayerPictureSound.swift:155`, `:196`, `:202`). |

---

## Geprüft und unauffällig

- **Token-Erzeugung:** `randomElement()` nutzt die System-Zufallsquelle; Alphabet ohne verwechselbare Zeichen, 31^10 Möglichkeiten (`PhoneInput.swift:106-109`).
- **Seite gibt keine vorhandenen Schlüssel preis:** Alle Felder werden leer ausgeliefert; sichtbar sind nur Profilname und Reihentitel (`PhoneInput.swift:169-193`).
- **`key_*` nur für die feste Dienstliste** (`:102`, `:137`); `op`-Befehle nur gegen den Stand des Fernsehers, IDs werden als UUID geprüft (`Phone/PhoneHome.swift:62-86`).
- **Sicherungen nie über das Schnell-Import-Feld:** `PhoneImportDetect` lehnt sie ab und verweist auf das eigene Feld (`Phone/PhoneImportDetect.swift:55`).
- **Parser:** kaputte Anfragen → 400/413; Kopf höchstens 64 KB, negative Länge abgefangen (`PhoneInput.swift:15-31`). Antworten mit `Cache-Control: no-store` (`:64`).
- **Import einer Sicherung:** Schema-Version und „nicht leer“ werden geprüft (`ProfileStore.swift:53-58`) – schützt vor Unfällen, nicht vor einem Angreifer mit Token.
- **Apple-ID in der App:** nur als md5 weitergegeben, nie geloggt; Meldungen von atvloadly laufen durch `AppUpdateLog.redact` (`AppUpdate.swift:300`, `:306`, `:604-621`).
- **GitHub-Abfragen:** fester Repo-, Workflow- und Tag-Pfad, Entwürfe ausgeschlossen (`:82-87`, `:119`).
- **Plattencache-Proxy:** siehe Tabelle oben; Quellen mit Zugangsdaten werden umgangen (`DiskCacheProxy.swift:489`).
- **CI:** Standardrechte `contents: read`, Schreibrechte nur in `release` und `publish`; `persist-credentials: false`; Actions auf Commits gepinnt; Python-Pakete mit `--require-hashes` (`build.yml:15-16`, `:26`, `:62`).
- **Zeilenangaben des Erstberichts:** alle zitierten Stellen stimmen; Ergänzung zu SEC-6: zweite Verwendung der Kopfzeilen in `AppModel+Reresolve.swift:20`.

## Am Gerät/Netz prüfen

1. **Handy-Seite bei Bildschirmschoner/Inaktivität:** Ansicht offen lassen, warten bzw. Home drücken – wie lange antwortet Port 8765 noch? (SEC-16)
2. **Erreichbarkeit über IPv6:** Antwortet Port 8765 auch über die globale IPv6-Adresse des Apple TV, und lässt der Router das von außen zu?
3. **Mitschnitt der Handy-Seite:** Am Router mitschneiden – Token, eingetippte Schlüssel und Export im Klartext sichtbar? (SEC-1)
4. **atvloadly offen?** Von einem dritten Rechner `GET /api/apps` und `/api/devices` – Antwort ohne Anmeldung, Feld `account` im Klartext? Nimmt `install_app` eine beliebige `ipa_url` an? (SEC-3)
5. **Welches Paket lädt atvloadly beim Weg „Quelle“?** `app-main`, das „Latest“-Release oder ein Prerelease von `integ`? (SEC-7)
6. **Fern-Log:** Zweiten Rechner den Dienst ankündigen lassen – kommt der Puffer ohne Zutun an, welche Zeilen enthalten Titel und Hosts? (SEC-2)
7. **Speichergrenze:** Viele hängende Verbindungen mit großem Körper – ab wann beendet tvOS die App? (SEC-5)
8. **tvOS-Tastatur am iPhone:** Erscheint sie für ein Textfeld in den Einstellungen zuverlässig und erlaubt Einfügen langer Schlüssel? (Gegenmaßnahme SEC-1)
9. **`NSAllowsLocalNetworking` allein:** Lädt ein HTTP-Addon unter IP oder `.local` noch, spielen HTTP-Quellen über den Plattencache weiter? (SEC-4)
10. **Engine und fremde Schemata:** Verhalten bei `file://` als Untertitel- oder Stream-Adresse. (SEC-6)
11. **Repo-Einstellungen:** Tag-/Release-Schutz, Environments, wer Schreibrecht hat, ob `IPA_DENYLIST` Repo- oder Environment-Secret ist. (SEC-7, SEC-17)
12. **WLAN:** Client-Isolation, WPA3/PMF (erschwert Mitlesen und ARP-Angriffe aus SEC-1 und SEC-3).

---

# Teil B: Git-Historie

Stand: Repo `/home/user/tvos-player`, nach `git fetch origin '+refs/heads/*:refs/remotes/origin/*' --tags`. Rein lesend geprüft (`for-each-ref`, `rev-list`, `log`, `show`, `grep`, `cat-file`); am Repo wurde nichts geändert.

### Kurzfassung

- **Keine Zugangsdaten gefunden.** In keinem der 1670 Datei-Stände (Blobs) aller 320 Commits über alle 78 Refs steht ein API-Schlüssel, Token, Client-Secret, Passwort, JWT, privater Schlüssel oder eine Addon-Adresse mit eingebetteter Konfiguration. Alle Schlüssel werden zur Laufzeit vom Nutzer eingegeben (`Profile.apiKeys`), nichts ist hart codiert.
- **Ein echter Personenbezug in den Commit-Metadaten** (GIT-1): 6 Merge-Commits tragen im Autor- und Committer-Feld einen Vornamen und eine E-Mail-Adresse aus Benutzerkonto + Rechnername + Heimrouter-Domain.
- Dazu drei niedrige Punkte (Session-Links, Fremd-Fixture mit echtem CDN-Host in der Historie, Setup-Angaben in Specs).
- Befunde: kritisch 0 · hoch 0 · mittel 1 · niedrig 4.

### Umfang der Prüfung

| Größe | Wert |
|---|---|
| Refs gesamt | 78 (2 lokale Branches, 67 `origin/*`-Branches, 9 Tags `build-*`, alle Tags leichtgewichtig ohne Tagger-Daten) |
| Commits über alle Refs | 320 |
| Datei-Stände (Blobs) über alle Refs | 1670, 343 verschiedene Pfade, rund 25,6 MB |
| Je gelöschte Dateien in der Historie | keine (`--diff-filter=D` liefert nichts) |
| Binärdateien | keine (alle Blobs sind UTF-8-Text) |

Die Inhaltsprüfung lief über jeden einzelnen Blob aller Refs (nicht nur über Diffs), damit auch Stände erfasst sind, die nur auf Seitenästen oder Tags liegen.

### Befunde

#### GIT-1: Vorname und Rechnername in Autor-/Committer-Feldern von 6 Merge-Commits
- **Ort:** Commit-Metadaten von `8ece755`, `29be6c9`, `555895d`, `b1e88c9`, `32bfdae`, `2a076e0` (Autor- und Committer-Feld, jeweils identisch)
- **Art:** Klarname (Vorname) im Namensfeld; E-Mail-Adresse der Form Benutzerkonto@Rechnername.Heimrouter-Domain (verrät lokalen Kontonamen, Hostnamen des Entwicklungsrechners samt eingesetzter Linux-Distribution und die Router-Marke). Die übrigen 313 Commits nutzen die GitHub-Noreply-Identität, 1 Commit die Claude-Noreply-Identität.
- **Szenario:** Jeder Besucher des öffentlichen Repos liest die Angaben über `git log`, die Commit-Ansicht auf GitHub oder die `.patch`-Ansicht eines Commits; sie lassen sich mit dem GitHub-Konto verknüpfen und heben die sonst durchgehaltene Pseudonymität auf.
- **Ursache:** Die 6 Commits sind lokale Merges (Zusammenführungen von `welle-*`/`fix-*` nach `integ`) von einem Rechner, auf dem `user.name`/`user.email` nicht auf die Noreply-Identität gesetzt waren; Git hat die Adresse aus Konto und Hostname gebildet.
- **Erreichbar über:** `origin/integ`, `origin/welle-merge` und alle 9 Tags (`build-144` enthält den ersten, `build-149`…`build-174` zwei, `build-187`/`build-198` fünf, `build-214`/`build-249` alle sechs); der älteste (`8ece755`) hängt an 40 von 78 Refs. **Nicht** in `origin/main`.
- **Noch in HEAD?** `origin/integ`: ja (alle 6 sind Vorfahren von `b2188a2`). `origin/main`: nein.
- **Schweregrad:** mittel · **Sicherheit:** bestätigt
- **Fix-Idee:** Historie umschreiben mit `git filter-repo --mailmap` (bzw. `--name-callback`/`--email-callback`), sodass die 6 Commits die Noreply-Identität tragen; danach Force-Push aller Branches, alle 9 Tags neu setzen (die Tags zeigen sonst weiter auf die alten Commits), alte Seitenäste löschen, Releases an die neuen Tags hängen und beim GitHub-Support die Bereinigung gecachter Commit-Ansichten und verwaister Objekte beantragen. Eine `.mailmap`-Datei allein genügt nicht (sie ändert nur die Anzeige). Vorbeugend: `user.name`/`user.email` global auf die Noreply-Identität setzen und in GitHub „Block command line pushes that expose my email“ aktivieren.
- **Test:** `git log --all --format='%ae%n%ce' | sort -u` darf danach nur noch Noreply-Adressen liefern.

#### GIT-2: Session-Links in 307 Commit-Nachrichten
- **Ort:** Trailer `Claude-Session:` in 307 von 320 Commits (3 verschiedene Session-Kennungen), dazu 307 `Co-Authored-By`-Trailer mit Noreply-Adresse
- **Art:** Verweis auf private Arbeitssitzungen (Session-Kennung in einer URL). Kein Geheimnis: der Link ist ohne Anmeldung am Konto des Besitzers nicht lesbar. Sonst enthalten die Commit-Nachrichten keine Namen, Hosts, Pfade, E-Mail-Adressen oder IPs (Mustersuche über alle 320 Nachrichten ohne Treffer).
- **Szenario:** Wird eine dieser Sitzungen später geteilt oder öffentlich gemacht, ist sie über die Historie sofort auffindbar; außerdem zeigt die Kennung, dass fast das ganze Repo in nur drei Sitzungen entstand.
- **Ursache:** Vorgabe im Plan (Commit-Identität mit beiden Trailern), bewusst so gesetzt.
- **Erreichbar über:** alle Refs · **Noch in HEAD?** `origin/integ` und `origin/main`: ja
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Belassen; die betreffenden Sitzungen nicht freigeben. Wer es ganz sauber will, entfernt die Trailer im selben `filter-repo`-Lauf wie GIT-1 per `--message-callback`.
- **Test:** `git log --all --format=%B | grep -c 'Claude-Session'`.

#### GIT-3: Fixture `nuvio.json` — Fremdinhalt mit echtem CDN-Host in Historie und `main`
- **Ort:** `Packages/PlayerCore/Tests/PlayerCoreTests/Fixtures/nuvio.json` (zuerst in `63d048b`; bereinigter Stand ab `ec1c6e3`)
- **Art:** Sammlungs-Export eines fremden Anbieters (16 Sammlungen, 407 Ordner, 2224 Quellen: TMDB-Discover-Filter, 55 öffentliche Trakt-Listen-IDs, 2 Addon-Kennungen mit UUID). **Keine personenbezogenen Daten:** keine Konto-/Profilnamen, keine Watch-Historie, keine Nutzer-IDs, keine Addon-Adressen, keine Tokens; die einzigen URLs sind 1492 Bild-/Video-Adressen mit einem Versionsparameter. Im älteren Stand zeigen sie auf den echten CDN-Host des Anbieters, im neueren auf einen Platzhalter-Host.
- **Szenario:** Kein Datenschutz-, sondern ein Herkunftsthema: der alte Stand dokumentiert öffentlich, welches Fremdpaket samt dessen Bildquellen übernommen wurde; die beiden Addon-UUIDs sind Kennungen des Anbieters, nicht des Nutzers (plausibel, nicht gegengeprüft).
- **Ursache:** Echter Export als Testdatei eingecheckt; Hosts erst in `ec1c6e3` ersetzt.
- **Erreichbar über:** alter Stand (echter Host) an allen 78 Refs als Historie; als aktueller Dateistand in `origin/main` und 49 weiteren Refs (u. a. `player-0…4`, `task-*`, `welle-a…e`, `build-144…162`); bereinigter Stand in `origin/integ` und 27 weiteren Refs.
- **Noch in HEAD?** `origin/main`: alter Stand mit echtem Host. `origin/integ`: bereinigter Stand.
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt (Inhalt), plausibel (Einordnung der UUIDs)
- **Fix-Idee:** `integ` nach `main` bringen, damit HEAD von `main` den bereinigten Stand trägt; die Fixture auf wenige Dutzend synthetische Einträge kürzen (1,6 MB sind für den Parser-Test nicht nötig). Historie nur dann umschreiben, wenn GIT-1 ohnehin umgesetzt wird (`filter-repo --replace-text` für den Host oder `--path … --invert-paths` und Fixture neu einchecken).
- **Test:** Parser-Tests in PlayerCore gegen die gekürzte Fixture laufen lassen; `git grep -c` auf den Hostnamen über alle Refs.

#### GIT-4: Specs beschreiben das private Setup des Nutzers
- **Ort:** `docs/superpowers/specs/2026-11-21-tvos-player-design.md:13`, `:42`, `:63`, `:64`, `:65`, `:104`, `:110`, `:155` (zuerst in `63d048b`)
- **Art:** personenbeziehbare Angaben: Fernseher-Hersteller und Paneltyp, Streaming-Gerät mit Systemversion, Einplatinenrechner im Heimnetz als Signier-/Sideload-Dienst, kostenlose Apple-ID ohne Entwicklerkonto, Zahl der bereits belegten App-Plätze, genutzter Debrid-Dienst als Hauptquelle. Keine Adresse, kein Hostname, keine Apple-ID selbst.
- **Szenario:** Zusammen mit GIT-1 ergibt sich ein Profil des Haushalts (Geräte, Dienste, Arbeitsweise); die Angabe zum Debrid-/Usenet-Bezug ist zudem die heikelste Aussage im Repo.
- **Ursache:** Die Spec hält Nutzerangaben wörtlich fest (Markierung „[U]“).
- **Erreichbar über:** alle 78 Refs · **Noch in HEAD?** `origin/integ` und `origin/main`: ja
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** In HEAD neutral formulieren („Dolby-Vision-fähiger Fernseher“, „Sideload-Dienst im Heimnetz“) oder `docs/superpowers/` aus dem öffentlichen Repo nehmen; aus der Historie nur im Zuge von GIT-1 mit entfernen (`filter-repo --path docs/superpowers --invert-paths`).
- **Test:** Sichtprüfung der Spec nach der Überarbeitung.

#### GIT-5: Kürzel des Nutzers in Bundle-ID, Log-Subsystem, Lizenz und Hilfsskripten
- **Ort:** `App/project.yml:3`, `App/project.yml:46`, `App/Sources/AppUpdater.swift:85`, `App/Sources/RemoteLog.swift:11`, `LICENSE:3`, `README.md:117`, `CHANGELOG.md:13`, `tools/backfill_releases.sh:15`, `tools/release_notes.sh:29`, `docs/superpowers/plans/2026-11-21-design-umbau.md:27`, `docs/superpowers/plans/2026-11-21-p1-kern-und-geruest.md:15`, `docs/superpowers/specs/2026-11-21-tvos-player-design.md:67`, `:156` (Bundle-ID zuerst in `601e5d6`)
- **Art:** personenbeziehbare Angabe: Bundle-ID-Präfix mit Länderkennung und Namenskürzel, das dem GitHub-Kontonamen entspricht; Kontoname als Rechteinhaber in der Lizenz und als Repo-Standard in Skripten.
- **Szenario:** Nichts davon ist geheim (der Kontoname steht ohnehin in der Repo-Adresse); die Bundle-ID landet aber in jeder veröffentlichten IPA und verknüpft installierte Apps dauerhaft mit dem Konto.
- **Ursache:** Übliche Namensgebung, bewusst gewählt.
- **Erreichbar über:** alle Refs · **Noch in HEAD?** `origin/integ`: ja; `origin/main`: ja (ohne `LICENSE`)
- **Schweregrad:** niedrig · **Sicherheit:** bestätigt
- **Fix-Idee:** Belassen. Eine Änderung der Bundle-ID würde beim Sideload einen neuen App-Container erzeugen (Datenverlust), der Nutzen wäre gering.
- **Test:** entfällt.

### Hart codierte Schlüssel im Stand `origin/integ` (b2188a2)

Keine. Im Einzelnen:
- Trakt (Client-ID, Client-Secret), Simkl (Client-ID), TMDB, MDBList, TorBox und die atvloadly-Adresse kommen ausschließlich aus `Profile.apiKeys` (`App/Sources/AppModel.swift:115`, `:120`, `:345`, `:550`; `App/Sources/Views/TorBoxFilesRow.swift:28`). Es gibt keinen Vorgabewert im Code.
- `Packages/PlayerCore/Sources/PlayerCore/Services/YouTubeResolver.swift` enthält keinen Innertube-API-Schlüssel (kein Treffer auf das übliche Schlüsselpräfix, keine Zeichenkette mit hoher Entropie).
- `.github/workflows/build.yml:229` verwendet genau ein Repository-Secret (`IPA_DENYLIST`), nur als Referenz; es gab in der gesamten Workflow-Historie nie einen Klartextwert. Runner sind GitHub-gehostet (`macos-26`, `ubuntu-latest`), keine eigenen Runner-Hostnamen. Actions sind auf Commit-SHA gepinnt (das sind die einzigen 40-stelligen Hex-Werte in der Datei).
- `tools/check_ipa.sh` prüft veröffentlichte IPAs auf private Adressen, Home-Pfade, JWTs und Hex-Schlüssel und gibt bei Treffern nur die Musterklasse aus.

### Geprüft und unauffällig

Geprüft wurden alle 1670 Blobs aller 78 Refs sowie alle 320 Commit-Nachrichten.

- **Schlüssel-Zuweisungen** (`api_key`, `apikey`, `secret`, `token`, `bearer`, `client_id`, `client_secret`, `password`, `Authorization` mit Wert ≥ 12 Zeichen): einziger Treffer ist ein offensichtlicher Testwert in `Fixtures/main-profiles-v1.json`.
- **Lange Hex-Werte (≥ 32)**: nur gepinnte Action-SHAs, Upstream-Commit- und SHA-256-Prüfwerte in `tools/xray_model/convert_sface.py`/`README.md`, Paket-Hashes in `requirements.lock`, Lizenztexte, Zählfolgen in Tests.
- **JWT/Base64 im URL-Pfad**: nur konstruierte Beispiele in `LogRedactTests.swift` (Beispiel-Domains).
- **GitHub-Tokens, Google-API-Schlüssel, AWS-Schlüssel, PEM-Privatschlüssel**: keine Treffer.
- **Private IPv4-Adressen, CGNAT-/Tailscale-Bereich**: nur Dokumentations- und Testwerte in `LogRedact.swift`, `LogRedactTests.swift`, `AppUpdateTests.swift`.
- **Private Hostnamen** (`.local`, `.lan`, Heimrouter-Domains, Tailscale-, DynDNS-Namen): nur generische Platzhalter in UI-Hinweistexten und Tests; in keinem Dateiinhalt ein echter Hostname (der einzige echte steht in den Commit-Metadaten, siehe GIT-1).
- **Home-Pfade** (`/Users/<name>`, `/home/<name>`): nur der CI-Runner-Pfad als Kommentar in `tools/check_ipa.sh`.
- **E-Mail-Adressen**: nur Beispiel-Domains in Tests und Urheberangaben in `THIRD_PARTY_NOTICES.md` (Upstream-Lizenztexte).
- **MAC-Adressen, UDIDs, Seriennummern**: eine Platzhalter-MAC in `AppUpdateTests.swift`, sonst nichts.
- **Vorname/Rechnername aus GIT-1 in Dateiinhalten**: kein Treffer in irgendeinem Blob.
- **Zeichenketten mit hoher Entropie** (≥ 20 Zeichen, gemischte Zeichenklassen): nur Bezeichner, Testnamen und die oben genannten Prüfwerte.
- **Addon-/Debrid-/AIOStreams-/TorBox-Adressen mit eingebetteter Konfiguration**: keine echten; nur Beispiele in Tests.
- **Fixture `main-profiles-v1.json`**: vollständig synthetisch (Platzhalter-UUIDs, Beispiel-Addon, Testschlüssel, Testtokens).
- **`THIRD_PARTY_NOTICES.md`** (7 Stände), **`tools/logcollector.py`**, **`tools/backfill_releases.sh`**, **`tools/release_notes.sh`**, **`CHANGELOG.md`**, **`README.md`**, Prompt-Datei auf `origin/claude/plugins-skills-usage-z18tc8`: keine Geheimnisse, keine Hosts, keine Namen.
- **Gelöschte Dateien, Übergabedateien, Mockups, HTML, Logs**: in der gesamten Historie nicht vorhanden.
- **Tags**: 9 leichtgewichtige Tags ohne eigene Tagger-Metadaten.

### Nicht prüfbar von hier

- Inhalte der GitHub-Releases (IPA-Dateien, Release-Texte), Actions-Logs, Issues, Pull-Request-Beschreibungen und -Kommentare sowie verwaiste Commits, die nur noch über die GitHub-Oberfläche erreichbar sind. Nach einem Umschreiben der Historie (GIT-1) bleiben alte Commits dort über ihre Hashes abrufbar, bis der GitHub-Support sie entfernt.
- Forks und fremde Klone, die die 6 Commits aus GIT-1 bereits enthalten.
