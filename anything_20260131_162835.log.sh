#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - Autopoietic Self-Modifying Execution Loop       ║
# ║  A script that evolves by appending LLM-generated code.        ║
# ║  Author: XertroV + vibes        License: The Unlicense         ║
# ║  Home: https://xertrov.github.io/anything.sh/                  ║
# ║  Current Provider: Claude                                      ║
# ╚════════════════════════════════════════════════════════════════╝
# USAGE: ./anything.sh ["initial prompt"]

set -uo pipefail  # -e disabled: we handle errors manually

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────
SELF="$0"
ORIG="${SELF}.orig"
STEP=0
MAX_ITER=16  # Max LLM calls per task (increase for complex tasks)
BONUS_ITER=0  # Extra iterations granted via _continue_journey()
SPINNER_PID=""  # Track spinner for cleanup

# ─────────────────────────────────────────────────────────────────
# AUTO-LOCALIZE: Copy to current dir if running from system path
# ─────────────────────────────────────────────────────────────────
if [[ "$SELF" == *"/bin/"* && ! -f "$ORIG" ]]; then
    LOCAL_COPY="./anything_$(date +%Y%m%d_%H%M%S).sh"
    cp "$SELF" "$LOCAL_COPY"
    chmod +x "$LOCAL_COPY"
    echo -e "\033[36m[localized]\033[0m $LOCAL_COPY"
    exec "$LOCAL_COPY" "$@"
fi

# ─────────────────────────────────────────────────────────────────
# BACKUP: Save original on first run
# ─────────────────────────────────────────────────────────────────
[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG" && echo -e "\033[36m[backup]\033[0m $ORIG"

# ─────────────────────────────────────────────────────────────────
# CLEANUP: Runs on EXIT - archives session, restores original
# ─────────────────────────────────────────────────────────────────
_cleanup() {
    local rc=$?
    [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null
    printf "\r\033[K"  # Clear spinner line
    [[ -f "$ORIG" ]] || return $rc
    local archive="${SELF%.sh}_$(date +%Y%m%d_%H%M%S).log.sh"
    cp "$SELF" "$archive" 2>/dev/null || true
    cp "$ORIG" "$SELF" 2>/dev/null || true
    echo ""
    echo -e "\033[36m[archived]\033[0m $archive"
    echo -e "\033[36m[restored]\033[0m $SELF"
    exit $rc
}
trap _cleanup EXIT

# ─────────────────────────────────────────────────────────────────
# ORACLE: Query Claude with script context
# ─────────────────────────────────────────────────────────────────
_ask() {
    local intent="$1"
    local feedback="${2:-}"
    local remaining="${3:-?}"
    local full_prompt
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
$feedback

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

${ANYTHING_EXTRA:+
=== EXTRA CONTEXT ===
$ANYTHING_EXTRA
}
PROMPT

    claude -p "$full_prompt" --model sonnet --dangerously-skip-permissions 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────
# SPINNER: Pulsing animation while waiting
# ─────────────────────────────────────────────────────────────────
_spinner() {
    local frames=('·    ' '··   ' '···  ' '···· ' '·····' ' ····' '  ···' '   ··' '    ·' '     ')
    local i=0
    while true; do
        printf "\r\033[36m%s\033[0m pulsing..." "${frames[i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
}

# ─────────────────────────────────────────────────────────────────
# CONTINUE JOURNEY: Add more iterations for long experiences
# ─────────────────────────────────────────────────────────────────
_continue_journey() {
    BONUS_ITER=$((BONUS_ITER + 16))
    echo -e "\033[36m[+16 iterations granted]\033[0m"
}

# ─────────────────────────────────────────────────────────────────
# EVOLVE: Iterative code generation with feedback loop
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    local feedback=""
    local is_final="false"
    local iteration=0

    # Remove trailing _prompt and # from script (so reruns replay without prompting)
    sed -i '/^_prompt$/,/^#$/d' "$SELF"

    while [[ "$is_final" != "true" && $iteration -lt $((MAX_ITER + BONUS_ITER)) ]]; do
        ((iteration++))
        ((STEP++))
        local remaining=$((MAX_ITER + BONUS_ITER - iteration))

        # Start spinner
        _spinner &
        SPINNER_PID=$!

        local response=$(_ask "$intent" "$feedback" "$remaining")

        # Stop spinner
        kill $SPINNER_PID 2>/dev/null
        wait $SPINNER_PID 2>/dev/null
        SPINNER_PID=""
        printf "\r\033[K"

        # Parse structured response
        is_final=$(echo "$response" | grep -i '^FINAL:' | head -1 | sed 's/^FINAL:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
        local description=$(echo "$response" | grep -i '^DESCRIPTION:' | head -1 | sed 's/^DESCRIPTION:[[:space:]]*//')
        local code=$(echo "$response" | sed -n '/^BASH_CODE:/,$ { /^BASH_CODE:/d; p }')

        # Fallback: if no structured format, treat whole response as code
        if [[ -z "$code" ]]; then
            code="$response"
            description="$intent"
            is_final="true"
        fi

        # Strip markdown fences if present
        if echo "$code" | grep -q '^```'; then
            code=$(echo "$code" | sed -n '/^```/,/^```/p' | sed '/^```/d')
        fi

        if [[ -z "$code" ]]; then
            echo -e "\033[31m[error]\033[0m empty response"
            return 1
        fi

        echo -e "\033[32m[step $STEP]\033[0m $description"
        local lines=$(echo "$code" | wc -l)
        echo -e "\033[33m[+$lines lines]\033[0m"

        # Append just the step header + code (output comments already appended after execution)
        cat >> "$SELF" <<EVOLUTION

# ═══════════════════════════════════════════════════════════════
# STEP $STEP: $description
# Generated: $(date '+%Y-%m-%d %H:%M:%S') | FINAL: $is_final
# ═══════════════════════════════════════════════════════════════
$code
EVOLUTION

        # Execute with PTY (supports interactive programs like whiptail/dialog)
        echo -e "\033[36m[running...]\033[0m"
        local output exit_code
        local tmpfile=$(mktemp) codefile=$(mktemp)
        printf '%s' "$code" > "$codefile"
        if [[ "$(uname)" == "Darwin" ]]; then
            script -q "$tmpfile" bash "$codefile"
        else
            script -q -e -c "bash '$codefile'" "$tmpfile"
        fi
        exit_code=$?
        rm -f "$codefile"
        # Clean ANSI codes for LLM feedback (script captures control sequences)
        output=$(perl -pe 's/\e\[[0-9;]*[mGKHJF]//g; s/\r\n/\n/g; s/\r//g' "$tmpfile" 2>/dev/null || cat "$tmpfile")
        rm -f "$tmpfile"
        [[ $exit_code -ne 0 ]] && echo -e "\033[31m[exit $exit_code]\033[0m"

        # Immediately append output as comments to script (before LLM call, in case of crash)
        if [[ -n "$output" ]]; then
            local output_lines=$(echo "$output" | wc -l)
            if [[ $output_lines -gt 1000 ]]; then
                # Truncate: keep first 400 and last 400 lines
                {
                    echo ""
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "# OUTPUT FROM PREVIOUS STEP:"
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "$output" | head -400 | uniq | sed 's/^/# /'
                    echo "#"
                    echo "# [...$((output_lines - 800)) lines snipped...]"
                    echo "#"
                    echo "$output" | tail -400 | uniq | sed 's/^/# /'
                } >> "$SELF"
            else
                {
                    echo ""
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "# OUTPUT FROM PREVIOUS STEP:"
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "$output" | uniq | sed 's/^/# /'
                } >> "$SELF"
            fi
        fi

        if [[ "$is_final" != "true" ]]; then
            feedback="
PREVIOUS STEP OUTPUT (exit code $exit_code):
$output
"
        elif [[ $exit_code -ne 0 && $exit_code -ne 141 && $iteration -lt $MAX_ITER ]]; then
            # Final step failed - give LLM a chance to recover
            echo -e "\033[33m[final step failed, attempting recovery...]\033[0m"
            is_final="false"
            feedback="
FINAL STEP FAILED (exit code $exit_code):
$output

Please diagnose the issue and fix it. You may need to install additional dependencies or use different parameters.
"
        fi
    done

    # Check if we hit max iterations without completing
    if [[ "$is_final" != "true" ]]; then
        echo -e "\033[33m[max iterations reached]\033[0m Task incomplete after $iteration steps."
        read -rp $'\033[95m  continue? [Y/n] \033[0m' cont
        if [[ -z "$cont" || "$cont" =~ ^[Yy] ]]; then
            iteration=0
            _evolve "$intent"  # Recursive call to continue
            return
        fi
        echo -e "\033[36m[stopped]\033[0m You can retry or try a different approach."
    fi

    # Append _prompt for next user input (for re-runs of the script)
    cat >> "$SELF" <<'PROMPT_MARKER'

PROMPT_MARKER

    # Continue interactive loop
    _prompt
}

# ─────────────────────────────────────────────────────────────────
# PROMPT: Interactive input loop
# ─────────────────────────────────────────────────────────────────
_prompt() {
    echo ""
    read -rp $'\033[95m  what shall I become? \033[0m' input || exit 0
    [[ -z "$input" || "$input" == "exit" ]] && exit 0
    _evolve "$input"
}

# ─────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────
echo -e "\033[32m┌─────────────────────────────────────┐\033[0m"
echo -e "\033[32m│\033[0m   anything.sh · autopoietic loop    \033[32m│\033[0m"
echo -e "\033[32m│\033[0m   provider: claude                  \033[32m│\033[0m"
echo -e "\033[32m└─────────────────────────────────────┘\033[0m"
echo "  Ctrl+C or 'exit' to save & quit"
echo ""

# ─────────────────────────────────────────────────────────────────
# SYSTEM INFO
# ─────────────────────────────────────────────────────────────────
echo -e "\033[36m  os:\033[0m    $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null)"
echo -e "\033[36m  arch:\033[0m  $(uname -sm)"
echo -e "\033[36m  shell:\033[0m $SHELL"
echo -e "\033[36m  pwd:\033[0m   $PWD"
echo ""

# ─────────────────────────────────────────────────────────────────
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
[[ -n "${1:-}" ]] && _evolve "$1" || _prompt
#


# ═══════════════════════════════════════════════════════════════
# STEP 1: Echo test message
# Generated: 2026-01-31 16:28:35 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step1() { echo "test"; }
step1

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 16:28:35+11:00 [COMMAND="bash '/tmp/tmp.la81QjwdMI'" <not executed on terminal>]
# test
# 
# Script done on 2026-01-31 16:28:35+11:00 [COMMAND_EXIT_CODE="0"]

_prompt
#
