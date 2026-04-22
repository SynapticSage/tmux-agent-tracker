#!/usr/bin/env bash
# Provider: recon (polled, authoritative)
#
# Calls `recon json` and translates pane_target -> pane_id so the cache
# keys align with other providers. Recon sees crashed / externally
# killed sessions that hooks missed; this is the reconciliation signal.
#
# Emits TSV: <pane_id>\t<state>\t<ignored=n>
# Canonical vocab:
#   Idle    -> idle
#   Working -> working
#   New     -> new
#   (Waiting would map to needs-input, kept here for when recon exposes it)

set -euo pipefail

command -v recon >/dev/null 2>&1 || exit 0
command -v tmux  >/dev/null 2>&1 || exit 0

# Pipe-delimited so we can parse in Python without shell quoting games.
MAP=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}' 2>/dev/null || true)
JSON=$(recon json 2>/dev/null || true)

[[ -n "$JSON" ]] || exit 0

MAP="$MAP" JSON="$JSON" python3 -c '
import os, json
m = {}
for line in os.environ.get("MAP", "").splitlines():
    if "|" in line:
        t, p = line.split("|", 1)
        m[t] = p

try:
    d = json.loads(os.environ.get("JSON", ""))
except Exception:
    raise SystemExit(0)

canonical = {
    "Idle":    "idle",
    "Working": "working",
    "New":     "new",
    "Waiting": "needs-input",
}
for s in d.get("sessions", []):
    canon = canonical.get(s.get("status", ""))
    target = s.get("pane_target", "")
    if canon and target in m:
        print(f"{m[target]}\t{canon}\tn")
'
