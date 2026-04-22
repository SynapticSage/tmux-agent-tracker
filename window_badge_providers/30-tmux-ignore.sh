#!/usr/bin/env bash
# Provider: @recon-ignore flag (tmux-native)
#
# Emits a "none" state with ignored=y for every pane where the
# @recon-ignore option resolves to "on" at any scope (pane -> window ->
# session -> global, via tmux's standard inheritance). The merger OR-s
# the ignored flag with observations from other providers, so an
# ignored pane that's also Working will land in the cache as
# (working, ignored=y) and render in the trailing ∅N bucket regardless.

set -euo pipefail

command -v tmux >/dev/null 2>&1 || exit 0

tmux list-panes -a -F '#{pane_id}|#{@recon-ignore}' 2>/dev/null | python3 -c '
import sys
for line in sys.stdin:
    line = line.strip()
    if "|" not in line:
        continue
    pane_id, ignored = line.split("|", 1)
    if ignored == "on":
        print(f"{pane_id}\tnone\ty")
'
