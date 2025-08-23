#!/bin/bash
# test_simple.sh - Simple test to verify basic functionality
# Created: 2025-08-07

source "$(dirname "$0")/../lib/claude_patterns.sh"

echo "Testing basic pattern detection..."

# Test 1
if detect_prompt_needed "Choose one of:"; then
    echo "✓ Test 1: Detect 'Choose one of:' - PASSED"
else
    echo "✗ Test 1: Detect 'Choose one of:' - FAILED"
fi

# Test 2
if detect_prompt_needed "Normal text"; then
    echo "✗ Test 2: Should not detect normal text - FAILED"
else
    echo "✓ Test 2: Should not detect normal text - PASSED"
fi

# Test 3
if detect_error "Error: something went wrong"; then
    echo "✓ Test 3: Detect error - PASSED"
else
    echo "✗ Test 3: Detect error - FAILED"
fi

# Test 4
if detect_completion "Successfully completed"; then
    echo "✓ Test 4: Detect completion - PASSED"
else
    echo "✗ Test 4: Detect completion - FAILED"
fi

echo "Basic tests complete!"