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
# STEP 1: Check for dialog/whiptail for TUI text adventure
# Generated: 2026-01-31 09:23:25 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
    echo "=== Checking TUI tools ==="
    command -v dialog &>/dev/null && echo "dialog: INSTALLED" || echo "dialog: NOT_INSTALLED"
    command -v whiptail &>/dev/null && echo "whiptail: INSTALLED" || echo "whiptail: NOT_INSTALLED"
    echo "=== Checking for bc (math) ==="
    command -v bc &>/dev/null && echo "bc: INSTALLED" || echo "bc: NOT_INSTALLED"
}
step1

# ═══════════════════════════════════════════════════════════════
# STEP 2: D&D-style text adventure with stats using whiptail
# Generated: 2026-01-31 09:24:06 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step2() {
    # Character stats
    local NAME="Hero"
    local CLASS="Warrior"
    local HP=20
    local MAX_HP=20
    local STR=14
    local DEX=12
    local CON=13
    local INT=10
    local WIS=8
    local CHA=11
    local GOLD=10
    local XP=0
    local LEVEL=1
    local WEAPON="Rusty Sword"
    local ARMOR="Leather Tunic"
    
    roll_d20() { echo $(( (RANDOM % 20) + 1 )); }
    roll_dice() { local sides=$1; echo $(( (RANDOM % sides) + 1 )); }
    mod() { echo $(( ($1 - 10) / 2 )); }
    
    show_stats() {
        whiptail --title "Character Sheet" --msgbox "\
╔════════════════════════════════════╗
║  $NAME the $CLASS (Level $LEVEL)
╠════════════════════════════════════╣
║  HP: $HP/$MAX_HP    XP: $XP    Gold: $GOLD
╠════════════════════════════════════╣
║  STR: $STR ($(mod $STR))  DEX: $DEX ($(mod $DEX))  CON: $CON ($(mod $CON))
║  INT: $INT ($(mod $INT))  WIS: $WIS ($(mod $WIS))  CHA: $CHA ($(mod $CHA))
╠════════════════════════════════════╣
║  Weapon: $WEAPON
║  Armor:  $ARMOR
╚════════════════════════════════════╝" 18 50
    }
    
    combat() {
        local enemy=$1 enemy_hp=$2 enemy_ac=$3 enemy_dmg=$4
        while [[ $enemy_hp -gt 0 && $HP -gt 0 ]]; do
            local roll=$(roll_d20)
            local attack=$(( roll + $(mod $STR) ))
            local msg="You roll $roll + $(mod $STR) = $attack vs AC $enemy_ac\n"
            if [[ $attack -ge $enemy_ac ]]; then
                local dmg=$(( $(roll_dice 6) + $(mod $STR) ))
                [[ $dmg -lt 1 ]] && dmg=1
                enemy_hp=$((enemy_hp - dmg))
                msg+="HIT! You deal $dmg damage. $enemy HP: $enemy_hp"
            else
                msg+="MISS!"
            fi
            if [[ $enemy_hp -gt 0 ]]; then
                local eroll=$(roll_d20)
                local eattack=$((eroll + 2))
                msg+="\n\n$enemy attacks! Roll: $eroll + 2 = $eattack vs your AC 12"
                if [[ $eattack -ge 12 ]]; then
                    local edmg=$(roll_dice $enemy_dmg)
                    HP=$((HP - edmg))
                    msg+="\nHIT! You take $edmg damage. Your HP: $HP"
                else
                    msg+="\nMISS!"
                fi
            fi
            whiptail --title "Combat vs $enemy" --msgbox "$msg" 16 50
        done
        [[ $HP -gt 0 ]] && return 0 || return 1
    }
    
    # Character creation
    NAME=$(whiptail --inputbox "Enter your character's name:" 8 40 "Aldric" 3>&1 1>&2 2>&3) || NAME="Aldric"
    CLASS=$(whiptail --title "Choose Class" --menu "Select your class:" 12 40 3 \
        "Warrior" "STR+2, CON+1, HP+5" \
        "Rogue" "DEX+2, CHA+1" \
        "Mage" "INT+2, WIS+1" 3>&1 1>&2 2>&3) || CLASS="Warrior"
    
    case $CLASS in
        Warrior) STR=$((STR+2)); CON=$((CON+1)); MAX_HP=25; HP=25; WEAPON="Iron Longsword";;
        Rogue) DEX=$((DEX+2)); CHA=$((CHA+1)); WEAPON="Twin Daggers";;
        Mage) INT=$((INT+2)); WIS=$((WIS+1)); WEAPON="Oak Staff"; ARMOR="Robes";;
    esac
    
    # Story
    whiptail --title "The Beginning" --msgbox "\
Welcome, $NAME the $CLASS!

You awaken in a dimly lit tavern cellar. The sounds
of a commotion echo from above. Your head throbs—
you remember nothing of how you got here.

A rat scurries past. Somewhere, a door creaks open..." 14 55
    
    show_stats
    
    # Scene 1
    local choice=$(whiptail --title "The Cellar" --menu "\
You see stairs leading up, a wooden crate, and shadows moving in the corner.\n\nWhat do you do?" 15 55 3 \
        "1" "Search the crate" \
        "2" "Investigate the shadows" \
        "3" "Go upstairs immediately" 3>&1 1>&2 2>&3)
    
    case $choice in
        1)
            local find_roll=$(roll_d20)
            if [[ $find_roll -ge 10 ]]; then
                GOLD=$((GOLD + 15))
                whiptail --msgbox "You find 15 gold coins hidden in the crate! (Roll: $find_roll)\n\nGold: $GOLD" 10 45
            else
                whiptail --msgbox "The crate is empty except for moldy cloth. (Roll: $find_roll)" 8 45
            fi
            ;;
        2)
            whiptail --msgbox "A GIANT RAT leaps from the shadows!" 8 40
            if combat "Giant Rat" 6 10 4; then
                XP=$((XP + 25))
                whiptail --msgbox "Victory! The rat is slain.\n+25 XP (Total: $XP)" 8 40
            else
                whiptail --msgbox "You collapse... darkness takes you.\n\nGAME OVER" 8 40
                return
            fi
            ;;
    esac
    
    # Scene 2
    whiptail --msgbox "You climb the creaky stairs into the tavern proper.\n\nChaos! Goblins are ransacking the place. The barkeep\ncowers behind the counter. A goblin spots you!" 12 55
    
    choice=$(whiptail --title "Tavern Ambush" --menu "A goblin charges at you!" 12 50 3 \
        "1" "Fight the goblin!" \
        "2" "Try to intimidate it (CHA check)" \
        "3" "Dodge and run for the exit" 3>&1 1>&2 2>&3)
    
    case $choice in
        1)
            if combat "Goblin" 7 13 6; then
                XP=$((XP + 50))
                GOLD=$((GOLD + 8))
                whiptail --msgbox "The goblin falls! You loot 8 gold from its pouch.\n+50 XP" 8 45
            else
                whiptail --msgbox "The goblin's blade finds its mark...\n\nGAME OVER" 8 40
                return
            fi
            ;;
        2)
            local roll=$(roll_d20)
            local check=$((roll + $(mod $CHA)))
            if [[ $check -ge 12 ]]; then
                whiptail --msgbox "\"BACK, VERMIN!\" you roar. (Roll: $roll + $(mod $CHA) = $check)\n\nThe goblin hesitates, fear in its eyes, then flees!\n+30 XP" 10 50
                XP=$((XP + 30))
            else
                whiptail --msgbox "Your threat falls flat. (Roll: $roll + $(mod $CHA) = $check)\nThe goblin laughs and attacks!" 9 45
                if ! combat "Goblin" 7 13 6; then
                    whiptail --msgbox "GAME OVER" 6 20
                    return
                fi
                XP=$((XP + 50))
            fi
            ;;
        3)
            local roll=$(roll_d20)
            local check=$((roll + $(mod $DEX)))
            if [[ $check -ge 11 ]]; then
                whiptail --msgbox "You tumble past the goblin! (DEX: $roll + $(mod $DEX) = $check)\nYou burst through the tavern door into daylight." 9 50
            else
                HP=$((HP - 4))
                whiptail --msgbox "The goblin clips you as you flee! (Roll: $check vs DC 11)\n-4 HP (Now: $HP)" 8 45
            fi
            ;;
    esac
    
    [[ $HP -le 0 ]] && { whiptail --msgbox "You succumb to your wounds...\n\nGAME OVER" 8 35; return; }
    
    # Finale
    whiptail --title "To Be Continued..." --msgbox "\
You escape into the village square. Smoke rises from
several buildings. Villagers flee in panic.

A hooded figure watches from a rooftop, then vanishes.

The goblin raid is just the beginning...

═══════════════════════════════════════
  $NAME the $CLASS
  Level $LEVEL | HP: $HP/$MAX_HP | XP: $XP | Gold: $GOLD
═══════════════════════════════════════

         END OF CHAPTER ONE

    Thank you for playing!" 20 55
}
step2

_prompt
#
