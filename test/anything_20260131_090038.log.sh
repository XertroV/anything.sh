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
# STEP 1: Check if ASCII Doom variants are available
# Generated: 2026-01-31 08:58:34 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
  echo "=== Checking for ASCII/terminal Doom options ==="
  
  # Check for common terminal doom games
  for cmd in doomrl doom-ascii ninvaders bastet greed; do
    command -v "$cmd" &>/dev/null && echo "FOUND: $cmd" || echo "NOT_FOUND: $cmd"
  done
  
  # Check if there's a doom-ascii in the local directory
  if [[ -d "doom-ascii" ]]; then
    echo "LOCAL: doom-ascii directory exists"
    ls -la doom-ascii/
  fi
  
  # Check pacman for available doom-related packages
  echo "=== Available in pacman ==="
  pacman -Ss doom 2>/dev/null | grep -i "ascii\|terminal\|console\|roguelike" || echo "No ASCII doom variants in pacman"
  
  # Check AUR helper
  command -v yay &>/dev/null && echo "YAY: available" || echo "YAY: not found"
  command -v paru &>/dev/null && echo "PARU: available" || echo "PARU: not found"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Build doom-ascii from source
# Generated: 2026-01-31 08:58:40 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    cd doom-ascii
    echo "=== Building doom-ascii ==="
    make clean 2>/dev/null
    make -j$(nproc) 2>&1
    if [[ -f doom-ascii ]]; then
        echo "BUILD_SUCCESS"
        ls -la doom-ascii
    else
        echo "BUILD_FAILED"
        ls -la
    fi
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Check build output and run doom-ascii
# Generated: 2026-01-31 08:58:49 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
    # Check if doom-ascii binary exists
    if [[ -f /home/xertrov/src/anything.sh/doom-ascii/game/doom-ascii ]]; then
        echo "BUILD_SUCCESS: doom-ascii binary found"
        ls -la /home/xertrov/src/anything.sh/doom-ascii/game/
        # Check if doom1.wad exists
        if [[ -f /home/xertrov/src/anything.sh/doom1.wad ]]; then
            echo "WAD_FOUND: doom1.wad exists"
            # Run doom-ascii with the wad file
            cd /home/xertrov/src/anything.sh/doom-ascii/game
            ./doom-ascii -iwad /home/xertrov/src/anything.sh/doom1.wad
        else
            echo "WAD_NOT_FOUND: Need doom1.wad to run"
        fi
    else
        echo "BUILD_FAILED: doom-ascii binary not found"
        # Check what's in obj directory
        ls -la /home/xertrov/src/anything.sh/doom-ascii/obj/ 2>/dev/null || echo "No obj directory"
    fi
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Check doom-ascii directory structure and find build issues
# Generated: 2026-01-31 08:58:56 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
    echo "=== Directory contents ==="
    ls -la doom-ascii/
    echo ""
    echo "=== Looking for Makefile or build instructions ==="
    cat doom-ascii/Makefile 2>/dev/null || echo "No Makefile found"
    echo ""
    echo "=== Looking for README ==="
    cat doom-ascii/README* 2>/dev/null | head -50 || echo "No README found"
    echo ""
    echo "=== Check for source files ==="
    find doom-ascii/ -name "*.c" -o -name "*.cpp" 2>/dev/null | head -20
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Build doom-ascii from source
# Generated: 2026-01-31 08:59:03 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
    cd doom-ascii
    # Build the project
    make 2>&1
    
    # Check if binary was created
    if [ -f "_unix/game/doom-ascii" ]; then
        echo "BUILD_SUCCESS"
        echo "Binary location: _unix/game/doom-ascii"
    else
        echo "BUILD_FAILED"
        find . -name "doom-ascii" -type f 2>/dev/null
    fi
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: Run doom-ascii with the WAD file
# Generated: 2026-01-31 08:59:08 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step6() { cd /home/xertrov/src/anything.sh && ./doom-ascii/doom-ascii -iwad doom1.wad; }
step6

# ═══════════════════════════════════════════════════════════════
# STEP 7: Check what files exist in doom-ascii directory and find the actual executable
# Generated: 2026-01-31 08:59:13 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step7() { ls -la doom-ascii/ 2>/dev/null || echo "Directory not found"; file doom-ascii/* 2>/dev/null; }
step7

# ═══════════════════════════════════════════════════════════════
# STEP 8: Build doom-ascii from source
# Generated: 2026-01-31 08:59:19 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step8() {
  cd doom-ascii
  make clean 2>/dev/null || true
  make -j$(nproc)
  ls -la doom-ascii 2>/dev/null || ls -la *.out 2>/dev/null || ls -la | grep -E '^-rwx'
}
step8

# ═══════════════════════════════════════════════════════════════
# STEP 9: Run doom-ascii with the WAD file
# Generated: 2026-01-31 08:59:25 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step9() { cd /home/xertrov/src/anything.sh && ./doom-ascii/game/doom-ascii -iwad doom1.wad; }
step9

# ═══════════════════════════════════════════════════════════════
# STEP 10: Check what files exist in doom-ascii directory and find the correct executable
# Generated: 2026-01-31 08:59:31 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step10() { find doom-ascii -type f -name "*.sh" -o -type f -executable 2>/dev/null | head -20; ls -la doom-ascii/ 2>/dev/null; ls -la doom-ascii/game/ 2>/dev/null; }
step10

# ═══════════════════════════════════════════════════════════════
# STEP 11: Run doom-ascii with the WAD file
# Generated: 2026-01-31 08:59:36 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step11() { cd doom-ascii && ./_unix/game/doom-ascii -iwad ../doom1.wad; }
step11
