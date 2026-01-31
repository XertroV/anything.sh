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
- Never include XML, HTML, or markup tags in bash code
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

    claude -p "$full_prompt" --model sonnet --dangerously-skip-permissions 2>/dev/null
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
# STEP 1: Setup game engine and character creation
# Generated: 2026-01-31 10:38:38 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step1() {
  # Game state variables (persist across steps)
  GAME_DIR="/tmp/bloodborne_adventure_$$"
  mkdir -p "$GAME_DIR"
  
  # Check available tools
  echo "=== System Check ==="
  for tool in gum whiptail fzf pv bat figlet; do
    if command -v "$tool" &>/dev/null; then
      echo "✓ $tool"
    else
      echo "✗ $tool (missing)"
    fi
  done
  
  # Check for figlet - needed for title art
  if ! command -v figlet &>/dev/null; then
    echo ""
    echo "NEED_FIGLET=1"
  else
    echo "NEED_FIGLET=0"
  fi
  
  echo ""
  echo "GAME_DIR=$GAME_DIR"
}
step1

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 10:38:38+11:00 [COMMAND="bash '/tmp/tmp.v5kSjOad4V'" TERM="xterm-256color" TTY="/dev/pts/0" COLUMNS="100" LINES="57"]
# === System Check ===
# ✓ gum
# ✓ whiptail
# ✓ fzf
# ✓ pv
# ✓ bat
# ✗ figlet (missing)
# 
# NEED_FIGLET=1
# 
# GAME_DIR=/tmp/bloodborne_adventure_1059419
# 
# Script done on 2026-01-31 10:38:38+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 2: Create complete game engine with character creation
# Generated: 2026-01-31 10:39:52 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step2() {
  GAME_DIR="${GAME_DIR:-/tmp/bloodborne_adventure_$(date +%s)}"
  mkdir -p "$GAME_DIR"
  
  # Core game state
  declare -g PLAYER_NAME PLAYER_CLASS PLAYER_HP PLAYER_MAX_HP PLAYER_BLOOD PLAYER_INSIGHT
  declare -g PLAYER_STR PLAYER_DEX PLAYER_ARC PLAYER_VIT
  declare -g PLAYER_WEAPON LOCATION CHAPTER
  declare -gA INVENTORY QUESTS
  
  # Game configuration
  GAME_SAVE="$GAME_DIR/save.dat"
  
  # UI Helper Functions
  show_header() {
    local title="$1"
    gum style --border double --border-foreground 166 --padding "0 2" --width 96 --align center "$title"
  }
  
  show_stats() {
    local hp_bar=$(printf '█%.0s' $(seq 1 $((PLAYER_HP * 30 / PLAYER_MAX_HP))) )
    local empty_bar=$(printf '░%.0s' $(seq 1 $((30 - PLAYER_HP * 30 / PLAYER_MAX_HP))) )
    
    gum style --border rounded --border-foreground 160 --padding "1 2" --width 96 \
"╔════════════════════════════════════════════════════════════════════════════════════════════╗
 Name: $(gum style --foreground 220 "$PLAYER_NAME") | Class: $(gum style --foreground 166 "$PLAYER_CLASS") | Location: $(gum style --foreground 67 "$LOCATION")
╠════════════════════════════════════════════════════════════════════════════════════════════╣
 HP: [$(gum style --foreground 196 "$hp_bar")$(gum style --foreground 240 "$empty_bar")] $PLAYER_HP/$PLAYER_MAX_HP
 Blood Echoes: $(gum style --foreground 196 "$PLAYER_BLOOD") | Insight: $(gum style --foreground 165 "$PLAYER_INSIGHT")
╠════════════════════════════════════════════════════════════════════════════════════════════╣
 STR: $(gum style --foreground 208 "$PLAYER_STR") | DEX: $(gum style --foreground 226 "$PLAYER_DEX") | ARC: $(gum style --foreground 141 "$PLAYER_ARC") | VIT: $(gum style --foreground 203 "$PLAYER_VIT")
 Weapon: $(gum style --foreground 215 "$PLAYER_WEAPON")
╚════════════════════════════════════════════════════════════════════════════════════════════╝"
  }
  
  narrate() {
    local text="$1"
    local speed="${2:-30}"
    echo
    echo "$text" | pv -qL "$speed"
    echo
  }
  
  slow_print() {
    echo "$1" | pv -qL "${2:-20}"
  }
  
  combat_system() {
    local enemy_name="$1"
    local enemy_hp=$2
    local enemy_max_hp=$2
    local enemy_dmg=$3
    local enemy_reward=$4
    
    show_header "⚔ COMBAT: $enemy_name ⚔"
    
    while [ $enemy_hp -gt 0 ] && [ $PLAYER_HP -gt 0 ]; do
      show_stats
      echo
      local enemy_hp_pct=$((enemy_hp * 100 / enemy_max_hp))
      local enemy_bar=$(printf '█%.0s' $(seq 1 $((enemy_hp * 30 / enemy_max_hp))) 2>/dev/null)
      local enemy_empty=$(printf '░%.0s' $(seq 1 $((30 - enemy_hp * 30 / enemy_max_hp))) 2>/dev/null)
      
      gum style --foreground 196 "
$enemy_name HP: [$enemy_bar$enemy_empty] $enemy_hp/$enemy_max_hp"
      echo
      
      local action=$(gum choose "⚔ Attack" "🛡 Defend" "💉 Use Blood Vial" "🏃 Flee")
      
      case "$action" in
        "⚔ Attack")
          local hit_chance=$((RANDOM % 100))
          if [ $hit_chance -lt 75 ]; then
            local dmg=$((PLAYER_STR * 3 + PLAYER_DEX * 2 + RANDOM % 10))
            enemy_hp=$((enemy_hp - dmg))
            slow_print "$(gum style --foreground 220 "You strike with $PLAYER_WEAPON dealing $dmg damage!")" 40
            sleep 0.5
          else
            slow_print "$(gum style --foreground 240 "Your attack misses!")" 40
            sleep 0.5
          fi
          ;;
        "🛡 Defend")
          slow_print "$(gum style --foreground 67 "You raise your guard...")" 40
          enemy_dmg=$((enemy_dmg / 2))
          sleep 0.5
          ;;
        "💉 Use Blood Vial")
          if [ "${INVENTORY[blood_vials]:-0}" -gt 0 ]; then
            local heal=$((PLAYER_MAX_HP / 3))
            PLAYER_HP=$((PLAYER_HP + heal))
            [ $PLAYER_HP -gt $PLAYER_MAX_HP ] && PLAYER_HP=$PLAYER_MAX_HP
            INVENTORY[blood_vials]=$((INVENTORY[blood_vials] - 1))
            slow_print "$(gum style --foreground 196 "You consume a Blood Vial, restoring $heal HP!")" 40
            sleep 0.5
          else
            slow_print "$(gum style --foreground 240 "You have no Blood Vials!")" 40
            sleep 0.5
            continue
          fi
          ;;
        "🏃 Flee")
          if [ $((RANDOM % 100)) -lt 40 ]; then
            slow_print "$(gum style --foreground 226 "You successfully fled from combat!")" 40
            return 1
          else
            slow_print "$(gum style --foreground 240 "You failed to escape!")" 40
          fi
          ;;
      esac
      
      if [ $enemy_hp -gt 0 ]; then
        echo
        sleep 0.3
        local enemy_hit=$((RANDOM % 100))
        if [ $enemy_hit -lt 70 ]; then
          PLAYER_HP=$((PLAYER_HP - enemy_dmg))
          slow_print "$(gum style --foreground 196 "The $enemy_name attacks for $enemy_dmg damage!")" 40
        else
          slow_print "$(gum style --foreground 67 "The $enemy_name's attack misses!")" 40
        fi
        sleep 1
      fi
    done
    
    if [ $PLAYER_HP -le 0 ]; then
      show_header "💀 YOU DIED 💀"
      narrate "The echoes of your death ripple through the nightmare..." 25
      narrate "You awaken at the last lantern, your blood echoes lost to the void." 25
      PLAYER_HP=$PLAYER_MAX_HP
      PLAYER_BLOOD=$((PLAYER_BLOOD / 2))
      return 2
    else
      show_header "⚔ VICTORY ⚔"
      PLAYER_BLOOD=$((PLAYER_BLOOD + enemy_reward))
      local insight_gain=$((RANDOM % 3))
      PLAYER_INSIGHT=$((PLAYER_INSIGHT + insight_gain))
      slow_print "$(gum style --foreground 220 "Defeated $enemy_name!")" 30
      slow_print "$(gum style --foreground 196 "+$enemy_reward Blood Echoes")" 30
      [ $insight_gain -gt 0 ] && slow_print "$(gum style --foreground 165 "+$insight_gain Insight")" 30
      sleep 2
      return 0
    fi
  }
  
  # Character Creation
  clear
  show_header "⚙ BLOODBORNE: GEARS OF THE OLD BLOOD ⚙"
  
  narrate "In a city where steam mingles with forbidden blood, where Victorian gaslamps cast shadows upon eldritch machinery, a hunter awakens..." 35
  narrate "The Workshop beckons. The Great Gears turn. Your hunt begins." 35
  
  sleep 1
  
  PLAYER_NAME=$(gum input --placeholder "Enter your Hunter's name..." --prompt "Name: " --width 60)
  [ -z "$PLAYER_NAME" ] && PLAYER_NAME="Nameless Hunter"
  
  echo
  slow_print "$(gum style --foreground 220 "Choose your Origin, Hunter...")" 30
  sleep 0.5
  
  PLAYER_CLASS=$(gum choose \
    "Gear Knight - Master of mechanized combat (High STR, VIT)" \
    "Blood Engineer - Arcane technologist (High ARC, Insight)" \
    "Cogwork Assassin - Swift bladework (High DEX, Speed)" \
    "Plague Doctor - Alchemist & healer (Balanced, Extra Vials)")
  
  case "$PLAYER_CLASS" in
    "Gear Knight"*)
      PLAYER_CLASS="Gear Knight"
      PLAYER_STR=15; PLAYER_DEX=8; PLAYER_ARC=6; PLAYER_VIT=14
      PLAYER_MAX_HP=120; PLAYER_WEAPON="Saw Cleaver"
      ;;
    "Blood Engineer"*)
      PLAYER_CLASS="Blood Engineer"
      PLAYER_STR=8; PLAYER_DEX=10; PLAYER_ARC=15; PLAYER_VIT=10
      PLAYER_MAX_HP=100; PLAYER_WEAPON="Threaded Cane"
      ;;
    "Cogwork Assassin"*)
      PLAYER_CLASS="Cogwork Assassin"
      PLAYER_STR=10; PLAYER_DEX=15; PLAYER_ARC=8; PLAYER_VIT=10
      PLAYER_MAX_HP=100; PLAYER_WEAPON="Hunter's Blade"
      ;;
    "Plague Doctor"*)
      PLAYER_CLASS="Plague Doctor"
      PLAYER_STR=10; PLAYER_DEX=10; PLAYER_ARC=12; PLAYER_VIT=11
      PLAYER_MAX_HP=105; PLAYER_WEAPON="Bone Ash Rapier"
      INVENTORY[blood_vials]=5
      ;;
  esac
  
  PLAYER_HP=$PLAYER_MAX_HP
  PLAYER_BLOOD=0
  PLAYER_INSIGHT=0
  INVENTORY[blood_vials]=${INVENTORY[blood_vials]:-3}
  INVENTORY[quicksilver_bullets]=10
  LOCATION="The Cogwheel Workshop"
  CHAPTER=1
  
  sleep 1
  clear
  show_header "✓ HUNTER CREATED ✓"
  show_stats
  sleep 2
  
  # Chapter 1: The Awakening
  clear
  show_header "CHAPTER 1: THE COGWHEEL WORKSHOP"
  
  narrate "You awaken in the Workshop, surrounded by the rhythmic churning of great brass gears." 30
  narrate "Steam hisses from copper pipes. The scent of oil and old blood fills your lungs." 30
  narrate "A note lies beside you, written in elegant copper-plate script:" 30
  
  sleep 1
  
  gum style --border rounded --border-foreground 166 --padding "1 3" --width 96 \
"
  'Hunter,
  
  The city of Yharnam-Below has fallen to the Scourge of Gears - a plague that fuses
  flesh with metal, blood with steam. The Church of the Clockwork Saints has sealed
  the Upper City, abandoning all below to transformation.
  
  Your first task: Venture to the Gaslight District. Find the Bonfire Lantern.
  Light it. Only then can you begin to hunt the Afflicted.
  
  May the Good Gears guide your blade.
  
  - Gehrman, First Hunter'
"
  
  sleep 2
  echo
  
  local choice=$(gum choose \
    "⚙ Examine the Workshop" \
    "🗡 Check your weapon" \
    "🚪 Leave for the Gaslight District")
  
  case "$choice" in
    "⚙ Examine the Workshop")
      narrate "The Workshop is filled with half-assembled contraptions: clockwork limbs, blood-fueled engines, brass augments." 30
      narrate "You find a small brass gear. It hums with faint warmth." 30
      INVENTORY[mysterious_gear]=1
      PLAYER_INSIGHT=$((PLAYER_INSIGHT + 1))
      slow_print "$(gum style --foreground 165 '+1 Insight: The gears whisper secrets...')" 25
      sleep 2
      ;;
    "🗡 Check your weapon")
      narrate "Your $PLAYER_WEAPON gleams in the lamplight. Well-maintained. Deadly." 30
      narrate "Attached is a small vial of quicksilver - the Church's gift to all hunters." 30
      sleep 2
      ;;
  esac
  
  echo
  narrate "You step through the iron door into the perpetual twilight of Yharnam-Below..." 30
  
  LOCATION="Gaslight District - Entrance"
  sleep 2
  clear
  show_stats
  
  narrate "The street is cobblestone and shadow. Gas lamps flicker weakly. In the distance, you hear the grinding of metal on bone." 30
  narrate "A figure stumbles from an alley - once human, now twisted. Gears protrude from its chest, pistons pump where lungs should be." 30
  
  sleep 1
  slow_print "$(gum style --foreground 196 --bold 'THE AFFLICTED ONE NOTICES YOU.')" 25
  sleep 1
  
  # First combat
  combat_system "Gear-Twisted Wretch" 40 8 50
  
  combat_result=$?
  
  if [ $combat_result -eq 0 ]; then
    echo
    narrate "The creature falls, its gears grinding to a halt. Black ichor pools beneath it." 30
    narrate "Ahead, you see the Bonfire Lantern - an ornate brass structure wreathed in blue flame." 30
    
    sleep 1.5
    echo
    local action=$(gum choose "Light the Bonfire Lantern" "Search the nearby bodies" "Continue cautiously")
    
    case "$action" in
      "Light the Bonfire Lantern")
        clear
        show_header "🔥 BONFIRE LANTERN LIT 🔥"
        narrate "You place your hand upon the lantern. Azure flames surge through the brass channels." 30
        narrate "A warmth spreads through you. Your wounds close. Your blood echoes resonate." 30
        PLAYER_HP=$PLAYER_MAX_HP
        INVENTORY[blood_vials]=$((INVENTORY[blood_vials] + 2))
        slow_print "$(gum style --foreground 67 'Checkpoint activated. You may rest here.')" 25
        QUESTS[find_lantern]="complete"
        PLAYER_INSIGHT=$((PLAYER_INSIGHT + 2))
        sleep 2
        ;;
      "Search the nearby bodies")
        narrate "Among the corpses, you find supplies left by less fortunate hunters." 30
        INVENTORY[blood_vials]=$((INVENTORY[blood_vials] + 2))
        PLAYER_BLOOD=$((PLAYER_BLOOD + 25))
        slow_print "$(gum style --foreground 196 'Found: 2 Blood Vials, 25 Blood Echoes')" 25
        sleep 1.5
        ;;
    esac
  fi
  
  echo
  echo
  show_stats
  echo
  
  # State summary for next iteration
  slow_print "$(gum style --foreground 220 '=== CHAPTER 1 PROGRESS ===')" 20
  echo "Hunter $PLAYER_NAME has reached the Gaslight District."
  echo "Bonfire Lantern: ${QUESTS[find_lantern]:-not_lit}"
  echo "Blood Vials: ${INVENTORY[blood_vials]}"
  echo "Current HP: $PLAYER_HP/$PLAYER_MAX_HP"
  echo "Blood Echoes: $PLAYER_BLOOD"
  echo "Insight: $PLAYER_INSIGHT"
  echo
  echo "The hunt continues..."
}

step2

# ───────────────────────────────────────────────────────────────
# OUTPUT FROM PREVIOUS STEP:
# ───────────────────────────────────────────────────────────────
# Script started on 2026-01-31 10:39:52+11:00 [COMMAND="bash '/tmp/tmp.g4WHIwqp0T'" TERM="xterm-256color" TTY="/dev/pts/0" COLUMNS="100" LINES="57"]
# ]11;?\[6n╔════════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                             ⚙ BLOODBORNE: GEARS OF THE OLD BLOOD ⚙                             ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
# 
# In a city where steam mingles with forbidden blood, where Victorian gaslamps cast shadows upon eldritch machinery, a hunter awakens...
# 
# 
# The Workshop beckons. The Great Gears turn. Your hunt begins.
# 
# [?25l[?2004h[?1004hName: Enter your Hunter's name...                                  
#                                                                    
# enter submit                                                       [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: Enter your Hunter's name...                                  
# 
# [100D[2AName: B                                                            
# 
# [100D[2AName: Bl                                                           
# 
# [100D[2AName: Blo                                                          
# 
# [100D[2AName: Bloo                                                         
# 
# [100D[2AName: Blood                                                        
# 
# [100D[2AName: Bloodf                                                       
# 
# [100D[2AName: Bloodfi                                                      
# 
# [100D[2AName: Bloodfie                                                     
# 
# [100D[2AName: Bloodfien                                                    
# 
# [100D[2AName: Bloodfiend                                                   
# 
# [100D[2AName: Bloodfiend                                                   
# 
# [100D[2A [100D[?2004l[?25h[?1002l[?1003l[?1006l[?1004l
# Choose your Origin, Hunter...
# [?25l[?2004hChoose:                                                     
# > Gear Knight - Master of mechanized combat (High STR, VIT) 
#   Blood Engineer - Arcane technologist (High ARC, Insight)  
#   Cogwork Assassin - Swift bladework (High DEX, Speed)      
#   Plague Doctor - Alchemist & healer (Balanced, Extra Vials)
#                                                             
#                                                             
# ←↓↑→ navigate • enter submit                                [100D[7A
#   Gear Knight - Master of mechanized combat (High STR, VIT) 
# > Blood Engineer - Arcane technologist (High ARC, Insight)  
# 
# 
# 
# 
# [100D[7A
# 
#   Blood Engineer - Arcane technologist (High ARC, Insight)  
# > Cogwork Assassin - Swift bladework (High DEX, Speed)      
# 
# 
# 
# [100D[7A
# 
# 
#   Cogwork Assassin - Swift bladework (High DEX, Speed)      
# > Plague Doctor - Alchemist & healer (Balanced, Extra Vials)
# 
# 
# [100D[7A
# 
# 
# > Cogwork Assassin - Swift bladework (High DEX, Speed)      
#   Plague Doctor - Alchemist & healer (Balanced, Extra Vials)
# 
# 
# [100D[7A
# 
# > Blood Engineer - Arcane technologist (High ARC, Insight)  
#   Cogwork Assassin - Swift bladework (High DEX, Speed)      
# 
# 
# 
# [100D[7A
# > Gear Knight - Master of mechanized combat (High STR, VIT) 
#   Blood Engineer - Arcane technologist (High ARC, Insight)  
# 
# 
# 
# 
# [100D[7A
#   Gear Knight - Master of mechanized combat (High STR, VIT) 
# > Blood Engineer - Arcane technologist (High ARC, Insight)  
# 
# 
# 
# 
# [100D[7A
# 
#   Blood Engineer - Arcane technologist (High ARC, Insight)  
# > Cogwork Assassin - Swift bladework (High DEX, Speed)      
# 
# 
# 
# [100D[7A
# 
# 
#   Cogwork Assassin - Swift bladework (High DEX, Speed)      
# > Plague Doctor - Alchemist & healer (Balanced, Extra Vials)
# 
# 
# [100D[7A [100D[?2004l[?25h[?1002l[?1003l[?1006l]11;?\[6n╔════════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                       ✓ HUNTER CREATED ✓                                       ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
# ]11;?\[6n╭────────────────────────────────────────────────────────────────────────────────────────────────╮
# │                                                                                                │
# │  ╔═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╗                                                                                            │
# │   Name: Bloodfiend | Class: Plague Doctor | Location: The Cogwheel Workshop                    │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   HP: [██████████████████████████████░] 105/105                                                │
# │   Blood Echoes: 0 | Insight: 0                                                                 │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   STR: 10 | DEX: 10 | ARC: 12 | VIT: 11                                                        │
# │   Weapon: Bone Ash Rapier                                                                      │
# │  ╚═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╝                                                                                            │
# │                                                                                                │
# ╰────────────────────────────────────────────────────────────────────────────────────────────────╯
# ]11;?\[6n╔════════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                CHAPTER 1: THE COGWHEEL WORKSHOP                                ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
# 
# You awaken in the Workshop, surrounded by the rhythmic churning of great brass gears.
# 
# 
# Steam hisses from copper pipes. The scent of oil and old blood fills your lungs.
# 
# 
# A note lies beside you, written in elegant copper-plate script:
# 
# ]11;?\[6n╭────────────────────────────────────────────────────────────────────────────────────────────────╮
# │                                                                                                │
# │                                                                                                │
# │     'Hunter,                                                                                   │
# │                                                                                                │
# │     The city of Yharnam-Below has fallen to the Scourge of Gears - a plague that fuses         │
# │     flesh with metal, blood with steam. The Church of the Clockwork Saints has sealed          │
# │     the Upper City, abandoning all below to transformation.                                    │
# │                                                                                                │
# │     Your first task: Venture to the Gaslight District. Find the Bonfire Lantern.               │
# │     Light it. Only then can you begin to hunt the Afflicted.                                   │
# │                                                                                                │
# │     May the Good Gears guide your blade.                                                       │
# │                                                                                                │
# │     - Gehrman, First Hunter'                                                                   │
# │                                                                                                │
# │                                                                                                │
# ╰────────────────────────────────────────────────────────────────────────────────────────────────╯
# 
# [?25l[?2004hChoose:                             
# > ⚙ Examine the Workshop            
#   🗡 Check your weapon               
#   🚪 Leave for the Gaslight District
#                                     
#                                     
# ←↓↑→ navigate • enter submit        [100D[6A [100D[?2004l[?25h[?1002l[?1003l[?1006l
# The Workshop is filled with half-assembled contraptions: clockwork limbs, blood-fueled engines, brass augments.
# 
# 
# You find a small brass gear. It hums with faint warmth.
# 
# +1 Insight: The gears whisper secrets...
# 
# 
# You step through the iron door into the perpetual twilight of Yharnam-Below...
# 
# ]11;?\[6n╭────────────────────────────────────────────────────────────────────────────────────────────────╮
# │                                                                                                │
# │  ╔═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╗                                                                                            │
# │   Name: Bloodfiend | Class: Plague Doctor | Location: Gaslight District - Entrance             │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   HP: [██████████████████████████████░] 105/105                                                │
# │   Blood Echoes: 0 | Insight: 1                                                                 │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   STR: 10 | DEX: 10 | ARC: 12 | VIT: 11                                                        │
# │   Weapon: Bone Ash Rapier                                                                      │
# │  ╚═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╝                                                                                            │
# │                                                                                                │
# ╰────────────────────────────────────────────────────────────────────────────────────────────────╯
# 
# The street is cobblestone and shadow. Gas lamps flicker weakly. In the distance, you hear the grinding of metal on bone.
# 
# 
# A figure stumbles from an alley - once human, now twisted. Gears protrude from its chest, pistons pump where lungs should be.
# 
# THE AFFLICTED ONE NOTICES YOU.
# ]11;?\[6n╔════════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                ⚔ COMBAT: Gear-Twisted Wretch ⚔                                 ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
# ]11;?\[6n╭────────────────────────────────────────────────────────────────────────────────────────────────╮
# │                                                                                                │
# │  ╔═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╗                                                                                            │
# │   Name: Bloodfiend | Class: Plague Doctor | Location: Gaslight District - Entrance             │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   HP: [██████████████████████████████░] 105/105                                                │
# │   Blood Echoes: 0 | Insight: 1                                                                 │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   STR: 10 | DEX: 10 | ARC: 12 | VIT: 11                                                        │
# │   Weapon: Bone Ash Rapier                                                                      │
# │  ╚═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╝                                                                                            │
# │                                                                                                │
# ╰────────────────────────────────────────────────────────────────────────────────────────────────╯
# 
# ]11;?\[6n                                                               
# Gear-Twisted Wretch HP: [██████████████████████████████░] 40/40
# 
# [?25l[?2004hChoose:                     
# > ⚔ Attack                  
#   🛡 Defend                  
#   💉 Use Blood Vial         
#   🏃 Flee                   
#                             
#                             
# ←↓↑→ navigate • enter submit[100D[7A [100D[?2004l[?25h[?1002l[?1003l[?1006lYou strike with Bone Ash Rapier dealing 54 damage!
# ]11;?\[6n╔════════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                          ⚔ VICTORY ⚔                                           ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
# Defeated Gear-Twisted Wretch!
# +50 Blood Echoes
# 
# 
# The creature falls, its gears grinding to a halt. Black ichor pools beneath it.
# 
# 
# Ahead, you see the Bonfire Lantern - an ornate brass structure wreathed in blue flame.
# 
# 
# [?25l[?2004hChoose:                     
# > Light the Bonfire Lantern 
#   Search the nearby bodies  
#   Continue cautiously       
#                             
#                             
# ←↓↑→ navigate • enter submit[100D[6A [100D[?2004l[?25h[?1002l[?1003l[?1006l]11;?\[6n╔════════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                   🔥 BONFIRE LANTERN LIT 🔥                                    ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
# 
# You place your hand upon the lantern. Azure flames surge through the brass channels.
# 
# 
# A warmth spreads through you. Your wounds close. Your blood echoes resonate.
# 
# Checkpoint activated. You may rest here.
# 
# 
# ]11;?\[6n╭────────────────────────────────────────────────────────────────────────────────────────────────╮
# │                                                                                                │
# │  ╔═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╗                                                                                            │
# │   Name: Bloodfiend | Class: Plague Doctor | Location: Gaslight District - Entrance             │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   HP: [██████████████████████████████░] 105/105                                                │
# │   Blood Echoes: 50 | Insight: 3                                                                │
# │  ╠═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╣                                                                                            │
# │   STR: 10 | DEX: 10 | ARC: 12 | VIT: 11                                                        │
# │   Weapon: Bone Ash Rapier                                                                      │
# │  ╚═══════════════════════════════════════════════════════════════════════════════════════════  │
# │  ═╝                                                                                            │
# │                                                                                                │
# ╰────────────────────────────────────────────────────────────────────────────────────────────────╯
# 
# === CHAPTER 1 PROGRESS ===
# Hunter Bloodfiend has reached the Gaslight District.
# Bonfire Lantern: complete
# Blood Vials: 7
# Current HP: 105/105
# Blood Echoes: 50
# Insight: 3
# 
# The hunt continues...
# 
# Script done on 2026-01-31 10:44:44+11:00 [COMMAND_EXIT_CODE="0"]

# ═══════════════════════════════════════════════════════════════
# STEP 3: Continue adventure - explore deeper into district
# Generated: 2026-01-31 10:45:38 | FINAL: false
# ═══════════════════════════════════════════════════════════════
step3() {
    clear
    
    # Persistent state
    HUNTER_NAME="Bloodfiend"
    HUNTER_CLASS="Plague Doctor"
    HP=105
    MAX_HP=105
    BLOOD_ECHOES=50
    INSIGHT=3
    STR=10
    DEX=10
    ARC=12
    VIT=11
    BLOOD_VIALS=7
    LOCATION="Gaslight District - Market Square"
    
    # Display header
    figlet -f standard "GEARS OF THE OLD BLOOD" | sed 's/^/  /' | gum style --border double --border-foreground 208 --padding "0 2"
    echo
    
    # Show updated status
    show_status() {
        local hp_percent=$((HP * 30 / MAX_HP))
        local hp_bar=$(printf "█%.0s" $(seq 1 $hp_percent))
        local hp_empty=$(printf "░%.0s" $(seq 1 $((30 - hp_percent))))
        
        gum style --border rounded --padding "1 2" --border-foreground 141 \
"╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
 Name: $HUNTER_NAME | Class: $HUNTER_CLASS | Location: $LOCATION
╠═══════════════════════════════════════════════════════════════════════════════════════════════╣
 HP: [$hp_bar$hp_empty] $HP/$MAX_HP
 Blood Echoes: $BLOOD_ECHOES | Insight: $INSIGHT | Blood Vials: $BLOOD_VIALS
╠═══════════════════════════════════════════════════════════════════════════════════════════════╣
 STR: $STR | DEX: $DEX | ARC: $ARC | VIT: $VIT
 Weapon: Bone Ash Rapier
╚═══════════════════════════════════════════════════════════════════════════════════════════════╝"
    }
    
    show_status
    echo
    
    # Narrative
    gum style --foreground 147 "
The Bonfire's azure glow fades behind you as you venture deeper into the Market Square.

Stalls stand abandoned, their wares scattered: rusted clockwork toys, vials of crimson liquid,
prayer books bound in copper. The air grows thick with steam.

A SOUND - rhythmic clanking, like chains dragging across stone..." | pv -qL 80
    
    echo
    sleep 1
    
    gum style --foreground 196 --bold "
THREE FIGURES emerge from the mist:

→ A Gear-Scourged Merchant, its jaw replaced by spinning blades
→ Two Clockwork Hounds, brass and teeth, eyes glowing furnace-red"
    
    echo
    sleep 2
    
    # Combat choice
    echo
    COMBAT_CHOICE=$(gum choose --header "⚔ COMBAT ENCOUNTER ⚔" \
        "⚔ Fight - Engage all three enemies" \
        "🎯 Focus Fire - Attack the Merchant first" \
        "💨 Arcane Blast - Use ARC to damage all (costs Insight)" \
        "🏃 Tactical Retreat - Fall back to Bonfire")
    
    echo
    
    case "$COMBAT_CHOICE" in
        *"Fight"*)
            gum style --foreground 214 "You raise your Bone Ash Rapier and charge into the fray!" | pv -qL 60
            sleep 1
            echo
            
            # Simulate combat
            gum spin --spinner dot --title "Combat in progress..." -- sleep 2
            
            DAMAGE_TAKEN=$((RANDOM % 30 + 20))
            HP=$((HP - DAMAGE_TAKEN))
            ECHOES_GAINED=120
            BLOOD_ECHOES=$((BLOOD_ECHOES + ECHOES_GAINED))
            
            figlet -f small "VICTORY" | gum style --foreground 46 --bold
            echo
            gum style --foreground 184 "
A brutal melee! The Hounds lunged in tandem while the Merchant's blade-jaw gnashed.

You danced between strikes, your rapier finding gaps in brass plating:
  → Hound 1: Pierced through the furnace-core (32 damage)
  → Hound 2: Severed hydraulic neck joint (28 damage)
  → Merchant: Final thrust through the vocal apparatus (46 damage)

The enemies collapse in a symphony of grinding gears and hissing steam."
            
            echo
            gum style --foreground 208 --bold "Damage Taken: -$DAMAGE_TAKEN HP"
            gum style --foreground 220 --bold "+$ECHOES_GAINED Blood Echoes"
            echo
            
            # Loot
            sleep 1
            gum style --foreground 141 "
You search the bodies...

Found:
  → Cogwork Merchant's Ledger (Insight +1)
  → 2x Blood Vials
  → Rusted Gear Shard (quest item?)"
            
            INSIGHT=$((INSIGHT + 1))
            BLOOD_VIALS=$((BLOOD_VIALS + 2))
            echo
            ;;
            
        *"Focus Fire"*)
            gum style --foreground 214 "You target the Merchant with precise strikes!" | pv -qL 60
            sleep 1
            echo
            
            gum spin --spinner dot --title "Combat in progress..." -- sleep 2
            
            DAMAGE_TAKEN=$((RANDOM % 20 + 15))
            HP=$((HP - DAMAGE_TAKEN))
            ECHOES_GAINED=120
            BLOOD_ECHOES=$((BLOOD_ECHOES + ECHOES_GAINED))
            
            figlet -f small "VICTORY" | gum style --foreground 46 --bold
            echo
            gum style --foreground 184 "
Smart tactics! You focused on the Merchant, driving your rapier through its chest cavity.

With the leader fallen, the Hounds hesitated - just long enough for you to strike:
  → Merchant: Three rapid thrusts to the core (51 damage)
  → Hound 1: Riposte after its confused lunge (29 damage)
  → Hound 2: Finishing blow as it attempted to flee (24 damage)"
            
            echo
            gum style --foreground 208 --bold "Damage Taken: -$DAMAGE_TAKEN HP (smart approach!)"
            gum style --foreground 220 --bold "+$ECHOES_GAINED Blood Echoes"
            echo
            
            sleep 1
            gum style --foreground 141 "
You search the bodies...

Found:
  → Cogwork Merchant's Ledger (Insight +1)
  → 2x Blood Vials
  → Rusted Gear Shard (quest item?)"
            
            INSIGHT=$((INSIGHT + 1))
            BLOOD_VIALS=$((BLOOD_VIALS + 2))
            echo
            ;;
            
        *"Arcane Blast"*)
            gum style --foreground 141 "You channel arcane energy through the gears themselves..." | pv -qL 60
            sleep 1
            echo
            
            gum spin --spinner dot --title "Channeling arcane power..." -- sleep 2
            
            INSIGHT=$((INSIGHT - 1))
            DAMAGE_TAKEN=$((RANDOM % 15 + 5))
            HP=$((HP - DAMAGE_TAKEN))
            ECHOES_GAINED=150
            BLOOD_ECHOES=$((BLOOD_ECHOES + ECHOES_GAINED))
            
            figlet -f small "ARCANE VICTORY" | gum style --foreground 99 --bold
            echo
            gum style --foreground 147 "
You raise your hand and speak words that predate the gears, predate flesh itself.

The enemies' mechanical augmentations turn against them - gears reversing, pistons seizing:
  → Area Arcane Damage: 68 total
  → All three enemies convulse and collapse simultaneously
  → The Merchant's blade-jaw shatters in a shower of bronze shrapnel

An elegant, if costly, solution."
            
            echo
            gum style --foreground 99 --bold "Insight Spent: -1 (Current: $INSIGHT)"
            gum style --foreground 208 "Damage Taken: -$DAMAGE_TAKEN HP (minimal)"
            gum style --foreground 220 --bold "+$ECHOES_GAINED Blood Echoes (Arcane Mastery bonus!)"
            echo
            
            sleep 1
            gum style --foreground 141 "
You search the bodies...

Found:
  → Cogwork Merchant's Ledger (Insight +2 - arcane resonance)
  → 3x Blood Vials
  → Rusted Gear Shard (quest item?)
  → Essence of Steam (rare crafting material)"
            
            INSIGHT=$((INSIGHT + 2))
            BLOOD_VIALS=$((BLOOD_VIALS + 3))
            echo
            ;;
            
        *"Tactical Retreat"*)
            gum style --foreground 220 "You retreat to the Bonfire Lantern..." | pv -qL 60
            sleep 1
            echo
            
            gum style --foreground 184 "
A wise Hunter knows when to withdraw.

You sprint back through the fog, the Hounds' brass claws scraping cobblestones behind you.

You reach the Bonfire. Its azure flames surge protectively - the enemies halt at its boundary,
their furnace-eyes dimming. They retreat into shadow.

Safe... for now."
            
            echo
            gum style --foreground 141 "HP Restored. Enemies still lurk ahead."
            HP=105
            echo
            ;;
    esac
    
    sleep 2
    echo
    show_status
    echo
    
    # Next choice
    gum style --foreground 147 "
Ahead, the Market Square opens onto three paths:

  🌉 NORTH: The Bridge of Chains - sounds of industry echo across it
  🏚 EAST: The Abandoned Manufactory - silent, but something glows within  
  ⛪ WEST: The Chapel of Cogs - hymns sung in binary drift from broken windows"
    
    echo
    sleep 1
    
    DIRECTION=$(gum choose --header "Choose your path, Hunter..." \
        "🌉 Cross the Bridge of Chains" \
        "🏚 Enter the Abandoned Manufactory" \
        "⛪ Investigate the Chapel of Cogs" \
        "🔥 Return to Bonfire and rest")
    
    echo
    gum style --foreground 220 --bold "You chose: $DIRECTION"
    echo
    
    # Store state for next iteration
    echo "=== STATE FOR NEXT STEP ==="
    echo "HP: $HP/$MAX_HP"
    echo "Blood Echoes: $BLOOD_ECHOES"
    echo "Insight: $INSIGHT"
    echo "Blood Vials: $BLOOD_VIALS"
    echo "Next Location: $DIRECTION"
    echo "Chapter 1 continues..."
}

step3
