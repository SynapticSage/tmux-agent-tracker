#!/usr/bin/env bash
# summarize_titles.sh — AI-generated per-pane title summaries.
#
# Finds agent panes via the badge cache, captures their recent scrollback
# (alternate screen first, history-buffer fallback), pipes to a configurable
# inference command, and writes the result into the per-pane option
# `@agent-title`. Surface it by including `#{@agent-title}` in
# `pane-border-format` (see README). Writing to an option — rather than
# `select-pane -T` — sidesteps the OSC 2 race: Claude Code and Codex emit
# OSC 2 every render, which would otherwise overwrite a `pane_title` we
# just set within ~1 second.
#
# Usage: summarize_titles.sh [--scope window|server|pane]
#                            [--lines N] [--cmd "CMD"] [--dry-run]
#                            [--yes] [--force]
#
# Tmux options (all optional, may be overridden by flags):
#   @agent-tracker-summarize-cmd              full inference invocation
#   @agent-tracker-summarize-lines            scrollback depth (history fallback)
#   @agent-tracker-summarize-max-title-chars  word-boundary truncation limit
#   @agent-tracker-summarize-log              log file path; 'off' to disable
#                                             (default /tmp/tmux-agent-tracker-summarize-<uid>.log)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || true)}"
[[ -x "$TMUX_BIN" ]] || { echo "tmux not found" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
scope="" lines="" cmd="" dry_run=0 yes=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)   scope="$2";  shift 2 ;;
    --lines)   lines="$2";  shift 2 ;;
    --cmd)     cmd="$2";    shift 2 ;;
    --dry-run) dry_run=1;   shift   ;;
    --yes)     yes=1;       shift   ;;
    --force)               shift   ;;  # reserved; currently no-op
    *)                     shift   ;;
  esac
done

# ---------------------------------------------------------------------------
# Defaults from tmux options
# ---------------------------------------------------------------------------
[[ -z "$scope" ]] && scope="window"

if [[ -z "$lines" ]]; then
  lines=$("$TMUX_BIN" show-option -gqv "@agent-tracker-summarize-lines" 2>/dev/null || true)
  lines="${lines:-200}"
fi

if [[ -z "$cmd" ]]; then
  cmd=$("$TMUX_BIN" show-option -gqv "@agent-tracker-summarize-cmd" 2>/dev/null || true)
  if [[ -z "$cmd" ]]; then
    # Build the default from optional parts. --bare forces ANTHROPIC_API_KEY
    # auth (skips OAuth/keychain), breaking Max-subscription users, so we
    # omit it. @agent-tracker-summarize-model lets users pick a model without
    # rewriting the whole command; defaults to haiku for low cost/latency.
    model=$("$TMUX_BIN" show-option -gqv "@agent-tracker-summarize-model" 2>/dev/null || true)
    model="${model:-claude-haiku-4-5-20251001}"
    cmd="claude --model $model -p \"In 1-3 words describe the task. Reply with only the topic, no punctuation.\""
  fi
fi

max_chars=$("$TMUX_BIN" show-option -gqv "@agent-tracker-summarize-max-title-chars" 2>/dev/null || true)
max_chars="${max_chars:-24}"

# ---------------------------------------------------------------------------
# Logging — write per-pane diagnostics to a single append-mode file so users
# can see *why* a summarize call failed (eval errors are otherwise swallowed
# by the inference subshell). Disabled by setting the option to 'off'.
# ---------------------------------------------------------------------------
log_file=$("$TMUX_BIN" show-option -gqv "@agent-tracker-summarize-log" 2>/dev/null || true)
log_file="${log_file:-/tmp/tmux-agent-tracker-summarize-$(id -u).log}"
log() {
  [[ "$log_file" == "off" ]] && return 0
  printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "${1:-info}" "${2:-}" >> "$log_file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Cache setup — mirrors window_badge.sh:59-74 sync-on-miss logic
# ---------------------------------------------------------------------------
cache_file="/tmp/tmux-window-badge-$(id -u).cache"
provenance_file="/tmp/tmux-badge-titles-$(id -u).cache"
refresh="$SCRIPT_DIR/window_badge_refresh.sh"
poll_interval=$("$TMUX_BIN" show-option -gqv "@window-badge-poll-interval" 2>/dev/null || true)
poll_interval="${poll_interval:-5}"

if [[ ! -f "$cache_file" ]]; then
  "$refresh" 2>/dev/null || true
else
  age=$(python3 -c "import os,time; print(int(time.time()-os.path.getmtime('$cache_file')))" 2>/dev/null || echo 0)
  (( age > poll_interval * 2 )) && { "$refresh" 2>/dev/null || true; }
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
capture_content() {
  local pane_id="$1" content
  # Alternate screen: where Claude Code and Codex render their TUI chrome.
  # Without -a we get the history buffer (shell output before the agent
  # started), which is the wrong thing to summarize.
  content=$("$TMUX_BIN" capture-pane -t "$pane_id" -p -a 2>/dev/null || true)
  # If the alternate screen is sparse, fall back to scrollback history.
  if [[ "${#content}" -lt 100 ]]; then
    content=$("$TMUX_BIN" capture-pane -t "$pane_id" -p -S -"$lines" 2>/dev/null || true)
  fi
  # Strip ANSI escape sequences. BSD sed's bracket expressions don't treat
  # \x07 as BEL, so CSI private bytes (?25l etc.) and ST-terminated OSC
  # (ESC ] ... ESC \) both survive sed. Python handles all three variants.
  printf '%s' "$content" | python3 -c "
import sys, re
t = sys.stdin.read()
t = re.sub(r'\x1b\[[\x20-\x3f]*[\x40-\x7e]', '', t)        # CSI
t = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\\\)', '', t)   # OSC (BEL or ST)
t = re.sub(r'\x1b[^\[\]]', '', t)                            # two-char escapes
sys.stdout.write(t)
"
}

truncate_title() {
  local t="$1" max="$2"
  [[ "${#t}" -le "$max" ]] && { printf '%s' "$t"; return; }
  local trimmed="${t:0:$max}"
  local last_space="${trimmed% *}"
  # Word-boundary trim only when it leaves at least 3 chars; otherwise hard-cut.
  [[ "${#last_space}" -ge 3 ]] \
    && printf '%s' "$last_space" \
    || printf '%s' "$trimmed"
}

# ---------------------------------------------------------------------------
# Discover candidate panes from cache
# Cache rows: <pane_id>\t<state>\t<ignored>
# Filtered to non-ignored, non-none rows (real agent observations only).
# ---------------------------------------------------------------------------
candidates=()
if [[ -f "$cache_file" ]]; then
  while IFS=$'\t' read -r pane_id state ignored; do
    [[ -z "$pane_id" ]]                    && continue
    [[ "$ignored" == "y" ]]                && continue
    [[ "$state" == "none" || -z "$state" ]] && continue
    candidates+=("$pane_id")
  done < "$cache_file"
fi

# ---------------------------------------------------------------------------
# Apply scope filter
# ---------------------------------------------------------------------------
filtered=()
case "$scope" in
  window)
    cur_win=$("$TMUX_BIN" display-message -p '#{window_id}' 2>/dev/null || true)
    win_panes=$("$TMUX_BIN" list-panes -t "$cur_win" -F '#{pane_id}' 2>/dev/null || true)
    for p in "${candidates[@]+"${candidates[@]}"}"; do
      printf '%s\n' "$win_panes" | grep -qFx "$p" && filtered+=("$p") || true
    done
    ;;
  pane)
    cur_pane=$("$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null || true)
    for p in "${candidates[@]+"${candidates[@]}"}"; do
      [[ "$p" == "$cur_pane" ]] && filtered+=("$p") || true
    done
    ;;
  server)
    filtered=("${candidates[@]+"${candidates[@]}"}")
    ;;
esac

total="${#filtered[@]}"

# ---------------------------------------------------------------------------
# Early exits
# ---------------------------------------------------------------------------
if [[ "$total" -eq 0 ]]; then
  "$TMUX_BIN" display-message "summarize-titles: no agent panes in scope" 2>/dev/null || true
  exit 0
fi

# Server-scope preflight confirmation (bypassed when --yes is passed, which
# the keybinding always does).
if [[ "$scope" == "server" && "$yes" -ne 1 ]]; then
  win_count=$("$TMUX_BIN" list-panes -a -F '#{window_id}' 2>/dev/null \
    | sort -u | wc -l | tr -d ' ')
  read -r -p "Summarize $total pane(s) across $win_count window(s)? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

# ---------------------------------------------------------------------------
# Dry run — print candidates without calling inference
# ---------------------------------------------------------------------------
if [[ "$dry_run" -eq 1 ]]; then
  for p in "${filtered[@]}"; do
    win_name=$("$TMUX_BIN" display-message -p -t "$p" '#{window_name}' 2>/dev/null || echo "?")
    content=$(capture_content "$p" | head -c 80 | tr '\n' ' ')
    printf '%s\t%s\t%s\n' "$p" "$win_name" "$content"
  done
  exit 0
fi

# ---------------------------------------------------------------------------
# Parallel inference
# ---------------------------------------------------------------------------
"$TMUX_BIN" display-message "summarize-titles: summarizing $total pane(s)..." 2>/dev/null || true

log "run" "scope=$scope panes=$total cmd=$cmd"

result_dir=$(mktemp -d)
trap 'rm -rf "$result_dir"' EXIT

concurrency="${SUMMARIZE_CONCURRENCY:-4}"
pids=()

for p in "${filtered[@]}"; do
  # Concurrency cap: block until the oldest job finishes before forking more.
  while [[ "${#pids[@]}" -ge "$concurrency" ]]; do
    wait "${pids[0]}" 2>/dev/null || true
    pids=("${pids[@]:1}")
  done

  (
    content=$(capture_content "$p")
    if [[ -z "$content" ]]; then
      log "skip" "pane=$p reason=empty-capture"
      touch "$result_dir/skip_${p//%/_}"
      exit 0
    fi
    log "capture" "pane=$p chars=${#content}"

    # Inference: the full invocation is eval-ed so the user's option value can
    # include flags, quoted strings, and pipeline stages.  $cmd is a tmux
    # option set by the server owner — same trust level as any run-shell hook.
    # Capture stderr + exit code separately so we can log eval failures
    # rather than swallowing them. `if ...; then` form is required:
    # `title=$(...); rc=$?` would trip errexit on the assignment line and
    # kill the subshell silently before logging or touching fail_*.
    err_file="$result_dir/err_${p//%/_}"
    if title=$(printf '%s' "$content" | eval "$cmd" 2>"$err_file"); then
      rc=0
    else
      rc=$?
      err_head=$(head -c 400 "$err_file" 2>/dev/null | tr '\n' ' ')
      # Many CLIs write the actual error to stdout, not stderr (claude's
      # "Credit balance is too low" being a notable example). On failure,
      # log both streams so the user has at least one chance of seeing
      # the real cause without having to add their own debugging.
      out_head=$(printf '%s' "$title" | head -c 400 | tr '\n' ' ')
      log "fail" "pane=$p eval-rc=$rc stdout=${out_head:-<empty>} stderr=${err_head:-<empty>}"
      touch "$result_dir/fail_${p//%/_}"
      exit 0
    fi

    # Take only the first non-empty output line; word-boundary truncate.
    title=$(printf '%s' "$title" | grep -m1 . | tr -d '\r' || true)
    title=$(truncate_title "$title" "$max_chars")

    if [[ -z "$title" ]]; then
      err_head=$(head -c 200 "$err_file" 2>/dev/null | tr '\n' ' ')
      log "skip" "pane=$p reason=empty-output eval-stderr=${err_head:-<empty>}"
      touch "$result_dir/skip_${p//%/_}"
      exit 0
    fi

    # Write into a per-pane option instead of pane_title. Pane titles are
    # owned by whichever side emits OSC 2 last, and Claude/Codex emit it
    # continuously — so `select-pane -T` flickers on for one render and
    # then loses. `@agent-title` is ours alone; render via pane-border-format.
    if "$TMUX_BIN" set-option -p -t "$p" '@agent-title' "$title" 2>>"$err_file"; then
      log "ok" "pane=$p title=$title"
      printf '%s\t%s\n' "$p" "$title" > "$result_dir/ok_${p//%/_}"
    else
      err_head=$(head -c 400 "$err_file" 2>/dev/null | tr '\n' ' ')
      log "fail" "pane=$p set-option-failed stderr=${err_head:-<empty>}"
      touch "$result_dir/fail_${p//%/_}"
    fi
  ) &
  pids+=($!)
done

# Drain remaining background jobs.
for pid in "${pids[@]+"${pids[@]}"}"; do
  wait "$pid" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Update provenance cache (atomic rename).
# Keeps track of which titles we wrote so future cleanup can tell ours from
# user-set titles. Known limitation: two concurrent invocations can race on
# the read→merge→mv cycle (the last mv wins). Worst outcome: the losing
# run's entries are re-summarized on the next invocation. flock is not
# available on macOS without homebrew, so we accept this for now.
# ---------------------------------------------------------------------------
tmp_prov=$(mktemp)
if [[ -f "$provenance_file" ]]; then
  while IFS=$'\t' read -r p_id p_title; do
    [[ -f "$result_dir/ok_${p_id//%/_}" ]] || printf '%s\t%s\n' "$p_id" "$p_title"
  done < "$provenance_file" >> "$tmp_prov" || true
fi
cat "$result_dir"/ok_* 2>/dev/null >> "$tmp_prov" || true
mv "$tmp_prov" "$provenance_file"

# ---------------------------------------------------------------------------
# Summary feedback
# ---------------------------------------------------------------------------
# find exits 0 on empty results; ls with a glob exits 1 under set -euo pipefail.
titled=$(find "$result_dir" -maxdepth 1 -name 'ok_*'   2>/dev/null | wc -l | tr -d ' ')
skipped=$(find "$result_dir" -maxdepth 1 -name 'skip_*' 2>/dev/null | wc -l | tr -d ' ')
failed=$(find "$result_dir"  -maxdepth 1 -name 'fail_*' 2>/dev/null | wc -l | tr -d ' ')
"$TMUX_BIN" display-message \
  "summarize-titles: ${titled} titled, ${skipped} skipped, ${failed} failed" \
  2>/dev/null || true
