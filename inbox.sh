#!/usr/bin/env bash
# inbox.sh — emit a deterministically-sorted list of agent panes.
#
# Architecture: cache + tmux options only. Does NOT call recon json or
# any provider script — that would create a second truth source. The
# cache is the integration point for observed agent state; tmux options
# are the user-controlled overlay.
#
# Output: TSV, one row per agent pane, columns:
#   <eff_priority>\t<pane_id>\t<target>\t<state>\t<mark>\t<visibility>\t<window_name>
#
#   eff_priority  integer; lower = higher priority; default 100
#   pane_id       %N (tmux's stable pane id)
#   target        session:window_idx.pane_idx (for tmux switch-client)
#   state         needs-input|done|new|idle|working|none
#   mark          user-set @agent-mark or empty
#   visibility    active|deferred|ignored
#   window_name   for display in pickers
#
# Sort order: (visibility_rank, eff_priority, state_priority, session,
# window, pane). Ignored panes excluded by default.
#
# Flags:
#   --include-ignored      also emit panes where visibility=ignored
#   --only-state=<state>   keep only rows whose state matches
#                          (used by recon_cycle.sh's --waiting-only)
#   --exclude-pane=<id>    omit this pane (used by inbox_next.sh
#                          to skip the current pane on cycle)
#   --sort-stdin           skip collection; read raw rows from stdin,
#                          sort, write to stdout. Used by tests to
#                          exercise the sort logic in isolation.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sort logic is a pure data transformation. Kept in its own function
# so tests can pipe synthetic rows in and verify ordering without
# needing a tmux server.
sort_rows() {
  # python3 -c (not heredoc) so stdin stays connected for sys.stdin.
  python3 -c '
import sys

# Lower priority value = surfaces first. Order chosen so the inbox
# top-down is "what to act on next": needs-input is most urgent;
# done is unread results worth acknowledging; new is freshly spawned
# (transient, will resolve to one of the others); idle is at-prompt
# but uninvolved; working is computing (least useful to interrupt);
# none is a marked pane with no observed state yet.
state_rank = {"needs-input": 0, "done": 1, "new": 2, "idle": 3,
              "working": 4, "none": 5}
visibility_rank = {"active": 0, "deferred": 1, "ignored": 2}

rows = []
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) != 7:
        continue
    eff_prio_str, pane_id, target, state, mark, visibility, window_name = parts
    try:
        eff_prio = int(eff_prio_str)
    except ValueError:
        eff_prio = 100
    rows.append((eff_prio, pane_id, target, state, mark, visibility, window_name))

def key(row):
    eff_prio, pane_id, target, state, mark, visibility, window_name = row
    try:
        session, rest = target.rsplit(":", 1)
        win_str, pane_str = rest.split(".")
        win = int(win_str)
        pane = int(pane_str)
    except ValueError:
        session, win, pane = target, 99999, 99999
    return (
        visibility_rank.get(visibility, 9),
        eff_prio,
        state_rank.get(state, 9),
        session,
        win,
        pane,
    )

rows.sort(key=key)
for r in rows:
    print("\t".join(str(x) for x in r))
'
}

# Sort-only mode for tests.
if [[ "${1:-}" == "--sort-stdin" ]]; then
  sort_rows
  exit 0
fi

# ---------------------------------------------------------------------
# Full pipeline: collect rows from cache + tmux, then sort.
# ---------------------------------------------------------------------

# shellcheck source=metadata.sh
source "$script_dir/metadata.sh"

include_ignored=0
only_state=""
exclude_pane=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-ignored)  include_ignored=1; shift ;;
    --only-state=*)     only_state="${1#*=}"; shift ;;
    --exclude-pane=*)   exclude_pane="${1#*=}"; shift ;;
    *) echo "inbox.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

cache_file="/tmp/tmux-window-badge-$(id -u).cache"

# Collect cache lines into bash associative arrays so we can join
# against tmux list-panes without re-reading the file per pane.
declare -A cache_state cache_ignored
if [[ -f "$cache_file" ]]; then
  while IFS=$'\t' read -r pane_id state ignored; do
    [[ -z "$pane_id" ]] && continue
    cache_state[$pane_id]="$state"
    cache_ignored[$pane_id]="$ignored"
  done < "$cache_file"
fi

# Iterate every pane on the tmux server, compose one TSV row per
# pane that passes the filters, then pipe to sort_rows.
collect_rows() {
  tmux list-panes -a -F '#{pane_id}|#{session_name}|#{window_index}|#{pane_index}|#{window_name}' 2>/dev/null \
  | while IFS='|' read -r pane_id session window_idx pane_idx window_name; do
      [[ -z "$pane_id" ]] && continue
      [[ "$pane_id" == "$exclude_pane" ]] && continue

      local state="${cache_state[$pane_id]:-}"
      local cache_ign="${cache_ignored[$pane_id]:-n}"

      # Resolve user options via inheritance helper.
      resolve_pane_metadata "$pane_id"

      # Visibility logic: cache-side ignored OR user-side @recon-ignore
      # both map to the ignored tier. The cache provider 30-tmux-ignore.sh
      # already reads @recon-ignore, but we re-check here so the inbox
      # picker reflects user changes immediately, before the next cache
      # refresh.
      local visibility
      if [[ "$cache_ign" == "y" || "$PANE_IGNORED" == "on" ]]; then
        visibility="ignored"
      elif [[ "$PANE_DEFERRED" == "on" ]]; then
        visibility="deferred"
      else
        visibility="active"
      fi

      if [[ "$visibility" == "ignored" ]] && (( include_ignored == 0 )); then
        continue
      fi

      # An "agent pane" for inbox purposes is one that EITHER has an
      # observed state (some provider reported on it) OR has a mark
      # (user explicitly tagged it for tracking). Plain shell panes
      # without either are skipped — the inbox is for tracked work.
      if [[ -z "$state" && -z "$PANE_MARK" ]]; then
        continue
      fi

      # State filter (used by --only-state=needs-input from
      # recon_cycle.sh --waiting-only).
      if [[ -n "$only_state" && "$state" != "$only_state" ]]; then
        continue
      fi

      # Default state for marked-but-unobserved panes.
      [[ -z "$state" ]] && state="none"

      printf '%s\t%s\t%s:%s.%s\t%s\t%s\t%s\t%s\n' \
        "$PANE_PRIORITY" "$pane_id" "$session" "$window_idx" "$pane_idx" \
        "$state" "$PANE_MARK" "$visibility" "$window_name"
    done
}

collect_rows | sort_rows
