#!/bin/bash
# state_manager.sh - State management for tmux-claude-ext
# Created: 2025-08-07

set -euo pipefail

[[ -z "${STATE_DIR:-}" ]] && readonly STATE_DIR="/tmp/tmux-claude"
[[ -z "${ENV_PREFIX:-}" ]] && readonly ENV_PREFIX="@claude"

init_state_dir() {
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
}

get_pane_id() {
    local session_window_pane="$1"
    echo "${session_window_pane//[:.]/_}"
}

get_window_for_pane() {
    local pane_id="$1"
    # Extract window index from format like "session:window.pane"
    echo "$pane_id" | cut -d':' -f2 | cut -d'.' -f1
}

get_panes_for_window() {
    local window="$1"
    tmux list-panes -t "$window" -F "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null || true
}

set_pane_status() {
    local pane_id="$1"
    local status="$2"
    local timestamp=$(date +%s)
    
    local clean_id=$(get_pane_id "$pane_id")
    local window=$(get_window_for_pane "$clean_id")
    
    tmux set-environment "${ENV_PREFIX}_${clean_id}_status" "$status" 2>/dev/null || true
    tmux set-environment "${ENV_PREFIX}_${clean_id}_timestamp" "$timestamp" 2>/dev/null || true
    
    echo "$status" > "${STATE_DIR}/${clean_id}.status"
    echo "$timestamp" > "${STATE_DIR}/${clean_id}.timestamp"
    
    update_window_status "$window"
}

get_pane_status() {
    local pane_id="$1"
    local clean_id=$(get_pane_id "$pane_id")
    
    local status=$(tmux show-environment "${ENV_PREFIX}_${clean_id}_status" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$status" ]] && [[ -f "${STATE_DIR}/${clean_id}.status" ]]; then
        status=$(cat "${STATE_DIR}/${clean_id}.status" 2>/dev/null)
    fi
    
    echo "${status:-none}"
}

clear_pane_status() {
    local pane_id="$1"
    local clean_id=$(get_pane_id "$pane_id")
    local window=$(get_window_for_pane "$clean_id")
    
    tmux set-environment -u "${ENV_PREFIX}_${clean_id}_status" 2>/dev/null || true
    tmux set-environment -u "${ENV_PREFIX}_${clean_id}_timestamp" 2>/dev/null || true
    
    rm -f "${STATE_DIR}/${clean_id}.status"
    rm -f "${STATE_DIR}/${clean_id}.timestamp"
    rm -f "${STATE_DIR}/${clean_id}.log"
    
    update_window_status "$window"
}

update_window_status() {
    local window="$1"
    local highest_priority=""
    local priority_order=("❓" "❌" "⏱" "🤔" "🔄" "✅")
    
    # Collect all statuses for this window
    local statuses=()
    for pane in $(get_panes_for_window "$window"); do
        local status=$(get_pane_status "$pane")
        if [[ "$status" != "none" ]] && [[ -n "$status" ]]; then
            statuses+=("$status")
        fi
    done
    
    # Find highest priority status
    if [[ ${#statuses[@]} -gt 0 ]]; then
        for priority_status in "${priority_order[@]}"; do
            for status in "${statuses[@]}"; do
                if [[ "$status" == "$priority_status" ]]; then
                    highest_priority="$priority_status"
                    break 2
                fi
            done
        done
    fi
    
    local clean_window="${window//:/_}"
    
    if [[ -n "$highest_priority" ]]; then
        tmux set-environment "${ENV_PREFIX}_${clean_window}_status" "$highest_priority" 2>/dev/null || true
    else
        tmux set-environment -u "${ENV_PREFIX}_${clean_window}_status" 2>/dev/null || true
    fi
    
    tmux refresh-client -S 2>/dev/null || true
}

get_last_activity() {
    local pane_id="$1"
    local clean_id=$(get_pane_id "$pane_id")
    
    if [[ -f "${STATE_DIR}/${clean_id}.timestamp" ]]; then
        cat "${STATE_DIR}/${clean_id}.timestamp"
    else
        date +%s
    fi
}

update_last_activity() {
    local pane_id="$1"
    local clean_id=$(get_pane_id "$pane_id")
    local timestamp=$(date +%s)
    
    echo "$timestamp" > "${STATE_DIR}/${clean_id}.timestamp"
    tmux set-environment "${ENV_PREFIX}_${clean_id}_timestamp" "$timestamp" 2>/dev/null || true
}

is_pane_monitored() {
    local pane_id="$1"
    local clean_id=$(get_pane_id "$pane_id")
    
    [[ -f "${STATE_DIR}/${clean_id}.monitoring" ]]
}

set_pane_monitored() {
    local pane_id="$1"
    local monitored="${2:-true}"
    local clean_id=$(get_pane_id "$pane_id")
    
    if [[ "$monitored" == "true" ]]; then
        touch "${STATE_DIR}/${clean_id}.monitoring"
    else
        rm -f "${STATE_DIR}/${clean_id}.monitoring"
    fi
}

list_monitored_panes() {
    shopt -s nullglob
    for file in "${STATE_DIR}"/*.monitoring; do
        if [[ -f "$file" ]]; then
            local clean_id=$(basename "$file" .monitoring)
            # Convert from clean_id (session_window_pane) back to pane_id (session:window.pane)
            local parts=(${clean_id//_/ })
            if [[ ${#parts[@]} -eq 3 ]]; then
                echo "${parts[0]}:${parts[1]}.${parts[2]}"
            else
                echo "$clean_id"
            fi
        fi
    done
    shopt -u nullglob
}

cleanup_stale_state() {
    shopt -s nullglob
    for file in "${STATE_DIR}"/*.monitoring; do
        if [[ -f "$file" ]]; then
            local clean_id=$(basename "$file" .monitoring)
            # Convert from clean_id to check session
            local session="${clean_id%%_*}"
            
            if ! tmux has-session -t "$session" 2>/dev/null; then
                rm -f "${STATE_DIR}/${clean_id}."*
            fi
        fi
    done
    shopt -u nullglob
}

get_all_statuses() {
    local format="%-30s %-15s %-20s\n"
    printf "$format" "PANE" "STATUS" "LAST ACTIVITY"
    printf "$format" "----" "------" "-------------"
    
    for pane in $(list_monitored_panes); do
        local status=$(get_pane_status "$pane")
        local timestamp=$(get_last_activity "$pane")
        local time_ago=$(($(date +%s) - timestamp))
        
        local activity
        if [[ $time_ago -lt 60 ]]; then
            activity="${time_ago}s ago"
        elif [[ $time_ago -lt 3600 ]]; then
            activity="$((time_ago / 60))m ago"
        else
            activity="$((time_ago / 3600))h ago"
        fi
        
        printf "$format" "$pane" "$status" "$activity"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <command> [args...]"
        echo "Commands: init, set_status, get_status, clear_status, list, cleanup"
        exit 1
    fi
    
    case "$1" in
        init)
            init_state_dir
            ;;
        set_status)
            set_pane_status "$2" "$3"
            ;;
        get_status)
            get_pane_status "$2"
            ;;
        clear_status)
            clear_pane_status "$2"
            ;;
        list)
            get_all_statuses
            ;;
        cleanup)
            cleanup_stale_state
            ;;
        *)
            echo "Unknown command: $1"
            exit 1
            ;;
    esac
fi