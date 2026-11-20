#!/usr/bin/env bash
# Carries Barcraft's changes to Omarchy's bar forward onto a newer Omarchy.
#
# Bar.qml and BarModel.js are Omarchy's own bar plugin with Barcraft's changes
# on top. upstream/<file>.orig holds the Omarchy version they were last synced
# with, so an Omarchy update is a three-way merge: what Barcraft changed
# (base -> ours) applied to what Omarchy shipped since (base -> theirs).
#
#   scripts/sync-upstream.sh            merge Omarchy's current bar in
#   scripts/sync-upstream.sh --check    only say whether Omarchy's bar moved
#                                       (exit 1 if it did; for CI or a hook)
#   scripts/sync-upstream.sh --mark-synced
#                                       after resolving conflicts by hand,
#                                       record Omarchy's current bar as base
set -euo pipefail

cd "$(dirname "$0")/.."

upstream_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/bar"
files=(Bar.qml BarModel.js)
mode="${1:-merge}"

omarchy_version() {
  pacman -Q omarchy omarchy-dev 2>/dev/null | awk 'NR == 1 { print $2 }' || true
}

[[ -d $upstream_dir ]] || { echo "No Omarchy bar at $upstream_dir (set OMARCHY_PATH)" >&2; exit 2; }
command -v git >/dev/null || { echo "git is needed for the merge" >&2; exit 2; }

case $mode in
  --check)
    moved=0
    for f in "${files[@]}"; do
      if ! cmp -s "upstream/$f.orig" "$upstream_dir/$f"; then
        echo "Omarchy changed $f since the last sync ($(cat upstream/VERSION 2>/dev/null || echo unknown))"
        moved=1
      fi
    done
    (( moved )) || echo "In step with Omarchy $(cat upstream/VERSION 2>/dev/null || echo)"
    exit $moved
    ;;

  --mark-synced)
    if grep -l '^<<<<<<< \|^>>>>>>> ' "${files[@]}" >/dev/null 2>&1; then
      echo "Conflict markers are still in: $(grep -l '^<<<<<<< \|^>>>>>>> ' "${files[@]}" | tr '\n' ' ')" >&2
      exit 1
    fi
    for f in "${files[@]}"; do cp "$upstream_dir/$f" "upstream/$f.orig"; done
    omarchy_version > upstream/VERSION
    echo "Recorded Omarchy $(cat upstream/VERSION) as the sync base"
    ;;

  merge)
    conflicts=0
    for f in "${files[@]}"; do
      if cmp -s "upstream/$f.orig" "$upstream_dir/$f"; then
        echo "$f: Omarchy unchanged"
        continue
      fi
      set +e
      git merge-file -L barcraft -L "last sync" -L "omarchy $(omarchy_version)" \
        "$f" "upstream/$f.orig" "$upstream_dir/$f"
      result=$?
      set -e
      if (( result == 0 )); then
        cp "$upstream_dir/$f" "upstream/$f.orig"
        echo "$f: merged Omarchy's changes cleanly"
      elif (( result > 0 )); then
        conflicts=$((conflicts + result))
        echo "$f: $result conflict(s) left marked in the file"
      else
        echo "$f: merge failed" >&2
        exit 2
      fi
    done
    if (( conflicts > 0 )); then
      echo "Resolve the conflicts, check with 'omarchy agent look plugin .', then run $0 --mark-synced"
      exit 1
    fi
    omarchy_version > upstream/VERSION
    echo "In step with Omarchy $(cat upstream/VERSION). Restart the shell and look at the bar."
    ;;

  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
