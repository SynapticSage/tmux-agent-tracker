#!/usr/bin/env bash
# recon_cycle.sh [--waiting-only]
#
# Compatibility wrapper for the historical recon_cycle.sh keybindings
# (`prefix + g`, `prefix + C-g`). The substantive cycling logic lives
# in inbox_next.sh now — this file only translates flags and exec's
# through.
#
# Behavior change vs the original recon_cycle.sh:
#   - Previously called `recon json` directly, bypassing the badge
#     cache and creating a second source of truth (Codex review,
#     round 1 finding #3).
#   - Now: cycles in the same priority + state order as the inbox
#     popup. Deterministic — repeated presses walk the same list
#     instead of recon's natively-sorted output.
#   - Default mode (no --waiting-only) cycles through every active
#     agent pane. The original cycled through "non-Working" only;
#     to reproduce that exactly, users can now express it via the
#     finer-grained --only-state flag on inbox_next.sh.
#
# Migration note: if you have a local hack relying on this script's
# old internals (parsing `recon json` output directly, etc.), see
# inbox.sh's TSV format — it carries everything the old recon JSON
# carried plus mark and visibility.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  --waiting-only)
    exec "$PLUGIN_DIR/inbox_next.sh" --waiting-only
    ;;
  "")
    exec "$PLUGIN_DIR/inbox_next.sh"
    ;;
  *)
    echo "recon_cycle.sh: unknown flag: $1 (use --waiting-only or no args)" >&2
    exit 2
    ;;
esac
