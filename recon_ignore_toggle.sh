#!/usr/bin/env bash
# recon_ignore_toggle.sh [--pane|--window]
#
# Toggle @recon-ignore at the given scope on the currently-focused
# target. Default: --pane.
#
#   --pane    silences one specific pane. Use when a window contains
#             multiple agents and you want to mute just one.
#   --window  silences every pane in the window at once via tmux's
#             standard inheritance chain (pane -> window -> session
#             -> global). Use when the whole window is something you
#             don't want to track right now.
#
# Both flags read the SCOPE-SPECIFIC value (not the inherited one),
# so flipping is predictable: a pane marked "on" flips off cleanly
# even when its parent window is also ignored. Inheritance still
# means un-ignoring a pane won't override a window-level mark —
# clear the parent via `prefix + e` or the `prefix + I` picker.
#
# For a picker UI covering session/window scope on a non-focused
# target, see recon_ignore_picker.sh (prefix + I).

set -euo pipefail

scope=pane
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane)   scope=pane;   shift ;;
    --window) scope=window; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

TMUX_BIN=/opt/homebrew/bin/tmux

case "$scope" in
  pane)
    target=$("$TMUX_BIN" display-message -p '#{pane_id}')
    label=$("$TMUX_BIN" display-message -p '#{session_name}:#{window_index}.#{pane_index}')
    state=$("$TMUX_BIN" show-options -pvt "$target" '@recon-ignore' 2>/dev/null || true)
    if [[ "$state" == "on" ]]; then
      "$TMUX_BIN" set-option -p -t "$target" -u '@recon-ignore'
      "$TMUX_BIN" display-message "recon: pane $label back in cycle"
    else
      "$TMUX_BIN" set-option -p -t "$target" '@recon-ignore' 'on'
      "$TMUX_BIN" display-message "recon: pane $label ignored"
    fi
    ;;
  window)
    target=$("$TMUX_BIN" display-message -p '#{session_name}:#{window_index}')
    window_name=$("$TMUX_BIN" display-message -p '#W')
    state=$("$TMUX_BIN" show-options -wvt "$target" '@recon-ignore' 2>/dev/null || true)
    if [[ "$state" == "on" ]]; then
      "$TMUX_BIN" set-option -w -t "$target" -u '@recon-ignore'
      "$TMUX_BIN" display-message "recon: window $target ($window_name) back in cycle"
    else
      "$TMUX_BIN" set-option -w -t "$target" '@recon-ignore' 'on'
      "$TMUX_BIN" display-message "recon: window $target ($window_name) ignored (all panes muted)"
    fi
    ;;
esac
