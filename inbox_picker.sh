#!/usr/bin/env bash
# inbox_picker.sh — fzf popup over inbox.sh; jumps tmux to the selected
# pane on Enter. Esc cancels.
#
# Bound from agent_tracker.tmux via `display-popup -E`. Reads a
# fresh inbox each invocation so transitions (a Claude finishing,
# a defer toggle) are reflected immediately.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}"

command -v fzf >/dev/null 2>&1 || {
  echo "fzf not found — install fzf to use the inbox picker"
  sleep 2
  exit 1
}

# Optional --include-ignored passthrough.
INBOX_FLAGS=()
[[ "${1:-}" == "--include-ignored" ]] && INBOX_FLAGS+=(--include-ignored)

# Render rows for fzf. inbox.sh emits TSV columns:
#   1=eff_priority 2=pane_id 3=target 4=state 5=mark 6=visibility 7=window_name
# We compose a human row of: <state-glyph> <prio?> <[mark]?> <target>  <window-name>
# while keeping pane_id as the first field (hidden) for the jump.
rows=$("$PLUGIN_DIR/inbox.sh" "${INBOX_FLAGS[@]}" | awk -F'\t' '
function glyph(state) {
  if (state == "needs-input") return "⌨"
  if (state == "working")     return "⚙"
  if (state == "new")         return "✳"
  if (state == "done")        return "✓"
  if (state == "idle")        return "💤"
  if (state == "none")        return " "
  return "?"
}
{
  pane_id   = $2
  target    = $3
  state     = $4
  mark      = $5
  vis       = $6
  win       = $7
  prio_str  = ($1 != "100") ? "p" $1 " " : ""
  mark_str  = (mark != "")  ? "[" mark "] " : ""
  vis_str   = (vis == "deferred") ? "⏸ " : (vis == "ignored" ? "∅ " : "")
  display   = sprintf("%s\t%s%s%s%s  %-22s  %s", pane_id, vis_str, glyph(state), " ", prio_str mark_str, target, win)
  print display
}')

if [[ -z "$rows" ]]; then
  echo "(inbox is empty — no agent panes tracked)"
  sleep 1
  exit 0
fi

# fzf reads tab-separated; --with-nth=2.. hides the first column
# (pane_id) from display, but keeps it for selection. --print-query
# off; we just want the picked line.
selected=$(printf '%s\n' "$rows" | fzf \
  --height=100% \
  --reverse \
  --prompt="inbox> " \
  --header="pick a pane to jump to (Esc to cancel)" \
  --delimiter=$'\t' \
  --with-nth=2..) || {
  exit 0
}

[[ -z "$selected" ]] && exit 0

# The first tab-separated column is the pane_id.
pane_id="${selected%%$'\t'*}"

# Jump: switch-client to the session, select-window, select-pane.
target="$("$TMUX_BIN" display -p -t "$pane_id" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)"
if [[ -z "$target" ]]; then
  echo "pane $pane_id no longer exists"
  sleep 1
  exit 1
fi

session="${target%%:*}"
"$TMUX_BIN" switch-client -t "$session" 2>/dev/null || true
"$TMUX_BIN" select-window -t "$target"
"$TMUX_BIN" select-pane -t "$pane_id"
