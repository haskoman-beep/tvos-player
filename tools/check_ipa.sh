#!/usr/bin/env bash
# Checks an IPA before it is published: no personal data, no LAN addresses, no keys or tokens.
# Usage: tools/check_ipa.sh Player.ipa   (exit 1 on a finding, exit 2 if the check itself fails)
# Optional: EXTRA_DENY = extra case-insensitive patterns (extended regex, one per line), for example
# personal names; kept out of the repo and passed in from a repository secret or the local shell.
# Used by the CI job "history" and by tools/backfill_releases.sh.
#
# Keys and tokens are only ever entered in the app (phone input page), so a CI build must not contain
# any. Identifiers such as "apiKey" or "token" are fine and are not searched for; the check looks for
# values: JWTs, 32/64-character hex keys (TMDB v3, Trakt/Simkl client IDs), private LAN addresses, home paths.
# Fail-closed: a grep error (for example an invalid pattern) stops the check. Findings name only the pattern
# class and the file, never the matched value (CI logs are public).
set -euo pipefail
ipa=$1
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
unzip -q "$ipa" -d "$dir" || { echo "check_ipa: cannot unzip $ipa"; exit 2; }
[ -d "$dir/Payload" ] || { echo "check_ipa: no Payload in $ipa"; exit 2; }
cd "$dir"
export LC_ALL=C
found=0
hit() { echo "check_ipa: $1"; found=1; }

# grep -l over Payload; prints matching files. Exit 0 = match, 1 = none, anything else = error → abort.
files() {
  local out rc=0
  out=$(grep -ral "$@" Payload) || rc=$?
  if [ "$rc" -gt 1 ]; then echo "check_ipa: grep failed (exit $rc) - check aborted" >&2; exit 2; fi
  printf '%s' "$out" | tr '\n' ' '
}

# Everywhere, including the bundled frameworks. (/Users/... paths are not checked: CI builds under
# /Users/runner/ and the prebuilt engine carries its upstream author's build paths.)
f=$(files -E '192\.168\.[0-9]{1,3}\.[0-9]{1,3}|(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}')
[ -z "$f" ] || hit "private LAN address in: $f"
f=$(files -E '/(var/)?home/[a-z]');                                  [ -z "$f" ] || hit "Linux home path in: $f"
f=$(files -E 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}');        [ -z "$f" ] || hit "JWT in: $f"

n=0
while IFS= read -r pat; do
  pat=${pat%$'\r'}
  [ -n "$pat" ] || continue
  n=$((n + 1))
  f=$(files -i -E -e "$pat"); [ -z "$f" ] || hit "denylist pattern #$n in: $f"
done <<< "${EXTRA_DENY:-}"
if [ "$n" -gt 0 ]; then echo "check_ipa: Denylist aktiv: ja ($n patterns)"; else echo "check_ipa: Denylist aktiv: nein"; fi

# Hex keys: only in the app's own code and resources. The prebuilt FFmpeg frameworks carry public
# upstream constants (for example the Audible AAX default key in libavformat) and are left out.
# Fail-closed: the file list and each grep stage go through temp files (next to Payload, inside the
# temp dir), and every exit code is checked; a find or read error aborts the check.
list="$dir/.files" m1="$dir/.m1" m2="$dir/.m2"
find Payload -type f ! -path '*/Frameworks/AetherLib*' > "$list" \
  || { echo "check_ipa: find failed - check aborted" >&2; exit 2; }
[ -s "$list" ] || { echo "check_ipa: no files to check - check aborted" >&2; exit 2; }
# grep exit: 0 = match, 1 = none, anything else = error → abort.
step() { local rc=0; "$@" || rc=$?; if [ "$rc" -gt 1 ]; then echo "check_ipa: grep failed (exit $rc) - check aborted" >&2; exit 2; fi; }
while IFS= read -r p; do
  # 32 or 64 hex digits (either case) with at least one letter, not part of a longer word (Swift's
  # _anon.<hash> and mangled _<hash>S symbols are skipped by the surrounding-character rule).
  step grep -aoE '(^|[^0-9A-Za-z_.$])([0-9a-fA-F]{32}|[0-9a-fA-F]{64})([^0-9A-Za-z_.]|$)' "$p" > "$m1"
  step grep -aoE '[0-9a-fA-F]{32,64}' "$m1" > "$m2"
  c=$(step grep -ac '[a-fA-F]' "$m2")
  [ "${c:-0}" -eq 0 ] || hit "hex key-like value ($c) in: $p"
done < "$list"

if [ "$found" -ne 0 ]; then echo "check_ipa: FAILED - do not publish"; exit 1; fi
echo "check_ipa: OK ($(find Payload -type f | wc -l) files checked)"
