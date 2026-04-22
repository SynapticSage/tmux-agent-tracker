#!/usr/bin/env bash
# Cold path for the per-window agent badge system.
#
# Runs every provider in window_badge_providers/, merges their TSV
# observations by pane_id, and writes the result atomically to the
# cache file that window_badge.sh (the hot path) reads.
#
# Merge rule:
#   - For each pane_id, keep the highest-priority state observed.
#     Priority (high -> low): needs-input > working > new > done > idle > none
#   - OR together the ignored flag: any "y" wins.
#
# This script is safe to run concurrently — writes go to a tempfile and
# atomic-rename, so a concurrent reader either sees the old cache or
# the new one, never a partial file. The callers still serialize via
# flock to avoid wasting CPU on simultaneous refreshes.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
providers_dir="$script_dir/window_badge_providers"
cache_file="/tmp/tmux-window-badge-$(id -u).cache"
cache_tmp="$(mktemp "${cache_file}.XXXXXX")"
trap 'rm -f "$cache_tmp"' EXIT

collect() {
  local provider
  for provider in "$providers_dir"/*.sh; do
    [[ -x "$provider" ]] || continue
    # Providers are responsible for failing silently. If one does
    # explode, swallow its stderr/exit so one bad provider can't
    # starve the rest.
    "$provider" 2>/dev/null || true
  done
}

collect | python3 -c '
import sys

priority = {
    "needs-input": 6,
    "working":     5,
    "new":         4,
    "done":        3,
    "idle":        2,
    "none":        0,
}

best = {}
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) != 3:
        continue
    pane_id, state, ignored = parts
    if state not in priority:
        continue
    is_ignored = (ignored == "y")
    if pane_id not in best:
        best[pane_id] = (state, is_ignored)
    else:
        cur_state, cur_ign = best[pane_id]
        new_state = state if priority[state] > priority[cur_state] else cur_state
        new_ign = is_ignored or cur_ign
        best[pane_id] = (new_state, new_ign)

for pane_id in sorted(best):
    state, ign = best[pane_id]
    flag = "y" if ign else "n"
    print(f"{pane_id}\t{state}\t{flag}")
' > "$cache_tmp"

mv "$cache_tmp" "$cache_file"
trap - EXIT
