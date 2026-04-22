#!/usr/bin/env bash
# install.sh — registers this plugin's Claude Code hooks in
# ~/.claude/settings.json.
#
# Why this script exists at all: TPM installs tmux plugins, but it
# cannot edit Claude Code's settings. The tmux-side wiring
# (window-status-format) is handled automatically by agent_tracker.tmux
# when TPM sources the plugin; the Claude hooks need one explicit run
# of this script.
#
# Behavior notes:
#   - Idempotent. Re-running with the same plugin path is a no-op.
#   - Migration-safe. Any prior hook entry whose command path ends in
#     /hook_agent_state.sh is removed before the new entries are added,
#     regardless of source directory. So moving this plugin from one
#     location to another (e.g. dev clone -> ~/.tmux/plugins) just
#     requires re-running install.sh at the new location — no manual
#     settings.json editing.
#   - Safe. Backs up settings.json to .bak.<stamp> before every write.
#   - Reversible. --uninstall strips every hook entry this script's
#     hook_agent_state.sh variants ever registered.
#
# Usage:
#   install.sh [--install|--uninstall] [--dry-run] [--yes]

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_SCRIPT="$PLUGIN_DIR/hook_agent_state.sh"

action=install
dry_run=0
assume_yes=0

print_help() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)   action=install;   shift ;;
    --uninstall) action=uninstall; shift ;;
    --dry-run)   dry_run=1;        shift ;;
    --yes|-y)    assume_yes=1;     shift ;;
    -h|--help)   print_help; exit 0 ;;
    *) echo "unknown argument: $1" >&2; print_help >&2; exit 2 ;;
  esac
done

confirm() {
  [[ $assume_yes -eq 1 || $dry_run -eq 1 ]] && return 0
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

backup() {
  local f="$1"
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  cp "$f" "${f}.bak.${stamp}"
  echo "  backup: ${f}.bak.${stamp}"
}

check_prereqs() {
  local missing=()
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  command -v tmux    >/dev/null 2>&1 || missing+=("tmux")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing required tools: ${missing[*]}" >&2
    exit 1
  fi
  [[ -x "$HOOK_SCRIPT" ]] || chmod +x "$HOOK_SCRIPT"
}

# ---------------------------------------------------------------------
# JSON manipulation — delegated to python so we never hand-craft JSON.
# Both install and uninstall first strip every hook whose command path
# ends in /hook_agent_state.sh. Install then adds fresh entries
# pointing at this plugin's HOOK_SCRIPT.
# ---------------------------------------------------------------------
run_python() {
  local mode="$1"
  local dry="$2"
  MODE="$mode" DRY="$dry" HOOK_SCRIPT="$HOOK_SCRIPT" \
  python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
mode = os.environ["MODE"]
dry  = os.environ["DRY"] == "1"
hook = os.environ["HOOK_SCRIPT"]

with open(path) as f:
    d = json.load(f)

# Structure: d["hooks"][event] -> list of {matcher, hooks: [{type, command}]}
# A hook "belongs to us" if its command references any path ending in
# /hook_agent_state.sh. This catches stale entries from a previous
# install location (e.g. tmux-manage) so migration is clean.
def ours(cmd):
    c = (cmd or "").strip().split()
    return bool(c) and c[0].endswith("/hook_agent_state.sh")

removed = []
hooks = d.setdefault("hooks", {})
for ev in list(hooks.keys()):
    new_groups = []
    for g in hooks[ev]:
        kept = []
        for h in g.get("hooks", []):
            if ours(h.get("command", "")):
                removed.append(f"{ev}: {h['command']}")
            else:
                kept.append(h)
        if kept:
            g["hooks"] = kept
            new_groups.append(g)
    if new_groups:
        hooks[ev] = new_groups
    else:
        del hooks[ev]

added = []
if mode == "install":
    # UserPromptSubmit fires twice: first clears any lingering "done"
    # indicator (state=off), then marks the session as actively running.
    plan = [
        ("UserPromptSubmit",  "off"),
        ("UserPromptSubmit",  "running"),
        ("PermissionRequest", "needs-input"),
        ("Stop",              "done"),
    ]
    for ev, st in plan:
        hooks.setdefault(ev, []).append({
            "matcher": "",
            "hooks": [{"type": "command", "command": f"{hook} --state {st}"}]
        })
        added.append(f"{ev} -> --state {st}")

if not hooks:
    d.pop("hooks", None)

if dry:
    if removed: print("  would remove:", *removed, sep="\n    ")
    if added:   print("  would add:",    *added,   sep="\n    ")
    if not removed and not added:
        print("  already in desired state")
else:
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    if removed: print("  removed:", *removed, sep="\n    ")
    if added:   print("  added:",   *added,   sep="\n    ")
    if not removed and not added:
        print("  already in desired state")
PY
}

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------
check_prereqs

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  echo "settings.json not found at $CLAUDE_SETTINGS" >&2
  echo "create Claude Code's settings first, then rerun" >&2
  exit 1
fi

case "$action" in
  install)
    echo "Install tmux-agent-tracker Claude hooks"
    echo "  plugin dir:    $PLUGIN_DIR"
    echo "  settings.json: $CLAUDE_SETTINGS"
    echo "  dry-run:       $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
    echo ""
    confirm "Proceed?" || { echo "aborted."; exit 1; }
    echo ""
    [[ $dry_run -eq 0 ]] && backup "$CLAUDE_SETTINGS"
    run_python install "$dry_run"
    echo ""
    echo "Done. Open or reload a Claude Code session — badges update as hooks fire."
    ;;
  uninstall)
    echo "Uninstall tmux-agent-tracker Claude hooks"
    echo "  settings.json: $CLAUDE_SETTINGS"
    echo "  dry-run:       $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
    echo ""
    confirm "Proceed?" || { echo "aborted."; exit 1; }
    echo ""
    [[ $dry_run -eq 0 ]] && backup "$CLAUDE_SETTINGS"
    run_python uninstall "$dry_run"
    echo ""
    echo "Done. Plugin files remain in $PLUGIN_DIR — delete manually if no longer wanted."
    ;;
esac
