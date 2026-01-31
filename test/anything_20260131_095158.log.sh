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
# Generated: 2026-01-31 09:51:07 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    clear
    
    # Game state - persists across steps
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
    
    # Title screen
    echo -e "\033[1;33m"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║   ⚔️  REALMS OF THE FORGOTTEN CROWN ⚔️                        ║
    ║                                                               ║
    ║        A Text Adventure in the Style of Dungeons & Dragons    ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "\033[0m"
    
    # Character name
    PLAYER_NAME=$(whiptail --inputbox "Enter your hero's name:" 10 40 "Adventurer" --title "Character Creation" 3>&1 1>&2 2>&3)
    [ -z "$PLAYER_NAME" ] && PLAYER_NAME="Adventurer"
    
    # Race selection
    PLAYER_RACE=$(whiptail --menu "Choose your race:" 16 50 6 \
        "Human" "+1 to all stats, versatile" \
        "Elf" "+2 DEX, +1 INT, darkvision" \
        "Dwarf" "+2 CON, +1 STR, poison resist" \
        "Halfling" "+2 DEX, +1 CHA, lucky" \
        "Orc" "+2 STR, +1 CON, intimidating" \
        --title "Race Selection" 3>&1 1>&2 2>&3)
    [ -z "$PLAYER_RACE" ] && PLAYER_RACE="Human"
    
    # Class selection
    PLAYER_CLASS=$(whiptail --menu "Choose your class:" 16 55 5 \
        "Fighter" "HP:12 | STR-based | Heavy armor, weapons" \
        "Rogue" "HP:8 | DEX-based | Stealth, sneak attack" \
        "Wizard" "HP:6 | INT-based | Arcane spells" \
        "Cleric" "HP:10 | WIS-based | Divine magic, healing" \
        "Ranger" "HP:10 | DEX-based | Archery, tracking" \
        --title "Class Selection" 3>&1 1>&2 2>&3)
    [ -z "$PLAYER_CLASS" ] && PLAYER_CLASS="Fighter"
    
    # Roll stats (4d6 drop lowest simulation)
    roll_stat() {
        local rolls=()
        for i in {1..4}; do rolls+=($((RANDOM % 6 + 1))); done
        IFS=$'\n' sorted=($(sort -n <<<"${rolls[*]}")); unset IFS
        echo $(( sorted[1] + sorted[2] + sorted[3] ))
    }
    
    STR=$(roll_stat); DEX=$(roll_stat); CON=$(roll_stat)
    INT=$(roll_stat); WIS=$(roll_stat); CHA=$(roll_stat)
    
    # Apply racial bonuses
    case $PLAYER_RACE in
        "Human") ((STR++)); ((DEX++)); ((CON++)); ((INT++)); ((WIS++)); ((CHA++)) ;;
        "Elf") ((DEX+=2)); ((INT++)) ;;
        "Dwarf") ((CON+=2)); ((STR++)) ;;
        "Halfling") ((DEX+=2)); ((CHA++)) ;;
        "Orc") ((STR+=2)); ((CON++)) ;;
    esac
    
    # Set HP based on class
    case $PLAYER_CLASS in
        "Fighter") MAX_HP=$((12 + (CON-10)/2)); INVENTORY=("Longsword" "Shield" "Chainmail") ;;
        "Rogue") MAX_HP=$((8 + (CON-10)/2)); INVENTORY=("Dagger" "Shortbow" "Thieves Tools") ;;
        "Wizard") MAX_HP=$((6 + (CON-10)/2)); INVENTORY=("Staff" "Spellbook" "Component Pouch") ;;
        "Cleric") MAX_HP=$((10 + (CON-10)/2)); INVENTORY=("Mace" "Holy Symbol" "Shield") ;;
        "Ranger") MAX_HP=$((10 + (CON-10)/2)); INVENTORY=("Longbow" "Shortsword" "Quiver") ;;
    esac
    HP=$MAX_HP
    
    # Output state for next step
    echo "CHARACTER_CREATED"
    echo "NAME:$PLAYER_NAME|RACE:$PLAYER_RACE|CLASS:$PLAYER_CLASS"
    echo "HP:$HP/$MAX_HP|STR:$STR|DEX:$DEX|CON:$CON|INT:$INT|WIS:$WIS|CHA:$CHA"
    echo "GOLD:$GOLD|XP:$XP|LEVEL:$LEVEL"
    echo "INVENTORY:${INVENTORY[*]}"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Start the text adventure gameplay loop with first encounter
# Generated: 2026-01-31 09:51:48 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    # Restore character state from previous step
    NAME="Bro"
    RACE="Human"
    CLASS="Fighter"
    HP=12
    MAX_HP=12
    STR=12
    DEX=9
    CON=9
    INT=10
    WIS=14
    CHA=17
    GOLD=10
    XP=0
    LEVEL=1
    INVENTORY=("Longsword" "Shield" "Chainmail")
    
    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
    
    # Dice roll function
    roll_d20() {
        echo $((RANDOM % 20 + 1))
    }
    
    roll_dice() {
        local sides=$1
        echo $((RANDOM % sides + 1))
    }
    
    # Display stats bar
    show_stats() {
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}$NAME${NC} the $RACE $CLASS (Lvl $LEVEL) ${CYAN}│${NC} HP: ${GREEN}$HP/$MAX_HP${NC} ${CYAN}│${NC} Gold: ${YELLOW}$GOLD${NC} ${CYAN}│${NC} XP: $XP"
        echo -e "${CYAN}║${NC} STR:$STR DEX:$DEX CON:$CON INT:$INT WIS:$WIS CHA:$CHA"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    }
    
    # Combat function
    combat() {
        local enemy_name=$1
        local enemy_hp=$2
        local enemy_ac=$3
        local enemy_damage=$4
        
        echo -e "\n${RED}⚔️  COMBAT: $enemy_name appears!${NC}"
        echo -e "Enemy HP: $enemy_hp | Enemy AC: $enemy_ac\n"
        
        while [[ $enemy_hp -gt 0 && $HP -gt 0 ]]; do
            # Player attack
            local attack_roll=$(roll_d20)
            local str_mod=$(( (STR - 10) / 2 ))
            local total_attack=$((attack_roll + str_mod))
            
            echo -e "${CYAN}You swing your Longsword! Roll: $attack_roll + $str_mod = $total_attack${NC}"
            
            if [[ $total_attack -ge $enemy_ac ]]; then
                local damage=$(($(roll_dice 8) + str_mod))
                [[ $damage -lt 1 ]] && damage=1
                enemy_hp=$((enemy_hp - damage))
                echo -e "${GREEN}HIT! You deal $damage damage. Enemy HP: $enemy_hp${NC}"
            else
                echo -e "${YELLOW}MISS!${NC}"
            fi
            
            # Enemy attack if still alive
            if [[ $enemy_hp -gt 0 ]]; then
                local enemy_roll=$(roll_d20)
                local player_ac=$((10 + (DEX - 10) / 2 + 6))  # Chainmail + shield
                echo -e "${RED}$enemy_name attacks! Roll: $enemy_roll vs AC $player_ac${NC}"
                
                if [[ $enemy_roll -ge $player_ac ]]; then
                    local enemy_dmg=$(roll_dice $enemy_damage)
                    HP=$((HP - enemy_dmg))
                    echo -e "${RED}You take $enemy_dmg damage! HP: $HP/$MAX_HP${NC}"
                else
                    echo -e "${GREEN}The attack misses!${NC}"
                fi
            fi
            sleep 0.5
        done
        
        if [[ $HP -le 0 ]]; then
            return 1  # Player died
        fi
        return 0  # Player won
    }
    
    clear
    show_stats
    
    echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                    CHAPTER 1: THE CROSSROADS${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}\n"
    
    sleep 1
    echo -e "You stand at a weathered crossroads, the setting sun casting long shadows"
    echo -e "across the cobblestones. A tattered signpost points in three directions:"
    echo -e ""
    echo -e "  ${CYAN}NORTH${NC} - The village of Millbrook (smoke rises from chimneys)"
    echo -e "  ${YELLOW}EAST${NC}  - The Whispering Woods (an eerie mist clings to the trees)"
    echo -e "  ${RED}WEST${NC}  - Ruins of Castle Dread (crumbling towers on the horizon)"
    echo -e ""
    echo -e "A cold wind carries the distant howl of wolves..."
    
    CHOICE=$(whiptail --title "The Crossroads" --menu "\nWhich path do you take?" 15 60 4 \
        "1" "North - Seek shelter in Millbrook village" \
        "2" "East - Explore the Whispering Woods" \
        "3" "West - Investigate the ancient ruins" \
        "4" "Search the area first" 3>&1 1>&2 2>&3)
    
    case $CHOICE in
        1)
            echo -e "\n${GREEN}You head north toward the safety of civilization...${NC}"
            echo "PATH:VILLAGE"
            ;;
        2)
            echo -e "\n${YELLOW}You venture into the misty woods...${NC}"
            echo "PATH:WOODS"
            ;;
        3)
            echo -e "\n${RED}You march toward the ominous ruins...${NC}"
            echo "PATH:RUINS"
            ;;
        4)
            echo -e "\n${CYAN}You search the area carefully...${NC}"
            local search_roll=$(roll_d20)
            local wis_mod=$(( (WIS - 10) / 2 ))
            echo "SEARCH_ROLL:$((search_roll + wis_mod))"
            if [[ $((search_roll + wis_mod)) -ge 12 ]]; then
                GOLD=$((GOLD + 5))
                echo -e "${GREEN}You find a pouch with 5 gold coins hidden in the tall grass!${NC}"
                echo "FOUND:GOLD"
            else
                echo -e "${YELLOW}You find nothing of interest.${NC}"
                echo "FOUND:NOTHING"
            fi
            echo "PATH:CROSSROADS"
            ;;
    esac
    
    echo ""
    echo "STATE:HP=$HP|GOLD=$GOLD|XP=$XP|CHOICE=$CHOICE"
}
step2
