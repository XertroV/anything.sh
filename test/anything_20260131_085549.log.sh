#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - Autopoietic Self-Modifying Execution Loop       ║
# ║  A script that evolves by appending LLM-generated code.        ║
# ║  Provider: OpenCode                                            ║
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
# ORACLE: Query OpenCode with script context
# ─────────────────────────────────────────────────────────────────
_ask() {
    local intent="$1"
    local feedback="${2:-}"
    local remaining="${3:-?}"
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
You are a bash code generator in an iterative execution loop.

SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL | $PWD
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

    opencode run "$full_prompt" 2>/dev/null
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
echo -e "\033[32m│\033[0m   provider: opencode                \033[32m│\033[0m"
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
# STEP 1: Check if chocolate-doom is installed
# Generated: 2026-01-31 08:44:26 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() { command -v chocolate-doom &>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"; }
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Identify which Doom binary is available
# Generated: 2026-01-31 08:45:00 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() { for cmd in fdoom chocolate-doom gzdoom prboom-plus doom; do command -v $cmd &>/dev/null && echo "BINARY: $cmd" && return 0; done; echo "BINARY: NONE"; }
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Check for chocolate-doom binary and available WAD files
# Generated: 2026-01-31 08:45:11 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() { command -v chocolate-doom && echo "DOOM_BIN_FOUND" || echo "DOOM_BIN_MISSING"; find /usr/share/games/doom /usr/share/doom . -name "*.wad" 2>/dev/null; }
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Check for Doom WAD files and verify chocolate-doom version
# Generated: 2026-01-31 08:45:38 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
    echo "Checking for WAD files..."
    WAD_PATH=$(find /usr/share /home -name "doom1.wad" 2>/dev/null | head -n 1)
    if [ -n "$WAD_PATH" ]; then
        echo "WAD_FOUND: $WAD_PATH"
    else
        echo "WAD_NOT_FOUND"
    fi
    if command -v chocolate-doom >/dev/null; then
        chocolate-doom -version 2>&1 | head -n 1 || echo "chocolate-doom version check failed"
    else
        echo "chocolate-doom not in PATH"
    fi
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Check for libcaca and verify chocolate-doom starts headless
# Generated: 2026-01-31 08:46:14 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
  pacman -Qi libcaca &>/dev/null && echo "CACA_INSTALLED" || echo "CACA_NOT_INSTALLED"
  export SDL_VIDEODRIVER=dummy
  timeout 1s chocolate-doom -iwad /home/xertrov/.local/share/games/doom/doom1.wad -nosound -window 2>&1 | grep -i "Chocolate Doom" | head -n 1
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: Install chocolate-doom and fetch shareware WAD
# Generated: 2026-01-31 08:46:47 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step6() { sudo pacman -Sy --noconfirm chocolate-doom wget &>/dev/null; [ ! -f doom1.wad ] && wget -q https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad; command -v chocolate-doom &>/dev/null && [ -f doom1.wad ] && echo "READY" || echo "FAILED"; }
step6

# ═══════════════════════════════════════════════════════════════
# STEP 7: Display DOOM ASCII art
# Generated: 2026-01-31 08:47:16 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step7() {
echo '  ____   ___   ___  __  __'
echo ' |  _ \ / _ \ / _ \|  \/  |'
echo ' | | | | | | | | | | |\/| |'
echo ' | |_| | |_| | |_| | |  | |'
echo ' |____/ \___/ \___/|_|  |_|'
}
step7


# ═══════════════════════════════════════════════════════════════
# STEP 8: Check for sudo, build tools, and system info
# Generated: 2026-01-31 08:50:17 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step8() {
  sudo -n true 2>/dev/null && echo "SUDO: YES" || echo "SUDO: NO"
  command -v git >/dev/null && echo "GIT: YES" || echo "GIT: NO"
  command -v gcc >/dev/null && echo "GCC: YES" || echo "GCC: NO"
  command -v cmake >/dev/null && echo "CMAKE: YES" || echo "CMAKE: NO"
  pacman -Si freedoom >/dev/null 2>&1 && echo "FREEDOOM_PKG: YES" || echo "FREEDOOM_PKG: NO"
}
step8

# ═══════════════════════════════════════════════════════════════
# STEP 9: Install cmake and freedoom, then locate WAD files
# Generated: 2026-01-31 08:50:39 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step9() {
    sudo pacman -Sy --noconfirm cmake freedoom >/dev/null 2>&1 && echo "INSTALLED_PACKAGES" || echo "INSTALL_FAILED"
    echo "SEARCHING_WADS:"
    find /usr/share/doom /usr/share/games/doom -name "*.wad" 2>/dev/null
}
step9

# ═══════════════════════════════════════════════════════════════
# STEP 10: Check build tools and libraries for doom-ascii
# Generated: 2026-01-31 08:50:59 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step10() {
  echo "TOOLS:"
  for tool in git gcc make cmake python3; do
    command -v $tool &>/dev/null && echo "$tool: INSTALLED" || echo "$tool: MISSING"
  done
  echo "LIBRARIES:"
  pacman -Qi sdl2 &>/dev/null && echo "sdl2: INSTALLED" || echo "sdl2: MISSING"
  pacman -Qi sdl2_mixer &>/dev/null && echo "sdl2_mixer: INSTALLED" || echo "sdl2_mixer: MISSING"
  echo "WADS:"
  find . -maxdepth 3 -name "doom1.wad" -o -name "DOOM1.WAD" 2>/dev/null
}
step10

# ═══════════════════════════════════════════════════════════════
# STEP 11: Install cmake and clone doom-ascii repository
# Generated: 2026-01-31 08:51:31 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step11() {
    if ! command -v cmake &> /dev/null; then
        echo "Installing cmake..."
        sudo pacman -S --noconfirm cmake || echo "CMAKE_INSTALL_FAILED"
    fi
    if [ ! -d "doom-ascii" ]; then
        echo "Cloning doom-ascii..."
        git clone https://github.com/wojciech-graj/doom-ascii.git
    else
        echo "doom-ascii already exists"
    fi
}
step11

# ═══════════════════════════════════════════════════════════════
# STEP 12: Configure and compile doom-ascii
# Generated: 2026-01-31 08:52:02 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step12() {
    cd doom-ascii || { echo "Directory not found"; exit 1; }
    # Configure and build
    cmake -DCMAKE_BUILD_TYPE=Release . && make
    # List executables to confirm build name
    echo "Checking for executables:"
    find . -maxdepth 2 -type f -executable -not -path '*/.*'
}
step12

# ═══════════════════════════════════════════════════════════════
# STEP 13: List contents of doom-ascii to locate build files and check for WADs
# Generated: 2026-01-31 08:52:20 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step13() { ls -R doom-ascii | head -n 20; find doom-ascii -name "CMakeLists.txt" -o -name "Makefile"; }
step13

# ═══════════════════════════════════════════════════════════════
# STEP 14: Install dependencies, build doom-ascii, and download shareware WAD
# Generated: 2026-01-31 08:52:53 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step14() {
    command -v pacman &>/dev/null && sudo pacman -S --needed --noconfirm ncurses base-devel &>/dev/null
    cd doom-ascii || return 1
    make -j$(nproc)
    bin=$(find . -maxdepth 1 -type f -executable -not -name "configure" -not -name "*.sh" | head -n 1)
    if [ -n "$bin" ]; then
        [ ! -f doom1.wad ] && curl -sL -o doom1.wad https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad
        echo "Build successful. Run: cd doom-ascii && $bin -iwad doom1.wad"
    else
        echo "Build failed."
    fi
}
step14


# ═══════════════════════════════════════════════════════════════
# STEP 15: Check for existing Doom binaries and ASCII libraries
# Generated: 2026-01-31 08:53:48 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step15() {
    echo "Checking for Doom..."
    for cmd in chocolate-doom gzdoom zdoom doom prboom-plus; do
        if command -v "$cmd" >/dev/null; then echo "Found binary: $cmd"; fi
    done
    echo "Checking libraries..."
    pacman -Q libcaca aalib 2>/dev/null || echo "Libraries not found via pacman -Q"
}
step15

# ═══════════════════════════════════════════════════════════════
# STEP 16: Check for Doom WAD files
# Generated: 2026-01-31 08:54:05 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step16() { find /usr/share/doom /usr/share/games/doom . -name "*.wad" 2>/dev/null || echo "No WADs found"; }
step16

# ═══════════════════════════════════════════════════════════════
# STEP 17: Check for development tools and doom1.wad existence/size
# Generated: 2026-01-31 08:54:23 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step17() { 
  ls -l doom1.wad 2>/dev/null || echo "MISSING_WAD"; 
  command -v git >/dev/null && echo "HAS_GIT" || echo "NO_GIT";
  command -v cmake >/dev/null && echo "HAS_CMAKE" || echo "NO_CMAKE";
  command -v gcc >/dev/null && echo "HAS_GCC" || echo "NO_GCC";
  command -v make >/dev/null && echo "HAS_MAKE" || echo "NO_MAKE";
}
step17

# ═══════════════════════════════════════════════════════════════
# STEP 18: Clone and build doom-ascii from source
# Generated: 2026-01-31 08:54:43 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step18() {
    rm -rf doom-ascii
    git clone --depth 1 https://github.com/wojciech-graj/doom-ascii.git
    cd doom-ascii
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j$(nproc)
}
step18

# ═══════════════════════════════════════════════════════════════
# STEP 19: Check doom-ascii directory contents to determine build method
# Generated: 2026-01-31 08:54:57 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step19() { ls -F doom-ascii 2>/dev/null || echo "doom-ascii dir missing"; }
step19

# ═══════════════════════════════════════════════════════════════
# STEP 20: Check for required tools (figlet, toilet) and if doom is already present
# Generated: 2026-01-31 08:55:25 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step20() {
    command -v figlet &>/dev/null && echo "FIGLET_FOUND" || echo "FIGLET_MISSING"
    command -v toilet &>/dev/null && echo "TOILET_FOUND" || echo "TOILET_MISSING"
    command -v lolcat &>/dev/null && echo "LOLCAT_FOUND" || echo "LOLCAT_MISSING"
}
step20

# ═══════════════════════════════════════════════════════════════
# STEP 21: Print ASCII art for DOOM manually since figlet is missing
# Generated: 2026-01-31 08:55:39 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step21() {
cat << "EOF"
______  _____  _____  ___  ___
|  _  \|  _  ||  _  ||  \/  |
| | | || | | || | | || .  . |
| | | || | | || | | || |\/| |
| |/ / \ \_/ /\ \_/ /| |  | |
|___/   \___/  \___/ \_|  |_/
EOF
}
step21

_prompt
#
