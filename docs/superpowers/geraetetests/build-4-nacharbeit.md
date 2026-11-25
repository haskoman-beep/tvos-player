# Device test Build 4 follow-up (branch `b4-nacharbeit`)

Fixes for the three open observations of `build-4.md` §7 (device test 25.11.). Based on `verbesserungen-build-4`
(85a76c8). Way back: Build 4 (50e9ff4, CI 45654859194).

## 1. Before testing
- [ ] **Turn on the remote log** (Einstellungen → System → Fern-Log → „Ereignis-Log senden“). The Build 4 test had no
      log since 23.11.; without it the new measuring lines below are lost.
- [ ] „Ruckler protokollieren“ (Einstellungen → System → Diagnose) is on (default on).

## 2. What changed

| # | Symptom (build-4.md §7) | Fix | Commits |
|---|---|---|---|
| 1 | Blue buttons on the phone page, label invisible | Token button (`ThemeActionButtonStyle`) instead of system buttons: phone page, new profile, status cards, focus anchor (10 pages), skip button, post-play card | 6147f22, c559bfe, 208a1c6 |
| 2 | Fast right presses stutter while posters load | S1 frame meter; S2 tiles keep the TMDB poster until the addon poster is there, network return reloads only missing pictures, decode prepared off main; S3 stream results parsed off main, badge values kept; S4 progress index, stable card anchor, row ids once | b4n-s1 … s4 |
| 3 | Row too low / posters cut at the bottom until selected once | S5: heading snap checks at 0.4 / 0.9 / 1.5 s and re-snaps only when the row is off by > 2 pt; restarts after the placeholder → card hand-over | b4n-s5 |

## 3. Checklist
- [ ] Phone page („Fertig“, „Neuer QR-Code“): focused button readable in every accent colour.
- [ ] New profile („Profil anlegen“, „Abbrechen“), a status card with a button, a loading/QR page with „Fertig“.
- [ ] Player: skip intro/credits button and the card after a film („Abspann weiterschauen“, „Zurück“) readable.
- [ ] Home, fresh start: press right quickly through a poster row while posters load → no visible stutter, no
      empty tile flashing between TMDB and addon poster.
- [ ] Home, fresh start: move down into the first poster rows → each row sits fully visible, nothing cut at the
      bottom, without opening a tile first.
- [ ] Wi-Fi off and on → missing pictures fill in, visible ones do not flash.

## 4. Expected remote-log lines
- `ruckler: Startseite 5,0 s: <n> Bilder (60 Hz) · <k> verpasst · ≈<d> Bilder fehlen · längstes <x> ms · zuletzt: …`
  at most every 5 s while focus moves in a home poster row (only there). „0 verpasst“ while it visibly stutters
  points to the render side, not the main thread.
- `ruckler: Quellen abgelegt: <n> Einträge, Hauptthread <x> ms` only at ≥ 8 ms, at most every 10 s (later
  `Nachtrag · dazu k weitere`).
- `bilder: Kachelwechsel <n> · mit Lücke <g> · längste Lücke <x> ms · längstes Warten <y> ms` per 10 s; `mit Lücke`
  should be 0.
- `metric: home.rowBody <n> · karten <k> · fokus <m>` per 5 s while focus moves (home page only).
- `nav:` heading lines (vorher / nach Rasten / nach 1,5 s) with offset, row and list frame, safe area. If a row is
  cut off while the line says the row is at the top edge (Abstand 0), the cause is the layout (list top = safe area
  + 470), not the scroll – that is then a layout decision.
- `nav: Reihe <title>: Platzhalter → Karte`; `Übergabe entfällt` right after it without a remote press means the
  focus guard is too strict.
- `streams: <id>: Plakettenwerte neu, n behaltene Quellen abgelaufen` rarely.

**Fallback triggers:** home focus stuck, rows jump repeatedly, player buttons not operable.

## 5. Observations during the device test

Device test 25.11. evening (user, remote log switched on):

1. **Profile picker („Wer schaut?“): no visual focus feedback.** You cannot tell which profile is selected before
   confirming. Cause (code): `ProfilePickerView` (`App/Sources/PlayerApp.swift:243`) uses `.buttonStyle(.borderless)`
   with a text + circle label. On tvOS that style gives no focus highlight for such a label. The circle is also a
   fixed `.blue`, not the theme accent. Fix: focus-aware style (scale + accent ring, like the other token buttons).
2. **Home poster row still stutters** while pressing right (symptom 2 not fixed by S1–S4).
3. **Row still cut off at the bottom (symptom 3, S5 not effective).** User: the first move down does not scroll
   far enough, a piece at the bottom is missing; up and down again corrects it.
4. **No remote-log lines arrived.** `~/tvos_player/logs` has no file after `player-2026-11-23.log`, although the
   switch is on. The collector (`playerlog.service`, signed mode since 24.11. 22:04) runs and announces
   `Player-Log`, but it answers wrong signatures with a silent 401 (`log_message` muted). Candidates: the TV status
   is „noch kein Empfänger gewählt“ / „kein Schlüssel“, or the TV secret (phone page, key `playerlog`) differs from
   `~/.config/playerlog/secret`. The app keeps the last 500 lines in memory; once sending works, they flush,
   provided the app was not restarted. TV page shows receiver „Player-Log“ chosen. The signed collector and its
   secret date from 24.11. 22:04, after the last log, so the TV most likely never got this secret.
   **Fixed 25.11. ~21:15:** new key in 4 groups (`~/.config/playerlog/secret`, old one kept as
   `secret.alt-2026-11-24`), collector restarted, 465 buffered lines arrived (session from 20:59).

### Log evaluation (`logs/player-2026-11-25.log`, 20:59–21:16 local)

- **Row cut off = layout, not scroll.** Every `nav` line shows `Liste 627…1080` (list top = safe area 157 + 470,
  inset bottom 45), i.e. 453 pt of list, about 408 pt usable, but a poster row is 580 pt tall (`Reihe 1283…1863`).
  At `Abstand 0` (heading at the top edge) the row's bottom is ~130–170 pt below the screen. When the snap fails
  (`Abstand -95 … -133`, the system focus scroll wins: `nach Rasten` stays off or even gets worse, e.g. -98 → -110),
  the poster is fully visible and the heading is hidden instead. That matches „after up/down it is correct“.
  S5 cannot fix this; it needs a layout decision (smaller row, higher list top, or align to the row bottom).
- **Stutter: main thread mostly fine.** `ruckler` 5-s windows: 0–10 missed frames (mostly 2–4), longest 33–48 ms,
  once 83 / 97 ms. `zuletzt: Quellen abgelegt` in almost every window: the 350-ms rest after each focus stop starts
  the backdrop swap + source prefetch (`prefetch → … 84–257 Quellen`, 0.5–2 s) and badge updates (`Plaketten …`),
  which re-render rows (`metric: home.rowBody` up to 38, `karten` up to 51 per 5 s). No `Quellen abgelegt` line
  ≥ 8 ms, so parsing is off main as intended. Picture cache hit rate is low (`Cache Treffer 21 / Fehlgriffe 180`).
  Suspects: render side (backdrop crossfade, first poster uploads) and the prefetch → badge → row re-render chain.
  Quick A/B without code: Einstellungen → Quellen → „Quellen vorladen“ off, then the same right-press test.
- **S2 works:** all `bilder: Kachelwechsel … mit Lücke 0`; longest wait for an addon poster 3.7 s.
- Other: `ruckler: Hauptthread hing 262 ms` once when opening a detail page (streams list, 185 sources);
  `nav: Leiste hing fest` once in Einstellungen (handled by the existing fallback).

### Decisions 25.11. ~21:30 (user)
- Row cut off → **info area collapses** (Apple TV app style): from the 2nd row on the info area at the top shrinks and
  the list moves up so a whole row fits; at the top of the page the layout stays as now.
- A/B „Quellen vorladen“ off: „ruckelt aber nicht mehr so doll“ → the prefetch → badges → row re-render chain is
  part of the stutter, not all of it. Next: calm that chain (later prefetch start, batched badge updates without
  row re-render) and measure the render side (backdrop swap, first poster uploads).
- Profile picker: focus-aware style with accent ring (no decision needed).
