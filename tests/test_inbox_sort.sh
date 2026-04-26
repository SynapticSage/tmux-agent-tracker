#!/usr/bin/env bash
# test_inbox_sort.sh — unit tests for inbox.sh's sort step.
#
# Feeds synthetic TSV rows to `inbox.sh --sort-stdin` and asserts the
# output ordering matches expectations. Pure data transformation —
# does not touch tmux or any cache file, so this runs anywhere.
#
# Run: ./tests/test_inbox_sort.sh
# Exits 0 on all-pass, 1 on first failure.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inbox="$script_dir/../inbox.sh"

PASS=0
FAIL=0

# Each row is TSV: eff_priority, pane_id, target, state, mark, visibility, window_name
# Helper to build an input fixture from compact strings.
row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

# Run a test: feed input, capture pane_id column from each output row.
# Compare to expected pane_id sequence.
expect_order() {
  local label="$1"; shift
  local expected="$1"; shift
  local input="$1"

  local actual
  actual=$(printf '%s' "$input" | "$inbox" --sort-stdin | awk -F'\t' '{printf "%s ", $2}' | sed 's/ *$//')

  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $label"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

# ---------------------------------------------------------------------
# Test 1: pure state precedence — no priorities set, no deferred.
# Order should be needs-input < done < new < idle < working.
# ---------------------------------------------------------------------
input1=$(printf '%s\n' \
  "$(row 100 %1 main:0.0 working ''   active win-a)" \
  "$(row 100 %2 main:1.0 needs-input '' active win-b)" \
  "$(row 100 %3 main:2.0 idle ''      active win-c)" \
  "$(row 100 %4 main:3.0 done ''      active win-d)" \
  "$(row 100 %5 main:4.0 new  ''      active win-e)")
expect_order "pure state precedence" "%2 %4 %5 %3 %1" "$input1"

# ---------------------------------------------------------------------
# Test 2: priority overrides state.
# %1 has priority 1 + idle; %2 has priority 100 + needs-input.
# Lower priority wins, so %1 sorts first despite weaker state.
# ---------------------------------------------------------------------
input2=$(printf '%s\n' \
  "$(row 100 %2 main:1.0 needs-input '' active win-b)" \
  "$(row 1   %1 main:0.0 idle ''        active win-a)")
expect_order "priority overrides state" "%1 %2" "$input2"

# ---------------------------------------------------------------------
# Test 3: deferred sorts last regardless of priority.
# %1 deferred + priority 1, %2 active + priority 100.
# Visibility tier dominates priority and state.
# ---------------------------------------------------------------------
input3=$(printf '%s\n' \
  "$(row 1   %1 main:0.0 needs-input '' deferred win-a)" \
  "$(row 100 %2 main:1.0 idle ''        active   win-b)")
expect_order "deferred sorts last regardless of priority" "%2 %1" "$input3"

# ---------------------------------------------------------------------
# Test 4: ignored excluded by default.
# Synthetic rows include a row with visibility=ignored. The sort-only
# mode doesn't filter (filtering happens upstream in inbox.sh's
# collect_rows). But it DOES rank ignored after deferred. So a sort-
# only test verifies the rank, not the exclusion. Exclusion is
# tested in the smoke flow.
# ---------------------------------------------------------------------
input4=$(printf '%s\n' \
  "$(row 100 %2 main:1.0 idle ''        active   win-b)" \
  "$(row 100 %3 main:2.0 working ''     ignored  win-c)" \
  "$(row 100 %1 main:0.0 needs-input '' deferred win-a)")
expect_order "active < deferred < ignored" "%2 %1 %3" "$input4"

# ---------------------------------------------------------------------
# Test 5: tiebreaker — same priority, same state, different sessions.
# Sort by session name asc, then window, then pane.
# ---------------------------------------------------------------------
input5=$(printf '%s\n' \
  "$(row 100 %3 zeta:0.0 idle '' active win-z)" \
  "$(row 100 %1 alpha:1.0 idle '' active win-a)" \
  "$(row 100 %2 alpha:0.0 idle '' active win-b)")
expect_order "session/window/pane tiebreak" "%2 %1 %3" "$input5"

# ---------------------------------------------------------------------
# Test 6: malformed eff_priority falls back to 100.
# ---------------------------------------------------------------------
input6=$(printf '%s\n' \
  "$(row 50 %1 a:0.0 working '' active w1)" \
  "$(row XX %2 a:1.0 working '' active w2)")
expect_order "malformed priority defaults to 100" "%1 %2" "$input6"

# ---------------------------------------------------------------------
# Test 7: malformed target sorts to end deterministically.
# ---------------------------------------------------------------------
input7=$(printf '%s\n' \
  "$(row 100 %2 garbage idle '' active w-bad)" \
  "$(row 100 %1 a:0.0 idle '' active w-good)")
expect_order "malformed target sorts to end" "%1 %2" "$input7"

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
