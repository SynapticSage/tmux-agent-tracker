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
#   @agent-tracker-mark-style    override for the per-pane mark styling.
#                                default: fg=brightcyan,bold (fallback palette:
#                                bg=colour24,fg=brightwhite,bold)
#
# Per-pane options read (not cached — queried at render time since
# show-options is fast and we want mark updates to appear instantly):
#   @agent-mark                  1-6 char label or single emoji glyph
#                                set by mark.sh / mark_emoji.sh

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

# Per-pane user metadata (mark + deferred). Resolved via the shared
# metadata.sh helper so window_badge.sh, inbox.sh, and any future
# surface walk the same inheritance chain. Codex round-2 sign-off
# called this consistency out as a non-blocker but worth doing.
# shellcheck source=metadata.sh
source "$script_dir/metadata.sh"

# Build TSV: <pane_id>\t<mark>\t<deferred> for panes in this window.
# Resolving 3 options × N panes via the shared helper costs roughly
# 3–12 show-options calls per pane (the inheritance walk), all cheap
# (<1ms each) — well within tmux's status-redraw budget.
metadata_rows=$(while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  resolve_pane_metadata "$p"
  # Emit the two we care about for badge rendering. Ignored is
  # already in the cache (provider 30-tmux-ignore.sh), priority
  # only matters for the inbox.
  printf '%s\t%s\t%s\n' "$p" "$PANE_MARK" "$PANE_DEFERRED"
done <<< "$panes") || metadata_rows=""

mark_style_override=$(tmux show-option -gqv "@agent-tracker-mark-style" 2>/dev/null || true)

PANES="$panes" METADATA="$metadata_rows" BADGE_MODE="$mode" BADGE_PALETTE="${palette:-}" MARK_STYLE_OVERRIDE="${mark_style_override:-}" CACHE_FILE="$cache_file" python3 <<'PY'
import os

panes = set(os.environ.get("PANES", "").split())
mode = os.environ.get("BADGE_MODE", "counts")
palette = os.environ.get("BADGE_PALETTE", "")
cache_file = os.environ["CACHE_FILE"]

# Per-pane user metadata. Dict pane_id -> {"mark": str, "deferred": bool}.
# Sourced from the metadata.sh helper at bash level (above) which
# walks the tmux scope-inheritance chain.
metadata = {}
for line in os.environ.get("METADATA", "").splitlines():
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        continue
    pane_id, mark, deferred = parts
    if pane_id in panes:
        metadata[pane_id] = {
            "mark": mark,
            "deferred": (deferred == "on"),
        }

# Convenience aliases for the per-pane marks dict (for the existing
# mark-rendering code paths below) and a deferred set for filtering.
marks = {p: m["mark"] for p, m in metadata.items() if m["mark"]}
deferred_panes = {p for p, m in metadata.items() if m["deferred"]}

counts = {"needs-input": 0, "working": 0, "new": 0, "done": 0, "idle": 0}
ignored = 0
deferred_count = 0

# Per-pane state lookup; kept around so marked panes can render
# mark+symbol pairs individually instead of rolling into counts.
pane_state = {}
pane_ignored = {}

try:
    with open(cache_file) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            pane_id, state, ign = parts
            if pane_id not in panes:
                continue
            pane_state[pane_id] = state
            pane_ignored[pane_id] = (ign == "y")
            # Marked panes render individually; unmarked aggregate.
            if pane_id in marks:
                continue
            # Deferred panes do not contribute to the per-state counts
            # — they render as a trailing ⏸N aggregate. Ignored
            # similarly bumps the ∅N bucket. The two are deliberately
            # separate so users can tell "I muted these" from "I'm
            # deferring these intentionally."
            if pane_id in deferred_panes:
                deferred_count += 1
                continue
            if ign == "y":
                ignored += 1
            elif state in counts:
                counts[state] += 1
except FileNotFoundError:
    pass

# Marked panes with no cache entry still render (state=none) so the
# label is visible even before any provider has observed the pane.
for pane_id in marks:
    pane_state.setdefault(pane_id, "none")
    pane_ignored.setdefault(pane_id, False)

# Marked panes that are also deferred should render their mark with
# the deferred styling rather than the active mark style — the
# user has both labelled the pane AND set it aside, both signals
# matter. Communicated by tagging the pane in the rendering loop.

symbols = {
    "needs-input": "\u2328",      # ⌨   waiting for user
    "working":     "\u2699",      # ⚙   computing
    "new":         "\u2733",      # ✳   fresh session
    "done":        "\u2713",      # ✓   finished, unseen
    "idle":        "\U0001f4a4",  # 💤  at prompt, no work
    "none":        "",            # marked pane, no state observation yet
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

# Deferred uses a distinctly readable color from ignored: we want the
# user to see "deferred" as still-tracked-but-not-urgent, not as
# muted-away-and-forgotten. Cyan-tinted gray pops a half-step harder
# than ignored's mid-gray.
deferred_style = "fg=colour109" if palette != "fallback" else "bg=colour237,fg=colour109"

# Mark styling: explicit override, else palette-appropriate default.
# Bright cyan pops against most dark bars without colliding with the
# state symbol palette (yellow/cyan/magenta/green).
mark_style = os.environ.get("MARK_STYLE_OVERRIDE", "")
if not mark_style:
    mark_style = "bg=colour24,fg=brightwhite,bold" if palette == "fallback" else "fg=brightcyan,bold"

order = ["needs-input", "working", "new", "done", "idle"]

def paint(style, text):
    return f"#[{style}]{text}#[default]"

def mark_chunk(pane_id):
    """Render one marked pane as mark+symbol (e.g. 'AR⚙')."""
    label = marks[pane_id]
    state = pane_state.get(pane_id, "none")
    sym = symbols.get(state, "")
    # Mute precedence: ignored > deferred > active. Marks under each
    # tier render with the matching style so the user sees at a glance
    # which moderation level applies. The state symbol stays styled so
    # you can still see what the pane is doing.
    if pane_ignored.get(pane_id):
        ms = ignored_style
    elif pane_id in deferred_panes:
        ms = deferred_style
    else:
        ms = mark_style
    if sym:
        return paint(ms, label) + paint(styles[state], sym)
    return paint(ms, label)

out = []

# Marked panes first, sorted by mark text for stable ordering so the
# status bar doesn't jitter as pane IDs shuffle between redraws.
for pane_id in sorted(marks, key=lambda p: (marks[p], p)):
    out.append(mark_chunk(pane_id))

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

# \u23F8 (deferred bracket) — distinct glyph from ignored's \u2205
# so users see "intentionally deferred" vs "passively muted" at a
# glance.
if deferred_count:
    out.append(paint(deferred_style, f"\u23F8{deferred_count}"))

print(" ".join(out))
PY
