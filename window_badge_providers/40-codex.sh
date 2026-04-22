#!/usr/bin/env bash
# Provider: OpenAI Codex sessions (polled, best-effort state)
#
# Codex lacks Claude Code's hook surface (no `UserPromptSubmit` /
# `Stop` equivalent), so state can only be inferred by observation:
#
#   1. Single `ps -ax -o tty,comm` call collects every TTY where
#      `codex` is the foreground command. One shell-out, not N.
#   2. Cross-reference against tmux pane_tty values to find which
#      panes host those processes.
#   3. For each codex pane, sample its recent visible output via
#      `tmux capture-pane -S -30` and look for braille-range
#      characters (a common TUI spinner convention) to upgrade
#      state from `idle` to `working`.
#
# State vocabulary is deliberately the same as the Claude-side
# providers (working / idle), collapsing both agents' observations
# into one set of counts. A future `@window-badge-split-by-agent`
# mode (noted in CLAUDE.md) would keep the states but prefix each
# count with an agent glyph to distinguish sources.
#
# Latency: polled on the badge cache's TTL (default 5s), so codex
# state lags by up to that interval. In mixed windows, Claude panes
# still update at hook speed (~10ms) — only codex contributes the
# slow signal.
#
# Conservative by design: pattern match is narrow (spinner
# characters only, no needs-input guesses) to avoid misleading
# "working" or "waiting" badges on idle panes. Refine patterns
# when real codex TUI samples are available.
#
# Emits TSV: <pane_id>\t<state>\t<ignored=n>

set -euo pipefail

command -v tmux >/dev/null 2>&1 || exit 0

# One-shot collection of TTYs running codex.
#
# NB: macOS BSD `ps -o comm=` reports the first 16 chars of the
# program PATH, not its basename — so a codex binary invoked as
# /opt/homebrew/Cellar/.../codex/codex shows up truncated to something
# like "/opt/homebrew/Ce". That makes `$2=="codex"` useless here.
# We use `-o command=` (full invocation line) and look for any
# space-separated field whose tail is "/codex" or the bare string
# "codex". Covers all four observed launch patterns:
#   codex -m ...              (on PATH)
#   /abs/path/to/codex -m ... (direct binary)
#   node /path/to/.bin/codex  (npm/npx wrapper)
#   /Cellar/.../codex/codex   (homebrew-vendored node module)
# and rejects arg-like fields such as "codex.txt", "@openai/codex@latest",
# or "codex-foo" that would otherwise trip a naïve substring grep.
codex_ttys=$(ps -ax -o tty= -o command= 2>/dev/null \
  | awk '
      {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /(^|\/)codex$/) {
            print "/dev/"$1
            next
          }
        }
      }
    ' \
  | sort -u)

# No codex running anywhere — provider exits with no output, merger
# picks up nothing, no-op for non-codex users.
[[ -z "$codex_ttys" ]] && exit 0

# For each tmux pane, decide if its tty is in the codex set.
tmux list-panes -a -F '#{pane_id}|#{pane_tty}' 2>/dev/null \
| while IFS='|' read -r pane_id tty; do
  [[ -z "$tty" ]] && continue

  # Exact-line fixed-string match — a substring match on tty names
  # like "/dev/ttys0" would also match "/dev/ttys01", "/dev/ttys02",
  # etc. -Fxq guards against that.
  if ! printf '%s\n' "$codex_ttys" | grep -Fxq "$tty"; then
    continue
  fi

  # Sample the last 30 lines of the pane's visible buffer + tail of
  # scrollback. If codex is rendering a braille-spinner frame right
  # now, it lands in this window.
  content=$(tmux capture-pane -t "$pane_id" -p -S -30 2>/dev/null || true)

  state="idle"
  # Only a small set of dots-spinner frames to keep the signal narrow.
  # Catching every braille char (U+2800..U+28FF) would risk matching
  # unrelated decorative UI glyphs.
  if printf '%s' "$content" | grep -q '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]'; then
    state="working"
  fi

  printf '%s\t%s\tn\n' "$pane_id" "$state"
done
