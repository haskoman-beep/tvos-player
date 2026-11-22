#!/usr/bin/env bash
# Writes the release notes (Markdown) for one Player build to stdout.
# Used by the CI job "history" (.github/workflows/build.yml) and by tools/backfill_releases.sh,
# so every release in the version history has the same format.
#
# Usage: tools/release_notes.sh BUILD BRANCH SHA RUN_ID DATE [PREV_REF [PREV_LABEL]]
#   BUILD      build number = CI run number (github.run_number), also CFBundleVersion in the app
#   BRANCH     integ (prerelease) or main (release); anything else is shown as-is
#   SHA        full commit SHA of the build
#   RUN_ID     GitHub Actions run id (github.run_id) for the run link
#   DATE       build date, ISO 8601 (for example 2026-11-22T09:55:57Z)
#   PREV_REF   optional: tag or commit the commit list starts after. Without it the script looks for
#              the previous build-* release that is an ancestor of SHA (main: previous full release first).
#   PREV_LABEL optional: how PREV_REF is named in the notes (default: PREV_REF itself)
# Environment: GH_REPO (owner/name, default haskoman-beep/tvos-player), EVENT (how the run was started,
# github.event_name, default push), NO_IPA=1 (no Player.ipa attached, for example an expired CI artifact),
# EXTRA_NOTE (one more line under the table). Needs git history with tags; the automatic lookup also
# needs the gh CLI (read access to releases).
set -euo pipefail

build=$1 branch=$2 sha=$3 run_id=$4 date=$5 prev=${6:-} prev_label=${7:-}
repo=${GH_REPO:-haskoman-beep/tvos-player}
event=${EVENT:-push}
url="https://github.com/$repo"
max=100

# Marketing version (CFBundleShortVersionString) as it was in this commit.
version=$(git show "$sha:App/project.yml" 2>/dev/null | sed -n 's/.*CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' | head -1)

# Previous release: newest build-<n> tag with n < BUILD whose commit is an ancestor of SHA.
find_prev() {
  local want_full=$1 tags t n
  tags=$(gh release list -R "$repo" -L 200 --json tagName,isPrerelease,isDraft \
           --jq ".[] | select(.isDraft | not) | select(.tagName | test(\"^build-[0-9]+$\")) | select(($want_full | not) or (.isPrerelease | not)) | .tagName" 2>/dev/null) \
    || { echo "release_notes: gh release list failed, no previous release used" >&2; return 0; }
  for t in $(printf '%s\n' $tags | sort -t- -k2,2nr); do
    n=${t#build-}
    [ "$n" -lt "$build" ] || continue
    git rev-parse -q --verify "refs/tags/$t^{commit}" > /dev/null || continue
    if git merge-base --is-ancestor "refs/tags/$t" "$sha"; then echo "$t"; return 0; fi
  done
  return 0
}
if [ -z "$prev" ]; then
  [ "$branch" = main ] && prev=$(find_prev true)
  [ -n "$prev" ] || prev=$(find_prev false)
  # No release yet: start after the previous successful CI build of the same branch.
  if [ -z "$prev" ]; then
    pnum="" psha=""
    if pr=$(gh run list -R "$repo" -b "$branch" -w build.yml -s success -L 100 --json number,headSha \
          --jq "[.[] | select(.number < $build)] | max_by(.number) | \"\(.number) \(.headSha)\"" 2>/dev/null); then
      read -r pnum psha <<< "$pr" || true
    else
      echo "release_notes: gh run list failed, commit list falls back to recent commits" >&2
    fi
    if [ -n "${psha:-}" ] && [ "$psha" != null ] && git rev-parse -q --verify "$psha^{commit}" > /dev/null; then
      prev=$psha prev_label="CI build $pnum (\`$branch\`, no release)"
    fi
  fi
fi
[ -n "$prev_label" ] || prev_label=$prev

case "$branch" in
  integ) kind="Prerelease from \`integ\`: built and checked by CI, not yet approved on the device." ;;
  main)  kind="Release from \`main\`: tested and approved on the device." ;;
  *)     kind="Build from \`$branch\` (not a release branch)." ;;
esac
day=$(date -u -d "$date" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo "$date")

echo "Player build $build. $kind"
echo
echo "| | |"
echo "| --- | --- |"
echo "| Build | $build (CI run number, shown in the app under Einstellungen › System) |"
[ -n "$version" ] && echo "| Version | $version |"
echo "| Branch | \`$branch\` |"
echo "| Commit | [\`${sha:0:7}\`]($url/commit/$sha) |"
case "$event" in
  push) how="push to \`$branch\`" ;;
  workflow_dispatch) how="manual CI run on \`$branch\`" ;;
  *) how="$event on \`$branch\`" ;;
esac
head=$(git log -1 --format=%s "$sha" | sed -e 's/</\&lt;/g' -e 's/|/\\|/g' -e 's/@\([A-Za-z0-9_-]\{1,\}\)/`@\1`/g')
echo "| Pushed as | $how, head commit: $head |"
echo "| CI run | [#$build]($url/actions/runs/$run_id) |"
echo "| Date | $day |"
echo
if [ "${NO_IPA:-0}" = 1 ]; then
  echo "No download: the CI artifact of this build had expired, so \`Player.ipa\` is not attached."
else
  echo "Download: \`Player.ipa\` below (unsigned; sign it with a sideloading tool before installing)."
fi
if [ -n "${EXTRA_NOTE:-}" ]; then echo; echo "$EXTRA_NOTE"; fi
echo
if [ -n "$prev" ] && git rev-parse -q --verify "$prev^{commit}" > /dev/null; then
  range="$prev..$sha"
  echo "### Commits since $prev_label"
else
  range="$sha"
  echo "### Recent commits (no earlier release found)"
fi
echo
log=$(git log --no-merges -n $((max + 1)) --format='%H%x09%s' "$range")
count=$(printf '%s' "$log" | grep -c . || true)
if [ "$count" -eq 0 ]; then
  echo "No new commits (only merges)."
else
  # Subjects quoted as they are (German); "@name" is put in code so nobody gets notified.
  printf '%s\n' "$log" | sed -n "1,${max}p" | while IFS=$'\t' read -r h s; do
    s=$(printf '%s' "$s" | sed -e 's/</\&lt;/g' -e 's/@\([A-Za-z0-9_-]\{1,\}\)/`@\1`/g')
    echo "- [\`${h:0:7}\`]($url/commit/$h) $s"
  done
  if [ "$count" -gt "$max" ]; then
    total=$(git rev-list --no-merges --count "$range")
    if [ "$range" = "$sha" ]; then more="$url/commits/$sha"; else more="$url/compare/$prev...$sha"; fi
    echo "- … and $((total - max)) more: [all commits]($more)"
  fi
fi
echo
echo "Changelog: [CHANGELOG.md]($url/blob/main/CHANGELOG.md) · Licenses of bundled components: [THIRD_PARTY_NOTICES.md]($url/blob/$sha/THIRD_PARTY_NOTICES.md)"
