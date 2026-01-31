#!/bin/bash
# Debug script for claude CLI empty response issue

set -euo pipefail

echo "=========================================="
echo "CLAUDE CLI DEBUG SCRIPT"
echo "=========================================="
echo ""

# Create a simple test prompt similar to anything.sh
test_prompt="You are a helpful assistant. Respond with exactly this text: FINAL: true
DESCRIPTION: Test response
BASH_CODE:
echo 'Hello from claude'"

echo "Test prompt:"
echo "---"
echo "$test_prompt"
echo "---"
echo ""

# Test 1: Original command with </dev/null redirect
echo "=========================================="
echo "TEST 1: With </dev/null redirect (original anything.sh style)"
echo "Command: claude -p --model sonnet --dangerously-skip-permissions '\$test_prompt' </dev/null 2>&1"
echo "=========================================="
response1=$(claude -p --model sonnet --dangerously-skip-permissions "$test_prompt" </dev/null 2>&1) || true
exit_code1=$?
echo "Exit code: $exit_code1"
echo "Response length: ${#response1} chars"
echo "Response:"
echo "'$response1'"
echo ""

# Test 2: Without </dev/null redirect
echo "=========================================="
echo "TEST 2: WITHOUT </dev/null redirect"
echo "Command: claude -p --model sonnet --dangerously-skip-permissions '\$test_prompt' 2>&1"
echo "=========================================="
response2=$(claude -p --model sonnet --dangerously-skip-permissions "$test_prompt" 2>&1) || true
exit_code2=$?
echo "Exit code: $exit_code2"
echo "Response length: ${#response2} chars"
echo "Response:"
echo "'$response2'"
echo ""

# Test 3: Capture stdout and stderr separately WITH </dev/null
echo "=========================================="
echo "TEST 3: Separate stdout/stderr WITH </dev/null"
echo "=========================================="
stdout_file=$(mktemp)
stderr_file=$(mktemp)
claude -p --model sonnet --dangerously-skip-permissions "$test_prompt" </dev/null > "$stdout_file" 2> "$stderr_file" || true
exit_code3=$?
stdout3=$(cat "$stdout_file")
stderr3=$(cat "$stderr_file")
rm -f "$stdout_file" "$stderr_file"
echo "Exit code: $exit_code3"
echo "Stdout length: ${#stdout3} chars"
echo "Stdout: '$stdout3'"
echo "Stderr length: ${#stderr3} chars"
echo "Stderr: '$stderr3'"
echo ""

# Test 4: Capture stdout and stderr separately WITHOUT </dev/null
echo "=========================================="
echo "TEST 4: Separate stdout/stderr WITHOUT </dev/null"
echo "=========================================="
stdout_file=$(mktemp)
stderr_file=$(mktemp)
claude -p --model sonnet --dangerously-skip-permissions "$test_prompt" > "$stdout_file" 2> "$stderr_file" || true
exit_code4=$?
stdout4=$(cat "$stdout_file")
stderr4=$(cat "$stderr_file")
rm -f "$stdout_file" "$stderr_file"
echo "Exit code: $exit_code4"
echo "Stdout length: ${#stdout4} chars"
echo "Stdout: '$stdout4'"
echo "Stderr length: ${#stderr4} chars"
echo "Stderr: '$stderr4'"
echo ""

# Test 5: Try without the --model flag (use default)
echo "=========================================="
echo "TEST 5: Without --model flag (use default)"
echo "=========================================="
response5=$(claude -p --dangerously-skip-permissions "$test_prompt" </dev/null 2>&1) || true
exit_code5=$?
echo "Exit code: $exit_code5"
echo "Response length: ${#response5} chars"
echo "Response:"
echo "'$response5'"
echo ""

# Test 6: Check if claude binary exists and is executable
echo "=========================================="
echo "TEST 6: Claude binary check"
echo "=========================================="
which claude && ls -la $(which claude) || echo "claude not found in PATH"
echo ""

# Test 7: Try with opencode instead (as a control test)
echo "=========================================="
echo "TEST 7: Control test - check if opencode works"
echo "=========================================="
if command -v opencode &> /dev/null; then
    response7=$(opencode run "$test_prompt" 2>&1) || true
    exit_code7=$?
    echo "Exit code: $exit_code7"
    echo "Response length: ${#response7} chars"
    echo "Response: '$response7'"
else
    echo "opencode not available"
fi
echo ""

# Summary
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Test 1 (with </dev/null): exit=$exit_code1, len=${#response1}"
echo "Test 2 (no </dev/null): exit=$exit_code2, len=${#response2}"
echo "Test 3 (sep, with </dev/null): exit=$exit_code3, stdout=${#stdout3}, stderr=${#stderr3}"
echo "Test 4 (sep, no </dev/null): exit=$exit_code4, stdout=${#stdout4}, stderr=${#stderr4}"
echo "Test 5 (no --model): exit=$exit_code5, len=${#response5}"
