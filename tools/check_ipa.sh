#!/usr/bin/env bash
# Checks an IPA before it is published: no personal data, no LAN addresses, no keys or tokens.
# Usage: tools/check_ipa.sh Player.ipa   (exit 1 and a list of findings if anything matches)
# Optional: EXTRA_DENY = extra case-insensitive patterns (extended regex, one per line), for example
# personal names; kept out of the repo and passed in from a repository secret or the local shell.
# Used by the CI job "history" and by tools/backfill_releases.sh.
#
# Keys and tokens are only ever entered in the app (phone input page), so a CI build must not contain
# any. Identifiers such as "apiKey" or "token" are fine and are not searched for; the check looks for
# values: JWTs, 32/64-character hex keys (TMDB v3, Trakt/Simkl client IDs), LAN addresses, home paths.
set -euo pipefail
ipa=$1
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
unzip -q "$ipa" -d "$dir"
[ -d "$dir/Payload" ] || { echo "check_ipa: no Payload in $ipa"; exit 1; }
cd "$dir"
export LC_ALL=C
found=0 n=0
hit() { echo "check_ipa: $1"; found=1; }

# Everywhere, including the bundled frameworks. (/Users/... paths are not checked: CI builds under
# /Users/runner/ and the prebuilt engine carries its upstream author's build paths.)
f=$(grep -ralE '192\.168\.[0-9]{1,3}\.[0-9]{1,3}' Payload || true);     [ -z "$f" ] || hit "LAN address in: $f"
f=$(grep -ralE '/(var/)?home/[a-z]' Payload || true);               [ -z "$f" ] || hit "Linux home path in: $f"
f=$(grep -ralE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' Payload || true); [ -z "$f" ] || hit "JWT in: $f"
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  n=$((n + 1))
  f=$(grep -railE -e "$pat" Payload || true); [ -z "$f" ] || hit "denied pattern #$n in: $f"
done <<< "${EXTRA_DENY:-}"

# Hex keys: only in the app's own code and resources. The prebuilt FFmpeg frameworks carry public
# upstream constants (for example the Audible AAX default key in libavformat) and are left out.
while IFS= read -r p; do
  # 32 or 64 hex digits with at least one letter, not part of a longer word (Swift's _anon.<hash>
  # and mangled _<hash>S symbols are skipped by the surrounding-character rule).
  k=$(grep -aoE '(^|[^0-9A-Za-z_.$])([0-9a-f]{32}|[0-9a-f]{64})([^0-9A-Za-z_.]|$)' "$p" \
        | grep -aoE '[0-9a-f]{32,64}' | grep -a '[a-f]' | sort -u || true)
  [ -z "$k" ] || hit "hex key-like value in $p: $(echo "$k" | head -3 | tr '\n' ' ')"
done < <(find Payload -type f ! -path '*/Frameworks/AetherLib*')

if [ "$found" -ne 0 ]; then echo "check_ipa: FAILED - do not publish"; exit 1; fi
echo "check_ipa: OK ($(find Payload -type f | wc -l) files checked)"
