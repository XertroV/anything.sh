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

SYSTEM: $(uname -sm) | $SHELL | $PWD

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
# STEP 1: joke factory
# Generated: 2026-01-31 07:55:29
# ═══════════════════════════════════════════════════════════════
```bash
joke_factory() {
  local jokes=(
    "Why do programmers prefer dark mode? Because light attracts bugs."
    "A SQL query walks into a bar, walks up to two tables and asks: 'Can I join you?'"
    "Why do Java developers wear glasses? Because they can't C#."
    "There are only 10 types of people in the world: those who understand binary and those who don't."
    "Why was the JavaScript developer sad? Because he didn't Node how to Express himself."
    "A programmer's wife tells him: 'Go to the store and get a loaf of bread. If they have eggs, get a dozen.' He comes back with 12 loaves of bread."
    "Why do Linux admins make terrible poets? They can only write in bash."
    "What's a programmer's favorite hangout place? Foo Bar."
    "Why did the developer go broke? Because he used up all his cache."
    "What do you call 8 hobbits? A hobbyte."
  )
  local idx=$((RANDOM % ${#jokes[@]}))
  echo "🏭 Joke Factory Output:"
  echo "━━━━━━━━━━━━━━━━━━━━━━"
  echo "${jokes[$idx]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━"
}
joke_factory
```

_prompt
#
