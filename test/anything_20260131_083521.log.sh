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
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
You are a bash code generator in an iterative execution loop.

SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL | $PWD
DISPLAY: $([[ -n "${WAYLAND_DISPLAY:-}" ]] && echo "wayland:$WAYLAND_DISPLAY" || [[ -n "${DISPLAY:-}" ]] && echo "x11:$DISPLAY" || echo "none")$([[ -n "${SSH_TTY:-}" ]] && echo " [ssh]")

TASK: $intent
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

        # Start spinner
        _spinner &
        local spinner_pid=$!

        local response=$(_ask "$intent" "$feedback")

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
# STEP 1: Check if chocolate-doom or another doom port is installed
# Generated: 2026-01-31 08:34:27
# ═══════════════════════════════════════════════════════════════
step1() {
    echo "Checking for Doom ports..."
    for doom in chocolate-doom crispy-doom prboom-plus gzdoom zdoom; do
        if command -v "$doom" &>/dev/null; then
            echo "FOUND: $doom"
        fi
    done
    echo "Checking for doom WAD files..."
    find /usr/share/games /usr/share/doom ~/.local/share 2>/dev/null | grep -i '\.wad$' | head -5 || echo "No WADs found in common locations"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Launch Doom with the found WAD file
# Generated: 2026-01-31 08:34:32
# ═══════════════════════════════════════════════════════════════
step2() { chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad; }
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Check for available display and try running with SDL video driver options
# Generated: 2026-01-31 08:34:39
# ═══════════════════════════════════════════════════════════════
step3() {
    # Check if we have any display available
    echo "DISPLAY=$DISPLAY"
    echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    
    # Check for framebuffer
    ls -la /dev/fb* 2>/dev/null || echo "No framebuffer devices"
    
    # Check available SDL video drivers
    echo "Checking SDL video drivers..."
    
    # Try running with dummy video driver to see if game logic works
    SDL_VIDEODRIVER=dummy chocolate-doom -iwad ~/.local/share/games/doom/doom1.wad 2>&1 | head -30
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Check for terminal-based doom games available
# Generated: 2026-01-31 08:34:49
# ═══════════════════════════════════════════════════════════════
step4() {
    echo "=== Checking for doom games ==="
    # Check for common terminal doom options
    command -v psdoom &>/dev/null && echo "psdoom: INSTALLED" || echo "psdoom: NOT INSTALLED"
    command -v chocolate-doom &>/dev/null && echo "chocolate-doom: INSTALLED" || echo "chocolate-doom: NOT INSTALLED"
    command -v crispy-doom &>/dev/null && echo "crispy-doom: INSTALLED" || echo "crispy-doom: NOT INSTALLED"
    command -v doomrl &>/dev/null && echo "doomrl: INSTALLED" || echo "doomrl: NOT INSTALLED"
    
    echo ""
    echo "=== Searching pacman for doom ==="
    pacman -Ss doom 2>/dev/null | grep -E "^[a-z]" | head -20
    
    echo ""
    echo "=== Checking for fbdoom or similar ==="
    pacman -Ss fbdoom 2>/dev/null || echo "No fbdoom"
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Check for WAD files and try launching doom
# Generated: 2026-01-31 08:34:55
# ═══════════════════════════════════════════════════════════════
step5() {
    echo "=== Searching for WAD files ==="
    find /usr/share -name "*.wad" -o -name "*.WAD" 2>/dev/null | head -20
    find ~/.local/share -name "*.wad" -o -name "*.WAD" 2>/dev/null | head -10
    
    echo ""
    echo "=== Checking doomretro ==="
    which doomretro
    doomretro --help 2>&1 | head -5
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: Try chocolate-doom with the found WAD file
# Generated: 2026-01-31 08:35:05
# ═══════════════════════════════════════════════════════════════
step6() {
    # Try chocolate-doom which might handle headless/framebuffer better
    # or check for other doom ports
    echo "=== Checking available Doom ports ==="
    pacman -Qs doom 2>/dev/null | grep -E "^local"
    
    echo ""
    echo "=== Trying prboom-plus with software rendering ==="
    if command -v prboom-plus &>/dev/null; then
        SDL_VIDEODRIVER=dummy prboom-plus -iwad /home/xertrov/.local/share/games/doom/doom1.wad -nowindow 2>&1 | head -20
    else
        echo "prboom-plus not found"
    fi
    
    echo ""
    echo "=== Trying chocolate-doom ==="
    if command -v chocolate-doom &>/dev/null; then
        SDL_VIDEODRIVER=dummy chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad 2>&1 | head -20
    else
        echo "chocolate-doom not found"
    fi
}
step6

# ═══════════════════════════════════════════════════════════════
# STEP 7: Check if chocolate-doom started and try with different options
# Generated: 2026-01-31 08:35:13
# ═══════════════════════════════════════════════════════════════
step7() {
    # The previous output shows chocolate-doom loaded but likely needs a display
    # Let's check if there's a framebuffer or try with SDL video driver options
    
    echo "=== Checking display options ==="
    echo "DISPLAY=$DISPLAY"
    echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    
    # Try running with SDL dummy/offscreen or check if we can use framebuffer
    echo ""
    echo "=== Trying chocolate-doom with SDL_VIDEODRIVER=dummy ==="
    timeout 5 env SDL_VIDEODRIVER=dummy chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad 2>&1 | head -30
    
    echo ""
    echo "=== Checking for doomretro options ==="
    doomretro --help 2>&1 | head -20 || echo "No help available"
}
step7

# ═══════════════════════════════════════════════════════════════
# STEP 8: Check for terminal-based doom options
# Generated: 2026-01-31 08:35:21
# ═══════════════════════════════════════════════════════════════
step8() {
    echo "=== Checking for doom games ==="
    command -v chocolate-doom &>/dev/null && echo "chocolate-doom: INSTALLED" || echo "chocolate-doom: NOT_INSTALLED"
    command -v prboom-plus &>/dev/null && echo "prboom-plus: INSTALLED" || echo "prboom-plus: NOT_INSTALLED"
    command -v crispy-doom &>/dev/null && echo "crispy-doom: INSTALLED" || echo "crispy-doom: NOT_INSTALLED"
    command -v doomrl &>/dev/null && echo "doomrl: INSTALLED" || echo "doomrl: NOT_INSTALLED"
    command -v nsnake &>/dev/null && echo "nsnake: INSTALLED" || echo "nsnake: NOT_INSTALLED"
    echo "=== Checking pacman for doom packages ==="
    pacman -Ss doom 2>/dev/null | grep -E "^[a-z]" | head -10
}
step8

_prompt
#
