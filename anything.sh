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
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
You are a bash code generator. Your output is appended directly to a running bash script and executed immediately.

CRITICAL: Output ONLY raw bash code. No markdown. No explanation. No \`\`\`. Just code.

SYSTEM: $(uname -sm) $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | $SHELL | $PWD

TASK: $intent

FORMAT:
step${STEP}() {
  # your implementation
}
step${STEP}

WRONG (DO NOT DO THIS):
  Here's the code:
  \`\`\`bash
  step1() { echo "hi"; }
  \`\`\`

RIGHT (DO THIS):
step${STEP}() { echo "hi"; }
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
# EVOLVE: Append generated code to script
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    ((STEP++))
    echo -e "\033[32m[step $STEP]\033[0m $intent"

    # Start spinner in background
    _spinner &
    local spinner_pid=$!

    local code=$(_ask "$intent")

    # Stop spinner
    kill $spinner_pid 2>/dev/null
    wait $spinner_pid 2>/dev/null
    printf "\r\033[K"
    # Extract code from markdown fences if present, otherwise use as-is
    if echo "$code" | grep -q '^```'; then
        code=$(echo "$code" | sed -n '/^```/,/^```/p' | sed '/^```/d')
    fi
    if [[ -z "$code" ]]; then
        echo -e "\033[31m[error]\033[0m empty response"
        return 1
    fi

    local lines=$(echo "$code" | wc -l)
    echo -e "\033[33m[+$lines lines]\033[0m"

    # Append: comment header, generated code, then _prompt for next iteration
    cat >> "$SELF" <<EVOLUTION

# ═══════════════════════════════════════════════════════════════
# STEP $STEP: $intent
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ═══════════════════════════════════════════════════════════════
$code

_prompt
#
EVOLUTION
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
# STEP 1: doom
# Generated: 2026-01-31 08:07:38
# ═══════════════════════════════════════════════════════════════
doom_game() {
  # ASCII Doom-like game using bash
  clear
  
  # Check for required tools
  if ! command -v tput &> /dev/null; then
    echo "Error: tput required for this game"
    return 1
  fi
  
  # Hide cursor and setup
  tput civis
  trap 'tput cnorm; tput reset; exit' INT TERM EXIT
  
  # Game variables
  local width=$(tput cols)
  local height=$(tput lines)
  local px=5.0 py=5.0  # Player position
  local pa=0.0         # Player angle
  local mapW=16 mapH=16
  local fov=3.14159/4  # Field of view
  local depth=16.0
  
  # Simple map
  local map=""
  map+="################"
  map+="#..............#"
  map+="#..............#"
  map+="#....####......#"
  map+="#....#..#......#"
  map+="#....#..#......#"
  map+="#....####......#"
  map+="#..............#"
  map+="#.......########"
  map+="#..............#"
  map+="#..............#"
  map+="###............#"
  map+="#..............#"
  map+="#......###.....#"
  map+="#..............#"
  map+="################"
  
  echo "DOOM-LITE: WASD to move, Q/E to turn, X to quit"
  sleep 2
  
  while true; do
    clear
    local screen=""
    
    # Raycasting loop
    for ((x=0; x<width; x++)); do
      local rayAngle=$(echo "$pa - $fov/2 + $fov * $x / $width" | bc -l)
      
      local distWall=0
      local hitWall=0
      local eyeX=$(echo "s($rayAngle)" | bc -l)
      local eyeY=$(echo "c($rayAngle)" | bc -l)
      
      while [[ $hitWall -eq 0 ]] && (( $(echo "$distWall < $depth" | bc -l) )); do
        distWall=$(echo "$distWall + 0.1" | bc -l)
        local testX=$(echo "$px + $eyeX * $distWall" | bc -l | cut -d. -f1)
        local testY=$(echo "$py + $eyeY * $distWall" | bc -l | cut -d. -f1)
        
        if [[ $testX -lt 0 || $testX -ge $mapW || $testY -lt 0 || $testY -ge $mapH ]]; then
          hitWall=1
          distWall=$depth
        else
          local idx=$((testY * mapW + testX))
          if [[ "${map:$idx:1}" == "#" ]]; then
            hitWall=1
          fi
        fi
      done
      
      local ceiling=$(echo "($height/2) - $height / $distWall" | bc -l | cut -d. -f1)
      local floor=$((height - ceiling))
      [[ $ceiling -lt 0 ]] && ceiling=0
      [[ $floor -gt $height ]] && floor=$height
      
      for ((y=0; y<height-2; y++)); do
        if [[ $y -lt $ceiling ]]; then
          printf " "
        elif [[ $y -le $floor ]]; then
          if (( $(echo "$distWall < $depth/4" | bc -l) )); then
            printf "█"
          elif (( $(echo "$distWall < $depth/3" | bc -l) )); then
            printf "▓"
          elif (( $(echo "$distWall < $depth/2" | bc -l) )); then
            printf "▒"
          elif (( $(echo "$distWall < $depth" | bc -l) )); then
            printf "░"
          else
            printf " "
          fi
        else
          printf "."
        fi
      done
    done
    
    # Input handling
    read -rsn1 -t 0.05 key
    case $key in
      w) px=$(echo "$px + s($pa)*0.5" | bc -l); py=$(echo "$py + c($pa)*0.5" | bc -l) ;;
      s) px=$(echo "$px - s($pa)*0.5" | bc -l); py=$(echo "$py - c($pa)*0.5" | bc -l) ;;
      a) px=$(echo "$px + c($pa)*0.5" | bc -l); py=$(echo "$py - s($pa)*0.5" | bc -l) ;;
      d) px=$(echo "$px - c($pa)*0.5" | bc -l); py=$(echo "$py + s($pa)*0.5" | bc -l) ;;
      q) pa=$(echo "$pa - 0.2" | bc -l) ;;
      e) pa=$(echo "$pa + 0.2" | bc -l) ;;
      x) break ;;
    esac
  done
  
  tput cnorm
  echo "Thanks for playing DOOM-LITE!"
}
doom_game

_prompt
#
