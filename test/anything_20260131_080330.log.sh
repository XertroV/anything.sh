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

SYSTEM: $(uname -sm) | $SHELL | $PWD | $(date '+%Y-%m-%d %H:%M')

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
# EVOLVE: Append generated code to script
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    ((STEP++))
    echo -e "\033[32m[step $STEP]\033[0m $intent"

    local code=$(_ask "$intent")
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
    read -rp $'\033[35m  what shall I become? \033[0m' input || exit 0
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
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
[[ -n "${1:-}" ]] && _evolve "$1" || _prompt
#


# ═══════════════════════════════════════════════════════════════
# STEP 1: a joke factory
# Generated: 2026-01-31 07:58:42
# ═══════════════════════════════════════════════════════════════
joke_factory() {
  local jokes=(
    "Why do programmers prefer dark mode? Because light attracts bugs."
    "A SQL query walks into a bar, walks up to two tables and asks... 'Can I join you?'"
    "Why do Java developers wear glasses? Because they can't C#."
    "There are only 10 types of people in the world: those who understand binary and those who don't."
    "Why was the JavaScript developer sad? Because he didn't Node how to Express himself."
    "A programmer's wife tells him: 'Go to the store and buy a loaf of bread. If they have eggs, buy a dozen.' He comes home with 12 loaves of bread."
    "Why do programmers hate nature? It has too many bugs."
    "['hip', 'hip'] - what's that? A hip hip array!"
    "Why did the developer go broke? Because he used up all his cache."
    "What's a programmer's favorite hangout place? Foo Bar."
  )
  
  local random_index=$((RANDOM % ${#jokes[@]}))
  
  echo "🏭 JOKE FACTORY 🏭"
  echo "===================="
  echo ""
  echo "${jokes[$random_index]}"
  echo ""
  echo "===================="
}
joke_factory

_prompt
#

# ═══════════════════════════════════════════════════════════════
# STEP 2: doom installer
# Generated: 2026-01-31 08:00:10
# ═══════════════════════════════════════════════════════════════
step2() {
  echo "Installing Doom..."
  
  # Check for chocolate-doom or freedoom
  if command -v chocolate-doom &>/dev/null; then
    echo "chocolate-doom already installed"
  elif command -v doom &>/dev/null; then
    echo "doom already installed"
  else
    # Detect package manager and install
    if command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm chocolate-doom freedoom
    elif command -v apt &>/dev/null; then
      sudo apt update && sudo apt install -y chocolate-doom freedoom
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y chocolate-doom freedoom
    elif command -v brew &>/dev/null; then
      brew install chocolate-doom
      brew install --cask freedoom
    else
      echo "Error: No supported package manager found"
      return 1
    fi
  fi
  
  echo "Doom installation complete!"
  echo "Run 'chocolate-doom' or check for freedoom WADs in /usr/share/games/doom/"
}
step2

_prompt
#

# ═══════════════════════════════════════════════════════════════
# STEP 3: doom installer using pacman
# Generated: 2026-01-31 08:00:31
# ═══════════════════════════════════════════════════════════════
step3() {
  echo "Installing Doom using pacman..."
  sudo pacman -S --noconfirm chocolate-doom freedoom
  echo "Doom installed successfully!"
  echo "Run 'chocolate-doom' or 'freedoom' to play"
}
step3

_prompt
#

# ═══════════════════════════════════════════════════════════════
# STEP 4: install doom on arch linux
# Generated: 2026-01-31 08:01:10
# ═══════════════════════════════════════════════════════════════
step4() {
  # Install Doom (the classic game) via the open source port
  sudo pacman -S --noconfirm chocolate-doom freedoom
  
  echo "Doom installed! Run with: chocolate-doom -iwad /usr/share/games/freedoom/freedoom1.wad"
}
step4

_prompt
#
