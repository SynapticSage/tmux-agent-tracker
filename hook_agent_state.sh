#!/usr/bin/env bash
# Claude Code hook handler — writes per-pane agent state into a tmux
# global env var that window_badge_providers/10-claude-hooks.sh reads.
#
# Invoked from ~/.claude/settings.json hooks:
#   UserPromptSubmit  -> --state running
#   PermissionRequest -> --state needs-input
#   Stop              -> --state done
# (--state off unsets the var, useful for manual reset.)
#
# Env schema: TMUX_BADGE_PANE_<pane_id>_STATE=<state>
# Stays independent of tmux-agent-indicator's schema by design so the
# two systems can coexist or the plugin can be fully removed.

set -euo pipefail

state=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) state="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$state" ]]            || exit 0
[[ -n "${TMUX:-}" ]]         || exit 0
[[ -n "${TMUX_PANE:-}" ]]    || exit 0

# Claude Code hooks run with a minimal PATH, so `tmux` may not be
# resolvable via name. Try the common install locations in order.
# Override with TMUX_BIN=... in the environment if yours is elsewhere.
for candidate in "${TMUX_BIN:-}" /opt/homebrew/bin/tmux /usr/local/bin/tmux /opt/local/bin/tmux /usr/bin/tmux; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    TMUX_BIN="$candidate"
    break
  fi
done
[[ -x "${TMUX_BIN:-}" ]] || exit 0

key="TMUX_BADGE_PANE_${TMUX_PANE}_STATE"

if [[ "$state" == "off" ]]; then
  "$TMUX_BIN" set-environment -gu "$key" 2>/dev/null || true
else
  "$TMUX_BIN" set-environment -g "$key" "$state"
fi

# Push the state change to the status bar without waiting for the
# next status-interval tick. refresh-client -S repaints status only,
# cheap enough to do on every hook firing.
"$TMUX_BIN" refresh-client -S 2>/dev/null || true
