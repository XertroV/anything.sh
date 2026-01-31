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
# Generated: 2026-01-31 09:32:55 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    # Character stats
    NAME="Adventurer"
    CLASS="Fighter"
    LEVEL=1
    HP=20
    MAX_HP=20
    STR=14
    DEX=12
    CON=13
    INT=10
    WIS=11
    CHA=8
    GOLD=15
    XP=0
    INVENTORY=("Longsword" "Leather Armor" "Torch" "Rations x3")
    LOCATION="tavern"
    CHAPTER=1
    
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "        ⚔️  DUNGEONS OF THE FORGOTTEN REALM ⚔️"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "The smell of ale and woodsmoke fills your nostrils as you push"
    echo "open the heavy oak door of the Prancing Pony tavern. Outside,"
    echo "a fierce storm rages through the village of Millbrook."
    echo ""
    echo "You are a wandering $CLASS, seeking fortune and glory."
    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│  CHARACTER SHEET                        │"
    echo "├─────────────────────────────────────────┤"
    printf "│  %-20s Level: %-10d │\n" "$NAME" "$LEVEL"
    echo "│  Class: $CLASS                          │"
    echo "├─────────────────────────────────────────┤"
    printf "│  HP: %d/%d     Gold: %d gp            │\n" "$HP" "$MAX_HP" "$GOLD"
    echo "│  STR: $STR  DEX: $DEX  CON: $CON              │"
    echo "│  INT: $INT  WIS: $WIS  CHA: $CHA               │"
    echo "├─────────────────────────────────────────┤"
    echo "│  Inventory: ${INVENTORY[*]}  │"
    echo "└─────────────────────────────────────────┘"
    echo ""
    echo "A grizzled old man approaches your table, his eyes wild."
    echo "'Please, brave warrior! Goblins have taken my daughter to the'"
    echo "'ruins north of town. I'll pay 50 gold pieces for her rescue!'"
    echo ""
    echo "What do you do?"
    echo "  [1] Accept the quest heroically"
    echo "  [2] Demand more gold (Charisma check)"
    echo "  [3] Ask for more information"
    echo ""
    echo "CHAPTER $CHAPTER: The Call to Adventure"
    echo "STATE: HP=$HP GOLD=$GOLD LOCATION=$LOCATION QUEST=offered"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: Player chooses to accept the quest
# Generated: 2026-01-31 09:33:11 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
    # Game state
    HP=20
    MAX_HP=20
    GOLD=15
    LEVEL=1
    STR=14
    DEX=12
    CON=13
    INT=10
    WIS=11
    CHA=8
    LOCATION="tavern"
    QUEST_ACCEPTED=true
    
    clear
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
        ⚔️  DUNGEONS OF THE FORGOTTEN REALM ⚔️
═══════════════════════════════════════════════════════════════

You stand tall and place your hand on the old man's shoulder.

"Fear not, good sir. I shall rescue your daughter from those
vile creatures. Point me toward these ruins!"

The old man's eyes fill with tears of gratitude.
"Bless you, brave warrior! The ruins lie a half-day's march
north, through the Whispering Woods. Take this..."

He presses a small vial into your hands.

  ✨ RECEIVED: Potion of Healing (+10 HP)

"My daughter's name is Elena. She has hair like autumn leaves.
Please... bring her home safely."

You gather your belongings and step out into the storm.
The rain lashes against your face as you head north...

───────────────────────────────────────────────────────────────
                    THE WHISPERING WOODS
───────────────────────────────────────────────────────────────

The forest path grows dark and twisted. Strange sounds echo
between the ancient trees. Your torch flickers ominously.

Suddenly, you hear rustling ahead! Two GOBLIN SCOUTS emerge
from the underbrush, their yellow eyes gleaming with malice!

┌─────────────────────────────────────────┐
│  ⚔️  COMBAT ENCOUNTER!                  │
│  Goblin Scout A - HP: 7                 │
│  Goblin Scout B - HP: 7                 │
│                                         │
│  Your HP: 20/20                         │
└─────────────────────────────────────────┘

What do you do?
  [1] Attack with longsword (STR)
  [2] Attempt to intimidate them (CHA)
  [3] Try to sneak past (DEX)
  [4] Use torch as weapon

CHAPTER 2: Into the Woods
STATE: HP=20 GOLD=15 LOCATION=forest QUEST=accepted INVENTORY=potion
EOF
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Combat encounter with goblin scouts
# Generated: 2026-01-31 09:33:33 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
    # Game state
    HP=20
    MAX_HP=20
    GOLD=15
    LOCATION="forest"
    GOBLIN_A_HP=7
    GOBLIN_B_HP=7
    HAS_POTION=true
    
    clear
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
        ⚔️  DUNGEONS OF THE FORGOTTEN REALM ⚔️
═══════════════════════════════════════════════════════════════

You grip your longsword tightly and charge at the goblins!

"FOR HONOR!" you bellow, your blade singing through the air!

EOF

    # Simulate combat with dice rolls
    PLAYER_ROLL=$((RANDOM % 20 + 1))
    DAMAGE=$((RANDOM % 6 + 3))
    
    echo "  🎲 Attack Roll: $PLAYER_ROLL + 3 (STR) = $((PLAYER_ROLL + 3))"
    sleep 0.3
    
    if [ $PLAYER_ROLL -ge 8 ]; then
        echo "  ⚔️  HIT! You slash Goblin A for $DAMAGE damage!"
        GOBLIN_A_HP=$((GOBLIN_A_HP - DAMAGE))
        if [ $GOBLIN_A_HP -le 0 ]; then
            echo "  💀 Goblin A falls with a shriek!"
            GOBLIN_A_HP=0
        fi
    else
        echo "  ❌ Your swing goes wide!"
    fi
    
    echo ""
    echo "The goblins counter-attack!"
    
    # Goblin attacks
    for goblin in "A:$GOBLIN_A_HP" "B:$GOBLIN_B_HP"; do
        name="${goblin%%:*}"
        hp="${goblin##*:}"
        if [ "$hp" -gt 0 ]; then
            GOBLIN_ROLL=$((RANDOM % 20 + 1))
            if [ $GOBLIN_ROLL -ge 12 ]; then
                G_DAMAGE=$((RANDOM % 4 + 1))
                HP=$((HP - G_DAMAGE))
                echo "  🗡️  Goblin $name hits you for $G_DAMAGE damage!"
            else
                echo "  🛡️  You parry Goblin ${name}'s attack!"
            fi
        fi
    done
    
    echo ""
    cat << EOF
┌─────────────────────────────────────────┐
│  ⚔️  COMBAT STATUS                      │
│  Goblin Scout A - HP: $GOBLIN_A_HP                 │
│  Goblin Scout B - HP: $GOBLIN_B_HP                 │
│                                         │
│  Your HP: $HP/$MAX_HP                         │
└─────────────────────────────────────────┘
EOF

    # Continue combat - player's second attack
    echo ""
    echo "You press your advantage with a sweeping strike!"
    PLAYER_ROLL=$((RANDOM % 20 + 1))
    DAMAGE=$((RANDOM % 8 + 4))
    
    echo "  🎲 Attack Roll: $PLAYER_ROLL + 3 (STR) = $((PLAYER_ROLL + 3))"
    
    if [ $PLAYER_ROLL -ge 6 ]; then
        if [ $GOBLIN_A_HP -gt 0 ]; then
            echo "  ⚔️  CRITICAL SLASH! Goblin A takes $DAMAGE damage!"
            GOBLIN_A_HP=0
        fi
        echo "  💀 Goblin A is slain!"
        echo "  ⚔️  Your blade continues through to Goblin B for $((DAMAGE/2)) damage!"
        GOBLIN_B_HP=$((GOBLIN_B_HP - DAMAGE/2))
    fi
    
    if [ $GOBLIN_B_HP -le 0 ]; then
        GOBLIN_B_HP=0
        echo "  💀 Goblin B collapses!"
    fi
    
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo "                    ✨ VICTORY! ✨"
    echo "───────────────────────────────────────────────────────────────"
    echo ""
    echo "The forest falls silent. You wipe your blade clean."
    echo ""
    LOOT=$((RANDOM % 10 + 5))
    GOLD=$((GOLD + LOOT))
    echo "  💰 Looted: $LOOT gold pieces"
    echo "  🗡️  Found: Rusty Dagger (backup weapon)"
    echo ""
    echo "Searching the bodies, you find a crude map scratched on leather."
    echo "It shows the path to the ANCIENT RUINS!"
    echo ""
    echo "As you venture deeper, the trees thin and you see..."
    echo "Crumbling stone pillars rising from the mist ahead!"
    echo ""
    cat << 'EOF'
What do you do?
  [1] Scout the ruins carefully (DEX check)
  [2] March boldly to the entrance (no stealth)
  [3] Search for an alternate entrance
  [4] Rest and use your healing potion

EOF
    echo "CHAPTER 3: The Ancient Ruins"
    echo "STATE: HP=$HP GOLD=$GOLD LOCATION=ruins_entrance HAS_POTION=$HAS_POTION"
}
step3

# ═══════════════════════════════════════════════════════════════
# STEP 4: Continue to Chapter 3 - exploring the ancient ruins
# Generated: 2026-01-31 09:34:14 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step4() {
    # Persistent state from previous steps
    HP=17
    MAX_HP=20
    GOLD=24
    STR=3
    DEX=2
    CON=1
    WIS=0
    LOCATION="ruins_entrance"
    HAS_POTION=true
    HAS_RUSTY_DAGGER=true
    
    clear
    
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
        🏛️  CHAPTER 3: THE ANCIENT RUINS 🏛️
═══════════════════════════════════════════════════════════════

You approach the crumbling entrance cautiously, choosing to
scout ahead before entering...

  🎲 Stealth Roll: 
EOF
    
    STEALTH_ROLL=$((RANDOM % 20 + 1))
    TOTAL=$((STEALTH_ROLL + DEX))
    echo "     $STEALTH_ROLL + $DEX (DEX) = $TOTAL"
    
    if [ $TOTAL -ge 12 ]; then
        echo ""
        echo "  ✅ You move like a shadow through the ruins!"
        echo ""
        cat << 'EOF'
From your hidden vantage point, you observe:
  • A SKELETAL GUARDIAN patrols the main hall
  • Ancient runes glow faintly on the walls
  • A cracked pillar could be toppled as a trap!

You've gained TACTICAL ADVANTAGE!
EOF
        ADVANTAGE=true
    else
        echo ""
        echo "  ⚠️  A loose stone clatters under your foot!"
        echo ""
        cat << 'EOF'
The noise echoes through the halls...
Something stirs in the darkness ahead!
EOF
        ADVANTAGE=false
    fi
    
    echo ""
    cat << 'EOF'
───────────────────────────────────────────────────────────────
                  🦴 SKELETAL GUARDIAN 🦴
───────────────────────────────────────────────────────────────
  "WHO DISTURBS THE ETERNAL REST?"

  The undead warrior raises its ancient blade!
  Its empty eye sockets burn with pale blue fire!

┌─────────────────────────────────────────┐
│  👤 ALDRIC THE WANDERER                 │
│  HP: 17/20  |  Gold: 24                 │
│  STR: 16 (+3)  DEX: 14 (+2)             │
│  CON: 12 (+1)  WIS: 10 (+0)             │
│  🧪 Healing Potion: YES                 │
│  🗡️  Rusty Dagger: YES                  │
├─────────────────────────────────────────┤
│  🦴 SKELETAL GUARDIAN                   │
│  HP: ???  |  AC: 13                     │
│  "Ancient protector of the ruins"       │
└─────────────────────────────────────────┘

COMBAT OPTIONS:
  [1] Attack with longsword (1d8+3)
  [2] Attempt to turn undead (WIS check - risky!)
  [3] Use the environment (topple pillar - DEX)
  [4] Drink healing potion (restore 2d4+2 HP)
EOF

    # Simulate player choice
    sleep 1
    CHOICE=$((RANDOM % 3 + 1))
    
    if [ "$ADVANTAGE" = true ]; then
        echo ""
        echo "With your tactical advantage, you strike first!"
        echo ""
        
        # Topple the pillar!
        echo "You sprint toward the cracked pillar and SHOVE!"
        DEX_ROLL=$((RANDOM % 20 + 1))
        DEX_TOTAL=$((DEX_ROLL + DEX))
        echo "  🎲 DEX Check: $DEX_ROLL + $DEX = $DEX_TOTAL"
        
        if [ $DEX_TOTAL -ge 10 ]; then
            echo ""
            echo "  💥 THE PILLAR CRASHES DOWN!"
            echo "  🦴 Skeletal Guardian takes 15 CRUSHING DAMAGE!"
            SKELETON_HP=$((25 - 15))
            echo ""
            echo "  The skeleton staggers, bones cracking!"
        else
            SKELETON_HP=25
            echo "  The pillar wobbles but holds!"
        fi
    else
        SKELETON_HP=25
        echo ""
        echo "The guardian strikes first!"
        SKEL_ATTACK=$((RANDOM % 20 + 1))
        if [ $SKEL_ATTACK -ge 12 ]; then
            DAMAGE=$((RANDOM % 8 + 1))
            HP=$((HP - DAMAGE))
            echo "  💀 The skeleton's blade cuts you for $DAMAGE damage!"
        else
            echo "  🛡️  You deflect the rusty blade!"
        fi
    fi
    
    echo ""
    echo "You raise your longsword and ATTACK!"
    ATTACK=$((RANDOM % 20 + 1))
    ATTACK_TOTAL=$((ATTACK + STR))
    echo "  🎲 Attack: $ATTACK + $STR = $ATTACK_TOTAL vs AC 13"
    
    if [ $ATTACK -eq 20 ]; then
        DAMAGE=$(( (RANDOM % 8 + 1) + (RANDOM % 8 + 1) + STR ))
        echo "  ⚡ CRITICAL HIT! $DAMAGE damage!"
        SKELETON_HP=$((SKELETON_HP - DAMAGE))
    elif [ $ATTACK_TOTAL -ge 13 ]; then
        DAMAGE=$((RANDOM % 8 + 1 + STR))
        echo "  ✅ Hit! $DAMAGE damage!"
        SKELETON_HP=$((SKELETON_HP - DAMAGE))
    else
        echo "  ❌ Your blade passes through empty air!"
    fi
    
    # Continue combat
    while [ $SKELETON_HP -gt 0 ] && [ $HP -gt 0 ]; do
        echo ""
        echo "  [Skeleton HP: $SKELETON_HP | Your HP: $HP]"
        
        # Skeleton attacks
        SKEL_ATTACK=$((RANDOM % 20 + 1))
        if [ $SKEL_ATTACK -ge 12 ]; then
            DAMAGE=$((RANDOM % 8 + 1))
            HP=$((HP - DAMAGE))
            echo "  💀 Skeleton slashes for $DAMAGE!"
        else
            echo "  🛡️  You parry the skeleton's attack!"
        fi
        
        [ $HP -le 0 ] && break
        
        # Player attacks
        ATTACK=$((RANDOM % 20 + 1))
        ATTACK_TOTAL=$((ATTACK + STR))
        if [ $ATTACK -eq 20 ]; then
            DAMAGE=$(( (RANDOM % 8 + 1) * 2 + STR ))
            SKELETON_HP=$((SKELETON_HP - DAMAGE))
            echo "  ⚡ CRITICAL! You deal $DAMAGE damage!"
        elif [ $ATTACK_TOTAL -ge 13 ]; then
            DAMAGE=$((RANDOM % 8 + 1 + STR))
            SKELETON_HP=$((SKELETON_HP - DAMAGE))
            echo "  ⚔️  You strike for $DAMAGE!"
        else
            echo "  ❌ Miss!"
        fi
    done
    
    echo ""
    if [ $HP -le 0 ]; then
        cat << 'EOF'
═══════════════════════════════════════════════════════════════
                    💀 YOU HAVE FALLEN 💀
═══════════════════════════════════════════════════════════════

The skeleton's blade finds its mark. You collapse among
the ancient stones, another soul claimed by the ruins...

                      GAME OVER

        "Perhaps another adventurer will succeed..."
═══════════════════════════════════════════════════════════════
EOF
    else
        cat << 'EOF'

═══════════════════════════════════════════════════════════════
                    ✨ VICTORY! ✨
═══════════════════════════════════════════════════════════════

The skeletal guardian crumbles to dust, its spirit released!

As the bones scatter, something glints among them...
EOF
        
        GOLD_FOUND=$((RANDOM % 20 + 10))
        GOLD=$((GOLD + GOLD_FOUND))
        echo ""
        echo "  💰 Found: $GOLD_FOUND gold pieces!"
        echo "  🗝️  Found: ANCIENT KEY"
        echo "  📜 Found: Mysterious Scroll"
        echo ""
        
        cat << 'EOF'
The scroll reads in an ancient tongue:
  "Beyond the sealed door lies the DRAGON'S HOARD...
   But beware, for Varathos the Eternal guards it still."

A massive stone door stands before you, inscribed with runes.
The Ancient Key fits perfectly into the lock...

EOF
        
        echo "┌─────────────────────────────────────────┐"
        printf "│  Your HP: %d/%d  |  Gold: %d            \n" $HP $MAX_HP $GOLD
        echo "│  🗝️  Ancient Key: OBTAINED              │"
        echo "│  📜 Dragon's Warning: READ              │"
        echo "└─────────────────────────────────────────┘"
        echo ""
        echo "CHAPTER 3 COMPLETE."
        echo "STATE: HP=$HP GOLD=$GOLD LOCATION=sealed_door HAS_KEY=true"
    fi
}
step4

# ═══════════════════════════════════════════════════════════════
# STEP 5: Chapter 4 - The Dragon's Lair
# Generated: 2026-01-31 09:34:49 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step5() {
    # Persistent state from previous chapter
    HP=4
    MAX_HP=20
    GOLD=37
    STR_MOD=3
    DEX_MOD=2
    CON_MOD=1
    WIS_MOD=0
    HAS_POTION=true
    HAS_DAGGER=true
    HAS_KEY=true
    
    roll() { echo $(( (RANDOM % $1) + 1 )); }
    
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "        🐉 CHAPTER 4: THE DRAGON'S LAIR 🐉"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "With trembling hands, you turn the Ancient Key..."
    sleep 0.3
    echo ""
    echo "  ⚙️  *CLICK* ... *RUMBLE* ... *CREAK*"
    echo ""
    echo "The massive stone door slowly grinds open, revealing..."
    sleep 0.3
    echo ""
    echo "  ✨ MOUNTAINS OF GOLD AND JEWELS! ✨"
    echo ""
    echo "But atop the treasure hoard, coiled like a living mountain,"
    echo "lies VARATHOS THE ETERNAL - an ancient red dragon!"
    echo ""
    
    # Critical decision with low HP
    echo "┌─────────────────────────────────────────┐"
    echo "│  ⚠️  WARNING: HP CRITICAL! (4/20)       │"
    echo "│  🧪 You still have a healing potion!   │"
    echo "└─────────────────────────────────────────┘"
    echo ""
    
    # Auto-use potion at critical HP before dragon encounter
    HEAL=$(( (RANDOM % 4) + 1 + (RANDOM % 4) + 1 + 2 ))
    HP=$(( HP + HEAL > MAX_HP ? MAX_HP : HP + HEAL ))
    HAS_POTION=false
    
    echo "  💚 You quickly drink your healing potion!"
    echo "     Restored $HEAL HP! (HP: $HP/$MAX_HP)"
    echo ""
    sleep 0.3
    
    echo "───────────────────────────────────────────────────────────────"
    echo "                  🐉 VARATHOS THE ETERNAL 🐉"
    echo "───────────────────────────────────────────────────────────────"
    echo ""
    echo "  The dragon's eye opens - a slit of molten gold!"
    echo ""
    echo '  "A MORTAL DARES ENTER MY DOMAIN?"'
    echo '  "SPEAK QUICKLY, LITTLE THIEF, BEFORE I REDUCE YOU TO ASH..."'
    echo ""
    
    echo "┌─────────────────────────────────────────┐"
    echo "│  👤 ALDRIC THE WANDERER                 │"
    printf "│  HP: %2d/20  |  Gold: %-3d               │\n" "$HP" "$GOLD"
    echo "│  STR: 16 (+3)  DEX: 14 (+2)             │"
    echo "│  CON: 12 (+1)  WIS: 10 (+0)             │"
    echo "├─────────────────────────────────────────┤"
    echo "│  🐉 VARATHOS THE ETERNAL                │"
    echo "│  HP: ???  |  AC: 18  |  LEGENDARY       │"
    echo '│  "Ancient wyrm of unfathomable power"   │'
    echo "└─────────────────────────────────────────┘"
    echo ""
    
    echo "DIALOGUE OPTIONS:"
    echo "  [1] Fight the dragon (near-certain death!)"
    echo "  [2] Offer your gold as tribute"
    echo "  [3] Attempt to negotiate (CHA check)"
    echo "  [4] Present the mysterious scroll"
    echo ""
    
    # AI chooses the clever option - the scroll
    sleep 0.3
    echo "You hold up the mysterious scroll you found..."
    echo ""
    
    LORE_ROLL=$(roll 20)
    echo "  🎲 Intelligence Check: $LORE_ROLL"
    echo ""
    
    if (( LORE_ROLL >= 8 )); then
        echo '  "THAT SCROLL... WHERE DID YOU FIND IT?"'
        echo ""
        echo "  The dragon's demeanor shifts. Recognition flickers"
        echo "  in those ancient eyes..."
        echo ""
        echo '  "THAT BEARS THE SEAL OF PRINCESS AELINDRA...'
        echo '   SHE WAS... KIND TO ME, ONCE, LONG AGO.'
        echo '   BEFORE THESE RUINS WERE RUINS."'
        echo ""
        sleep 0.3
        echo "  The great wyrm lowers its head..."
        echo ""
        echo '  "TAKE WHAT YOU NEED, MORTAL. BUT PROMISE ME THIS:'
        echo '   TELL THE WORLD THAT VARATHOS REMEMBERS.'
        echo '   TELL THEM... THE DRAGON REMEMBERS KINDNESS."'
        echo ""
        
        # Treasure!
        TREASURE=$(( (RANDOM % 100) + 150 ))
        GOLD=$(( GOLD + TREASURE ))
        
        echo "═══════════════════════════════════════════════════════════════"
        echo "              ✨ THE DRAGON'S GIFT ✨"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "  💰 Received: $TREASURE gold pieces!"
        echo "  🔮 Received: DRAGON SCALE AMULET"
        echo "     (Grants fire resistance)"
        echo "  📜 Received: MAP TO THE SUNKEN TEMPLE"
        echo ""
        echo "  Varathos permits you to leave in peace..."
        echo ""
        ENDING="GOOD"
    else
        echo "  The dragon snorts dismissively."
        echo '  "YOU CANNOT EVEN READ IT, CAN YOU?"'
        echo ""
        echo "  Before you can react, a wave of fire engulfs you!"
        echo ""
        echo "  🔥🔥🔥 FIRE BREATH! 🔥🔥🔥"
        echo ""
        HP=0
        ENDING="DEATH"
    fi
    
    echo "┌─────────────────────────────────────────────────────────────┐"
    if [[ "$ENDING" == "GOOD" ]]; then
        echo "│           🏆 QUEST COMPLETE! 🏆                            │"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│  Final HP: %2d/20                                           │\n" "$HP"
        printf "│  Total Gold: %-4d                                          │\n" "$GOLD"
        echo "│  Items: Dragon Scale Amulet, Map to Sunken Temple          │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│  🐉 Achievement Unlocked: DRAGON WHISPERER                  │"
        echo "│  📖 The tale of Aldric and the Dragon spreads far...       │"
    else
        echo "│           💀 GAME OVER 💀                                   │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│  Aldric the Wanderer met his end in the Dragon's Lair.     │"
        echo "│  Perhaps another hero will succeed where he failed...      │"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "         ═══ THE END ═══"
    echo ""
    echo "Thank you for playing!"
    echo "STATE: HP=$HP GOLD=$GOLD ENDING=$ENDING"
}
step5

# ═══════════════════════════════════════════════════════════════
# STEP 6: Adventure complete - display epilogue and save game summary
# Generated: 2026-01-31 09:35:07 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step6() {
    clear
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
                    📖 EPILOGUE: THE LEGEND OF ALDRIC 📖
═══════════════════════════════════════════════════════════════════════════════

    Months have passed since that fateful encounter...

    The tale of Aldric the Wanderer spread across the realm like wildfire.
    They say a lone adventurer entered the Dragon's Lair and emerged not
    with stolen treasure, but with a dragon's blessing.

    ┌─────────────────────────────────────────────────────────────────────┐
    │  🏰 In the taverns of Thornwood, bards sing of the hero who        │
    │     showed mercy to a forgotten beast...                           │
    │                                                                    │
    │  🐉 Varathos, for the first time in centuries, sleeps peacefully,  │
    │     knowing that kindness still exists in the world...             │
    │                                                                    │
    │  🗺️  The Map to the Sunken Temple awaits, promising new            │
    │     adventures in lands unknown...                                 │
    └─────────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════════════
                         📊 FINAL CHARACTER SHEET 📊
═══════════════════════════════════════════════════════════════════════════════

    👤 ALDRIC THE WANDERER
    ═══════════════════════
    Level: 2 (gained from quest completion!)
    HP: 8/20  |  Gold: 217

    ┌──────────────────┐
    │   ATTRIBUTES     │
    ├──────────────────┤
    │  STR: 16 (+3)    │
    │  DEX: 14 (+2)    │
    │  CON: 12 (+1)    │
    │  INT: 11 (+0)    │
    │  WIS: 10 (+0)    │
    │  CHA: 13 (+1)    │
    └──────────────────┘

    🎒 INVENTORY:
       • Dragon Scale Amulet (Fire Resistance)
       • Map to the Sunken Temple
       • Ancient Key
       • Mysterious Scroll (now revealed as Princess Aelindra's letter)

    🏆 ACHIEVEMENTS UNLOCKED:
       ⭐ First Steps - Begin your adventure
       ⭐ Survivor - Escape the goblins
       ⭐ Puzzle Solver - Open the ancient door
       ⭐ Dragon Whisperer - Befriend Varathos

═══════════════════════════════════════════════════════════════════════════════

                    ✨ THANKS FOR PLAYING! ✨

           "Every hero's journey begins with a single step,
            but the greatest heroes know when to stay their blade."

                         ~ The Chronicles of Aldric ~

═══════════════════════════════════════════════════════════════════════════════
                        🎮 GAME COMPLETE 🎮
                    Ending: THE DRAGON'S BLESSING
                    Play Time: ~5 chapters
═══════════════════════════════════════════════════════════════════════════════

EOF
}
step6

_prompt
#
