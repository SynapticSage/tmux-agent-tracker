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
MARK_SCRIPT="$PLUGIN_DIR/mark.sh"
MARK_EMOJI_SCRIPT="$PLUGIN_DIR/mark_emoji.sh"
RECON_CYCLE_SCRIPT="$PLUGIN_DIR/recon_cycle.sh"
RECON_IGNORE_TOGGLE_SCRIPT="$PLUGIN_DIR/recon_ignore_toggle.sh"
RECON_IGNORE_PICKER_SCRIPT="$PLUGIN_DIR/recon_ignore_picker.sh"

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
# Key bindings for per-pane marks.
#
# Defaults:
#   prefix + m   -> mark.sh popup (type 1-6 chars, Ctrl-E for emoji)
#   prefix + M   -> mark_emoji.sh direct (skip the char prompt)
#
# Override via:
#   set -g @agent-tracker-mark-key       'm'
#   set -g @agent-tracker-mark-emoji-key 'M'
#   set -g @agent-tracker-mark-key       ''   # disable binding
#
# Idempotent — binding to the same key twice is fine, tmux replaces
# the previous binding silently. No need to track prior binds.
# ---------------------------------------------------------------------
bind_popup() {
  local key="$1"
  local script="$2"
  [[ -z "$key" ]] && return 0
  "$TMUX_BIN" bind-key "$key" display-popup -E -w 60 -h 14 "$script"
}

mark_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-mark-key" 2>/dev/null || true)"
[[ -z "$mark_key" ]] && mark_key="m"
bind_popup "$mark_key" "$MARK_SCRIPT"

mark_emoji_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-mark-emoji-key" 2>/dev/null || true)"
[[ -z "$mark_emoji_key" ]] && mark_emoji_key="M"
bind_popup "$mark_emoji_key" "$MARK_EMOJI_SCRIPT"

# ---------------------------------------------------------------------
# Key bindings for recon integration.
#
# Recon (https://github.com/gavraz/recon) is the upstream Rust TUI
# that enumerates Claude sessions across the tmux server. These
# helpers provide keyboard UX around its data:
#
#   prefix + g   -> cycle to next non-Working agent (Idle or waiting)
#   prefix + C-g -> cycle only to agents waiting for input
#   prefix + i   -> toggle @recon-ignore on the focused pane
#   prefix + e   -> toggle @recon-ignore on the focused window
#   prefix + I   -> fzf popup for ignoring/unignoring session or window
#
# The @recon-ignore option is also read by 30-tmux-ignore.sh, so
# muting a pane/window/session correctly routes into the ∅N bucket
# in the badge. Toggles and badge logic are two halves of one UX.
#
# Each binding is opt-out via the matching option set to empty:
#   set -g @agent-tracker-recon-cycle-key ''
# ---------------------------------------------------------------------
bind_run() {
  local key="$1" cmd="$2"
  [[ -z "$key" ]] && return 0
  "$TMUX_BIN" bind-key "$key" run-shell "$cmd"
}

bind_popup_full() {
  local key="$1" cmd="$2"
  [[ -z "$key" ]] && return 0
  "$TMUX_BIN" bind-key "$key" display-popup -w 85% -h 75% -E "$cmd"
}

cycle_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-recon-cycle-key" 2>/dev/null || true)"
[[ -z "$cycle_key" ]] && cycle_key="g"
bind_run "$cycle_key" "$RECON_CYCLE_SCRIPT"

cycle_wait_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-recon-cycle-waiting-key" 2>/dev/null || true)"
[[ -z "$cycle_wait_key" ]] && cycle_wait_key="C-g"
bind_run "$cycle_wait_key" "$RECON_CYCLE_SCRIPT --waiting-only"

ignore_pane_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-ignore-pane-key" 2>/dev/null || true)"
[[ -z "$ignore_pane_key" ]] && ignore_pane_key="i"
bind_run "$ignore_pane_key" "$RECON_IGNORE_TOGGLE_SCRIPT --pane"

ignore_window_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-ignore-window-key" 2>/dev/null || true)"
[[ -z "$ignore_window_key" ]] && ignore_window_key="e"
bind_run "$ignore_window_key" "$RECON_IGNORE_TOGGLE_SCRIPT --window"

ignore_picker_key="$("$TMUX_BIN" show-option -gqv "@agent-tracker-ignore-picker-key" 2>/dev/null || true)"
[[ -z "$ignore_picker_key" ]] && ignore_picker_key="I"
bind_popup_full "$ignore_picker_key" "$RECON_IGNORE_PICKER_SCRIPT"

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
