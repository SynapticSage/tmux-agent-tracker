# tmux-agent-tracker — CLAUDE.md

Repository-level notes for Claude Code working in this repo.

---

## What this is

A TPM-compatible tmux plugin that appends per-window status badges
showing the state of AI coding agents (Claude Code, Codex) running
inside each window's panes.

Shape:

- `agent_tracker.tmux` — TPM entry point. Auto-wires the badge into
  `window-status-format` / `window-status-current-format` when tmux
  sources the plugin.
- `window_badge.sh` — hot path. Called by tmux once per window per
  status redraw. Reads the cache file, renders a badge string.
- `window_badge_refresh.sh` — cold path. Runs every provider, merges
  their TSV lines by pane_id, atomically writes the cache.
- `window_badge_providers/` — the extension surface. Any executable
  here that emits `<pane_id>\t<state>\t<ignored>` is a provider.
- `hook_agent_state.sh` — Claude Code hook handler. Writes
  `TMUX_BADGE_PANE_<pane_id>_STATE` into tmux global env.
- `install.sh` — one-shot Claude-hook registration (edits
  `~/.claude/settings.json` since TPM can't).

---

## Architectural ground rules

### No daemon

The first attempt at this concept (commit `d978a0e`, now razed)
reached for a central daemon with a control binary, monitor binary,
hook binary, pattern library, and state manager. That attempt stalled
at the daemon itself (the `daemon/` directory was still empty at time
of razing). The current architecture is the opposite: **the hot path
is the refresh trigger.** When `window_badge.sh` notices the cache is
stale, it forks the refresh in the background and renders with stale
data this tick. Next redraw picks up the fresh cache. There is no
long-running process to start, supervise, or explain.

Do not reintroduce a daemon. If a future feature seems to require
one, look for a way to piggyback on tmux's own redraw cadence
(`status-interval`) instead.

### Cache is the only integration point

Providers never talk to each other or to the renderer. They emit TSV
to stdout; the merger reads stdin and writes the cache; the renderer
reads the cache. This is the only shared state.

Corollary: **no provider may depend on another provider's output.**
If you find yourself wanting provider B to read provider A's result,
merge them into one provider or add an upstream cache file that both
consume.

### Providers are executables, not functions

The extension contract is a filesystem one: drop an executable into
`window_badge_providers/`, and the merger picks it up on next refresh.
This keeps the contract language-agnostic — a provider written in
Rust, Python, Node, or shell all look identical to the merger.

Do not refactor toward a "provider plugin API" in shell. The
filename-based discovery is the feature.

---

## Provider contract

TSV on stdout, one line per observation:

```
<pane_id>\t<state>\t<ignored>
```

- `pane_id` — tmux's `#{pane_id}` form, e.g. `%12`. Stable across
  window moves; this is the canonical key.
- `state` — one of `needs-input`, `working`, `new`, `done`, `idle`,
  `none`. Adding a new state requires updating the priority table in
  `window_badge_refresh.sh` AND the symbols map + style tables in
  `window_badge.sh`. If only one side knows the state, renders will
  silently drop it.
- `ignored` — `y` or `n`.

### Merge rule

- Per `pane_id`, keep the highest-priority `state` across providers.
  Priority high → low: `needs-input > working > new > done > idle > none`.
- OR the `ignored` flag: any `y` wins.

A provider may observe any subset of panes — it is not required to
cover all panes. Providers whose upstream tool is missing (e.g.
`recon` not installed, `codex` not running) should exit 0 with no
output, not fail. The merger swallows stderr of every provider so
one broken provider can't starve the rest.

---

## Claude Code hook chain

Event-driven fast path. `install.sh` registers these in
`~/.claude/settings.json`:

| Hook                              | `hook_agent_state.sh` state |
|-----------------------------------|-----------------------------|
| `UserPromptSubmit` (first group)  | `off` (clears prior `done`) |
| `UserPromptSubmit` (second group) | `running`                   |
| `PermissionRequest`               | `needs-input`               |
| `Stop`                            | `done`                      |

`hook_agent_state.sh` writes the state into a tmux global env var and
calls `refresh-client -S` so the status bar repaints immediately —
no waiting on `status-interval`.

This is fast (~10 ms) but lossy: Claude processes killed with
`SIGKILL` never fire `Stop`, so the env var lingers until the recon
provider drops the pane from its next observation. Reconciliation
through polling is deliberate; don't try to make the hooks themselves
"complete."

---

## Rendering

Surface is `window-status-format` / `window-status-current-format`.
Not `rename-window`.

Rationale: renaming windows pollutes ssh titlebars, vim's `set title`,
and anything else that reads `$WINDOW`. Status-bar formatting is
scoped, reversible, and re-rendered on tmux's own cadence.

`agent_tracker.tmux` self-heals its own wiring: on every source, it
checks whether `window_badge.sh` is already referenced in the format
string before appending. Repeat-sourcing the plugin (tmux reload,
TPM update) does not duplicate the badge.

---

## Migration safety

`install.sh` supersedes prior registrations. It identifies "ours" by
matching any hook whose command path ends in `/hook_agent_state.sh` —
regardless of which directory. So moving the plugin between
directories (dev clone → `~/.tmux/plugins/…`) cleanly updates
`settings.json` when re-run at the new location.

Do not keep historical path knowledge elsewhere. The filename suffix
match IS the migration mechanism.

---

## Testing

Bash wrappers around tmux don't unit-test well. Minimum smoke path
for any substantive change:

1. Start 3 windows, each with a different agent state (idle /
   working / needs-input). Confirm correct symbol + count per window.
2. `kill -9` a Claude process without the hook firing. Within one
   poll interval (`@window-badge-poll-interval`, default 5 s), that
   pane should clear from the cache.
3. Set `@recon-ignore on` on a pane. Next redraw, pane moves into
   the `∅N` bucket; the state symbols for that window decrement.
4. Restart the tmux server. Badges repopulate within one poll
   interval without manual intervention.
5. Run `install.sh` twice in a row — second run should report
   "already in desired state", not duplicate entries.
6. Move the plugin to a different directory, run `install.sh` from
   the new location — old entries should vanish and new ones appear
   pointing at the new path.
