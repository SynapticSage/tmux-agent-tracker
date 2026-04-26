#!/usr/bin/env bash
# inbox_next.sh — headless. Jumps tmux to the first pane in inbox order
# that isn't the currently-active pane. Wraps from end of list.
#
# Use case: muscle-memory `prefix + g` (or whatever cycle key the user
# bound) walks through agents in priority order. recon_cycle.sh is a
# thin compat wrapper that exec's this with arg translation.
#
# Flags:
#   --waiting-only        only consider needs-input panes (translates
#                         to inbox.sh --only-state=needs-input)
#   --include-ignored     also consider ignored panes
#
# Status messages go through tmux display-message so users see them
# in the status bar, matching recon_cycle.sh's UX.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}"

INBOX_FLAGS=()
case "${1:-}" in
  --waiting-only)     INBOX_FLAGS+=(--only-state=needs-input) ;;
  --only-state=*)     INBOX_FLAGS+=("$1") ;;
  --include-ignored)  INBOX_FLAGS+=(--include-ignored) ;;
  "")                 ;;
  *)
    echo "inbox_next.sh: unknown flag: $1" >&2
    exit 2
    ;;
esac

current_pane=$("$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null || echo "")

# Get the first pane_id from inbox that isn't the current pane.
# If --exclude-pane removes the current one upstream, the first row
# is unambiguously the "next" one in priority order.
next_pane=$("$PLUGIN_DIR/inbox.sh" "${INBOX_FLAGS[@]}" --exclude-pane="$current_pane" 2>/dev/null \
  | head -n1 | awk -F'\t' '{print $2}')

if [[ -z "$next_pane" ]]; then
  if [[ " ${INBOX_FLAGS[*]} " == *"--only-state=needs-input"* ]]; then
    "$TMUX_BIN" display-message "no agents waiting for input"
  else
    "$TMUX_BIN" display-message "no other agent panes in inbox"
  fi
  exit 0
fi

# Jump: switch-client to the session, select-window, select-pane.
target="$("$TMUX_BIN" display -p -t "$next_pane" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)"
if [[ -z "$target" ]]; then
  "$TMUX_BIN" display-message "next pane $next_pane no longer exists"
  exit 1
fi

session="${target%%:*}"
"$TMUX_BIN" switch-client -t "$session" 2>/dev/null || true
"$TMUX_BIN" select-window -t "$target"
"$TMUX_BIN" select-pane -t "$next_pane"
