# Device test Build 3 (branch `verbesserungen-build-3`)

Tasks 3.1–3.8 of docs/superpowers/plans/2026-11-22-verbesserungen.md, plus 3.9 (a backup without keys keeps the
keys) and 3.10 (the remaining network calls go through the shared HTTP client). Way back: Build 2.

## 1. Before installing
- [ ] Backup from the phone page (sealed, with keys), code noted.
- [ ] Note the Build 2 values from the remote log: `start.usable`, `streams.order`, `player.firstFrame`,
      `detail.badges`.

## 2. Checklist from the plan
- [ ] Series: start episode 1, episode 2 starts automatically, close the player → the list shows the sources of
      episode 2.
- [ ] Source with an expired link (resume an older session) → after the repair, audio track and subtitles are right.
- [ ] Title with a commentary track in Dolby Digital → the main audio is chosen.
- [ ] Switch profile A → B right after the start: A's progress does not appear in B.
- [ ] Set the profile to English → the detail page is English at once.
- [ ] Film detail page: badges appear with the first addon.
- [ ] Leave the player with the audio panel open via „Zurück“ → preloading works afterwards.
- [ ] „Überspringen“ 5 s before the end of the file.

## 3. Additional checks (Build 3 additions and review notes)
- [ ] Resume a title with a sync position → it jumps to the right spot (also with a Dolby Digital audio switch).
- [ ] Play a special (season 0) → up next is the next special, never S1E1. A regular episode never offers a special.
- [ ] Restore a plain (unsealed) backup → existing logins and keys stay.
- [ ] Open the same film twice → the badges on the second visit match the first, or show more (never fewer).
- [ ] Trailer on a title without a direct trailer → starts within about 8 s, or shows „nicht verfügbar“.
- [ ] Sound/video probe on a server without Range support (disk cache title) → starts normally, no full download.
- [ ] Ratings, rating icons, app-update check, collection link/code import and addon subtitles still work.
- [ ] Scrolling through „Weiterschauen“ and source lists feels at least as smooth as Build 2.

## 4. Deliberate changes to notice
- Commentary and audio description tracks are never chosen automatically. A language that has only commentary is
  skipped; audio description is chosen only when it was remembered.
- During a rate-limit pause, the search of an open page still runs; only background refreshes wait.
- Source search shows intermediate results at once; badges from the first answer are only ever added to.
- A credits skip stops 1 s before the end of the file (before: 5 s).
- While a special plays, the side panel's episode list also shows season 0.
- Network calls that had no total time limit now have one: ratings 20 s, version probe 8 s, sound probes 20 s.

## 5. Expected remote-log lines
- `player: Startschritte placeholderCheck,selectAudio,…` once per session. After a repair:
  `player: Startschritte selectAudio(restore),play`.
- `player: Sprung wiederholt` only when the first resume jump did not land.
- `profil: Ergebnis verworfen (Epoche)` only on a quick profile switch.
- `metric: detail.badges <ms>` clearly below the Build 1 value; compare `metric: streams.order` and the `hitch`
  count with Build 2.
- `trailer` lines with ms per step.

**Fallback triggers:** playback starts without sound or with the wrong track; the source list stays empty.

## 6. Observations during the device test
