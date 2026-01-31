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
TUI: $(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv; do command -v $t &>/dev/null && printf "%s " "$t"; done)

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
- USER INPUT: Don't assume on vague tasks - ask. Use whiptail/dialog for polished UX, or 'read -rp' as fallback
- Set FINAL: false after asking - response appears in next feedback
- For interactive experiences: use the best available tools (TUI, colors, ASCII art) to make something impressive
- When asking for input, ensure the user can see what they need to decide - pause after animations, recap after long output
- Prefer fewer, more substantial steps over many small ones - each LLM call is expensive
- For long experiences, define reusable helper functions early - they persist across steps

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
# STEP 1: Initialize D&D-style text adventure with character creation
# Generated: 2026-01-31 09:55:02 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    clear
    
    # Game state variables (persist across steps)
    PLAYER_NAME=""
    PLAYER_CLASS=""
    PLAYER_RACE=""
    HP=0
    MAX_HP=0
    STR=0
    DEX=0
    CON=0
    INT=0
    WIS=0
    CHA=0
    GOLD=10
    XP=0
    LEVEL=1
    INVENTORY=()
    CURRENT_LOCATION="tavern"
    CHAPTER=1
    
    # Roll 3d6
    roll_3d6() {
        echo $(( (RANDOM % 6 + 1) + (RANDOM % 6 + 1) + (RANDOM % 6 + 1) ))
    }
    
    # Title screen
    echo -e "\033[1;33m"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║   ⚔️  REALMS OF SHADOWMIRE ⚔️                                  ║
    ║                                                               ║
    ║        A D&D-Style Text Adventure                             ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "\033[0m"
    sleep 1
    
    # Character name
    PLAYER_NAME=$(whiptail --inputbox "Enter your hero's name:" 10 40 "Adventurer" 3>&1 1>&2 2>&3)
    [ -z "$PLAYER_NAME" ] && PLAYER_NAME="Adventurer"
    
    # Race selection
    PLAYER_RACE=$(whiptail --menu "Choose your race:" 16 50 6 \
        "Human" "+1 to all stats, versatile" \
        "Elf" "+2 DEX, +1 INT, darkvision" \
        "Dwarf" "+2 CON, +1 STR, sturdy" \
        "Halfling" "+2 DEX, +1 CHA, lucky" \
        3>&1 1>&2 2>&3)
    [ -z "$PLAYER_RACE" ] && PLAYER_RACE="Human"
    
    # Class selection
    PLAYER_CLASS=$(whiptail --menu "Choose your class:" 16 50 6 \
        "Fighter" "High HP, martial weapons, STR-based" \
        "Rogue" "Sneak attack, traps, DEX-based" \
        "Wizard" "Powerful spells, low HP, INT-based" \
        "Cleric" "Healing magic, armor, WIS-based" \
        3>&1 1>&2 2>&3)
    [ -z "$PLAYER_CLASS" ] && PLAYER_CLASS="Fighter"
    
    # Roll base stats
    STR=$(roll_3d6)
    DEX=$(roll_3d6)
    CON=$(roll_3d6)
    INT=$(roll_3d6)
    WIS=$(roll_3d6)
    CHA=$(roll_3d6)
    
    # Apply racial bonuses
    case $PLAYER_RACE in
        "Human") ((STR++)); ((DEX++)); ((CON++)); ((INT++)); ((WIS++)); ((CHA++)) ;;
        "Elf") ((DEX+=2)); ((INT++)) ;;
        "Dwarf") ((CON+=2)); ((STR++)) ;;
        "Halfling") ((DEX+=2)); ((CHA++)) ;;
    esac
    
    # Calculate HP based on class
    case $PLAYER_CLASS in
        "Fighter") BASE_HP=10; INVENTORY=("Longsword" "Chain Mail" "Shield") ;;
        "Rogue") BASE_HP=8; INVENTORY=("Daggers" "Leather Armor" "Thieves Tools") ;;
        "Wizard") BASE_HP=6; INVENTORY=("Staff" "Spellbook" "Robes") ;;
        "Cleric") BASE_HP=8; INVENTORY=("Mace" "Scale Mail" "Holy Symbol") ;;
    esac
    
    CON_MOD=$(( (CON - 10) / 2 ))
    MAX_HP=$(( BASE_HP + CON_MOD ))
    [ $MAX_HP -lt 1 ] && MAX_HP=1
    HP=$MAX_HP
    
    # Display character sheet
    clear
    echo -e "\033[1;36m╔═══════════════════════════════════════╗\033[0m"
    echo -e "\033[1;36m║       CHARACTER CREATED!              ║\033[0m"
    echo -e "\033[1;36m╚═══════════════════════════════════════╝\033[0m"
    echo ""
    echo -e "\033[1;33m  $PLAYER_NAME\033[0m"
    echo -e "  Level $LEVEL $PLAYER_RACE $PLAYER_CLASS"
    echo ""
    echo -e "\033[1;31m  ❤️  HP: $HP/$MAX_HP\033[0m"
    echo -e "\033[1;33m  💰 Gold: $GOLD\033[0m"
    echo -e "\033[1;35m  ✨ XP: $XP\033[0m"
    echo ""
    echo -e "\033[1;32m  ═══ STATS ═══\033[0m"
    echo "  STR: $STR  DEX: $DEX  CON: $CON"
    echo "  INT: $INT  WIS: $WIS  CHA: $CHA"
    echo ""
    echo -e "\033[1;34m  ═══ INVENTORY ═══\033[0m"
    for item in "${INVENTORY[@]}"; do
        echo "  • $item"
    done
    echo ""
    
    # Export state for next step
    echo "STATE:NAME=$PLAYER_NAME|RACE=$PLAYER_RACE|CLASS=$PLAYER_CLASS|HP=$HP|MAX_HP=$MAX_HP|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|CHAPTER=1|LOCATION=tavern|INVENTORY=${INVENTORY[*]}"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Continue adventure with tavern scene and first quest
# Generated: 2026-01-31 09:55:48 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    # Parse state from previous output
    STATE="NAME=Bob|RACE=Human|CLASS=Fighter|HP=10|MAX_HP=10|STR=9|DEX=11|CON=10|INT=11|WIS=11|CHA=13|GOLD=10|XP=0|LEVEL=1|CHAPTER=1|LOCATION=tavern|INVENTORY=Longsword Chain Mail Shield"
    
    # Extract values
    NAME="Bob"
    RACE="Human"
    CLASS="Fighter"
    HP=10
    MAX_HP=10
    STR=9
    DEX=11
    CON=10
    INT=11
    WIS=11
    CHA=13
    GOLD=10
    XP=0
    LEVEL=1
    LOCATION="tavern"
    INVENTORY="Longsword Chain Mail Shield"
    
    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
    
    # Function to show status bar
    show_status() {
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}$NAME${NC} | ${RED}❤️ HP: $HP/$MAX_HP${NC} | ${YELLOW}💰 $GOLD gp${NC} | ${MAGENTA}✨ XP: $XP${NC} | ${GREEN}Lvl $LEVEL $RACE $CLASS${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    }
    
    # Roll dice function
    roll_d20() {
        echo $((RANDOM % 20 + 1))
    }
    
    clear
    echo ""
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}                    CHAPTER 1: THE TROUBLED TAVERN                     ${NC}"
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    show_status
    echo ""
    
    # Tavern scene
    echo -e "${CYAN}You sit in the corner of the ${BOLD}Rusty Flagon Tavern${NC}${CYAN}, nursing a mug of ale.${NC}"
    echo -e "${CYAN}The fire crackles warmly, but the mood is tense.${NC}"
    echo ""
    sleep 1
    
    echo -e "${GREEN}A weathered old man approaches your table, his eyes filled with worry.${NC}"
    echo ""
    sleep 1
    
    echo -e "${MAGENTA}\"Please, adventurer,\"${NC} he whispers urgently."
    echo -e "${MAGENTA}\"My daughter was taken by goblins! They dragged her to the old mines${NC}"
    echo -e "${MAGENTA}north of town. I'll pay you ${YELLOW}50 gold${MAGENTA} if you bring her back safely!\"${NC}"
    echo ""
    sleep 1
    
    # Choice
    CHOICE=$(whiptail --title "🍺 The Rusty Flagon Tavern" --menu "\nWhat do you do?" 18 60 5 \
        "1" "Accept the quest heroically" \
        "2" "Demand more gold (Charisma check)" \
        "3" "Ask for more information first" \
        "4" "Refuse and order another ale" \
        3>&1 1>&2 2>&3)
    
    case $CHOICE in
        1)
            echo ""
            echo -e "${GREEN}\"Fear not, good sir! I shall rescue your daughter!\"${NC}"
            echo -e "${CYAN}The old man weeps with gratitude and hands you a ${YELLOW}healing potion${CYAN}.${NC}"
            INVENTORY="$INVENTORY Healing_Potion"
            XP=$((XP + 10))
            echo -e "${MAGENTA}+10 XP | Gained: Healing Potion${NC}"
            QUEST="rescue"
            ;;
        2)
            ROLL=$(roll_d20)
            CHA_MOD=$(( (CHA - 10) / 2 ))
            TOTAL=$((ROLL + CHA_MOD))
            echo ""
            echo -e "${YELLOW}Charisma Check: Rolled $ROLL + $CHA_MOD (CHA) = $TOTAL (DC 12)${NC}"
            sleep 1
            if [ $TOTAL -ge 12 ]; then
                echo -e "${GREEN}SUCCESS!${NC} The old man agrees to pay ${YELLOW}75 gold${NC} instead!"
                GOLD=$((GOLD + 25))
                XP=$((XP + 15))
                echo -e "${MAGENTA}+15 XP | +25 gold advance${NC}"
            else
                echo -e "${RED}FAILED!${NC} The old man looks hurt. \"That's all I have...please...\" "
                echo -e "${CYAN}Feeling guilty, you accept the original offer.${NC}"
                XP=$((XP + 5))
            fi
            QUEST="rescue"
            ;;
        3)
            echo ""
            echo -e "${CYAN}\"Tell me more about these goblins,\" you say thoughtfully.${NC}"
            echo ""
            echo -e "${MAGENTA}\"There's about 5-6 of them, led by a larger hobgoblin called ${RED}Skrag${MAGENTA}.${NC}"
            echo -e "${MAGENTA}The old mines have two entrances - the main shaft and a hidden${NC}"
            echo -e "${MAGENTA}ventilation tunnel on the east side. Here, take this map.\"${NC}"
            INVENTORY="$INVENTORY Mine_Map"
            XP=$((XP + 20))
            echo -e "${MAGENTA}+20 XP | Gained: Mine Map (reveals secret entrance!)${NC}"
            QUEST="rescue"
            ;;
        4)
            echo ""
            echo -e "${CYAN}You wave the old man away. \"Not my problem.\"${NC}"
            echo -e "${RED}The old man stumbles away, broken.${NC}"
            sleep 1
            echo ""
            echo -e "${YELLOW}Suddenly, a hooded figure slides into the seat across from you.${NC}"
            echo -e "${MAGENTA}\"Cold-hearted. I like that. I have a... different kind of job.${NC}"
            echo -e "${MAGENTA}There's a merchant caravan coming through tomorrow. ${YELLOW}100 gold${MAGENTA}${NC}"
            echo -e "${MAGENTA}to make sure it never arrives. Interested?\"${NC}"
            QUEST="dark"
            XP=$((XP + 5))
            ;;
    esac
    
    echo ""
    sleep 2
    
    # Output state for next iteration
    echo ""
    echo "STATE:NAME=$NAME|RACE=$RACE|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|CHAPTER=1|LOCATION=$LOCATION|INVENTORY=$INVENTORY|QUEST=$QUEST"
}
step2
