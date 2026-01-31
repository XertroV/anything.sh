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
TUI: $(for t in whiptail dialog gum fzf; do command -v $t &>/dev/null && printf "%s " "$t"; done)

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
# Generated: 2026-01-31 09:40:03 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    # Game state - global variables
    CHAPTER=1
    PLAYER_NAME=""
    PLAYER_CLASS=""
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
    INVENTORY=("Torch" "Rations (3)")
    
    # Character creation with whiptail
    PLAYER_NAME=$(whiptail --inputbox "⚔️  REALM OF SHADOWS ⚔️\n\nA darkness spreads across the land...\nOnly a brave adventurer can stop it.\n\nEnter your name, hero:" 14 50 "Adventurer" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        echo "Adventure cancelled."
        return 1
    fi
    
    PLAYER_CLASS=$(whiptail --title "Choose Your Class" --menu "\nSelect your path, $PLAYER_NAME:\n" 16 60 4 \
        "WARRIOR" "High HP, Strong melee (STR+2, CON+2)" \
        "ROGUE" "Quick & deadly, finds treasure (DEX+2, CHA+1)" \
        "MAGE" "Powerful spells, fragile (INT+3, WIS+1)" \
        "CLERIC" "Healer & holy magic (WIS+2, CON+1)" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        echo "Adventure cancelled."
        return 1
    fi
    
    # Roll base stats (3d6 style, simplified)
    STR=$((8 + RANDOM % 6))
    DEX=$((8 + RANDOM % 6))
    CON=$((8 + RANDOM % 6))
    INT=$((8 + RANDOM % 6))
    WIS=$((8 + RANDOM % 6))
    CHA=$((8 + RANDOM % 6))
    
    # Apply class bonuses
    case $PLAYER_CLASS in
        "WARRIOR") STR=$((STR+2)); CON=$((CON+2)); INVENTORY+=("Longsword" "Shield");;
        "ROGUE")   DEX=$((DEX+2)); CHA=$((CHA+1)); INVENTORY+=("Dagger" "Lockpicks");;
        "MAGE")    INT=$((INT+3)); WIS=$((WIS+1)); INVENTORY+=("Staff" "Spellbook");;
        "CLERIC")  WIS=$((WIS+2)); CON=$((CON+1)); INVENTORY+=("Mace" "Holy Symbol");;
    esac
    
    # Calculate HP based on class and CON
    case $PLAYER_CLASS in
        "WARRIOR") MAX_HP=$((12 + (CON-10)/2 * 2));;
        "ROGUE")   MAX_HP=$((8 + (CON-10)/2 * 2));;
        "MAGE")    MAX_HP=$((6 + (CON-10)/2 * 2));;
        "CLERIC")  MAX_HP=$((10 + (CON-10)/2 * 2));;
    esac
    HP=$MAX_HP
    
    # Output state for next iteration
    echo "=== CHARACTER CREATED ==="
    echo "NAME: $PLAYER_NAME"
    echo "CLASS: $PLAYER_CLASS"
    echo "LEVEL: $LEVEL | XP: $XP | GOLD: $GOLD"
    echo "HP: $HP/$MAX_HP"
    echo "STR:$STR DEX:$DEX CON:$CON INT:$INT WIS:$WIS CHA:$CHA"
    echo "INVENTORY: ${INVENTORY[*]}"
    echo "CHAPTER: $CHAPTER"
    echo "=== READY FOR CHAPTER 1 ==="
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Chapter 1 - The Village of Thornwood
# Generated: 2026-01-31 09:40:46 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    # Load character state
    NAME="XertroV"
    CLASS="WARRIOR"
    LEVEL=1
    XP=0
    GOLD=10
    HP=14
    MAX_HP=14
    STR=11
    DEX=8
    CON=12
    INT=8
    WIS=13
    CHA=9
    INVENTORY=("Torch" "Rations (3)" "Longsword" "Shield")
    
    # Chapter 1 intro
    clear
    echo -e "\n\033[1;33m═══════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;36m                    CHAPTER 1: THE VILLAGE OF THORNWOOD\033[0m"
    echo -e "\033[1;33m═══════════════════════════════════════════════════════════════\033[0m\n"
    sleep 1
    
    echo -e "\033[0;37mYou arrive at the village of Thornwood as dusk settles."
    echo -e "Smoke rises from chimneys, but the streets are eerily empty."
    echo -e "A weathered sign creaks in the wind: 'Beware the Shadow Woods'\n"
    echo -e "An old man emerges from the tavern, eyes wide with fear.\033[0m"
    sleep 2
    
    echo -e "\n\033[1;35m\"A warrior! Thank the gods!\" he gasps."
    echo -e "\"Dark creatures have taken our children into the woods!"
    echo -e "Please, you must help us!\"\033[0m\n"
    sleep 2
    
    # Player choice
    CHOICE=$(whiptail --title "⚔️ $NAME the $CLASS | HP: $HP/$MAX_HP | Gold: $GOLD" \
        --menu "\nWhat do you do?" 18 70 5 \
        "1" "🗡️  'I will save them!' (Go to Shadow Woods)" \
        "2" "🍺 'Tell me more.' (Enter the tavern for info)" \
        "3" "💰 'What's in it for me?' (Negotiate reward)" \
        "4" "📦 Check inventory and stats" \
        3>&1 1>&2 2>&3)
    
    case $CHOICE in
        1)
            echo -e "\n\033[1;32mYou draw your longsword with determination.\033[0m"
            echo "The old man points toward the dark treeline to the north."
            echo -e "\033[1;33m+25 XP for bravery!\033[0m"
            XP=$((XP + 25))
            NEXT="woods_entrance"
            ;;
        2)
            echo -e "\n\033[0;36mYou enter the Rusty Tankard tavern.\033[0m"
            echo "Inside, frightened villagers huddle around a fire."
            echo "The barkeep slides you an ale. 'On the house, if you'll listen...'"
            echo -e "\n\033[1;35m'Three nights ago, shadow creatures emerged from the old ruins."
            echo "They took five children. We've lost two hunters who went after them."
            echo "They say an ancient evil has awakened...'\033[0m"
            echo -e "\n\033[1;33m+10 XP for gathering intel. You learned: Ruins are the source!\033[0m"
            XP=$((XP + 10))
            NEXT="tavern"
            ;;
        3)
            echo -e "\n\033[0;33mThe old man's face hardens, then softens.\033[0m"
            echo "'We have little, but... 50 gold pieces and a family heirloom"
            echo "if you bring them back safely.'"
            echo -e "\n\033[1;33mQuest reward increased! +5 XP for negotiation.\033[0m"
            XP=$((XP + 5))
            GOLD=$((GOLD + 10)) # Advance payment
            echo -e "\033[1;32mReceived 10 gold advance payment!\033[0m"
            NEXT="woods_entrance"
            ;;
        4)
            echo -e "\n\033[1;34m═══ CHARACTER SHEET ═══\033[0m"
            echo "NAME: $NAME | CLASS: $CLASS | LEVEL: $LEVEL"
            echo "HP: $HP/$MAX_HP | XP: $XP | GOLD: $GOLD"
            echo "STR:$STR DEX:$DEX CON:$CON INT:$INT WIS:$WIS CHA:$CHA"
            echo "INVENTORY: ${INVENTORY[*]}"
            NEXT="village"
            ;;
        *)
            echo "The old man waits nervously..."
            NEXT="village"
            ;;
    esac
    
    echo ""
    echo "=== CHAPTER 1 STATE ==="
    echo "NAME=$NAME CLASS=$CLASS LEVEL=$LEVEL XP=$XP GOLD=$GOLD"
    echo "HP=$HP MAX_HP=$MAX_HP"
    echo "STR=$STR DEX=$DEX CON=$CON INT=$INT WIS=$WIS CHA=$CHA"
    echo "NEXT=$NEXT"
    echo "=== CONTINUE TO NEXT SCENE ==="
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Continue to Shadow Woods entrance scene
# Generated: 2026-01-31 09:41:36 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
    # Persist state from previous step
    NAME="XertroV"
    CLASS="WARRIOR"
    LEVEL=1
    XP=25
    GOLD=10
    HP=14
    MAX_HP=14
    STR=11
    DEX=8
    CON=12
    INT=8
    WIS=13
    CHA=9
    WEAPON="Longsword"
    INVENTORY=("Longsword" "Leather Armor" "Torch" "Rations x3")
    
    clear
    
    # Scene: Woods Entrance
    cat << 'EOF'

═══════════════════════════════════════════════════════════════
              CHAPTER 2: THE SHADOW WOODS ENTRANCE
═══════════════════════════════════════════════════════════════

The path leads to a wall of ancient, twisted trees.
Mist curls between the gnarled trunks like ghostly fingers.
The air grows cold. Unnatural silence presses in.

        🌲🌲🌲   ⛰️   🌲🌲🌲
       🌲 💀 🌲🌲🌲🌲🌲 💀 🌲
      🌲🌲  ══════════  🌲🌲
       🌲   🚶 YOU 🚶   🌲
            ══════════

As you approach, you notice:
- Fresh tracks leading into the woods (small, child-sized)
- A torn piece of cloth caught on a branch
- Strange glowing mushrooms along the left path
- The faint sound of weeping from deep within

EOF

    CHOICE=$(whiptail --title "⚔️ $NAME the $CLASS | HP: $HP/$MAX_HP | XP: $XP | Gold: $GOLD" \
        --menu "\nThe woods split into two paths. What do you do?\n" 20 72 6 \
        "1" "🔍 Examine the tracks and cloth for clues (WIS check)" \
        "2" "🍄 Follow the glowing mushrooms (left path)" \
        "3" "👂 Follow the sound of weeping (right path)" \
        "4" "🔥 Light your torch before entering" \
        "5" "📦 Check inventory and stats" \
        3>&1 1>&2 2>&3)
    
    case $CHOICE in
        1)
            # Wisdom check
            ROLL=$((RANDOM % 20 + 1))
            WIS_MOD=$(( (WIS - 10) / 2 ))
            TOTAL=$((ROLL + WIS_MOD))
            echo ""
            echo "🎲 Wisdom Check: Rolled $ROLL + $WIS_MOD (WIS mod) = $TOTAL"
            if [ $TOTAL -ge 10 ]; then
                echo "✅ SUCCESS! You notice the tracks show signs of struggle..."
                echo "The children were DRAGGED, not walking. Something large took them."
                echo "You also spot goblin footprints mixed with the children's!"
                echo "+15 XP for keen observation!"
                XP=$((XP + 15))
                CLUE="goblins"
            else
                echo "❌ The tracks are too muddled to read clearly."
                echo "You'll need to proceed carefully."
            fi
            ;;
        2)
            echo ""
            echo "🍄 You decide to follow the glowing mushrooms..."
            echo "Their soft blue light seems almost... inviting."
            NEXT="mushroom_path"
            ;;
        3)
            echo ""
            echo "👂 The weeping grows louder as you push through branches..."
            echo "It sounds like a child! You quicken your pace."
            NEXT="weeping_path"
            ;;
        4)
            echo ""
            echo "🔥 You light your torch. Shadows dance and retreat!"
            echo "The warm light reveals claw marks on nearby trees..."
            echo "+5 XP for caution!"
            XP=$((XP + 5))
            TORCH_LIT=1
            ;;
        5)
            whiptail --title "📦 CHARACTER SHEET" --msgbox "
╔══════════════════════════════════════╗
║  $NAME the $CLASS (Level $LEVEL)
║  XP: $XP / 100 to next level
╠══════════════════════════════════════╣
║  HP: $HP / $MAX_HP    Gold: $GOLD
╠══════════════════════════════════════╣
║  STR: $STR  DEX: $DEX  CON: $CON
║  INT: $INT  WIS: $WIS  CHA: $CHA
╠══════════════════════════════════════╣
║  INVENTORY:
║  • ${INVENTORY[0]}
║  • ${INVENTORY[1]}
║  • ${INVENTORY[2]}
║  • ${INVENTORY[3]}
╚══════════════════════════════════════╝" 20 46
            ;;
    esac
    
    echo ""
    echo "=== CHAPTER 2 STATE ==="
    echo "NAME=$NAME CLASS=$CLASS LEVEL=$LEVEL XP=$XP GOLD=$GOLD"
    echo "HP=$HP MAX_HP=$MAX_HP TORCH_LIT=${TORCH_LIT:-0} CLUE=${CLUE:-none}"
    echo "NEXT=${NEXT:-woods_entrance}"
    echo "=== CONTINUE TO NEXT SCENE ==="
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Continue into the Shadow Woods with torch lit
# Generated: 2026-01-31 09:44:15 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
    # Restore state from previous step
    NAME="XertroV"
    CLASS="WARRIOR"
    LEVEL=1
    XP=30
    GOLD=10
    HP=14
    MAX_HP=14
    TORCH_LIT=1
    
    # Stats
    STR=14
    DEX=10
    CON=12
    INT=8
    WIS=10
    CHA=12
    
    clear
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════
           CHAPTER 3: THE GLOWING MUSHROOM PATH
═══════════════════════════════════════════════════════════════

Your torch casts dancing shadows as you follow the luminescent
mushrooms deeper into the Shadow Woods. The fungi pulse with an
eerie blue-green light, forming a trail into the darkness.

        🌲🔥🌲🌲🌲🌲🌲🌲🌲🌲🌲
       🌲  🍄    🍄    🍄  🌲
      🌲    🍄  🚶  🍄    🌲
       🌲  🍄    🍄    🍄  🌲
        🌲🌲🌲🌲🌲🌲🌲🌲🌲🌲🌲

Suddenly, you hear rustling! A creature emerges from behind
a massive oak - a GOBLIN SCOUT, startled by your torchlight!

          👺 GOBLIN SCOUT
          HP: 8  |  AC: 13
          "Bright light! Burns eyes!"

The goblin reaches for a crude dagger, squinting against
your torch's glow. It seems disoriented by the flames!

EOF

    # Combat encounter menu
    CHOICE=$(whiptail --title "⚔️ $NAME the $CLASS | HP: $HP/$MAX_HP | XP: $XP | Gold: $GOLD" \
        --menu "\nThe goblin is blinded by your torch! What do you do?" 20 74 6 \
        "1" "⚔️  Attack with sword (advantage - goblin is blinded!)" \
        "2" "🗣️  Try to intimidate (CHA check)" \
        "3" "🤝 Offer gold to let you pass (costs 5 gold)" \
        "4" "🏃 Attempt to sneak past while it's blinded (DEX check)" \
        "5" "❓ Demand information about the missing children" \
        3>&1 1>&2 2>&3)
    
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -ne 0 ]; then
        echo "Adventure paused. Farewell, brave warrior!"
        exit 0
    fi
    
    case $CHOICE in
        1)
            echo ""
            echo "⚔️  You swing your sword at the disoriented goblin!"
            # Roll with advantage (2d20 take highest) + STR mod
            ROLL1=$((RANDOM % 20 + 1))
            ROLL2=$((RANDOM % 20 + 1))
            if [ $ROLL1 -gt $ROLL2 ]; then ROLL=$ROLL1; else ROLL=$ROLL2; fi
            STR_MOD=$(( (STR - 10) / 2 ))
            TOTAL=$((ROLL + STR_MOD))
            echo "🎲 Attack roll: [$ROLL1, $ROLL2] → $ROLL + $STR_MOD (STR) = $TOTAL vs AC 13"
            
            if [ $TOTAL -ge 13 ]; then
                DAMAGE=$((RANDOM % 8 + 1 + STR_MOD))
                echo "💥 HIT! You deal $DAMAGE damage!"
                if [ $DAMAGE -ge 8 ]; then
                    echo "☠️  CRITICAL BLOW! The goblin falls instantly!"
                    XP=$((XP + 25))
                    GOLD=$((GOLD + 3))
                    echo "🏆 +25 XP, +3 Gold looted!"
                    GOBLIN_DEFEATED=1
                else
                    echo "🩸 The goblin shrieks and flees into the darkness!"
                    XP=$((XP + 15))
                    echo "🏆 +15 XP for driving off the enemy!"
                    GOBLIN_FLED=1
                fi
            else
                echo "💨 The goblin ducks! It scratches you with its dagger!"
                DMG=$((RANDOM % 4 + 1))
                HP=$((HP - DMG))
                echo "🩸 You take $DMG damage! HP: $HP/$MAX_HP"
                echo "The goblin scurries away into the underbrush..."
                XP=$((XP + 10))
                GOBLIN_FLED=1
            fi
            ;;
        2)
            echo ""
            echo "🗣️  You raise your torch high and ROAR at the goblin!"
            ROLL=$((RANDOM % 20 + 1))
            CHA_MOD=$(( (CHA - 10) / 2 ))
            TOTAL=$((ROLL + CHA_MOD))
            echo "🎲 Intimidation check: $ROLL + $CHA_MOD (CHA) = $TOTAL vs DC 12"
            
            if [ $TOTAL -ge 12 ]; then
                echo "😱 The goblin cowers and drops its weapon!"
                echo "\"No hurt! No hurt! Me tell you things!\""
                echo ""
                echo "📜 The goblin reveals: \"Children taken to spider caves!"
                echo "   Big boss Skrag want them for... trade with dark ones!\""
                XP=$((XP + 30))
                echo "🏆 +30 XP for valuable information!"
                LEARNED_LOCATION=1
            else
                echo "😤 The goblin snarls defiantly and attacks!"
                DMG=$((RANDOM % 4 + 1))
                HP=$((HP - DMG))
                echo "🩸 You take $DMG damage! HP: $HP/$MAX_HP"
                echo "The goblin then flees before you can retaliate..."
                XP=$((XP + 5))
            fi
            ;;
        3)
            if [ $GOLD -ge 5 ]; then
                GOLD=$((GOLD - 5))
                echo ""
                echo "💰 You toss 5 gold coins to the goblin."
                echo "\"Shiny! Shiny! You pass, human!\""
                echo "The goblin scampers away clutching the coins."
                echo "🏆 -5 Gold, but safe passage secured."
            else
                echo ""
                echo "💸 You don't have enough gold!"
                echo "The goblin attacks while you fumble for coins!"
                DMG=$((RANDOM % 4 + 2))
                HP=$((HP - DMG))
                echo "🩸 You take $DMG damage! HP: $HP/$MAX_HP"
            fi
            ;;
        4)
            echo ""
            echo "🏃 You attempt to slip past while the goblin rubs its eyes..."
            ROLL=$((RANDOM % 20 + 1))
            DEX_MOD=$(( (DEX - 10) / 2 ))
            TOTAL=$((ROLL + DEX_MOD))
            echo "🎲 Stealth check: $ROLL + $DEX_MOD (DEX) = $TOTAL vs DC 10"
            
            if [ $TOTAL -ge 10 ]; then
                echo "🥷 You slip silently past the blinded creature!"
                XP=$((XP + 20))
                echo "🏆 +20 XP for clever tactics!"
            else
                echo "💥 You step on a twig! The goblin spots you!"
                DMG=$((RANDOM % 4 + 1))
                HP=$((HP - DMG))
                echo "🩸 It slashes you as you run past! $DMG damage! HP: $HP/$MAX_HP"
                XP=$((XP + 10))
            fi
            ;;
        5)
            echo ""
            echo "❓ \"Where are the children?!\" you demand."
            echo "The goblin's eyes widen with fear... then cunning."
            echo ""
            echo "\"Me know things... but what you give Grubnik?\""
            ROLL=$((RANDOM % 20 + 1))
            WIS_MOD=$(( (WIS - 10) / 2 ))
            echo "🎲 Insight check: $ROLL + $WIS_MOD (WIS) = $((ROLL + WIS_MOD)) vs DC 11"
            
            if [ $((ROLL + WIS_MOD)) -ge 11 ]; then
                echo "👁️  You sense the goblin knows something important!"
                echo "\"Spider caves! North! Big boss Skrag has them!\""
                XP=$((XP + 25))
                echo "🏆 +25 XP for extracting information!"
                LEARNED_LOCATION=1
            else
                echo "🤔 The goblin seems to be lying... or hiding something."
                echo "It uses your distraction to flee!"
                XP=$((XP + 5))
            fi
            ;;
    esac
    
    # Check for death
    if [ $HP -le 0 ]; then
        echo ""
        echo "💀 YOUR VISION FADES..."
        echo "The Shadow Woods claim another victim."
        echo ""
        echo "═══ GAME OVER ═══"
        echo "Final Score: $XP XP | Gold: $GOLD"
        echo "=== GAME_OVER ==="
        exit 0
    fi
    
    sleep 2
    
    echo ""
    echo "=== CHAPTER 3 STATE ==="
    echo "NAME=$NAME CLASS=$CLASS LEVEL=$LEVEL XP=$XP GOLD=$GOLD"
    echo "HP=$HP MAX_HP=$MAX_HP TORCH_LIT=$TORCH_LIT"
    echo "LEARNED_LOCATION=${LEARNED_LOCATION:-0}"
    echo "NEXT=deeper_woods"
    echo "=== CONTINUE TO NEXT SCENE ==="
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Continue adventure - deeper woods encounter after goblin escapes
# Generated: 2026-01-31 09:46:04 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
    # Load state from previous chapter
    NAME="XertroV"
    CLASS="WARRIOR"
    LEVEL=1
    XP=40
    GOLD=10
    HP=10
    MAX_HP=14
    TORCH_LIT=1
    LEARNED_LOCATION=0
    
    # Stats
    STR=2
    DEX=1
    CON=1
    INT=0
    WIS=0
    CHA=-1
    
    clear
    
    # Chapter header
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "           CHAPTER 4: THE DEEPER WOODS"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "The goblin has fled, but left a trail of disturbed foliage."
    echo "You press onward, your torch flickering in the damp air."
    echo "The mushroom path continues, but you notice something new..."
    echo ""
    echo "        🌲🌲🌲🌑🌑🌑🌲🌲🌲"
    echo "       🌲  🍄  🏚️   🍄  🌲"
    echo "      🌲    🚶→ 🚪      🌲"
    echo "       🌲  🍄       🍄  🌲"
    echo "        🌲🌲🌲🌲🌲🌲🌲🌲🌲"
    echo ""
    echo "A dilapidated HUT emerges from the gloom! Its windows are dark,"
    echo "but smoke curls from a crooked chimney. Near the door, you spot"
    echo "a CHILD'S TOY - a small wooden horse, freshly dropped!"
    echo ""
    echo "From inside, you hear muffled voices... and a child's whimper!"
    echo ""
    
    # Show HP status with color based on health
    if [ $HP -lt 5 ]; then
        HP_COLOR="\e[31m"  # Red
    elif [ $HP -lt 10 ]; then
        HP_COLOR="\e[33m"  # Yellow
    else
        HP_COLOR="\e[32m"  # Green
    fi
    
    CHOICE=$(whiptail --title "⚔️ $NAME the $CLASS | HP: $HP/$MAX_HP | XP: $XP | Gold: $GOLD" \
        --menu "You've found the hut! The children might be inside!\n\nWhat do you do?" 20 76 6 \
        "1" "🚪 Kick down the door (STR check - loud entrance!)" \
        "2" "🔍 Peer through a window first (stealth check)" \
        "3" "🔥 Throw your torch onto the thatched roof" \
        "4" "🗣️  Call out to whoever is inside" \
        "5" "🔄 Circle around to find a back entrance (DEX check)" \
        "6" "📖 Examine the toy for clues (WIS check)" \
        3>&1 1>&2 2>&3)
    
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -ne 0 ]; then
        echo "Adventure paused. The hut awaits your return..."
        echo "=== CHAPTER 4 STATE ==="
        echo "NAME=$NAME CLASS=$CLASS LEVEL=$LEVEL XP=$XP GOLD=$GOLD"
        echo "HP=$HP MAX_HP=$MAX_HP TORCH_LIT=$TORCH_LIT"
        echo "NEXT=hut_approach"
        return
    fi
    
    case $CHOICE in
        1)
            echo ""
            echo "💪 You charge at the door with your shoulder!"
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + STR))
            echo "🎲 Strength check: $ROLL + $STR (STR) = $TOTAL vs DC 12"
            
            if [ $TOTAL -ge 12 ]; then
                echo "💥 CRASH! The door splinters open!"
                echo ""
                echo "Inside you see: THREE GOBLINS around a cooking pot,"
                echo "and in the corner - a CAGE with TWO CHILDREN inside!"
                echo ""
                echo "The goblins shriek in surprise! You have the initiative!"
                SURPRISE=1
                NEXT="hut_combat"
            else
                echo "🚫 The door holds! You slam against it painfully."
                echo "🩸 You take 2 damage from the impact! HP: $((HP-2))/$MAX_HP"
                HP=$((HP-2))
                echo ""
                echo "The noise alerts those inside! You hear scrambling..."
                SURPRISE=0
                NEXT="hut_combat_nosurprise"
            fi
            ;;
        2)
            echo ""
            echo "👁️ You creep to the grimy window and peer inside..."
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + DEX))
            echo "🎲 Stealth check: $ROLL + $DEX (DEX) = $TOTAL vs DC 10"
            
            if [ $TOTAL -ge 10 ]; then
                echo "✅ You see clearly without being noticed!"
                echo ""
                echo "Inside: THREE GOBLINS sit around a bubbling cauldron."
                echo "One sharpens a blade. One stirs the pot. One guards a CAGE"
                echo "containing TWO FRIGHTENED CHILDREN - the miller's kids!"
                echo ""
                echo "You also spot: A BACK DOOR, and POTIONS on a shelf!"
                LEARNED_LOCATION=1
                XP=$((XP+10))
                echo "📚 +10 XP for reconnaissance!"
                NEXT="hut_informed"
            else
                echo "⚠️ A floorboard creaks! A goblin looks toward the window!"
                echo "You duck just in time... but they're now on alert."
                NEXT="hut_alert"
            fi
            ;;
        3)
            echo ""
            echo "🔥 A desperate gambit! You hurl your torch at the roof!"
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + DEX))
            echo "🎲 Dexterity (throw): $ROLL + $DEX (DEX) = $TOTAL vs DC 13"
            
            if [ $TOTAL -ge 13 ]; then
                echo "🎯 Direct hit! The dry thatch catches immediately!"
                echo ""
                echo "🔥🔥🔥 FIRE! 🔥🔥🔥"
                echo ""
                echo "Panicked screams erupt from inside! The goblins burst"
                echo "out the front door, coughing and fleeing into the woods!"
                echo ""
                echo "But wait - THE CHILDREN ARE STILL INSIDE!"
                TORCH_LIT=0
                NEXT="burning_hut"
            else
                echo "💨 The torch bounces off and lands in a puddle. Fizzle."
                echo "🔦 Your torch is extinguished! Darkness surrounds you."
                TORCH_LIT=0
                NEXT="hut_dark"
            fi
            ;;
        4)
            echo ""
            echo "📢 'Hello! I know you're in there! Release the children!'"
            echo ""
            echo "Silence... then cackling goblin laughter!"
            echo ""
            echo "A raspy voice calls back:"
            echo "   '👺 Stupid human! Come in, come in!"
            echo "    We make room in pot for YOU too! Hehehehe!'"
            echo ""
            echo "The door creaks open invitingly... it's clearly a trap."
            NEXT="hut_trap"
            ;;
        5)
            echo ""
            echo "🔄 You quietly circle the hut, seeking another way in..."
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + DEX))
            echo "🎲 Dexterity check: $ROLL + $DEX (DEX) = $TOTAL vs DC 11"
            
            if [ $TOTAL -ge 11 ]; then
                echo "✅ You find a loose board at the back!"
                echo ""
                echo "Through the gap you see the cage with two children."
                echo "One child notices you and her eyes widen with hope!"
                echo "You gesture for silence. She nods."
                echo ""
                echo "You could slip in and free them while the goblins"
                echo "are distracted at the front of the hut!"
                XP=$((XP+15))
                echo "📚 +15 XP for tactical positioning!"
                NEXT="hut_stealth_rescue"
            else
                echo "⚠️ SNAP! You step on a twig pile - an alarm!"
                echo "Bells and bones clatter! The goblins are alerted!"
                NEXT="hut_ambush"
            fi
            ;;
        6)
            echo ""
            echo "🔍 You kneel to examine the wooden toy horse..."
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + WIS))
            echo "🎲 Wisdom (insight): $ROLL + $WIS (WIS) = $TOTAL vs DC 8"
            
            if [ $TOTAL -ge 8 ]; then
                echo "✅ The toy is freshly dropped - within the hour!"
                echo ""
                echo "More importantly, you notice SMALL FOOTPRINTS leading"
                echo "not INTO the hut... but AWAY from it, toward a cellar door!"
                echo ""
                echo "Could one child have escaped? Or is it another trap?"
                XP=$((XP+10))
                echo "📚 +10 XP for keen observation!"
                NEXT="cellar_discovery"
            else
                echo "It's just a toy. Worn but well-loved."
                echo "The children must be inside. Time is wasting!"
                NEXT="hut_approach"
            fi
            ;;
    esac
    
    echo ""
    echo "=== CHAPTER 4 STATE ==="
    echo "NAME=$NAME CLASS=$CLASS LEVEL=$LEVEL XP=$XP GOLD=$GOLD"
    echo "HP=$HP MAX_HP=$MAX_HP TORCH_LIT=$TORCH_LIT"
    echo "LEARNED_LOCATION=$LEARNED_LOCATION"
    echo "NEXT=$NEXT"
    echo "=== CONTINUE TO NEXT SCENE ==="
}

script -q -c "step5" /dev/null

# ═══════════════════════════════════════════════════════════════
# STEP 6: Initialize D&D-style text adventure with character creation
# Generated: 2026-01-31 09:46:30 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step6() {
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
    CHAPTER=1
    INVENTORY=("Torch" "Rations")
    
    clear
    
    # Title screen
    echo -e "\033[1;33m"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║  ____  _   _ _   _  ____ _____ ___  _   _ ____                ║
    ║ |  _ \| | | | \ | |/ ___| ____/ _ \| \ | / ___|               ║
    ║ | | | | | | |  \| | |  _|  _|| | | |  \| \___ \               ║
    ║ | |_| | |_| | |\  | |_| | |__| |_| | |\  |___) |              ║
    ║ |____/ \___/|_| \_|\____|_____\___/|_| \_|____/               ║
    ║                                                               ║
    ║              ___  _____   ____   ___   ___  __  __            ║
    ║             / _ \|  ___| |  _ \ / _ \ / _ \|  \/  |           ║
    ║            | | | | |_    | | | | | | | | | | |\/| |           ║
    ║            | |_| |  _|   | |_| | |_| | |_| | |  | |           ║
    ║             \___/|_|     |____/ \___/ \___/|_|  |_|           ║
    ║                                                               ║
    ║           ~ A Text Adventure in the Classic Style ~           ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "\033[0m"
    
    sleep 1
    
    # Character creation - Race selection
    PLAYER_RACE=$(whiptail --title "Character Creation - Race" --menu "\nChoose your race:\n" 18 60 6 \
        "Human" "Versatile and ambitious (+1 to all stats)" \
        "Elf" "Graceful and wise (+2 DEX, +1 INT)" \
        "Dwarf" "Sturdy and resilient (+2 CON, +1 STR)" \
        "Halfling" "Lucky and nimble (+2 DEX, +1 CHA)" \
        "Half-Orc" "Strong and fierce (+2 STR, +1 CON)" \
        "Tiefling" "Cunning and charismatic (+2 CHA, +1 INT)" \
        3>&1 1>&2 2>&3)
    
    # Class selection
    PLAYER_CLASS=$(whiptail --title "Character Creation - Class" --menu "\nChoose your class:\n" 18 60 6 \
        "Fighter" "Master of martial combat (d10 HP)" \
        "Wizard" "Wielder of arcane magic (d6 HP)" \
        "Rogue" "Skilled in stealth and trickery (d8 HP)" \
        "Cleric" "Divine spellcaster and healer (d8 HP)" \
        "Ranger" "Hunter of the wilderness (d10 HP)" \
        "Barbarian" "Primal warrior of rage (d12 HP)" \
        3>&1 1>&2 2>&3)
    
    # Name input
    PLAYER_NAME=$(whiptail --title "Character Creation - Name" --inputbox "\nEnter your character's name:" 10 50 "Adventurer" 3>&1 1>&2 2>&3)
    
    # Roll stats (4d6 drop lowest style)
    roll_stat() {
        local rolls=()
        for i in {1..4}; do
            rolls+=($((RANDOM % 6 + 1)))
        done
        IFS=$'\n' sorted=($(sort -n <<<"${rolls[*]}")); unset IFS
        echo $(( sorted[1] + sorted[2] + sorted[3] ))
    }
    
    STR=$(roll_stat)
    DEX=$(roll_stat)
    CON=$(roll_stat)
    INT=$(roll_stat)
    WIS=$(roll_stat)
    CHA=$(roll_stat)
    
    # Apply racial bonuses
    case $PLAYER_RACE in
        "Human") ((STR++)); ((DEX++)); ((CON++)); ((INT++)); ((WIS++)); ((CHA++)) ;;
        "Elf") ((DEX+=2)); ((INT++)) ;;
        "Dwarf") ((CON+=2)); ((STR++)) ;;
        "Halfling") ((DEX+=2)); ((CHA++)) ;;
        "Half-Orc") ((STR+=2)); ((CON++)) ;;
        "Tiefling") ((CHA+=2)); ((INT++)) ;;
    esac
    
    # Calculate HP based on class
    case $PLAYER_CLASS in
        "Fighter") MAX_HP=$((10 + (CON - 10) / 2)) ;;
        "Wizard") MAX_HP=$((6 + (CON - 10) / 2)) ;;
        "Rogue") MAX_HP=$((8 + (CON - 10) / 2)) ;;
        "Cleric") MAX_HP=$((8 + (CON - 10) / 2)) ;;
        "Ranger") MAX_HP=$((10 + (CON - 10) / 2)) ;;
        "Barbarian") MAX_HP=$((12 + (CON - 10) / 2)) ;;
    esac
    [[ $MAX_HP -lt 1 ]] && MAX_HP=1
    HP=$MAX_HP
    
    # Output character sheet for next step
    echo "=== CHARACTER CREATED ==="
    echo "NAME: $PLAYER_NAME"
    echo "RACE: $PLAYER_RACE"
    echo "CLASS: $PLAYER_CLASS"
    echo "LEVEL: $LEVEL"
    echo "HP: $HP/$MAX_HP"
    echo "STR: $STR DEX: $DEX CON: $CON"
    echo "INT: $INT WIS: $WIS CHA: $CHA"
    echo "GOLD: $GOLD"
    echo "XP: $XP"
    echo "INVENTORY: ${INVENTORY[*]}"
    echo "CHAPTER: $CHAPTER"
    echo "=== READY FOR ADVENTURE ==="
}
step6

# ═══════════════════════════════════════════════════════════════
# STEP 7: Start Chapter 1 - The Tavern adventure scene
# Generated: 2026-01-31 09:47:36 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step7() {
    # Load character state
    NAME="Adventurer"
    RACE="Human"
    CLASS="Barbarian"
    LEVEL=1
    HP=13
    MAX_HP=13
    STR=13
    DEX=14
    CON=13
    INT=11
    WIS=17
    CHA=14
    GOLD=10
    XP=0
    CHAPTER=1
    
    clear
    
    # Chapter 1 intro
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                      CHAPTER 1                                ║
    ║              THE RUSTY FLAGON TAVERN                          ║
    ╚═══════════════════════════════════════════════════════════════╝

EOF
    
    echo -e "\033[1;33m"
    cat << 'EOF'
    The evening rain patters against the weathered windows of the Rusty
    Flagon tavern. You push through the heavy oak door, your clothes
    damp from the storm outside. The warmth of the hearth and the smell
    of roasting meat welcome you.
    
    As you survey the room, you notice:
    
    • A HOODED FIGURE sits alone in a dark corner, nursing a drink
    • The BARKEEP polishes glasses, eyeing you curiously  
    • A group of ROWDY MERCENARIES laugh loudly at a table
    • A NOTICE BOARD hangs near the entrance
EOF
    echo -e "\033[0m"
    
    echo ""
    echo -e "\033[1;36m═══ $NAME the $RACE $CLASS | HP: $HP/$MAX_HP | Gold: $GOLD ═══\033[0m"
    echo ""
    
    ACTION=$(whiptail --title "The Rusty Flagon" --menu "What do you do?" 18 60 6 \
        "1" "Approach the hooded figure" \
        "2" "Talk to the barkeep" \
        "3" "Join the mercenaries" \
        "4" "Check the notice board" \
        "5" "Find a quiet table and rest" \
        3>&1 1>&2 2>&3)
    
    echo "CHAPTER=1"
    echo "ACTION_CHOSEN=$ACTION"
    echo "HP=$HP"
    echo "GOLD=$GOLD"
    echo "XP=$XP"
}
step7

# ═══════════════════════════════════════════════════════════════
# STEP 8: Continue adventure - player talks to barkeep
# Generated: 2026-01-31 09:48:34 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step8() {
    # Persist state from previous step
    CHAPTER=1
    HP=13
    MAX_HP=13
    GOLD=10
    XP=0
    NAME="Adventurer"
    CLASS="Barbarian"
    RACE="Human"
    
    clear
    
    # Display scene
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    TALKING TO THE BARKEEP                     ║
    ╚═══════════════════════════════════════════════════════════════╝

    You approach the bar, water dripping from your cloak onto the worn
    wooden floor. The barkeep, a stout dwarf with a magnificent braided
    beard, sets down his glass and regards you with keen eyes.
    
    "Evenin' stranger. Name's Thorin Ironbelly. What brings ye to the
    Rusty Flagon on such a miserable night?"
    
    He leans in conspiratorially:
    
    "If ye be lookin' for work, there's trouble brewin'. Goblins been
    raidin' the trade caravans on the north road. The merchant guild's
    offerin' 50 GOLD to anyone brave - or foolish - enough to clear
    'em out."
    
    He slides a foaming mug toward you.
    
    "First drink's on the house for anyone willin' to help."

EOF
    
    echo "═══ $NAME the $RACE $CLASS | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP ═══"
    echo ""
    
    # Player choice
    CHOICE=$(whiptail --title "The Barkeep's Offer" --menu "How do you respond?" 18 60 6 \
        "1" "Accept the quest to hunt goblins (+Quest)" \
        "2" "Ask for more information about the goblins" \
        "3" "Buy a meal (2 gold, restore HP)" \
        "4" "Ask about the hooded figure" \
        "5" "Return to looking around the tavern" \
        3>&1 1>&2 2>&3)
    
    # Output state for next iteration
    echo "CHAPTER=$CHAPTER"
    echo "ACTION_CHOSEN=$CHOICE"
    echo "HP=$HP"
    echo "MAX_HP=$MAX_HP"
    echo "GOLD=$GOLD"
    echo "XP=$XP"
    echo "LOCATION=barkeep"
    echo "QUEST_GOBLINS=offered"
}
step8

# ═══════════════════════════════════════════════════════════════
# STEP 9: Continue adventure - player asks about hooded figure
# Generated: 2026-01-31 09:49:53 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step9() {
    clear
    
    # Display scene header
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                   THE MYSTERIOUS STRANGER                     ║
    ╚═══════════════════════════════════════════════════════════════╝

    You lower your voice and lean closer to the barkeep.
    
    "That hooded figure in the corner... who is that?"
    
    Thorin's eyes dart nervously to the shadowy booth, then back to you.
    His voice drops to a whisper.
    
    "That there's a dangerous question, friend. She arrived three nights
    ago, pays in strange silver coins, and speaks to no one. But..."
    
    He glances around and continues even quieter:
    
    "I've seen the symbol on her cloak when it shifted. A black serpent
    eating its own tail. That's the mark of the SHADOW COVENANT - 
    assassins, spies, and worse. Whatever business brought her here,
    it ain't good for anyone."
    
    He straightens up abruptly as the figure seems to look your way.
    
    "Best not stare too long, stranger. Some secrets are better left
    buried."

EOF

    echo "═══ Adventurer the Human Barbarian | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP ═══"
    echo ""
    
    # Player choice
    CHOICE=$(whiptail --title "A Dangerous Interest" --menu "What do you do?" 18 60 6 \
        "1" "Approach the hooded figure directly" \
        "2" "Try to secretly observe her (Stealth check)" \
        "3" "Accept the goblin quest to change subject" \
        "4" "Buy a drink and wait to see what happens" \
        "5" "Leave the tavern entirely" \
        3>&1 1>&2 2>&3)
    
    ACTION_CHOSEN=$CHOICE
    SHADOW_COVENANT_KNOWN=true
    
    # Output state for next iteration
    echo "CHAPTER=$CHAPTER"
    echo "ACTION_CHOSEN=$ACTION_CHOSEN"
    echo "HP=$HP"
    echo "MAX_HP=$MAX_HP"
    echo "GOLD=$GOLD"
    echo "XP=$XP"
    echo "LOCATION=barkeep"
    echo "QUEST_GOBLINS=$QUEST_GOBLINS"
    echo "SHADOW_COVENANT_KNOWN=$SHADOW_COVENANT_KNOWN"
}
step9

# ═══════════════════════════════════════════════════════════════
# STEP 10: Stealth check to secretly observe the hooded figure
# Generated: 2026-01-31 09:50:23 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step10() {
    clear
    
    # Stealth check - roll d20 + dexterity modifier (barbarian has low dex, +1)
    ROLL=$((RANDOM % 20 + 1))
    DEX_MOD=1
    STEALTH_TOTAL=$((ROLL + DEX_MOD))
    DC=14
    
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                     STEALTH CHECK                             ║
    ╚═══════════════════════════════════════════════════════════════╝

EOF
    
    echo "    Rolling for Stealth..."
    sleep 1
    echo ""
    echo "    🎲 d20 roll: $ROLL"
    echo "    📊 Dexterity modifier: +$DEX_MOD"
    echo "    ═══════════════════"
    echo "    Total: $STEALTH_TOTAL vs DC $DC"
    echo ""
    sleep 1
    
    if [ $STEALTH_TOTAL -ge $DC ]; then
        STEALTH_SUCCESS=true
        echo "    ✓ SUCCESS! You blend into the shadows unnoticed."
        cat << 'EOF'

    You casually move to a darker corner of the tavern, pretending to
    study a faded map on the wall. From here, you can observe without
    being obvious.
    
    The hooded figure pulls out a small vial of glowing purple liquid
    and places it on the table. She seems to be waiting for someone.
    
    Then you notice it - a second figure enters through a back door.
    A well-dressed man with a signet ring bearing a noble crest.
    They exchange hushed words and a leather pouch changes hands.
    
    You've witnessed what appears to be a secret transaction between
    the Shadow Covenant and local nobility!
    
    [NEW QUEST AVAILABLE: The Noble's Secret]
    
EOF
        QUEST_NOBLE=true
        XP=$((XP + 25))
        echo "    ⭐ +25 XP earned for successful observation!"
    else
        STEALTH_SUCCESS=false
        echo "    ✗ FAILED! You knock over a tankard while repositioning."
        cat << 'EOF'

    CLANG! The metal cup clatters across the floor, and every eye
    in the tavern turns to you - including the cold gaze beneath
    that dark hood.
    
    The figure rises slowly. In a voice like silk over steel, she
    speaks directly to you:
    
    "Curious one... curiosity has a price. Perhaps we should discuss
    your... interest... in my affairs. Outside. Now."
    
    Her hand rests meaningfully on a dagger at her belt.
    
EOF
        CONFRONTATION=true
    fi
    
    echo ""
    echo "═══ Adventurer the Human Barbarian | HP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP ═══"
    echo ""
    
    if [ "$STEALTH_SUCCESS" = true ]; then
        CHOICE=$(whiptail --title "Information Gathered" --menu "What do you do with this knowledge?" 18 65 5 \
            "1" "Follow the nobleman when he leaves" \
            "2" "Approach the hooded figure now that you have leverage" \
            "3" "Report to the town guard about the Shadow Covenant" \
            "4" "Return to the barkeep and ask about the nobleman" \
            "5" "Mind your own business - take the goblin quest" \
            3>&1 1>&2 2>&3)
    else
        CHOICE=$(whiptail --title "Confrontation!" --menu "The assassin demands you step outside..." 16 65 4 \
            "1" "Agree to meet her outside (dangerous!)" \
            "2" "Refuse and prepare for a fight" \
            "3" "Try to talk your way out (Charisma check)" \
            "4" "Flee the tavern immediately" \
            3>&1 1>&2 2>&3)
    fi
    
    echo "CHAPTER=stealth_result"
    echo "ACTION_CHOSEN=$CHOICE"
    echo "HP=$HP"
    echo "MAX_HP=$MAX_HP"
    echo "GOLD=$GOLD"
    echo "XP=$XP"
    echo "STEALTH_SUCCESS=$STEALTH_SUCCESS"
    echo "QUEST_NOBLE=${QUEST_NOBLE:-false}"
    echo "CONFRONTATION=${CONFRONTATION:-false}"
}
step10
