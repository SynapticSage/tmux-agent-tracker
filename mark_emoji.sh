#!/usr/bin/env bash
# mark_emoji.sh — fzf-based emoji picker for pane marks.
#
# Invoked either from mark.sh (via Ctrl-E hand-off) or bound directly
# for a one-step emoji-only mark. Writes the picked glyph as the
# @agent-mark pane option.
#
# Source list resolution:
#   1. $PLUGIN_DIR/emoji_full.txt  (only if the user opted in via
#      install.sh --emoji, which downloads the full Unicode CLDR list)
#   2. $PLUGIN_DIR/emoji.txt       (always present, curated subset)
#
# The tmux option @agent-tracker-emoji-list can force one or the other
# ("full" / "basic"); defaults to auto-detect ("full" if present,
# falls back to basic).

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || echo /opt/homebrew/bin/tmux)}"

target="${1:-${TMUX_PANE:-$("$TMUX_BIN" display -p '#{pane_id}')}}"

command -v fzf >/dev/null 2>&1 || {
  echo "fzf not found — install fzf to use the emoji picker"
  echo "(falling back to character input)"
  sleep 2
  exec "$PLUGIN_DIR/mark.sh"
}

preference="$("$TMUX_BIN" show-option -gqv @agent-tracker-emoji-list 2>/dev/null || true)"
basic="$PLUGIN_DIR/emoji.txt"
full="$PLUGIN_DIR/emoji_full.txt"

case "$preference" in
  full)  list="$full" ;;
  basic) list="$basic" ;;
  *)     # auto: prefer full if present, else basic
    if [[ -f "$full" ]]; then list="$full"; else list="$basic"; fi
    ;;
esac

if [[ ! -f "$list" ]]; then
  echo "emoji list not found: $list" >&2
  echo "re-run install.sh --emoji to set it up" >&2
  exit 1
fi

# fzf over the list. Each line is "<glyph>\t<keywords>" — fzf
# matches against the whole line so typing a keyword filters
# correctly. --with-nth=1,2 keeps display clean; --delimiter keeps
# the glyph column discoverable.
picked=$(fzf --height=100% \
             --reverse \
             --prompt="emoji> " \
             --header="pick an emoji to mark pane $target (Esc to cancel)" \
             --delimiter=$'\t' \
             < "$list") || {
  echo "(canceled)"
  exit 0
}

# Take the first tab-separated field (the glyph itself). Handles
# the case where multi-codepoint emoji (like ⚠️ with VS-16) contain
# no whitespace inside but are followed by \t then keywords.
glyph="${picked%%$'\t'*}"

if [[ -z "$glyph" ]]; then
  echo "(empty selection, canceled)"
  exit 0
fi

"$TMUX_BIN" set-option -t "$target" -p @agent-mark "$glyph"
"$TMUX_BIN" refresh-client -S 2>/dev/null || true
echo "set: $glyph"
