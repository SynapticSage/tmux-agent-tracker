# tmux-claude-ext - Claude File

## Project Overview
A tmux extension that monitors Claude Code sessions across panes and windows, providing visual indicators in the status bar when Claude needs user input or when activity has stalled. Never miss a prompt or stuck process again while multitasking.

## Core Features
- Detect Claude Code prompts/choices in tmux panes
- Visual markers on window tabs for panes needing attention
- Activity timeout detection with configurable thresholds
- Multiple notification styles (symbols, colors, bells)
- Smart pattern matching for Claude's output
- Per-pane status tracking
- Integration with tmux status line

## Visual Indicators
```bash
# Window tab examples with markers
1:vim  2:claude[❓2,⏱3]  3:logs  4:claude[❓1]  5:shell

# Marker meanings
❓ - Choice/input needed
⏱ - Activity timeout
🤔 - Thinking/processing
✅ - Task complete
❌ - Error state
🔄 - Active/running

# Pane numbers indicate which pane needs attention
[❓2] - Pane 2 needs input
[⏱3] - Pane 3 has stalled
[❓1,⏱3] - Multiple panes need attention
```

## Technical Architecture
- **Core**: Shell script + tmux hooks
- **Monitoring**: tmux pipe-pane for output capture
- **State Management**: Temporary files in /tmp/tmux-claude/
- **Configuration**: Extended .tmux.conf
- **Optional**: Go/Rust daemon for performance

## Project Structure
```
tmux-claude-ext/
├── bin/
│   ├── tmux-claude-monitor    # Main monitoring script
│   ├── tmux-claude-hook       # Hook scripts
│   └── tmux-claude-ctl        # Control utility
├── lib/
│   ├── claude_patterns.sh     # Pattern matching
│   ├── status_formatter.sh    # Status line formatting
│   └── state_manager.sh       # State tracking
├── conf/
│   ├── tmux-claude.conf       # Main tmux config
│   └── patterns.conf          # Claude output patterns
├── scripts/
│   ├── install.sh
│   └── uninstall.sh
├── daemon/                    # Optional compiled daemon
│   ├── main.go
│   └── monitor.go
├── tests/
├── README.md
└── Makefile
```

## Pattern Detection
```bash
# patterns.conf - Claude Code output patterns
CHOICE_PATTERNS=(
    "Choose one of:"
    "Select an option:"
    "Please choose"
    "Enter your choice"
    "[1-9]\)"
    "Type 'yes' or 'no'"
    "→"  # Claude's choice indicator
)

COMPLETION_PATTERNS=(
    "Task completed"
    "Successfully"
    "Finished"
    "Done!"
)

ERROR_PATTERNS=(
    "Error:"
    "Failed"
    "Exception"
    "Could not"
)

THINKING_PATTERNS=(
    "Thinking..."
    "Analyzing"
    "Processing"
    "Working on"
)
```

## tmux Configuration
```bash
# ~/.tmux.conf additions
# Enable Claude monitoring
set-option -g @claude-monitor on
set-option -g @claude-timeout 300  # 5 minutes
set-option -g @claude-bell on
set-option -g @claude-style "symbols"  # or "colors", "both"

# Window status format with Claude indicators
set-window-option -g window-status-format '#I:#W#{?@claude_#{window_index}_status,[#{@claude_#{window_index}_status}],}'
set-window-option -g window-status-current-format '#I:#W#{?@claude_#{window_index}_status,[#{@claude_#{window_index}_status}],}'

# Hooks for monitoring
set-hook -g after-new-session 'run-shell "tmux-claude-monitor start"'
set-hook -g after-new-window 'run-shell "tmux-claude-hook window-add"'
set-hook -g after-new-pane 'run-shell "tmux-claude-hook pane-add"'
set-hook -g pane-exited 'run-shell "tmux-claude-hook pane-remove"'

# Key bindings
bind-key C-c run-shell "tmux-claude-ctl status"
bind-key M-c run-shell "tmux-claude-ctl clear"
```

## Monitoring Implementation
```bash
#!/bin/bash
# tmux-claude-monitor - Main monitoring loop

monitor_pane() {
    local pane_id=$1
    local pane_tty=$(tmux display -p -t "$pane_id" '#{pane_tty}')
    
    # Set up pipe-pane to capture output
    tmux pipe-pane -t "$pane_id" "cat >> /tmp/tmux-claude/${pane_id}.log"
    
    # Monitor loop
    while true; do
        # Check for patterns in recent output
        local recent=$(tail -n 50 "/tmp/tmux-claude/${pane_id}.log")
        
        # Check for choice prompts
        if match_choice_pattern "$recent"; then
            set_pane_status "$pane_id" "❓"
            notify_user "$pane_id" "choice"
        fi
        
        # Check for inactivity
        if check_inactive "$pane_id" "$TIMEOUT"; then
            set_pane_status "$pane_id" "⏱"
            notify_user "$pane_id" "timeout"
        fi
        
        sleep 1
    done
}
```

## State Management
```bash
# State stored in tmux environment variables
# Format: @claude_<window>_<pane>_<attribute>

set_pane_status() {
    local pane_id=$1
    local status=$2
    local window=$(get_window_for_pane "$pane_id")
    
    # Store status
    tmux set-environment "@claude_${window}_${pane}_status" "$status"
    
    # Update window status
    update_window_status "$window"
}

update_window_status() {
    local window=$1
    local combined_status=""
    
    # Aggregate all pane statuses for window
    for pane in $(get_panes_for_window "$window"); do
        local status=$(tmux show-environment "@claude_${window}_${pane}_status" 2>/dev/null | cut -d= -f2)
        if [ -n "$status" ]; then
            combined_status="${combined_status}${status}${pane},"
        fi
    done
    
    # Set window-level status
    tmux set-environment "@claude_${window}_status" "${combined_status%,}"
    tmux refresh-client -S
}
```

## Control Utility
```bash
# tmux-claude-ctl - User control interface

case "$1" in
    status)
        # Show all Claude panes and their status
        show_claude_status
        ;;
    clear)
        # Clear status for current pane
        clear_pane_status
        ;;
    mute)
        # Temporarily disable monitoring
        tmux set-option @claude-monitor off
        ;;
    unmute)
        # Re-enable monitoring
        tmux set-option @claude-monitor on
        ;;
    goto)
        # Jump to pane needing attention
        goto_next_alert
        ;;
esac
```

## Advanced Features

### Smart Detection
```bash
# Contextual pattern matching
detect_claude_state() {
    local content=$1
    local context_lines=100
    
    # Multi-line pattern matching
    if grep -Pzo "(?s)Choose one of:.*?\n\s*\d+\)" <<< "$content"; then
        return 0  # Choice detected
    fi
    
    # Detect stuck spinner/progress
    if detect_stuck_animation "$content"; then
        return 1  # Stuck state
    fi
}
```

### Custom Notifications
```bash
# User-defined notification actions
notify_user() {
    local pane_id=$1
    local type=$2
    
    case "$NOTIFY_METHOD" in
        bell)
            tmux send-keys -t "$pane_id" C-g  # Bell
            ;;
        flash)
            tmux select-pane -t "$pane_id" -P 'bg=red'
            sleep 0.1
            tmux select-pane -t "$pane_id" -P 'default'
            ;;
        system)
            notify-send "Claude needs input" "Pane $pane_id"
            ;;
    esac
}
```

### Performance Optimization
```go
// Optional Go daemon for better performance
package main

import (
    "github.com/fsnotify/fsnotify"
    "github.com/hpcloud/tail"
)

func monitorPane(paneID string) {
    logFile := fmt.Sprintf("/tmp/tmux-claude/%s.log", paneID)
    
    t, _ := tail.TailFile(logFile, tail.Config{
        Follow: true,
        ReOpen: true,
    })
    
    for line := range t.Lines {
        if detectPattern(line.Text) {
            updateTmuxStatus(paneID, getStatus(line.Text))
        }
    }
}
```

## Installation
```bash
# install.sh
#!/bin/bash

# Create directories
mkdir -p ~/.tmux/plugins/tmux-claude-ext/{bin,lib}
mkdir -p /tmp/tmux-claude

# Copy files
cp bin/* ~/.tmux/plugins/tmux-claude-ext/bin/
cp lib/* ~/.tmux/plugins/tmux-claude-ext/lib/

# Add to PATH
echo 'export PATH="$PATH:~/.tmux/plugins/tmux-claude-ext/bin"' >> ~/.bashrc

# Update tmux.conf
cat conf/tmux-claude.conf >> ~/.tmux.conf

# Reload tmux
tmux source-file ~/.tmux.conf
```

## Usage Examples
```bash
# Start monitoring
tmux-claude-monitor start

# Check status across all windows
tmux-claude-ctl status

# Jump to next pane needing attention
tmux-claude-ctl goto

# Clear alerts for current pane
tmux-claude-ctl clear

# Configure timeout
tmux set-option @claude-timeout 600  # 10 minutes
```

## Configuration Options
```bash
# Timeout before showing ⏱ marker (seconds)
@claude-timeout 300

# Enable/disable monitoring
@claude-monitor on

# Style: symbols, colors, both
@claude-style symbols

# Enable bell on alerts
@claude-bell on

# Custom symbols
@claude-symbol-choice "❓"
@claude-symbol-timeout "⏱"
@claude-symbol-error "❌"
@claude-symbol-complete "✅"

# Notification method: bell, flash, system, none
@claude-notify bell
```

## Future Enhancements
- Machine learning for better pattern detection
- Integration with other AI coding assistants
- Historical analytics of Claude usage patterns
- Collaborative session awareness
- Mobile notifications
- Web dashboard for remote monitoring
- Automatic context switching based on urgency
- Integration with task management tools

## Implementation Notes

### Window Status Format Challenges

#### Problem: Dynamic Variable Expansion in tmux
tmux doesn't support dynamic variable expansion like `#{@claude_#{window_index}_status}` directly. The `#{window_index}` variable isn't expanded within the variable name lookup.

#### Solution: Explicit Conditionals
Had to use explicit conditionals for each window index (0-9):
```bash
#{?#{e|==:#{window_index},0},#{@claude_0_status},}
#{?#{e|==:#{window_index},1},#{@claude_1_status},}
# ... etc for indices 2-9
```

### Integration with Existing Formats
- Use `-ag` (append global) to add status indicators without overriding existing window formats
- This preserves powerline separators and custom themes
- The status emoji is appended after the existing window format

### State Management
- Variables must be checked before declaring as readonly to avoid conflicts when multiple scripts source the same library
- Use `[[ -z "${VAR:-}" ]] && readonly VAR=value` pattern
- For loop globbing, use `shopt -s nullglob` to handle empty directories

### Monitoring Detection
The monitor looks for processes with names matching:
- `claude`
- `claude-code`
- `claude_code`
- `npx` (commonly used to run Claude via `npx claude`)

Uses `#{pane_current_command}` from tmux to identify Claude sessions.