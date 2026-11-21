# Player

Player ist eine tvOS-App für das Apple TV. Sie spielt Inhalte aus Stremio-kompatiblen Addons ab und
ist auf hochwertige Wiedergabe ausgelegt: Dolby Vision bis Profil 7 FEL, 4K/HDR und Mehrkanalton.
Die App ist ein privates Hobbyprojekt. Der Quelltext ist öffentlich, es gibt aber keinen Support und
keine Veröffentlichung im App Store.

Die App liefert selbst keine Inhalte. Sie zeigt nur, was die eingerichteten Addons und Dienste liefern.

## Funktionen

- **Stremio-Addons:** Kataloge, Metadaten, Streams und Untertitel über das Stremio-Addon-Protokoll.
  AIOStreams wird mit seinen Zusatzfeldern ausgewertet.
- **TorBox:** gecachte Quellen werden bevorzugt, und die eigenen TorBox-Dateien erscheinen in der
  Bibliothek.
- **Bild:** Dolby Vision (Profil 5, 8 und 7 mit Umwandlung nach 8.1; bei FEL-Filmen wird die
  Erweiterungsschicht eingerechnet), HDR10/HDR10+/HLG, AV1 und HEVC.
- **Ton:** 5.1 und Atmos als Passthrough; TrueHD und DTS-HD werden zu Mehrkanal-PCM dekodiert. Dolby-Digital-Spuren
  werden bevorzugt.
- **Player:** eigene Steuerleiste mit lesbaren Plaketten, ein Ton- und Untertitel-Panel, Untertitel aus Addons
  (auch über den Datei-Hash) mit Versatz und Zeichensatz-Erkennung, Spulen mit Vorschau über die
  Touchfläche, „Intro überspringen“, Autoplay der nächsten Folge mit gleichem Release, die Abfrage „Noch da?“ und
  ein Spur-Gedächtnis je Serie.
- **Startseite:** Reihen und Stile lassen sich selbst zusammenstellen (Hero, Poster, Querformat, Top 10,
  Logo- und Collection-Kacheln). Fertige Pakete sowie Listen von TMDB, Trakt und MDBList stehen bereit, und Fusion-
  bzw. betterer-Startseiten-Kits werden als Reihen übernommen.
- **Detailseite:** Bewertungen über MDBList, Technik-Plaketten (4K, Dolby Vision, HDR, Atmos, Kanäle),
  deutsche Texte und Bilder aus TMDB, Besetzung, Personenseite, ähnliche Titel und Trailer.
- **Sync:** Trakt und Simkl mit Geräte-Login, Scrobbling, Weiterschauen-Abgleich, Merkliste und Listen.
  Wo Fortschritt und „Gesehen“ geführt werden, ist wählbar: lokal, bei Trakt oder bei Simkl.
- **Kalender und Bibliothek:** neue Folgen mit Sendetag und -zeit, die Reihe „Heute neu“ und die Merkliste.
- **Profile:** jedes Profil ist eigenständig, mit eigener Startseite, eigenen Addons, Konten und Einstellungen.
  Die Oberfläche gibt es auf Deutsch und auf Englisch.

## Installation

Die CI baut bei jedem Stand von `main` eine **unsignierte IPA** (`Player.ipa`) und legt sie im
GitHub-Release **`app-main`** ab. Die IPA muss vor der Installation signiert werden, zum Beispiel mit
einem Sideloading-Werkzeug wie [atvloadly](https://github.com/bitxeno/atvloadly) und einer eigenen
Apple-ID. Danach wird sie aufs Apple TV übertragen.
Mit einer kostenlosen Apple-ID läuft die Signatur nach 7 Tagen ab und muss erneuert werden.

Voraussetzungen: tvOS 18 oder neuer, auf dem Gerät mit tvOS 26 getestet.

In den Einstellungen gibt es den Punkt „App aktualisieren“. Er vergleicht die installierte Build-Nummer mit dem
Release. Ist im lokalen Netz eine atvloadly-Instanz erreichbar, stößt er bei Bedarf die
Neuinstallation an.

## Einrichtung

Alle Zugangsdaten werden **nur in der App** eingegeben, und zwar über die Handy-Eingabeseite:

1. Am Apple TV „Einstellungen“ öffnen und die Handy-Eingabe starten. Die App zeigt einen QR-Code.
2. Den QR-Code mit dem Handy im selben Netz scannen. Es öffnet sich eine Eingabeseite, die das Apple TV selbst
   bereitstellt.
3. Dort Addon-Adressen (etwa ein AIOStreams-Manifest) und die API-Schlüssel eintragen: TMDB, MDBList,
   Trakt/Simkl-Client-ID, TorBox und andere. Über dieselbe Seite lassen sich auch alle Profile sichern und
   wiederherstellen.
4. Trakt und Simkl verbindet man anschließend in der App per Geräte-Code.

Im Repository stehen keine Schlüssel, Token oder Adressen, und es sollen auch keine hinein. Die Protokolle der
App schwärzen Schlüssel und Token, bevor sie geschrieben werden.

Optional: `tools/logcollector.py` empfängt das Fern-Log der App im lokalen Netz (per Bonjour) und schreibt es in
eine Datei, etwa zur Fehlersuche.

## Bauen

Die App wird mit Xcode gebaut. Das Projekt erzeugt [XcodeGen](https://github.com/yonaskolb/XcodeGen)
aus `App/project.yml`:

```sh
brew install xcodegen
cd App && xcodegen generate
xcodebuild -project Player.xcodeproj -scheme Player -configuration Release \
  -sdk appletvos -destination 'generic/platform=tvOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Die CI (`.github/workflows/build.yml`, GitHub Actions auf macOS) baut bei Änderungen unter `App/`,
`Packages/` oder `.github/workflows/`. Ein Lauf baut die IPA, prüft den App-Inhalt und den Dolby-Vision-FEL-Trait
und veröffentlicht die IPA für `main` als Release `app-main`. Die Build-Nummer der App ist die Laufnummer der CI.

Die plattformunabhängige Logik liegt im Paket `PlayerCore` und lässt sich ohne Mac testen, zum Beispiel unter
Linux mit Swift 6:

```sh
cd Packages/PlayerCore && swift test
```

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `App/` | tvOS-App (SwiftUI): Ansichten, App-Modell, Player-Anbindung, Bildlader, Fern-Log, Updater |
| `App/project.yml` | XcodeGen-Projektbeschreibung |
| `Packages/PlayerCore/` | Kernlogik mit Tests: Addon-Client, Modelle, Profile und Speicher, Sync (Trakt/Simkl), Fortschritt, Quellen-Reihenfolge, Handy-Seite, Update-Prüfung |
| `Packages/AetherFEL/` | dünne Hülle um die Wiedergabe-Engine [AetherEngine](https://github.com/superuser404notfound/AetherEngine), die den Trait `DolbyVisionFelCurves` einschaltet |
| `tools/` | Hilfsprogramme, zum Beispiel der Empfänger für das Fern-Log |
| `docs/` | Design- und Plandokumente |

## Stand und Zweige

- **`main`**: der Stand, der auf dem Gerät getestet ist. Aus ihm entsteht das Release `app-main`.
- **`integ`**: der Testzweig. Neue Stufen werden hier zusammengeführt und erst nach dem Gerätetest nach `main`
  übernommen.

Zurzeit enthält `main` die Version 0.4.0. Die Stufen ab Welle A (darunter TorBox, Fusion-Kits,
Dolby Vision FEL, das Paket `Packages/AetherFEL` und das Release `app-main`) liegen noch auf `integ`. Den
Verlauf beschreibt [CHANGELOG.md](CHANGELOG.md).

## Lizenz

Der Quelltext der App steht unter der [MIT-Lizenz](LICENSE).

Die mitgelieferten Fremdkomponenten (AetherEngine, FFmpeg, dav1d, libdovi und weitere) behalten ihre eigenen
Lizenzen, unter anderem LGPL. Einzelheiten und die vollständigen Lizenztexte stehen in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Dolby, Dolby Vision und Dolby Atmos sind Marken der Dolby Laboratories. Dieses Projekt steht in keiner Verbindung zu
Dolby, Apple oder den genannten Diensten.
