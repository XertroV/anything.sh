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
- USER INPUT: Don't assume on vague tasks - ask. Prefer inline tools (gum, fzf, read -rp) that preserve context
- Full-screen TUI (whiptail/dialog) sparingly - include all context needed to decide in the dialog itself, recap after
- Set FINAL: false after asking - response appears in next feedback
- For interactive experiences: use the best available tools (TUI, colors, ASCII art) to make something impressive
- When asking for input, ensure the user can see what they need to decide - pause after animations, recap after long output
- Don't split choices over multiple steps - put as much content in each step as you safely can. LLM calls are expensive.
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
# Generated: 2026-01-31 09:58:21 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    # Colors and styling
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'

    clear
    
    # Title banner
    echo -e "${MAGENTA}${BOLD}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║  ⚔️   R E A L M S   O F   S H A D O W F E L L   ⚔️            ║
    ║         A D&D-Style Text Adventure                            ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    sleep 1
    
    # Character creation
    echo -e "${CYAN}${BOLD}═══ CHARACTER CREATION ═══${NC}\n"
    
    # Get character name
    echo -e "${YELLOW}What is your name, adventurer?${NC}"
    read -rp "> " PLAYER_NAME
    PLAYER_NAME=${PLAYER_NAME:-"Stranger"}
    
    echo ""
    
    # Class selection with fzf
    echo -e "${YELLOW}Choose your class:${NC}"
    CLASS=$(echo -e "⚔️  Warrior - Strong and resilient (STR+2, CON+1)\n🏹 Ranger - Swift and precise (DEX+2, WIS+1)\n🔮 Mage - Wielder of arcane arts (INT+2, WIS+1)\n🗡️  Rogue - Cunning and stealthy (DEX+2, CHA+1)" | fzf --height=6 --prompt="Select class: " --no-info)
    
    # Parse class and set base stats
    HP=100
    MAX_HP=100
    GOLD=50
    XP=0
    LEVEL=1
    CHAPTER=1
    
    # Base stats
    STR=10; DEX=10; CON=10; INT=10; WIS=10; CHA=10
    
    case "$CLASS" in
        *Warrior*) CLASS="Warrior"; STR=$((STR+2)); CON=$((CON+1)); MAX_HP=120; HP=120 ;;
        *Ranger*)  CLASS="Ranger";  DEX=$((DEX+2)); WIS=$((WIS+1)) ;;
        *Mage*)    CLASS="Mage";    INT=$((INT+2)); WIS=$((WIS+1)); MAX_HP=80; HP=80 ;;
        *Rogue*)   CLASS="Rogue";   DEX=$((DEX+2)); CHA=$((CHA+1)) ;;
        *)         CLASS="Warrior"; STR=$((STR+2)); CON=$((CON+1)) ;;
    esac
    
    # Inventory
    INVENTORY=("Torch" "Rations x3")
    case "$CLASS" in
        Warrior) INVENTORY+=("Longsword" "Shield") ;;
        Ranger)  INVENTORY+=("Longbow" "Arrows x20" "Dagger") ;;
        Mage)    INVENTORY+=("Staff" "Spellbook" "Mana Potion") ;;
        Rogue)   INVENTORY+=("Short Sword" "Lockpicks" "Smoke Bomb") ;;
    esac
    
    clear
    
    # Character sheet display
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}       CHARACTER CREATED!${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}Name:${NC}  ${BOLD}$PLAYER_NAME${NC}"
    echo -e "${CYAN}Class:${NC} ${BOLD}$CLASS${NC}"
    echo -e "${CYAN}Level:${NC} ${BOLD}$LEVEL${NC}\n"
    
    echo -e "${YELLOW}╔═══ STATS ═══╗${NC}"
    echo -e "  STR: ${BOLD}$STR${NC}  DEX: ${BOLD}$DEX${NC}  CON: ${BOLD}$CON${NC}"
    echo -e "  INT: ${BOLD}$INT${NC}  WIS: ${BOLD}$WIS${NC}  CHA: ${BOLD}$CHA${NC}"
    echo -e "${YELLOW}╚═════════════╝${NC}\n"
    
    echo -e "${RED}HP:${NC} ${BOLD}$HP/$MAX_HP${NC}  ${YELLOW}Gold:${NC} ${BOLD}$GOLD${NC}  ${MAGENTA}XP:${NC} ${BOLD}$XP${NC}\n"
    
    echo -e "${BLUE}Inventory:${NC} ${INVENTORY[*]}\n"
    
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}\n"
    
    sleep 1
    
    # Opening narrative
    echo -e "${BOLD}The adventure begins...${NC}\n"
    sleep 0.5
    
    echo -e "You awaken in a ${CYAN}dimly lit tavern${NC} in the village of ${GREEN}Millbrook${NC}."
    echo -e "Rain hammers against the windows as thunder rumbles in the distance."
    echo -e "A hooded figure approaches your table and slides a ${YELLOW}worn parchment${NC} toward you.\n"
    sleep 1
    
    echo -e "\"${ITALIC}The Shadowfell stirs,\"${NC} they whisper. \"${ITALIC}Dark creatures emerge from"
    echo -e "the abandoned mines to the north. The village elder offers ${YELLOW}500 gold${NC}"
    echo -e "to any brave soul who can discover the source... and end it.\"${NC}\n"
    
    echo -e "The figure vanishes into the shadows before you can respond.\n"
    
    # Export state for next step
    echo "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=$CHAPTER"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Continue adventure with player choices
# Generated: 2026-01-31 09:59:14 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    # Parse state from previous output
    PLAYER_NAME="Max"
    CLASS="Warrior"
    HP=120
    MAX_HP=120
    GOLD=50
    XP=0
    LEVEL=1
    STR=12
    DEX=10
    CON=11
    INT=10
    WIS=10
    CHA=10
    CHAPTER=1
    
    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
    
    # Status bar function
    show_status() {
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}$PLAYER_NAME${NC} the ${YELLOW}$CLASS${NC} | Lvl $LEVEL | HP: ${GREEN}$HP/$MAX_HP${NC} | Gold: ${YELLOW}$GOLD${NC} | XP: $XP"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    }
    
    clear
    show_status
    
    echo ""
    echo -e "${BOLD}Chapter 1: The Call to Adventure${NC}"
    echo ""
    echo "The mysterious parchment lies before you. It shows a crude map"
    echo "marking the abandoned Irondeep Mines to the north of Millbrook."
    echo ""
    echo "The tavern is still bustling despite the late hour. You notice:"
    echo -e "  • The ${YELLOW}barkeep${NC} polishing glasses, eyeing you curiously"
    echo -e "  • A ${YELLOW}grizzled dwarf${NC} drinking alone in the corner"  
    echo -e "  • The ${YELLOW}door${NC} leading out into the stormy night"
    echo ""
    
    # Use fzf for choice selection
    CHOICE=$(echo -e "1. Talk to the barkeep about the mines\n2. Approach the dwarf - he looks like a miner\n3. Head out immediately toward the mines\n4. Check your equipment and rest for the night" | fzf --height=8 --prompt="What do you do? " --no-info --pointer="▶" --color="pointer:yellow,prompt:cyan")
    
    CHOICE_NUM="${CHOICE:0:1}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    case $CHOICE_NUM in
        1)
            echo -e "\n${BOLD}You approach the barkeep...${NC}\n"
            echo "The heavyset man leans in, lowering his voice."
            echo ""
            echo "\"Those mines? Been closed for twenty years since the collapse."
            echo "But lately... folks hear sounds at night. Screaming from below.\""
            echo ""
            echo "He slides you a small vial of red liquid."
            echo -e "\"${GREEN}Healing Potion${NC}. On the house. You'll need it.\""
            echo ""
            echo -e "${GREEN}[Gained: Healing Potion - Restores 50 HP]${NC}"
            INVENTORY="Torch Rations x3 Longsword Shield Healing_Potion"
            ;;
        2)
            echo -e "\n${BOLD}You sit across from the dwarf...${NC}\n"
            echo "His eyes are haunted, his hands trembling around his mug."
            echo ""
            echo "\"I was the last foreman of Irondeep. We dug too deep, lad.\""
            echo "\"Found something... ancient. A door carved with runes.\""
            echo "\"When we opened it...\" He shudders. \"Don't go alone.\""
            echo ""
            echo "He hands you a rusty iron key."
            echo -e "\"${YELLOW}The foreman's key${NC}. Opens the deep tunnels.\""
            echo ""
            echo -e "${GREEN}[Gained: Foreman's Key - Opens locked mine doors]${NC}"
            echo -e "${GREEN}[Gained: +100 XP for gathering intel]${NC}"
            XP=$((XP + 100))
            INVENTORY="Torch Rations x3 Longsword Shield Foremans_Key"
            ;;
        3)
            echo -e "\n${BOLD}You stride out into the storm...${NC}\n"
            echo "Rain lashes your face as lightning illuminates the muddy road north."
            echo "Bold choice, warrior. The mines await."
            echo ""
            echo -e "${YELLOW}[You head directly to Chapter 2 - no additional items]${NC}"
            CHAPTER=2
            ;;
        4)
            echo -e "\n${BOLD}You rent a room for the night...${NC}\n"
            echo "A good night's rest before danger. Wise."
            echo "In the morning, the storm has passed. You feel refreshed."
            echo ""
            echo -e "${GREEN}[HP fully restored | -10 Gold for room]${NC}"
            GOLD=$((GOLD - 10))
            HP=$MAX_HP
            ;;
    esac
    
    echo ""
    echo -e "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=$CHAPTER|INVENTORY=$INVENTORY|LAST_CHOICE=$CHOICE_NUM"
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Continue adventure with next encounter
# Generated: 2026-01-31 10:01:13 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
  # Restore state from previous step
  STATE="PLAYER_NAME=Max|CLASS=Warrior|HP=120|MAX_HP=120|GOLD=50|XP=0|LEVEL=1|STR=12|DEX=10|CON=11|INT=10|WIS=10|CHA=10|CHAPTER=1|INVENTORY=Torch Rations x3 Longsword Shield Healing_Potion|LAST_CHOICE=1"
  
  IFS='|' read -ra PAIRS <<< "$STATE"
  for pair in "${PAIRS[@]}"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    case $key in
      PLAYER_NAME) PLAYER_NAME="$val" ;;
      CLASS) CLASS="$val" ;;
      HP) HP=$val ;;
      MAX_HP) MAX_HP=$val ;;
      GOLD) GOLD=$val ;;
      XP) XP=$val ;;
      LEVEL) LEVEL=$val ;;
      STR) STR=$val ;;
      DEX) DEX=$val ;;
      CON) CON=$val ;;
      INT) INT=$val ;;
      WIS) WIS=$val ;;
      CHA) CHA=$val ;;
      CHAPTER) CHAPTER=$val ;;
      INVENTORY) INVENTORY="$val" ;;
    esac
  done
  
  clear
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$PLAYER_NAME the $CLASS | Lvl $LEVEL | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "Chapter 1: The Journey North"
  echo
  echo "You leave the warm tavern and step into the stormy night."
  echo "Rain lashes against your face as you follow the muddy road north."
  echo
  echo "After an hour of travel, you see a flickering campfire ahead."
  echo "Three bandits sit around it, blocking the road."
  echo
  echo "As you approach, they notice you and stand, hands on weapons."
  echo
  echo "\"Toll's 30 gold, stranger,\" the leader sneers."
  echo
  
  CHOICES=(
    "1. Pay the toll (30 gold)"
    "2. Try to talk your way through (CHA check)"
    "3. Attack them (Combat)"
    "4. Sneak around through the woods (DEX check)"
  )
  
  choice=$(printf '%s\n' "${CHOICES[@]}" | fzf --height=40% --reverse --header="What do you do?" --prompt="▶ ")
  choice_num=$(echo "$choice" | cut -d. -f1)
  
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  
  case $choice_num in
    1)
      if [ $GOLD -ge 30 ]; then
        GOLD=$((GOLD - 30))
        echo "You hand over 30 gold. The bandits step aside with ugly grins."
        echo
        echo "[Lost: 30 Gold]"
        echo "You continue north toward the mines..."
      else
        echo "\"Don't got enough?\" the leader snarls."
        echo "\"Then we'll take it from your corpse!\""
        echo
        echo "[Combat begins!]"
        HP=$((HP - 30))
        GOLD=$((GOLD + 45))
        XP=$((XP + 150))
        echo "After a brutal fight, you defeat all three bandits."
        echo
        echo "[Lost: 30 HP]"
        echo "[Gained: 45 Gold, 150 XP]"
      fi
      ;;
    2)
      roll=$((RANDOM % 20 + 1))
      mod=$((CHA - 10))
      total=$((roll + mod))
      echo "CHA Check: d20($roll) + $mod = $total (DC 15)"
      echo
      if [ $total -ge 15 ]; then
        echo "\"I'm heading to clear out the mines for the town,\" you say."
        echo "The leader hesitates, then waves you through."
        echo "\"Yer funeral. Those mines are cursed.\""
        echo
        echo "[Success! No combat needed]"
      else
        echo "\"Nice try.\" The leader draws his blade."
        echo
        HP=$((HP - 25))
        GOLD=$((GOLD + 45))
        XP=$((XP + 150))
        echo "[Combat!]"
        echo "After a hard fight, you defeat the bandits."
        echo
        echo "[Lost: 25 HP]"
        echo "[Gained: 45 Gold, 150 XP]"
      fi
      ;;
    3)
      echo "You draw your longsword and charge!"
      echo
      HP=$((HP - 35))
      GOLD=$((GOLD + 45))
      XP=$((XP + 150))
      echo "The fight is fierce. Your warrior training prevails."
      echo
      echo "[Lost: 35 HP]"
      echo "[Gained: 45 Gold, 150 XP]"
      ;;
    4)
      roll=$((RANDOM % 20 + 1))
      mod=$((DEX - 10))
      total=$((roll + mod))
      echo "DEX Check: d20($roll) + $mod = $total (DC 13)"
      echo
      if [ $total -ge 13 ]; then
        echo "You slip into the dark woods and circle around."
        echo "The bandits never notice as you rejoin the road beyond them."
        echo
        echo "[Success! Avoided combat]"
      else
        echo "A branch snaps beneath your foot!"
        echo "\"There! In the trees!\" The bandits attack."
        echo
        HP=$((HP - 30))
        GOLD=$((GOLD + 45))
        XP=$((XP + 150))
        echo "You fight your way out."
        echo
        echo "[Lost: 30 HP]"
        echo "[Gained: 45 Gold, 150 XP]"
      fi
      ;;
  esac
  
  echo
  echo "Current HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
  echo
  echo "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=$CHAPTER|INVENTORY=$INVENTORY|LAST_CHOICE=$choice_num"
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Continue adventure - explore the forest path ahead
# Generated: 2026-01-31 10:02:35 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
    # Restore state from previous step
    PLAYER_NAME="Max"
    CLASS="Warrior"
    HP=85
    MAX_HP=120
    GOLD=95
    XP=150
    LEVEL=1
    STR=12
    DEX=10
    CON=11
    INT=10
    WIS=10
    CHA=10
    CHAPTER=1
    INVENTORY=("Torch" "Rations" "Rations" "Rations" "Longsword" "Shield" "Healing_Potion")

    clear
    
    # Header
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$PLAYER_NAME the $CLASS | Lvl $LEVEL | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Story progression
    echo "You search the bandits' camp and find some useful supplies."
    echo "[Gained: 2 Healing Potions, 1 Rope]"
    echo
    INVENTORY+=("Healing_Potion" "Healing_Potion" "Rope")
    
    sleep 1
    
    echo "The rain has stopped. You continue north along the muddy road."
    echo "After another mile, the forest grows denser and darker."
    echo
    sleep 1
    
    echo "You hear a woman's scream echoing from deep in the woods to the east!"
    echo "The road continues north toward your destination."
    echo
    
    # Choice menu using fzf
    choice=$(printf "1. Rush into the forest to help (STR/DEX check)\n2. Ignore it and continue north (safer)\n3. Approach cautiously, scouting first (WIS check)\n4. Shout into the woods to assess the situation" | \
        fzf --height=8 --reverse --header="What do you do?" --prompt="▶ " --border --no-info)
    
    choice_num=$(echo "$choice" | cut -d'.' -f1)
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    case $choice_num in
        1)
            # Rush in - DEX check to avoid traps
            roll=$((RANDOM % 20 + 1))
            echo "You charge into the forest! [DEX Check: rolled $roll + $DEX = $((roll + DEX))]"
            echo
            if [ $((roll + DEX)) -ge 12 ]; then
                echo "You nimbly dodge the roots and branches!"
                echo "You find a young woman cornered by a massive dire wolf!"
                echo "The wolf turns toward you, snarling..."
                ENCOUNTER="dire_wolf"
            else
                echo "You trip over a hidden root and tumble down a slope!"
                damage=$((RANDOM % 10 + 5))
                HP=$((HP - damage))
                echo "[Lost: $damage HP from fall damage]"
                echo
                echo "Bruised, you stand up and see a young woman cornered by a dire wolf above you."
                ENCOUNTER="dire_wolf_disadvantage"
            fi
            ;;
        2)
            echo "You steel yourself and continue north, ignoring the screams."
            echo "A true warrior knows when not to get involved..."
            echo
            echo "After a few minutes, the screaming stops. An eerie silence fills the forest."
            KARMA="dark"
            ENCOUNTER="guilt"
            ;;
        3)
            # Scout - WIS check
            roll=$((RANDOM % 20 + 1))
            echo "You move carefully into the forest. [WIS Check: rolled $roll + $WIS = $((roll + WIS))]"
            echo
            if [ $((roll + WIS)) -ge 13 ]; then
                echo "Your careful observation reveals a trap - trip wires leading to spike pits!"
                echo "You also spot a dire wolf stalking a young woman who hasn't seen it yet."
                echo
                echo "You can approach with advantage now that you know the terrain."
                ENCOUNTER="dire_wolf_advantage"
            else
                echo "You try to move quietly but snap a twig."
                echo "A massive dire wolf spins toward you, abandoning its previous prey!"
                ENCOUNTER="dire_wolf"
            fi
            ;;
        4)
            echo "You cup your hands and shout: 'HOLD ON! I'M COMING!'"
            echo
            echo "The screaming stops abruptly. You hear rustling in the bushes..."
            echo "Three goblin scouts emerge from hiding, weapons drawn!"
            echo "'Human fall for trap!' one cackles. 'Now we take shinies!'"
            ENCOUNTER="goblin_ambush"
            ;;
    esac
    
    echo
    echo "Current HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
    echo
    echo "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=$CHAPTER|INVENTORY=${INVENTORY[*]}|ENCOUNTER=$ENCOUNTER|LAST_CHOICE=$choice_num"
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Dire wolf combat encounter with combat system
# Generated: 2026-01-31 10:04:04 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
    # Parse state from previous output
    IFS='|' read -ra STATE_PARTS <<< "PLAYER_NAME=Max|CLASS=Warrior|HP=85|MAX_HP=120|GOLD=95|XP=150|LEVEL=1|STR=12|DEX=10|CON=11|INT=10|WIS=10|CHA=10|CHAPTER=1|INVENTORY=Torch Rations Rations Rations Longsword Shield Healing_Potion Healing_Potion Healing_Potion Rope|ENCOUNTER=dire_wolf|LAST_CHOICE=1"
    
    for part in "${STATE_PARTS[@]}"; do
        key="${part%%=*}"
        val="${part#*=}"
        declare "$key=$val"
    done
    
    # Combat system
    WOLF_HP=45
    WOLF_MAX_HP=45
    WOLF_ATK=8
    WOLF_NAME="Dire Wolf"
    
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$PLAYER_NAME the $CLASS | Lvl $LEVEL | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⚔️  COMBAT ENCOUNTER ⚔️"
    echo ""
    echo "🐺 $WOLF_NAME: $WOLF_HP/$WOLF_MAX_HP HP"
    echo ""
    
    # Combat loop
    ROUND=1
    while [ "$HP" -gt 0 ] && [ "$WOLF_HP" -gt 0 ]; do
        echo "─── Round $ROUND ───"
        echo ""
        
        # Player action
        CHOICE=$(whiptail --title "Combat - Round $ROUND" --menu "Your HP: $HP/$MAX_HP | Wolf HP: $WOLF_HP/$WOLF_MAX_HP\n\nWhat do you do?" 20 70 4 \
            "1" "Attack with longsword (STR-based)" \
            "2" "Defensive stance (reduce damage)" \
            "3" "Use Healing Potion (restore 30 HP)" \
            "4" "Attempt to flee (CHA check)" 3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then CHOICE=1; fi
        
        clear
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$PLAYER_NAME the $CLASS | Lvl $LEVEL | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "🐺 $WOLF_NAME: $WOLF_HP/$WOLF_MAX_HP HP"
        echo ""
        echo "─── Round $ROUND ───"
        echo ""
        
        DEFEND=0
        
        case $CHOICE in
            1)
                ROLL=$((RANDOM % 20 + 1))
                HIT_CHANCE=$((ROLL + STR))
                echo "⚔️  You swing your longsword! [STR Check: rolled $ROLL + $STR = $HIT_CHANCE]"
                if [ $HIT_CHANCE -ge 12 ]; then
                    DMG=$((RANDOM % 8 + 1 + STR))
                    WOLF_HP=$((WOLF_HP - DMG))
                    echo "💥 HIT! Dealt $DMG damage!"
                else
                    echo "❌ MISS! The wolf dodges!"
                fi
                ;;
            2)
                echo "🛡️  You raise your shield defensively!"
                DEFEND=1
                ;;
            3)
                if [[ "$INVENTORY" == *"Healing_Potion"* ]]; then
                    HEAL=30
                    HP=$((HP + HEAL))
                    [ $HP -gt $MAX_HP ] && HP=$MAX_HP
                    INVENTORY=$(echo "$INVENTORY" | sed 's/Healing_Potion//' | sed 's/  / /g')
                    echo "🧪 Drank Healing Potion! Restored $HEAL HP! (HP: $HP/$MAX_HP)"
                else
                    echo "❌ No healing potions left!"
                fi
                ;;
            4)
                ROLL=$((RANDOM % 20 + 1))
                FLEE_CHANCE=$((ROLL + CHA))
                echo "🏃 Attempting to flee... [CHA Check: rolled $ROLL + $CHA = $FLEE_CHANCE]"
                if [ $FLEE_CHANCE -ge 15 ]; then
                    echo "✅ You successfully escape into the darkness!"
                    echo "The woman follows you to safety."
                    sleep 2
                    break
                else
                    echo "❌ Failed to escape! The wolf blocks your path!"
                fi
                ;;
        esac
        
        echo ""
        sleep 1.5
        
        # Wolf's turn
        if [ "$WOLF_HP" -gt 0 ]; then
            WOLF_ROLL=$((RANDOM % 20 + 1))
            WOLF_HIT=$((WOLF_ROLL + WOLF_ATK))
            echo "🐺 The $WOLF_NAME attacks! [rolled $WOLF_ROLL + $WOLF_ATK = $WOLF_HIT]"
            
            if [ $WOLF_HIT -ge 14 ]; then
                WOLF_DMG=$((RANDOM % 10 + 1 + 3))
                if [ $DEFEND -eq 1 ]; then
                    WOLF_DMG=$((WOLF_DMG / 2))
                    echo "🛡️  Your shield absorbs some damage!"
                fi
                HP=$((HP - WOLF_DMG))
                echo "💢 The wolf bites you for $WOLF_DMG damage! (HP: $HP/$MAX_HP)"
            else
                echo "✨ The wolf's attack misses!"
            fi
        fi
        
        echo ""
        sleep 1.5
        ROUND=$((ROUND + 1))
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$HP" -le 0 ]; then
        echo "💀 YOU HAVE FALLEN 💀"
        echo ""
        echo "The dire wolf was too powerful..."
        echo "Your journey ends here in the dark forest."
        echo ""
        echo "GAME OVER"
        echo ""
        echo "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=0|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=DEAD|INVENTORY=$INVENTORY"
    elif [ "$WOLF_HP" -le 0 ]; then
        XP=$((XP + 100))
        GOLD=$((GOLD + 25))
        echo "⚔️  VICTORY! ⚔️"
        echo ""
        echo "The dire wolf falls with a final howl!"
        echo "[Gained: 100 XP, 25 Gold]"
        echo ""
        echo "The woman thanks you profusely."
        echo '"I am Elena, a merchant\'s daughter. Bandits attacked our"'
        echo '"caravan. Please, help me reach the village of Millhaven!"'
        echo ""
        echo "Elena joins your party. She gives you a Silver Amulet as thanks."
        INVENTORY="$INVENTORY Silver_Amulet"
        echo ""
        echo "Current HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP"
        echo ""
        echo "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=2|INVENTORY=$INVENTORY|COMPANION=Elena"
    else
        echo "You escaped the encounter."
        echo ""
        echo "STATE:PLAYER_NAME=$PLAYER_NAME|CLASS=$CLASS|HP=$HP|MAX_HP=$MAX_HP|GOLD=$GOLD|XP=$XP|LEVEL=$LEVEL|STR=$STR|DEX=$DEX|CON=$CON|INT=$INT|WIS=$WIS|CHA=$CHA|CHAPTER=1|INVENTORY=$INVENTORY"
    fi
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: D&D fantasy adventure - character creation
# Generated: 2026-01-31 10:04:33 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step6() {
    # Global game state
    declare -g PLAYER_NAME PLAYER_CLASS PLAYER_RACE
    declare -g HP MAX_HP STRENGTH DEXTERITY CONSTITUTION INTELLIGENCE WISDOM CHARISMA
    declare -g GOLD LEVEL XP
    declare -g -a INVENTORY
    
    clear
    
    # ASCII title
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║         ████████╗██╗  ██╗███████╗    ██████╗ ██╗   ██╗███╗   ██╗ ║
║         ╚══██╔══╝██║  ██║██╔════╝    ██╔══██╗██║   ██║████╗  ██║ ║
║            ██║   ███████║█████╗      ██████╔╝██║   ██║██╔██╗ ██║ ║
║            ██║   ██╔══██║██╔══╝      ██╔══██╗██║   ██║██║╚██╗██║ ║
║            ██║   ██║  ██║███████╗    ██║  ██║╚██████╔╝██║ ╚████║ ║
║            ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ║
║                                                                   ║
║              Chronicles of the Forgotten Realm                    ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    echo "Welcome, brave adventurer! Your journey begins..."
    echo ""
    
    # Character creation
    read -rp "What is your name? " PLAYER_NAME
    echo ""
    
    echo "Choose your race:"
    echo "1) Human    - Versatile and ambitious (+1 to all stats)"
    echo "2) Elf      - Graceful and wise (+2 DEX, +1 INT)"
    echo "3) Dwarf    - Hardy and strong (+2 CON, +1 STR)"
    echo "4) Halfling - Lucky and nimble (+2 DEX, +1 CHA)"
    read -rp "Enter 1-4: " race_choice
    
    case $race_choice in
        1) PLAYER_RACE="Human" ;;
        2) PLAYER_RACE="Elf" ;;
        3) PLAYER_RACE="Dwarf" ;;
        4) PLAYER_RACE="Halfling" ;;
        *) PLAYER_RACE="Human" ;;
    esac
    
    echo ""
    echo "Choose your class:"
    echo "1) Fighter  - Master of weapons and armor (High HP, high STR)"
    echo "2) Rogue    - Cunning and stealthy (High DEX, medium HP)"
    echo "3) Wizard   - Wielder of arcane magic (High INT, low HP)"
    echo "4) Cleric   - Divine healer and warrior (High WIS, medium HP)"
    read -rp "Enter 1-4: " class_choice
    
    # Base stats
    STRENGTH=10
    DEXTERITY=10
    CONSTITUTION=10
    INTELLIGENCE=10
    WISDOM=10
    CHARISMA=10
    
    case $class_choice in
        1) 
            PLAYER_CLASS="Fighter"
            STRENGTH=16
            CONSTITUTION=14
            MAX_HP=12
            ;;
        2) 
            PLAYER_CLASS="Rogue"
            DEXTERITY=16
            CHARISMA=14
            MAX_HP=8
            ;;
        3) 
            PLAYER_CLASS="Wizard"
            INTELLIGENCE=16
            WISDOM=14
            MAX_HP=6
            ;;
        4) 
            PLAYER_CLASS="Cleric"
            WISDOM=16
            STRENGTH=14
            MAX_HP=10
            ;;
        *) 
            PLAYER_CLASS="Fighter"
            STRENGTH=16
            MAX_HP=10
            ;;
    esac
    
    # Apply racial bonuses
    case $PLAYER_RACE in
        "Human")
            ((STRENGTH++)); ((DEXTERITY++)); ((CONSTITUTION++))
            ((INTELLIGENCE++)); ((WISDOM++)); ((CHARISMA++))
            ;;
        "Elf")
            ((DEXTERITY+=2)); ((INTELLIGENCE++))
            ;;
        "Dwarf")
            ((CONSTITUTION+=2)); ((STRENGTH++))
            ;;
        "Halfling")
            ((DEXTERITY+=2)); ((CHARISMA++))
            ;;
    esac
    
    HP=$MAX_HP
    GOLD=20
    LEVEL=1
    XP=0
    INVENTORY=("Rusty Sword" "Leather Armor" "Healing Potion")
    
    clear
    cat << EOF

═══════════════════════════════════════════════════════════════════
                      CHARACTER CREATED!
═══════════════════════════════════════════════════════════════════

Name:  $PLAYER_NAME the $PLAYER_RACE $PLAYER_CLASS
Level: $LEVEL                                    XP: $XP/100

╔═══════════════════╗    ╔═══════════════════════════════════════╗
║   HIT POINTS      ║    ║          ABILITY SCORES               ║
║   [$HP/$MAX_HP]        ║    ║                                       ║
╚═══════════════════╝    ║   STR: $STRENGTH  DEX: $DEXTERITY  CON: $CONSTITUTION        ║
                         ║   INT: $INTELLIGENCE  WIS: $WISDOM   CHA: $CHARISMA         ║
╔═══════════════════╗    ╚═══════════════════════════════════════╝
║   GOLD: $GOLD gp       ║    
╚═══════════════════╝    ╔═══════════════════════════════════════╗
                         ║          INVENTORY                    ║
                         ║   - ${INVENTORY[0]}                      ║
                         ║   - ${INVENTORY[1]}                   ║
                         ║   - ${INVENTORY[2]}                 ║
                         ╚═══════════════════════════════════════╝

═══════════════════════════════════════════════════════════════════
EOF
    
    echo ""
    read -rp "Press ENTER to begin your adventure..."
    
    echo ""
    echo "CHAPTER_CREATED|HP:$HP|CLASS:$PLAYER_CLASS|NAME:$PLAYER_NAME"
}
step6

# ═══════════════════════════════════════════════════════════════
# STEP 7: Chapter 1 - The Dark Forest
# Generated: 2026-01-31 10:05:38 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step7() {
    # Read previous character state
    HP=10
    MAX_HP=10
    NAME="bruce"
    CLASS="Cleric"
    LEVEL=1
    XP=0
    GOLD=20
    
    # Stats
    STR=15
    DEX=11
    CON=11
    INT=11
    WIS=17
    CHA=11
    
    clear
    
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                      CHAPTER 1: THE DARK FOREST"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "You awaken in a small village called Millhaven. The morning sun barely"
    echo "penetrates the thick fog that has settled over the land. The village"
    echo "elder, a wizened old woman named Elara, approaches you urgently."
    echo ""
    echo "\"$NAME! Thank the gods you're here. Last night, the blacksmith's"
    echo "daughter, young Sarah, wandered into the Darkwood Forest and hasn't"
    echo "returned. We've heard... strange howls. Please, you must find her!\""
    echo ""
    echo "She presses 5 gold pieces into your hand."
    echo ""
    
    GOLD=$((GOLD + 5))
    
    sleep 2
    
    echo "═══════════════════════════════════════════════════════════════════"
    echo "You approach the edge of the Darkwood. The trees loom before you,"
    echo "twisted and ancient. A narrow path leads into the darkness."
    echo ""
    echo "As you step forward, you notice:"
    echo "  • Fresh footprints (small, child-sized) leading north"
    echo "  • Strange claw marks on a nearby tree to the east"
    echo "  • The sound of running water to the west"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "What do you do?"
    echo ""
    echo "1) Follow the footprints north (likely Sarah's trail)"
    echo "2) Investigate the claw marks to the east"
    echo "3) Head toward the water to the west"
    echo "4) Say a prayer for divine guidance (WIS check)"
    echo ""
    read -rp "Enter your choice (1-4): " CHOICE
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    
    case $CHOICE in
        1)
            echo ""
            echo "You follow the small footprints along the winding path. After several"
            echo "minutes, you hear a faint whimper ahead. Pushing through the brush,"
            echo "you find Sarah huddled against a tree, terrified."
            echo ""
            echo "\"Help! There's something out there!\" she cries."
            echo ""
            echo "Before you can respond, a DIRE WOLF leaps from the shadows!"
            echo ""
            ENEMY="Dire Wolf"
            ENEMY_HP=12
            ENEMY_AC=12
            ENEMY_ATK=5
            ;;
        2)
            echo ""
            echo "You cautiously approach the tree. The claw marks are fresh and deep."
            echo "[WIS Check: Rolling 1d20 + $((WIS/2 - 5))...]"
            ROLL=$((RANDOM % 20 + 1))
            WISDOM_BONUS=$((WIS/2 - 5))
            TOTAL=$((ROLL + WISDOM_BONUS))
            echo "Rolled: $ROLL + $WISDOM_BONUS = $TOTAL"
            echo ""
            if [ $TOTAL -ge 12 ]; then
                echo "SUCCESS! You recognize these as goblin claw marks - a warning sign!"
                echo "You gain insight: +10 XP"
                XP=$((XP + 10))
                echo ""
                echo "Following the marks, you discover a goblin camp! Two GOBLINS spot you!"
                ENEMY="2 Goblins"
                ENEMY_HP=14
                ENEMY_AC=13
                ENEMY_ATK=4
            else
                echo "You're not sure what made these marks. As you lean closer..."
                echo "A GOBLIN drops from the tree above! Another emerges from the brush!"
                ENEMY="2 Goblins (Surprised!)"
                ENEMY_HP=14
                ENEMY_AC=13
                ENEMY_ATK=4
                HP=$((HP - 2))
                echo ""
                echo "You take 2 damage from surprise! HP: $HP/$MAX_HP"
            fi
            ;;
        3)
            echo ""
            echo "You make your way toward the sound of water and discover a small"
            echo "stream. Kneeling to drink, you notice the water glowing faintly..."
            echo ""
            echo "A magical spring! You fill your waterskin."
            echo ""
            echo "+5 HP restored! You gain a Flask of Blessed Water!"
            HP=$((HP > MAX_HP ? MAX_HP : HP + 5))
            echo "HP: $HP/$MAX_HP"
            echo ""
            sleep 1
            echo "Suddenly, you hear a scream from the north - Sarah!"
            echo "You sprint through the forest and find her cornered by a DIRE WOLF!"
            ENEMY="Dire Wolf"
            ENEMY_HP=12
            ENEMY_AC=12
            ENEMY_ATK=5
            ;;
        4)
            echo ""
            echo "You kneel and pray to your deity for guidance..."
            echo "[WIS Check: Rolling 1d20 + $((WIS/2 - 5))...]"
            ROLL=$((RANDOM % 20 + 1))
            WISDOM_BONUS=$((WIS/2 - 5))
            TOTAL=$((ROLL + WISDOM_BONUS))
            echo "Rolled: $ROLL + $WISDOM_BONUS = $TOTAL"
            echo ""
            if [ $TOTAL -ge 15 ]; then
                echo "CRITICAL SUCCESS! Divine light fills your mind!"
                echo "You see a vision: Sarah to the north, trapped by a wolf."
                echo "Your deity grants you DIVINE FAVOR: +2 to next attack roll!"
                echo "+20 XP for divine communion"
                XP=$((XP + 20))
                DIVINE_FAVOR=2
            else
                echo "You feel a gentle warmth, but no clear vision."
                echo "You must trust your instincts. The footprints lead north..."
            fi
            echo ""
            sleep 1
            echo "Following your insight, you find Sarah cornered by a DIRE WOLF!"
            ENEMY="Dire Wolf"
            ENEMY_HP=12
            ENEMY_AC=12
            ENEMY_ATK=5
            ;;
    esac
    
    echo ""
    echo "COMBAT_START|HP:$HP|XP:$XP|GOLD:$GOLD|ENEMY:$ENEMY|ENEMY_HP:$ENEMY_HP|FAVOR:${DIVINE_FAVOR:-0}"
}
step7

# ═══════════════════════════════════════════════════════════════
# STEP 8: Combat system - player vs Dire Wolf with turn-based mechanics
# Generated: 2026-01-31 10:07:27 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step8() {
    # Combat state from previous step
    PLAYER_HP=10
    PLAYER_MAX_HP=10
    PLAYER_XP=20
    PLAYER_GOLD=25
    PLAYER_LEVEL=1
    PLAYER_STR=2
    PLAYER_DEX=1
    PLAYER_CON=0
    PLAYER_INT=1
    PLAYER_WIS=3
    PLAYER_CHA=0
    DIVINE_FAVOR=2
    
    ENEMY_NAME="Dire Wolf"
    ENEMY_HP=12
    ENEMY_MAX_HP=12
    ENEMY_ATK=4
    ENEMY_DEF=2
    
    clear
    
    # Combat display function
    show_combat_status() {
        echo "═══════════════════════════════════════════════════════════════════"
        echo "                           ⚔️  COMBAT  ⚔️"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "YOU (bruce the Cleric)               ${ENEMY_NAME}"
        echo "HP: ${PLAYER_HP}/${PLAYER_MAX_HP} [$( printf '█%.0s' $(seq 1 $((PLAYER_HP * 10 / PLAYER_MAX_HP))) )]                HP: ${ENEMY_HP}/${ENEMY_MAX_HP} [$( printf '█%.0s' $(seq 1 $((ENEMY_HP * 10 / ENEMY_MAX_HP))) )]"
        [[ $DIVINE_FAVOR -gt 0 ]] && echo "✨ Divine Favor: +${DIVINE_FAVOR} to next attack"
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
    }
    
    # Combat round
    show_combat_status
    echo ""
    echo "The wolf snarls, ready to pounce! Sarah cowers behind you."
    echo ""
    echo "Your actions:"
    echo "1) Attack with mace (STR-based, 1d6+2 damage)"
    echo "2) Sacred Flame (WIS-based spell, 1d8 radiant, enemy DEX save)"
    echo "3) Healing Word on self (heal 1d4+3 HP)"
    echo "4) Try to intimidate the wolf (CHA check)"
    echo ""
    read -rp "Enter your choice (1-4): " choice
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    
    case $choice in
        1)
            echo "You swing your mace at the Dire Wolf!"
            roll=$((RANDOM % 20 + 1))
            total=$((roll + PLAYER_STR + DIVINE_FAVOR))
            echo "[Attack Roll: 1d20+${PLAYER_STR}+${DIVINE_FAVOR} = ${roll}+${PLAYER_STR}+${DIVINE_FAVOR} = ${total}]"
            DIVINE_FAVOR=0
            
            if [[ $total -ge $((ENEMY_DEF + 10)) ]]; then
                dmg=$((RANDOM % 6 + 1 + PLAYER_STR))
                echo "💥 HIT! Damage: ${dmg}"
                ENEMY_HP=$((ENEMY_HP - dmg))
                [[ $roll -eq 20 ]] && echo "🎯 CRITICAL HIT! Maximum damage!"
            else
                echo "❌ MISS! The wolf dodges your attack!"
            fi
            ;;
        2)
            echo "You call upon divine fire! Sacred flames descend upon the wolf!"
            echo "[Wolf DEX Save: DC $((8 + PLAYER_WIS + 2))]"
            enemy_save=$((RANDOM % 20 + 1 + 1))
            echo "Wolf rolled: ${enemy_save}"
            
            if [[ $enemy_save -lt $((8 + PLAYER_WIS + 2)) ]]; then
                dmg=$((RANDOM % 8 + 1))
                echo "🔥 The sacred flames burn! Damage: ${dmg} radiant"
                ENEMY_HP=$((ENEMY_HP - dmg))
            else
                dmg=$(( (RANDOM % 8 + 1) / 2 ))
                echo "⚡ Partial save! Damage: ${dmg} radiant"
                ENEMY_HP=$((ENEMY_HP - dmg))
            fi
            DIVINE_FAVOR=0
            ;;
        3)
            heal=$((RANDOM % 4 + 1 + PLAYER_WIS))
            old_hp=$PLAYER_HP
            PLAYER_HP=$((PLAYER_HP + heal))
            [[ $PLAYER_HP -gt $PLAYER_MAX_HP ]] && PLAYER_HP=$PLAYER_MAX_HP
            echo "✨ You channel healing magic! Restored $((PLAYER_HP - old_hp)) HP"
            DIVINE_FAVOR=0
            ;;
        4)
            echo "You attempt to intimidate the beast!"
            roll=$((RANDOM % 20 + 1))
            total=$((roll + PLAYER_CHA))
            echo "[CHA Check: ${roll}+${PLAYER_CHA} = ${total} vs DC 14]"
            
            if [[ $total -ge 14 ]]; then
                echo "🎭 SUCCESS! The wolf backs away, whimpering!"
                echo "You grab Sarah and flee! Combat avoided!"
                echo ""
                echo "+30 XP for clever thinking!"
                PLAYER_XP=$((PLAYER_XP + 30))
                echo ""
                echo "COMBAT_END|HP:${PLAYER_HP}|XP:${PLAYER_XP}|GOLD:${PLAYER_GOLD}|OUTCOME:fled"
                return
            else
                echo "❌ FAILED! The wolf is not impressed!"
            fi
            DIVINE_FAVOR=0
            ;;
        *)
            echo "Invalid choice! You hesitate..."
            DIVINE_FAVOR=0
            ;;
    esac
    
    # Check if enemy defeated
    if [[ $ENEMY_HP -le 0 ]]; then
        echo ""
        echo "🎉 The Dire Wolf collapses! Victory!"
        echo ""
        echo "+50 XP | Found: 3 gold pieces"
        PLAYER_XP=$((PLAYER_XP + 50))
        PLAYER_GOLD=$((PLAYER_GOLD + 3))
        echo ""
        echo "Sarah runs to you, tears streaming down her face."
        echo "'Thank you! Thank you! I was so scared!'"
        echo ""
        echo "COMBAT_END|HP:${PLAYER_HP}|XP:${PLAYER_XP}|GOLD:${PLAYER_GOLD}|OUTCOME:victory"
        return
    fi
    
    # Enemy turn
    echo ""
    echo "--- ENEMY TURN ---"
    sleep 1
    echo "The Dire Wolf lunges at you!"
    
    enemy_roll=$((RANDOM % 20 + 1))
    enemy_total=$((enemy_roll + ENEMY_ATK))
    player_ac=$((10 + PLAYER_DEX + 2))
    
    echo "[Wolf Attack: ${enemy_roll}+${ENEMY_ATK} = ${enemy_total} vs AC ${player_ac}]"
    
    if [[ $enemy_total -ge $player_ac ]]; then
        dmg=$((RANDOM % 6 + 1 + 2))
        echo "🩸 HIT! You take ${dmg} damage!"
        PLAYER_HP=$((PLAYER_HP - dmg))
    else
        echo "🛡️  MISS! You dodge the attack!"
    fi
    
    echo ""
    
    # Check if player defeated
    if [[ $PLAYER_HP -le 0 ]]; then
        echo "💀 You fall unconscious..."
        echo "The last thing you see is Sarah screaming..."
        echo ""
        echo "GAME OVER"
        echo ""
        echo "COMBAT_END|HP:0|XP:${PLAYER_XP}|GOLD:${PLAYER_GOLD}|OUTCOME:defeat"
        return
    fi
    
    echo "COMBAT_CONTINUE|HP:${PLAYER_HP}|ENEMY_HP:${ENEMY_HP}|XP:${PLAYER_XP}|GOLD:${PLAYER_GOLD}|FAVOR:${DIVINE_FAVOR}"
}

step8

# ═══════════════════════════════════════════════════════════════
# STEP 9: Continue combat - player damaged, wolf still at full health
# Generated: 2026-01-31 10:09:47 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step9() {
    clear
    
    # Parse state from previous output
    HP=5
    ENEMY_HP=12
    XP=20
    GOLD=25
    FAVOR=0
    MAX_HP=10
    ENEMY_MAX_HP=12
    
    # Helper function for HP bar
    hp_bar() {
        local current=$1
        local max=$2
        local width=10
        local filled=$((current * width / max))
        local empty=$((width - filled))
        printf "["
        printf "█%.0s" $(seq 1 $filled 2>/dev/null)
        printf "░%.0s" $(seq 1 $empty 2>/dev/null)
        printf "]"
    }
    
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                           ⚔️  COMBAT  ⚔️"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    printf "YOU (bruce the Cleric)               Dire Wolf\n"
    printf "HP: %d/%d " $HP $MAX_HP
    hp_bar $HP $MAX_HP
    printf "                HP: %d/%d " $ENEMY_HP $ENEMY_MAX_HP
    hp_bar $ENEMY_HP $ENEMY_MAX_HP
    echo ""
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "⚠️  You're badly wounded! Sarah gasps in horror as blood seeps through"
    echo "your armor. The wolf circles, sensing weakness..."
    echo ""
    echo "Your actions:"
    echo "1) Attack with mace (STR-based, 1d6+2 damage) - risky!"
    echo "2) Sacred Flame (WIS-based spell, 1d8 radiant, enemy DEX save)"
    echo "3) 🩹 Healing Word on self (heal 1d4+3 HP) - RECOMMENDED"
    echo "4) Try to intimidate the wolf (CHA check)"
    echo ""
    read -rp "Enter your choice (1-4): " choice
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    
    case $choice in
        1)
            echo "You grit your teeth and swing your mace despite your injuries!"
            ATTACK=$((RANDOM % 20 + 1))
            MOD=2
            TOTAL=$((ATTACK + MOD))
            echo "[Attack Roll: 1d20+$MOD = $ATTACK+$MOD = $TOTAL]"
            if [ $TOTAL -ge 12 ]; then
                DMG=$((RANDOM % 6 + 1 + 2))
                echo "💥 HIT! You deal $DMG damage!"
                ENEMY_HP=$((ENEMY_HP - DMG))
                FAVOR=2
            else
                echo "❌ MISS! Your wound throws off your aim!"
            fi
            ;;
        2)
            echo "You invoke holy fire upon the beast!"
            SAVE=$((RANDOM % 20 + 1 + 1))
            echo "[Wolf DEX Save: 1d20+1 = $SAVE vs DC 13]"
            if [ $SAVE -lt 13 ]; then
                DMG=$((RANDOM % 8 + 1))
                echo "🔥 The wolf howls as sacred flames engulf it! $DMG radiant damage!"
                ENEMY_HP=$((ENEMY_HP - DMG))
                FAVOR=2
            else
                echo "❌ The wolf dodges the divine fire!"
            fi
            ;;
        3)
            HEAL=$((RANDOM % 4 + 1 + 3))
            HP=$((HP + HEAL))
            [ $HP -gt $MAX_HP ] && HP=$MAX_HP
            echo "✨ Golden light surrounds you as wounds close!"
            echo "💚 You heal $HEAL HP! (Now at $HP/$MAX_HP)"
            FAVOR=2
            ;;
        4)
            echo "You roar at the wolf, trying to appear threatening!"
            CHA_ROLL=$((RANDOM % 20 + 1 - 1))
            echo "[Intimidation Check: 1d20-1 = $CHA_ROLL]"
            if [ $CHA_ROLL -ge 14 ]; then
                echo "😨 The wolf hesitates, backing away slightly!"
                echo "You gain advantage on your next attack!"
                FAVOR=3
            else
                echo "❌ The wolf seems unimpressed by your bravado!"
            fi
            ;;
    esac
    
    if [ $ENEMY_HP -le 0 ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "🎉 VICTORY! The dire wolf collapses!"
        XP=$((XP + 50))
        GOLD=$((GOLD + 15))
        echo "💫 +50 XP (Total: $XP)"
        echo "💰 +15 gold (Total: $GOLD)"
        echo "COMBAT_WON|HP:$HP|XP:$XP|GOLD:$GOLD"
    else
        echo ""
        echo "--- ENEMY TURN ---"
        echo "The Dire Wolf lunges again!"
        WOLF_ATK=$((RANDOM % 20 + 1 + 4))
        echo "[Wolf Attack: 1d20+4 = $WOLF_ATK vs AC 13]"
        if [ $WOLF_ATK -ge 13 ]; then
            WOLF_DMG=$((RANDOM % 6 + 1 + 2))
            HP=$((HP - WOLF_DMG))
            echo "🩸 HIT! You take $WOLF_DMG damage!"
            
            if [ $HP -le 0 ]; then
                echo ""
                echo "═══════════════════════════════════════════════════════════════════"
                echo "💀 You fall unconscious! Sarah screams..."
                echo "COMBAT_LOST|HP:0"
            else
                echo ""
                echo "COMBAT_CONTINUE|HP:$HP|ENEMY_HP:$ENEMY_HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
            fi
        else
            echo "✨ MISS! You dodge the attack!"
            echo ""
            echo "COMBAT_CONTINUE|HP:$HP|ENEMY_HP:$ENEMY_HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
        fi
    fi
}
step9

# ═══════════════════════════════════════════════════════════════
# STEP 10: Enemy turn complete, display status and get player action
# Generated: 2026-01-31 10:11:01 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step10() {
    # Combat state from previous output
    HP=3
    MAX_HP=10
    ENEMY_HP=12
    ENEMY_MAX_HP=12
    XP=20
    GOLD=25
    FAVOR=2
    
    clear
    
    # Combat header
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                           ⚔️  COMBAT  ⚔️"
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    
    # Health bars
    player_bars=$(printf '█%.0s' $(seq 1 $((HP * 10 / MAX_HP))))
    player_empty=$(printf '░%.0s' $(seq 1 $((10 - HP * 10 / MAX_HP))))
    
    enemy_bars=$(printf '█%.0s' $(seq 1 $((ENEMY_HP * 10 / ENEMY_MAX_HP))))
    enemy_empty=$(printf '░%.0s' $(seq 1 $((10 - ENEMY_HP * 10 / ENEMY_MAX_HP))))
    
    printf "YOU (bruce the Cleric)               Dire Wolf\n"
    printf "HP: %d/%d [%s%s]                HP: %d/%d [%s%s]\n" $HP $MAX_HP "$player_bars" "$player_empty" $ENEMY_HP $ENEMY_MAX_HP "$enemy_bars" "$enemy_empty"
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    echo "🩸 CRITICAL DANGER! You're at death's door (3 HP)!"
    echo "Sarah screams: 'Bruce, you're dying! Heal yourself NOW!'"
    echo "The wolf's jaws drip with your blood as it prepares to finish you..."
    echo
    echo "Your actions:"
    echo "1) 🩹 Healing Word on self (heal 1d4+3 HP) - HEAL OR DIE!"
    echo "2) Sacred Flame (WIS-based spell, 1d8 radiant, enemy DEX save)"
    echo "3) Attack with mace (STR-based, 1d6+2 damage)"
    echo "4) Desperate prayer to your deity (WIS check, risky)"
    echo
    read -rp "Enter your choice (1-4): " choice
    
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    
    case $choice in
        1)
            heal=$((RANDOM % 4 + 1 + 3))
            HP=$((HP + heal))
            [[ $HP -gt $MAX_HP ]] && HP=$MAX_HP
            echo "✨ Divine light washes over you! Wounds knit together!"
            echo "💚 You heal $heal HP! (Now at $HP/$MAX_HP)"
            ;;
        2)
            dex_save=$((RANDOM % 20 + 1 + 1))
            if [[ $dex_save -lt 13 ]]; then
                damage=$((RANDOM % 8 + 1))
                ENEMY_HP=$((ENEMY_HP - damage))
                echo "🔥 Sacred flames engulf the wolf!"
                echo "⚡ $damage radiant damage! The beast howls in pain!"
            else
                echo "💨 The wolf dodges! Your flames scorch only earth!"
            fi
            ;;
        3)
            attack=$((RANDOM % 20 + 1 + 2))
            if [[ $attack -ge 13 ]]; then
                damage=$((RANDOM % 6 + 1 + 2))
                ENEMY_HP=$((ENEMY_HP - damage))
                echo "⚔️ Your mace connects with a sickening crunch!"
                echo "💥 $damage damage!"
            else
                echo "💨 You swing wildly but miss!"
            fi
            ;;
        4)
            wis_check=$((RANDOM % 20 + 1 + 3))
            if [[ $wis_check -ge 15 ]]; then
                echo "✨ Your deity answers! Divine power surges through you!"
                heal=5
                HP=$((HP + heal))
                [[ $HP -gt $MAX_HP ]] && HP=$MAX_HP
                ENEMY_HP=$((ENEMY_HP - 3))
                echo "💚 You heal $heal HP and the wolf takes 3 radiant damage!"
            else
                echo "🙏 Your prayer goes unanswered in this desperate moment..."
            fi
            ;;
        *)
            echo "❌ Hesitation! You waste your turn!"
            ;;
    esac
    
    echo
    
    # Check if wolf is dead
    if [[ $ENEMY_HP -le 0 ]]; then
        echo "COMBAT_WON|HP:$HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
        exit 0
    fi
    
    # Enemy turn
    echo "--- ENEMY TURN ---"
    sleep 1
    wolf_attack=$((RANDOM % 20 + 1 + 4))
    
    if [[ $wolf_attack -ge 13 ]]; then
        damage=$((RANDOM % 10 + 1 + 2))
        HP=$((HP - damage))
        echo "The Dire Wolf's fangs sink deep into your flesh!"
        echo "🩸 HIT! You take $damage damage!"
        
        if [[ $HP -le 0 ]]; then
            echo
            echo "PLAYER_DEATH|HP:0|ENEMY_HP:$ENEMY_HP"
            exit 0
        fi
    else
        echo "💨 The wolf lunges but you dodge aside!"
    fi
    
    echo
    echo "COMBAT_CONTINUE|HP:$HP|ENEMY_HP:$ENEMY_HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
}
step10

# ═══════════════════════════════════════════════════════════════
# STEP 11: Continue D&D combat - wolf's turn and player's next action
# Generated: 2026-01-31 10:13:08 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step11() {
  # Parse state from previous output
  HP=5
  ENEMY_HP=12
  XP=20
  GOLD=25
  FAVOR=2
  
  # Clear screen and show combat status
  clear
  echo "═══════════════════════════════════════════════════════════════════"
  echo "                           ⚔️  COMBAT  ⚔️"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  
  # Health bars
  player_bar=$(printf '█%.0s' $(seq 1 $((HP * 10 / 10))))
  player_empty=$(printf '░%.0s' $(seq 1 $((10 - HP))))
  enemy_bar=$(printf '█%.0s' $(seq 1 $((ENEMY_HP * 10 / 12))))
  enemy_empty=$(printf '░%.0s' $(seq 1 $((12 - ENEMY_HP))))
  
  echo "YOU (bruce the Cleric)               Dire Wolf"
  echo "HP: $HP/10 [${player_bar}${player_empty}]                HP: $ENEMY_HP/12 [${enemy_bar}${enemy_empty}]"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "⚠️  DANGER! The wolf circles, bloodthirsty and enraged!"
  echo "Sarah grips her dagger, ready to assist if you fall..."
  echo ""
  echo "Your actions:"
  echo "1) 🩹 Healing Word on self (heal 1d4+3 HP)"
  echo "2) ⚡ Sacred Flame (WIS-based spell, 1d8 radiant, enemy DEX save DC 13)"
  echo "3) ⚔️  Attack with mace (STR-based, 1d6+2 damage, +4 to hit)"
  echo "4) 🛡️  Dodge (disadvantage on enemy attacks this round)"
  echo ""
  read -rp "Enter your choice (1-4): " choice
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  
  # Process player action
  case $choice in
    1)
      heal_roll=$((RANDOM % 4 + 1 + 3))
      echo "✨ Divine light washes over you! Wounds knit together!"
      echo "💚 You heal $heal_roll HP!"
      HP=$((HP + heal_roll))
      [[ $HP -gt 10 ]] && HP=10
      echo "(Now at $HP/10 HP)"
      ;;
    2)
      dex_save=$((RANDOM % 20 + 1 + 2))
      if [[ $dex_save -lt 13 ]]; then
        dmg=$((RANDOM % 8 + 1))
        echo "🔥 Sacred flames engulf the wolf! (DEX save: $dex_save, failed)"
        echo "💥 The wolf takes $dmg radiant damage!"
        ENEMY_HP=$((ENEMY_HP - dmg))
      else
        echo "💨 The wolf leaps aside! (DEX save: $dex_save, succeeded)"
        echo "Your sacred flames scorch only grass!"
      fi
      ;;
    3)
      attack_roll=$((RANDOM % 20 + 1))
      if [[ $attack_roll -ge 14 ]]; then
        dmg=$((RANDOM % 6 + 1 + 2))
        echo "⚔️  Your mace strikes true! (rolled ${attack_roll}+4 vs AC 14)"
        echo "💥 You deal $dmg bludgeoning damage!"
        ENEMY_HP=$((ENEMY_HP - dmg))
      else
        echo "❌ Your mace swings wide! (rolled ${attack_roll}+4, needed 14+)"
        echo "The wolf dances away from your blow!"
      fi
      ;;
    4)
      echo "🛡️  You focus on defense, weaving and dodging!"
      DODGE=1
      ;;
  esac
  
  echo ""
  
  # Check if wolf is dead
  if [[ $ENEMY_HP -le 0 ]]; then
    echo "═══════════════════════════════════════════════════════════════════"
    echo "🎉 VICTORY! 🎉"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "The dire wolf collapses with a final whimper, its eyes glazing over."
    echo "Sarah exhales shakily: 'We... we did it! You're incredible, Bruce!'"
    echo ""
    XP=$((XP + 50))
    GOLD=$((GOLD + 15))
    FAVOR=$((FAVOR + 1))
    echo "🌟 +50 XP (Total: $XP)"
    echo "💰 Found 15 gold on the wolf (Total: $GOLD)"
    echo "✨ +1 Divine Favor (Total: $FAVOR)"
    echo ""
    echo "COMBAT_WON|HP:$HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
  else
    # Enemy turn
    echo "--- ENEMY TURN ---"
    wolf_attack=$((RANDOM % 20 + 1))
    threshold=14
    [[ -n "$DODGE" ]] && echo "🛡️  (Dodge active - disadvantage on enemy attack)" && {
      wolf_attack2=$((RANDOM % 20 + 1))
      [[ $wolf_attack2 -lt $wolf_attack ]] && wolf_attack=$wolf_attack2
    }
    
    if [[ $wolf_attack -ge 12 ]]; then
      wolf_dmg=$((RANDOM % 10 + 1 + 2))
      echo "The Dire Wolf's fangs sink deep into your flesh!"
      echo "🩸 HIT! (rolled ${wolf_attack}+4) You take $wolf_dmg damage!"
      HP=$((HP - wolf_dmg))
    else
      echo "💨 The wolf snaps at empty air! (rolled ${wolf_attack}+4, needed 12+)"
      echo "You dodge its savage bite!"
    fi
    
    echo ""
    
    # Check if player is dead
    if [[ $HP -le 0 ]]; then
      echo "═══════════════════════════════════════════════════════════════════"
      echo "💀 DEFEAT 💀"
      echo "═══════════════════════════════════════════════════════════════════"
      echo ""
      echo "Darkness closes in as you fall. The last thing you hear is Sarah"
      echo "screaming your name... then nothing."
      echo ""
      echo "GAME_OVER|HP:0"
    else
      echo "COMBAT_CONTINUE|HP:$HP|ENEMY_HP:$ENEMY_HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
    fi
  fi
}
step11

# ═══════════════════════════════════════════════════════════════
# STEP 12: Continue D&D combat - round 2
# Generated: 2026-01-31 10:15:02 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step12() {
    # Parse state from previous output
    HP=5
    ENEMY_HP=7
    XP=20
    GOLD=25
    FAVOR=2
    PLAYER_NAME="bruce"
    PLAYER_CLASS="Cleric"
    ENEMY_NAME="Dire Wolf"
    MAX_HP=10
    ENEMY_MAX_HP=12

    clear
    
    # Combat header
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                           ⚔️  COMBAT  ⚔️"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    # HP bars
    player_filled=$((HP * 10 / MAX_HP))
    enemy_filled=$((ENEMY_HP * 10 / ENEMY_MAX_HP))
    player_bar=$(printf '█%.0s' $(seq 1 $player_filled))$(printf '░%.0s' $(seq 1 $((10-player_filled))))
    enemy_bar=$(printf '█%.0s' $(seq 1 $enemy_filled))$(printf '░%.0s' $(seq 1 $((10-enemy_filled))))
    
    printf "YOU (%s the %s)%*sEnemy: %s\n" "$PLAYER_NAME" "$PLAYER_CLASS" $((44-${#PLAYER_NAME}-${#PLAYER_CLASS})) "" "$ENEMY_NAME"
    printf "HP: %d/%d [%s]%*sHP: %d/%d [%s]\n" $HP $MAX_HP "$player_bar" $((31-${#HP}-${#MAX_HP})) "" $ENEMY_HP $ENEMY_MAX_HP "$enemy_bar"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "🩸 The wolf is wounded but still dangerous!"
    echo "Sarah watches anxiously, dagger ready..."
    echo ""
    echo "Your actions:"
    echo "1) 🩹 Healing Word on self (heal 1d4+3 HP, bonus action)"
    echo "2) ⚡ Sacred Flame (WIS spell, 1d8 radiant, enemy DEX save DC 13)"
    echo "3) ⚔️  Attack with mace (STR-based, 1d6+2 damage, +4 to hit)"
    echo "4) 🛡️  Dodge (disadvantage on enemy attacks)"
    echo ""
    read -rp "Enter your choice (1-4): " choice
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    
    # Player turn
    case $choice in
        1)
            heal=$((RANDOM % 4 + 1 + 3))
            HP=$((HP + heal > MAX_HP ? MAX_HP : HP + heal))
            echo "✨ Divine light washes over you! You heal $heal HP!"
            echo "💚 Current HP: $HP/$MAX_HP"
            ;;
        2)
            dex_save=$((RANDOM % 20 + 1 + 2))
            if [ $dex_save -lt 13 ]; then
                damage=$((RANDOM % 8 + 1))
                ENEMY_HP=$((ENEMY_HP - damage))
                echo "🔥 Sacred flame descends! (enemy rolled $dex_save, needed 13+)"
                echo "💥 You deal $damage radiant damage!"
            else
                echo "💨 The wolf dodges the holy fire! (rolled $dex_save vs DC 13)"
            fi
            ;;
        3)
            attack_roll=$((RANDOM % 20 + 1 + 4))
            if [ $attack_roll -ge 14 ]; then
                damage=$((RANDOM % 6 + 1 + 2))
                ENEMY_HP=$((ENEMY_HP - damage))
                echo "⚔️  Your mace strikes true! (rolled $attack_roll vs AC 14)"
                echo "💥 You deal $damage bludgeoning damage!"
            else
                echo "💨 Your mace swings wide! (rolled $attack_roll, needed 14+)"
            fi
            ;;
        4)
            echo "🛡️  You focus on defense!"
            DODGING=1
            ;;
    esac
    
    echo ""
    
    # Check if enemy defeated
    if [ $ENEMY_HP -le 0 ]; then
        echo "🎉 VICTORY! The dire wolf falls with a final whimper!"
        echo ""
        echo "Sarah rushes over: 'You did it! That was incredible!'"
        XP=$((XP + 40))
        GOLD=$((GOLD + 15))
        echo "📈 +40 XP (Total: $XP) | 💰 +15 gold (Total: $GOLD)"
        echo ""
        echo "COMBAT_WON|HP:$HP|XP:$XP|GOLD:$GOLD|FAVOR:$((FAVOR+1))"
    else
        # Enemy turn
        echo "--- ENEMY TURN ---"
        if [ "${DODGING:-0}" -eq 1 ]; then
            attack1=$((RANDOM % 20 + 1 + 4))
            attack2=$((RANDOM % 20 + 1 + 4))
            enemy_attack=$((attack1 < attack2 ? attack1 : attack2))
            echo "🛡️  The wolf attacks with disadvantage..."
        else
            enemy_attack=$((RANDOM % 20 + 1 + 4))
        fi
        
        if [ $enemy_attack -ge 12 ]; then
            damage=$((RANDOM % 8 + 1 + 2))
            HP=$((HP - damage))
            echo "🩸 The wolf's fangs find flesh! (rolled $enemy_attack vs AC 12)"
            echo "💔 You take $damage piercing damage!"
            
            if [ $HP -le 0 ]; then
                echo ""
                echo "💀 You fall unconscious..."
                echo "Sarah screams and throws her dagger, driving the wolf back!"
                echo ""
                echo "COMBAT_DEATH|HP:0|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
            else
                echo ""
                echo "COMBAT_CONTINUE|HP:$HP|ENEMY_HP:$ENEMY_HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
            fi
        else
            echo "💨 The wolf's bite misses! (rolled $enemy_attack, needed 12+)"
            echo ""
            echo "COMBAT_CONTINUE|HP:$HP|ENEMY_HP:$ENEMY_HP|XP:$XP|GOLD:$GOLD|FAVOR:$FAVOR"
        fi
    fi
}
step12

# ═══════════════════════════════════════════════════════════════
# STEP 13: Handle death and offer resurrection choices
# Generated: 2026-01-31 10:15:31 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step13() {
  clear
  
  # Parse death state
  HP=0
  MAX_HP=10
  XP=20
  GOLD=25
  FAVOR=2
  LEVEL=1
  NAME="bruce"
  CLASS="Cleric"
  
  # Death scene with dramatic pause
  echo -e "\n\033[1;31m╔═══════════════════════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;31m║                          💀 FALLEN 💀                              ║\033[0m"
  echo -e "\033[1;31m╚═══════════════════════════════════════════════════════════════════╝\033[0m\n"
  
  sleep 1
  echo "Your vision fades to darkness as the wolf's jaws close around you..."
  sleep 2
  echo ""
  echo "Sarah's desperate cry echoes in the void: \"No! Not like this!\""
  sleep 2
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  
  # Fate's choice
  echo -e "\033[1;33m🌟 The Fates offer you a choice:\033[0m\n"
  
  OPTIONS=(
    "1" "⚰️  Accept death - Your story ends here (Game Over)" \
    "2" "✨ Divine Intervention - Your god revives you (Lose 1 FAVOR, return at half HP)" \
    "3" "🔮 Sarah's Sacrifice - She uses forbidden magic (She loses 5 HP, you revive at 1 HP)" \
    "4" "💰 Bribe Death - Pay 20 gold to return (Lose 20 GOLD, return at 1 HP)"
  )
  
  if command -v whiptail &>/dev/null; then
    CHOICE=$(whiptail --title "Death's Door" --menu "\nYour HP: $HP/$MAX_HP | Gold: $GOLD | Divine Favor: $FAVOR\n\nChoose your fate:" 20 78 4 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
  else
    echo "1) ⚰️  Accept death - Game Over"
    echo "2) ✨ Divine Intervention (Requires 1 FAVOR)"
    echo "3) 🔮 Sarah's Sacrifice (She loses 5 HP)"
    echo "4) 💰 Bribe Death (20 gold)"
    echo ""
    read -rp "Enter choice (1-4): " CHOICE
  fi
  
  echo ""
  echo "DEATH_CHOICE:$CHOICE|HP:$HP|GOLD:$GOLD|FAVOR:$FAVOR"
}
step13

# ═══════════════════════════════════════════════════════════════
# STEP 14: Game over - player chose death
# Generated: 2026-01-31 10:16:04 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step14() {
    clear
    
    # Display dramatic death sequence
    echo -e "\n\n"
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "\033[1;31m"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                      ⚰️  GAME OVER ⚰️                          ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "\033[0m"
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    
    # Dramatic narration with delays
    sleep 1
    echo -e "\033[2;3mYou accept the embrace of death...\033[0m"
    sleep 2
    echo
    echo -e "\033[2;3mThe wolf's fangs were the last thing you felt in this world.\033[0m"
    sleep 2
    echo
    echo -e "\033[1;33mSarah kneels beside your fallen form, tears streaming down her face.\033[0m"
    sleep 2
    echo
    echo -e '\033[1;33m"You saved me," she whispers. "I will tell them of your bravery."\033[0m'
    sleep 2
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    
    # Final stats
    echo -e "\033[1;36m📊 FINAL STATISTICS\033[0m"
    echo
    echo "  🗡️  Battles Fought: 2 (Goblin, Dire Wolf)"
    echo "  ⚔️  Enemies Slain: 1 (Goblin)"
    echo "  💰 Gold Earned: 25"
    echo "  🌟 Divine Favor: 2"
    echo "  👥 Allies Met: 1 (Sarah the Herbalist)"
    echo "  ❤️  Final HP: 0/10"
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    echo -e "\033[1;35m🏆 ACHIEVEMENT UNLOCKED:\033[0m"
    echo -e "   \033[1m'Noble Sacrifice'\033[0m - Died protecting an innocent"
    echo
    sleep 2
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    echo -e "\033[1;32mThank you for playing!\033[0m"
    echo
    echo -e "\033[2;3mYour tale, though brief, will be remembered in the annals of"
    echo -e "the Whispering Woods. Perhaps another hero will rise to continue"
    echo -e "the fight against the darkness...\033[0m"
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo
}
step14

_prompt
#
