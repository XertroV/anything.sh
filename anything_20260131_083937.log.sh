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
MAX_ITER=8  # Max LLM calls per task (increase for complex tasks)

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

SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL | $PWD
DISPLAY: $([[ -n "${WAYLAND_DISPLAY:-}" ]] && echo "wayland:$WAYLAND_DISPLAY" || [[ -n "${DISPLAY:-}" ]] && echo "x11:$DISPLAY" || echo "none")$([[ -n "${SSH_TTY:-}" ]] && echo " [ssh]")

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
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ═══════════════════════════════════════════════════════════════
$code
EVOLUTION

        # Execute and capture output
        echo -e "\033[36m[running...]\033[0m"
        local output exit_code
        output=$( { eval "$code"; } 2>&1 )
        exit_code=$?
        echo "$output"
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
        echo -e "\033[31m[max iterations reached]\033[0m Task incomplete after $MAX_ITER steps."
        echo -e "\033[33mTip: Increase MAX_ITER at top of script for complex tasks.\033[0m"
    fi

    # Append _prompt for next user input
    cat >> "$SELF" <<'PROMPT_MARKER'

PROMPT_MARKER
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
# STEP 1: Check if chocolate-doom or similar DOOM port is installed
# Generated: 2026-01-31 08:38:55
# ═══════════════════════════════════════════════════════════════
step1() {
    echo "Checking for DOOM ports..."
    for doom in chocolate-doom crispy-doom prboom-plus gzdoom zdoom; do
        if command -v "$doom" &>/dev/null; then
            echo "FOUND: $doom"
        fi
    done
    echo "Checking for DOOM WAD files..."
    find /usr/share -name "*.wad" -o -name "*.WAD" 2>/dev/null | head -5
    find ~/.local/share -name "*.wad" -o -name "*.WAD" 2>/dev/null | head -5
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Launch DOOM with chocolate-doom using doom1.wad
# Generated: 2026-01-31 08:39:01
# ═══════════════════════════════════════════════════════════════
step2() { chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad; }
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Check for framebuffer or virtual display options
# Generated: 2026-01-31 08:39:10
# ═══════════════════════════════════════════════════════════════
step3() {
  echo "=== Checking for display options ==="
  # Check if Xvfb is available for virtual display
  command -v Xvfb &>/dev/null && echo "Xvfb: INSTALLED" || echo "Xvfb: NOT_INSTALLED"
  # Check if xvfb-run is available
  command -v xvfb-run &>/dev/null && echo "xvfb-run: INSTALLED" || echo "xvfb-run: NOT_INSTALLED"
  # Check chocolate-doom video drivers
  echo "=== Checking chocolate-doom help for video options ==="
  chocolate-doom -h 2>&1 | grep -i "video\|display\|screen" || echo "No video options in help"
  # Check if SDL has dummy driver
  echo "=== Testing SDL_VIDEODRIVER=dummy ==="
  SDL_VIDEODRIVER=dummy chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad -timedemo demo1 2>&1 | head -30
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Try running doom with dummy video driver and demo playback
# Generated: 2026-01-31 08:39:20
# ═══════════════════════════════════════════════════════════════
step4() {
    # The previous attempt showed it loaded the WAD but couldn't find demo1.lmp
    # Let's try running with the dummy driver and see if we can get it to render frames
    # We need to create a demo file or use built-in demo playback
    
    cd /home/xertrov/src/anything.sh
    
    # Try running doom with timedemo (built-in demo) and dummy video
    # -timedemo runs a built-in benchmark demo
    SDL_VIDEODRIVER=dummy timeout 10 chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad -timedemo demo1 2>&1 || true
    
    echo "=== Trying with -1 for episode 1 map 1 and -warp ==="
    # Try just starting the game briefly
    SDL_VIDEODRIVER=dummy timeout 5 chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad -skill 1 -warp 1 1 -nomonsters 2>&1 || true
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Doom runs but lacks display - cannot play interactively over SSH without X11
# Generated: 2026-01-31 08:39:37
# ═══════════════════════════════════════════════════════════════
step5() {
  echo "Chocolate Doom initialized successfully but requires a display to play."
  echo ""
  echo "The game loaded correctly:"
  echo "  - WAD file: doom1.wad (Shareware)"
  echo "  - Performance: 1374 fps in demo mode"
  echo ""
  echo "To play interactively, you need either:"
  echo "  1. SSH with X11 forwarding: ssh -X user@host"
  echo "  2. A local display (not SSH)"
  echo "  3. A framebuffer setup for headless play"
}
step5

_prompt
#
