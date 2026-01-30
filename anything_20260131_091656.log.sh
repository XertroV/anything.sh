#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - Autopoietic Self-Modifying Execution Loop       ║
# ║  A script that evolves by appending LLM-generated code.        ║
# ║  Provider: Claude                                              ║
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

# ─────────────────────────────────────────────────────────────────
# BACKUP: Save original on first run
# ─────────────────────────────────────────────────────────────────
[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG" && echo -e "\033[36m[backup]\033[0m $ORIG"

# ─────────────────────────────────────────────────────────────────
# CLEANUP: Runs on EXIT - archives session, restores original
# ─────────────────────────────────────────────────────────────────
_cleanup() {
    local rc=$?
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
You are a bash code generator in an iterative execution loop.

SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL
CWD: $PWD
DISPLAY: $([[ -n "${WAYLAND_DISPLAY:-}" ]] && echo "wayland:$WAYLAND_DISPLAY" || [[ -n "${DISPLAY:-}" ]] && echo "x11:$DISPLAY" || echo "NONE")$([[ -n "${SSH_TTY:-}" ]] && echo " [ssh]")

TASK: $intent
TURNS REMAINING: $remaining (if 1-2, prioritize completing the task or informing user why it can't be done)
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
- No markdown fences, no explanation outside the format above
- Each code block should define and call step${STEP}()
- IMPORTANT: Use absolute paths or verify paths exist before running commands. CWD may not be where you expect.

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

    claude -p "$full_prompt" --dangerously-skip-permissions 2>/dev/null
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
# EVOLVE: Iterative code generation with feedback loop
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    local feedback=""
    local is_final="false"
    local iteration=0

    # Remove trailing _prompt and # from script (so reruns replay without prompting)
    sed -i '/^_prompt$/,/^#$/d' "$SELF"

    while [[ "$is_final" != "true" && $iteration -lt $MAX_ITER ]]; do
        ((iteration++))
        ((STEP++))
        local remaining=$((MAX_ITER - iteration))

        # Start spinner
        _spinner &
        local spinner_pid=$!

        local response=$(_ask "$intent" "$feedback" "$remaining")

        # Stop spinner
        kill $spinner_pid 2>/dev/null
        wait $spinner_pid 2>/dev/null
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

        # Append code to script
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
        local tmpfile=$(mktemp)
        if [[ "$(uname)" == "Darwin" ]]; then
            script -q "$tmpfile" bash -c "eval \"$code\""
        else
            script -q -e -c "eval \"$code\"" "$tmpfile"
        fi
        exit_code=$?
        # Clean ANSI codes for LLM feedback (script captures control sequences)
        output=$(perl -pe 's/\e\[[0-9;]*[mGKHJF]//g; s/\r\n/\n/g; s/\r//g' "$tmpfile" 2>/dev/null || cat "$tmpfile")
        rm -f "$tmpfile"
        [[ $exit_code -ne 0 ]] && echo -e "\033[31m[exit $exit_code]\033[0m"

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
# STEP 1: Check for text adventure tools and create D&D style game
# Generated: 2026-01-31 09:16:44 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    # Create a D&D style text adventure game
    cat << 'GAME_EOF'
╔══════════════════════════════════════════════════════════════════╗
║          ⚔️  DUNGEONS OF DESTINY - A Text Adventure  ⚔️          ║
╚══════════════════════════════════════════════════════════════════╝

You awaken in a dimly lit stone chamber. Torchlight flickers against
ancient walls covered in strange runes. The air smells of dust and magic.

┌─────────────────── CHARACTER STATUS ───────────────────┐
│  Name: Wanderer          Class: Fighter               │
│  ───────────────────────────────────────────────────  │
│  HP: ████████████████████ 20/20    Level: 1          │
│  MP: ██████░░░░░░░░░░░░░░  6/20    XP: 0/100         │
│  ───────────────────────────────────────────────────  │
│  STR: 14 (+2)  DEX: 12 (+1)  CON: 13 (+1)            │
│  INT: 10 (+0)  WIS: 11 (+0)  CHA:  9 (-1)            │
│  ───────────────────────────────────────────────────  │
│  Gold: 15      Inventory: Rusty Sword, Torch, Rope   │
│  Armor Class: 12                                      │
└───────────────────────────────────────────────────────┘

Three passages lead away from this chamber:

  [N] A narrow passage to the NORTH, from which you hear dripping water
  [E] A wide corridor to the EAST, lit by a faint green glow  
  [S] A crumbling doorway to the SOUTH, blocked by thick cobwebs

A weathered CHEST sits in the corner, its lock rusted but intact.

What do you do?
> examine chest | go north | go east | go south | check inventory

GAME_EOF
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: D&D style text adventure game with status display
# Generated: 2026-01-31 09:16:52 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step2() {
    cat << 'GAME_EOF'
╔══════════════════════════════════════════════════════════════════╗
║          ⚔️  DUNGEONS OF DESTINY - A Text Adventure  ⚔️          ║
╚══════════════════════════════════════════════════════════════════╝

You awaken in a dimly lit stone chamber. Torchlight flickers against
ancient walls covered in strange runes. The air smells of dust and magic.

┌─────────────────── CHARACTER STATUS ───────────────────┐
│  Name: Wanderer          Class: Fighter               │
│  ───────────────────────────────────────────────────  │
│  HP: ████████████████████ 20/20    Level: 1          │
│  MP: ██████░░░░░░░░░░░░░░  6/20    XP: 0/100         │
│  ───────────────────────────────────────────────────  │
│  STR: 14 (+2)  DEX: 12 (+1)  CON: 13 (+1)            │
│  INT: 10 (+0)  WIS: 11 (+0)  CHA:  9 (-1)            │
│  ───────────────────────────────────────────────────  │
│  Gold: 15      Inventory: Rusty Sword, Torch, Rope   │
│  Armor Class: 12                                      │
└───────────────────────────────────────────────────────┘

Three passages lead away from this chamber:

  [N] A narrow passage to the NORTH, from which you hear dripping water
  [E] A wide corridor to the EAST, lit by a faint green glow  
  [S] A crumbling doorway to the SOUTH, blocked by thick cobwebs

A weathered CHEST sits in the corner, its lock rusted but intact.

What do you do?
> examine chest | go north | go east | go south | check inventory

GAME_EOF
}
step2
