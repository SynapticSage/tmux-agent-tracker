#!/usr/bin/env bash
# tmux-agent-tracker — TPM entry point.
#
# Sourced by tmux (via TPM, or via `run-shell` on manual install) every
# time the tmux config is loaded. Its job is to wire the per-window
# agent badge into the status bar with sane defaults so that
# `set -g @plugin 'SynapticSage/tmux-agent-tracker'` is enough —
# no further .tmux.conf edits required.
#
# Does NOT touch ~/.claude/settings.json. TPM cannot edit that file,
# and lying about it would be worse than asking for one explicit
# user step. On first source, if the Claude hooks aren't registered,
# this script prints a one-line nudge with the command to run.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BADGE_SCRIPT="$PLUGIN_DIR/window_badge.sh"

# Resolve tmux. TPM sources this inside tmux, so `tmux` is on PATH,
# but pin to absolute for anything that forks without inheriting PATH.
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || true)}"
[[ -x "$TMUX_BIN" ]] || { echo "tmux-agent-tracker: tmux not found on PATH" >&2; exit 0; }

# ---------------------------------------------------------------------
# Status-format wiring — self-healing and idempotent.
#
# Runs on every source of the config. Writes end up as exactly one
# `#(…window_badge.sh…)` reference per option, pointing at THIS
# install's path, regardless of starting state. Handles:
#
#   1. First install (option has no badge ref) — append ours.
#   2. Repeat source (option already has ours) — scrub + re-append
#      is a no-op net change, but keeps the code path single.
#   3. Plugin moved (option has a badge ref at an old path, e.g.
#      from a dev clone now TPM-installed, or from legacy
#      install_badges.sh marker block) — scrub stale, append ours.
#   4. Running tmux server has stale in-memory wiring from a previous
#      session's config (tmux `source-file` re-applies `set` directives
#      but doesn't unset them; stale refs persist otherwise).
#
# The regex targets `#(…window_badge.sh…)` specifically. Using
# `[^)]*` stops each match from crossing into other `#(…)` commands
# in the same format string — essential because theme plugins often
# embed their own `#(…)` commands next to ours.
# ---------------------------------------------------------------------
wire_status_format() {
  local option="$1"
  local current scrubbed
  current="$("$TMUX_BIN" show-option -gqv "$option" 2>/dev/null || true)"

  scrubbed=$(CUR="$current" python3 -c "
import os, re
print(re.sub(r' *#\\([^)]*window_badge\\.sh[^)]*\\)', '', os.environ['CUR']), end='')
")

  if [[ "$scrubbed" != "$current" ]]; then
    "$TMUX_BIN" set-option -g "$option" "$scrubbed"
  fi
  "$TMUX_BIN" set-option -ag "$option" " #($BADGE_SCRIPT #{window_id})"
}

wire_status_format window-status-format
wire_status_format window-status-current-format

# ---------------------------------------------------------------------
# First-source nudge for the Claude-hooks install step.
#
# The badge system still renders without hooks (recon + codex pollers
# cover the common case), but hook-driven updates are the ~10ms fast
# path that makes state changes feel instant. Nudge once, quietly.
# User can silence forever with:
#   tmux set-option -g @agent-tracker-silence-hook-nudge on
# ---------------------------------------------------------------------
nudge_hooks_if_missing() {
  local silence
  silence="$("$TMUX_BIN" show-option -gqv "@agent-tracker-silence-hook-nudge" 2>/dev/null || true)"
  [[ "$silence" == "on" ]] && return 0

  local settings="${HOME}/.claude/settings.json"
  [[ -f "$settings" ]] || return 0

  # Look for any hook command that references our hook_agent_state.sh.
  # grep is cheaper than spinning up python for one string check.
  if ! grep -Fq "$PLUGIN_DIR/hook_agent_state.sh" "$settings" 2>/dev/null; then
    "$TMUX_BIN" display-message \
      "tmux-agent-tracker: run '$PLUGIN_DIR/install.sh' to enable Claude hooks (or set @agent-tracker-silence-hook-nudge 'on')" \
      2>/dev/null || true
  fi
}

nudge_hooks_if_missing
