#!/usr/bin/env bash
# Adds CI builds to the version history afterwards: one GitHub release build-<run number> per run, on the
# run's commit, with the original CI artifact Player.ipa and the same notes as the CI job "history"
# (tools/release_notes.sh). integ runs become prereleases, main runs releases.
#
# Usage: tools/backfill_releases.sh [--publish] [RUN_ID ...]
#   Without --publish it only prints the notes (dry run). Without RUN_IDs it uses the integ builds
#   from before the version history existed (CI runs 144, 149, 156, 162).
#   Use it also when the CI job could not create a release (it prints the command with the run id).
# Needs: gh (logged in with write access to the repo), git, unzip. Run it from a checkout of the repo.
# If a run's artifact has expired (CI keeps it 14 days), the release is created without the IPA.
# Existing releases are left alone.
set -euo pipefail

repo=${GH_REPO:-haskoman-beep/tvos-player}
export GH_REPO=$repo
publish=0
if [ "${1:-}" = --publish ]; then publish=1; shift; fi
runs=("$@")
[ ${#runs[@]} -gt 0 ] || runs=(44967063603 45003758627 45007265314 45009922547)

here=$(cd "$(dirname "$0")" && pwd)
cd "$(git -C "$here" rev-parse --show-toplevel)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Oldest first, so each release finds the one before it as "previous release".
sorted=$(for id in "${runs[@]}"; do
  printf '%s\t%s\n' "$(gh run view "$id" --json number --jq .number)" "$id"
done | sort -n | cut -f2)

for id in $sorted; do
  IFS=$'\t' read -r num sha branch created event concl < <(gh run view "$id" \
    --json number,headSha,headBranch,createdAt,event,conclusion \
    --jq '[.number, .headSha, .headBranch, .createdAt, .event, .conclusion] | @tsv')
  tag="build-$num"
  echo "== $tag (run $id, $branch, ${sha:0:7}, $concl)"
  if [ "$concl" != success ]; then echo "   run did not succeed, skipped"; continue; fi
  case "$branch" in integ|main) ;; *) echo "   branch $branch has no releases, skipped"; continue ;; esac
  if gh release view "$tag" > /dev/null 2>&1; then echo "   $tag exists, skipped"; continue; fi

  git fetch -q --tags origin
  git cat-file -e "$sha^{commit}" 2>/dev/null || git fetch -q origin "$sha"

  # Previous release; if there is none, start after the previous successful CI build on the same branch.
  prev="" label=""
  probe=$(bash "$here/release_notes.sh" "$num" "$branch" "$sha" "$id" "$created" | grep -m1 '^### ' || true)
  if [[ "$probe" == "### Recent commits"* ]]; then
    read -r pnum psha < <(gh run list -b "$branch" -w build.yml -s success -L 100 --json number,headSha \
      --jq "[.[] | select(.number < $num)] | max_by(.number) | \"\(.number) \(.headSha)\"" 2>/dev/null || true)
    if [ -n "${psha:-}" ] && [ "$psha" != null ]; then
      git cat-file -e "$psha^{commit}" 2>/dev/null || git fetch -q origin "$psha"
      prev=$psha label="CI build $pnum (\`$branch\`, before the version history)"
    fi
  fi

  dir="$work/$id"; mkdir -p "$dir"
  no_ipa=0
  if gh run download "$id" -n Player-ipa -D "$dir" > /dev/null 2>&1 && [ -f "$dir/Player.ipa" ]; then
    bash "$here/check_ipa.sh" "$dir/Player.ipa" || { echo "   IPA check failed: nothing published, stopping"; exit 1; }
  else
    echo "   artifact Player-ipa not available (expired?): release without IPA"
    no_ipa=1
  fi

  note="Added to the version history afterwards (tools/backfill_releases.sh)."
  [ "$no_ipa" = 1 ] || note="$note The IPA is the original CI artifact of this run."
  NO_IPA=$no_ipa EVENT=$event EXTRA_NOTE=$note \
    bash "$here/release_notes.sh" "$num" "$branch" "$sha" "$id" "$created" "$prev" "$label" > "$dir/notes.md"

  if [ "$branch" = main ]; then flags=(--latest); title="Player build $num"
  else flags=(--prerelease --latest=false); title="Player build $num (integ)"; fi
  assets=(); [ "$no_ipa" = 1 ] || assets=("$dir/Player.ipa")

  if [ "$publish" = 1 ]; then
    gh release create "$tag" "${assets[@]}" --target "$sha" --title "$title" --notes-file "$dir/notes.md" "${flags[@]}"
  else
    echo "   dry run, would create: $title ${flags[*]} ${assets:+with Player.ipa}"
    sed 's/^/   | /' "$dir/notes.md"
  fi
done
