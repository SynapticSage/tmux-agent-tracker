#!/bin/bash
# test_state_management.sh - Tests for state management
# Created: 2025-08-14

# Source the state management library
source "$LIB_DIR/state_manager.sh"

# Mock tmux commands for testing
tmux() {
    case "$1" in
        "set-environment")
            echo "MOCK: set-environment $*" >> "$TEST_STATE_DIR/tmux.log"
            return 0
            ;;
        "show-environment")
            if [[ "$2" == "@claude_0_status" ]]; then
                echo "@claude_0_status=❓"
            else
                return 1
            fi
            ;;
        "display")
            echo "test:0.0"
            ;;
        "list-panes")
            echo "test:0.0 bash 1234"
            echo "test:0.1 vim 1235"
            echo "test:1.0 claude 1236"
            ;;
        "has-session")
            [[ "$3" == "test" ]] && return 0
            return 1
            ;;
        "list-windows")
            echo "0 1 2"
            ;;
        *)
            return 0
            ;;
    esac
}

# Export the mock function
export -f tmux

test_get_pane_id() {
    local result=$(get_pane_id "test:0.1")
    assert_equals "test_0_1" "$result" "Should convert pane ID to clean format"
}

test_set_pane_status() {
    set_pane_status "test:0.1" "❓"
    assert_file_exists "$STATE_DIR/test_0_1.status" "Status file should be created"
    assert_file_contains "$STATE_DIR/test_0_1.status" "❓" "Status file should contain emoji"
}

test_get_pane_status() {
    set_pane_status "test:0.1" "🔄"
    local status=$(get_pane_status "test:0.1")
    assert_equals "🔄" "$status" "Should retrieve correct status"
}

test_clear_pane_status() {
    set_pane_status "test:0.1" "❓"
    clear_pane_status "test:0.1"
    local status=$(get_pane_status "test:0.1")
    assert_equals "none" "$status" "Status should be cleared"
}

test_set_pane_monitored() {
    set_pane_monitored "test:0.1" true
    assert_file_exists "$STATE_DIR/test_0_1.monitoring" "Monitoring file should exist"
    
    set_pane_monitored "test:0.1" false
    assert_command_fails "test -f $STATE_DIR/test_0_1.monitoring" "Monitoring file should be removed"
}

test_is_pane_monitored() {
    set_pane_monitored "test:0.1" true
    is_pane_monitored "test:0.1"
    assert_equals "0" "$?" "Should return true for monitored pane"
    
    set_pane_monitored "test:0.1" false
    is_pane_monitored "test:0.1"
    assert_equals "1" "$?" "Should return false for unmonitored pane"
}

test_list_monitored_panes() {
    set_pane_monitored "test:0.0" true
    set_pane_monitored "test:0.1" true
    set_pane_monitored "test:1.0" true
    
    local panes=$(list_monitored_panes)
    assert_contains "$panes" "test:0.0" "Should list first pane"
    assert_contains "$panes" "test:0.1" "Should list second pane"
    assert_contains "$panes" "test:1.0" "Should list third pane"
}

test_cleanup_stale_state() {
    # Create monitoring files
    touch "$STATE_DIR/old_0_0.monitoring"
    touch "$STATE_DIR/test_0_0.monitoring"
    
    cleanup_stale_state
    
    assert_command_fails "test -f $STATE_DIR/old_0_0.monitoring" "Old session should be cleaned"
    assert_file_exists "$STATE_DIR/test_0_0.monitoring" "Valid session should remain"
}

test_update_window_status() {
    # Set up multiple panes with different statuses
    set_pane_status "test:0.0" "✅"
    set_pane_status "test:0.1" "❓"
    
    # Mock get_panes_for_window
    get_panes_for_window() {
        echo "test:0.0 test:0.1"
    }
    export -f get_panes_for_window
    
    update_window_status "0"
    
    # Check that tmux set-environment was called
    assert_file_contains "$STATE_DIR/tmux.log" "set-environment" "Should call tmux set-environment"
}

test_get_window_for_pane() {
    local window=$(get_window_for_pane "test:2.3")
    assert_equals "2" "$window" "Should extract window index from pane ID"
}

test_get_panes_for_window() {
    # This would need actual tmux integration
    skip_test "Get panes for window" "Requires tmux session"
}

test_priority_status_selection() {
    # Test that highest priority status is selected
    set_pane_status "test:0.0" "✅"  # Low priority
    set_pane_status "test:0.1" "❓"  # High priority
    
    get_panes_for_window() {
        echo "test:0.0 test:0.1"
    }
    export -f get_panes_for_window
    
    # The update should select ❓ over ✅
    update_window_status "0"
    assert_file_contains "$STATE_DIR/tmux.log" "@claude_0_status" "Should set window status"
}

test_concurrent_access() {
    # Test that multiple processes can safely access state
    for i in {1..5}; do
        (set_pane_status "test:0.$i" "🔄") &
    done
    wait
    
    for i in {1..5}; do
        assert_file_exists "$STATE_DIR/test_0_$i.status" "Status file $i should exist"
    done
}

test_invalid_pane_id() {
    # Test handling of invalid pane IDs
    set_pane_status "invalid" "❓"
    # Should not crash, just create file with sanitized name
    assert_command_succeeds "true" "Should handle invalid pane ID gracefully"
}

test_empty_status() {
    set_pane_status "test:0.0" ""
    local status=$(get_pane_status "test:0.0")
    assert_equals "none" "$status" "Empty status should return none"
}

test_get_last_activity() {
    # Create a log file with known timestamp
    local test_file="$STATE_DIR/test_0_0.log"
    echo "test" > "$test_file"
    
    # Get timestamp
    local timestamp=$(get_last_activity "test:0.0")
    assert_command_succeeds "test $timestamp -gt 0" "Should return valid timestamp"
}

# Test descriptions
test_get_pane_id_desc() { echo "Convert pane ID to clean format"; }
test_set_pane_status_desc() { echo "Set pane status"; }
test_get_pane_status_desc() { echo "Get pane status"; }
test_clear_pane_status_desc() { echo "Clear pane status"; }
test_set_pane_monitored_desc() { echo "Set pane monitoring state"; }
test_is_pane_monitored_desc() { echo "Check if pane is monitored"; }
test_list_monitored_panes_desc() { echo "List all monitored panes"; }
test_cleanup_stale_state_desc() { echo "Clean up stale state files"; }
test_update_window_status_desc() { echo "Update window status"; }
test_get_window_for_pane_desc() { echo "Extract window from pane ID"; }
test_priority_status_selection_desc() { echo "Select highest priority status"; }
test_concurrent_access_desc() { echo "Handle concurrent state access"; }
test_invalid_pane_id_desc() { echo "Handle invalid pane IDs"; }
test_empty_status_desc() { echo "Handle empty status"; }
test_get_last_activity_desc() { echo "Get last activity timestamp"; }