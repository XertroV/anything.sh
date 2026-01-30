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
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
[[ -n "${1:-}" ]] && _evolve "$1" || _prompt
#


# ═══════════════════════════════════════════════════════════════
# STEP 1: install doom for me
# Generated: 2026-01-31 08:03:53
# ═══════════════════════════════════════════════════════════════
step1() {
  # Install Chocolate Doom (a popular, easy-to-install Doom source port)
  if command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm chocolate-doom freedoom
  elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y chocolate-doom freedoom
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y chocolate-doom freedoom
  else
    echo "Package manager not recognized. Please install chocolate-doom manually."
    return 1
  fi
  echo "Doom installed! Run 'chocolate-doom' or 'chocolate-doom -iwad /usr/share/games/doom/freedoom1.wad' to play."
}
step1

_prompt
#
