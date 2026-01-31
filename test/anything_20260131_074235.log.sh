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
[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG" && echo -e "\\033[36m[backup]\\033[0m $ORIG"

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
    echo -e "\\033[36m[archived]\\033[0m $archive"
    echo -e "\\033[36m[restored]\\033[0m $SELF"
    exit $rc
}
trap _cleanup EXIT

# ─────────────────────────────────────────────────────────────────
# ORACLE: Query Claude with script context
# ─────────────────────────────────────────────────────────────────
_ask() {
    local intent="$1"
    local full_prompt="You are part of an AUTOPOIETIC, SELF-MODIFYING EXECUTION LOOP.

This bash script appends your output to itself and executes it immediately.

TASK: $intent

OUTPUT FORMAT - You MUST output:
1. Any helper functions needed (optional)
2. A main function named step${STEP} that implements the task
3. A call to that function

Example:
deps_step${STEP}() { echo "helper"; }
step${STEP}() { deps_step${STEP}; echo "doing task"; }
step${STEP}

RULES:
- Output ONLY valid bash code - NO markdown, NO explanation, NO \`\`\`
- Your code is appended to this script and runs immediately
- Available: _ask, _evolve, _prompt, _cleanup
- Current STEP: $STEP
- Script has $(wc -l < "$SELF") lines"

    claude -p "$full_prompt" --dangerously-skip-permissions 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────
# EVOLVE: Append generated code to script
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    ((STEP++))
    echo -e "\\033[32m[step $STEP]\\033[0m $intent"

    local code=$(_ask "$intent")
    if [[ -z "$code" ]]; then
        echo -e "\\033[31m[error]\\033[0m empty response"
        return 1
    fi

    local lines=$(echo "$code" | wc -l)
    echo -e "\\033[33m[+$lines lines]\\033[0m"

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
    read -rp $'\\033[35m  what shall I become? \\033[0m' input || exit 0
    [[ -z "$input" || "$input" == "exit" ]] && exit 0
    _evolve "$input"
}

# ─────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────
echo -e "\\033[32m┌─────────────────────────────────────┐\\033[0m"
echo -e "\\033[32m│\\033[0m   anything.sh · autopoietic loop    \\033[32m│\\033[0m"
echo -e "\\033[32m│\\033[0m   provider: claude                 \\033[32m│\\033[0m"
echo -e "\\033[32m└─────────────────────────────────────┘\\033[0m"
echo "  Ctrl+C or 'exit' to save & quit"
echo ""

# ─────────────────────────────────────────────────────────────────
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
[[ -n "${1:-}" ]] && _evolve "$1" || _prompt
#
