# Device test Build 4 (branch `verbesserungen-build-4`)

Tasks 4.1–4.5 of docs/superpowers/plans/2026-11-22-verbesserungen.md: focus and navigation fixes (4.1a home,
4.1b rest, A-B-10 kit date filters), the `Look` model with „Mein Look“ and migration (4.2), the configurator import
(4.3), the runtime theme (4.4) and the „Aussehen“ settings page with all 35 options (4.5). Head 50e9ff4,
CI 45654859194 green, installed 25.11. ~17:51 via atvloadly APP_ID=10. Way back: Build 3 (8159e35).

User decisions 25.11.: the summary counts against the old default values (unchanged, new and Build 3 profiles show
„Standard“; the reset goes back to the old defaults; same format), and the wording is „Standard“ instead of
„Apple TV“. The plan lines that say „Apple TV“ are read as „Standard“ below.

## 1. Before installing
- [ ] Backup from the phone page (sealed, with keys), code noted.
- [ ] Turn on the remote log on the TV (Einstellungen → System → Fern-Log); secret in `~/.config/playerlog/secret`.
- [ ] Build 3 device test done or noted as open (`build-3.md`).

## 2. Checklist from the plan
- [ ] Press „Abspielen“ on the hero and open a tile at once → no late jump.
- [ ] Hide, delete and move a row up via the context menu → focus lands visibly on a row.
- [ ] Focus a kit collection row while it loads → focus moves on to the first tile.
- [ ] Create a second profile in the settings → you stay in the settings.
- [ ] Turn Wi-Fi off and on briefly → grey tiles fill in.
- [ ] Aussehen: step through all eight accent colours and all four background tones → the settings page recolours
      at once, focus stays on the row.
- [ ] Step through font size and font character once each → nothing is cut off.
- [ ] All 35 options are visible; the later ones carry „kommt mit Build 5a/5b/5c“.
- [ ] „Alles auf Standard zurücksetzen“ (with confirmation) → the „Mein Look“ row shows „Standard“.
- [ ] Import a configurator JSON (any template) via the phone page → values match, row shows „angepasst · <n>“.
- [ ] Back to Build 3 and forward again: profiles load, the look of the old build is unchanged.

## 3. Additional checks (Build 4 additions and review notes)
- [ ] A Build 3 profile and a new profile show „Mein Look · Standard“ (not „angepasst · 5–6“).
- [ ] Import the Apple TV template from the configurator → shows „angepasst · 6“ (expected, it differs from the old
      defaults).
- [ ] A changed row carries an accent dot; long press → „Auf Standard zurücksetzen“ resets only that row, focus stays.
- [ ] „Glanz“ on (`home.focusGlow`) → corners, focus scale, focus border and focus shadow are disabled with the hint
      „Bei Glanz bestimmt tvOS Form, Größe und Schatten der Karte.“
- [ ] Focus scale none, border none, shadow none, glow off → hint „Ohne Fokus-Zeichen setzt die App einen weißen
      Rahmen.“ and a white focus border appears.
- [ ] System „Bewegung reduzieren“ on → hint at motion and expand posters.
- [ ] Accent tints the whole app (root tint): blue → #3B82F6; pink/green/purple → coral/sage/violet.
- [ ] Neutral symbol tile instead of the nine category colours, also in the row browser and the player track tiles.
- [ ] Language row is at the top of the settings again; disabled rows are one line high.
- [ ] Conditional rows (phone page, login, icon set, delete profile) stay in place and are only shown as disabled.
- [ ] Hero source fails → the hero frame stays with a status tile and retries on wake; the layout does not change.
- [ ] Collection hero („Abspielen“) is not dead.
- [ ] „Heute neu“, hero slides and kit rows with a date filter are right after a day change (leave the app overnight,
      or across midnight).
- [ ] Calendar shows the running season even when only the last aired episode lies in the window.
- [ ] Rows show no duplicate entries.

## 4. Deliberate changes to notice
- Import writes the nearest old value for colours that do not exist yet (champagner → weiß, eisblau → blau,
  rot → pink, umriss/gefüllt → text).
- `detail.episodes` and `detail.titleArt` are not part of Build 4; they come in Build 5b as profile fields.
- Image errors: network errors and timeouts are remembered for 20 s, only 404/410 for five minutes; visible tiles
  retry when the network comes back.
- The profile picker appears only at app start, not after creating a profile in the settings.

## 5. Expected remote-log lines
- `navigation: später Sprung verworfen (<what>)` only in the hero/TorBox test case.
- `aussehen: Mein Look · <n> Abweichungen` after a change on the Aussehen page.
- Phone import: command list contains `aussehen <n> abweichungen`.
- `speicher: Import · ignoriert: <paths>` only for a backup from a newer build.

**Fallback triggers:** focus stays stuck on the home page; the settings cannot be operated.

## 6. Known minors (not blocking, task-4.5app-review.md)
- Background colour swatches all look black.
- Badge/hero style appear twice (dimmed catalogue row plus the old row).
- JSON round trips per row.
- Status dots are grey.

## 7. Observations during the device test
- **25.11. ~18:0x – phone page: focused button is solid blue, label invisible** („Fertig“ next to „Neuer QR-Code“,
  accent blau). Likely cause: root tint `theme.color.accent` (#3B82F6, commit 0164c17, Task 4.5 D-14) on plain system
  buttons that have no `ThemeActionButtonStyle`; the system button pulls the tint into the focused platter and the
  label. Same risk: ProfileRecoveryView („Erneut versuchen“, „Diese Fassung laden“, „Neu anfangen“), ProfileSettings
  („Profil anlegen“, „Abbrechen“), possibly StillWatchingPrompt („Beenden“).
