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
- Expired logins are dropped on restore even when they could be refreshed → log in again there.
- Old watched entries (beyond the newest 1500 and older than 18 months) are pruned.

## 4. Expected remote-log lines
`geheimnisse: <n> in den Schlüsselbund kopiert` (first start only), `netz: … Schattenbetrieb` (target check, at most
5 per start), `sync: Warteschlange <n> offen · <n> abgelegt`, `fortschritt: beschnitten <n>` (only large books),
`Profildaten entfernt · N Blöcke` (delete or restore).

## 5. Also check
- [ ] Images still come from the disk cache after a restart; scrolling smooth.
- [ ] Simkl/Trakt sync with a large history still completes (limit 8 MiB / 20 s).
- [ ] Trakt history check: a watched stop resent after a timeout appears only once.

**Fallback triggers:** login lost; playback does not start; images missing everywhere.

## 6. Observations during the device test
(empty)
