#!/usr/bin/env bash
# defer_toggle.sh — flip @agent-deferred on the focused pane or window.
#
# Mirror of recon_ignore_toggle.sh's pattern, but for the deferred
# tier (visible in inbox, excluded from badge state-counts and
# from cycling) rather than the ignored tier (rendered as ∅, hidden
# from inbox by default).
#
# Usage:
#   defer_toggle.sh --pane     toggle on the current pane only
#   defer_toggle.sh --window   toggle on the current window
#                              (cascades to every pane via tmux's
#                              standard pane→window→session→global
#                              option inheritance chain)

set -euo pipefail

TMUX_BIN="${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}"

scope=""
case "${1:-}" in
  --pane)   scope=pane ;;
  --window) scope=window ;;
  *)
    echo "defer_toggle.sh: required: --pane | --window" >&2
    exit 2
    ;;
esac

# Read current value at the scope we're toggling. show-options scopes:
#   -p = pane, -w = window, (none) = session, -g = global.
# We toggle at the same scope we read, so window-scoped users don't
# accidentally promote to a pane-level override.
current=""
target_id=""
target_label=""
if [[ "$scope" == "pane" ]]; then
  target_id=$("$TMUX_BIN" display-message -p '#{pane_id}')
  current=$("$TMUX_BIN" show-options -p -t "$target_id" -qv "@agent-deferred" 2>/dev/null || true)
  target_label="pane $target_id"
else
  target_id=$("$TMUX_BIN" display-message -p '#{session_name}:#{window_index}')
  current=$("$TMUX_BIN" show-options -w -t "$target_id" -qv "@agent-deferred" 2>/dev/null || true)
  target_label="window $target_id"
fi

# Toggle: any non-"on" → "on" → unset.
if [[ "$current" == "on" ]]; then
  if [[ "$scope" == "pane" ]]; then
    "$TMUX_BIN" set-option -p -t "$target_id" -u "@agent-deferred"
  else
    "$TMUX_BIN" set-option -w -t "$target_id" -u "@agent-deferred"
  fi
  "$TMUX_BIN" display-message "deferred OFF on $target_label"
else
  if [[ "$scope" == "pane" ]]; then
    "$TMUX_BIN" set-option -p -t "$target_id" "@agent-deferred" "on"
  else
    "$TMUX_BIN" set-option -w -t "$target_id" "@agent-deferred" "on"
  fi
  "$TMUX_BIN" display-message "deferred ON on $target_label"
fi

# Repaint status bar so the new ⏸ glyph appears immediately.
"$TMUX_BIN" refresh-client -S 2>/dev/null || true
