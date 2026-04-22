#!/usr/bin/env bash
# mark.sh — set, clear, or change the @agent-mark on the current pane.
#
# Invoked via `display-popup -E` from agent_tracker.tmux's key binding.
# Reads up to 6 characters of input with short inter-key timeouts so
# users can commit a short label (e.g. "AR") without filling the buffer.
#
# Control keys during input:
#   Esc       -> cancel, leave existing mark untouched
#   Enter     -> commit what's been typed so far (empty = clear)
#   Ctrl-U    -> erase what's been typed, start over
#   Ctrl-E    -> hand off to mark_emoji.sh for an fzf-based emoji pick
#   Backspace -> delete last char
#
# The mark itself is stored in tmux's per-pane option @agent-mark,
# which persists for the server lifetime. window_badge.sh reads it
# at render time and prepends it to that pane's state symbol.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}"
MAX_LEN=6

# Resolve the target pane. In a display-popup -E invocation, TMUX_PANE
# points at the pane the popup was opened from — that's the one the
# user wants to mark. Outside popups, fall back to the active pane.
target="${TMUX_PANE:-$("$TMUX_BIN" display -p '#{pane_id}')}"

current="$("$TMUX_BIN" show-options -t "$target" -pqv @agent-mark 2>/dev/null || true)"

echo "Set mark for pane $target"
if [[ -n "$current" ]]; then
  echo "current: [$current]"
fi
echo
echo "Type up to $MAX_LEN chars then Enter. Enter alone clears."
echo "Ctrl-E = emoji picker.  Ctrl-U = reset.  Esc = cancel."
echo
printf '> '

# ---------------------------------------------------------------------
# Input loop.
#
# Use `read -n1` per char (not a single `read -n$MAX_LEN`) so we can
# intercept Ctrl-E to hand off, react to Esc/Enter at any position,
# and echo chars as they're typed. After the first char we set a
# short timeout so quick-typers can stop early by just pausing; a
# trailing Enter commits immediately regardless.
# ---------------------------------------------------------------------
buf=""
first=1

while (( ${#buf} < MAX_LEN )); do
  if (( first )); then
    # First char: wait indefinitely. User may be deciding.
    IFS= read -rsn1 ch
    first=0
  else
    # Subsequent chars: 1.5s idle timeout. If the user pauses, we
    # treat that as commit — they typed what they wanted.
    if ! IFS= read -rsn1 -t 1.5 ch; then
      break
    fi
  fi

  # Esc — single 0x1b. Terminal escape sequences (arrow keys etc.)
  # start with Esc too, but we don't care about those: they'd just
  # treat the first byte as cancel, which is fine for a 6-char
  # alphanumeric input.
  if [[ "$ch" == $'\e' ]]; then
    echo
    echo "(canceled)"
    exit 0
  fi

  # Enter / newline — commit.
  if [[ "$ch" == $'\n' || "$ch" == $'\r' ]]; then
    break
  fi

  # Ctrl-E — hand off to emoji picker. exec so we don't return here.
  if [[ "$ch" == $'\x05' ]]; then
    echo
    exec "$PLUGIN_DIR/mark_emoji.sh" "$target"
  fi

  # Ctrl-U — reset the buffer.
  if [[ "$ch" == $'\x15' ]]; then
    # Backspace over what's been shown.
    if (( ${#buf} > 0 )); then
      printf '\b%.0s' $(seq 1 ${#buf})
      printf ' %.0s' $(seq 1 ${#buf})
      printf '\b%.0s' $(seq 1 ${#buf})
    fi
    buf=""
    first=1
    continue
  fi

  # Backspace (0x7f on most terminals, 0x08 on some).
  if [[ "$ch" == $'\x7f' || "$ch" == $'\x08' ]]; then
    if (( ${#buf} > 0 )); then
      buf="${buf%?}"
      printf '\b \b'
    fi
    continue
  fi

  # Reject control chars we didn't match above — they'd render weird.
  if [[ "$ch" < $' ' ]]; then
    continue
  fi

  buf+="$ch"
  printf '%s' "$ch"
done

echo
mark="$buf"

if [[ -z "$mark" ]]; then
  # Empty commit = clear the mark. `-u` unsets the option cleanly
  # so show-options returns nothing rather than an empty string,
  # which is what the renderer's emptiness check relies on.
  "$TMUX_BIN" set-option -t "$target" -pu @agent-mark 2>/dev/null || true
  echo "(cleared)"
else
  "$TMUX_BIN" set-option -t "$target" -p @agent-mark "$mark"
  echo "set: [$mark]"
fi

# Repaint the status bar immediately rather than waiting for the next
# status-interval tick. Same pattern used by hook_agent_state.sh.
"$TMUX_BIN" refresh-client -S 2>/dev/null || true
