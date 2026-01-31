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
    local max_iterations=5
    local iteration=0

    # Remove trailing _prompt and # from script (so reruns replay without prompting)
    sed -i '/^_prompt$/,/^#$/d' "$SELF"

    while [[ "$is_final" != "true" && $iteration -lt $max_iterations ]]; do
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
        elif [[ $exit_code -ne 0 && $iteration -lt $max_iterations ]]; then
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
# STEP 1: Check if doom is installed or available
# Generated: 2026-01-31 08:29:31
# ═══════════════════════════════════════════════════════════════
step1() {
  # Check for various doom games/ports
  echo "=== Checking for Doom games/ports ==="
  for cmd in doom chocolate-doom crispy-doom prboom prboom-plus gzdoom zdoom; do
    if command -v "$cmd" &>/dev/null; then
      echo "FOUND: $cmd"
    fi
  done
  
  # Check what's available in package manager
  echo ""
  echo "=== Available in pacman ==="
  pacman -Ss doom 2>/dev/null | grep -E "(chocolate-doom|crispy-doom|prboom|gzdoom|zdoom)" | head -10
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Launch Chocolate Doom with shareware WAD
# Generated: 2026-01-31 08:29:39
# ═══════════════════════════════════════════════════════════════
step2() {
    # Check for WAD files
    local wad_dirs=("/usr/share/games/doom" "/usr/share/doom" "$HOME/.local/share/games/doom" "$HOME/Games/doom")
    local wad=""
    
    for dir in "${wad_dirs[@]}"; do
        if [[ -f "$dir/doom1.wad" ]]; then
            wad="$dir/doom1.wad"
            break
        elif [[ -f "$dir/doom.wad" ]]; then
            wad="$dir/doom.wad"
            break
        fi
    done
    
    if [[ -z "$wad" ]]; then
        # Download shareware DOOM1.WAD if not found
        mkdir -p "$HOME/.local/share/games/doom"
        echo "Downloading DOOM shareware..."
        curl -sL "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad" -o "$HOME/.local/share/games/doom/doom1.wad"
        wad="$HOME/.local/share/games/doom/doom1.wad"
    fi
    
    echo "Launching Chocolate Doom with: $wad"
    chocolate-doom -iwad "$wad"
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Check for available display and X11 forwarding options
# Generated: 2026-01-31 08:29:55
# ═══════════════════════════════════════════════════════════════
step3() {
    echo "=== Checking DISPLAY variable ==="
    echo "DISPLAY: $DISPLAY"
    
    echo -e "\n=== Checking for Xvfb (virtual framebuffer) ==="
    command -v Xvfb &>/dev/null && echo "Xvfb: INSTALLED" || echo "Xvfb: NOT_INSTALLED"
    
    echo -e "\n=== Checking for xvfb-run ==="
    command -v xvfb-run &>/dev/null && echo "xvfb-run: INSTALLED" || echo "xvfb-run: NOT_INSTALLED"
    
    echo -e "\n=== Checking chocolate-doom options for headless/null video ==="
    chocolate-doom -h 2>&1 | grep -i -E "(video|display|null|dummy)" || echo "No obvious headless options found"
    
    echo -e "\n=== Checking SDL video drivers available ==="
    SDL_VIDEODRIVER=dummy chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad 2>&1 | head -20 || true
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Check if doom is installed and available display options
# Generated: 2026-01-31 08:30:03
# ═══════════════════════════════════════════════════════════════
step4() {
    echo "=== Checking for doom games ==="
    command -v chocolate-doom && echo "chocolate-doom: INSTALLED" || echo "chocolate-doom: NOT_INSTALLED"
    command -v prboom-plus && echo "prboom-plus: INSTALLED" || echo "prboom-plus: NOT_INSTALLED"
    command -v crispy-doom && echo "crispy-doom: INSTALLED" || echo "crispy-doom: NOT_INSTALLED"
    command -v gzdoom && echo "gzdoom: INSTALLED" || echo "gzdoom: NOT_INSTALLED"
    echo "=== Checking for terminal doom ==="
    command -v doomrl && echo "doomrl: INSTALLED" || echo "doomrl: NOT_INSTALLED"
    pacman -Ss doom 2>/dev/null | grep -E "^[a-z]" | head -10
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Check for DOOM WAD files and launch chocolate-doom
# Generated: 2026-01-31 08:30:11
# ═══════════════════════════════════════════════════════════════
step5() {
    # Check for WAD files
    echo "=== Checking for DOOM WAD files ==="
    WAD_PATHS=(
        "/usr/share/games/doom"
        "/usr/share/doom"
        "/usr/local/share/games/doom"
        "$HOME/.local/share/games/doom"
        "$HOME/Games/doom"
    )
    
    for path in "${WAD_PATHS[@]}"; do
        if [[ -d "$path" ]]; then
            echo "Checking $path:"
            ls -la "$path" 2>/dev/null | grep -i "\.wad"
        fi
    done
    
    # Check if freedoom is available
    echo ""
    echo "=== Checking for freedoom (free DOOM WADs) ==="
    pacman -Ss freedoom 2>/dev/null | head -5
    
    # Check doomretro default paths
    echo ""
    echo "=== Checking doomretro ==="
    which doomretro 2>/dev/null && echo "doomretro is available"
}
step5

_prompt
#
