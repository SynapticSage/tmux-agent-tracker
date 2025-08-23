#!/bin/bash
# test_pattern_detection.sh - Tests for Claude pattern detection
# Created: 2025-08-14

# Source the pattern detection library
source "$LIB_DIR/claude_patterns.sh"

# Test fixture data
[[ -z "${CLAUDE_CHOICE_OUTPUT:-}" ]] && CLAUDE_CHOICE_OUTPUT="What would you like to do?

1) Create a new file
2) Edit an existing file
3) Run tests
4) Exit

Choose one of the options above:"

[[ -z "${CLAUDE_THINKING_OUTPUT:-}" ]] && CLAUDE_THINKING_OUTPUT="Let me analyze this code...
Thinking...
Processing your request..."

[[ -z "${CLAUDE_ERROR_OUTPUT:-}" ]] && CLAUDE_ERROR_OUTPUT="Error: Command not found
Failed to execute the requested operation
Exception: Unable to parse input"

[[ -z "${CLAUDE_COMPLETION_OUTPUT:-}" ]] && CLAUDE_COMPLETION_OUTPUT="Task completed successfully!
✓ All tests passed
Successfully created file
Finished processing"

[[ -z "${CLAUDE_ACTIVE_OUTPUT:-}" ]] && CLAUDE_ACTIVE_OUTPUT="Running tests...
Executing command: npm test
Working on your request..."

# Test functions
test_detect_choice_prompt() {
    local result=$(analyze_pane_content <(echo "$CLAUDE_CHOICE_OUTPUT"))
    assert_equals "prompt" "$result" "Should detect choice prompt"
}

test_detect_thinking_state() {
    local result=$(analyze_pane_content <(echo "$CLAUDE_THINKING_OUTPUT"))
    assert_equals "thinking" "$result" "Should detect thinking state"
}

test_detect_error_state() {
    local result=$(analyze_pane_content <(echo "$CLAUDE_ERROR_OUTPUT"))
    assert_equals "error" "$result" "Should detect error state"
}

test_detect_completion_state() {
    local result=$(analyze_pane_content <(echo "$CLAUDE_COMPLETION_OUTPUT"))
    assert_equals "complete" "$result" "Should detect completion state"
}

test_detect_active_state() {
    local result=$(analyze_pane_content <(echo "$CLAUDE_ACTIVE_OUTPUT"))
    assert_equals "active" "$result" "Should detect active state"
}

test_extract_last_prompt() {
    local prompt=$(extract_last_prompt <(echo "$CLAUDE_CHOICE_OUTPUT"))
    assert_contains "$prompt" "Choose one of" "Should extract choice prompt"
}

test_get_status_symbol() {
    assert_equals "❓" "$(get_status_symbol 'prompt')" "Prompt symbol"
    assert_equals "🤔" "$(get_status_symbol 'thinking')" "Thinking symbol"
    assert_equals "❌" "$(get_status_symbol 'error')" "Error symbol"
    assert_equals "✅" "$(get_status_symbol 'complete')" "Complete symbol"
    assert_equals "🔄" "$(get_status_symbol 'active')" "Active symbol"
    assert_equals "⏱" "$(get_status_symbol 'timeout')" "Timeout symbol"
}

test_match_choice_pattern() {
    local patterns=(
        "Choose one of:"
        "Select an option:"
        "1) Option"
        "Enter your choice"
        "Type 'yes' or 'no'"
    )
    
    for pattern in "${patterns[@]}"; do
        assert_contains "$(match_choice_pattern "$pattern")" "true" \
            "Should match choice pattern: $pattern"
    done
}

test_detect_claude_specific_prompts() {
    local claude_prompts=(
        "Would you like me to continue?"
        "Should I proceed with this change?"
        "Do you want to see more?"
        "Press Enter to continue"
    )
    
    for prompt in "${claude_prompts[@]}"; do
        local result=$(analyze_pane_content <(echo "$prompt"))
        assert_equals "prompt" "$result" "Should detect Claude prompt: $prompt"
    done
}

test_detect_stuck_animation() {
    local stuck_output="⠋ Processing...
⠙ Processing...
⠹ Processing...
⠸ Processing...
⠼ Processing...
⠴ Processing..."
    
    # This would need actual implementation in claude_patterns.sh
    # For now, we'll skip this test
    skip_test "Stuck animation detection" "Not yet implemented"
}

test_multiline_pattern_detection() {
    local multiline_choice="Please select an option:

    1. First option with a very long description that spans
       multiple lines
    2. Second option
    3. Third option
    
Enter your choice (1-3):"
    
    local result=$(analyze_pane_content <(echo "$multiline_choice"))
    assert_equals "prompt" "$result" "Should detect multiline choice prompt"
}

test_no_pattern_match() {
    local normal_output="This is just regular output
with no special patterns
that should be detected"
    
    local result=$(analyze_pane_content <(echo "$normal_output"))
    assert_equals "none" "$result" "Should return none for no pattern match"
}

test_priority_order() {
    # Test that prompt takes priority over other patterns
    local mixed_output="Error: Something went wrong
But now choose an option:
1) Retry
2) Cancel"
    
    local result=$(analyze_pane_content <(echo "$mixed_output"))
    assert_equals "prompt" "$result" "Prompt should take priority over error"
}

# Test descriptions (optional)
test_detect_choice_prompt_desc() { echo "Detect choice prompts"; }
test_detect_thinking_state_desc() { echo "Detect thinking state"; }
test_detect_error_state_desc() { echo "Detect error state"; }
test_detect_completion_state_desc() { echo "Detect completion state"; }
test_detect_active_state_desc() { echo "Detect active state"; }
test_extract_last_prompt_desc() { echo "Extract last prompt from output"; }
test_get_status_symbol_desc() { echo "Get correct status symbols"; }
test_match_choice_pattern_desc() { echo "Match various choice patterns"; }
test_detect_claude_specific_prompts_desc() { echo "Detect Claude-specific prompts"; }
test_multiline_pattern_detection_desc() { echo "Detect multiline patterns"; }
test_no_pattern_match_desc() { echo "Handle no pattern match"; }
test_priority_order_desc() { echo "Pattern priority order"; }