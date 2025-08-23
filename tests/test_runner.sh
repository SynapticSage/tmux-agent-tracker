#!/bin/bash
# test_runner.sh - Test runner for tmux-claude-ext
# Created: 2025-08-14

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LIB_DIR="$PROJECT_DIR/lib"
readonly BIN_DIR="$PROJECT_DIR/bin"

# Test configuration
readonly TEST_TEMP_DIR="/tmp/tmux-claude-test-$$"
readonly TEST_STATE_DIR="$TEST_TEMP_DIR/state"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_STATE_DIR"
    export STATE_DIR="$TEST_STATE_DIR"
    export TMUX_CLAUDE_TEST_MODE=1
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_TEMP_DIR"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo -e "${RED}✗ Assertion failed: $message${NC}"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}✗ Assertion failed: $message${NC}"
        echo "  String: '$haystack'"
        echo "  Should contain: '$needle'"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        echo -e "${RED}✗ Assertion failed: $message${NC}"
        echo "  File not found: '$file'"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local content="$2"
    local message="${3:-}"
    
    if grep -q "$content" "$file" 2>/dev/null; then
        return 0
    else
        echo -e "${RED}✗ Assertion failed: $message${NC}"
        echo "  File '$file' should contain: '$content'"
        return 1
    fi
}

assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command should succeed}"
    
    if eval "$command" &>/dev/null; then
        return 0
    else
        echo -e "${RED}✗ Assertion failed: $message${NC}"
        echo "  Command failed: '$command'"
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local message="${2:-Command should fail}"
    
    if ! eval "$command" &>/dev/null; then
        return 0
    else
        echo -e "${RED}✗ Assertion failed: $message${NC}"
        echo "  Command succeeded but should have failed: '$command'"
        return 1
    fi
}

# Run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -n "Running $test_name... "
    
    # Create clean test environment for each test
    rm -rf "$TEST_STATE_DIR"
    mkdir -p "$TEST_STATE_DIR"
    
    if $test_function; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Skip a test
skip_test() {
    local test_name="$1"
    local reason="${2:-}"
    
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}⊘ Skipping $test_name${NC}"
    if [[ -n "$reason" ]]; then
        echo "  Reason: $reason"
    fi
}

# Run test suite
run_test_suite() {
    local suite_name="$1"
    local suite_file="$2"
    
    echo
    echo "=== $suite_name ==="
    echo
    
    # Source the test suite
    source "$suite_file"
    
    # Run all test functions (those starting with test_)
    for test_func in $(declare -F | awk '{print $3}' | grep "^test_" | grep -v "_desc"); do
        # Get description if available
        local desc_func="${test_func}_desc"
        local test_desc=""
        if declare -f "$desc_func" &>/dev/null; then
            test_desc=$($desc_func)
        else
            test_desc=$test_func
        fi
        
        run_test "$test_desc" "$test_func"
    done
    
    # Clean up test functions to avoid conflicts
    for test_func in $(declare -F | awk '{print $3}' | grep "^test_"); do
        unset -f "$test_func"
    done
}

# Print test summary
print_summary() {
    echo
    echo "==================================="
    echo "Test Summary"
    echo "==================================="
    echo -e "Tests run:     $TESTS_RUN"
    echo -e "Tests passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Tests skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo "==================================="
    echo "tmux-claude-ext Test Suite"
    echo "==================================="
    
    # Setup
    setup_test_env
    trap cleanup_test_env EXIT
    
    # Determine which test files to run
    local test_files=()
    
    if [[ $# -gt 0 ]]; then
        # Specific test files were requested
        for arg in "$@"; do
            local test_file="$SCRIPT_DIR/$arg"
            if [[ ! -f "$test_file" ]]; then
                test_file="$SCRIPT_DIR/test_$arg"
            fi
            if [[ -f "$test_file" ]]; then
                test_files+=("$test_file")
            else
                echo "Warning: Test file not found: $arg"
            fi
        done
    else
        # Run all test files
        for test_file in "$SCRIPT_DIR"/test_*.sh; do
            if [[ -f "$test_file" ]] && [[ "$test_file" != *"test_runner.sh" ]]; then
                test_files+=("$test_file")
            fi
        done
    fi
    
    # Run test suites
    for test_file in "${test_files[@]}"; do
        suite_name=$(basename "$test_file" .sh | sed 's/test_//' | sed 's/_/ /g')
        run_test_suite "$suite_name" "$test_file"
    done
    
    # Summary
    print_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi