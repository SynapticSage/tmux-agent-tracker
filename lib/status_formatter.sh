#!/bin/bash
# status_formatter.sh - Format status for tmux status line
# Created: 2025-08-07

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${STATE_DIR:-}" ]] && readonly STATE_DIR="/tmp/tmux-claude"

get_style_option() {
    tmux show-option -gqv @claude-style 2>/dev/null || echo "symbols"
}

get_custom_symbol() {
    local symbol_type="$1"
    local default="$2"
    
    tmux show-option -gqv "@claude-symbol-${symbol_type}" 2>/dev/null || echo "$default"
}

format_window_status() {
    local window="$1"
    local status_var="@claude_${window//:/_}_status"
    local status=$(tmux show-environment "$status_var" 2>/dev/null | cut -d= -f2)
    
    if [[ -n "$status" ]]; then
        echo "$status"
    fi
}

format_pane_indicator() {
    local status="$1"
    local pane_num="$2"
    local style=$(get_style_option)
    
    case "$style" in
        symbols)
            echo "${status}${pane_num}"
            ;;
        colors)
            case "$status" in
                "❓")
                    echo "#[fg=yellow]P${pane_num}#[default]"
                    ;;
                "⏱")
                    echo "#[fg=orange]P${pane_num}#[default]"
                    ;;
                "❌")
                    echo "#[fg=red]P${pane_num}#[default]"
                    ;;
                "✅")
                    echo "#[fg=green]P${pane_num}#[default]"
                    ;;
                "🤔")
                    echo "#[fg=blue]P${pane_num}#[default]"
                    ;;
                "🔄")
                    echo "#[fg=cyan]P${pane_num}#[default]"
                    ;;
                *)
                    echo "P${pane_num}"
                    ;;
            esac
            ;;
        both)
            case "$status" in
                "❓")
                    echo "#[fg=yellow]${status}${pane_num}#[default]"
                    ;;
                "⏱")
                    echo "#[fg=orange]${status}${pane_num}#[default]"
                    ;;
                "❌")
                    echo "#[fg=red]${status}${pane_num}#[default]"
                    ;;
                "✅")
                    echo "#[fg=green]${status}${pane_num}#[default]"
                    ;;
                "🤔")
                    echo "#[fg=blue]${status}${pane_num}#[default]"
                    ;;
                "🔄")
                    echo "#[fg=cyan]${status}${pane_num}#[default]"
                    ;;
                *)
                    echo "${status}${pane_num}"
                    ;;
            esac
            ;;
    esac
}

get_alert_count() {
    local count=0
    
    for var in $(tmux show-environment | grep "^@claude_.*_status=" | cut -d= -f1); do
        local status=$(tmux show-environment "$var" 2>/dev/null | cut -d= -f2)
        if [[ "$status" == *"❓"* ]] || [[ "$status" == *"⏱"* ]]; then
            ((count++))
        fi
    done
    
    echo "$count"
}

format_status_line() {
    local position="${1:-right}"
    local alerts=$(get_alert_count)
    
    if [[ $alerts -eq 0 ]]; then
        echo ""
    else
        local style=$(get_style_option)
        
        case "$style" in
            symbols)
                echo " [Claude: ${alerts} alerts]"
                ;;
            colors)
                echo " #[fg=yellow,bold][Claude: ${alerts}]#[default]"
                ;;
            both)
                echo " #[fg=yellow,bold][Claude: ${alerts} ⚠️]#[default]"
                ;;
        esac
    fi
}

generate_tmux_config() {
    cat <<'EOF'
# Window status format with Claude indicators
set-window-option -g window-status-format '#I:#W#{?@claude_#{window_index}_status,#{@claude_#{window_index}_status},}'
set-window-option -g window-status-current-format '#[bold]#I:#W#{?@claude_#{window_index}_status,#{@claude_#{window_index}_status},}#[default]'

# Status line with Claude alerts
set -g status-right-length 100
set -g status-right '#{?@claude_alerts,[Claude: #{@claude_alerts}] ,}#[default]%H:%M %d-%b-%y'
EOF
}

update_tmux_status() {
    local total_alerts=0
    local alert_windows=()
    
    for var in $(tmux show-environment | grep "^@claude_.*_.*_status=" | cut -d= -f1); do
        local status=$(tmux show-environment "$var" 2>/dev/null | cut -d= -f2)
        
        if [[ "$status" == "❓" ]] || [[ "$status" == "⏱" ]] || [[ "$status" == "❌" ]]; then
            ((total_alerts++))
            
            local window=$(echo "$var" | sed 's/@claude_\(.*\)_.*_status/\1/' | tr '_' ':')
            if [[ ! " ${alert_windows[@]} " =~ " ${window} " ]]; then
                alert_windows+=("$window")
            fi
        fi
    done
    
    if [[ $total_alerts -gt 0 ]]; then
        tmux set-environment "@claude_alerts" "$total_alerts"
        tmux set-environment "@claude_alert_windows" "${alert_windows[*]}"
    else
        tmux set-environment -u "@claude_alerts" 2>/dev/null || true
        tmux set-environment -u "@claude_alert_windows" 2>/dev/null || true
    fi
    
    tmux refresh-client -S
}

highlight_window() {
    local window="$1"
    local has_alerts=false
    
    for var in $(tmux show-environment | grep "^@claude_${window//:/_}_.*_status=" | cut -d= -f1); do
        local status=$(tmux show-environment "$var" 2>/dev/null | cut -d= -f2)
        if [[ "$status" == "❓" ]] || [[ "$status" == "⏱" ]] || [[ "$status" == "❌" ]]; then
            has_alerts=true
            break
        fi
    done
    
    if [[ "$has_alerts" == "true" ]]; then
        local style=$(get_style_option)
        
        case "$style" in
            colors|both)
                tmux set-window-option -t "$window" window-status-style "fg=yellow,bold"
                tmux set-window-option -t "$window" window-status-current-style "fg=yellow,bold,underscore"
                ;;
        esac
    else
        tmux set-window-option -t "$window" window-status-style "default"
        tmux set-window-option -t "$window" window-status-current-style "bold"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        window)
            format_window_status "${2:-}"
            ;;
        pane)
            format_pane_indicator "${2:-}" "${3:-}"
            ;;
        status-line)
            format_status_line "${2:-right}"
            ;;
        update)
            update_tmux_status
            ;;
        highlight)
            highlight_window "${2:-}"
            ;;
        config)
            generate_tmux_config
            ;;
        *)
            echo "Usage: $0 {window|pane|status-line|update|highlight|config} [args...]"
            exit 1
            ;;
    esac
fi