# tmux-claude-ext Test Suite

## Overview
Comprehensive test suite for tmux-claude-ext, covering pattern detection, state management, and tmux integration.

## Running Tests

### Run all tests
```bash
make test
```

### Run specific test categories
```bash
make test-unit        # Unit tests only
make test-integration # Integration tests only
make test-coverage    # With coverage report (requires bashcov)
```

### Run individual test files
```bash
bash tests/test_pattern_detection.sh
bash tests/test_state_management.sh
bash tests/test_tmux_integration.sh
bash tests/test_fixtures.sh
```

## Test Structure

### Test Files
- `test_runner.sh` - Main test runner framework
- `test_pattern_detection.sh` - Tests for Claude output pattern detection
- `test_state_management.sh` - Tests for state tracking and window status
- `test_tmux_integration.sh` - Integration tests with tmux
- `test_fixtures.sh` - Tests using real Claude output samples

### Fixtures
- `fixtures/claude_outputs.txt` - Real examples of Claude Code output patterns

## Test Framework Features

### Assertions
```bash
assert_equals "expected" "actual" "message"
assert_contains "haystack" "needle" "message"
assert_file_exists "/path/to/file" "message"
assert_file_contains "/path/to/file" "content" "message"
assert_command_succeeds "command" "message"
assert_command_fails "command" "message"
```

### Test Functions
- Test functions must start with `test_`
- Optional description functions ending with `_desc`
- Tests run in isolated environments

### Skip Tests
```bash
skip_test "test name" "reason"
```

## Writing New Tests

### Example Test
```bash
test_my_feature() {
    # Setup
    local input="test input"
    
    # Execute
    local result=$(my_function "$input")
    
    # Assert
    assert_equals "expected" "$result" "my_function should return expected"
}

test_my_feature_desc() {
    echo "Test my feature functionality"
}
```

## Coverage

Install bashcov for coverage reports:
```bash
gem install bashcov
make test-coverage
```

Coverage reports will be generated in `coverage/` directory.

## Continuous Integration

The test suite is designed to run in CI environments:
```bash
# GitHub Actions example
- name: Run tests
  run: make test
```

## Known Issues

- Some integration tests require an active tmux session
- Pattern detection tests may need updates as Claude's output format evolves
- Coverage tools may not work correctly with sourced shell scripts

## Contributing

When adding new features:
1. Write tests first (TDD approach)
2. Add fixtures for real-world scenarios
3. Update this README with new test descriptions
4. Ensure all tests pass before committing