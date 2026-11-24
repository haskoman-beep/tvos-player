# Device test Build 2 (branch `verbesserungen-build-2`)

Tasks 2.1–2.6 of docs/superpowers/plans/2026-11-22-verbesserungen.md. Way back: Build 1 (build-291 on integ).

## 1. Before installing
- [ ] Backup from the phone page (sealed, with keys), code noted.

## 2. Checklist from the plan
- [ ] All logins (Trakt, Simkl, TorBox) work without logging in again.
- [ ] Open a watched film for 15 s and close it → the checkmark stays. Then trigger a sync → it still stays.
- [ ] Next episode starts automatically, stop after 30 s → the series stays in „Weiterschauen“ with this episode
      (also after a sync).
- [ ] WLAN off, mark a film „gesehen“, WLAN on → the entry appears at Trakt exactly once.
- [ ] Restore the backup on the device → kit rows stay; progress is there.
- [ ] An addon in the home network over `http://` still works; images and playback unchanged.
- [ ] Dolby Vision title, TrueHD title and a title via the disk cache start.
- [ ] Back to Build 1 and forward again: logins stay.

## 3. Deliberate changes to notice
- With a sync service connected, a title counts as watched from 80 % (before 92 %): a film left at 85 % leaves
  „Weiterschauen“.
- Addon calls wait as long as the profile's addon timeout (+5 s without data, +10 s total).
- Restoring a backup replaces the TV's progress with the backup's; profiles not in the backup lose their data.
- A plain (unsealed) backup has no keys, no logins and no URLs that may carry secrets; restoring it on the same TV
  also replaces kit and link settings with the scrubbed ones.
- On restore, expired logins are dropped only when they have no refresh token (cannot be renewed) → log in again
  there. An expired Trakt login with a refresh token stays and is renewed on first use.
- Old watched entries (beyond the newest 1500 and older than 18 months) are pruned.

## 4. Expected remote-log lines
- `speicher: Schlüsselbund: <n> Eintrag/Einträge abgeglichen` (every start; `<n>` is 0 when nothing changed). On
  recovery (older version loaded, profile file lost, or a profile value unreadable) it ends with
  `, <n> fehlende Wert(e) ergänzt`.
- `streams: <addon> <type>/<id>: Zielprüfung würde <n> von <m> Streams ablehnen (Schattenbetrieb)` (target check,
  every stream answer with refusals) and `bilder: Zielprüfung würde Bild ablehnen (Schattenbetrieb, <scheme>, Nr. <n>)`
  (at most 5 per start).
- `sync: Warteschlange: <n> ausstehend, <n> gemerkt, <n> abgelaufen` (at the first queue use per profile, only when
  changes are remembered or entries expired; queued actions and dead letters are not counted in this line).
- `fortschritt: beschnitten <n>` (only large books).
- `speicher: Profildaten entfernt · <n> Block/Blöcke` (delete or restore).

## 5. Also check
- [ ] Images still come from the disk cache after a restart; scrolling smooth.
- [ ] Simkl/Trakt sync with a large history still completes (limit 8 MiB / 20 s).
- [ ] Trakt history check: a watched stop resent after a timeout appears only once.

**Fallback triggers:** login lost; playback does not start; images missing everywhere.

## 6. Observations during the device test
- 24.11. Phone-input screen: the backup code was cut off („Y25M-DWYP-T8…“) → backup useless. Fixed in a3c292d
  (code on its own line, never truncated; hint texts wrap).
- 24.11. Home (hero): moving focus into a row hides that row's heading (it scrolls under the hero info).
- 24.11. Home (hero): title logo above the hero info missing (planned: `heroTitle` logo, Build 5a).
- 24.11. Wish: sign in with a Nuvio account and sync its addons etc.
