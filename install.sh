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
# Two optional steps run after the hook registration:
#   1. Emoji picker — fetches a full Unicode CLDR emoji list and writes
#      it next to the bundled small list so mark_emoji.sh can use it.
#      Skipped with --no-emoji. Prompted interactively otherwise.
#   2. Theme recommendation — if neither onedark nor catppuccin is
#      detected in ~/.tmux.conf, offers to append a plugin line.
#      Skipped with --no-theme. Prompted interactively otherwise.
#
# Usage:
#   install.sh [--install|--uninstall] [--dry-run] [--yes]
#              [--emoji|--no-emoji] [--theme onedark|catppuccin|--no-theme]

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_SCRIPT="$PLUGIN_DIR/hook_agent_state.sh"
EMOJI_LIST_FULL="$PLUGIN_DIR/emoji_full.txt"
TMUX_CONF="${HOME}/.tmux.conf"
THEME_BEGIN_MARKER='# >>> tmux-agent-tracker theme >>>'
THEME_END_MARKER='# <<< tmux-agent-tracker theme <<<'
EMOJI_URL="${EMOJI_URL:-https://unicode.org/Public/emoji/latest/emoji-test.txt}"

action=install
dry_run=0
assume_yes=0
emoji_choice=""   # "" = ask, "yes", "no"
theme_choice=""   # "" = ask, "no", "onedark", "catppuccin"

print_help() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)    action=install;   shift ;;
    --uninstall)  action=uninstall; shift ;;
    --dry-run)    dry_run=1;        shift ;;
    --yes|-y)     assume_yes=1;     shift ;;
    --emoji)      emoji_choice=yes; shift ;;
    --no-emoji)   emoji_choice=no;  shift ;;
    --theme)
      theme_choice="${2:-}"
      [[ "$theme_choice" =~ ^(onedark|catppuccin)$ ]] || {
        echo "--theme requires 'onedark' or 'catppuccin'" >&2; exit 2
      }
      shift 2 ;;
    --no-theme)   theme_choice=no;  shift ;;
    -h|--help)    print_help; exit 0 ;;
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
# Emoji picker — optionally fetch a full Unicode CLDR emoji list.
#
# Always-present: the bundled `emoji.txt` (~60 curated dev-relevant
# entries). Opt-in: parse emoji-test.txt from Unicode.org into a
# tab-separated "<glyph>\t<keywords>" list so fzf can fuzzy match
# by name ("bug" finds 🐛).
#
# Failure modes:
#   - No network: prints a hint, leaves bundled list alone. Picker
#     still works with curated entries.
#   - Parse error: leaves existing emoji_full.txt if one exists,
#     otherwise no file — picker falls back to bundled.
# ---------------------------------------------------------------------
install_emoji_list() {
  local do_it="$1"   # "yes" / "no" / "" (ask)
  if [[ -z "$do_it" && $assume_yes -eq 0 ]]; then
    echo ""
    echo "[emoji picker] Full Unicode CLDR emoji list enables fuzzy-search"
    echo "  by name (e.g. 'bug' -> 🐛). Without it, Ctrl-E in the mark popup"
    echo "  still works against ~60 bundled dev-relevant emojis."
    confirm "  Fetch the full list now?" && do_it=yes || do_it=no
  elif [[ -z "$do_it" ]]; then
    # --yes without explicit --emoji/--no-emoji: default to bundled-only.
    do_it=no
  fi

  echo "[emoji picker] mode: $do_it"
  if [[ "$do_it" != "yes" ]]; then
    echo "  bundled list at $PLUGIN_DIR/emoji.txt"
    return 0
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo "  would fetch $EMOJI_URL"
    echo "  would write $EMOJI_LIST_FULL"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "  curl not found — skipping fetch"
    return 0
  }

  local tmp
  tmp=$(mktemp)
  if ! curl -fsSL --max-time 30 "$EMOJI_URL" -o "$tmp"; then
    echo "  fetch failed — leaving bundled list as fallback"
    rm -f "$tmp"
    return 0
  fi

  # emoji-test.txt format (excerpt):
  #   1F600 ; fully-qualified     # 😀 E1.0 grinning face
  # We want:  😀\tgrinning face
  # Keep only fully-qualified so skin tones & component parts don't
  # flood the list.
  python3 - "$tmp" "$EMOJI_LIST_FULL" <<'PY'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
out = []
pat = re.compile(r"^[0-9A-F\s]+;\s*fully-qualified\s*#\s*(\S+)\s+E\d+\.\d+\s+(.+)$")
with open(src) as f:
    for line in f:
        m = pat.match(line)
        if m:
            glyph, name = m.group(1), m.group(2).strip()
            out.append(f"{glyph}\t{name}")
with open(dst, "w") as f:
    f.write("\n".join(out) + "\n")
print(f"  wrote {len(out)} entries -> {dst}")
PY
  rm -f "$tmp"
}

# ---------------------------------------------------------------------
# Theme recommendation.
#
# Badges lean on a dark status bar for readability. If the user hasn't
# installed onedark or catppuccin, recommend one and (on accept)
# append a plugin line under sentinel markers so --uninstall can strip
# it cleanly. Does NOT run `prefix+I` for them — that's a tmux-side
# interactive step; we just tell them what to do next.
# ---------------------------------------------------------------------
detect_theme() {
  [[ -f "$TMUX_CONF" ]] || { echo "none"; return; }
  # Consider a plugin line active only if it's not commented out. The
  # -E pattern matches uncommented @plugin lines with the theme name.
  if grep -Eq "^[[:space:]]*set[[:space:]]+-g[[:space:]]+@plugin[[:space:]]+.*onedark" "$TMUX_CONF"; then
    echo "onedark"; return
  fi
  if grep -Eq "^[[:space:]]*set[[:space:]]+-g[[:space:]]+@plugin[[:space:]]+.*catppuccin" "$TMUX_CONF"; then
    echo "catppuccin"; return
  fi
  echo "none"
}

install_theme() {
  local choice="$1"   # "no", "onedark", "catppuccin", "" (ask)

  local detected
  detected=$(detect_theme)
  if [[ "$detected" != "none" ]]; then
    echo ""
    echo "[theme] $detected already active — skipping recommendation"
    return 0
  fi

  if [[ -z "$choice" && $assume_yes -eq 0 ]]; then
    echo ""
    echo "[theme] No dark theme detected. Badges are readable against most"
    echo "  backgrounds, but the default palette assumes a dark status bar."
    echo "  Options: (1) onedark  (2) catppuccin  (3) skip"
    local ans
    read -r -p "  Choice [3]: " ans
    case "${ans:-3}" in
      1|onedark)    choice=onedark ;;
      2|catppuccin) choice=catppuccin ;;
      *)            choice=no ;;
    esac
  elif [[ -z "$choice" ]]; then
    choice=no
  fi

  echo "[theme] choice: $choice"
  if [[ "$choice" == "no" ]]; then
    return 0
  fi

  local plugin_line
  case "$choice" in
    onedark)    plugin_line="set -g @plugin 'odedlaz/tmux-onedark-theme'" ;;
    catppuccin) plugin_line="set -g @plugin 'catppuccin/tmux'" ;;
  esac

  if [[ ! -f "$TMUX_CONF" ]]; then
    echo "  $TMUX_CONF missing — cannot add plugin line"
    return 0
  fi

  # Don't re-add if a previous install run already wrote the block
  # (the marker is unique to us — tpm won't have touched this).
  if grep -Fq "$THEME_BEGIN_MARKER" "$TMUX_CONF"; then
    echo "  theme block already present; not touching"
    return 0
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo "  would append to $TMUX_CONF:"
    echo "    $THEME_BEGIN_MARKER"
    echo "    $plugin_line"
    echo "    $THEME_END_MARKER"
    return 0
  fi

  backup "$TMUX_CONF"
  {
    echo ""
    echo "$THEME_BEGIN_MARKER"
    echo "$plugin_line"
    echo "$THEME_END_MARKER"
  } >> "$TMUX_CONF"
  echo "  appended plugin line. Run this to actually install it:"
  echo "    ~/.tmux/plugins/tpm/bin/install_plugins"
}

uninstall_theme_block() {
  [[ -f "$TMUX_CONF" ]] || return 0
  grep -Fq "$THEME_BEGIN_MARKER" "$TMUX_CONF" || return 0
  if [[ $dry_run -eq 1 ]]; then
    echo "  would strip theme block from $TMUX_CONF"
    return 0
  fi
  backup "$TMUX_CONF"
  awk -v b="$THEME_BEGIN_MARKER" -v e="$THEME_END_MARKER" '
    index($0, b) { skip=1; next }
    index($0, e) { skip=0; next }
    !skip
  ' "$TMUX_CONF" > "${TMUX_CONF}.tmp"
  mv "${TMUX_CONF}.tmp" "$TMUX_CONF"
  echo "  stripped theme block"
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
    echo "Install tmux-agent-tracker"
    echo "  plugin dir:    $PLUGIN_DIR"
    echo "  settings.json: $CLAUDE_SETTINGS"
    echo "  dry-run:       $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
    echo ""
    confirm "Proceed?" || { echo "aborted."; exit 1; }
    echo ""
    [[ $dry_run -eq 0 ]] && backup "$CLAUDE_SETTINGS"
    run_python install "$dry_run"
    install_emoji_list "$emoji_choice"
    install_theme "$theme_choice"
    echo ""
    echo "Done. Open or reload a Claude Code session — badges update as hooks fire."
    ;;
  uninstall)
    echo "Uninstall tmux-agent-tracker"
    echo "  settings.json: $CLAUDE_SETTINGS"
    echo "  tmux.conf:     $TMUX_CONF (theme block, if any)"
    echo "  dry-run:       $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
    echo ""
    confirm "Proceed?" || { echo "aborted."; exit 1; }
    echo ""
    [[ $dry_run -eq 0 ]] && backup "$CLAUDE_SETTINGS"
    run_python uninstall "$dry_run"
    uninstall_theme_block
    if [[ -f "$EMOJI_LIST_FULL" && $dry_run -eq 0 ]]; then
      rm -f "$EMOJI_LIST_FULL"
      echo "  removed $EMOJI_LIST_FULL"
    fi
    echo ""
    echo "Done. Plugin files remain in $PLUGIN_DIR — delete manually if no longer wanted."
    ;;
esac
