# Device test – Build 4 follow-up 2

Build: branch `b4-nacharbeit-2`, head 1c79685 (P1 profile picker focus style, P2 collapsing hero info, P3 calmer
prefetch/badge chain + render-side measurement). CI 45703936854 green, installed 25.11.2026 22:49 via atvloadly (ID 10).

## Test 1 (25.11. ~22:50, remote log on)

Log: `logs/player-2026-11-25.log` from 21:49:53Z (copy: `~/.cache/claude-tmp/arbeit/b4n2/geraetetest-1.log`).

### Observations (user)
1. **Row no longer cut off** – posters fully visible (`nav` lines: `Abstand 0, unten +5`, list 451…1080). Fixed.
2. **Collapsed info almost gone** – only the meta line („2026 · 2 h 38 min · FSK 12“) is left; the user expected the
   info to move up, not to shrink. Ratings and overview were dropped on purpose by P2.
3. **Logo missing** in the collapsed info although the metadata says `Logo ja`; empty backdrop where the logo belongs.
4. **Row heading jitters** (jumps up and down) while pressing right quickly.

### Log evaluation
- Jitter: `nav: Reihe fokussiert, Überschrift nach oben` every ~180 ms for the same row (21:52:11–15Z, 20+ lines):
  the row reports focus lost/gained on every card move, so the heading snap scrolls and animates on every step.
- Stutter now attributable (`ruckler` events): missed frames mostly in windows with backdrop swaps
  (`verpasst bei`: Hintergrund 22, Poster 8, none 12; longest 58 / 88 ms with backdrop swaps). Backdrops decode at
  3840×2160 (~31.6 MB each); the image cache evicts posters (`verdrängt` up to 24, `freigegeben 362,8 MB`).
- Badge batching works (`Plaketten gebündelt: 1 Durchgang`), main thread otherwise calm (0–1 missed frames per 5 s
  without backdrop swaps).

### Decisions (user, 25.11. ~23:00)
- Collapsed info keeps **everything** (logo, meta line, ratings, 2-line overview), only moved up and a bit more compact
  (logo ~100 pt instead of 140, tighter spacing).
- **Home hero backdrop capped at 1920×1080** (detail page stays 4K).

### Fix round
- P2: heading jitter (focus lost/gained per card move), missing logo, full compact info.
- P3: home backdrop decode cap 1920×1080.
