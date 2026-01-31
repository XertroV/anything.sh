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
TUI: $(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv nms chafa glow bat cmatrix slides fastfetch asciinema delta; do command -v $t &>/dev/null && printf "%s " "$t"; done)

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
- USER INPUT: Don't assume on vague tasks - ask. Prefer inline tools (gum, fzf, read -rp) that preserve context
- Full-screen TUI (whiptail/dialog) sparingly - include all context needed to decide in the dialog itself, recap after
- Set FINAL: false after asking - response appears in next feedback
- For interactive experiences: use the best available tools (TUI, colors, ASCII art) to make something impressive
- QUALITY: Don't settle for minimal - create something impressive. The user will appreciate extra polish and creativity.
- Use timing for effect: slow text reveals (pv, character-by-character), pauses for dramatic moments, animations where appropriate
- When asking for input, ensure the user can see what they need to decide - pause after animations, recap after long output
- Avoid clearing the screen, but if you need to during interactive experiences, confirm with the user first
- Generate substantial, content-rich steps: full scenes with setup, action, dialogue AND choices - not minimal fragments. LLM calls are slow.
- Build complete interactive systems in single steps: combat loops, dialogue trees, puzzles should run to completion - don't fragment across iterations without good reason
- For complex experiences: use first 1-2 steps to create utility functions (UI helpers, combat engine, state display) so later steps are richer and more efficient. Leave design notes in comments.

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

    claude -p "$full_prompt" --model haiku --dangerously-skip-permissions 2>/dev/null
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
    local prev_output=""  # Track previous step output for script comments

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

        # Format previous output as comments (truncate if >1000 lines)
        local output_comment=""
        if [[ -n "$prev_output" ]]; then
            local output_lines=$(echo "$prev_output" | wc -l)
            local formatted_output
            if [[ $output_lines -gt 1000 ]]; then
                # Truncate: keep first 400 and last 400 lines
                local head_part=$(echo "$prev_output" | head -400 | sed 's/^/# /')
                local tail_part=$(echo "$prev_output" | tail -400 | sed 's/^/# /')
                local snipped=$(( output_lines - 800 ))
                formatted_output="$head_part
#
# [...$snipped lines snipped...]
#
$tail_part"
            else
                formatted_output=$(echo "$prev_output" | sed 's/^/# /')
            fi
            output_comment="
# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
$formatted_output
"
        fi

        # Append output comment + code to script
        cat >> "$SELF" <<EVOLUTION
$output_comment
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

        # Save output for next iteration's script comments
        prev_output="$output"

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
# STEP 1: Create D&D text adventure game with character stats and initial world setup
# Generated: 2026-01-31 10:31:52 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
  # Game state variables (global, persist across steps)
  PLAYER_NAME=""
  PLAYER_CLASS=""
  PLAYER_HP=0
  PLAYER_MAX_HP=0
  PLAYER_MANA=0
  PLAYER_MAX_MANA=0
  PLAYER_STRENGTH=0
  PLAYER_DEXTERITY=0
  PLAYER_CONSTITUTION=0
  PLAYER_INTELLIGENCE=0
  PLAYER_WISDOM=0
  PLAYER_CHARISMA=0
  PLAYER_LEVEL=1
  PLAYER_EXP=0
  PLAYER_GOLD=0
  PLAYER_INVENTORY=()
  CURRENT_LOCATION="tavern"
  CURRENT_ENEMY=""
  IN_COMBAT=false
  
  # Color codes
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  MAGENTA='\033[0;35m'
  CYAN='\033[0;36m'
  WHITE='\033[1;37m'
  NC='\033[0m'
  
  # Display title
  clear
  cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                 REALM OF ELDORIA                               ║
║           A Text Adventure in the D&D Tradition                ║
╚════════════════════════════════════════════════════════════════╝
EOF
  
  echo ""
  echo -e "${CYAN}Welcome, brave adventurer!${NC}"
  echo -e "${CYAN}You have wandered into the realm of Eldoria...${NC}"
  echo ""
  
  # Character creation - class selection
  echo -e "${YELLOW}Choose your class:${NC}"
  echo "1) Warrior  - High Strength, good HP"
  echo "2) Rogue    - High Dexterity, quick strikes"
  echo "3) Mage     - High Intelligence, spellcasting"
  echo "4) Cleric   - High Wisdom, healing & support"
  echo ""
  
  read -rp "Enter your choice (1-4): " CLASS_CHOICE
  
  case $CLASS_CHOICE in
    1) PLAYER_CLASS="Warrior"; PLAYER_STRENGTH=16; PLAYER_DEXTERITY=10; PLAYER_CONSTITUTION=15; PLAYER_INTELLIGENCE=8; PLAYER_WISDOM=11; PLAYER_CHARISMA=10;;
    2) PLAYER_CLASS="Rogue"; PLAYER_STRENGTH=12; PLAYER_DEXTERITY=16; PLAYER_CONSTITUTION=10; PLAYER_INTELLIGENCE=12; PLAYER_WISDOM=11; PLAYER_CHARISMA=13;;
    3) PLAYER_CLASS="Mage"; PLAYER_STRENGTH=8; PLAYER_DEXTERITY=11; PLAYER_CONSTITUTION=10; PLAYER_INTELLIGENCE=16; PLAYER_WISDOM=12; PLAYER_CHARISMA=12;;
    4) PLAYER_CLASS="Cleric"; PLAYER_STRENGTH=12; PLAYER_DEXTERITY=10; PLAYER_CONSTITUTION=13; PLAYER_INTELLIGENCE=11; PLAYER_WISDOM=16; PLAYER_CHARISMA=14;;
    *) PLAYER_CLASS="Warrior"; PLAYER_STRENGTH=16; PLAYER_DEXTERITY=10; PLAYER_CONSTITUTION=15; PLAYER_INTELLIGENCE=8; PLAYER_WISDOM=11; PLAYER_CHARISMA=10;;
  esac
  
  # Calculate HP and Mana based on class
  PLAYER_MAX_HP=$((10 + PLAYER_CONSTITUTION - 10))
  PLAYER_HP=$PLAYER_MAX_HP
  PLAYER_MAX_MANA=$((PLAYER_INTELLIGENCE * 2))
  PLAYER_MANA=$PLAYER_MAX_MANA
  PLAYER_GOLD=50
  
  # Get player name
  echo ""
  read -rp "What is your name, ${PLAYER_CLASS}? " PLAYER_NAME
  
  clear
  cat << EOF
╔════════════════════════════════════════════════════════════════╗
║                  CHARACTER CREATED                             ║
╚════════════════════════════════════════════════════════════════╝
EOF
  
  echo -e "${GREEN}${PLAYER_NAME} the ${PLAYER_CLASS}${NC}"
  echo ""
  echo -e "${YELLOW}Stats:${NC}"
  echo "STR: $PLAYER_STRENGTH | DEX: $PLAYER_DEXTERITY | CON: $PLAYER_CONSTITUTION"
  echo "INT: $PLAYER_INTELLIGENCE | WIS: $PLAYER_WISDOM | CHA: $PLAYER_CHARISMA"
  echo ""
  echo -e "${CYAN}HP: ${RED}$PLAYER_HP${NC}/${GREEN}$PLAYER_MAX_HP${NC} | MANA: ${BLUE}$PLAYER_MANA${NC}/${GREEN}$PLAYER_MAX_MANA${NC}"
  echo "GOLD: ${YELLOW}$PLAYER_GOLD${NC} | LEVEL: ${GREEN}$PLAYER_LEVEL${NC}"
  
  echo ""
  echo -e "${CYAN}You awaken in the Wandering Griffin Tavern...${NC}"
  sleep 2
  
  echo ""
  echo "The tavern is warm and dimly lit by candlelight. The smell of ale and"
  echo "roasted meat fills the air. Adventurers of all kinds sit at wooden tables,"
  echo "nursing their drinks and telling tales of distant lands."
  echo ""
  echo -e "${YELLOW}The tavern keeper, a stout dwarf named Grendel, nods at you.${NC}"
  echo ''"'"'"I see fresh blood. Got any interest in work? Plenty of coin to be made'
  echo 'for those brave—or foolish—enough to seek it.'"'"'"'
  echo ""
  echo "What do you do?"
  echo "1) Speak with Grendel about jobs"
  echo "2) Explore the tavern"
  echo "3) Head out into the town"
  echo ""
  
  echo "CHAPTER_1_READY"
}

step1
EOF

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 10:31:52+11:00 [COMMAND="bash '/tmp/tmp.Ypf1FueLbd'" TERM="xterm-256color" TTY="/dev/pts/0" COLUMNS="100" LINES="57"]
# ╔════════════════════════════════════════════════════════════════╗
# ║                 REALM OF ELDORIA                               ║
# ║           A Text Adventure in the D&D Tradition                ║
# ╚════════════════════════════════════════════════════════════════╝
# 
# Welcome, brave adventurer!
# You have wandered into the realm of Eldoria...
# 
# Choose your class:
# 1) Warrior  - High Strength, good HP
# 2) Rogue    - High Dexterity, quick strikes
# 3) Mage     - High Intelligence, spellcasting
# 4) Cleric   - High Wisdom, healing & support
# 
# Enter your choice (1-4): 1
# 
# What is your name, Warrior? SIR LAC NCALOT, THE BRAVE
# ╔════════════════════════════════════════════════════════════════╗
# ║                  CHARACTER CREATED                             ║
# ╚════════════════════════════════════════════════════════════════╝
# SIR LANCALOT, THE BRAVE the Warrior
# 
# Stats:
# STR: 16 | DEX: 10 | CON: 15
# INT: 8 | WIS: 11 | CHA: 10
# 
# HP: 15/15 | MANA: 16/16
# GOLD: \033[1;33m50\033[0m | LEVEL: \033[0;32m1\033[0m
# 
# You awaken in the Wandering Griffin Tavern...
# 
# The tavern is warm and dimly lit by candlelight. The smell of ale and
# roasted meat fills the air. Adventurers of all kinds sit at wooden tables,
# nursing their drinks and telling tales of distant lands.
# 
# The tavern keeper, a stout dwarf named Grendel, nods at you.
# '"I see fresh blood. Got any interest in work? Plenty of coin to be made
# for those brave—or foolish—enough to seek it.'"
# 
# What do you do?
# 1) Speak with Grendel about jobs
# 2) Explore the tavern
# 3) Head out into the town
# 
# CHAPTER_1_READY
# /tmp/tmp.Ypf1FueLbd: line 115: EOF: command not found
# 
# Script done on 2026-01-31 10:32:16+11:00 [COMMAND_EXIT_CODE="127"]

# ═══════════════════════════════════════════════════════════════
# STEP 2: Build complete D&D text adventure with stats, inventory, combat, and multi-chapter progression
# Generated: 2026-01-31 10:32:47 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
  cat > /tmp/dnd_adventure.sh << 'SCRIPT_EOF'
#!/bin/bash

# D&D Text Adventure - Complete Game Engine
# Global state variables (persist across scenes)
CHARACTER_NAME=""
CLASS=""
STR=0 DEX=0 CON=0 INT=0 WIS=0 CHA=0
HP=0 MAX_HP=0 MANA=0 MAX_MANA=0
GOLD=50 LEVEL=1 EXP=0
INVENTORY=()
CHAPTER=1
IN_COMBAT=0
CURRENT_ENEMY=""
ENEMY_HP=0
ENEMY_MAX_HP=0

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# UI Functions
show_header() {
  clear
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║${RESET}                 REALM OF ELDORIA                               ${CYAN}║${RESET}"
  echo -e "${CYAN}║${RESET}           A Text Adventure in the D&D Tradition                ${CYAN}║${RESET}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

show_stats() {
  echo -e "${BOLD}${CHARACTER_NAME} the ${CLASS}${RESET}"
  echo ""
  echo -e "Stats: ${BOLD}STR${RESET}: $STR | ${BOLD}DEX${RESET}: $DEX | ${BOLD}CON${RESET}: $CON | ${BOLD}INT${RESET}: $INT | ${BOLD}WIS${RESET}: $WIS | ${BOLD}CHA${RESET}: $CHA"
  echo -e "HP: ${RED}${HP}/${MAX_HP}${RESET} | MANA: ${BLUE}${MANA}/${MAX_MANA}${RESET} | GOLD: ${YELLOW}${GOLD}${RESET} | LEVEL: ${GREEN}${LEVEL}${RESET}"
  echo ""
}

pause_for_effect() {
  sleep 1
}

# Character Creation
create_character() {
  show_header
  echo "Welcome, brave adventurer!"
  echo "You have wandered into the realm of Eldoria..."
  echo ""
  pause_for_effect
  
  echo "Choose your class:"
  echo "1) Warrior  - High Strength, good HP"
  echo "2) Rogue    - High Dexterity, quick strikes"
  echo "3) Mage     - High Intelligence, spellcasting"
  echo "4) Cleric   - High Wisdom, healing & support"
  echo ""
  
  read -rp "Enter your choice (1-4): " class_choice
  
  case $class_choice in
    1) CLASS="Warrior"; STR=16; DEX=10; CON=15; INT=8; WIS=11; CHA=10 ;;
    2) CLASS="Rogue"; STR=12; DEX=16; CON=12; INT=13; WIS=10; CHA=12 ;;
    3) CLASS="Mage"; STR=8; DEX=11; CON=11; INT=16; WIS=12; CHA=13 ;;
    4) CLASS="Cleric"; STR=13; DEX=11; CON=13; INT=10; WIS=16; CHA=14 ;;
    *) CLASS="Warrior"; STR=16; DEX=10; CON=15; INT=8; WIS=11; CHA=10 ;;
  esac
  
  read -rp "What is your name, ${CLASS}? " CHARACTER_NAME
  CHARACTER_NAME=$(echo "$CHARACTER_NAME" | tr '[:lower:]' '[:upper:]')
  
  MAX_HP=$((10 + CON))
  HP=$MAX_HP
  MAX_MANA=$((5 + INT))
  MANA=$MAX_MANA
  
  show_header
  echo -e "${BOLD}CHARACTER CREATED${RESET}"
  echo ""
  show_stats
  
  echo "You awaken in the ${BOLD}Wandering Griffin Tavern${RESET}..."
  echo ""
  sleep 1
  echo "The tavern is warm and dimly lit by candlelight. The smell of ale and"
  echo "roasted meat fills the air. Adventurers of all kinds sit at wooden tables,"
  echo "nursing their drinks and telling tales of distant lands."
  echo ""
  echo "A stout dwarf behind the bar, named ${BOLD}Grendel${RESET}, nods at you."
  echo "\"I see fresh blood. Got any interest in work? Plenty of coin to be made\""
  echo "\"for those brave—or foolish—enough to seek it.\""
  echo ""
}

# Tavern Scene - Chapter 1
tavern_scene() {
  echo "What do you do?"
  echo "1) Speak with Grendel about jobs"
  echo "2) Explore the tavern"
  echo "3) Head out into the town"
  echo ""
  
  read -rp "Enter your choice (1-3): " choice
  
  case $choice in
    1) grendel_quest ;;
    2) explore_tavern ;;
    3) leave_tavern ;;
    *) tavern_scene ;;
  esac
}

grendel_quest() {
  show_header
  show_stats
  
  echo "You approach Grendel at the bar. He slides you a mug of ale."
  pause_for_effect
  echo ""
  echo "\"Ah, a ${CLASS}. Listen, there's a problem. Goblin scouts have been"
  echo "terrorizing the road to ${BOLD}Millbrook Village${RESET}. Kill a few of 'em,"
  echo "bring back proof, and I'll pay you ${YELLOW}100 gold${RESET} pieces.\""
  echo ""
  pause_for_effect
  
  read -rp "Accept the quest? (y/n): " accept
  if [[ $accept == "y" ]]; then
    INVENTORY+=("Grendel's Quest")
    GOLD=$((GOLD + 10))
    echo ""
    echo "${GREEN}Quest accepted!${RESET} Grendel gives you ${YELLOW}10 gold${RESET} for supplies."
    sleep 2
    chapter_2
  else
    echo "You politely decline. Grendel shrugs and returns to cleaning glasses."
    sleep 2
    tavern_scene
  fi
}

explore_tavern() {
  show_header
  show_stats
  
  echo "You wander through the tavern, observing the various patrons..."
  pause_for_effect
  echo ""
  echo "At one table, an old knight in faded armor watches you intently."
  echo "At another, two merchants argue over trade routes."
  echo "In the corner, a mysterious hooded figure stares into their drink."
  echo ""
  pause_for_effect
  
  echo "1) Talk to the old knight"
  echo "2) Eavesdrop on the merchants"
  echo "3) Investigate the hooded figure"
  echo "4) Return to the bar"
  echo ""
  
  read -rp "What do you do? (1-4): " explore_choice
  case $explore_choice in
    1) echo "The knight tells you stories of battles long past."; pause_for_effect; tavern_scene ;;
    2) echo "The merchants are discussing a missing shipment headed north."; pause_for_effect; tavern_scene ;;
    3) echo "The figure notices you and quickly leaves the tavern."; pause_for_effect; tavern_scene ;;
    4) tavern_scene ;;
    *) explore_tavern ;;
  esac
}

leave_tavern() {
  show_header
  show_stats
  
  echo "You push through the tavern doors into the cool evening air."
  pause_for_effect
  echo ""
  echo "The town of ${BOLD}Greystone${RESET} sprawls before you. Candlelight flickers"
  echo "in shop windows. To the north, the road winds toward Millbrook Village."
  echo ""
  pause_for_effect
  
  echo "1) Head to the town square"
  echo "2) Visit the general store"
  echo "3) Take the north road immediately"
  echo "4) Return to the tavern"
  echo ""
  
  read -rp "What do you do? (1-4): " town_choice
  case $town_choice in
    1) echo "The square is quiet, with only a few night merchants packing up."; pause_for_effect; leave_tavern ;;
    2) echo "The shopkeeper offers to sell you healing potions for 25 gold each."; pause_for_effect; leave_tavern ;;
    3) chapter_2 ;;
    4) tavern_scene ;;
    *) leave_tavern ;;
  esac
}

# Chapter 2 - Combat!
chapter_2() {
  CHAPTER=2
  show_header
  show_stats
  
  echo "You travel north on the winding road, leaving Greystone behind."
  pause_for_effect
  echo ""
  echo "The forest grows darker around you. The sounds of civilization fade,"
  echo "replaced by the chirping of crickets and the rustle of leaves."
  echo ""
  pause_for_effect
  
  echo "Suddenly, you hear a ${RED}GROWL${RESET}!"
  pause_for_effect
  echo ""
  echo "From the shadows emerges a ${RED}${BOLD}GOBLIN SCOUT${RESET}!"
  pause_for_effect
  echo ""
  
  CURRENT_ENEMY="Goblin Scout"
  ENEMY_MAX_HP=8
  ENEMY_HP=$ENEMY_MAX_HP
  IN_COMBAT=1
  
  combat_loop
}

combat_loop() {
  while [ $IN_COMBAT -eq 1 ]; do
    show_header
    show_stats
    
    echo -e "${RED}${BOLD}$CURRENT_ENEMY${RESET}"
    echo "HP: ${RED}${ENEMY_HP}/${ENEMY_MAX_HP}${RESET}"
    echo ""
    
    echo "What do you do?"
    echo "1) Attack with weapon"
    echo "2) Cast a spell (if you have mana)"
    echo "3) Attempt to flee"
    echo ""
    
    read -rp "Choose action (1-3): " combat_choice
    
    case $combat_choice in
      1) player_attack ;;
      2) player_spell ;;
      3) attempt_flee ;;
      *) combat_loop ;;
    esac
  done
}

player_attack() {
  local hit_roll=$((RANDOM % 20 + 1))
  local damage=$((STR / 3 + RANDOM % 6 + 1))
  
  if [ $hit_roll -gt 10 ]; then
    echo ""
    echo -e "${GREEN}Hit!${RESET} You deal ${YELLOW}${damage}${RESET} damage!"
    ENEMY_HP=$((ENEMY_HP - damage))
  else
    echo ""
    echo -e "${RED}Miss!${RESET} Your attack doesn't connect."
  fi
  
  pause_for_effect
  
  if [ $ENEMY_HP -le 0 ]; then
    combat_victory
  else
    enemy_attack
  fi
}

player_spell() {
  if [ $MANA -lt 5 ]; then
    echo ""
    echo -e "${BLUE}Not enough mana!${RESET} (Need 5, have $MANA)"
    pause_for_effect
    return
  fi
  
  local damage=$((INT / 2 + RANDOM % 8 + 2))
  echo ""
  echo -e "${BLUE}A magical bolt erupts from your hands!${RESET}"
  echo "You deal ${YELLOW}${damage}${RESET} damage!"
  
  MANA=$((MANA - 5))
  ENEMY_HP=$((ENEMY_HP - damage))
  
  pause_for_effect
  
  if [ $ENEMY_HP -le 0 ]; then
    combat_victory
  else
    enemy_attack
  fi
}

attempt_flee() {
  local flee_roll=$((RANDOM % 20 + DEX / 2))
  
  echo ""
  if [ $flee_roll -gt 12 ]; then
    echo -e "${GREEN}You manage to escape!${RESET}"
    IN_COMBAT=0
    pause_for_effect
    tavern_scene
  else
    echo -e "${RED}You can't get away!${RESET}"
    pause_for_effect
    enemy_attack
  fi
}

enemy_attack() {
  local enemy_damage=$((RANDOM % 6 + 1))
  local hit_roll=$((RANDOM % 20 + 1))
  
  echo ""
  if [ $hit_roll -gt 8 ]; then
    echo -e "${RED}The $CURRENT_ENEMY hits you for ${enemy_damage} damage!${RESET}"
    HP=$((HP - enemy_damage))
    if [ $HP -le 0 ]; then
      HP=0
      combat_defeat
    fi
  else
    echo -e "${GREEN}The $CURRENT_ENEMY's attack misses!${RESET}"
  fi
  
  pause_for_effect
}

combat_victory() {
  show_header
  show_stats
  
  echo -e "${GREEN}${BOLD}VICTORY!${RESET}"
  echo ""
  echo "The ${CURRENT_ENEMY} falls to the ground, defeated!"
  pause_for_effect
  echo ""
  
  local xp=50
  local gold_reward=$((RANDOM % 20 + 10))
  
  EXP=$((EXP + xp))
  GOLD=$((GOLD + gold_reward))
  
  echo "You gain ${YELLOW}${xp} experience${RESET} and ${YELLOW}${gold_reward} gold${RESET}!"
  
  sleep 2
  echo ""
  echo "You stand over the fallen creature, catching your breath..."
  sleep 2
  echo ""
  
  IN_COMBAT=0
  INVENTORY+=("Goblin Ears")
  
  read -rp "Press enter to continue... " enter_continue
  chapter_3
}

combat_defeat() {
  show_header
  
  echo -e "${RED}${BOLD}YOU HAVE BEEN DEFEATED!${RESET}"
  echo ""
  echo "Darkness envelops you as you fall..."
  pause_for_effect
  echo ""
  
  echo "You awaken back in the Wandering Griffin Tavern, battered and bruised."
  echo "Grendel looks at you with pity."
  echo ""
  
  HP=$MAX_HP
  GOLD=$((GOLD - 10))
  
  sleep 2
  read -rp "Press enter to try again... " enter_continue
  tavern_scene
}

# Chapter 3 - Quest Return
chapter_3() {
  CHAPTER=3
  show_header
  show_stats
  
  echo "You have defeated the Goblin Scout. The path ahead is clear."
  pause_for_effect
  echo ""
  echo "You return to Greystone and head straight to the Wandering Griffin."
  pause_for_effect
  echo ""
  
  echo "Grendel's eyes light up when you approach, goblin ears in hand."
  pause_for_effect
  echo ""
  
  echo "\"${BOLD}Excellent!${RESET} You've got the mettle of a true adventurer!\""
  pause_for_effect
  
  GOLD=$((GOLD + 100))
  INVENTORY+=("Grendel's Blessing")
  LEVEL=2
  
  echo ""
  echo "Grendel slides ${YELLOW}100 gold${RESET} across the bar."
  echo "You are now ${GREEN}Level ${LEVEL}${RESET}!"
  
  sleep 2
  echo ""
  echo "\"There's more work where that came from,\" Grendel says,"
  echo "\"but that's a tale for another time...\""
  
  sleep 2
  read -rp "Press enter to see final stats... " enter_continue
  
  show_header
  show_stats
  echo "Inventory: ${INVENTORY[@]}"
  echo ""
  echo -e "${CYAN}${BOLD}=== ADVENTURE COMPLETE (Chapter 3) ===${RESET}"
  echo ""
  echo "Your story in Eldoria has begun!"
  echo "Will you continue your adventures? The realm awaits..."
}

# Main execution
create_character
tavern_scene
SCRIPT_EOF

  bash /tmp/dnd_adventure.sh
}

step2
</parameter>
</invoke>
