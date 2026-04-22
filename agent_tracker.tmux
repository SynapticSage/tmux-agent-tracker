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
# Status-format wiring — idempotent.
#
# Each time tmux sources the config, this script runs. Using `set -ag`
# unconditionally would re-append the `#(...)` call on every reload
# (2×, 3× badges in the status bar). Guard by reading the current
# value and skipping if our script is already referenced.
# ---------------------------------------------------------------------
wire_status_format() {
  local option="$1"
  local current
  current="$("$TMUX_BIN" show-option -gqv "$option" 2>/dev/null || true)"
  if [[ "$current" == *"$BADGE_SCRIPT"* ]]; then
    return 0
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
