#!/bin/bash
# Diagnostic script for "[error] empty response" issue

set -uo pipefail

echo "=========================================="
echo "CLAUDE CLI DIAGNOSTIC FOR EMPTY RESPONSE"
echo "=========================================="
echo ""

# Check 1: Environment
echo "--- Check 1: Environment ---"
echo "ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-NOT SET}"
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "  Key starts with: ${ANTHROPIC_API_KEY:0:15}..."
    echo "  Key length: ${#ANTHROPIC_API_KEY}"
fi
echo ""

# Check 2: Claude CLI
echo "--- Check 2: Claude CLI ---"
which claude && ls -la $(which claude)
claude --version 2>&1
echo ""

# Check 3: Auth status
echo "--- Check 3: Auth Status ---"
claude auth status 2>&1 || echo "Could not check auth status"
echo ""

# Check 4: Test with minimal prompt
echo "--- Check 4: Minimal Prompt Test ---"
minimal_prompt="Say 'hello world'"
echo "Testing with minimal prompt: '$minimal_prompt'"
minimal_response=$(claude -p "$minimal_prompt" --model sonnet --dangerously-skip-permissions 2>&1) || true
echo "Response length: ${#minimal_response}"
echo "Response: '$minimal_response'"
if [[ -z "$minimal_response" ]]; then
    echo "FAIL: Empty response to minimal prompt"
else
    echo "OK: Got response"
fi
echo ""

# Check 5: Test without model flag
echo "--- Check 5: Test without --model flag ---"
no_model_response=$(claude -p "$minimal_prompt" --dangerously-skip-permissions 2>&1) || true
echo "Response length: ${#no_model_response}"
if [[ -z "$no_model_response" ]]; then
    echo "FAIL: Empty response without --model flag"
else
    echo "OK: Got response (${#no_model_response} chars)"
fi
echo ""

# Check 6: Test with verbose output
echo "--- Check 6: Test with verbose flag ---"
claude -p "$minimal_prompt" --model sonnet --dangerously-skip-permissions --verbose 2>&1 | head -50 || true
echo ""

# Check 7: Check for common errors in stderr
echo "--- Check 7: Stderr analysis ---"
stderr_output=$(claude -p "$minimal_prompt" --model sonnet --dangerously-skip-permissions 2>&1 >/dev/null) || true
echo "Stderr output: '$stderr_output'"
if [[ -n "$stderr_output" ]]; then
    echo "WARNING: There is stderr output! This might indicate an error."
fi
echo ""

# Check 8: Check if specific model exists
echo "--- Check 8: Available Models ---"
echo "Testing different model names..."
for model in "sonnet" "claude-sonnet-4-5-20250929" "opus" "haiku"; do
    response=$(claude -p "Say hello" --model "$model" --dangerously-skip-permissions 2>&1) || true
    if [[ -n "$response" ]]; then
        echo "  Model '$model': OK (${#response} chars)"
    else
        echo "  Model '$model': EMPTY RESPONSE"
    fi
done
echo ""

# Check 9: Network connectivity
echo "--- Check 9: Network ---"
ping -c 1 api.anthropic.com 2>&1 | head -3 || echo "Could not ping api.anthropic.com"
curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com/v1/ 2>&1 | head -1 || echo "Could not reach API"
echo ""

# Check 10: Timeout test
echo "--- Check 10: Timeout Test ---"
echo "Testing if claude hangs (10 second timeout)..."
timeout 10 claude -p "Say hello" --model sonnet --dangerously-skip-permissions 2>&1 || echo "Command timed out or failed (exit code: $?)"
echo ""

echo "=========================================="
echo "DIAGNOSTIC COMPLETE"
echo "=========================================="
echo ""
echo "Common causes of empty response:"
echo "  1. ANTHROPIC_API_KEY not set or invalid"
echo "  2. Claude CLI not authenticated (run: claude auth login)"
echo "  3. Network connectivity issues"
echo "  4. Rate limiting or account issues"
echo "  5. Model name incorrect (try without --model flag)"
echo "  6. API key doesn't have access to specified model"
echo ""
