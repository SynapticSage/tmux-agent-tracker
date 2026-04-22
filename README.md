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

`N` is the count of panes in that window in that state.

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
        ├── 10-claude-hooks.sh   ← TMUX_BADGE_PANE_*_STATE env vars
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

See [`CLAUDE.md`](CLAUDE.md) for the full provider contract, merge
rules, and the "drop an executable, get a new signal source"
extension pattern.

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
working > new > done > idle > none`) and OR-s the ignored flag. See
[`CLAUDE.md`](CLAUDE.md) for the full contract.

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
