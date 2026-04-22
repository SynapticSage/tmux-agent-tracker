#!/usr/bin/env bash
# Provider: Claude Code hook state (event-driven, fast path)
#
# Reads TMUX_BADGE_PANE_<pane_id>_STATE global env vars written by
# ../hook_agent_state.sh, which is wired into Claude Code hooks in
# ~/.claude/settings.json. Hook latency is ~10ms — this is the fast
# path that lets badges react before the next recon poll.
#
# Lossy by design: if a Claude process dies without Stop firing, the
# env var persists until the recon provider drops the pane from the
# cache by no longer observing it there. That's the whole reason the
# two providers coexist.
#
# Emits TSV: <pane_id>\t<state>\t<ignored=n>
# Canonical vocab:
#   running     -> working
#   needs-input -> needs-input
#   done        -> done
#   (off / unknown -> skipped)

set -euo pipefail

command -v tmux >/dev/null 2>&1 || exit 0

tmux show-environment -g 2>/dev/null | python3 -c '
import sys, re
pat = re.compile(r"^TMUX_BADGE_PANE_(%\d+)_STATE=(.+)$")
mapping = {"running": "working", "needs-input": "needs-input", "done": "done"}
for line in sys.stdin:
    m = pat.match(line.strip())
    if not m:
        continue
    pane_id, raw = m.group(1), m.group(2)
    canon = mapping.get(raw)
    if canon:
        print(f"{pane_id}\t{canon}\tn")
'
