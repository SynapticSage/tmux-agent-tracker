#!/usr/bin/env bash
# Interactive picker to toggle @recon-ignore at session or window scope.
#
# Flat list: all sessions, then all windows. Enter toggles the ignore
# mark at the selected scope (session-scope or window-scope), Esc exits.
# After each toggle the list redraws so state changes are visible.
#
# Inheritance note:
#   tmux resolves @recon-ignore through pane -> window -> session. A
#   window whose session is ignored will SHOW as [IGN] (effective state),
#   but toggling it only flips the window's own value — the session-level
#   mark still applies. To actually un-ignore an inherited window, toggle
#   its session. The picker header surfaces this.

set -euo pipefail

TMUX_BIN=/opt/homebrew/bin/tmux

# Per-scope toggle — uses `show-options -v` on the specific scope (not
# the inherited view) so we only flip the direct value at that scope.
toggle_session() {
  local sess=$1
  local curr
  curr=$("$TMUX_BIN" show-options -v -t "$sess" '@recon-ignore' 2>/dev/null || true)
  if [[ "$curr" == "on" ]]; then
    "$TMUX_BIN" set-option -t "$sess" -u '@recon-ignore'
  else
    "$TMUX_BIN" set-option -t "$sess" '@recon-ignore' 'on'
  fi
}

toggle_window() {
  local target=$1  # session:window_index
  local curr
  curr=$("$TMUX_BIN" show-options -wv -t "$target" '@recon-ignore' 2>/dev/null || true)
  if [[ "$curr" == "on" ]]; then
    "$TMUX_BIN" set-option -w -t "$target" -u '@recon-ignore'
  else
    "$TMUX_BIN" set-option -w -t "$target" '@recon-ignore' 'on'
  fi
}

# Build the picker list. Columns are tab-separated:
#   1) pretty label (shown in fzf)
#   2) scope tag (S or W)
#   3) target (session name, or session:window_index)
# fzf shows only column 1 via --with-nth=1.
render_list() {
  {
    "$TMUX_BIN" list-sessions -F \
      '#{?#{==:#{@recon-ignore},on},[IGN],     }  session:  #{session_name}	S	#{session_name}'
    "$TMUX_BIN" list-windows -a -F \
      '#{?#{==:#{@recon-ignore},on},[IGN],     }  window:   #{session_name}:#{window_index}  #{window_name}	W	#{session_name}:#{window_index}'
  }
}

HEADER="Enter: toggle at this scope   Esc: quit
Inherited ignores (session -> window) clear only at the session level."

while true; do
  selection=$(
    render_list | fzf \
      --with-nth=1 \
      --delimiter=$'\t' \
      --prompt="recon ignore > " \
      --header="$HEADER" \
      --height=100% \
      --no-sort \
      --reverse
  ) || break

  [[ -z "$selection" ]] && break

  scope=$(printf '%s' "$selection" | awk -F'\t' '{print $2}')
  target=$(printf '%s' "$selection" | awk -F'\t' '{print $3}')

  case "$scope" in
    S) toggle_session "$target" ;;
    W) toggle_window "$target" ;;
    *) "$TMUX_BIN" display-message "recon: unexpected scope '$scope'"; break ;;
  esac
done
