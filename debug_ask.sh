#!/bin/bash
# Debug version of _ask function from anything.sh

set -uo pipefail

SELF="/home/xertrov/src/anything.sh/dist/claude/full/anything.sh"
STEP=0
MAX_ITER=160
BONUS_ITER=0
AGENT_MODE=0
_OUT="/tmp/anything_out_$$"

# ─────────────────────────────────────────────────────────────────
# DEBUG ASK: Query Claude with full debugging output
# ─────────────────────────────────────────────────────────────────
_ask_debug() {
    local intent="$1"
    local feedback="${2:-}"
    local remaining="${3:-?}"
    local agent_context=""
    local AGENT_MODE_RULE=""
    local script_content
    script_content=$(cat "$SELF")
    if [[ $AGENT_MODE -eq 1 ]]; then
        agent_context="

AGENT MODE: This script is running with -a/--agent flag (non-interactive).
- You cannot use 'read', 'gum', 'fzf', or any interactive tools - the user cannot respond
- Do not prompt for input or confirmation
- Your FINAL: true step should output a summary via echo of what was created/modified
- This summary will be captured and returned to the parent script
- Example: echo 'Created fib() function in ./lib/math.sh'"
    else
        AGENT_MODE_RULE="- AGENT MODE: The script supports -a/--agent flag for non-interactive execution. When generating code that will call anything.sh with -a/--agent, your FINAL: true step should echo a summary of what was created/modified.
- In the first step, discover available TUI utilities AND call \`<tool> --help\` on each to understand their options (colors, fonts, flags) before building the experience"
    fi
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
You are the bash code generator anything.sh in an iterative execution loop.
 [ anything.sh - https://xertrov.github.io/anything.sh/ - Author: XertroV - License: Unlicense ]
---

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
- AVOID dark gray colors (e.g., [90m, "bright black") - they are invisible on black terminals. Use bold white ([1;37m), bright colors ([96m cyan, [93m yellow), or standard colors instead.
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
check_deps() { command -v figlet &>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"; }
check_deps

EXAMPLE (final step after seeing output):
FINAL: true
DESCRIPTION: Install figlet
BASH_CODE:
install_figlet() { sudo pacman -S --noconfirm figlet && figlet "Hello"; }
install_figlet

${ANYTHING_EXTRA:+
=== EXTRA CONTEXT ===
$ANYTHING_EXTRA
}

=== CURRENT SCRIPT CONTENT ===
${script_content}

=== CURRENT SYSTEM ===
SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL
CWD: $PWD
DISPLAY: $([[ -n "${WAYLAND_DISPLAY:-}" ]] && echo "wayland:$WAYLAND_DISPLAY" || [[ -n "${DISPLAY:-}" ]] && echo "x11:$DISPLAY" || echo "NONE")$([[ -n "${SSH_TTY:-}" ]] && echo " [ssh]")
INSTALLED TUI: $(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv nms chafa glow bat cmatrix slides fastfetch asciinema delta; do command -v $t &>/dev/null && printf "%s " "$t"; done)

STEP ${STEP} INSTRUCTIONS:
${AGENT_MODE_RULE}

TASK: $intent
TURNS REMAINING: $remaining (if 1-2 and this is a long experience, call _continue_journey() to add 16 more; otherwise prioritize completing or informing user why it can't be done)
$feedback$agent_context
PROMPT

    echo "=== DEBUG: About to run claude command ===" >&2
    echo "Command: claude -p [prompt truncated] --model sonnet --dangerously-skip-permissions" >&2
    echo "" >&2
    
    # Run claude WITHOUT the 2>/dev/null redirect to see errors
    local response
    response=$(claude -p "$full_prompt" --model sonnet --dangerously-skip-permissions)
    local exit_code=$?
    
    echo "=== DEBUG: claude command finished ===" >&2
    echo "Exit code: $exit_code" >&2
    echo "" >&2
    echo "=== DEBUG: First 500 chars of response ===" >&2
    echo "${response:0:500}" >&2
    echo "" >&2
    echo "=== DEBUG: Response length: ${#response} chars ===" >&2
    echo "" >&2
    
    echo "$response"
}

# Test with a simple prompt
echo "Running debug test with prompt: 'echo hello'"
echo "================================================"

result=$(_ask_debug "echo hello" "" "160")

echo ""
echo "================================================"
echo "Full response received:"
echo "$result"
