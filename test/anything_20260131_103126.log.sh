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
# STEP 1: Initialize D&D text adventure with character creation
# Generated: 2026-01-31 10:21:29 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    clear
    
    # Character stats (global for persistence)
    declare -g HP=20
    declare -g MAX_HP=20
    declare -g STRENGTH=10
    declare -g DEXTERITY=10
    declare -g INTELLIGENCE=10
    declare -g GOLD=10
    declare -g LEVEL=1
    declare -g XP=0
    declare -g CHAPTER=1
    declare -g -a INVENTORY=("rusty sword" "leather armor" "healing potion")
    
    echo "═══════════════════════════════════════════════════════════════"
    echo "          TALES OF THE FORGOTTEN REALM - Chapter 1"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "You awaken in a damp, dark dungeon cell. The stone walls are"
    echo "covered with moss, and a single torch flickers in the corridor"
    echo "beyond the iron bars."
    echo ""
    echo "Your head throbs. How did you get here?"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "CHARACTER STATUS:"
    echo "═══════════════════════════════════════════════════════════════"
    echo "HP: $HP/$MAX_HP | Level: $LEVEL | XP: $XP/100"
    echo "STR: $STRENGTH | DEX: $DEXTERITY | INT: $INTELLIGENCE"
    echo "Gold: $GOLD"
    echo "Inventory: ${INVENTORY[*]}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "You notice:"
    echo "  [1] The cell door is slightly ajar"
    echo "  [2] A loose stone in the wall"
    echo "  [3] Scratch marks on the floor leading to the corner"
    echo ""
    echo -n "What do you do? (1/2/3): "
    read -r CHOICE
    
    case $CHOICE in
        1)
            echo ""
            echo "You push the cell door. It creaks open! Freedom beckons..."
            echo "You step into a torch-lit corridor. To your left: stairs up."
            echo "To your right: a dark passage with the sound of dripping water."
            echo ""
            declare -g LOCATION="corridor"
            ;;
        2)
            echo ""
            echo "You pry at the loose stone. Behind it: a small alcove!"
            echo "You find: [+5 GOLD] and a [mysterious key]"
            declare -g GOLD=$((GOLD + 5))
            INVENTORY+=("mysterious key")
            echo "The cell door remains ajar. You can leave now."
            declare -g LOCATION="corridor"
            ;;
        3)
            echo ""
            echo "Following the scratches, you find a hidden message carved into stone:"
            echo "'The guard drinks at midnight. The key is his weakness.'"
            echo "[+2 INTELLIGENCE for your perception!]"
            declare -g INTELLIGENCE=$((INTELLIGENCE + 2))
            declare -g LOCATION="corridor"
            ;;
        *)
            echo ""
            echo "You hesitate, uncertain. The torch flickers ominously..."
            declare -g LOCATION="corridor"
            ;;
    esac
    
    echo ""
    echo "CHAPTER 1 COMPLETE - Hero Status: HP=$HP/$MAX_HP | Gold=$GOLD | Location=$LOCATION"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Chapter 2 - Corridor exploration and first combat
# Generated: 2026-01-31 10:22:21 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
          TALES OF THE FORGOTTEN REALM - Chapter 2
═══════════════════════════════════════════════════════════════

You step into the torch-lit corridor, gripping your rusty sword.
The mysterious key feels warm in your pocket.

To your left, you hear the shuffling of feet. To your right,
stone stairs descend into darkness. Ahead, a locked wooden door.

═══════════════════════════════════════════════════════════════
CHARACTER STATUS:
═══════════════════════════════════════════════════════════════
HP: 20/20 | Level: 1 | XP: 0/100
STR: 10 | DEX: 10 | INT: 10
Gold: 15
Inventory: rusty sword, leather armor, healing potion, mysterious key
═══════════════════════════════════════════════════════════════

You can:
  [1] Investigate the shuffling sounds (left)
  [2] Descend the dark stairs (right)
  [3] Try the mysterious key on the wooden door (ahead)

EOF
    read -p "What do you do? (1/2/3): " choice
    
    echo
    case $choice in
        1)
            echo "You creep toward the shuffling sound..."
            sleep 1
            echo
            echo "═══════════════════════════════════════════════════════════════"
            echo "                    ⚔️  COMBAT ENCOUNTER  ⚔️"
            echo "═══════════════════════════════════════════════════════════════"
            echo "A GIANT RAT lunges at you! [Enemy HP: 8]"
            echo
            
            PLAYER_HP=20
            ENEMY_HP=8
            COMBAT_XP=25
            
            while [ $PLAYER_HP -gt 0 ] && [ $ENEMY_HP -gt 0 ]; do
                echo "Your HP: $PLAYER_HP | Rat HP: $ENEMY_HP"
                echo "  [1] Attack with sword (1d6+2 damage)"
                echo "  [2] Use healing potion (restore 10 HP)"
                read -p "Action: " action
                
                case $action in
                    1)
                        DAMAGE=$((RANDOM % 6 + 3))
                        ENEMY_HP=$((ENEMY_HP - DAMAGE))
                        echo "⚔️  You strike for $DAMAGE damage!"
                        [ $ENEMY_HP -gt 0 ] && echo "The rat has $ENEMY_HP HP remaining" || echo "The rat is defeated!"
                        ;;
                    2)
                        PLAYER_HP=$((PLAYER_HP + 10))
                        [ $PLAYER_HP -gt 20 ] && PLAYER_HP=20
                        echo "🧪 You drink the potion. HP restored to $PLAYER_HP"
                        echo "Inventory: rusty sword, leather armor, mysterious key"
                        ;;
                esac
                
                if [ $ENEMY_HP -gt 0 ]; then
                    RAT_DAMAGE=$((RANDOM % 4 + 1))
                    PLAYER_HP=$((PLAYER_HP - RAT_DAMAGE))
                    echo "🐀 The rat bites you for $RAT_DAMAGE damage!"
                    echo
                fi
            done
            
            if [ $PLAYER_HP -gt 0 ]; then
                echo "═══════════════════════════════════════════════════════════════"
                echo "                      ⭐ VICTORY! ⭐"
                echo "═══════════════════════════════════════════════════════════════"
                echo "Gained: +25 XP, +8 Gold, [rat pelt]"
                echo
                echo "CHAPTER 2 COMPLETE - Status: HP=$PLAYER_HP/20 | Gold=23 | XP=25/100 | Location=corridor_cleared"
            else
                echo "═══════════════════════════════════════════════════════════════"
                echo "                    💀 DEFEAT 💀"
                echo "═══════════════════════════════════════════════════════════════"
                echo "The rat overcomes you. Your vision fades..."
                echo "GAME OVER - Try again!"
            fi
            ;;
        2)
            echo "You carefully descend the dark stairs, feeling along the wall..."
            sleep 1
            echo
            echo "The stairs lead to an underground chamber filled with glowing"
            echo "mushrooms. A treasure chest sits in the center!"
            echo
            echo "Opening the chest..."
            sleep 1
            echo "You find: [+20 GOLD], [iron dagger], [scroll of fireball]"
            echo
            echo "CHAPTER 2 COMPLETE - Status: HP=20/20 | Gold=35 | Items=+2 | Location=mushroom_chamber"
            ;;
        3)
            echo "You insert the mysterious key into the lock..."
            sleep 1
            echo "*CLICK*"
            echo
            echo "The door swings open, revealing a study filled with ancient books."
            echo "An old wizard looks up from his desk."
            echo
            echo "WIZARD: 'Ah! You found my spare key. Here, take this gift.'"
            echo
            echo "Received: [+30 XP], [staff of wisdom], [INT +2]"
            echo
            echo "CHAPTER 2 COMPLETE - Status: HP=20/20 | Gold=15 | INT=12 | XP=30/100 | Location=wizard_study"
            ;;
        *)
            echo "Invalid choice. You stand still, contemplating..."
            echo "CHAPTER 2 INCOMPLETE - Status: HP=20/20 | Gold=15 | Location=corridor"
            ;;
    esac
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Chapter 3 - Explore the cleared corridor and discover what lies ahead
# Generated: 2026-01-31 10:24:15 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
    # Persistent state from Chapter 2
    HP=19
    MAX_HP=20
    LEVEL=1
    XP=25
    XP_NEXT=100
    STR=10
    DEX=10
    INT=10
    GOLD=23
    INVENTORY=("rusty sword" "leather armor" "healing potion" "mysterious key" "rat pelt")
    LOCATION="corridor_cleared"
    
    clear
    
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
          TALES OF THE FORGOTTEN REALM - Chapter 3
═══════════════════════════════════════════════════════════════

With the rat defeated, you search the alcove and find a small
wooden chest hidden behind loose stones. Inside: 12 gold pieces
and a faintly glowing amber vial labeled "Elixir of Might"
(+2 STR for 3 encounters).

The corridor opens into a three-way junction:
  LEFT: Heavy iron door with strange runes (locked)
  CENTER: Continuation of the main passage, torch-lit
  RIGHT: Narrow passage, cold draft, sounds of dripping water

═══════════════════════════════════════════════════════════════
CHARACTER STATUS:
═══════════════════════════════════════════════════════════════
EOF
    
    GOLD=$((GOLD + 12))
    INVENTORY+=("Elixir of Might (+2 STR)")
    
    echo "HP: $HP/$MAX_HP | Level: $LEVEL | XP: $XP/$XP_NEXT"
    echo "STR: $STR | DEX: $DEX | INT: $INT"
    echo "Gold: $GOLD"
    echo -n "Inventory: "
    printf "%s, " "${INVENTORY[@]}" | sed 's/, $/\n/'
    
    cat << 'EOF'
═══════════════════════════════════════════════════════════════

You can:
  [1] Examine the runic iron door (left) - requires INT check
  [2] Follow the main torch-lit passage (center)
  [3] Venture into the cold, wet passage (right)
  [4] Use Elixir of Might before choosing
  [5] Check your map and rest (restore 5 HP, costs 1 turn)

EOF
    
    read -p "What do you do? (1/2/3/4/5): " CHOICE
    echo
    
    case $CHOICE in
        1)
            echo "You approach the runic door and study the symbols..."
            echo "═══════════════════════════════════════════════════════════════"
            echo "                    🎲 INTELLIGENCE CHECK 🎲"
            echo "═══════════════════════════════════════════════════════════════"
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + INT))
            echo "You roll: $ROLL + INT($INT) = $TOTAL (Need 15+)"
            
            if [ $TOTAL -ge 15 ]; then
                echo "✅ SUCCESS! You decipher the runes:"
                echo "   'Only those of noble blood or clever mind may pass.'"
                echo "   'Speak the word AETHERIA to unlock.'"
                echo
                read -p "Do you speak the word? (y/n): " SPEAK
                if [[ $SPEAK == "y" ]]; then
                    echo
                    echo "🔓 The door rumbles open, revealing a treasure chamber!"
                    echo "   Inside: Enchanted Steel Sword (+3 damage)"
                    echo "           Scroll of Fireball (1d20 damage, 1 use)"
                    echo "           50 Gold Pieces"
                    echo
                    INVENTORY=("${INVENTORY[@]/rusty sword/enchanted steel sword (+3)}")
                    INVENTORY+=("Scroll of Fireball")
                    GOLD=$((GOLD + 50))
                    XP=$((XP + 50))
                    echo "⭐ Gained: +50 XP, +50 Gold"
                else
                    echo "You step back from the door cautiously."
                fi
            else
                echo "❌ FAILED. The runes remain indecipherable."
                echo "   Perhaps you'll understand them later..."
            fi
            ;;
        2)
            echo "You follow the torch-lit passage deeper into the dungeon..."
            echo "The air grows warmer. You hear distant chanting."
            echo "This path leads to the Chamber of Trials."
            XP=$((XP + 10))
            echo "⭐ Gained: +10 XP (exploration)"
            ;;
        3)
            echo "You venture into the cold passage. Water drips from above."
            echo "═══════════════════════════════════════════════════════════════"
            echo "                    🎲 DEXTERITY CHECK 🎲"
            echo "═══════════════════════════════════════════════════════════════"
            ROLL=$((RANDOM % 20 + 1))
            TOTAL=$((ROLL + DEX))
            echo "You roll: $ROLL + DEX($DEX) = $TOTAL (Need 12+)"
            
            if [ $TOTAL -ge 12 ]; then
                echo "✅ SUCCESS! You navigate the slippery stones carefully."
                echo "   You find a hidden alcove with a Potion of Agility (+2 DEX)"
                INVENTORY+=("Potion of Agility (+2 DEX)")
                XP=$((XP + 15))
                echo "⭐ Gained: +15 XP"
            else
                echo "❌ FAILED! You slip on the wet stones!"
                DAMAGE=$((RANDOM % 4 + 1))
                HP=$((HP - DAMAGE))
                echo "💥 You take $DAMAGE damage from the fall."
            fi
            ;;
        4)
            echo "You drink the glowing amber elixir!"
            echo "⚡ Your muscles surge with power! STR +2 for next 3 encounters"
            STR=$((STR + 2))
            INVENTORY=("${INVENTORY[@]/Elixir of Might (+2 STR)/}")
            BUFF_TURNS=3
            ;;
        5)
            echo "You rest briefly, consulting your crude map and bandaging wounds..."
            HP=$((HP + 5))
            [ $HP -gt $MAX_HP ] && HP=$MAX_HP
            echo "❤️  Restored 5 HP. Current HP: $HP/$MAX_HP"
            ;;
    esac
    
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "CHAPTER 3 COMPLETE - Status: HP=$HP/$MAX_HP | Gold=$GOLD | XP=$XP/$XP_NEXT | STR=$STR"
    echo "Next: The path deepens... greater challenges await!"
    echo "═══════════════════════════════════════════════════════════════"
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Chapter 4 - Exploring deeper into the dungeon
# Generated: 2026-01-31 10:28:35 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
    # Persistent game state
    HP=19
    MAX_HP=20
    LEVEL=1
    XP=75
    XP_NEXT=100
    STR=10
    DEX=10
    INT=10
    GOLD=85
    INVENTORY=("Enchanted Steel Sword (+3 dmg)" "leather armor" "healing potion" "mysterious key" "rat pelt" "Elixir of Might (+2 STR)" "Scroll of Fireball (1d20 dmg)")
    
    clear
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
          TALES OF THE FORGOTTEN REALM - Chapter 4
═══════════════════════════════════════════════════════════════

Armed with your new enchanted blade, you venture deeper into
the dungeon. The main torch-lit corridor slopes downward,
the air growing thick with an ancient, musty scent.

After descending for several minutes, you hear footsteps ahead.
Three GOBLIN RAIDERS emerge from the shadows, wielding crude
weapons and hissing in their guttural tongue!

💀 COMBAT ENCOUNTER 💀
   Goblin Raider #1 (HP: 12)
   Goblin Raider #2 (HP: 12)
   Goblin Raider #3 (HP: 12)

═══════════════════════════════════════════════════════════════
CHARACTER STATUS:
═══════════════════════════════════════════════════════════════
EOF
    echo "HP: $HP/$MAX_HP | Level: $LEVEL | XP: $XP/$XP_NEXT"
    echo "STR: $STR | DEX: $DEX | INT: $INT"
    echo "Gold: $GOLD"
    echo -n "Inventory: "
    printf '%s, ' "${INVENTORY[@]}" | sed 's/, $/\n/'
    cat << 'EOF'
═══════════════════════════════════════════════════════════════

COMBAT OPTIONS:
  [1] Attack with Enchanted Sword (1d8+3+STR damage)
  [2] Use Fireball Scroll (1d20 damage to ALL goblins, consume scroll)
  [3] Drink Elixir of Might (+2 STR for this combat)
  [4] Attempt to flee (DEX check, may take damage)

What do you do? (1/2/3/4): 
EOF
    read -r choice
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    
    case $choice in
        1)
            # Normal attack
            echo "                    ⚔️  ATTACK ⚔️"
            echo "═══════════════════════════════════════════════════════════════════"
            dmg=$((RANDOM % 8 + 1 + 3 + STR))
            echo "You slash with your Enchanted Sword! Roll: 1d8+3+STR = $dmg damage"
            echo "🗡️  Goblin Raider #1 takes $dmg damage!"
            
            g1_hp=$((12 - dmg))
            if [ $g1_hp -le 0 ]; then
                echo "💀 Goblin Raider #1 is slain!"
                echo ""
                echo "The remaining goblins attack!"
                g_dmg1=$((RANDOM % 6 + 1))
                g_dmg2=$((RANDOM % 6 + 1))
                total_dmg=$((g_dmg1 + g_dmg2))
                HP=$((HP - total_dmg))
                echo "🗡️  Goblin #2 hits you for $g_dmg1 damage!"
                echo "🗡️  Goblin #3 hits you for $g_dmg2 damage!"
                echo "💔 You take $total_dmg total damage! HP: $HP/$MAX_HP"
            else
                echo "Goblin #1 HP remaining: $g1_hp/12"
                echo ""
                echo "All three goblins counterattack!"
                g_dmg1=$((RANDOM % 6 + 1))
                g_dmg2=$((RANDOM % 6 + 1))
                g_dmg3=$((RANDOM % 6 + 1))
                total_dmg=$((g_dmg1 + g_dmg2 + g_dmg3))
                HP=$((HP - total_dmg))
                echo "💔 You take $total_dmg total damage! HP: $HP/$MAX_HP"
            fi
            ;;
        2)
            # Fireball
            echo "            🔥🔥🔥 FIREBALL SCROLL 🔥🔥🔥"
            echo "═══════════════════════════════════════════════════════════════════"
            dmg=$((RANDOM % 20 + 1))
            echo "You unleash the ancient magic! Roll: 1d20 = $dmg damage"
            echo "🔥 A massive fireball engulfs all three goblins!"
            echo ""
            echo "💀 All goblins are incinerated instantly!"
            echo ""
            echo "⭐ Combat Victory! Gained +60 XP, +25 Gold"
            GOLD=$((GOLD + 25))
            XP=$((XP + 60))
            
            if [ $XP -ge $XP_NEXT ]; then
                echo ""
                echo "✨✨✨ LEVEL UP! ✨✨✨"
                LEVEL=$((LEVEL + 1))
                MAX_HP=$((MAX_HP + 5))
                HP=$((HP + 5))
                STR=$((STR + 1))
                DEX=$((DEX + 1))
                INT=$((INT + 1))
                XP=$((XP - XP_NEXT))
                XP_NEXT=$((XP_NEXT + 50))
                echo "Now Level $LEVEL! HP +5, All stats +1"
                echo "HP: $HP/$MAX_HP | STR: $STR | DEX: $DEX | INT: $INT"
            fi
            ;;
        3)
            echo "You drink the Elixir of Might! STR +2 for this combat!"
            echo "(Combat continues...)"
            ;;
        4)
            echo "                    🏃 FLEE ATTEMPT 🏃"
            echo "═══════════════════════════════════════════════════════════════════"
            flee_roll=$((RANDOM % 20 + 1 + DEX))
            echo "DEX check: $flee_roll (need 15+)"
            if [ $flee_roll -ge 15 ]; then
                echo "✅ You successfully escape!"
            else
                echo "❌ The goblins catch you! You take damage while fleeing."
                dmg=$((RANDOM % 12 + 3))
                HP=$((HP - dmg))
                echo "💔 You take $dmg damage! HP: $HP/$MAX_HP"
            fi
            ;;
    esac
    
    echo "═══════════════════════════════════════════════════════════════════"
    echo "CHAPTER 4 STATUS: HP=$HP/$MAX_HP | Gold=$GOLD | XP=$XP/$XP_NEXT | Level=$LEVEL"
    echo "The dungeon grows darker ahead... what horrors await?"
    echo "═══════════════════════════════════════════════════════════════════"
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Continue combat round 2 against remaining goblins
# Generated: 2026-01-31 10:29:51 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
    # Combat state from previous turn
    HP=11
    MAX_HP=20
    LEVEL=1
    XP=75
    GOLD=85
    STR=10
    DEX=10
    INT=10
    
    # Enemy state
    GOBLIN2_HP=12
    GOBLIN3_HP=12
    
    script -q -c "cat <<'COMBAT_EOF'
═══════════════════════════════════════════════════════════════
          TALES OF THE FORGOTTEN REALM - Chapter 4
═══════════════════════════════════════════════════════════════

COMBAT CONTINUES!
   Goblin Raider #2 (HP: $GOBLIN2_HP)
   Goblin Raider #3 (HP: $GOBLIN3_HP)

═══════════════════════════════════════════════════════════════
CHARACTER STATUS:
═══════════════════════════════════════════════════════════════
HP: $HP/$MAX_HP | Level: $LEVEL | XP: $XP/100
STR: $STR | DEX: $DEX | INT: $INT
Gold: $GOLD
Inventory: Enchanted Steel Sword (+3 dmg), leather armor, healing potion, mysterious key, rat pelt, Elixir of Might (+2 STR), Scroll of Fireball (1d20 dmg)
═══════════════════════════════════════════════════════════════

COMBAT OPTIONS:
  [1] Attack with Enchanted Sword (1d8+3+STR damage)
  [2] Use Fireball Scroll (1d20 damage to ALL goblins, consume scroll)
  [3] Drink Healing Potion (restore 2d8 HP)
  [4] Drink Elixir of Might (+2 STR for this combat)
  [5] Attempt to flee (DEX check, may take damage)

What do you do? (1-5): 
COMBAT_EOF
read -p '' CHOICE

case \$CHOICE in
    1)
        PLAYER_DMG=\$((RANDOM % 8 + 1 + 3 + STR))
        echo
        echo \"═══════════════════════════════════════════════════════════════════\"
        echo \"                    ⚔️  ATTACK ROUND 2 ⚔️\"
        echo \"═══════════════════════════════════════════════════════════════════\"
        echo \"You slash with your Enchanted Sword! Roll: 1d8+3+STR = \$PLAYER_DMG damage\"
        GOBLIN2_HP=\$((GOBLIN2_HP - PLAYER_DMG))
        if [ \$GOBLIN2_HP -le 0 ]; then
            echo \"🗡️  Goblin Raider #2 takes \$PLAYER_DMG damage!\"
            echo \"💀 Goblin Raider #2 is slain!\"
            XP=\$((XP + 15))
            GOLD=\$((GOLD + 8))
            echo \"💰 +8 gold! 🌟 +15 XP!\"
            echo
            echo \"Only one goblin remains!\"
            GOBLIN_ATK=\$((RANDOM % 6 + 1))
            HP=\$((HP - GOBLIN_ATK))
            echo \"🗡️  Goblin #3 hits you for \$GOBLIN_ATK damage!\"
            echo \"💔 HP: \$HP/\$MAX_HP\"
        else
            echo \"🗡️  Goblin Raider #2 takes \$PLAYER_DMG damage! (HP: \$GOBLIN2_HP)\"
            echo
            echo \"The goblins counterattack!\"
            GOBLIN2_ATK=\$((RANDOM % 6 + 1))
            GOBLIN3_ATK=\$((RANDOM % 6 + 1))
            TOTAL_DMG=\$((GOBLIN2_ATK + GOBLIN3_ATK))
            HP=\$((HP - TOTAL_DMG))
            echo \"🗡️  Goblin #2 hits you for \$GOBLIN2_ATK damage!\"
            echo \"🗡️  Goblin #3 hits you for \$GOBLIN3_ATK damage!\"
            echo \"💔 You take \$TOTAL_DMG total damage! HP: \$HP/\$MAX_HP\"
        fi
        ;;
    2)
        FIREBALL_DMG=\$((RANDOM % 20 + 1))
        echo
        echo \"═══════════════════════════════════════════════════════════════════\"
        echo \"                    🔥 FIREBALL 🔥\"
        echo \"═══════════════════════════════════════════════════════════════════\"
        echo \"You unfurl the ancient scroll and speak the words of power!\"
        echo \"A massive fireball explodes among the goblins!\"
        echo \"💥 FIREBALL deals \$FIREBALL_DMG damage to ALL enemies!\"
        echo
        echo \"💀 Goblin Raider #2 is OBLITERATED!\"
        echo \"💀 Goblin Raider #3 is OBLITERATED!\"
        XP=\$((XP + 30))
        GOLD=\$((GOLD + 16))
        echo \"💰 +16 gold! 🌟 +30 XP!\"
        HP=\$HP
        ;;
    3)
        HEAL_AMT=\$((RANDOM % 8 + 1 + RANDOM % 8 + 1))
        HP=\$((HP + HEAL_AMT))
        [ \$HP -gt \$MAX_HP ] && HP=\$MAX_HP
        echo
        echo \"═══════════════════════════════════════════════════════════════════\"
        echo \"You drink the healing potion! ❤️ +\$HEAL_AMT HP\"
        echo \"HP: \$HP/\$MAX_HP\"
        echo \"═══════════════════════════════════════════════════════════════════\"
        echo
        echo \"The goblins attack while you drink!\"
        GOBLIN2_ATK=\$((RANDOM % 6 + 1))
        GOBLIN3_ATK=\$((RANDOM % 6 + 1))
        TOTAL_DMG=\$((GOBLIN2_ATK + GOBLIN3_ATK))
        HP=\$((HP - TOTAL_DMG))
        echo \"🗡️  Goblin #2 hits you for \$GOBLIN2_ATK damage!\"
        echo \"🗡️  Goblin #3 hits you for \$GOBLIN3_ATK damage!\"
        echo \"💔 You take \$TOTAL_DMG total damage! HP: \$HP/\$MAX_HP\"
        ;;
    *)
        echo \"Invalid choice! The goblins attack!\"
        GOBLIN2_ATK=\$((RANDOM % 6 + 1))
        GOBLIN3_ATK=\$((RANDOM % 6 + 1))
        TOTAL_DMG=\$((GOBLIN2_ATK + GOBLIN3_ATK))
        HP=\$((HP - TOTAL_DMG))
        echo \"💔 You take \$TOTAL_DMG total damage! HP: \$HP/\$MAX_HP\"
        ;;
esac

echo \"═══════════════════════════════════════════════════════════════════\"
echo \"CHAPTER 4 STATUS: HP=\$HP/\$MAX_HP | Gold=\$GOLD | XP=\$XP/100 | Level=\$LEVEL\"
echo \"Combat continues...\"
echo \"═══════════════════════════════════════════════════════════════════\"
" /dev/null
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: Initialize D&D-style text adventure with character creation
# Generated: 2026-01-31 10:30:08 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step6() {
    clear
    
    # Initialize game state (global variables for persistence)
    HP=20
    MAX_HP=20
    STRENGTH=10
    DEXTERITY=10
    INTELLIGENCE=10
    GOLD=10
    LOCATION="village_square"
    INVENTORY=()
    CHAPTER=1
    
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                      ⚔️  REALM OF SHADOWS  ⚔️                              ║
║                    A Text Adventure Awaits...                              ║
╚════════════════════════════════════════════════════════════════════════════╝

CHAPTER 1: The Village of Thornhaven

You awaken in the quiet village of Thornhaven, a small settlement on the edge
of the Darkwood Forest. The morning sun barely breaks through the thick mist
that clings to the cobblestone streets.

════════════════════════════════════════════════════════════════════════════

CHARACTER STATS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HP: 20/20  ❤️    STRENGTH:     10  💪
  GOLD: 10   💰    DEXTERITY:    10  🏃
  LOCATION: Thornhaven Village Square    INTELLIGENCE: 10  📚
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

════════════════════════════════════════════════════════════════════════════

The village square bustles with activity. You notice:

  🏛️  [1] The Town Hall - The mayor might have work
  🍺 [2] The Rusty Tankard Inn - Warmth, food, and rumors
  🗡️  [3] Blacksmith's Forge - Weapons and armor
  🌲 [4] Path to Darkwood Forest - A dangerous route
  📚 [5] Old Library - Ancient tomes and knowledge

An old woman approaches you, her eyes filled with worry.

"Please, brave adventurer! A dire wolf has been terrorizing our village,
taking our livestock at night. The mayor offers a reward of 50 gold pieces
to whoever can slay the beast!"

════════════════════════════════════════════════════════════════════════════
QUEST RECEIVED: Slay the Dire Wolf
Reward: 50 Gold
════════════════════════════════════════════════════════════════════════════

What will you do?
EOF

    echo ""
    echo "STATUS: Chapter 1 initialized. HP=$HP STR=$STRENGTH DEX=$DEXTERITY INT=$INTELLIGENCE GOLD=$GOLD LOCATION=$LOCATION"
}
step6

# ═══════════════════════════════════════════════════════════════
# STEP 7: Continue adventure - player chooses action
# Generated: 2026-01-31 10:30:51 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step7() {
    # Display colorized prompt
    echo -e "\n\033[1;33m════════════════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;36mWhat will you do?\033[0m"
    echo -e "\033[1;33m════════════════════════════════════════════════════════════════════════════\033[0m"
    echo ""
    echo -e "  \033[1;32m[1]\033[0m Visit the Town Hall"
    echo -e "  \033[1;32m[2]\033[0m Enter The Rusty Tankard Inn"
    echo -e "  \033[1;32m[3]\033[0m Go to the Blacksmith's Forge"
    echo -e "  \033[1;32m[4]\033[0m Head into Darkwood Forest"
    echo -e "  \033[1;32m[5]\033[0m Visit the Old Library"
    echo -e "  \033[1;32m[6]\033[0m Accept the quest and ask for more information"
    echo ""
    echo -n -e "\033[1;37mEnter your choice (1-6): \033[0m"
    
    read -r CHOICE
    
    echo ""
    echo -e "\033[1;33m════════════════════════════════════════════════════════════════════════════\033[0m"
    echo ""
    
    case $CHOICE in
        1)
            echo -e "\033[1;35m📜 THE TOWN HALL\033[0m"
            echo ""
            echo "You push open the heavy oak doors and enter the town hall."
            echo "Mayor Aldric, a portly man with a thick beard, looks up from his desk."
            echo ""
            echo '"Ah, another adventurer! Welcome to Thornhaven. I assume the old woman'
            echo 'told you about our dire wolf problem? Indeed, the beast prowls at night.'
            echo 'We need someone brave enough to track it down. I can offer you 50 gold"'
            echo 'pieces, plus any equipment from our armory - a steel sword and leather armor."'
            echo ""
            echo "QUEST UPDATED: Mayor offers steel sword + leather armor as additional reward"
            echo "STATUS: LOCATION=town_hall"
            ;;
        2)
            echo -e "\033[1;35m🍺 THE RUSTY TANKARD INN\033[0m"
            echo ""
            echo "You enter the warm, smoky inn. The smell of roasted meat fills the air."
            echo "The innkeeper, a burly woman named Marta, greets you with a smile."
            echo ""
            echo '"Welcome, traveler! Ale costs 2 gold, a meal is 3 gold, and a room for'
            echo 'the night is 5 gold. What will it be?"'
            echo ""
            echo "A grizzled hunter in the corner calls out:"
            echo '"If you\'re hunting that dire wolf, you\'ll want to check the northern edge'
            echo 'of Darkwood around midnight. That\'s when it hunts. And bring fire - wolves'
            echo 'fear flames!"'
            echo ""
            echo "INFO GAINED: Dire wolf hunts at midnight, vulnerable to fire"
            echo "STATUS: LOCATION=inn"
            ;;
        3)
            echo -e "\033[1;35m⚒️  BLACKSMITH'S FORGE\033[0m"
            echo ""
            echo "The heat of the forge washes over you as you enter."
            echo "Thorgrim, the dwarf blacksmith, wipes sweat from his brow."
            echo ""
            echo '"Looking for gear, are ye? I have:"'
            echo ""
            echo "  • Iron Sword (15 gold) - +3 STR damage"
            echo "  • Leather Armor (12 gold) - +2 HP protection"
            echo "  • Torch x3 (5 gold) - Fire source, wolves fear it"
            echo "  • Health Potion (8 gold) - Restore 10 HP"
            echo ""
            echo "Your gold: 10 💰"
            echo ""
            echo "SHOP AVAILABLE: Come back when you have more gold"
            echo "STATUS: LOCATION=blacksmith"
            ;;
        4)
            echo -e "\033[1;35m🌲 DARKWOOD FOREST - DAY\033[0m"
            echo ""
            echo "You approach the dark treeline. Even in daylight, the forest looks ominous."
            echo "The trees are thick and gnarled, their branches forming a canopy that blocks"
            echo "most of the sunlight."
            echo ""
            echo "A weathered sign reads: 'DANGER - Dire wolves, goblins, and worse lurk within'"
            echo ""
            echo "INTELLIGENCE CHECK (roll 1d20 + INT modifier)..."
            ROLL=$((RANDOM % 20 + 1))
            INT_MOD=0
            TOTAL=$((ROLL + INT_MOD))
            echo "Rolled: $ROLL + $INT_MOD = $TOTAL"
            echo ""
            if [ $TOTAL -ge 12 ]; then
                echo "✓ SUCCESS! You notice fresh wolf tracks leading north, and claw marks"
                echo "  on nearby trees. The dire wolf definitely uses this area."
                echo ""
                echo "INFO GAINED: Wolf tracks lead north into forest"
            else
                echo "✗ FAILED. The forest seems impenetrable and confusing."
            fi
            echo ""
            echo "It would be unwise to enter unprepared and unarmed."
            echo "STATUS: LOCATION=forest_edge"
            ;;
        5)
            echo -e "\033[1;35m📚 THE OLD LIBRARY\033[0m"
            echo ""
            echo "You enter the dusty library. Shelves of ancient tomes line the walls."
            echo "An elderly sage named Elminster looks up from his reading."
            echo ""
            echo '"Ah, a seeker of knowledge! I sense you\'re on a quest. Let me see..."'
            echo "He pulls out an old bestiary and flips through yellowed pages."
            echo ""
            echo '"Dire Wolves - Level 2 Beasts. HP: 25, ATK: 2d6. Weak to: Fire (+50% damage)'
            echo 'Abilities: Pack Tactics (advantage if allies present), Keen Hearing."'
            echo ""
            echo "He looks at you seriously:"
            echo '"You\'re level 1, aren\'t you? This will be a difficult fight. I recommend'
            echo 'getting better equipment first, and perhaps some fire-based weapons or torches."'
            echo ""
            echo "KNOWLEDGE GAINED: Dire Wolf has 25 HP, deals 2d6 damage, weak to fire"
            echo "STATUS: LOCATION=library"
            ;;
        6)
            echo -e "\033[1;35m🗣️  SPEAKING WITH THE OLD WOMAN\033[0m"
            echo ""
            echo "You turn to the old woman and nod."
            echo '"I\'ll help you with your dire wolf problem. Tell me more."'
            echo ""
            echo 'She clasps her hands together gratefully.'
            echo '"Oh, thank you! The beast is massive - twice the size of a normal wolf,'
            echo 'with eyes that glow red in the darkness. It comes from the northern part'
            echo 'of Darkwood Forest every night around midnight."'
            echo ""
            echo '"My husband was a hunter before he passed. Take this - it might help."'
            echo ""
            echo "She hands you an old, worn TORCH."
            echo ""
            echo "ITEM GAINED: Torch (1x) - Can be used as weapon or light source"
            echo "QUEST ACCEPTED: Slay the Dire Wolf"
            echo "STATUS: INVENTORY=torch"
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
    
    echo ""
    echo -e "\033[1;33m════════════════════════════════════════════════════════════════════════════\033[0m"
    echo ""
    echo -e "\033[1;36mCurrent Status:\033[0m HP: 20/20 ❤️  | GOLD: 10 💰 | STR: 10 | DEX: 10 | INT: 10"
    echo ""
    echo "STATUS: CHOICE=$CHOICE AWAITING_NEXT_ACTION=true"
}
step7

# ═══════════════════════════════════════════════════════════════
# STEP 8: Start D&D fantasy adventure - character creation
# Generated: 2026-01-31 10:31:05 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step8() {
    clear
    
    # Character stats (global for persistence)
    HP=20
    MAX_HP=20
    ATTACK=5
    DEFENSE=3
    GOLD=10
    CHAPTER=1
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           THE RUINS OF SHADOWPEAK - A D&D Adventure           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "You are a young adventurer seeking fortune in the cursed ruins"
    echo "of Shadowpeak Tower. Legends speak of ancient treasures..."
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "CHARACTER STATS:"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  HP:      $HP/$MAX_HP ♥"
    echo "  Attack:  $ATTACK ⚔"
    echo "  Defense: $DEFENSE 🛡"
    echo "  Gold:    $GOLD 💰"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "CHAPTER 1: THE ENTRANCE"
    echo ""
    echo "You stand before the crumbling entrance of Shadowpeak Tower."
    echo "Dark stone archways loom overhead, covered in ancient moss."
    echo "A cold wind carries whispers from within..."
    echo ""
    echo "Suddenly, a GOBLIN jumps out from behind a broken pillar!"
    echo ""
    echo "🗡 GOBLIN appears! (HP: 8, Attack: 3)"
    echo ""
    echo "COMBAT_START CHAPTER_1_GOBLIN HP:$HP ENEMY_HP:8"
}
step8
