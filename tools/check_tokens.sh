#!/usr/bin/env bash
# Task 5.5 (D-3): design tokens only. Fails when an App source file outside App/Sources/Views/Design/ sets a fixed
# font size (`.font(.system(size:`) or a literal colour (`Color(red:`); those belong in the design layer
# (`Theme`, `ThemeValues`, `LookTheme`). Files listed in tools/token_allowlist.txt are skipped (see the reasons there).
# Usage: tools/check_tokens.sh [repo root]   (exit 1 on a finding, exit 2 if the check itself fails)
# Used by the CI job "test" (step "Design tokens").
set -euo pipefail
root=${1:-.}
cd "$root"
export LC_ALL=C
allow=tools/token_allowlist.txt
[ -f "$allow" ] || { echo "check_tokens: $allow missing"; exit 2; }
[ -d App/Sources ] || { echo "check_tokens: App/Sources missing"; exit 2; }
pattern='\.font\(\.system\(size:|Color\(red:'
# Allowlist: one path per line (relative to the repo root); text after '#' and blank lines are ignored.
allowed=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$allow")
status=0
hits=$(grep -rnE --include='*.swift' "$pattern" App/Sources || [ $? -eq 1 ]) || { echo "check_tokens: grep failed"; exit 2; }
while IFS= read -r line; do
    [ -n "$line" ] || continue
    file=${line%%:*}
    case "$file" in App/Sources/Views/Design/*) continue ;; esac
    if printf '%s\n' "$allowed" | grep -qxF "$file"; then continue; fi
    echo "::error file=$file::fixed font size or colour outside Views/Design (use a theme token): ${line#*:}"
    status=1
done <<< "$hits"
# Stale entries only warn: a task that converted its file removes the line in its own commit.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$f" ]; then echo "::warning::$allow lists $f, which does not exist"; continue; fi
    grep -qE "$pattern" "$f" || echo "::warning::$allow lists $f, which no longer needs it"
done <<< "$allowed"
[ $status -eq 0 ] && echo "check_tokens: ok"
exit $status
