#!/bin/bash
# test_fixtures.sh - Tests using real Claude output fixtures
# Created: 2025-08-14

# Source the pattern detection library
source "$LIB_DIR/claude_patterns.sh"

# Load fixtures
readonly FIXTURES_FILE="$SCRIPT_DIR/fixtures/claude_outputs.txt"

# Helper to extract fixture by name
get_fixture() {
    local name="$1"
    local in_fixture=0
    local content=""
    
    while IFS= read -r line; do
        if [[ "$line" == "[FIXTURE: $name]" ]]; then
            in_fixture=1
        elif [[ "$line" == "[END]" ]] && [[ $in_fixture -eq 1 ]]; then
            echo "$content"
            return 0
        elif [[ $in_fixture -eq 1 ]]; then
            if [[ -n "$content" ]]; then
                content="$content"$'\n'"$line"
            else
                content="$line"
            fi
        fi
    done < "$FIXTURES_FILE"
    
    return 1
}

# Test each fixture type
test_fixture_choice_simple() {
    local content=$(get_fixture "choice_simple")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "prompt" "$result" "Should detect simple choice prompt"
}

test_fixture_choice_continue() {
    local content=$(get_fixture "choice_continue")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "prompt" "$result" "Should detect continue choice"
}

test_fixture_choice_yes_no() {
    local content=$(get_fixture "choice_yes_no")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "prompt" "$result" "Should detect yes/no prompt"
}

test_fixture_thinking_dots() {
    local content=$(get_fixture "thinking_dots")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "thinking" "$result" "Should detect thinking state"
}

test_fixture_thinking_analyzing() {
    local content=$(get_fixture "thinking_analyzing")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "thinking" "$result" "Should detect analyzing state"
}

test_fixture_active_tests() {
    local content=$(get_fixture "active_tests")
    local result=$(analyze_pane_content <(echo "$content"))
    # This fixture contains "PASS" and "✓" which are completion indicators
    assert_equals "complete" "$result" "Should detect test completion"
}

test_fixture_active_command() {
    local content=$(get_fixture "active_command")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "active" "$result" "Should detect executing command"
}

test_fixture_error_command() {
    local content=$(get_fixture "error_command")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "error" "$result" "Should detect command error"
}

test_fixture_error_exception() {
    local content=$(get_fixture "error_exception")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "error" "$result" "Should detect exception"
}

test_fixture_complete_success() {
    local content=$(get_fixture "complete_success")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "complete" "$result" "Should detect successful completion"
}

test_fixture_complete_done() {
    local content=$(get_fixture "complete_done")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "complete" "$result" "Should detect done state"
}

test_fixture_mixed_error_then_choice() {
    local content=$(get_fixture "mixed_error_then_choice")
    local result=$(analyze_pane_content <(echo "$content"))
    # Prompt should take priority over error
    assert_equals "prompt" "$result" "Prompt should override error"
}

test_fixture_mixed_complete_then_choice() {
    local content=$(get_fixture "mixed_complete_then_choice")
    local result=$(analyze_pane_content <(echo "$content"))
    # Prompt should take priority over completion
    assert_equals "prompt" "$result" "Prompt should override completion"
}

test_fixture_complex_multiline_choice() {
    local content=$(get_fixture "complex_multiline_choice")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "prompt" "$result" "Should detect complex multiline choice"
}

test_fixture_stuck_waiting() {
    local content=$(get_fixture "stuck_waiting")
    # This would be detected as timeout by checking timestamps
    # For now, we'll check if it's recognized as potentially stuck
    local lines=$(echo "$content" | grep -c "Waiting")
    assert_command_succeeds "test $lines -gt 3" "Should have repeated waiting lines"
}

test_fixture_claude_continue() {
    local content=$(get_fixture "claude_continue")
    local result=$(analyze_pane_content <(echo "$content"))
    assert_equals "prompt" "$result" "Should detect Claude continue prompt"
}

test_all_fixtures_loadable() {
    local fixture_count=$(grep -c "^\[FIXTURE:" "$FIXTURES_FILE")
    assert_command_succeeds "test $fixture_count -gt 10" "Should have multiple fixtures"
}

test_fixture_extraction() {
    # Test that fixture extraction works correctly
    local content=$(get_fixture "choice_simple")
    assert_contains "$content" "What would you like me to do?" "Should extract fixture content"
    assert_contains "$content" "Please enter your choice:" "Should include full fixture"
}

# Test descriptions
test_fixture_choice_simple_desc() { echo "Simple choice prompt fixture"; }
test_fixture_choice_continue_desc() { echo "Continue choice fixture"; }
test_fixture_choice_yes_no_desc() { echo "Yes/no prompt fixture"; }
test_fixture_thinking_dots_desc() { echo "Thinking dots fixture"; }
test_fixture_thinking_analyzing_desc() { echo "Analyzing fixture"; }
test_fixture_active_tests_desc() { echo "Test completion fixture"; }
test_fixture_active_command_desc() { echo "Executing command fixture"; }
test_fixture_error_command_desc() { echo "Command error fixture"; }
test_fixture_error_exception_desc() { echo "Exception fixture"; }
test_fixture_complete_success_desc() { echo "Success completion fixture"; }
test_fixture_complete_done_desc() { echo "Done state fixture"; }
test_fixture_mixed_error_then_choice_desc() { echo "Mixed error/choice fixture"; }
test_fixture_mixed_complete_then_choice_desc() { echo "Mixed complete/choice fixture"; }
test_fixture_complex_multiline_choice_desc() { echo "Complex multiline fixture"; }
test_fixture_stuck_waiting_desc() { echo "Stuck waiting fixture"; }
test_fixture_claude_continue_desc() { echo "Claude continue fixture"; }
test_all_fixtures_loadable_desc() { echo "All fixtures loadable"; }
test_fixture_extraction_desc() { echo "Fixture extraction works"; }