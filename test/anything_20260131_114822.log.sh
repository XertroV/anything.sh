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
SPINNER_PID=""  # Track spinner for cleanup

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
- MULTI-PART EXPERIENCES: For games, stories, or tutorials, use FINAL: false after each chapter/segment
- Your stdout/stderr feeds back to you, so output "Chapter 1 complete. Hero HP: 50" to inform your next step
- Global variables persist across steps - declare without 'local' for state (HP=100, CHAPTER=1, INVENTORY=())

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
# STEP 1: Check for required tools and create solar system animation
# Generated: 2026-01-31 11:42:01 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    # Check if we have basic animation tools available
    if command -v tput &>/dev/null; then
        echo "TPUT_AVAILABLE"
    else
        echo "TPUT_NOT_AVAILABLE"
    fi
    
    # Check terminal size
    echo "TERM_COLS=$(tput cols 2>/dev/null || echo 80)"
    echo "TERM_LINES=$(tput lines 2>/dev/null || echo 24)"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Create solar system animation with orbital mechanics
# Generated: 2026-01-31 11:42:19 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    # Solar system ASCII animation with orbiting planets
    # Terminal size from previous step: 126x76
    
    # Check for required commands
    if ! command -v bc &>/dev/null; then
        echo "ERROR: bc not installed"
        return 1
    fi
    
    # Animation parameters
    WIDTH=126
    HEIGHT=76
    CENTER_X=$((WIDTH / 2))
    CENTER_Y=$((HEIGHT / 2))
    
    # Planet data: name, orbital_radius, speed, size
    declare -a PLANETS=(
        "☿:8:0.4:1"      # Mercury
        "♀:12:0.3:1"     # Venus  
        "⊕:16:0.2:1"     # Earth
        "♂:20:0.15:1"    # Mars
        "♃:28:0.08:2"    # Jupiter
        "♄:36:0.06:2"    # Saturn
        "♅:42:0.04:1"    # Uranus
        "♆:48:0.03:1"    # Neptune
    )
    
    # Animation loop
    FRAME=0
    MAX_FRAMES=200
    
    clear
    tput civis  # Hide cursor
    
    while [ $FRAME -lt $MAX_FRAMES ]; do
        tput cup 0 0
        
        # Create screen buffer
        declare -A screen
        
        # Draw Sun at center
        screen["$CENTER_Y,$CENTER_X"]="☀"
        
        # Draw orbits and planets
        for planet_data in "${PLANETS[@]}"; do
            IFS=':' read -r symbol radius speed size <<< "$planet_data"
            
            # Calculate angle based on frame and speed
            angle=$(echo "scale=4; $FRAME * $speed" | bc)
            
            # Calculate position
            x=$(echo "scale=0; $CENTER_X + ($radius * c($angle))" | bc -l)
            y=$(echo "scale=0; $CENTER_Y + ($radius * s($angle) / 2)" | bc -l)
            
            # Draw orbit (every 15 degrees)
            for orbit_angle in $(seq 0 15 360); do
                rad=$(echo "scale=4; $orbit_angle * 0.0174533" | bc)
                ox=$(echo "scale=0; $CENTER_X + ($radius * c($rad))" | bc -l)
                oy=$(echo "scale=0; $CENTER_Y + ($radius * s($rad) / 2)" | bc -l)
                
                if [ $ox -ge 0 ] && [ $ox -lt $WIDTH ] && [ $oy -ge 0 ] && [ $oy -lt $HEIGHT ]; then
                    [ -z "${screen[$oy,$ox]}" ] && screen["$oy,$ox"]="·"
                fi
            done
            
            # Draw planet
            if [ $x -ge 0 ] && [ $x -lt $WIDTH ] && [ $y -ge 0 ] && [ $y -lt $HEIGHT ]; then
                screen["$y,$x"]="$symbol"
            fi
        done
        
        # Render screen
        for ((row=0; row<HEIGHT-2; row++)); do
            line=""
            for ((col=0; col<WIDTH; col++)); do
                char="${screen[$row,$col]}"
                [ -z "$char" ] && char=" "
                line+="$char"
            done
            echo "$line"
        done
        
        # Status line
        echo "Solar System Animation - Frame: $FRAME/$MAX_FRAMES - Press Ctrl+C to stop"
        
        FRAME=$((FRAME + 1))
        sleep 0.05
        
        unset screen
    done
    
    tput cnorm  # Show cursor
    echo -e "\n\nAnimation complete!"
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 4: Check current directory and files
# Generated: 2026-01-31 11:43:39 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
  echo "=== Current Directory ==="
  pwd
  echo -e "\n=== Files in current directory ==="
  ls -lah
  echo -e "\n=== Check for anything.sh script ==="
  if [ -f "anything.sh" ]; then
    echo "Found anything.sh"
    head -50 anything.sh
  else
    echo "anything.sh not found"
  fi
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Read and analyze anything.sh for performance bottlenecks
# Generated: 2026-01-31 11:43:46 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
    echo "=== Script Size ==="
    wc -l anything.sh
    
    echo -e "\n=== Checking for slow operations ==="
    grep -n "sleep\|wait\|spinner" anything.sh || echo "No obvious delays found"
    
    echo -e "\n=== Checking LLM call efficiency ==="
    grep -n "claude\|_ask" anything.sh | head -20
    
    echo -e "\n=== Current MAX_ITER setting ==="
    grep "MAX_ITER" anything.sh
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: Profile script execution to identify bottlenecks
# Generated: 2026-01-31 11:43:56 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step6() {
    cd /home/xertrov/src/anything.sh/test
    
    echo "=== Timing full script execution ==="
    time bash anything.sh "echo hello" 2>&1 | head -20
    
    echo -e "\n=== Breaking down timing ==="
    echo "1. Spinner overhead (0.1s sleeps):"
    grep -n "sleep 0.1\|sleep 0.05" anything.sh
    
    echo -e "\n2. LLM call latency:"
    echo "   - Each claude CLI call has network overhead"
    echo "   - Currently makes 1 call per iteration"
    
    echo -e "\n3. Potential optimizations:"
    echo "   - Remove/speed up spinner animations"
    echo "   - Reduce MAX_ITER default if appropriate"
    echo "   - Optimize prompt to get answers in fewer iterations"
    echo "   - Add caching headers to Claude API calls"
    
    echo -e "\n=== Check if we can add --cache flag ==="
    claude --help 2>&1 | grep -i cache || echo "No cache flag visible in help"
}
step6

# ═══════════════════════════════════════════════════════════════
# STEP 1: Echo hello to stdout
# Generated: 2026-01-31 11:44:01 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step1() { echo hello; }
step1

