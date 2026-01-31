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

        # Execute and capture output
        echo -e "\033[36m[running...]\033[0m"
        local output exit_code
        output=$( { eval "$code"; } 2>&1 )
        exit_code=$?
        echo "$output"
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
# Generated: 2026-01-31 09:03:09 | FINAL: false
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
# STEP 2: Text adventure with D&D stats using whiptail
# Generated: 2026-01-31 09:03:43 | FINAL: true
# ═══════════════════════════════════════════════════════════════
step2() {
    # Character stats
    declare -A STATS
    STATS[STR]=$((10 + RANDOM % 8))
    STATS[DEX]=$((10 + RANDOM % 8))
    STATS[CON]=$((10 + RANDOM % 8))
    STATS[INT]=$((10 + RANDOM % 8))
    STATS[WIS]=$((10 + RANDOM % 8))
    STATS[CHA]=$((10 + RANDOM % 8))
    HP=$((10 + (STATS[CON] - 10) / 2))
    MAX_HP=$HP
    GOLD=10
    XP=0
    LEVEL=1
    
    roll_d20() { echo $((1 + RANDOM % 20)); }
    stat_mod() { echo $(( (STATS[$1] - 10) / 2 )); }
    
    show_stats() {
        whiptail --title "Character Sheet" --msgbox "=== HERO (Level $LEVEL) ===\nHP: $HP/$MAX_HP | Gold: $GOLD | XP: $XP\n\nSTR: ${STATS[STR]} ($(stat_mod STR))\nDEX: ${STATS[DEX]} ($(stat_mod DEX))\nCON: ${STATS[CON]} ($(stat_mod CON))\nINT: ${STATS[INT]} ($(stat_mod INT))\nWIS: ${STATS[WIS]} ($(stat_mod WIS))\nCHA: ${STATS[CHA]} ($(stat_mod CHA))" 16 40
    }
    
    combat() {
        local enemy=$1 enemy_hp=$2 enemy_ac=$3 enemy_dmg=$4
        while [[ $enemy_hp -gt 0 && $HP -gt 0 ]]; do
            local roll=$(roll_d20)
            local atk=$((roll + $(stat_mod STR)))
            if [[ $atk -ge $enemy_ac ]]; then
                local dmg=$((1 + RANDOM % 6 + $(stat_mod STR)))
                enemy_hp=$((enemy_hp - dmg))
                whiptail --msgbox "You rolled $roll + $(stat_mod STR) = $atk vs AC $enemy_ac\nHIT! You deal $dmg damage.\n$enemy HP: $enemy_hp" 10 50
            else
                whiptail --msgbox "You rolled $roll + $(stat_mod STR) = $atk vs AC $enemy_ac\nMISS!" 8 50
            fi
            if [[ $enemy_hp -gt 0 ]]; then
                local eroll=$(roll_d20)
                local player_ac=$((10 + $(stat_mod DEX)))
                if [[ $eroll -ge $player_ac ]]; then
                    local edmg=$((1 + RANDOM % enemy_dmg))
                    HP=$((HP - edmg))
                    whiptail --msgbox "$enemy attacks! Rolled $eroll vs your AC $player_ac\nHIT! You take $edmg damage.\nYour HP: $HP" 10 50
                else
                    whiptail --msgbox "$enemy attacks! Rolled $eroll vs your AC $player_ac\nMISS!" 8 50
                fi
            fi
        done
        [[ $HP -gt 0 ]]
    }
    
    # Intro
    whiptail --title "Fantasy Quest" --msgbox "Welcome, brave adventurer!\n\nYou awaken in a dark forest clearing.\nThe moon casts eerie shadows through the trees.\n\nYour quest: Find the legendary Crystal of Dawn!" 14 50
    show_stats
    
    # Scene 1: Forest
    CHOICE=$(whiptail --title "Dark Forest" --menu "Paths diverge before you:" 15 50 4 \
        "1" "Follow the glowing mushrooms north" \
        "2" "Head toward distant torchlight east" \
        "3" "Investigate strange sounds south" \
        "4" "Check stats" 3>&1 1>&2 2>&3)
    
    case $CHOICE in
        1)
            whiptail --msgbox "The mushrooms lead to a fairy circle!\nA sprite offers you a healing potion." 8 50
            HP=$MAX_HP
            GOLD=$((GOLD + 5))
            ;;
        2)
            whiptail --msgbox "You find a goblin camp!\nThey spot you - COMBAT!" 8 50
            if combat "Goblin" 7 12 4; then
                XP=$((XP + 25))
                GOLD=$((GOLD + 15))
                whiptail --msgbox "Victory! +25 XP, +15 Gold" 8 40
            fi
            ;;
        3)
            local check=$(roll_d20)
            local wis_mod=$(stat_mod WIS)
            if [[ $((check + wis_mod)) -ge 12 ]]; then
                whiptail --msgbox "WIS check: $check + $wis_mod = $((check + wis_mod)) >= 12 SUCCESS!\nYou spot a trap and find 20 gold!" 10 50
                GOLD=$((GOLD + 20))
            else
                whiptail --msgbox "WIS check: $check + $wis_mod = $((check + wis_mod)) < 12 FAIL!\nYou fall into a pit trap! -3 HP" 10 50
                HP=$((HP - 3))
            fi
            ;;
        4) show_stats ;;
    esac
    
    [[ $HP -le 0 ]] && { whiptail --msgbox "YOU HAVE DIED\nGame Over" 8 30; return; }
    
    # Scene 2: Cave
    whiptail --msgbox "You discover a cave entrance.\nAncient runes glow on the walls.\nThe Crystal must be inside!" 10 45
    
    CHOICE=$(whiptail --title "Crystal Cave" --menu "Inside the cave:" 12 50 3 \
        "1" "Charge in boldly (STR)" \
        "2" "Sneak carefully (DEX)" \
        "3" "Decipher the runes (INT)" 3>&1 1>&2 2>&3)
    
    case $CHOICE in
        1)
            whiptail --msgbox "A Stone Golem awakens!" 8 40
            if combat "Stone Golem" 15 14 6; then
                XP=$((XP + 50))
                whiptail --msgbox "The golem crumbles! +50 XP" 8 40
            fi
            ;;
        2)
            local check=$(roll_d20)
            local dex_mod=$(stat_mod DEX)
            if [[ $((check + dex_mod)) -ge 14 ]]; then
                whiptail --msgbox "DEX check: $((check + dex_mod)) >= 14 SUCCESS!\nYou slip past the guardian unnoticed!" 10 50
                XP=$((XP + 30))
            else
                whiptail --msgbox "DEX check: $((check + dex_mod)) < 14 FAIL!\nAlarm triggered! Guards attack!" 10 50
                combat "Cave Guard" 10 13 5
            fi
            ;;
        3)
            local check=$(roll_d20)
            local int_mod=$(stat_mod INT)
            if [[ $((check + int_mod)) -ge 13 ]]; then
                whiptail --msgbox "INT check: $((check + int_mod)) >= 13 SUCCESS!\nThe runes reveal a secret passage!" 10 50
                XP=$((XP + 40))
                GOLD=$((GOLD + 30))
            else
                whiptail --msgbox "INT check failed! The runes explode! -5 HP" 8 50
                HP=$((HP - 5))
            fi
            ;;
    esac
    
    [[ $HP -le 0 ]] && { whiptail --msgbox "YOU HAVE DIED\nGame Over" 8 30; return; }
    
    # Finale
    whiptail --msgbox "You reach the crystal chamber!\nThe Crystal of Dawn floats before you,\nguarded by a SHADOW DRAGON!" 10 50
    
    if combat "Shadow Dragon" 25 16 8; then
        XP=$((XP + 100))
        whiptail --title "VICTORY!" --msgbox "You have obtained the Crystal of Dawn!\n\n=== FINAL SCORE ===\nLevel: $LEVEL | XP: $XP\nGold: $GOLD | HP: $HP/$MAX_HP\n\nThe realm is saved!\nThanks for playing!" 14 45
    else
        whiptail --msgbox "The dragon's shadow consumes you...\n\nGAME OVER\n\nFinal XP: $XP | Gold: $GOLD" 10 45
    fi
}
step2

# ═══════════════════════════════════════════════════════════════
# STEP 3: Check current script to understand dialog usage
# Generated: 2026-01-31 09:15:03 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() { 
    # Find the most recent log file to see what script was run
    ls -la /home/xertrov/src/anything.sh/*.log.sh 2>/dev/null | tail -5
    echo "---"
    # Check the most recent one
    if [ -f /home/xertrov/src/anything.sh/anything_20260131_090038.log.sh ]; then
        head -100 /home/xertrov/src/anything.sh/anything_20260131_090038.log.sh
    fi
}
step3
