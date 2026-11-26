# Device test – Build 5 (5a + 5b + 5c in one build)

Build: branch `build-5`, head ce56ca5 (Tasks 5.1–5.6 of docs/superpowers/plans/2026-11-22-verbesserungen.md plus the
Task 4.5 minors, on top of `b4-nacharbeit-2` 649b50f). CI: pending. App code was never compiled locally; CI is the
first compiler. Way back: `b4-nacharbeit-2`. Decision round 26.11. (section 13) on top: commits c41ce76 to the
docs commit of that round; its PlayerCore tests were not run locally (CPU pause), CI runs them first.

Format per line: action → expected → confirming remote-log line (`–` = visual only).

## 1. Before installing
- [ ] Backup from the phone page (sealed, with keys), code noted. Remote log on (Einstellungen → System → Fern-Log).
- [ ] Note: untouched profiles get the new default look at once (see section 13).

## 2. Profile picker
- [ ] Start with ≥ 2 profiles → ring with gap, lift, dimmed name as before → `fokus Profilwahl: Fokus auf Profil i von n`.
- [ ] VoiceOver on the picker → reads the name and „Profil i von n“ → –
- [ ] Profile names and login steps render regular weight, not semibold → –

## 3. Home, default look
- [ ] Start the app → one cards line → `home: Karten: Form querformat, Größe gross, Titel immer, Abstände luftig, Reihentitel standard, Fokus Glanz`.
- [ ] Hero at launch → logo, meta line, ratings, two-line overview, buttons (heroInfo standard, decision 26.11.) → `hero: Stil vollbild, Info standard, Titel logo, Hintergrund folgt Fokus an`.
- [ ] Down into the rows → info collapses (logo ≈ 100, meta, ratings, overview), collapse latch as before → `nav … Info eingeklappt …`, `ruckler` like Build 4.
- [ ] Rest 1 s on a card → prefetch still runs, one backdrop swap per rest (backdropFollowsFocus on by default) → `hero: Fokus-Hintergrund <id>` at most once per rest.
- [ ] Quality strip below posters on, large cards, focus into a poster row → collapsed overview one line, logo ≈ 93, row fully visible → `nav: Info eingeklappt: … Logo 93, Beschreibung 1 Zeile`.
- [ ] Fast left/right in a 40-card row (querformat gross), up/down between rows and into the hero → no jump, no stutter → `nav` lines unchanged, `ruckler` per minute not above Build 4.
- [ ] Focus the lowest row (also on a home with only landscape/collection rows) → card title below the card fully on screen → `nav: … unten …`.
- [ ] Row gap and hero button gap at luftig → hero buttons keep their gap, focus ring does not touch the first row heading → –
- [ ] „Reihen & Collections“ button and status tiles sit one row gap below the last row (moves with rowSpacing) → –
- [ ] A row that fails to load → no height jump of the rows below → –

## 4. Home hero variants (Aussehen › Startseite & Hero)
- [ ] heroInfo standard (default) → expanded and collapsed exactly like Build 4 follow-up 2 (list 470, collapsed ≈ 451 window) → `hero: Stil vollbild, Info standard, …`.
- [ ] heroInfo minimal → logo + buttons only → `hero: Stil vollbild, Info minimal, …`.
- [ ] backdropFollowsFocus an (default), rest on a card → one swap per rest; quick moves → none → `hero: Fokus-Hintergrund <id>` at most once per rest. aus → no swap, no line.
- [ ] vollbild: up from the first row → focus on „Abspielen“ → –
- [ ] banner → card, buttons inside the card bottom; down → row 1, up → „Abspielen“ → `hero: Stil banner, …`.
- [ ] banner/karussell collapsed (focus in the tab bar) → note whether the button row shows below the shrunk card → –
- [ ] karussell, top navigation: left on „Abspielen“ / right on „Details“ (click and swipe) → title changes, wraps at the ends, peek not focusable → `hero: Karussell vor → <Titel> (3/8)` / `… zurück → …`.
- [ ] karussell, up/down from the buttons → tab bar / row 1, no title step → no `Karussell` line.
- [ ] karussell, sidebar navigation: left on „Abspielen“ opens the sidebar, no step; right still steps → `hero: Karussell vor → …` only.
- [ ] aus → page without hero; up from the first row → navigation → –

## 5. Cards and rows (Aussehen › Startseite)
- [ ] Each card option through all values (cardShape, cardSize, corners, rowSpacing, rowTitle, cardTitles, focusScale/Border/Shadow, glow, expandPosters) → home follows at once, focus stays on the same card → new `home: Karten: …` line per change.
- [ ] Glow on → corners, scale, border, shadow rows dimmed with the glow reason → –
- [ ] Glow off, focusBorder + focusShadow tief → border and shadow not cut at the list top/bottom edge → –
- [ ] cardTitles fokus → title fades in on the focused card only, row height constant → –
- [ ] Change cardTitles and glow from the phone page while a home card has focus → focus returns to the same card → –
- [ ] expandPosters on + shape poster → expands after ~0.5 s, card scrolls to the left edge → –
- [ ] Diagnose › „Alte Karte (Test)“ on → home looks like Build 4 → `home: Diagnose alte Karte an`, `home: Karten: alte Karte (Diagnose)`.
- [ ] Kalender with Kartengröße groß → tiles fill the strip, no extra gaps → –
- [ ] Landscape film cards → quality badges top right → –

## 6. Navigation and clock
- [ ] Hauptnavigation seitenleiste and back to oben → tab bar guard and top-edge watch as before → `nav: Hauptnavigation seitenleiste, Inhalt ab 150` (content still starts at 80 by decision).
- [ ] Uhr an → clock top right, level with the top bar (oben: scrolls away with it; sidebar: fixed, hidden on pushed pages); never in the player → `nav: Uhr an (oben)`, `nav: Uhr-Rahmen x a–b, y c–d` (right edge 1840, top 56).
- [ ] Wait for a full minute → minute switches on the full minute, 24 h → –

## 7. Settings layouts (Aussehen › Einstellungs-Layout)
- [ ] spalten → exactly as before → –
- [ ] kacheln → after the choice page closes the root switches; 4 columns, OK opens a page, Menu back to the grid, Menu again → Start → `nav: Einstellungs-Layout spalten → kacheln`, `nav: Einstellungen › Aussehen (Kachel)`.
- [ ] liste → one centred column with all categories, subpages open and close, Menu → Start → `Einstellungen (Liste): X per Fokus|Bildlauf`.
- [ ] Look rows: a changed row has an accent dot; „Folgen“ / „Titelbild“ rows show their value; summary n matches → `aussehen: Mein Look · <n> Abweichungen` (extras counted).
- [ ] Aussehen has no „Plaketten-Stil“ row, Startseite no „Titelbild oben“ toggle; Hero-Stil aus → Startseite hides „Titelbild zeigt“ → –
- [ ] Profile with Build-4 „Plaketten-Stil Text“ or „Titelbild oben aus“ and a changed look → after the update Plaketten-Stil (look) = Text, Hero-Stil = Aus → –
- [ ] Plaketten-Stil logos / text in the look → hero badges (heroInfo ausführlich) follow → –
- [ ] Hintergrundton swatches → four tones distinguishable (two-tone swatch) → –
- [ ] Category pages: leading status circle visible, lighter than the card, tinted with graphit/tinte/warm → –

## 8. Detail page and source list
- [ ] Open a movie (default) → kino layout, logo title → `detail: Look: kino · Text 2 Zeilen · Besetzung kreise · Plaketten logos · Bewertungen text · Folgen reihe · Titel logo (mit Logo)`.
- [ ] Kino head height → main button not in the overscan, page does not scroll on entry → `detail: Kino-Kopf: Fläche <h> pt, Kopf <k> pt, Serie ja|nein` (expect area ≈ 960).
- [ ] Each `detail.*` option through all values, once with a movie, once with a series → –
- [ ] Kino over a bright picture → text readable; zentriert: title at the top readable → –
- [ ] Title with a failing or missing logo → poster + text title → `detail: Titel-Logo nicht geladen: Poster und Titeltext`.
- [ ] Flat logo → note whether it sits centred in the 260 pt slot (gap to the info block) → –
- [ ] Series, kino → note whether the episodes peek in below the head → –
- [ ] Season change (reihe) → row starts at the first unwatched episode → `detail: Folgenreihe Staffel 2: Start bei Folge 3`.
- [ ] Source list first row → one line per source → `quellen: Darstellung kompakt`.
- [ ] Return from the player → focus and scroll of the source list kept, also into another season → `playerDismissed` path, no new line.
- [ ] Primary button at rest with a white/light accent → distinguishable from the focused button → –

## 9. Player (Aussehen › Player, while a film runs)
- [ ] Steuerleiste minimal / standard / ausfuehrlich → minimal: timeline + times only; ausfuehrlich: chapter marks + gesture line → –
- [ ] Zeitanzeige ende → „Endet um HH:MM“, keeps running → –
- [ ] Plaketten voll with a DV/Atmos source → „4K · Dolby Vision · Atmos · 7.1 · HEVC · NN Mbit/s“ (max 6), filled, not white logos; also TorBox playback and trailer → –
- [ ] Spur-Panel Seite (▼) → panel from the right; ▲ from the first audio row closes; ▲ from subtitles only jumps to audio → `player: Spur-Panel öffnen (…, Seite)`, `Panel auf (Seite)`, `Panel zu (Wisch nach oben)`.
- [ ] Seite → rows indented equally left/right, long track names not cut earlier → –
- [ ] Unten (▲) → one row Ton | Untertitel, Versatz as a strip of steps below (decision 26.11.); ▼ from the last list row moves onto the strip, ▼ from the strip closes; ▲ from the strip lands on the active row → `Panel auf (Unten)`, `Panel zu (Wisch nach unten)`.
- [ ] Unten during an audio reload (strip locked) → ▼ from the last list row closes → `Panel zu (Wisch nach unten)`.
- [ ] Mitte (▲) → dimmed card, only Menu closes; subtitles do not touch the card edge → `Panel auf (Mitte)`, `Panel zu`.
- [ ] Nächste Folge karte / leiste / vollbild (series, autoplay) → countdown from 20 s; focus on „Jetzt abspielen“, ◀/▶ moves to „Abbrechen“; Select starts or cancels; Menu and Play/Pause as before; vollbild: video small top left → `player: Up-next: <Titel> · Stil karte`, `Up-next: Jetzt abspielen`, `Nächste Folge startet` / `Up-next abgebrochen (Knopf)`, `Menu: Up-next abgebrochen`.
- [ ] Up-next cancelled → focus back on the video, ◀/▶ jump ±10 s again → –
- [ ] vollbild with a DV source → video draws cleanly under the scale animation → –
- [ ] „Jetzt abspielen“ button with a light accent → resting readable (accent 80 %, dark text), focused white → –
- [ ] „Noch da?“ (counter small) → answer both ways → `player: Noch da?: gefragt (Stil dialog)`, `Noch da?: Weiterschauen` / `Noch da?: Beenden`.
- [ ] „Noch da?“ → Weiterschauen with episode 2 preloaded → next episode starts → `Noch da?: Weiterschauen`, then the episode start.
- [ ] „Noch da?“ → Menu → note „Wiedergabe beendet …“ → `Noch da?: Beenden`. No answer → `Noch da?: keine Antwort in 60 s, nichts gestartet`.
- [ ] All four player cards over a bright HDR scene → readable → –
- [ ] VoiceOver on the video → „<Titel>, Läuft, 42:10 von 2:08:00“, actions play/pause, ±10 s → –

## 10. Other screens
- [ ] Settings › Trakt verbinden → title, QR, steps, 90 pt code; VoiceOver spells the code; „Verbunden ✓“ green → –
- [ ] Phone page → all texts fit at 29 pt (also with the backup code block); status lines with symbol → –
- [ ] Library › TorBox row → tiles 480 × 180, nothing cut (also with the resolving spinner) → –
- [ ] Reihen & Collections › Verschieben → orange frame and tile; VoiceOver adds „wird verschoben“ → –
- [ ] Look rows of later builds show plain „kommt mit Build …“ notes (no „bis dahin“ any more, the old rows are gone); long notes fit in two lines → –

## 11. Accessibility
- [ ] Bewegung reduzieren on → no crossfades, no poster expand, no focus video/GIF on package tiles, row manager bar opens without animation → –
- [ ] Bewegung reduzieren on → Bewegung / Poster aufklappen rows one line at rest, full help on focus (note the jump) → –
- [ ] Transparenz reduzieren on → confirmation scrim opaque, rows and badges opaque grey → –
- [ ] VoiceOver on home cards → title and state (year, progress, watched); Top 10 „Platz n, Titel“ → –

## 12. Reset and round trip
- [ ] „Alles auf Standard zurücksetzen“, then change each of the 35 options once → no page breaks → `aussehen: Mein Look · <n> Abweichungen`.
- [ ] Back to `b4-nacharbeit-2` and forward again → profiles load, `detailExtras` survives → –

**Fallback triggers:** focus jumps or hangs on home (first „Alte Karte (Test)“, then fall back); detail page does not
open or focus does not reach the source list; player overlay covers the controls or audio/subtitle choice fails.

## 13. Decisions (user, 26.11. 07:35)
- Taken: Apple-TV preset heroInfo standard, backdropFollowsFocus on; clock stays off, all other defaults stay.
- Taken: player badges stay in standard; up-next back to the plan (20 s, focusable „Jetzt abspielen“ / „Abbrechen“);
  Unten back to the plan (one row Ton | Untertitel, Versatz as a strip below); gestures, „Noch da?“, skip and track
  choice unchanged. Consequence: arrows no longer cancel up-next (they move between the buttons).
- Taken: old rows „Plaketten-Stil“ and „Titelbild oben“ removed; a non-default old value moves into the look once on
  load (JSON unchanged); hero badges read the look's badge style.
- Taken: collapsed hero info shortens the overview to one line when two lines leave the row no room (strip case:
  logo 93, row fits).
- Still open: Apple-TV defaults for untouched profiles (detail kino, white „logos“ badges, compact source list,
  episode row; minimal control bar + side track panel); clock default for top-bar profiles; Mitte replaces the
  two-step menu; sidebar content inset 150 only as a token; cardShape querformat recuts every poster row; detail
  (compact source list text line, zentriert without sources panel, description on press); look tweaks (status
  circles 14 %, two-tone swatches, orange move frame, captions 29 pt); collapsed overview in the 69 pt edge band.
