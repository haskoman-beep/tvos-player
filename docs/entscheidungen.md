# Decision log

One entry per decision, three lines each: what was decided, why, and what follows from it. Newest entries go at the
end. The first seven are the architecture decisions (ADR-1 to ADR-7) from the analysis of 22 Nov 2026
(`docs/superpowers/analysis/2026-11-22/03-engineering-entscheidungen.md`, section 5), where context, alternatives and
migration paths are written out.

## ADR-1: App and `PlayerCore` split (22 Nov 2026)
- **Decision:** platform-independent logic lives in `Packages/PlayerCore` (Foundation only, tested on Linux); the app is a SwiftUI shell. Every rule that can be written as "state + event → next step" belongs in `PlayerCore`.
- **Why:** there is no Mac; a Linux test run takes minutes, a device round trip 15 to 20 minutes.
- **Follows:** playback flows (source fallback, next episode, input locks) move into `PlayerCore` step by step; a separate `PlaybackKit` package is not built.

## ADR-2: `AppModel` as the central model (22 Nov 2026)
- **Decision:** keep `AppModel` as the facade, but move to `@Observable` and add a profile epoch (`ProfileScope`) that invalidates profile-bound tasks.
- **Why:** with `ObservableObject` every change re-evaluates all built cards, and a profile switch clears state by hand in many places.
- **Follows:** services (progress, streams, catalogue, profiles, metadata) move out one per build; storage stays as it is.

## ADR-3: XcodeGen, builds only in CI, unsigned IPA, atvloadly for updates (22 Nov 2026)
- **Decision:** keep the chain; CI runs the `PlayerCore` tests before every build, the release text carries the IPA's SHA256, and an install shows build and commit on the TV first.
- **Why:** without a Mac and a developer account there is no alternative; the gaps were cheap to close.
- **Follows:** pinned dependencies; the app target moves to strict concurrency and Swift 6 later, in steps.

## ADR-4: Persistence and migrations (22 Nov 2026)
- **Decision:** reading never leads to overwriting: unreadable profiles open „Profile nicht lesbar“ (profiles not readable), the last two versions are kept, and decoding never fails on a single value.
- **Why:** one unknown value (for example after going back to an older build) used to replace all profiles with a default profile.
- **Follows:** keys move to the Keychain in later builds with double bookkeeping first; the stored format stays readable by build 249 until then.

## ADR-5: Own web server for the phone page (22 Nov 2026)
- **Decision:** keep the phone page, but the TV is the authority: one-time QR address bound to the first phone, sensitive changes confirmed on the TV, export without keys by default, a backup with keys only as `player-sicherung.enc` with a 12-character code (three groups of four, `XXXX-XXXX-XXXX`) shown on the TV.
- **Why:** before, the token in the address unlocked everything, including all keys, without any confirmation.
- **Follows:** one extra press on the remote for sensitive actions; no data migration.

## ADR-6: Remote log as the diagnostic path (22 Nov 2026)
- **Decision:** off by default; it sends only to the receiver chosen on the TV, signed with a shared secret set on the phone page; a log history stays on the device; measuring points are `metric:` lines with fixed names.
- **Why:** it is the only window into the running device, but any device on the network could receive titles and errors.
- **Follows:** `tools/logcollector.py` needs the secret (`PLAYERLOG_SECRET` or `--secret-file`); the log has to be turned on once after the update.

## ADR-7: Ranking and choice of sources (22 Nov 2026)
- **Decision:** the list shows the addon order (or „Smart (App)“), the automatic choice uses the app's ranking; the parser never throws or crashes.
- **Why:** the split resolves the conflict with the first spec; the weak point is parsing free text from addons.
- **Follows:** traits are computed once per stream, structured fields come before free text, addons are told apart by manifest ID.

## Interface language (23 Nov 2026)
- **Decision:** the interface stays German; the profile language only sets titles, descriptions and trailers.
- **Why:** there is no string catalogue, and the README promised English that did not exist (E-30, Q-24).
- **Follows:** README and spec say so; an English interface would be its own project.

## TVDB and MDBList lists (23 Nov 2026)
- **Decision:** the unused TVDB key field is removed from the phone page; MDBList stays for ratings only.
- **Why:** neither TVDB episode order nor MDBList lists were ever built (E-51, E-53), but both were offered.
- **Follows:** a TVDB key already stored in a profile stays there unused; no format change.

## Default sound bridge (23 Nov 2026)
- **Decision:** TrueHD, DTS and DTS-HD MA stay converted to Dolby Digital Plus 5.1 by default; the README now says so.
- **Why:** this reaches a sound system over optical or ARC; the README claimed multichannel PCM (W-A-12, W-12).
- **Follows:** 7.1 becomes 5.1 and height channels are dropped for these formats.

## Nuvio account sync (28 Nov 2026)
- **Decision:** the app can sign in to one Nuvio account per device and use it as an additional sync target next to the profile's progress source. It reads collections, addons, watch progress and watch history, and writes watch progress only (`sync_push_watch_progress`). Each local profile picks one account profile. Owner decisions:
  - The password is typed on the phone page and sealed there (ChaCha20-Poly1305 with a key carried in the QR address fragment); without sealing nothing is sent, there is no cleartext fallback.
  - Existing local progress is not uploaded at first connect; only titles played after connecting are pushed.
  - Removals stay local: "remove from continue watching" and "mark unwatched" delete nothing on the account.
  - Settings blobs (profile settings, home catalog settings) stay separate; the app keeps its own settings (D1).
  - Addons removed on the account are listed in the next import preview and asked about one by one; only addons that came from the account are offered, locally installed ones are never touched (D2).
  - A chosen account profile that gets a PIN later stops the sync until another profile is chosen (D3).
  - The first pull takes all titles, however old (D4).
- **Why:** the service's terms allow automation only through the APIs documented for public use, so the client follows the public API reference (v1.3) alone and uses no code from other clients. `NuvioEndpoint` is a closed list of 13 calls; `NuvioGuardTests` pins that list and fails when a source file names a full-replace, delete, sign-up, TV/QR login, device registry, tracker-token, provider-credential or settings call, when the service's host appears outside `NuvioClient.swift`, or when anything but `NuvioSession.swift` names the Keychain entry `nuvio.session`.
- **Follows:** the session lives only in the Keychain (device-only, in no profile and no backup); pulled progress lands in the normal progress books. Known limits:
  - Sealing protects only against a passive listener on the Wi-Fi. Someone who can change the page in transit can read the password; the key may stay in the phone browser's history; there is no forward secrecy.
  - The first progress snapshot holds at most the newest 200 rows (the server's cap); older unfinished titles from before the first connect are not imported. The watch history is read in full, in pages of 500 (20 per pass, then resumed in the next pass).
  - The scope of sign-out is not documented: it may end only this session or all sessions of the account.
  - A title marked watched by hand without a known duration is not pushed, because a push needs position and duration.
