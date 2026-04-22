#!/usr/bin/env bash
# recon_cycle.sh [--waiting-only]
#
# Cycle to the next recon-tracked Claude session, skipping panes marked
# with the @recon-ignore tmux option.
#
# Default mode: rotation includes Idle AND waiting-for-input sessions,
#   sorted waiting-first. So if anything is waiting you land there on
#   the first press — identical to `recon next` as a sub-case.
#
# --waiting-only: restrict rotation to waiting-for-input agents only
#   (status is neither Idle nor Working). Shows a "no agents waiting"
#   status-bar message if the filtered list is empty.
#
# Ignore filter: any pane where `@recon-ignore` is set to "on" is removed
# from the candidate list in both modes. Toggle the mark per-pane with
# recon_ignore_toggle.sh.

set -euo pipefail

TMUX_BIN=/opt/homebrew/bin/tmux

waiting_only=0
if [[ "${1:-}" == "--waiting-only" ]]; then
  waiting_only=1
fi

current=$("$TMUX_BIN" display-message -p '#{session_name}:#{window_index}.#{pane_index}')

# Build the ignore set: one pane_target per line (session:window.pane).
# Use '|' as the list-panes field delimiter so empty @recon-ignore values
# don't collapse fields together under awk's default whitespace parsing.
ignored=$(
  "$TMUX_BIN" list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{@recon-ignore}' \
    | awk -F'|' '$2=="on"{print $1}'
)

# Filter + sort candidates in Python.
mapfile -t targets < <(
  recon json | IGNORED="$ignored" WAITING_ONLY="$waiting_only" python3 -c '
import sys, json, os
ignored = set(os.environ.get("IGNORED", "").split())
waiting_only = os.environ.get("WAITING_ONLY") == "1"
d = json.load(sys.stdin)
idle = {"Idle"}
busy = {"Working"}
if waiting_only:
    picks = [s for s in d["sessions"] if s["status"] not in busy and s["status"] not in idle]
else:
    picks = [s for s in d["sessions"] if s["status"] not in busy]
picks = [s for s in picks if s["pane_target"] not in ignored]
picks.sort(key=lambda s: (1 if s["status"] in idle else 0, s["index"]))
for s in picks:
    print(s["pane_target"])
'
)

if [[ ${#targets[@]} -eq 0 ]]; then
  if [[ $waiting_only -eq 1 ]]; then
    "$TMUX_BIN" display-message "recon: no agents waiting for input"
  else
    "$TMUX_BIN" display-message "recon: no idle or waiting agents"
  fi
  exit 0
fi

# Locate current pane in the rotation; advance with wrap. If current
# isn't in the list (user is on a non-Claude or ignored pane), jump to
# the first candidate.
next_idx=0
for i in "${!targets[@]}"; do
  if [[ "${targets[$i]}" == "$current" ]]; then
    next_idx=$(( (i + 1) % ${#targets[@]} ))
    break
  fi
done

target="${targets[$next_idx]}"
window="${target%.*}"  # strip trailing .pane_index for switch-client

"$TMUX_BIN" switch-client -t "$window"
"$TMUX_BIN" select-pane -t "$target"
