# Device test protocol: Build 1

Branch `verbesserungen-build-1`. Check everything here on the Apple TV before merging. UI texts are quoted in German
as they appear on screen. One pass takes about 40 minutes.

Preparation:
- [ ] Note the installed build (`build-249` or `build-250`) so you can go back to it.
- [ ] Have the logcollector ready: same secret as on the phone page, started with `PLAYERLOG_SECRET=<secret>`.

## 1. From the plan's deploy checklist ("Am Gerät prüfen")

- [ ] App starts; all profiles, home screens and logins are there.
- [ ] Phone page: scan QR, add an addon → the TV shows the confirmation; „Ablehnen“ changes nothing.
- [ ] Open the same address on a second device → refused.
- [ ] Load the backup without keys. Backup with keys: code shown on the TV, the downloaded file is not readable.
- [ ] Restore the encrypted backup with the code.
- [ ] Fern-Log: off after the update. Switch it on, choose a receiver, lines arrive. A second, wrong receiver in the
      network gets nothing.
- [ ] Diagnose page shows the last lines without any receiver.
- [ ] Update page: „Im Netz suchen“ shows a choice; installing shows build and commit.
- [ ] Go back to `build-249` and forward again: profiles stay (generations `.1`/`.2` do not disturb the old build).

## 2. Expected Fern-Log lines

- [ ] `metric: start.usable <ms>` exactly once per start.
- [ ] `speicher: Profile geladen · Bericht leer` or `… · ignoriert: <path>`.
- [ ] `handy: Sitzung gebunden`, `handy: Bestätigung <kind> erlaubt|abgelehnt|abgelaufen`.
- [ ] `log: Empfänger <name> gewählt`.
- [ ] The other metrics appear in the format `metric: <name> <ms>`: `start.profiles`, `start.catalog`,
      `detail.badges`, `streams.firstRow`, `streams.order`, `player.loadBegins`, `player.firstFrame`,
      `player.audioReload`, `sync.merged`.

Fallback triggers: profiles missing after start; „Profile nicht lesbar“ without a visible reason; the phone page no
longer opens.

## 3. Device-only checks found during implementation

### Profiles (Task 1.3)
- [ ] Force an unreadable state (for example a build with a higher schema) → the recovery screen appears, focus is on
      „Erneut versuchen“, the log shows `speicher: Profile nicht lesbar …`, and changes save nothing.
- [ ] While profiles are unreadable, phone export and phone import are refused (the recovery screen is the way out).
- [ ] After „Wiederherstellen“ or „Neu anfangen“, the profile picker or home appears.
- [ ] Start summary: UserDefaults total stays under 640 KB. Worst case after going back to 249: about 840 KB — check
      that 249 still starts normally.
- [ ] Dates and labels of the older versions in the recovery screen look right on a German device.
- [ ] `Date.distantPast` in watch progress survives a save and reload on Apple Foundation (no crash, no lost entry).
- [ ] A number like `1.0` in addon or collection data still works after a save (Apple may write it as `1`).

### Phone page (Task 1.4)
- [ ] iPhone Safari: after the QR scan the cookie is set and sent with later requests (submit, home, export).
- [ ] The camera preview does not use up the one-time address before Safari opens it.
- [ ] Download of `player-sicherung.enc` after „Erlauben“ starts in Safari; the page then says it was loaded.
- [ ] The code is shown as `XXXX-XXXX-XXXX` and stays visible while the keyboard or a short overlay is open.
- [ ] Restore `.enc`: the file picker fills the field; the code field accepts lower case and missing dashes; a wrong
      code gives a German message.
- [ ] The confirmation card: focus starts on „Ablehnen“, Menu = Ablehnen, it closes after 60 s, focus returns afterwards.
- [ ] Two requests at once: the phone shows that one is already waiting on the TV.
- [ ] Safari with many parallel connections: nothing is refused (limit is 4).
- [ ] The phone page no longer shows a TVDB field.

### Fern-Log (Task 1.5)
- [ ] The local-network prompt appears only when Fern-Log is switched on or its page is opened.
- [ ] The receiver list fills via Bonjour; the chosen name (`Player-Log` by default) is matched exactly.
- [ ] Lines arrive at the collector with a valid signature.
- [ ] `log-ring.json` survives an app restart; the Diagnose page shows it; scrolling through 200 rows works.
- [ ] No noticeable stutter while sending (signature is computed on the main thread).
- [ ] An addon address with login data shows no password in the log.

### Update (Task 1.6)
- [ ] Press „Build N · Commit … installieren?“: the row stays dimmed, focus stays. With atvloadly off, the row stays
      after the failure and can be pressed again.
- [ ] „Pi im Netz suchen“ with a saved address: a hit is only offered („ersetzt …“), nothing is saved until pressed.
- [ ] After the first main build with this CI change: the SHA256 in the footnote matches `sha256sum` of `Player.ipa`.
- [ ] Long texts: title one line, detail two lines.

### Metrics and docs (Task 1.8)
- [ ] `player.audioReload` appears after switching the audio track; `streams.order` does not flood the log.
- [ ] Settings „Was spielt wie“: the Dolby Vision Profile 7 row text is correct.
- [ ] `metric: start.usable` appears exactly once on each path: with hero, home without hero, profile picker,
      recovery screen (field `weg` names the path).

## 4. Found in the final review

- [ ] Type the 12-character code with the remote: there is enough time (5 minutes), and a wrong code keeps the request
      open with a message instead of ending it.
- [ ] Home button or screensaver while the phone page is open: the server comes back with a new QR code, no stale
      „Server-Fehler“; the old phone tab gets a clear refusal page.
- [ ] While „Profile nicht lesbar“: no Fern-Log lines arrive; they arrive after the restore. After „Neu anfangen“ the
      Fern-Log shows „Schlüssel fehlt“ (the secret has to be set again). `speicher: Profile nicht lesbar` is visible in
      „Verlauf“ afterwards.
- [ ] „Erneut versuchen“ with an unchanged state shows a short note.
- [ ] Round trip through 249: changing „Bild & Ton“ there resets the Fern-Log switch and receiver (expected);
      a `.enc` file cannot be restored on 249 (expected).
- [ ] Restore the plain export: the confirmation text says keys, logins and addon configuration must be entered again;
      no duplicate addons afterwards.
- [ ] A `.enc` file with one changed character is refused; a large profile (about 500 KB) restores from the iPhone.
- [ ] A failed restore on the recovery screen shows the error alert.

## 5. Observations during the device test

- 23 Nov: in „Reihe hinzufügen“ the left list scrolled over the page title. Pre-existing since the F-0 design wave (also in
  249/250). Fixed in 5b8710b: both `CategoryList` columns clip top and bottom, the sides stay open for the focus zoom.
  - [ ] Check: „Reihe hinzufügen“ and the settings pages, scroll to the bottom, nothing covers the title; the focused
        row still zooms without being cut at the sides or at the first/last row.
- 23 Nov: fast scrolling on the home screen shows many grey placeholders that turn into posters late. Build 1 does not
  touch image loading (`ImagePipeline`, `RemoteImage` unchanged), so this is not a regression. Open item for a later
  build: measure with the metrics from 1.8 and compare with 250 before changing anything.
