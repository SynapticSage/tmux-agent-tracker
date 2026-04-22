#!/usr/bin/env bash
# Hot path for the per-window agent badge system.
#
# Invoked from tmux's window-status-format / window-status-current-format
# as `#(window_badge.sh #{window_id})`, so tmux calls it once per window
# on every status-bar redraw. MUST stay fast — it reads the cache,
# filters to panes in the given window, renders a badge string.
#
# Cache staleness triggers an async refresh under a non-blocking lock;
# the current render uses the stale cache and the next render picks up
# the fresh one. If the cache is missing entirely (first ever render,
# server just started), we refresh synchronously — this is the one slow
# path, and it happens at most once per tmux server lifetime.
#
# Usage: window_badge.sh <window_id>
#   window_id is tmux's @N form (passed by `#{window_id}` in a format).
# Env:
#   WINDOW_BADGE_TTL     cache TTL in seconds (default 5)
#
# tmux options read (all optional):
#   @window-badge-mode           "counts" (default) | "worst" | "off"
#   @window-badge-palette        "" (default — terminal named colors) |
#                                "fallback" (bg+fg color chips, theme-agnostic) |
#                                "onedark" / "catppuccin" (hint, currently
#                                identical to default — reserved for future
#                                per-theme tuning)

set -euo pipefail

window_id="${1:-}"
[[ -n "$window_id" ]] || { echo ""; exit 0; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_file="/tmp/tmux-window-badge-$(id -u).cache"
refresh="$script_dir/window_badge_refresh.sh"

# --- Config -----------------------------------------------------------
mode=$(tmux show-option -gqv "@window-badge-mode" 2>/dev/null || true)
[[ -z "$mode" ]] && mode="counts"
[[ "$mode" == "off" ]] && { echo ""; exit 0; }

ttl=$(tmux show-option -gqv "@window-badge-poll-interval" 2>/dev/null || true)
[[ -z "$ttl" ]] && ttl="${WINDOW_BADGE_TTL:-5}"

palette=$(tmux show-option -gqv "@window-badge-palette" 2>/dev/null || true)

# --- Cache maintenance -------------------------------------------------
# First-ever render: must synchronously populate the cache so the badge
# isn't empty on startup. Every subsequent stale render fires an async
# refresh and uses the stale cache this tick.
if [[ ! -f "$cache_file" ]]; then
  "$refresh" 2>/dev/null || true
else
  age=$(python3 -c "import os,time; print(int(time.time()-os.path.getmtime('$cache_file')))" 2>/dev/null || echo 0)
  if (( age > ttl )); then
    # Thundering-herd guard without flock (not shipped on macOS by
    # default). Bump the mtime first so other windows rendering in
    # this same tick see a "fresh" cache and skip their own refresh;
    # the one refresh we kick off atomically overwrites the file when
    # it's done. If the refresh crashes, the stale content sticks for
    # another TTL — acceptable, eventually self-healing.
    touch "$cache_file"
    ( "$refresh" ) &
    disown 2>/dev/null || true
  fi
fi

# --- Render ------------------------------------------------------------
panes=$(tmux list-panes -t "$window_id" -F '#{pane_id}' 2>/dev/null) || { echo ""; exit 0; }

PANES="$panes" BADGE_MODE="$mode" BADGE_PALETTE="${palette:-}" CACHE_FILE="$cache_file" python3 <<'PY'
import os

panes = set(os.environ.get("PANES", "").split())
mode = os.environ.get("BADGE_MODE", "counts")
palette = os.environ.get("BADGE_PALETTE", "")
cache_file = os.environ["CACHE_FILE"]

counts = {"needs-input": 0, "working": 0, "new": 0, "done": 0, "idle": 0}
ignored = 0

try:
    with open(cache_file) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            pane_id, state, ign = parts
            if pane_id not in panes:
                continue
            if ign == "y":
                ignored += 1
            elif state in counts:
                counts[state] += 1
except FileNotFoundError:
    pass

symbols = {
    "needs-input": "\u2328",      # ⌨   waiting for user
    "working":     "\u2699",      # ⚙   computing
    "new":         "\u2733",      # ✳   fresh session
    "done":        "\u2713",      # ✓   finished, unseen
    "idle":        "\U0001f4a4",  # 💤  at prompt, no work
}
# Per-state tmux style overrides. Unicode symbols inherit the
# window-status-style foreground (typically a muted gray on most
# themes) which makes them hard to read next to full-color emoji
# like 💤. Forcing fg here restores legibility and adds semantic
# color (yellow=attention, green=done, etc.). Named colors so it
# adapts to the user's terminal palette.
# Two palettes. The default (fg-only) inherits the status-bar background
# from whatever theme is active — fine on onedark/catppuccin/dracula,
# can wash out on default tmux green or light themes. The 'fallback'
# palette uses bg+fg chips so each badge is its own legible island
# regardless of background; opt-in via @window-badge-palette = fallback.
default_styles = {
    "needs-input": "fg=yellow,bold",
    "working":     "fg=cyan,bold",
    "new":         "fg=magenta,bold",
    "done":        "fg=green,bold",
    "idle":        "fg=brightwhite",     # 💤 is already colored; this
                                         # only reaches the digit next to it
}
fallback_styles = {
    "needs-input": "bg=yellow,fg=black,bold",
    "working":     "bg=cyan,fg=black,bold",
    "new":         "bg=magenta,fg=white,bold",
    "done":        "bg=green,fg=black,bold",
    "idle":        "bg=colour237,fg=brightwhite",
}
styles = fallback_styles if palette == "fallback" else default_styles
ignored_style = "fg=colour244" if palette != "fallback" else "bg=colour237,fg=colour244"

order = ["needs-input", "working", "new", "done", "idle"]

def paint(style, text):
    return f"#[{style}]{text}#[default]"

out = []
if mode == "worst":
    for s in order:
        if counts[s]:
            out.append(paint(styles[s], symbols[s]))
            break
else:  # "counts"
    for s in order:
        if counts[s]:
            out.append(paint(styles[s], f"{symbols[s]}{counts[s]}"))

if ignored:
    out.append(paint(ignored_style, f"\u2205{ignored}"))

print(" ".join(out))
PY
