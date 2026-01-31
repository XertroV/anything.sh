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
            script -q -e -c "bash -c 'eval \"$code\"'" "$tmpfile"
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
# STEP 1: Check for available tools and create text adventure game
# Generated: 2026-01-31 09:19:44 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    # Check what we have available
    echo "=== System Check ==="
    command -v figlet &>/dev/null && echo "figlet: YES" || echo "figlet: NO"
    command -v cowsay &>/dev/null && echo "cowsay: YES" || echo "cowsay: NO"
    
    # Create the D&D text adventure
    cat << 'GAME' > /tmp/dnd_adventure.sh
#!/bin/bash

# D&D Style Text Adventure - Fantasy Quest
# Character Stats
declare -A STATS
STATS[STR]=10
STATS[DEX]=10
STATS[CON]=10
STATS[INT]=10
STATS[WIS]=10
STATS[CHA]=10
HP=20
MAX_HP=20
GOLD=10
XP=0
LEVEL=1
INVENTORY=("Rusty Sword" "Torch")

clear
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     ⚔️  THE CAVERNS OF SHADOW  ⚔️                          ║"
echo "║         A D&D Style Text Adventure                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Roll stats
roll_stat() {
    echo $(( (RANDOM % 6 + 1) + (RANDOM % 6 + 1) + (RANDOM % 6 + 1) ))
}

show_stats() {
    echo "┌─────────────────────────────────┐"
    echo "│ CHARACTER SHEET                 │"
    echo "├─────────────────────────────────┤"
    printf "│ HP: %d/%d  GOLD: %d  XP: %d     \n" $HP $MAX_HP $GOLD $XP
    printf "│ LEVEL: %d                       \n" $LEVEL
    echo "├─────────────────────────────────┤"
    printf "│ STR: %-2d  DEX: %-2d  CON: %-2d     │\n" ${STATS[STR]} ${STATS[DEX]} ${STATS[CON]}
    printf "│ INT: %-2d  WIS: %-2d  CHA: %-2d     │\n" ${STATS[INT]} ${STATS[WIS]} ${STATS[CHA]}
    echo "├─────────────────────────────────┤"
    echo "│ INVENTORY:                      │"
    for item in "${INVENTORY[@]}"; do
        printf "│  • %-28s│\n" "$item"
    done
    echo "└─────────────────────────────────┘"
}

roll_d20() {
    echo $(( RANDOM % 20 + 1 ))
}

echo "Rolling your stats (3d6 each)..."
sleep 1
STATS[STR]=$(roll_stat)
STATS[DEX]=$(roll_stat)
STATS[CON]=$(roll_stat)
STATS[INT]=$(roll_stat)
STATS[WIS]=$(roll_stat)
STATS[CHA]=$(roll_stat)
MAX_HP=$((10 + (STATS[CON] - 10) / 2))
HP=$MAX_HP

echo ""
show_stats
echo ""

echo "You stand at the entrance to the CAVERNS OF SHADOW."
echo "Legends speak of treasure... and terrible monsters within."
echo ""

# Game loop
LOCATION="entrance"
GAME_OVER=false

while [ "$GAME_OVER" = false ]; do
    case $LOCATION in
        "entrance")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "CAVERN ENTRANCE"
            echo "Cold air flows from the dark opening before you."
            echo "Bones are scattered near the entrance."
            echo ""
            echo "What do you do?"
            echo "  [1] Enter the cavern"
            echo "  [2] Search the bones"
            echo "  [3] Check stats"
            echo "  [4] Quit"
            read -p "> " choice
            case $choice in
                1) LOCATION="main_hall";;
                2) 
                    roll=$(roll_d20)
                    echo "🎲 Investigation check: $roll + $((( ${STATS[INT]} - 10) / 2))"
                    if [ $roll -ge 10 ]; then
                        echo "You find 5 gold coins among the bones!"
                        GOLD=$((GOLD + 5))
                    else
                        echo "You find nothing but dust and regret."
                    fi
                    ;;
                3) show_stats;;
                4) GAME_OVER=true;;
            esac
            ;;
        "main_hall")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "MAIN HALL"
            echo "A vast cavern opens before you. Stalactites hang"
            echo "like stone fangs. Three passages lead deeper."
            echo "You hear growling from the LEFT passage..."
            echo ""
            echo "What do you do?"
            echo "  [1] Take the LEFT passage (growling)"
            echo "  [2] Take the CENTER passage (faint light)"
            echo "  [3] Take the RIGHT passage (quiet)"
            echo "  [4] Return to entrance"
            echo "  [5] Check stats"
            read -p "> " choice
            case $choice in
                1) LOCATION="goblin_lair";;
                2) LOCATION="treasure_room";;
                3) LOCATION="trap_corridor";;
                4) LOCATION="entrance";;
                5) show_stats;;
            esac
            ;;
        "goblin_lair")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚔️  COMBAT! A GOBLIN attacks!"
            echo ""
            GOBLIN_HP=7
            while [ $GOBLIN_HP -gt 0 ] && [ $HP -gt 0 ]; do
                echo "Goblin HP: $GOBLIN_HP | Your HP: $HP"
                echo "  [1] Attack  [2] Flee"
                read -p "> " choice
                if [ "$choice" = "1" ]; then
                    roll=$(roll_d20)
                    attack=$((roll + (STATS[STR] - 10) / 2))
                    echo "🎲 Attack roll: $roll + $((( ${STATS[STR]} - 10) / 2)) = $attack"
                    if [ $attack -ge 12 ]; then
                        dmg=$((RANDOM % 6 + 1))
                        echo "✓ HIT! You deal $dmg damage!"
                        GOBLIN_HP=$((GOBLIN_HP - dmg))
                    else
                        echo "✗ Miss!"
                    fi
                    if [ $GOBLIN_HP -gt 0 ]; then
                        groll=$(roll_d20)
                        if [ $groll -ge 10 ]; then
                            gdmg=$((RANDOM % 4 + 1))
                            echo "The goblin strikes you for $gdmg damage!"
                            HP=$((HP - gdmg))
                        else
                            echo "The goblin misses!"
                        fi
                    fi
                else
                    echo "You flee back to the main hall!"
                    LOCATION="main_hall"
                    break
                fi
            done
            if [ $HP -le 0 ]; then
                echo ""
                echo "☠️  YOU HAVE DIED  ☠️"
                echo "The goblin stands victorious over your corpse."
                GAME_OVER=true
            elif [ $GOBLIN_HP -le 0 ]; then
                echo ""
                echo "🏆 VICTORY! The goblin falls!"
                echo "You gain 25 XP and find 8 gold!"
                XP=$((XP + 25))
                GOLD=$((GOLD + 8))
                LOCATION="main_hall"
            fi
            ;;
        "treasure_room")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "TREASURE ROOM"
            echo "Golden light fills this chamber! A chest sits"
            echo "on a pedestal. But wait... is that a trap?"
            echo ""
            echo "  [1] Open the chest carefully"
            echo "  [2] Smash it open"
            echo "  [3] Leave"
            read -p "> " choice
            case $choice in
                1)
                    roll=$(roll_d20)
                    check=$((roll + (STATS[DEX] - 10) / 2))
                    echo "🎲 Dexterity check: $roll + $((( ${STATS[DEX]} - 10) / 2)) = $check"
                    if [ $check -ge 12 ]; then
                        echo "You carefully disarm the trap and open the chest!"
                        echo "Inside: 50 GOLD and a MAGIC SWORD!"
                        GOLD=$((GOLD + 50))
                        INVENTORY+=("Magic Sword (+2)")
                        XP=$((XP + 50))
                        echo ""
                        echo "🎉 QUEST COMPLETE! You've found the treasure!"
                        echo "Final Stats:"
                        show_stats
                        GAME_OVER=true
                    else
                        echo "CLICK! A poison dart hits you for 5 damage!"
                        HP=$((HP - 5))
                        if [ $HP -le 0 ]; then
                            echo "☠️  YOU HAVE DIED  ☠️"
                            GAME_OVER=true
                        else
                            echo "You grab 20 gold and flee!"
                            GOLD=$((GOLD + 20))
                            LOCATION="main_hall"
                        fi
                    fi
                    ;;
                2)
                    echo "CRASH! The trap triggers! 8 damage!"
                    HP=$((HP - 8))
                    if [ $HP -le 0 ]; then
                        echo "☠️  YOU HAVE DIED  ☠️"
                        GAME_OVER=true
                    else
                        echo "You grab what you can: 30 gold!"
                        GOLD=$((GOLD + 30))
                        LOCATION="main_hall"
                    fi
                    ;;
                3) LOCATION="main_hall";;
            esac
            ;;
        "trap_corridor")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "TRAP CORRIDOR"
            echo "The floor is covered with suspicious tiles..."
            roll=$(roll_d20)
            check=$((roll + (STATS[WIS] - 10) / 2))
            echo "🎲 Wisdom (Perception) check: $roll + $((( ${STATS[WIS]} - 10) / 2)) = $check"
            if [ $check -ge 14 ]; then
                echo "You spot the safe path and find a HEALING POTION!"
                INVENTORY+=("Healing Potion")
            else
                echo "You trigger a trap! 4 damage!"
                HP=$((HP - 4))
                if [ $HP -le 0 ]; then
                    echo "☠️  YOU HAVE DIED  ☠️"
                    GAME_OVER=true
                fi
            fi
            if [ "$GAME_OVER" = false ]; then
                LOCATION="main_hall"
            fi
            ;;
    esac
    echo ""
done

echo ""
echo "Thanks for playing THE CAVERNS OF SHADOW!"
echo "Final Score: $GOLD gold, $XP experience"
GAME

    chmod +x /tmp/dnd_adventure.sh
    echo ""
    echo "=== Game Created ==="
    echo "Location: /tmp/dnd_adventure.sh"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Create and run D&D text adventure game
# Generated: 2026-01-31 09:20:24 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step2() {
    cat << 'GAME' > /tmp/dnd_adventure.sh
#!/bin/bash

# D&D Style Text Adventure - Fantasy Quest
# Character Stats
declare -A STATS
STATS[STR]=10
STATS[DEX]=10
STATS[CON]=10
STATS[INT]=10
STATS[WIS]=10
STATS[CHA]=10
HP=20
MAX_HP=20
GOLD=10
XP=0
LEVEL=1
INVENTORY=("Rusty Sword" "Torch")

clear
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     ⚔️  THE CAVERNS OF SHADOW  ⚔️                          ║"
echo "║         A D&D Style Text Adventure                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

roll_stat() {
    echo $(( (RANDOM % 6 + 1) + (RANDOM % 6 + 1) + (RANDOM % 6 + 1) ))
}

show_stats() {
    echo "┌─────────────────────────────────┐"
    echo "│ CHARACTER SHEET                 │"
    echo "├─────────────────────────────────┤"
    printf "│ HP: %d/%d  GOLD: %d  XP: %d     \n" $HP $MAX_HP $GOLD $XP
    printf "│ LEVEL: %d                       \n" $LEVEL
    echo "├─────────────────────────────────┤"
    printf "│ STR: %-2d  DEX: %-2d  CON: %-2d     │\n" ${STATS[STR]} ${STATS[DEX]} ${STATS[CON]}
    printf "│ INT: %-2d  WIS: %-2d  CHA: %-2d     │\n" ${STATS[INT]} ${STATS[WIS]} ${STATS[CHA]}
    echo "├─────────────────────────────────┤"
    echo "│ INVENTORY:                      │"
    for item in "${INVENTORY[@]}"; do
        printf "│  • %-28s│\n" "$item"
    done
    echo "└─────────────────────────────────┘"
}

roll_d20() {
    echo $(( RANDOM % 20 + 1 ))
}

echo "Rolling your stats (3d6 each)..."
sleep 1
STATS[STR]=$(roll_stat)
STATS[DEX]=$(roll_stat)
STATS[CON]=$(roll_stat)
STATS[INT]=$(roll_stat)
STATS[WIS]=$(roll_stat)
STATS[CHA]=$(roll_stat)
MAX_HP=$((10 + (STATS[CON] - 10) / 2))
HP=$MAX_HP

echo ""
show_stats
echo ""

echo "You stand at the entrance to the CAVERNS OF SHADOW."
echo "Legends speak of treasure... and terrible monsters within."
echo ""

LOCATION="entrance"
GAME_OVER=false

while [ "$GAME_OVER" = false ]; do
    case $LOCATION in
        "entrance")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "CAVERN ENTRANCE"
            echo "Cold air flows from the dark opening before you."
            echo "Bones are scattered near the entrance."
            echo ""
            echo "What do you do?"
            echo "  [1] Enter the cavern"
            echo "  [2] Search the bones"
            echo "  [3] Check stats"
            echo "  [4] Quit"
            read -p "> " choice
            case $choice in
                1) LOCATION="main_hall";;
                2) 
                    roll=$(roll_d20)
                    mod=$(( (STATS[INT] - 10) / 2 ))
                    echo "🎲 Investigation check: $roll + $mod"
                    if [ $roll -ge 10 ]; then
                        echo "You find 5 gold coins among the bones!"
                        GOLD=$((GOLD + 5))
                    else
                        echo "You find nothing but dust and regret."
                    fi
                    ;;
                3) show_stats;;
                4) GAME_OVER=true;;
            esac
            ;;
        "main_hall")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "MAIN HALL"
            echo "A vast cavern opens before you. Stalactites hang"
            echo "like stone fangs. Three passages lead deeper."
            echo "You hear growling from the LEFT passage..."
            echo ""
            echo "What do you do?"
            echo "  [1] Take the LEFT passage (growling)"
            echo "  [2] Take the CENTER passage (faint light)"
            echo "  [3] Take the RIGHT passage (quiet)"
            echo "  [4] Return to entrance"
            echo "  [5] Check stats"
            read -p "> " choice
            case $choice in
                1) LOCATION="goblin_lair";;
                2) LOCATION="treasure_room";;
                3) LOCATION="trap_corridor";;
                4) LOCATION="entrance";;
                5) show_stats;;
            esac
            ;;
        "goblin_lair")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚔️  COMBAT! A GOBLIN attacks!"
            echo ""
            GOBLIN_HP=7
            while [ $GOBLIN_HP -gt 0 ] && [ $HP -gt 0 ]; do
                echo "Goblin HP: $GOBLIN_HP | Your HP: $HP"
                echo "  [1] Attack  [2] Flee"
                read -p "> " choice
                if [ "$choice" = "1" ]; then
                    roll=$(roll_d20)
                    mod=$(( (STATS[STR] - 10) / 2 ))
                    attack=$((roll + mod))
                    echo "🎲 Attack roll: $roll + $mod = $attack"
                    if [ $attack -ge 12 ]; then
                        dmg=$((RANDOM % 6 + 1))
                        echo "✓ HIT! You deal $dmg damage!"
                        GOBLIN_HP=$((GOBLIN_HP - dmg))
                    else
                        echo "✗ Miss!"
                    fi
                    if [ $GOBLIN_HP -gt 0 ]; then
                        groll=$(roll_d20)
                        if [ $groll -ge 10 ]; then
                            gdmg=$((RANDOM % 4 + 1))
                            echo "The goblin strikes you for $gdmg damage!"
                            HP=$((HP - gdmg))
                        else
                            echo "The goblin misses!"
                        fi
                    fi
                else
                    echo "You flee back to the main hall!"
                    LOCATION="main_hall"
                    break
                fi
            done
            if [ $HP -le 0 ]; then
                echo ""
                echo "☠️  YOU HAVE DIED  ☠️"
                GAME_OVER=true
            elif [ $GOBLIN_HP -le 0 ]; then
                echo ""
                echo "🏆 VICTORY! The goblin falls!"
                echo "You gain 25 XP and find 8 gold!"
                XP=$((XP + 25))
                GOLD=$((GOLD + 8))
                LOCATION="main_hall"
            fi
            ;;
        "treasure_room")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "TREASURE ROOM"
            echo "Golden light fills this chamber! A chest sits"
            echo "on a pedestal. But wait... is that a trap?"
            echo ""
            echo "  [1] Open the chest carefully"
            echo "  [2] Smash it open"
            echo "  [3] Leave"
            read -p "> " choice
            case $choice in
                1)
                    roll=$(roll_d20)
                    mod=$(( (STATS[DEX] - 10) / 2 ))
                    check=$((roll + mod))
                    echo "🎲 Dexterity check: $roll + $mod = $check"
                    if [ $check -ge 12 ]; then
                        echo "You carefully disarm the trap and open the chest!"
                        echo "Inside: 50 GOLD and a MAGIC SWORD!"
                        GOLD=$((GOLD + 50))
                        INVENTORY+=("Magic Sword (+2)")
                        XP=$((XP + 50))
                        echo ""
                        echo "🎉 QUEST COMPLETE! You have found the treasure!"
                        echo "Final Stats:"
                        show_stats
                        GAME_OVER=true
                    else
                        echo "CLICK! A poison dart hits you for 5 damage!"
                        HP=$((HP - 5))
                        if [ $HP -le 0 ]; then
                            echo "☠️  YOU HAVE DIED  ☠️"
                            GAME_OVER=true
                        else
                            echo "You grab 20 gold and flee!"
                            GOLD=$((GOLD + 20))
                            LOCATION="main_hall"
                        fi
                    fi
                    ;;
                2)
                    echo "CRASH! The trap triggers! 8 damage!"
                    HP=$((HP - 8))
                    if [ $HP -le 0 ]; then
                        echo "☠️  YOU HAVE DIED  ☠️"
                        GAME_OVER=true
                    else
                        echo "You grab what you can: 30 gold!"
                        GOLD=$((GOLD + 30))
                        LOCATION="main_hall"
                    fi
                    ;;
                3) LOCATION="main_hall";;
            esac
            ;;
        "trap_corridor")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "TRAP CORRIDOR"
            echo "The floor is covered with suspicious tiles..."
            roll=$(roll_d20)
            mod=$(( (STATS[WIS] - 10) / 2 ))
            check=$((roll + mod))
            echo "🎲 Wisdom (Perception) check: $roll + $mod = $check"
            if [ $check -ge 14 ]; then
                echo "You spot the safe path and find a HEALING POTION!"
                INVENTORY+=("Healing Potion")
            else
                echo "You trigger a trap! 4 damage!"
                HP=$((HP - 4))
                if [ $HP -le 0 ]; then
                    echo "☠️  YOU HAVE DIED  ☠️"
                    GAME_OVER=true
                fi
            fi
            if [ "$GAME_OVER" = false ]; then
                LOCATION="main_hall"
            fi
            ;;
    esac
    echo ""
done

echo ""
echo "Thanks for playing THE CAVERNS OF SHADOW!"
echo "Final Score: $GOLD gold, $XP experience"
GAME

    chmod +x /tmp/dnd_adventure.sh
    echo "=== D&D Text Adventure Created ==="
    echo "Starting game..."
    echo ""
    /tmp/dnd_adventure.sh
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Create and run D&D text adventure with fixed quoting
# Generated: 2026-01-31 09:20:50 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step3() {
    cat << 'GAME' > /tmp/dnd_adventure.sh
#!/bin/bash

# D&D Style Text Adventure - Fantasy Quest
# Character Stats
declare -A STATS
STATS[STR]=10
STATS[DEX]=10
STATS[CON]=10
STATS[INT]=10
STATS[WIS]=10
STATS[CHA]=10
HP=20
MAX_HP=20
GOLD=10
XP=0
LEVEL=1
INVENTORY=("Rusty Sword" "Torch")

clear
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     ⚔️  THE CAVERNS OF SHADOW  ⚔️                          ║"
echo "║         A D&D Style Text Adventure                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

roll_stat() {
    echo $(( (RANDOM % 6 + 1) + (RANDOM % 6 + 1) + (RANDOM % 6 + 1) ))
}

show_stats() {
    echo "┌─────────────────────────────────┐"
    echo "│ CHARACTER SHEET                 │"
    echo "├─────────────────────────────────┤"
    printf "│ HP: %d/%d  GOLD: %d  XP: %d     \n" $HP $MAX_HP $GOLD $XP
    printf "│ LEVEL: %d                       \n" $LEVEL
    echo "├─────────────────────────────────┤"
    printf "│ STR: %-2d  DEX: %-2d  CON: %-2d     │\n" ${STATS[STR]} ${STATS[DEX]} ${STATS[CON]}
    printf "│ INT: %-2d  WIS: %-2d  CHA: %-2d     │\n" ${STATS[INT]} ${STATS[WIS]} ${STATS[CHA]}
    echo "├─────────────────────────────────┤"
    echo "│ INVENTORY:                      │"
    for item in "${INVENTORY[@]}"; do
        printf "│  • %-28s│\n" "$item"
    done
    echo "└─────────────────────────────────┘"
}

roll_d20() {
    echo $(( RANDOM % 20 + 1 ))
}

echo "Rolling your stats (3d6 each)..."
sleep 1
STATS[STR]=$(roll_stat)
STATS[DEX]=$(roll_stat)
STATS[CON]=$(roll_stat)
STATS[INT]=$(roll_stat)
STATS[WIS]=$(roll_stat)
STATS[CHA]=$(roll_stat)
MAX_HP=$((10 + (STATS[CON] - 10) / 2))
HP=$MAX_HP

echo ""
show_stats
echo ""

echo "You stand at the entrance to the CAVERNS OF SHADOW."
echo "Legends speak of treasure... and terrible monsters within."
echo ""

LOCATION="entrance"
GAME_OVER=false

while [ "$GAME_OVER" = false ]; do
    case $LOCATION in
        "entrance")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "CAVERN ENTRANCE"
            echo "Cold air flows from the dark opening before you."
            echo "Bones are scattered near the entrance."
            echo ""
            echo "What do you do?"
            echo "  [1] Enter the cavern"
            echo "  [2] Search the bones"
            echo "  [3] Check stats"
            echo "  [4] Quit"
            read -p "> " choice
            case $choice in
                1) LOCATION="main_hall";;
                2) 
                    roll=$(roll_d20)
                    mod=$(( (STATS[INT] - 10) / 2 ))
                    echo "🎲 Investigation check: $roll + $mod"
                    if [ $roll -ge 10 ]; then
                        echo "You find 5 gold coins among the bones!"
                        GOLD=$((GOLD + 5))
                    else
                        echo "You find nothing but dust and regret."
                    fi
                    ;;
                3) show_stats;;
                4) GAME_OVER=true;;
            esac
            ;;
        "main_hall")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "MAIN HALL"
            echo "A vast cavern opens before you. Stalactites hang"
            echo "like stone fangs. Three passages lead deeper."
            echo "You hear growling from the LEFT passage..."
            echo ""
            echo "What do you do?"
            echo "  [1] Take the LEFT passage (growling)"
            echo "  [2] Take the CENTER passage (faint light)"
            echo "  [3] Take the RIGHT passage (quiet)"
            echo "  [4] Return to entrance"
            echo "  [5] Check stats"
            read -p "> " choice
            case $choice in
                1) LOCATION="goblin_lair";;
                2) LOCATION="treasure_room";;
                3) LOCATION="trap_corridor";;
                4) LOCATION="entrance";;
                5) show_stats;;
            esac
            ;;
        "goblin_lair")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚔️  COMBAT! A GOBLIN attacks!"
            echo ""
            GOBLIN_HP=7
            while [ $GOBLIN_HP -gt 0 ] && [ $HP -gt 0 ]; do
                echo "Goblin HP: $GOBLIN_HP | Your HP: $HP"
                echo "  [1] Attack  [2] Flee"
                read -p "> " choice
                if [ "$choice" = "1" ]; then
                    roll=$(roll_d20)
                    mod=$(( (STATS[STR] - 10) / 2 ))
                    attack=$((roll + mod))
                    echo "🎲 Attack roll: $roll + $mod = $attack"
                    if [ $attack -ge 12 ]; then
                        dmg=$((RANDOM % 6 + 1))
                        echo "✓ HIT! You deal $dmg damage!"
                        GOBLIN_HP=$((GOBLIN_HP - dmg))
                    else
                        echo "✗ Miss!"
                    fi
                    if [ $GOBLIN_HP -gt 0 ]; then
                        groll=$(roll_d20)
                        if [ $groll -ge 10 ]; then
                            gdmg=$((RANDOM % 4 + 1))
                            echo "The goblin strikes you for $gdmg damage!"
                            HP=$((HP - gdmg))
                        else
                            echo "The goblin misses!"
                        fi
                    fi
                else
                    echo "You flee back to the main hall!"
                    LOCATION="main_hall"
                    break
                fi
            done
            if [ $HP -le 0 ]; then
                echo ""
                echo "☠️  YOU HAVE DIED  ☠️"
                GAME_OVER=true
            elif [ $GOBLIN_HP -le 0 ]; then
                echo ""
                echo "🏆 VICTORY! The goblin falls!"
                echo "You gain 25 XP and find 8 gold!"
                XP=$((XP + 25))
                GOLD=$((GOLD + 8))
                LOCATION="main_hall"
            fi
            ;;
        "treasure_room")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "TREASURE ROOM"
            echo "Golden light fills this chamber! A chest sits"
            echo "on a pedestal. But wait... is that a trap?"
            echo ""
            echo "  [1] Open the chest carefully"
            echo "  [2] Smash it open"
            echo "  [3] Leave"
            read -p "> " choice
            case $choice in
                1)
                    roll=$(roll_d20)
                    mod=$(( (STATS[DEX] - 10) / 2 ))
                    check=$((roll + mod))
                    echo "🎲 Dexterity check: $roll + $mod = $check"
                    if [ $check -ge 12 ]; then
                        echo "You carefully disarm the trap and open the chest!"
                        echo "Inside: 50 GOLD and a MAGIC SWORD!"
                        GOLD=$((GOLD + 50))
                        INVENTORY+=("Magic Sword (+2)")
                        XP=$((XP + 50))
                        echo ""
                        echo "🎉 QUEST COMPLETE! You have found the treasure!"
                        echo "Final Stats:"
                        show_stats
                        GAME_OVER=true
                    else
                        echo "CLICK! A poison dart hits you for 5 damage!"
                        HP=$((HP - 5))
                        if [ $HP -le 0 ]; then
                            echo "☠️  YOU HAVE DIED  ☠️"
                            GAME_OVER=true
                        else
                            echo "You grab 20 gold and flee!"
                            GOLD=$((GOLD + 20))
                            LOCATION="main_hall"
                        fi
                    fi
                    ;;
                2)
                    echo "CRASH! The trap triggers! 8 damage!"
                    HP=$((HP - 8))
                    if [ $HP -le 0 ]; then
                        echo "☠️  YOU HAVE DIED  ☠️"
                        GAME_OVER=true
                    else
                        echo "You grab what you can: 30 gold!"
                        GOLD=$((GOLD + 30))
                        LOCATION="main_hall"
                    fi
                    ;;
                3) LOCATION="main_hall";;
            esac
            ;;
        "trap_corridor")
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "TRAP CORRIDOR"
            echo "The floor is covered with suspicious tiles..."
            roll=$(roll_d20)
            mod=$(( (STATS[WIS] - 10) / 2 ))
            check=$((roll + mod))
            echo "🎲 Wisdom (Perception) check: $roll + $mod = $check"
            if [ $check -ge 14 ]; then
                echo "You spot the safe path and find a HEALING POTION!"
                INVENTORY+=("Healing Potion")
            else
                echo "You trigger a trap! 4 damage!"
                HP=$((HP - 4))
                if [ $HP -le 0 ]; then
                    echo "☠️  YOU HAVE DIED  ☠️"
                    GAME_OVER=true
                fi
            fi
            if [ "$GAME_OVER" = false ]; then
                LOCATION="main_hall"
            fi
            ;;
    esac
    echo ""
done

echo ""
echo "Thanks for playing THE CAVERNS OF SHADOW!"
echo "Final Score: $GOLD gold, $XP experience"
GAME
    chmod +x /tmp/dnd_adventure.sh
    echo "=== D&D Text Adventure Created ==="
    echo "Starting game..."
    echo ""
    /tmp/dnd_adventure.sh
}
step3
