# tmux-agent-tracker

> Per-window status badges for AI coding agents (Claude Code, Codex)
> running across a tmux server. One glance at the status bar tells you
> which windows are waiting on you, which are computing, which are idle.

```
  main:1 obsidian    💤2        ← 2 idle Claude sessions
  main:2 mlx-audio   ⚙1         ← 1 actively working
  main:3 gtd         ⌨1 💤1     ← 1 waiting for input, 1 idle
  main:4 sec         ✓1 ∅2      ← 1 finished-unseen, 2 muted
  main:5 new-proj    ✳1         ← 1 freshly spawned
```

## Origin

A long time coming. The first attempt at this (commit
[`d978a0e`](../../commit/d978a0e) dated 2025-08-22, now razed) reached
for a centralized daemon — a control plane, pattern-matcher library,
state manager, dispatcher — and stalled before any of it worked. The
current code started from the opposite premise: no daemon, a single
cache file, a render script that refreshes the cache when it notices
it's stale. Five files of logic instead of fifty.

## What it does

Every window in your tmux status bar gets a compact suffix showing
what's happening in its panes:

| Symbol | State        | Meaning                               | Default color |
|--------|--------------|---------------------------------------|---------------|
| `⌨N`   | needs-input  | User action required (prompt gate)    | yellow bold   |
| `⚙N`   | working      | Agent is computing a response         | cyan bold     |
| `✳N`   | new          | Session freshly spawned               | magenta bold  |
| `✓N`   | done         | Finished response you haven't seen    | green bold    |
| `💤N`  | idle         | Sitting at prompt, no active work     | bright white  |
| `∅N`   | ignored      | Muted via `@recon-ignore`             | mid-gray      |
| `⏸N`   | deferred     | Set aside via `@agent-deferred`       | cyan-gray     |

`N` is the count of panes in that window in that state.

**Three-tier visibility model:**

| Tier      | Counted in state badges? | Trailing aggregate? | Inbox? | Cycle? |
|-----------|--------------------------|---------------------|--------|--------|
| active    | yes                      | —                   | yes    | yes    |
| deferred  | no                       | `⏸N`                | yes (sorted last) | no |
| ignored   | no                       | `∅N`                | hidden by default | no |

`deferred` is "I'm intentionally setting this aside but want it
discoverable." `ignored` is "drop it from everything." The two are
deliberately separate.

## Recon integration

When `recon` ([gavraz/recon](https://github.com/gavraz/recon)) is
installed, the plugin also provides keyboard UX for navigating and
muting the Claude sessions it enumerates:

| Key           | What it does                                                  |
|---------------|---------------------------------------------------------------|
| `prefix + g`  | Jump to the next non-Working agent (Idle or waiting-for-input). |
| `prefix + C-g`| Jump only to agents waiting for input.                         |
| `prefix + i`  | Toggle `@recon-ignore` on the focused **pane**. Muted panes drop out of cycle and move into the `∅N` bucket in the badge. |
| `prefix + e`  | Toggle `@recon-ignore` on the focused **window** (cascades to every pane via tmux's option inheritance chain). |
| `prefix + I`  | fzf popup: mute/unmute a non-focused **session** or **window**. |

Muting shares one mechanism across the two UX halves — the toggles
set the option, the `30-tmux-ignore.sh` provider reads it, and the
badge renderer shows the muted count in the trailing `∅N` bucket.
That way marking a window muted also hides it from `recon next` /
`prefix + g` cycling.

All five bindings are individually overridable or disable-able; see
the configuration table below.

## Per-pane marks

Sometimes you want to remember which of your five Claude panes is the
"auth refactor" and which is the "PR review" without renaming the
window or leaving the session. Marks are short per-pane labels (1–6
characters or a single emoji) that render alongside the state badge:

```
  no marks:            ⚙2 💤1
  marks AUTH, BL:      AUTH⚙ BL💤 ⚙1     ← AUTH and BL each own a slot
  mark is an emoji:    🐛⚙ ⚙1 💤1        ← picked via Ctrl-E
```

Marked panes render individually (mark + their own state symbol);
unmarked panes still aggregate into counts.

| Key          | What it does                                             |
|--------------|----------------------------------------------------------|
| `prefix + m` | Popup for the current pane. Type up to 6 chars + Enter to commit, Enter on empty to clear, Esc to cancel, Ctrl-U to reset, **Ctrl-E** to hand off to the emoji picker. |
| `prefix + M` | Skip the char popup; go straight to the emoji picker.     |

Marks live in the tmux pane option `@agent-mark` and persist for the
tmux server's lifetime. They don't survive a tmux server restart.
(Per-pane, not per-session — restoring a saved session from tmux-attic
doesn't carry marks forward either.)

Override the key bindings (or disable them entirely) via:

```tmux
set -g @agent-tracker-mark-key        'm'   # empty string = no bind
set -g @agent-tracker-mark-emoji-key  'M'
set -g @agent-tracker-mark-style      'fg=brightcyan,bold'
```

### Walkthrough

From a Claude pane you want to tag:

```
prefix m            → popup opens
AR<Enter>           → mark set; status bar now shows "AR⚙" for this pane
```

Change your mind about the label:

```
prefix m            → popup shows "current: [AR]"
<Ctrl-U>            → resets the buffer
PR<Enter>           → mark now "PR"
```

Swap to an emoji:

```
prefix m            → popup opens
<Ctrl-E>            → fzf picker opens
bug                 → filter
<Enter>             → 🐛 becomes the mark
```

Clear the mark entirely:

```
prefix m            → popup opens
<Enter>             → empty commit clears; pane re-aggregates into counts
```

Never want to set a mark and want to reclaim `prefix + m`:

```tmux
set -g @agent-tracker-mark-key ''
set -g @agent-tracker-mark-emoji-key ''
```

### Rendering when multiple panes are marked

Marks sort alphabetically, so a window with two marked Claude panes
and two unmarked ones renders stably across redraws regardless of
which pane tmux activates:

```
window:            [AR:claude] [bug:claude] [claude-3] [claude-4]
badge with marks:  AR⚙ 🐛💤 ⚙1 💤1
```

The two trailing aggregated counts cover the unmarked panes; marks
own their own slots and never collapse into the totals.

## Inbox

The badges tell you *which windows* have agents in which states.
The inbox tells you *which agent to work on next*. With 8+ agents
running, that's the harder question.

The inbox lists every agent pane on the tmux server in priority
order — top of the list is what to pick up first. Picker:

```
prefix + <inbox-key>   → fzf popup of every agent pane, sorted
                          (top = most urgent)
```

Default inbox sort:

1. **Visibility tier**: active before deferred. Ignored hidden.
2. **`@agent-priority`** (lower number = higher priority, default
   `100`). Walks the pane → window → session → global tmux scope
   chain, so you can pin a whole session ahead of others with one
   `set -t <session> @agent-priority 10`.
3. **State priority**: needs-input → done → new → idle → working →
   none. So a needs-input agent beats a working one at the same
   `@agent-priority`.
4. **Tiebreak**: session name, window index, pane index — stable
   across redraws.

### Cycling

`prefix + g` and `prefix + C-g` (the recon-cycle bindings) now
walk the inbox in order. Repeated presses are deterministic — they
visit panes in the same priority sequence, not whatever order recon
returned. `recon_cycle.sh` is now a thin wrapper around
`inbox_next.sh`; both end up at the same place.

### Deferred

```
prefix + <defer-pane-key>     → toggle @agent-deferred on this pane
prefix + <defer-window-key>   → toggle @agent-deferred on the window
```

A deferred pane:

- still shows up in the inbox (sorted to the bottom, dimmed style)
- contributes to the trailing `⏸N` aggregate in the badge — not the
  per-state counts
- is skipped by `prefix + g` cycling

This is distinct from `prefix + i` ignore: ignored panes drop
entirely (hidden from inbox, render as `∅N`). Deferred is "park
it but don't lose it"; ignored is "stop tracking."

### Recommended binding sets

Inbox / defer / summarize keys are unset by default — they're opt-in
because every tmux user's prefix-key surface is already crowded by
the time they install another plugin. Two coherent starter sets are
documented below; pick whichever doesn't collide with your existing
muscle memory. (Or roll your own — every key here is just an option.)

**Set A — pause-themed.** Reads naturally if your prefix surface is
mostly free.

```tmux
set -g @agent-tracker-defer-pane-key       'P'   # Pause this pane
set -g @agent-tracker-defer-window-key     'F'   # Freeze whole window
set -g @agent-tracker-inbox-key            '?'   # what's next?
set -g @agent-tracker-summarize-server-key 'Y'   # Yes, summarize all
```

Conflicts to watch for: `P` and `F` are unclaimed in vanilla tmux,
but several session/resurrect plugins reach for them. `Y` is rare
in tmux configs but trivially overrideable if it bites.

**Set B — visual-metaphor.** Reads naturally if `P`/`F`/`Y` are
already claimed by other plugins.

```tmux
set -g @agent-tracker-defer-pane-key       '_'   # underscore = lowered/aside
set -g @agent-tracker-defer-window-key     'Z'   # zzz the whole window
set -g @agent-tracker-inbox-key            '?'
set -g @agent-tracker-summarize-server-key 'Q'   # Quick summary, all
```

Both sets agree on `?` for the inbox popup — that one rarely
conflicts (tmux's default `prefix + ?` is `list-keys -N`, which
most users don't reach for explicitly).

### Priority

Set `@agent-priority N` (integer; lower = higher priority) at any
tmux scope:

```bash
# Pin a single pane to the very top
tmux set-option -p -t %12 @agent-priority 1

# Pin a whole session
tmux set-option -t auth @agent-priority 10

# Default for unset everywhere is 100
```

A pane in the auth session inherits priority 10. If a single pane in
that session sets `1`, that pane jumps ahead of its siblings.

### Cross-agent ranking — known asymmetry

Claude Code panes surface 5 distinct states (needs-input, done,
new, idle, working) at hook latency (~10ms per transition). Codex
panes only surface 2 states (working, idle) via spinner sampling
at the badge poll interval (default 5s). So:

- The inbox ranks Claude transitions immediately and richly.
- Codex transitions appear after up to one poll cycle, and the
  state vocabulary is coarser.

This is a property of the upstream tools, not a plugin choice.
Document it here so users don't expect Codex's "done" to surface
as fast as Claude's.

## Pane title summarization

`prefix+T` walks every agent pane in the current window, captures recent
scrollback, asks an inference backend for a 1-3 word topic, and writes
the result into a per-pane option `@agent-title`. Render that option in
your pane border:

```tmux
set -g pane-border-status top
set -g pane-border-format "#{pane_index}.#{?#{@agent-title},#{@agent-title},#{pane_title}}"
```

**Why an option, not `pane_title`?** Claude Code and Codex emit OSC 2
("set window title") on every render, which would overwrite a
`select-pane -T` value within ~1 second. `@agent-title` is in tmux's
namespace — the pty can't touch it — so summaries stick.

### Invoking

```bash
# Current window (default keybinding: prefix+T)
./summarize_titles.sh --scope window

# All agent panes on the server (skips interactive confirmation)
./summarize_titles.sh --scope server --yes

# Active pane only
./summarize_titles.sh --scope pane

# Preview what would be summarized — no inference calls
./summarize_titles.sh --dry-run
```

### Keybinding configuration

```tmux
# window-scope is bound to T by default; disable with:
set -g @agent-tracker-summarize-window-key 'off'

# opt in to server-scope (prefix+S = all agent panes, server-wide):
set -g @agent-tracker-summarize-server-key 'S'

# opt in to pane-scope:
set -g @agent-tracker-summarize-pane-key   't'
```

### Backends

Set `@agent-tracker-summarize-cmd` to the **complete invocation**. Pane
content is always piped to stdin. The command should write a short title
to stdout.

| Backend       | `set -g @agent-tracker-summarize-cmd` value |
| ------------- | ------------------------------------------- |
| Claude (default) | *(built-in — uses `@agent-tracker-summarize-model`)* |
| Codex         | `codex exec --no-git "In 1-3 words describe the task. No punctuation."` |
| summarize     | `summarize --prompt "In 1-3 words describe the task. No punctuation." -` |
| Fabric        | `fabric -p summarize` *(pattern must exist in `~/.config/fabric/patterns/summarize/`)* |
| Ollama/local  | `ollama run llama3.2 "In 1-3 words describe the task. No punctuation."` |

`--no-git` (codex exec) suppresses repo-rule loading.

> **Note on `--bare`:** Claude's `--bare` flag forces API-key auth and
> skips OAuth/keychain — it breaks Max-subscription users. The default
> command does not use it.

### Tuning

```tmux
# Model for the built-in claude backend (alias or full name).
# Default: claude-haiku-4-5-20251001 (fast, cheap, sufficient for 1-3 words).
set -g @agent-tracker-summarize-model haiku   # or 'sonnet', 'claude-opus-4-7', etc.

# History fallback depth (alternate-screen capture is unbounded)
set -g @agent-tracker-summarize-lines 200

# Word-boundary truncation limit for pane titles
set -g @agent-tracker-summarize-max-title-chars 24
```

To use a fully custom command (different backend or extra flags), override
the whole invocation:

```tmux
set -g @agent-tracker-summarize-cmd \
  'claude --model claude-sonnet-4-6 -p "In 1-3 words describe the task. No punctuation."'
```

## Architecture at a glance

```
┌──────────────────────┐  #(...) called once per window per redraw
│ window_badge.sh      │──────────────────────────┐
│   reads cache        │                          │
│   renders badge      │                          ▼
│   kicks async        │                  ┌───────────────┐
│   refresh on stale   │                  │ /tmp/…cache   │
└──────────────────────┘                  └───────┬───────┘
           ▲                                      │
           │                              atomic write
           │                                      │
┌──────────────────────┐  merges every provider   │
│ window_badge_refresh │──────────────────────────┘
│   priority merge     │
│   writes TSV cache   │
└───────▲──────────────┘
        │
        ├── 10-agent-hooks.sh    ← TMUX_BADGE_PANE_*_STATE env vars
        ├── 20-recon.sh          ← `recon json` (if installed)
        ├── 30-tmux-ignore.sh    ← @recon-ignore option inheritance
        ├── 40-codex.sh          ← ps + tmux capture-pane sampling
        └── (drop-in providers) ← any executable emitting TSV
```

Event-driven source (Claude hooks, ~10 ms) for the fast path; polled
sources (recon, codex, ignore flags) for reconciliation. The renderer
never calls signal sources directly — it reads the cache only. When
cache age exceeds `@window-badge-poll-interval` (default 5 s), the
next render kicks an async refresh in the background and paints with
the current data; the following tick picks up the fresh cache.

## Install

### With TPM (recommended)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'SynapticSage/tmux-agent-tracker'
```

Then `prefix + I` to install. On load, the plugin auto-wires the
badge into `window-status-format` and `window-status-current-format` —
no further config needed to see badges for anything recon or codex
can observe.

For the Claude Code hook fast path (the thing that makes state
changes instant rather than 5-seconds-laggy), one explicit step:

```sh
~/.tmux/plugins/tmux-agent-tracker/install.sh
```

This rewrites `~/.claude/settings.json` to call `hook_agent_state.sh`
on Claude's lifecycle events. It's separate because TPM can't edit
that file for you. The script:

- **Supersedes** any prior `hook_agent_state.sh` registration from a
  previous install location — safe to rerun after moving/upgrading
  the plugin.
- **Backs up** `settings.json` to `.bak.<stamp>` before any write.
- **Supports** `--dry-run`, `--yes`, `--uninstall`.
- Offers two optional follow-on steps (pass `--no-emoji` / `--no-theme`
  to skip):
  - **Emoji picker** — downloads the full Unicode CLDR emoji list into
    `emoji_full.txt` so the mark popup's Ctrl-E picker can fuzzy-match
    by name. Without it, Ctrl-E still works against ~60 curated
    dev-relevant emojis bundled with the plugin.
  - **Theme** — if neither onedark nor catppuccin is already declared
    in `~/.tmux.conf`, offers to append a `@plugin` line. The default
    badge palette assumes a dark status bar; if yours isn't, badges
    still work but may blend.

On first source after install, the plugin prints a one-line
`display-message` nudging you to run this if the hooks aren't
registered yet. Silence with:

```tmux
set -g @agent-tracker-silence-hook-nudge 'on'
```

### Manual

```sh
git clone https://github.com/SynapticSage/tmux-agent-tracker ~/path/to/tmux-agent-tracker
```

Then in `~/.tmux.conf`:

```tmux
run-shell ~/path/to/tmux-agent-tracker/agent_tracker.tmux
```

And run `install.sh` once, as above.

## Configuration

| Option                               | Values                           | Default  | Effect |
|--------------------------------------|----------------------------------|----------|--------|
| `@window-badge-mode`                 | `counts`, `worst`, `off`         | `counts` | Render one symbol+count per state, only the highest-priority state, or disable badges entirely. |
| `@window-badge-poll-interval`        | integer seconds                  | `5`      | Maximum cache age before the renderer triggers an async refresh. |
| `@window-badge-palette`              | *empty*, `fallback`              | *empty*  | Default inherits status-bar styling. `fallback` uses bg+fg color chips for readability regardless of theme. |
| `@agent-tracker-silence-hook-nudge`  | `on`, *empty*                    | *empty*  | Suppresses the one-line nudge when Claude hooks aren't yet registered. |
| `@agent-tracker-mark-key`            | any key or *empty*               | `m`      | `prefix`-table key that opens the mark popup. Empty disables the bind. |
| `@agent-tracker-mark-emoji-key`      | any key or *empty*               | `M`      | `prefix`-table key that opens the emoji picker directly. |
| `@agent-tracker-mark-style`          | tmux style string                | *auto*   | Override the mark coloring. Default: `fg=brightcyan,bold` (or fallback equivalent). |
| `@agent-tracker-emoji-list`          | `full`, `basic`, *empty*         | *auto*   | Force `mark_emoji.sh` to read one list or the other. Auto prefers `emoji_full.txt` if present. |
| `@agent-tracker-recon-cycle-key`         | any key or *empty* | `g`   | Cycle to next non-Working recon agent. |
| `@agent-tracker-recon-cycle-waiting-key` | any key or *empty* | `C-g` | Cycle only to agents waiting for input. |
| `@agent-tracker-ignore-pane-key`         | any key or *empty* | `i`   | Toggle `@recon-ignore` on the focused pane (mutes from cycle + moves to `∅N` bucket). |
| `@agent-tracker-ignore-window-key`       | any key or *empty* | `e`   | Toggle `@recon-ignore` on the focused window (cascades to all panes via inheritance). |
| `@agent-tracker-ignore-picker-key`       | any key or *empty* | `I`   | fzf popup: toggle `@recon-ignore` at session/window scope for non-focused targets. |
| `@agent-tracker-inbox-key`               | any key or *empty* | *unset* | fzf popup: priority-ranked list of every agent pane; pick → jump. Opt-in. |
| `@agent-tracker-inbox-next-key`          | any key or *empty* | *unset* | Headless: jump to next agent in inbox order. (Same logic as `prefix+g`; opt-in extra binding if you want a separate key.) |
| `@agent-tracker-defer-pane-key`          | any key or *empty* | *unset* | Toggle `@agent-deferred` on the focused pane. |
| `@agent-tracker-defer-window-key`        | any key or *empty* | *unset* | Toggle `@agent-deferred` on the focused window (cascades). |
| `@agent-priority`                        | integer            | `100`   | **Per-pane/window/session option** (not a key). Lower = higher inbox priority. Walks tmux's scope inheritance chain. |
| `@agent-deferred`                        | `on` or *unset*    | *unset* | **Per-pane/window option** (not a key). Routes pane out of state counts and cycle, into the `⏸N` bucket and the bottom of the inbox. |

Set at runtime: `tmux set-option -g @window-badge-mode worst` —
takes effect on the next status redraw, no reload required.

## Extending with a new signal source

Any executable dropped in `window_badge_providers/` that emits TSV on
stdout is a valid provider:

```
<pane_id>\t<state>\t<ignored>
```

- `pane_id` — tmux's `#{pane_id}` form, e.g. `%12`
- `state` — one of `needs-input`, `working`, `new`, `done`, `idle`, `none`
- `ignored` — `y` or `n`

Example: a "git dirty" indicator piggybacking on the `new` state
(or add your own to the priority table in `window_badge_refresh.sh`):

```bash
# window_badge_providers/50-git-dirty.sh
#!/usr/bin/env bash
tmux list-panes -a -F '#{pane_id}|#{pane_current_path}' | while IFS='|' read -r p path; do
  [[ -d "$path/.git" ]] || continue
  (cd "$path" && [[ -n "$(git status --porcelain 2>/dev/null)" ]]) && \
    printf '%s\tnew\tn\n' "$p"
done
```

The merger merges observations by priority per pane (`needs-input >
working > new > done > idle > none`) and OR-s the ignored flag. A
provider emitting a state outside the priority table is silently
dropped — so any new state needs to be added to both the priority
dict (`window_badge_refresh.sh`) and the symbols/styles maps
(`window_badge.sh`).

## Dependencies

- `tmux` 3.0+
- `python3` (for the TSV merge step and JSON edits)
- `recon` (optional — enables polled Claude-session observability for
  panes that missed a hook event: [gavraz/recon](https://github.com/gavraz/recon))

## Coexistence

The badge lives in `window-status-format` and adds text only — it
doesn't touch `window-status-style` or any other per-window coloring.
Other status-bar plugins (tmux-powerline themes, continuum's
indicator, etc.) stack around it without conflict.

## License

MIT — see [LICENSE](LICENSE).
