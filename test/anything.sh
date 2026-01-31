#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - Autopoietic Self-Modifying Execution Loop       ║
# ║  A script that evolves by appending LLM-generated code.        ║
# ║  Provider: Groq API                                            ║
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
# ORACLE: Query Groq API with script context
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
INSTALLED TUI: $(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv nms chafa glow bat cmatrix slides fastfetch asciinema delta; do command -v $t &>/dev/null && printf "%s " "$t"; done)
${ANYTHING_EXTRA:+EXTRA: $ANYTHING_EXTRA}

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
PROMPT

    curl -s https://api.groq.com/openai/v1/chat/completions \
      -H "Authorization: Bearer $GROQ_API_KEY" -H "Content-Type: application/json" \
      -d "$(jq -n --arg p "$full_prompt" '{model:"openai/gpt-oss-120b",messages:[{role:"user",content:$p}],temperature:0.7,max_tokens:4096}')" \
      | jq -r '.choices[0].message.content // empty'
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
echo -e "\033[32m│\033[0m   provider: groq api                \033[32m│\033[0m"
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
# STEP 1: Ask user to start the Bash FPS demo and ensure required terminal capabilities are present
# Generated: 2026-01-31 11:54:17 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Global helpers
setup_terminal() {
    # Ensure we can control cursor and clear screen
    command -v tput >/dev/null || { echo "tput not found, required for screen handling."; exit 1; }
    # Hide cursor
    tput civis
    # Restore cursor on exit
    trap 'tput cnorm; exit' INT TERM EXIT
}
draw_frame() {
    local -n map=$1
    tput clear
    for line in "${map[@]}"; do
        echo "$line"
    done
    echo -e "\nControls: w/a/s/d = move, f = fire, q = quit"
}
init_map() {
    # Simple 10x20 map (walls around, some enemies)
    MAP=(
"####################"
"#@      #         E#"
"#   ##  #   ##      #"
"#   ##  #   ##   E  #"
"#        ####       #"
"#   E                #"
"#        ##         #"
"#   ##        ##    #"
"#          E        #"
"####################"
)
    # Player position and direction
    PLAYER_X=1
    PLAYER_Y=1
    PLAYER_DIR="right"
    SCORE=0
}
update_map() {
    # Rebuild map string array from current state
    local new_map=()
    for ((y=0; y<${#MAP[@]}; y++)); do
        line="${MAP[y]}"
        # Replace player position
        if (( y == PLAYER_Y )); then
            line="${line:0:PLAYER_X}@${line:PLAYER_X+1}"
        fi
        new_map+=("$line")
    done
    MAP=("${new_map[@]}")
}
move_player() {
    local dir=$1
    local nx=$PLAYER_X ny=$PLAYER_Y
    case $dir in
        up) ((ny--));;
        down) ((ny++));;
        left) ((nx--));;
        right) ((nx++));;
    esac
    # Check bounds and walls
    local target_char="${MAP[ny]:nx:1}"
    if [[ $target_char != "#" ]]; then
        PLAYER_X=$nx
        PLAYER_Y=$ny
        PLAYER_DIR=$dir
    fi
}
fire() {
    local x=$PLAYER_X y=$PLAYER_Y
    case $PLAYER_DIR in
        up) ((y--));;
        down) ((y++));;
        left) ((x--));;
        right) ((x++));;
    esac
    while (( x >= 0 && y >= 0 && x < ${#MAP[0]} && y < ${#MAP[@]} )); do
        local ch="${MAP[y]:x:1}"
        if [[ $ch == "#" ]]; then
            break
        elif [[ $ch == "E" ]]; then
            # Remove enemy
            MAP[y]="${MAP[y]:0:x} ${MAP[y]:x+1}"
            ((SCORE++))
            break
        fi
        case $PLAYER_DIR in
            up) ((y--));;
            down) ((y++));;
            left) ((x--));;
            right) ((x++));;
        esac
    done
}
game_loop() {
    while true; do
        update_map
        draw_frame MAP
        echo -e "Score: $SCORE"
        # Read single key without echo
        IFS= read -rsn1 -t 0.2 key
        case $key in
            w) move_player up ;;
            s) move_player down ;;
            a) move_player left ;;
            d) move_player right ;;
            f) fire ;;
            q) echo "Quitting..."; break ;;
        esac
    done
}
step1() {
    setup_terminal
    # Ask user if they want to start the FPS demo
    if gum confirm "Start the simple Bash FPS demo?" ; then
        init_map
        game_loop
    else
        echo "Demo aborted by user."
    fi
}
step1

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:54:17+11:00 [COMMAND="bash '/tmp/tmp.SnRKosdP6W'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# [?25l]11;?\[6n[?25l[?2004h Start the simple Bash FPS demo?       
#                                        
#     Yes        No                      
#                                        
# ←→ toggle • enter submit • y Yes • n No[126D[4A
# 
#     Yes        No                      
# 
# [126D[4A
# 
#     Yes        No                      
# 
# [126D[4A [126D[?2004l[?25h[?1002l[?1003l[?1006l####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #   ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@  ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #   ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@  ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@ ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@ ##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #        ####       #
# #   E                #
# #        ##         #
# #   ##        ##    #
# #          E        #
# ####################
#
# [...1205 lines snipped...]
#
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@           #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@           #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@           #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@           #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@           #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@          #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@         #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@         #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@        #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@       #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@       #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@       #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@@      #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@@      #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@@      #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####       #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ##   E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# ####################
# #@      #         E#
# #@@ ##  #   ##      #
# #@@@##  #   ## @ E  #
# #  @  @@@####  @    #
# #  @@@@ @@@@@@@@     #
# #    @@@@##         #
# #   ##        ##    #
# #          E        #
# ####################
# 
# Controls: w/a/s/d = move, f = fire, q = quit
# Score: 0
# Quitting...
# [?12l[?25h
# Script done on 2026-01-31 11:54:44+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 2: Complete simple Bash FPS game with movement, shooting, enemies, health, and score
# Generated: 2026-01-31 11:54:50 | FINAL: true
# ═══════════════════════════════════════════════════════════════
#!/usr/bin/env bash
# Simple Bash FPS
# Global state
MAP_WIDTH=30
MAP_HEIGHT=12
PLAYER_CHAR='@'
ENEMY_CHAR='E'
WALL_CHAR='#'
EMPTY_CHAR=' '
BULLET_CHAR='*'
PLAYER_X=2
PLAYER_Y=2
PLAYER_HP=5
SCORE=0
ENEMIES=()   # array of "x y"
BULLETS=()   # array of "x y dx dy"
WALLS=()     # array of "x y"

# Initialize map walls (border + some obstacles)
init_walls() {
  for ((x=0;x<MAP_WIDTH;x++)); do
    WALLS+=("$x 0")
    WALLS+=("$x $((MAP_HEIGHT-1))")
  done
  for ((y=0;y<MAP_HEIGHT;y++)); do
    WALLS+=("0 $y")
    WALLS+=("$((MAP_WIDTH-1)) $y")
  done
  # Add some interior walls
  for ((x=5;x<25;x++)); do
    WALLS+=("$x 5")
  done
  for ((y=2;y<9;y++)); do
    WALLS+=("15 $y")
  done
}

# Place enemies at random empty spots
spawn_enemies() {
  ENEMIES=()
  for i in {1..5}; do
    while :; do
      ex=$((RANDOM % (MAP_WIDTH-2) + 1))
      ey=$((RANDOM % (MAP_HEIGHT-2) + 1))
      if ! is_wall "$ex" "$ey" && ! is_player "$ex" "$ey"; then
        ENEMIES+=("$ex $ey")
        break
      fi
    done
  done
}

# Helper checks
is_wall() {
  local x=$1 y=$2
  for w in "${WALLS[@]}"; do
    read wx wy <<<"$w"
    ((wx==x && wy==y)) && return 0
  done
  return 1
}
is_player() {
  ((x==PLAYER_X && y==PLAYER_Y))
}
is_enemy_at() {
  local x=$1 y=$2
  for e in "${ENEMIES[@]}"; do
    read ex ey <<<"$e"
    ((ex==x && ey==y)) && return 0
  done
  return 1
}
remove_enemy_at() {
  local x=$1 y=$2
  local new=()
  for e in "${ENEMIES[@]}"; do
    read ex ey <<<"$e"
    if ((ex!=x || ey!=y)); then
      new+=("$ex $ey")
    fi
  done
  ENEMIES=("${new[@]}")
}
remove_bullet_at() {
  local x=$1 y=$2
  local new=()
  for b in "${BULLETS[@]}"; do
    read bx by dx dy <<<"$b"
    if ((bx!=x || by!=y)); then
      new+=("$bx $by $dx $dy")
    fi
  done
  BULLETS=("${new[@]}")
}

# Draw the whole screen
draw_screen() {
  tput civis
  tput clear
  for ((y=0;y<MAP_HEIGHT;y++)); do
    line=""
    for ((x=0;x<MAP_WIDTH;x++)); do
      char=$EMPTY_CHAR
      if is_wall "$x" "$y"; then
        char=$WALL_CHAR
      elif ((x==PLAYER_X && y==PLAYER_Y)); then
        char=$PLAYER_CHAR
      else
        for e in "${ENEMIES[@]}"; do
          read ex ey <<<"$e"
          if ((ex==x && ey==y)); then char=$ENEMY_CHAR; break; fi
        done
        for b in "${BULLETS[@]}"; do
          read bx by dx dy <<<"$b"
          if ((bx==x && by==y)); then char=$BULLET_CHAR; break; fi
        done
      fi
      line+="$char"
    done
    echo "$line"
  done
  echo "HP: $PLAYER_HP   Score: $SCORE   Enemies: ${#ENEMIES[@]}"
  tput cnorm
}

# Move player if possible
move_player() {
  local dir=$1
  local nx=$PLAYER_X ny=$PLAYER_Y
  case $dir in
    w) ((ny--)) ;;
    s) ((ny++)) ;;
    a) ((nx--)) ;;
    d) ((nx++)) ;;
  esac
  if ! is_wall "$nx" "$ny" && ! is_enemy_at "$nx" "$ny"; then
    PLAYER_X=$nx PLAYER_Y=$ny
  fi
}

# Fire a bullet in the direction player last moved (default up)
fire_bullet() {
  local dir=$1
  local dx=0 dy=0
  case $dir in
    w) dy=-1 ;;
    s) dy=1 ;;
    a) dx=-1 ;;
    d) dx=1 ;;
    *) dy=-1 ;; # default up
  esac
  # start bullet adjacent to player
  local bx=$((PLAYER_X+dx))
  local by=$((PLAYER_Y+dy))
  if ! is_wall "$bx" "$by"; then
    BULLETS+=("$bx $by $dx $dy")
  fi
}

# Advance bullets, handle collisions
update_bullets() {
  local new=()
  for b in "${BULLETS[@]}"; do
    read bx by dx dy <<<"$b"
    local nx=$((bx+dx)) ny=$((by+dy))
    if is_wall "$nx" "$ny"; then
      continue
    elif is_enemy_at "$nx" "$ny"; then
      remove_enemy_at "$nx" "$ny"
      ((SCORE++))
      continue
    else
      new+=("$nx $ny $dx $dy")
    fi
  done
  BULLETS=("${new[@]}")
}

# Simple enemy AI: move towards player if not blocked
update_enemies() {
  local new=()
  for e in "${ENEMIES[@]}"; do
    read ex ey <<<"$e"
    local dx=$((PLAYER_X-ex))
    local dy=$((PLAYER_Y-ey))
    # Normalize to -1,0,1
    ((dx>0)) && dx=1 || ((dx<0)) && dx=-1 || dx=0
    ((dy>0)) && dy=1 || ((dy<0)) && dy=-1 || dy=0
    local nx=$((ex+dx)) ny=$((ey+dy))
    if ((nx==PLAYER_X && ny==PLAYER_Y)); then
      ((PLAYER_HP--))
      # enemy stays in place after hit
      new+=("$ex $ey")
    elif ! is_wall "$nx" "$ny" && ! is_enemy_at "$nx" "$ny" && ! is_player "$nx" "$ny"; then
      new+=("$nx $ny")
    else
      new+=("$ex $ey")
    fi
  done
  ENEMIES=("${new[@]}")
}

# Main game loop
game_loop() {
  local last_dir='w'
  while (( PLAYER_HP > 0 )); do
    draw_screen
    # Non-blocking read with timeout for smoother loop
    read -rsn1 -t 0.2 key
    case $key in
      w|a|s|d) move_player "$key"; last_dir=$key ;;
      f| ) fire_bullet "$last_dir" ;;
      q) echo "Quitting..."; break ;;
    esac
    update_bullets
    update_enemies
    # Respawn enemies if all dead
    (( ${#ENEMIES[@]} == 0 )) && spawn_enemies
  done
  tput clear
  echo "Game Over! Final Score: $SCORE"
}

# Initialize everything
init_walls
spawn_enemies
draw_screen
echo "Press any key to start..."
read -rsn1
game_loop

# End of script

# No need to call step2; script runs on execution.

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:54:50+11:00 [COMMAND="bash '/tmp/tmp.bswzaArk7b'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# /tmp/tmp.bswzaArk7b: line 212: syntax error near unexpected token `)'
# /tmp/tmp.bswzaArk7b: line 212: `      f| ) fire_bullet "$last_dir" ;;'
# 
# Script done on 2026-01-31 11:54:50+11:00 [COMMAND_EXIT_CODE="2"]

# ═══════════════════════════════════════════════════════════════
# STEP 3: Show the contents of the script that caused the syntax error so we can locate and fix the malformed case pattern
# Generated: 2026-01-31 11:54:51 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
    script_path="/tmp/tmp.bswzaArk7b"
    if [[ -f "$script_path" ]]; then
        echo "=== BEGIN $script_path ==="
        cat "$script_path"
        echo "=== END $script_path ==="
    else
        echo "Script file not found at $script_path"
    fi
}
step3

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:54:51+11:00 [COMMAND="bash '/tmp/tmp.w6CuSYzf81'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# Script file not found at /tmp/tmp.bswzaArk7b
# 
# Script done on 2026-01-31 11:54:51+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 4: Initialize and run a simple text‑based FPS loop in bash (player can turn, move, and shoot enemies on a small grid)
# Generated: 2026-01-31 11:54:54 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Global helpers -------------------------------------------------
clear_screen() { printf "\033[H\033[2J"; }
hide_cursor() { printf "\033[?25l"; }
show_cursor() { printf "\033[?25h"; }
# --------------------------------------------------------------

# Game state ----------------------------------------------------
MAP_WIDTH=15
MAP_HEIGHT=9
# Simple open map with walls (#) around edges
declare -A MAP
for ((y=0; y<MAP_HEIGHT; y++)); do
    for ((x=0; x<MAP_WIDTH; x++)); do
        if (( x==0 || y==0 || x==MAP_WIDTH-1 || y==MAP_HEIGHT-1 )); then
            MAP[$x,$y]='#'   # wall
        else
            MAP[$x,$y]=' '   # empty space
        fi
    done
done

# Player state
PX=7; PY=5            # start near centre
PDIR=0               # 0=N,1=E,2=S,3=W
# Enemies (list of x,y)
ENEMIES=()
ENEMIES+=("3,3")
ENEMIES+=("11,2")
ENEMIES+=("12,7")
# --------------------------------------------------------------

# Utility --------------------------------------------------------
direction_name() {
    case $1 in
        0) echo "N";;
        1) echo "E";;
        2) echo "S";;
        3) echo "W";;
    esac
}
# --------------------------------------------------------------

# Rendering ------------------------------------------------------
draw_map() {
    clear_screen
    for ((y=0; y<MAP_HEIGHT; y++)); do
        for ((x=0; x<MAP_WIDTH; x++)); do
            if (( x==PX && y==PY )); then
                # player arrow based on direction
                case $PDIR in
                    0) printf "^";;
                    1) printf ">";;
                    2) printf "v";;
                    3) printf "<";;
                esac
            else
                # check enemy
                local found=0
                for e in "${ENEMIES[@]}"; do
                    IFS=',' read -r ex ey <<<"$e"
                    if (( ex==x && ey==y )); then
                        printf "E"
                        found=1
                        break
                    fi
                done
                ((found)) || printf "${MAP[$x,$y]}"
            fi
        done
        printf "\n"
    done
    printf "\nUse arrow keys to move/turn, SPACE to shoot, Q to quit.\n"
    printf "Facing: %s  Enemies left: %d\n" "$(direction_name $PDIR)" "${#ENEMIES[@]}"
}
# --------------------------------------------------------------

# Game logic -----------------------------------------------------
move_forward() {
    local nx=$PX ny=$PY
    case $PDIR in
        0) ((ny--));;
        1) ((nx++));;
        2) ((ny++));;
        3) ((nx--));;
    esac
    # collision with walls
    if [[ "${MAP[$nx,$ny]}" != "#" ]]; then
        PX=$nx; PY=$ny
    fi
}
move_backward() {
    local nx=$PX ny=$PY
    case $PDIR in
        0) ((ny++));;
        1) ((nx--));;
        2) ((ny--));;
        3) ((nx++));;
    esac
    if [[ "${MAP[$nx,$ny]}" != "#" ]]; then
        PX=$nx; PY=$ny
    fi
}
turn_left() { ((PDIR=(PDIR+3)%4)); }
turn_right() { ((PDIR=(PDIR+1)%4)); }

shoot() {
    # Raycast in facing direction until wall or max range 10
    local sx=$PX sy=$PY
    for ((step=1; step<=10; step++)); do
        case $PDIR in
            0) ((sy--));;
            1) ((sx++));;
            2) ((sy++));;
            3) ((sx--));;
        esac
        # stop at wall
        if [[ "${MAP[$sx,$sy]}" == "#" ]]; then
            break
        fi
        # check enemy
        local i=0
        for e in "${ENEMIES[@]}"; do
            IFS=',' read -r ex ey <<<"$e"
            if (( ex==sx && ey==sy )); then
                # remove enemy
                unset 'ENEMIES[i]'
                ENEMIES=("${ENEMIES[@]}")   # reindex
                printf "\a"   # beep
                break 2
            fi
            ((i++))
        done
    done
}
# --------------------------------------------------------------

# Input handling -------------------------------------------------
read_key() {
    # read one key, handling escape sequences for arrows
    IFS= read -rsn1 -t 0.1 key || return 1
    if [[ $key == $'\e' ]]; then
        IFS= read -rsn2 -t 0.01 rest
        key+=$rest
    fi
    echo "$key"
}
# --------------------------------------------------------------

# Main loop ------------------------------------------------------
step4() {
    hide_cursor
    trap 'show_cursor; clear_screen; exit' INT TERM EXIT
    draw_map
    while true; do
        key=$(read_key) || continue
        case "$key" in
            $'\e[A') move_forward;;      # Up arrow
            $'\e[B') move_backward;;     # Down arrow
            $'\e[D') turn_left;;         # Left arrow
            $'\e[C') turn_right;;        # Right arrow
            " ") shoot;;                 # Space
            [qQ]) break;;                # Quit
        esac
        draw_map
        # win condition
        if (( ${#ENEMIES[@]} == 0 )); then
            printf "\nAll enemies eliminated! You win!\n"
            break
        fi
    done
    show_cursor
    printf "\nThanks for playing.\n"
}
step4

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:54:54+11:00 [COMMAND="bash '/tmp/tmp.PxW2WcFOYm'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# [?25l###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      ^      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      >      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      ^      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      ^      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      <      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      v      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      >      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      >      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      >      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      v      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      v      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #      <      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #     <       #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #    <        #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #   <         #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #  <          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 3
# ###############
# #             #
# #          E  #
# #  E          #
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 3
# ###############
# #             #
# #          E  #
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 2
# ###############
# #             #
# #          E  #
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 2
# ###############
# #             #
# #          E  #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 2
# ###############
# #             #
# #  ^       E  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 2
# ###############
# #             #
# #  >       E  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 2
# ###############
# #             #
# #  >          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #  v          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #  <          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 1
# ###############
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 1
# ###############
# #             #
# #  >          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #  v          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #  v          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #  v          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #  v          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #  >          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 1
# ###############
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 1
# ###############
# #             #
# #  ^          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: N  Enemies left: 1
# ###############
# #             #
# #  >          #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #   >         #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #    >        #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #     >       #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #      >      #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ^[[A###############
# #             #
# #       >     #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #        >    #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #         >   #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #          >  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #          v  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #          v  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #          <  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: W  Enemies left: 1
# ###############
# #             #
# #          v  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #          >  #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #           > #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: E  Enemies left: 1
# ###############
# #             #
# #           v #
# #             #
# #           E #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 1
# ###############
# #             #
# #           v #
# #             #
# ###############
# 
# Use arrow keys to move/turn, SPACE to shoot, Q to quit.
# Facing: S  Enemies left: 0
# 
# All enemies eliminated! You win!
# [?25h
# Thanks for playing.
# [?25h
# Script done on 2026-01-31 11:55:20+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 5: Task complete – simple Bash FPS game finished and user won.
# Generated: 2026-01-31 11:55:20 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step5() { echo "FPS game completed successfully. No further action needed."; }
step5

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:55:20+11:00 [COMMAND="bash '/tmp/tmp.CNGY1g8094'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# FPS game completed successfully. No further action needed.
# 
# Script done on 2026-01-31 11:55:20+11:00 [COMMAND_EXIT_CODE="0"]


# ═══════════════════════════════════════════════════════════════
# STEP 6: Show intro title with figlet/boxes and ask user to start the demo
# Generated: 2026-01-31 11:55:36 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Helper functions (persist across steps)
display_title() {
    # Generate a big title and frame it
    figlet -c "Adventure Demo" 2>/dev/null | boxes -d ascii -p a
}
prompt_start() {
    # Ask user to confirm starting the demo
    if gum confirm "Ready to embark on the adventure?" --default=true; then
        echo "STARTED=1"
    else
        echo "STARTED=0"
    fi
}

step6() {
    display_title
    prompt_start
}
step6

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:55:36+11:00 [COMMAND="bash '/tmp/tmp.KdQwxxWM6R'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# boxes: invalid padding specification - a
# ]11;?\[6n[?25l[?2004h Ready to embark on the adventure?     
#                                        
#     Yes        No                      
#                                        
# ←→ toggle • enter submit • y Yes • n No[126D[4A [126D[?2004l[?25h[?1002l[?1003l[?1006lSTARTED=1
# 
# Script done on 2026-01-31 11:55:41+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 7: Initialize helper functions and display an impressive intro scene with title, ASCII art, and a choice prompt
# Generated: 2026-01-31 11:55:43 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Global helper functions
display_title() {
    # Use figlet to render a big title, then wrap with boxes for framing
    local txt="$1"
    figlet -c "$txt" | boxes -d simple -p a
}
slow_print() {
    # Print text slowly, character by character, using pv for effect
    local txt="$1"
    echo -n "$txt" | pv -qL 30
    echo
}
show_art() {
    # Show optional ASCII art from a heredoc, with optional slow effect
    local art="$1"
    local speed="${2:-0}"
    if (( speed > 0 )); then
        echo "$art" | pv -qL "$speed"
    else
        echo "$art"
    fi
}
prompt_choice() {
    # Use gum to present a list of options; returns the selected string
    local prompt="$1"
    shift
    local options=("$@")
    gum choose --cursor.foreground="#ff6c6b" --cursor.background="#1e2127" \
        --selected.foreground="#98c379" --selected.background="#1e2127" \
        --height=15 --width=50 --header="$prompt" "${options[@]}"
}
# Step 7: demo scene
step7() {
    clear
    # 1️⃣ Title
    display_title "Adventure Demo"

    # 2️⃣ Intro narrative (slow)
    slow_print "Welcome, brave traveler, to the realm of Bashonia."
    sleep 1
    slow_print "Legends speak of a hidden treasure guarded by the mighty *Shell Dragon*."
    sleep 1

    # 3️⃣ Simple ASCII art of a dragon (slow reveal)
    local dragon_art="
          / \\  //\\
     |\\___/|      /\\
     /0  0\\     /  \\
    /\\   /\\    /\\_/\\
   /  \\_/  \\  /      \\
"
    show_art "$dragon_art" 20
    sleep 1

    # 4️⃣ Present a choice
    local choice
    choice=$(prompt_choice "What will you do?" \
        "Approach the dragon cautiously" \
        "Search for a hidden path" \
        "Retreat to the village")
    # Store for later steps
    CHOICE="$choice"
    echo
    slow_print "You chose: $CHOICE"
}
step7

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:55:43+11:00 [COMMAND="bash '/tmp/tmp.Xujya2y99k'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
# boxes: invalid padding specification - a
# Welcome, brave traveler, to the realm of Bashonia.
# Legends speak of a hidden treasure guarded by the mighty *Shell Dragon*.
# 
#           / \  //\
#      |\___/|      /\
#      /0  0\     /  \
#     /\   /\    /\_/\
#    /  \_/  \  /      \
# 
# gum: error: unknown flag --width
# 
# You chose: Usage: gum choose [<options> ...] [flags]
# 
# Choose an option from a list of choices
# 
# Arguments:
#   [<options> ...]    Options to choose from.
# 
# Flags:
#   -h, --help                      Show context-sensitive help.
#   -v, --version                   Print the version number
# 
#       --ordered                   Maintain the order of the selected options
#                                   ($GUM_CHOOSE_ORDERED)
#       --height=10                 Height of the list ($GUM_CHOOSE_HEIGHT)
#       --cursor="> "               Prefix to show on item that corresponds to the
#                                   cursor position ($GUM_CHOOSE_CURSOR)
#       --[no-]show-help            Show help keybinds ($GUM_CHOOSE_SHOW_HELP)
#       --timeout=0s                Timeout until choose returns selected element
#                                   ($GUM_CHOOSE_TIMEOUT)
#       --header="Choose:"          Header value ($GUM_CHOOSE_HEADER)
#       --cursor-prefix="• "        Prefix to show on the cursor item (hidden if
#                                   limit is 1) ($GUM_CHOOSE_CURSOR_PREFIX)
#       --selected-prefix="✓ "      Prefix to show on selected items (hidden if
#                                   limit is 1) ($GUM_CHOOSE_SELECTED_PREFIX)
#       --unselected-prefix="• "
#                                   Prefix to show on unselected items (hidden if
#                                   limit is 1) ($GUM_CHOOSE_UNSELECTED_PREFIX)
#       --selected=,...             Options that should start as selected (selects
#                                   all if given *) ($GUM_CHOOSE_SELECTED)
#       --input-delimiter="\n"      Option delimiter when reading from STDIN
#                                   ($GUM_CHOOSE_INPUT_DELIMITER)
#       --output-delimiter="\n"     Option delimiter when writing to STDOUT
#                                   ($GUM_CHOOSE_OUTP^C
# 
# Script done on 2026-01-31 11:56:57+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 8: Present an animated Bashonia scene with title, story text, and a choice menu using figlet, pv, and whiptail
# Generated: 2026-01-31 11:57:00 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Global state
HP=100
INVENTORY=()
CHAPTER=1

# Helper: display a centered title using figlet
show_title() {
    figlet -c "Bashonia Quest"
    echo
}

# Helper: type out text slowly (characters per second)
type_text() {
    local text="$1"
    echo -e "$text" | pv -qL 30
    echo
}

# Helper: present a whiptail menu and return the chosen tag
present_menu() {
    local title="$1"
    shift
    local options=("$@")   # expects tag description pairs
    whiptail --title "$title" --menu "Choose your destiny:" 15 60 4 "${options[@]}" 3>&1 1>&2 2>&3
}

# Scene logic
step8() {
    clear
    show_title

    type_text "Welcome, brave traveler, to the realm of Bashonia.\nLegends speak of a hidden treasure guarded by the mighty *Shell Dragon*.\n"

    type_text "You find yourself at the mouth of a dark cavern. The air is thick with the scent of ozone.\n"

    type_text "A low rumble echoes from within... The Shell Dragon emerges, its scales shimmering with terminal colors.\n"

    # Present choices
    CHOICE=$(present_menu "The Encounter" \
        "1" "Fight the dragon with your trusty script" \
        "2" "Flee back to safety" \
        "3" "Attempt to reason with the dragon")

    case "$CHOICE" in
        1)
            type_text "You brandish your keyboard and launch a flurry of commands!\n"
            type_text "The dragon snarls as your code slices through its firewall.\n"
            HP=$((HP - 30))
            INVENTORY+=("Dragon Scale")
            type_text "You defeat the dragon but suffer wounds. HP is now $HP.\nYou acquire a Dragon Scale."
            ;;
        2)
            type_text "You turn tail and sprint out of the cavern, heart pounding.\n"
            HP=$((HP - 10))
            type_text "You escape, but the dragon's fiery breath singes you. HP is now $HP."
            ;;
        3)
            type_text "You raise your hands in peace and speak the ancient Bash incantation:\n"
            type_text "\"echo 'Hello, mighty dragon!'\n\""
            type_text "The dragon pauses, intrigued by your polite syntax.\n"
            type_text "It grants you safe passage and a gift: a mystical .bashrc.\n"
            INVENTORY+=(".bashrc of Wisdom")
            type_text "Your inventory now contains: ${INVENTORY[*]}"
            ;;
        *)
            type_text "You stand frozen, indecision paralyzing you. The dragon devours you."
            HP=0
            ;;
    esac

    # Summary
    echo
    echo "=== Chapter $CHAPTER Summary ==="
    echo "HP: $HP"
    echo "Inventory: ${INVENTORY[*]}"
    echo "=============================="
}
step8

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:57:00+11:00 [COMMAND="bash '/tmp/tmp.WnZvHaRNqN'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
#      ____            _                 _          ___                  _   
#     | __ )  __ _ ___| |__   ___  _ __ (_) __ _   / _ \ _   _  ___  ___| |_ 
#     |  _ \ / _` / __| '_ \ / _ \| '_ \| |/ _` | | | | | | | |/ _ \/ __| __|
#     | |_) | (_| \__ \ | | | (_) | | | | | (_| | | |_| | |_| |  __/\__ \ |_ 
#     |____/ \__,_|___/_| |_|\___/|_| |_|_|\__,_|  \__\_\\__,_|\___||___/\__|
#                                                                            
# 
# Welcome, brave traveler, to the realm of Bashonia.
# Legends speak of a hidden treasure guarded by the mighty *Shell Dragon*.
# 
# You find yourself at the mouth of a dark cavern. The air is thick with the scent of ozone.
# 
# A low rumble echoes from within... The Shell Dragon emerges, its scales shimmering with terminal colors.
# 
# [?1049h[22;0;0t[1;76r[4l[?25l(B[1;76r
# 
# ┌────────────────────┤ The Encounter ├─────────────────────┐│ Choose your destiny:                                     │ │                                                          │ │        1 Fight the dragon with your trusty script        │ │        2 Flee back to safety                             │ │        3 Attempt to reason with the dragon               │ │                                                          │ │                                                          │ │                                                          │ │                                                          │ │                                                          │ │                                                          │ │              <Ok>                  <Cancel>              │ │                                                          │ └──────────────────────────────────────────────────────────┘                                                             1 Fight the dragon with your trusty script2 Flee back to safety                     2 Flee back to safety                     3 Attempt to reason with the dragon       [A2 Flee back to safety                     3 Attempt to reason with the dragon       [A1 Fight the dragon with your trusty script2 Flee back to safety                     [?12l[?25h(B[?1049l[23;0;0tYou brandish your keyboard and launch a flurry of commands!
# 
# The dragon snarls as your code slices through its firewall.
# 
# You defeat the dragon but suffer wounds. HP is now 70.
# You acquire a Dragon Scale.
# 
# === Chapter 1 Summary ===
# HP: 70
# Inventory: Dragon Scale
# ==============================
# 
# Script done on 2026-01-31 11:57:21+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 9: Continue the Bashonia adventure with a dramatic scene, present choices, and update hero state
# Generated: 2026-01-31 11:57:24 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Global state (persisted across steps)
HP=${HP:-70}
INVENTORY=(${INVENTORY[@]:-Dragon\ Scale})
CHAPTER=${CHAPTER:-1}
# Helper: slow typewriter effect
slow_echo() {
    local text="$1"
    echo -e "$text" | pv -qL 30
}
# Helper: display hero status in a box
display_status() {
    local status="🗡️  HP: $HP   📦 Inventory: ${INVENTORY[*]}"
    boxes -d double -p a <<<"$status"
}
# Helper: present choices using gum
choose_action() {
    gum choose \
        "🔎 Explore deeper into the cavern" \
        "🛏️ Rest at the safe nook (heal 20 HP)" \
        "🔮 Inspect the Dragon Scale"
}
# Main scene
step9() {
    clear
    # Intro art
    figlet -c "Chapter $((CHAPTER+1))"
    echo
    slow_echo "The cavern walls glimmer with phosphorescent moss, casting eerie shadows.\n"
    slow_echo "A faint, rhythmic drumming echoes from the darkness ahead, as if some ancient heart beats within the stone.\n"
    slow_echo "You feel the weight of the Dragon Scale against your chest, its surface still warm from the battle.\n"
    echo
    display_status
    echo
    # Prompt user
    ACTION=$(choose_action)
    echo
    case "$ACTION" in
        "🔎 Explore deeper into the cavern")
            slow_echo "\nYou venture further, your footsteps echoing.\n"
            sleep 1
            slow_echo "Suddenly, a hidden alcove reveals a chest pulsing with a soft golden light.\n"
            INVENTORY+=("Golden Chest")
            slow_echo "You obtain a *Golden Chest*! It might contain something valuable.\n"
            ;;
        "🛏️ Rest at the safe nook (heal 20 HP)")
            slow_echo "\nYou find a cozy nook, its walls lined with soft moss.\n"
            sleep 1
            ((HP+=20))
            ((HP>100)) && HP=100
            slow_echo "You rest for a while, feeling your wounds mend. (+20 HP)\n"
            ;;
        "🔮 Inspect the Dragon Scale")
            slow_echo "\nYou hold the Dragon Scale up to the dim light.\n"
            sleep 1
            slow_echo "Its iridescent surface shimmers, revealing faint runes.\n"
            slow_echo "The runes whisper a secret: *'Only the brave may claim the treasure beyond the fire.'*\n"
            ;;
    esac
    echo
    # Update chapter and show status
    ((CHAPTER++))
    display_status
    echo
    slow_echo "\n--- End of Chapter $CHAPTER ---\n"
}
step9

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 11:57:24+11:00 [COMMAND="bash '/tmp/tmp.UDYdVrEold'" TERM="xterm-256color" TTY="/dev/pts/4" COLUMNS="126" LINES="76"]
#                    ____ _                 _              ____  
#                   / ___| |__   __ _ _ __ | |_ ___ _ __  |___ \ 
#                  | |   | '_ \ / _` | '_ \| __/ _ \ '__|   __) |
#                  | |___| | | | (_| | |_) | ||  __/ |     / __/ 
#                   \____|_| |_|\__,_| .__/ \__\___|_|    |_____|
#                                    |_|                         
# 
# The cavern walls glimmer with phosphorescent moss, casting eerie shadows.
# 
# A faint, rhythmic drumming echoes from the darkness ahead, as if some ancient heart beats within the stone.
# 
# You feel the weight of the Dragon Scale against your chest, its surface still warm from the battle.
# 
# boxes: invalid padding specification - a
# 
# [?25l[?2004hChoose:                                
# > 🔎 Explore deeper into the cavern    
#   🛏️ Rest at the safe nook (heal 20 HP)
#   🔮 Inspect the Dragon Scale          
#                                        
# ←↓↑→ navigate • enter submit           [126D[6A
#   🔎 Explore deeper into the cavern    
# > 🛏️ Rest at the safe nook (heal 20 HP)
# 
# [126D[6A
# 
#   🛏️ Rest at the safe nook (heal 20 HP)
# > 🔮 Inspect the Dragon Scale          
# 
# [126D[6A [126D[?2004l[?25h[?1002l[?1003l[?1006l
# 
# You hold the Dragon Scale up to the dim light.
# 
# Its iridescent surface shimmers, revealing faint runes.
# 
# The runes whisper a secret: *'Only the brave may claim the treasure beyond the fire.'*
# 
# boxes: invalid padding specification - a
# 
# --- End of Chapter 2 ---
# 
# Script done on 2026-01-31 11:57:47+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 10: Chapter 3 – Ember Hall, present choices and update state
# Generated: 2026-01-31 11:57:51 | FINAL: false
# ═══════════════════════════════════════════════════════════════
# Global state (persist across steps)
: "${HP:=100}"
: "${CHAPTER:=2}"
: "${INVENTORY:=()}"   # bash array

# Helper: slow text reveal (uses pv if available, falls back to echo)
display_text() {
  if command -v pv >/dev/null; then
    echo -e "$1" | pv -qL 30
  else
    echo -e "$1"
  fi
}

# Helper: show current status
show_status() {
  echo -e "\n\033[1;33m[Status]\033[0m HP: $HP"
  if ((${#INVENTORY[@]})); then
    echo -e "Inventory: ${INVENTORY[*]}"
  else
    echo -e "Inventory: (empty)"
  fi
  echo
}

# Helper: present choices via gum (fallback to read)
present_choices() {
  local opts=("$@")
  if command -v gum >/dev/null; then
    gum choose "${opts[@]}"
  else
    echo "Choose an option:"
    select opt in "${opts[@]}"; do
      [[ -n "$opt" ]] && echo "$opt" && break
    done
  fi
}

step10() {
  # Advance chapter counter
  CHAPTER=$((CHAPTER + 1))

  display_text "\n=== Chapter $CHAPTER: The Ember Hall ===\n"
  display_text "The tunnel widens into a vast hall bathed in the orange glow of a river of molten lava.\n"
  display_text "Heat washes over you, and the roar of fire echoes off the stone walls.\n"

  show_status

  # Player choices
  local choice
  choice=$(present_choices \
    "Advance to the lava bridge" \
    "Inspect the stone altar" \
    "Invoke the Dragon Scale")

  case "$choice" in
    "Advance to the lava bridge")
      display_text "\nYou step onto a precarious stone bridge spanning the lava.\n"
      # 20% chance of taking damage
      if (( RANDOM % 5 == 0 )); then
        HP=$((HP - 15))
        display_text "A sudden burst of heat singes your arm! (-15 HP)\n"
      else
        display_text "You cross safely, the heat strengthening your resolve.\n"
      fi
      ;;
    "Inspect the stone altar")
      display_text "\nThe altar bears carvings identical to the runes on the Dragon Scale.\n"
      display_text "A hidden compartment slides open, revealing a glowing ruby.\n"
      INVENTORY+=("Ruby of Ember")
      display_text "You acquire the Ruby of Ember.\n"
      ;;
    "Invoke the Dragon Scale")
      if [[ " ${INVENTORY[*]} " == *"Dragon Scale"* ]]; then
        display_text "\nYou raise the Dragon Scale. Its fire awakens, forming a protective shield around you.\n"
        display_text "You feel rejuvenated. (+20 HP)\n"
        HP=$((HP + 20))
        # Remove the scale after use (optional)
        INVENTORY=("${INVENTORY[@]/Dragon Scale}")
      else
        display_text "\nYou fumble for the Dragon Scale, but it is not in your possession.\n"
      fi
      ;;
    *)
      display_text "\nIndecision holds you in place. The lava hisses.\n"
      ;;
  esac

  # Cap HP at 100 and avoid negative values
  (( HP > 100 )) && HP=100
  (( HP < 0 )) && HP=0

  show_status

  echo "Chapter $CHAPTER complete. HP: $HP"
}

step10
