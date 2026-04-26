#!/usr/bin/env bash
# metadata.sh — shared helper for resolving per-pane user-set tmux options
# via the standard inheritance chain (pane → window → session → global).
#
# Sourced by window_badge.sh, inbox.sh, defer_toggle.sh — any surface
# that consults @agent-mark / @agent-priority / @agent-deferred /
# @recon-ignore. Per Codex round-2 sign-off, having one resolver
# prevents drift between surfaces.
#
# This file MUST be sourced, not exec'd — its functions modify the
# caller's variables (PANE_MARK, PANE_PRIORITY, etc.) which is the
# bash idiom for returning multiple values cheaply.
#
# IMPORTANT: tmux calls go through $METADATA_TMUX_BIN, not bare `tmux`.
# Reason: when this file is sourced from interactive zsh (e.g. during
# manual testing), oh-my-zsh's tmux plugin aliases bare `tmux` to a
# function that swallows args and fails silently. The absolute-path
# fallback makes the resolver work in every call path.

METADATA_TMUX_BIN="${TMUX_BIN:-${METADATA_TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}}"

# ---------------------------------------------------------------------
# resolve_pane_option <pane_id> <option_name>
#
# Walks the tmux scope chain manually: pane → window → session →
# global. Returns the first set non-empty value via stdout.
#
# Why an explicit walk: `tmux show-options -t <pane> -qv @opt` without
# a scope flag reads SESSION-scope options, not pane. Passing `-p`
# restricts to pane scope only. There's no built-in "walk and return
# first set" mode, so we synthesize it. The cost is 1–4 extra
# show-options calls per resolve, all cheap (<1ms each).
# ---------------------------------------------------------------------
resolve_pane_option() {
  local pane="$1" opt="$2" val

  val=$("$METADATA_TMUX_BIN" show-options -p -t "$pane" -qv "$opt" 2>/dev/null)
  if [[ -n "$val" ]]; then printf '%s' "$val"; return; fi

  val=$("$METADATA_TMUX_BIN" show-options -w -t "$pane" -qv "$opt" 2>/dev/null)
  if [[ -n "$val" ]]; then printf '%s' "$val"; return; fi

  val=$("$METADATA_TMUX_BIN" show-options -t "$pane" -qv "$opt" 2>/dev/null)
  if [[ -n "$val" ]]; then printf '%s' "$val"; return; fi

  val=$("$METADATA_TMUX_BIN" show-options -gqv "$opt" 2>/dev/null)
  printf '%s' "$val"
}

# ---------------------------------------------------------------------
# resolve_pane_metadata <pane_id>
#
# Resolves all four agent-tracker user-options at once and assigns
# them to PANE_MARK / PANE_PRIORITY / PANE_DEFERRED / PANE_IGNORED in
# the caller's scope. Priority defaults to 100 (neutral) when unset
# or non-integer. The others default to empty string.
# ---------------------------------------------------------------------
resolve_pane_metadata() {
  local pane="$1" prio
  PANE_MARK=$(resolve_pane_option "$pane" "@agent-mark")
  PANE_DEFERRED=$(resolve_pane_option "$pane" "@agent-deferred")
  PANE_IGNORED=$(resolve_pane_option "$pane" "@recon-ignore")
  prio=$(resolve_pane_option "$pane" "@agent-priority")
  if [[ "$prio" =~ ^[0-9]+$ ]]; then
    PANE_PRIORITY="$prio"
  else
    PANE_PRIORITY=100
  fi
}

# ---------------------------------------------------------------------
# pane_visibility <deferred> <ignored>
#
# Pure function: maps the two boolean-ish flags to the visibility
# tier name used everywhere else (active / deferred / ignored).
# ignored takes precedence over deferred — a pane explicitly told
# "don't show me at all" stays out even if also deferred.
# ---------------------------------------------------------------------
pane_visibility() {
  local deferred="$1" ignored="$2"
  if [[ "$ignored" == "on" ]]; then
    echo "ignored"
  elif [[ "$deferred" == "on" ]]; then
    echo "deferred"
  else
    echo "active"
  fi
}
