#!/bin/bash
# Extended debug script - mimics actual anything.sh flow

set -uo pipefail

echo "=========================================="
echo "EXTENDED DEBUG - MIMICKING anything.sh"
echo "=========================================="
echo ""

# Check claude version
echo "Claude version:"
claude --version 2>&1 || echo "Could not get version"
echo ""

# Check available models
echo "Checking if 'sonnet' model is available:"
claude --help 2>&1 | grep -i model || echo "No model flag in help"
echo ""

# Create a realistic prompt similar to anything.sh
STEP=1
intent="install gum and make a pretty hello world"
remaining=15

read -r -d '' full_prompt <<PROMPT
You are the bash code generator anything.sh in an iterative execution loop.
 [ anything.sh - https://xertrov.github.io/anything.sh/ - Author: XertroV - License: Unlicense ]
---
SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL
CWD: $PWD
DISPLAY: $([[ -n "${WAYLAND_DISPLAY:-}" ]] && echo "wayland:$WAYLAND_DISPLAY" || [[ -n "${DISPLAY:-}" ]] && echo "x11:$DISPLAY" || echo "NONE")$([[ -n "${SSH_TTY:-}" ]] && echo " [ssh]")
INSTALLED TUI: $(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv nms chafa glow bat cmatrix slides fastfetch asciinema delta; do command -v $t &>/dev/null && printf "%s " "$t"; done)

TASK: $intent
TURNS REMAINING: $remaining (if 1-2 and this is a long experience, call _continue_journey() to add 16 more; otherwise prioritize completing or informing user why it can't be done)

OUTPUT FORMAT (exactly 3 lines, then code):
FINAL: <true if task complete, false if you need to see output first>
DESCRIPTION: <short description of this step>
BASH_CODE:
<your bash code here - no markdown, no fences>

RULES:
- If you need to check something (installed packages, file contents, etc), set FINAL: false
- When FINAL: false, your code runs and stdout/stderr is sent back to you
- When FINAL: true, task is complete and user is prompted for next task
- Don't set FINAL: true prematurely - only when the entire task/experience is genuinely complete, not after partial progress
- No markdown fences, no explanation outside the format above
- Never include XML, HTML, or markup tags in bash code
- Declare reusable helper functions globally at the top of your code block - they persist across all steps
- Then define step${STEP}() which uses those helpers, then call step${STEP} at the end
- IMPORTANT: Use absolute paths or verify paths exist before running commands. CWD may not be where you expect.
- MULTI-PART EXPERIENCES: For games, stories, or tutorials, use FINAL: false after each chapter/segment
- Your stdout/stderr feeds back to you, so output "Chapter 1 complete. Hero HP: 50" to inform your next step
- Global variables persist across steps - declare without 'local' for state (HP=100, CHAPTER=1, INVENTORY=())
- USER INPUT: Don't assume on vague tasks - ask. Prefer inline tools (gum, fzf, read -rp) that preserve context
- Full-screen TUI (whiptail/dialog) sparingly - include all context needed to decide in the dialog itself, recap after
- Set FINAL: false after asking - response appears in next feedback
- For interactive experiences: use the best available tools (TUI, colors, ASCII art) to make something impressive
- Only use TUI tools shown in INSTALLED TUI: line. To use unlisted tools, install them first (set FINAL: false, ask permission, install, then use)
- QUALITY: Don't settle for minimal - create something impressive. The user will appreciate extra polish and creativity.
- Use timing for effect: slow text reveals (pv, character-by-character), pauses for dramatic moments, animations where appropriate
- When asking for input, ensure the user can see what they need to decide - pause after animations, recap after long output
- Avoid clearing the screen, but if you need to during interactive experiences, confirm with the user first
- Generate substantial, content-rich steps: full scenes with setup, action, dialogue AND choices - not minimal fragments. LLM calls are slow.
- Build complete interactive systems in single steps: combat loops, dialogue trees, puzzles should run to completion - don't fragment across iterations without good reason
- For complex experiences: use first 1-2 steps to create utility functions (UI helpers, combat engine, state display) so later steps are richer and more efficient. Leave design notes in comments.
- For long experiences: call _continue_journey() at chapter/quest completion to add 16 more iterations

EXAMPLE (checking before installing):
FINAL: false
DESCRIPTION: Check if package is installed
BASH_CODE:
step${STEP}() { command -v figlet &>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"; }
step${STEP}

EXAMPLE (final step after seeing output):
FINAL: true
DESCRIPTION: Install figlet
BASH_CODE:
step${STEP}() { sudo pacman -S --noconfirm figlet && figlet "Hello"; }
step${STEP}
PROMPT

echo "Prompt length: ${#full_prompt} characters"
echo ""

# Test the exact command from anything.sh
echo "=========================================="
echo "TEST: Exact anything.sh command"
echo "=========================================="
echo "Command: claude -p '\$full_prompt' --model sonnet --dangerously-skip-permissions 2>/dev/null"
echo ""

# First, let's see what happens WITHOUT 2>/dev/null to catch any errors
echo "--- Running WITHOUT stderr redirect (to see errors) ---"
response_stderr=$(claude -p "$full_prompt" --model sonnet --dangerously-skip-permissions </dev/null 2>&1) || true
exit_code_stderr=$?
echo "Exit code: $exit_code_stderr"
echo "Response length: ${#response_stderr}"
echo "Response preview (first 500 chars):"
echo "${response_stderr:0:500}"
echo ""

# Check for empty response
echo "--- Checking for empty response ---"
if [[ -z "$response_stderr" ]]; then
    echo "ERROR: Empty response detected!"
    
    # Try to diagnose why
    echo ""
    echo "Diagnosing..."
    
    # Check if ANTHROPIC_API_KEY is set
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "ANTHROPIC_API_KEY is NOT set in environment"
    else
        echo "ANTHROPIC_API_KEY is set (starts with: ${ANTHROPIC_API_KEY:0:10}...)"
    fi
    
    # Check for claude auth
    echo ""
    echo "Checking claude authentication status:"
    claude auth status 2>&1 || echo "Could not check auth status"
    
else
    echo "Response is NOT empty (${#response_stderr} characters)"
    
    # Parse response like anything.sh does
    echo ""
    echo "--- Parsing response (like anything.sh does) ---"
    is_final=$(echo "$response_stderr" | grep -i '^FINAL:' | head -1 | sed 's/^FINAL:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
    description=$(echo "$response_stderr" | grep -i '^DESCRIPTION:' | head -1 | sed 's/^DESCRIPTION:[[:space:]]*//')
    code=$(echo "$response_stderr" | sed -n '/^BASH_CODE:/,$ { /^BASH_CODE:/d; p }')
    
    echo "is_final: '$is_final'"
    echo "description: '$description'"
    echo "code length: ${#code}"
    echo "code preview:"
    echo "${code:0:200}"
fi

echo ""
echo "=========================================="
echo "ALTERNATIVE TEST: Using -p with echo pipe"
echo "=========================================="
# Some CLI tools work better with piped input
echo "$full_prompt" | claude -p --model sonnet --dangerously-skip-permissions 2>&1 || true

echo ""
echo "=========================================="
echo "COMPLETE"
echo "=========================================="
