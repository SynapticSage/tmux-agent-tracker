#!/bin/bash
# uninstall.sh - Uninstallation script for tmux-claude-ext
# Created: 2025-08-07

set -euo pipefail

readonly INSTALL_DIR="${HOME}/.tmux/plugins/tmux-claude-ext"
readonly TMUX_CONF="${HOME}/.tmux.conf"
readonly STATE_DIR="/tmp/tmux-claude"

print_header() {
    echo "======================================"
    echo "  tmux-claude-ext Uninstallation"
    echo "======================================"
    echo
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1" >&2
}

print_info() {
    echo "ℹ️  $1"
}

print_warning() {
    echo "⚠️  $1"
}

confirm() {
    local prompt="$1"
    local response
    
    read -p "$prompt (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

stop_monitor() {
    print_info "Stopping tmux-claude-monitor..."
    
    if [[ -f "${STATE_DIR}/monitor.pid" ]]; then
        local pid=$(cat "${STATE_DIR}/monitor.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            print_success "Monitor stopped (PID: $pid)"
        else
            print_info "Monitor not running (stale PID file)"
        fi
        rm -f "${STATE_DIR}/monitor.pid"
    else
        print_info "Monitor not running"
    fi
}

clean_state() {
    if [[ -d "$STATE_DIR" ]]; then
        print_info "Cleaning state directory..."
        
        if confirm "Remove all logs and state files?"; then
            rm -rf "$STATE_DIR"
            print_success "State directory removed"
        else
            print_info "Keeping state directory: $STATE_DIR"
        fi
    fi
}

remove_from_tmux_conf() {
    if [[ -f "$TMUX_CONF" ]]; then
        print_info "Removing from tmux configuration..."
        
        local backup="${TMUX_CONF}.uninstall.$(date +%Y%m%d_%H%M%S)"
        cp "$TMUX_CONF" "$backup"
        print_success "Backed up tmux.conf to $backup"
        
        if grep -q "tmux-claude-ext" "$TMUX_CONF"; then
            local temp_file=$(mktemp)
            
            awk '
                /^# ============================================================================$/ {
                    if (getline && /tmux-claude-ext configuration/) {
                        in_block = 1
                        next
                    } else {
                        print prev
                        print
                    }
                    next
                }
                /^source-file.*tmux-claude-ext/ {
                    if (!in_block) next
                }
                in_block && /^# ============================================================================$/ {
                    in_block = 0
                    next
                }
                !in_block {
                    if (NR > 1) print prev
                    prev = $0
                }
                END {
                    if (!in_block && prev) print prev
                }
            ' "$TMUX_CONF" > "$temp_file"
            
            mv "$temp_file" "$TMUX_CONF"
            print_success "Removed tmux-claude-ext from tmux.conf"
        else
            print_info "tmux-claude-ext not found in tmux.conf"
        fi
    fi
}

remove_from_path() {
    local modified=false
    
    for rc_file in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        if [[ -f "$rc_file" ]] && grep -q "tmux-claude-ext" "$rc_file"; then
            print_info "Removing from $rc_file..."
            
            local backup="${rc_file}.uninstall.$(date +%Y%m%d_%H%M%S)"
            cp "$rc_file" "$backup"
            
            local temp_file=$(mktemp)
            grep -v "tmux-claude-ext" "$rc_file" > "$temp_file"
            mv "$temp_file" "$rc_file"
            
            print_success "Removed from $rc_file (backup: $backup)"
            modified=true
        fi
    done
    
    if [[ "$modified" == "false" ]]; then
        print_info "No PATH modifications found"
    fi
}

clear_tmux_environment() {
    print_info "Clearing tmux environment variables..."
    
    if tmux info &>/dev/null; then
        for var in $(tmux show-environment | grep "^@claude_" | cut -d= -f1); do
            tmux set-environment -u "$var" 2>/dev/null || true
        done
        print_success "Cleared tmux environment variables"
    else
        print_info "tmux not running - skipping environment cleanup"
    fi
}

remove_installation() {
    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "Removing installation directory..."
        
        if confirm "Remove $INSTALL_DIR?"; then
            rm -rf "$INSTALL_DIR"
            print_success "Installation directory removed"
        else
            print_warning "Installation directory kept: $INSTALL_DIR"
        fi
    else
        print_info "Installation directory not found"
    fi
}

reload_tmux() {
    if tmux info &>/dev/null; then
        print_info "Reloading tmux configuration..."
        tmux source-file "$TMUX_CONF" 2>/dev/null || true
        print_success "tmux configuration reloaded"
    fi
}

print_completion() {
    echo
    echo "======================================"
    echo "  Uninstallation Complete"
    echo "======================================"
    echo
    echo "tmux-claude-ext has been uninstalled."
    echo
    
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "⚠️  Installation directory still exists: $INSTALL_DIR"
        echo "   Remove manually with: rm -rf $INSTALL_DIR"
    fi
    
    if [[ -d "$STATE_DIR" ]]; then
        echo "⚠️  State directory still exists: $STATE_DIR"
        echo "   Remove manually with: rm -rf $STATE_DIR"
    fi
    
    echo
    echo "Thank you for using tmux-claude-ext!"
}

main() {
    print_header
    
    echo "This will uninstall tmux-claude-ext from your system."
    echo
    
    if ! confirm "Do you want to continue?"; then
        echo "Uninstallation cancelled."
        exit 0
    fi
    
    echo
    
    stop_monitor
    clear_tmux_environment
    remove_from_tmux_conf
    remove_from_path
    clean_state
    remove_installation
    reload_tmux
    
    print_completion
}

main "$@"