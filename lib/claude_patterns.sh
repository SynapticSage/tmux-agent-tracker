#!/bin/bash
# claude_patterns.sh - Pattern detection for Claude Code output
# Created: 2025-08-07

set -euo pipefail

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        readonly PATTERNS_FILE="${SCRIPT_DIR}/../conf/patterns.conf"
    else
        readonly SCRIPT_DIR="$(pwd)"
        readonly PATTERNS_FILE="${SCRIPT_DIR}/conf/patterns.conf"
    fi
elif [[ -z "${PATTERNS_FILE:-}" ]]; then
    readonly PATTERNS_FILE="${SCRIPT_DIR}/../conf/patterns.conf"
fi

declare -a PROMPT_PATTERNS
declare -a ACTIVE_PATTERNS
declare -a COMPLETION_PATTERNS
declare -a ERROR_PATTERNS
declare -a THINKING_PATTERNS

load_patterns() {
    if [[ -f "$PATTERNS_FILE" ]]; then
        source "$PATTERNS_FILE"
    else
        PROMPT_PATTERNS=(
            "Choose one of:"
            "Select an option:"
            "Please choose"
            "Enter your choice"
            "\[1-9\]\)"
            "Type 'yes' or 'no'"
            "(y/n)"
            "→"
            "Press Enter to continue"
            "Would you like to"
            "Proceed with"
        )
        
        ACTIVE_PATTERNS=(
            "Thinking\.\.\."
            "Working on"
            "Analyzing"
            "Processing"
            "Executing"
            "Running"
            "Building"
            "Installing"
            "Downloading"
            "\[.*\]"
            "⠋\|⠙\|⠹\|⠸\|⠼\|⠴\|⠦\|⠧\|⠇\|⠏"
        )
        
        COMPLETION_PATTERNS=(
            "Task completed"
            "Successfully"
            "Finished"
            "Done!"
            "Complete"
            "✓"
            "✅"
            "All tests passed"
            "Build successful"
        )
        
        ERROR_PATTERNS=(
            "Error:"
            "Failed"
            "Exception"
            "Could not"
            "Unable to"
            "Fatal:"
            "FAILED"
            "❌"
            "✗"
            "Tests failed"
            "Build failed"
        )
        
        THINKING_PATTERNS=(
            "Thinking"
            "🤔"
            "Analyzing"
            "Considering"
            "Planning"
            "Let me"
            "I'll"
            "I will"
            "Checking"
            "Looking"
        )
    fi
}

match_patterns() {
    local content="$1"
    local pattern_array_name=$2
    
    # Use eval to access the array by name (compatible with older bash)
    eval "local patterns=(\"\${${pattern_array_name}[@]}\")"
    
    if [[ ${#patterns[@]} -eq 0 ]]; then
        return 1
    fi
    
    for pattern in "${patterns[@]}"; do
        # Use case-insensitive matching for better detection
        if grep -qiE "$pattern" <<< "$content" 2>/dev/null; then
            return 0
        fi
    done
    
    return 1
}

detect_prompt_needed() {
    local content="$1"
    match_patterns "$content" PROMPT_PATTERNS
}

detect_active_state() {
    local content="$1"
    match_patterns "$content" ACTIVE_PATTERNS
}

detect_completion() {
    local content="$1"
    match_patterns "$content" COMPLETION_PATTERNS
}

detect_error() {
    local content="$1"
    match_patterns "$content" ERROR_PATTERNS
}

detect_thinking() {
    local content="$1"
    match_patterns "$content" THINKING_PATTERNS
}

detect_multiline_choice() {
    local content="$1"
    
    # Check for numbered choices (1), 2), etc.)
    if echo "$content" | grep -iE "(choose|select|pick|enter).*:" >/dev/null && \
       echo "$content" | grep -E "[0-9]+\)" >/dev/null; then
        return 0
    fi
    
    # Check for numbered choices with dots 1. 2. etc.
    if echo "$content" | grep -iE "(choose|select|options)" >/dev/null && \
       echo "$content" | grep -E "[0-9]+\." >/dev/null; then
        return 0
    fi
    
    # Check for bracketed choices [1], [2], etc.
    if echo "$content" | grep -iE "select.*:" >/dev/null && \
       echo "$content" | grep -E "\[.*\]" >/dev/null; then
        return 0
    fi
    
    # Check for dash/bullet-prefixed options
    if echo "$content" | grep -iE "(options|choose):" >/dev/null && \
       echo "$content" | grep -E "^\s*[-•*]" >/dev/null; then
        return 0
    fi
    
    return 1
}

detect_stuck_animation() {
    local log_file="$1"
    local threshold="${2:-10}"
    
    if [[ ! -f "$log_file" ]]; then
        return 1
    fi
    
    local last_lines=$(tail -n "$threshold" "$log_file" 2>/dev/null)
    local unique_lines=$(echo "$last_lines" | sort -u | wc -l)
    
    if [[ $unique_lines -le 2 ]]; then
        if echo "$last_lines" | grep -qE "⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|\[.*\]|\.{3,}"; then
            return 0
        fi
    fi
    
    return 1
}

check_inactivity() {
    local pane_id="$1"
    local timeout="${2:-300}"
    local log_file="/tmp/tmux-claude/${pane_id}.log"
    
    if [[ ! -f "$log_file" ]]; then
        return 1
    fi
    
    local last_modified=$(stat -f %m "$log_file" 2>/dev/null || stat -c %Y "$log_file" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local inactive_time=$((current_time - last_modified))
    
    if [[ $inactive_time -ge $timeout ]]; then
        local last_line=$(tail -n 1 "$log_file" 2>/dev/null)
        
        if [[ -z "$last_line" ]] || echo "$last_line" | grep -qE "^[❯>$#] *$"; then
            return 0
        fi
    fi
    
    return 1
}

analyze_pane_content() {
    local input="$1"
    local lines="${2:-100}"
    local content=""
    
    # Check if input is a file or file descriptor
    if [[ -f "$input" ]]; then
        # It's a regular file
        content=$(tail -n "$lines" "$input" 2>/dev/null)
    elif [[ -r "$input" ]]; then
        # It's a readable file descriptor (like /dev/fd/XX from process substitution)
        content=$(cat "$input" 2>/dev/null | tail -n "$lines")
    else
        # Treat as direct content
        content="$input"
    fi
    
    if [[ -z "$content" ]]; then
        echo "empty"
        return
    fi
    
    # Check in priority order - prompts have highest priority
    if detect_prompt_needed "$content" || detect_multiline_choice "$content"; then
        echo "prompt"
    elif detect_error "$content"; then
        echo "error"
    elif detect_completion "$content"; then
        echo "complete"
    elif detect_thinking "$content"; then
        echo "thinking"
    elif detect_active_state "$content"; then
        echo "active"
    elif [[ -f "$input" ]] && detect_stuck_animation "$input"; then
        echo "stuck"
    else
        echo "none"
    fi
}

get_status_symbol() {
    local state="$1"
    
    case "$state" in
        prompt)
            echo "❓"
            ;;
        error)
            echo "❌"
            ;;
        complete)
            echo "✅"
            ;;
        thinking)
            echo "🤔"
            ;;
        active)
            echo "🔄"
            ;;
        stuck|timeout)
            echo "⏱"
            ;;
        *)
            echo ""
            ;;
    esac
}

extract_last_prompt() {
    local input="$1"
    local content=""
    
    # Check if input is a file or file descriptor
    if [[ -f "$input" ]]; then
        content=$(tail -n 50 "$input" 2>/dev/null)
    elif [[ -r "$input" ]]; then
        # It's a readable file descriptor (like /dev/fd/XX from process substitution)
        content=$(cat "$input" 2>/dev/null | tail -n 50)
    else
        # Treat as direct content
        content="$input"
    fi
    
    if [[ -z "$content" ]]; then
        echo "No content"
        return
    fi
    
    # Look for the most specific prompt patterns first
    local last_line=$(echo "$content" | tail -n 1)
    if [[ -n "$last_line" ]] && echo "$last_line" | grep -iE "(choose|select|enter|type)" >/dev/null; then
        echo "$last_line" | sed 's/^[[:space:]]*//' | cut -c 1-80
        return
    fi
    
    # Fall back to searching for any prompt pattern
    for pattern in "${PROMPT_PATTERNS[@]}"; do
        local match=$(echo "$content" | grep -iE "$pattern" | tail -n 1)
        if [[ -n "$match" ]]; then
            echo "$match" | sed 's/^[[:space:]]*//' | cut -c 1-80
            return
        fi
    done
    
    echo "Unknown prompt"
}

load_patterns

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <command> [args...]"
        echo "Commands: analyze <log_file>, check_prompt <content>, check_stuck <log_file>"
        exit 1
    fi
    
    case "$1" in
        analyze)
            analyze_pane_content "$2" "${3:-100}"
            ;;
        check_prompt)
            if detect_prompt_needed "$2"; then
                echo "Prompt detected"
                exit 0
            else
                echo "No prompt"
                exit 1
            fi
            ;;
        check_stuck)
            if detect_stuck_animation "$2"; then
                echo "Stuck animation detected"
                exit 0
            else
                echo "Not stuck"
                exit 1
            fi
            ;;
        symbol)
            get_status_symbol "$2"
            ;;
        *)
            echo "Unknown command: $1"
            exit 1
            ;;
    esac
fi
# Helper function for tests
match_choice_pattern() {
    local content="$1"
    
    # Check for common choice patterns
    if echo "$content" | grep -qiE "(choose one|select.*option|enter.*choice|type.*yes.*no|^[0-9]+\)|→)"; then
        echo "true"
        return 0
    fi
    
    echo "false"
    return 1
}
