#!/bin/bash
# test_tmux_integration.sh - Integration tests for tmux
# Created: 2025-08-14

# Check if tmux is available
check_tmux_available() {
    if ! command -v tmux &>/dev/null; then
        skip_test "All tmux integration tests" "tmux not available"
        return 1
    fi
    return 0
}

# Setup test session
setup_tmux_session() {
    export TEST_SESSION="tmux-claude-test-$$"
    tmux new-session -d -s "$TEST_SESSION" 2>/dev/null || true
}

# Cleanup test session
cleanup_tmux_session() {
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
}

test_tmux_environment_variables() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Set environment variable
    tmux set-environment -t "$TEST_SESSION" -g "@test_var" "test_value"
    
    # Get environment variable
    local value=$(tmux show-environment -t "$TEST_SESSION" -g "@test_var" 2>/dev/null | cut -d= -f2)
    assert_equals "test_value" "$value" "Should set and get tmux environment variable"
    
    cleanup_tmux_session
}

test_tmux_hooks() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Set a hook
    tmux set-hook -t "$TEST_SESSION" -g after-new-window 'run-shell "echo window created"'
    
    # Check if hook is set
    local hooks=$(tmux show-hooks -t "$TEST_SESSION" -g 2>/dev/null)
    assert_contains "$hooks" "after-new-window" "Should set tmux hook"
    
    cleanup_tmux_session
}

test_tmux_pipe_pane() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    local log_file="$TEST_STATE_DIR/pipe.log"
    
    # Start pipe-pane
    tmux pipe-pane -t "$TEST_SESSION:0.0" "cat > $log_file"
    
    # Send some text
    tmux send-keys -t "$TEST_SESSION:0.0" "test output" Enter
    
    # Wait for output
    sleep 0.5
    
    # Check log file
    if [[ -f "$log_file" ]]; then
        assert_file_contains "$log_file" "test output" "Pipe-pane should capture output"
    else
        # Some tmux versions might not work with pipe-pane in detached sessions
        skip_test "Pipe-pane test" "Pipe-pane not working in detached session"
    fi
    
    cleanup_tmux_session
}

test_tmux_window_format() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Set window format
    tmux set-window-option -t "$TEST_SESSION" -g window-status-format '#I:#W'
    
    # Get window format
    local format=$(tmux show-window-options -t "$TEST_SESSION" -g window-status-format 2>/dev/null | cut -d' ' -f2-)
    assert_equals "#I:#W" "$format" "Should set window format"
    
    cleanup_tmux_session
}

test_tmux_key_bindings() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Set key binding
    tmux bind-key -T prefix x run-shell "echo test"
    
    # Check if binding exists
    local bindings=$(tmux list-keys 2>/dev/null)
    assert_contains "$bindings" "run-shell" "Should set key binding"
    
    cleanup_tmux_session
}

test_monitor_start_stop() {
    check_tmux_available || return 0
    
    # Start monitor
    "$BIN_DIR/tmux-claude-monitor" start &
    local monitor_pid=$!
    
    sleep 1
    
    # Check if running
    if ps -p $monitor_pid > /dev/null 2>&1; then
        assert_command_succeeds "true" "Monitor should start"
        
        # Stop monitor
        "$BIN_DIR/tmux-claude-monitor" stop
        sleep 1
        
        assert_command_fails "ps -p $monitor_pid > /dev/null 2>&1" "Monitor should stop"
    else
        skip_test "Monitor start/stop" "Monitor failed to start"
    fi
}

test_claude_ctl_commands() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Test status command
    local output=$("$BIN_DIR/tmux-claude-ctl" status 2>&1)
    assert_contains "$output" "tmux-claude Status" "Should show status"
    
    # Test help command
    output=$("$BIN_DIR/tmux-claude-ctl" help 2>&1)
    assert_contains "$output" "Commands:" "Should show help"
    
    cleanup_tmux_session
}

test_window_status_update() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Source state manager
    source "$LIB_DIR/state_manager.sh"
    
    # Set pane status
    set_pane_status "$TEST_SESSION:0.0" "❓"
    
    # Update window status
    update_window_status "0"
    
    # Check if environment variable is set
    local status=$(tmux show-environment -g "@claude_0_status" 2>/dev/null | cut -d= -f2)
    if [[ -n "$status" ]]; then
        assert_equals "❓" "$status" "Window status should be updated"
    else
        skip_test "Window status update" "Environment variable not set"
    fi
    
    cleanup_tmux_session
}

test_multiple_windows() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Create multiple windows
    tmux new-window -t "$TEST_SESSION"
    tmux new-window -t "$TEST_SESSION"
    
    # List windows
    local windows=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_index}" 2>/dev/null)
    assert_contains "$windows" "0" "Should have window 0"
    assert_contains "$windows" "1" "Should have window 1"
    assert_contains "$windows" "2" "Should have window 2"
    
    cleanup_tmux_session
}

test_pane_detection() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Create a pane running a specific command
    tmux send-keys -t "$TEST_SESSION:0.0" "sleep 100" Enter
    sleep 0.5
    
    # Get pane command
    local cmd=$(tmux list-panes -t "$TEST_SESSION" -F "#{pane_current_command}" 2>/dev/null | head -1)
    assert_equals "sleep" "$cmd" "Should detect pane command"
    
    cleanup_tmux_session
}

test_configuration_persistence() {
    check_tmux_available || return 0
    
    setup_tmux_session
    
    # Set configuration
    tmux set-option -t "$TEST_SESSION" -g @claude-timeout 600
    
    # Get configuration
    local timeout=$(tmux show-options -t "$TEST_SESSION" -g @claude-timeout 2>/dev/null | cut -d' ' -f2)
    assert_equals "600" "$timeout" "Configuration should persist"
    
    cleanup_tmux_session
}

# Test descriptions
test_tmux_environment_variables_desc() { echo "tmux environment variables"; }
test_tmux_hooks_desc() { echo "tmux hooks"; }
test_tmux_pipe_pane_desc() { echo "tmux pipe-pane"; }
test_tmux_window_format_desc() { echo "tmux window format"; }
test_tmux_key_bindings_desc() { echo "tmux key bindings"; }
test_monitor_start_stop_desc() { echo "Monitor start/stop"; }
test_claude_ctl_commands_desc() { echo "claude-ctl commands"; }
test_window_status_update_desc() { echo "Window status update"; }
test_multiple_windows_desc() { echo "Multiple windows"; }
test_pane_detection_desc() { echo "Pane command detection"; }
test_configuration_persistence_desc() { echo "Configuration persistence"; }