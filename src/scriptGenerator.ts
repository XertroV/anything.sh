// Script generation utilities - shared between build and frontend

// Shared LLM prompt template (embedded in bash scripts)
export const LLM_PROMPT = `You are the bash code generator anything.sh in an iterative execution loop.
 [ anything.sh - https://xertrov.github.io/anything.sh/ - Author: XertroV - License: Unlicense ]
---

OUTPUT FORMAT (exactly 3 lines, then code):
FINAL: <true if task complete, false if you need to see output first>
DESCRIPTION: <short description of this step>
BASH_CODE:
<your bash code here - no markdown, no fences>

RULES:
- If you need to check something (installed packages, file contents, etc), set FINAL: false
- When FINAL: false, your code runs and stdout/stderr is sent back to you
- When FINAL: true, task is complete and user is prompted for next task
- Don't set FINAL: true prematurely - only when the entire task/experience is genuinely complete, not after partial progress
- No markdown fences, no explanation outside the format above
- Never include XML, HTML, or markup tags in bash code
- Declare reusable helper functions globally at the top of your code block - they persist across all steps
- IMPORTANT: Use absolute paths or verify paths exist before running commands. CWD may not be where you expect.
- MULTI-PART EXPERIENCES: For games, stories, or tutorials, use FINAL: false after each chapter/segment
- Your stdout/stderr feeds back to you, so output "Chapter 1 complete. Hero HP: 50" to inform your next step
- Global variables persist across steps - declare without 'local' for state (HP=100, CHAPTER=1, INVENTORY=())
- USER INPUT: Don't assume on vague tasks - ask. Prefer inline tools (gum, fzf, read -rp) that preserve context
- Full-screen TUI (whiptail/dialog) sparingly - include all context needed to decide in the dialog itself, recap after
- Set FINAL: false after asking - response appears in next feedback
- For interactive experiences: use the best available tools (TUI, colors, ASCII art) to make something impressive
- Only use TUI tools shown in INSTALLED TUI: line. To use unlisted tools, install them first (set FINAL: false, ask permission, install, then use)
- QUALITY: Don't settle for minimal - create something impressive. The user will appreciate extra polish and creativity.
- AVOID dark gray colors (e.g., \033[90m, "bright black") - they are invisible on black terminals. Use bold white (\033[1;37m), bright colors (\033[96m cyan, \033[93m yellow), or standard colors instead.
- Use timing for effect: slow text reveals (pv, character-by-character), pauses for dramatic moments, animations where appropriate
- When asking for input, ensure the user can see what they need to decide - pause after animations, recap after long output
- Avoid clearing the screen, but if you need to during interactive experiences, confirm with the user first
- Generate substantial, content-rich steps: full scenes with setup, action, dialogue AND choices - not minimal fragments. LLM calls are slow.
- Build complete interactive systems in single steps: combat loops, dialogue trees, puzzles should run to completion - don't fragment across iterations without good reason
- For complex experiences: use first 1-2 steps to create utility functions (UI helpers, combat engine, state display) so later steps are richer and more efficient. Leave design notes in comments.
- For long experiences: call _continue_journey() at chapter/quest completion to add 16 more iterations

EXAMPLE (checking before installing):
FINAL: false
DESCRIPTION: Check if package is installed
BASH_CODE:
check_deps() { command -v figlet &>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"; }
check_deps

EXAMPLE (final step after seeing output):
FINAL: true
DESCRIPTION: Install figlet
BASH_CODE:
install_figlet() { sudo pacman -S --noconfirm figlet && figlet "Hello"; }
install_figlet

\${ANYTHING_EXTRA:+
=== EXTRA CONTEXT ===
\$ANYTHING_EXTRA
}

=== CURRENT SCRIPT CONTENT ===
\${script_content}

=== CURRENT SYSTEM ===
SYSTEM: \$(uname -sm) \$(. /etc/os-release 2>/dev/null && echo "\$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | \$SHELL
CWD: \$PWD
DISPLAY: \$([[ -n "\${WAYLAND_DISPLAY:-}" ]] && echo "wayland:\$WAYLAND_DISPLAY" || [[ -n "\${DISPLAY:-}" ]] && echo "x11:\$DISPLAY" || echo "NONE")\$([[ -n "\${SSH_TTY:-}" ]] && echo " [ssh]")
INSTALLED TUI: \$(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv nms chafa glow bat cmatrix slides fastfetch asciinema delta; do command -v \$t &>/dev/null && printf "%s " "\$t"; done)

STEP \${STEP} INSTRUCTIONS:
\${AGENT_MODE_RULE}

TASK: \$intent
TURNS REMAINING: \$remaining (if 1-2 and this is a long experience, call _continue_journey() to add 16 more; otherwise prioritize completing or informing user why it can't be done)
\$feedback`;

// LLM CLI Provider configurations
export const PROVIDERS = {
  claude: {
    name: 'Claude',
    cmd: 'claude -p "$full_prompt" --model sonnet --dangerously-skip-permissions 2>/dev/null',
  },
  codex: {
    name: 'Codex',
    cmd: 'codex exec "$full_prompt" --full-auto 2>/dev/null',
  },
  aider: {
    name: 'Aider',
    cmd: 'aider --message "$full_prompt" --yes --no-stream 2>/dev/null',
  },
  gemini: {
    name: 'Gemini',
    cmd: 'gemini -p "$full_prompt" 2>/dev/null',
  },
  goose: {
    name: 'Goose',
    cmd: 'goose run -t "$full_prompt" 2>/dev/null',
  },
  continue: {
    name: 'Continue',
    cmd: 'cn -p "$full_prompt" --allow Write --allow Bash 2>/dev/null',
  },
  opencode: {
    name: 'OpenCode',
    cmd: 'opencode run "$full_prompt" 2>/dev/null',
  },
  kimi: {
    name: 'Kimi',
    cmd: 'kimi --print --command "$full_prompt" 2>/dev/null',
  },
  groq: {
    name: 'Groq API',
    cmd: `curl -s https://api.groq.com/openai/v1/chat/completions \\
      -H "Authorization: Bearer \$GROQ_API_KEY" -H "Content-Type: application/json" \\
      -d "\$(jq -n --arg p \"\$full_prompt\" '{model:"moonshotai/kimi-k2-instruct-0905",messages:[{role:"user",content:\$p}],temperature:0.7,max_tokens:4096}')" \\
      | jq -r '.choices[0].message.content // empty'`,
  },
  openrouter: {
    name: 'OpenRouter',
    cmd: `curl -s https://openrouter.ai/api/v1/chat/completions \\
      -H "Authorization: Bearer \$OPENROUTER_API_KEY" -H "Content-Type: application/json" \\
      -d "\$(jq -n --arg p \"\$full_prompt\" '{model:"anthropic/claude-3.5-sonnet",messages:[{role:"user",content:\$p}],max_tokens:4096}')" \\
      | jq -r '.choices[0].message.content // empty'`,
  },
} as const;

export type ProviderId = keyof typeof PROVIDERS;

// All providers in a flat list
export const ALL_PROVIDERS: ProviderId[] = [
  'claude', 'codex', 'aider', 'gemini', 'goose', 'continue', 'opencode', 'kimi',
  'groq', 'openrouter'
];

// Generate full script with provider-specific CLI command
export const getScriptFull = (provider: ProviderId) => `#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - Autopoietic Self-Modifying Execution Loop       ║
# ║  A script that evolves by appending LLM-generated code.        ║
# ║  Author: XertroV + vibes        License: The Unlicense         ║
# ║  Home: https://xertrov.github.io/anything.sh/                  ║
# ║  Current Provider: ${PROVIDERS[provider].name.padEnd(41)}   ║
# ╚════════════════════════════════════════════════════════════════╝
# USAGE: ./anything.sh ["initial prompt"]

set -uo pipefail  # -e disabled: we handle errors manually

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────
SELF="$0"
ORIG="\${SELF}.orig"
STEP=0
MAX_ITER=160  # Max LLM calls per task (increase for complex tasks)
BONUS_ITER=0  # Extra iterations granted via _continue_journey()
SPINNER_PID=""  # Track spinner for cleanup
AGENT_MODE=0  # Set to 1 with -a/--agent flag for non-interactive execution
AGENT_REALTIME_FD=2  # Agent real-time output: 2=stderr, or use /dev/tty
_OUT="/tmp/anything_out_\$\$"  # Output capture file for same-process execution

# ─────────────────────────────────────────────────────────────────
# TRACK ORIGINAL: For agent mode self-calling, track the original script
# ─────────────────────────────────────────────────────────────────
[[ -z "\${ANYTHING_ORIGINAL:-}" ]] && export ANYTHING_ORIGINAL="$SELF"

# ─────────────────────────────────────────────────────────────────
# AUTO-LOCALIZE: Copy to current dir if running from system path
# ─────────────────────────────────────────────────────────────────
if [[ "$SELF" == *"/bin/"* && ! -f "$ORIG" ]]; then
    LOCAL_COPY="./anything_\$(date +%Y%m%d_%H%M%S).sh"
    cp "$SELF" "$LOCAL_COPY"
    chmod +x "$LOCAL_COPY"
    echo -e "\\033[36m[localized]\\033[0m $LOCAL_COPY"
    exec "$LOCAL_COPY" "\$@"
fi

# ─────────────────────────────────────────────────────────────────
# ARGUMENT PARSING: Handle -a/--agent flag
# ─────────────────────────────────────────────────────────────────
while [[ \$# -gt 0 ]]; do case "$1" in -a|--agent) AGENT_MODE=1; shift ;; --) shift; break ;; -*) echo -e "\\033[31m[error]\\033[0m Unknown: $1" >&2; exit 1 ;; *) break ;; esac; done

# ─────────────────────────────────────────────────────────────────
# AGENT MODE: Create temp copy and exec for non-interactive execution
# ─────────────────────────────────────────────────────────────────
if [[ \$AGENT_MODE -eq 1 && -n "\${1:-}" ]]; then
    TEMP_SCRIPT="./anything_agent_\$\$.sh"
    cp "\${ANYTHING_ORIGINAL}" "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    exec "$TEMP_SCRIPT" "\$@"
fi

# ─────────────────────────────────────────────────────────────────
# BACKUP: Save original on first run (only for original script)
# ─────────────────────────────────────────────────────────────────
[[ "$SELF" == "\${ANYTHING_ORIGINAL}" && ! -f "$ORIG" ]] && cp "$SELF" "$ORIG" && echo -e "\\033[36m[backup]\\033[0m $ORIG"

# ─────────────────────────────────────────────────────────────────
# CLEANUP: Runs on EXIT - archives session, restores original
# ─────────────────────────────────────────────────────────────────
_cleanup() {
    local rc=\$?
    [[ -n "\$SPINNER_PID" ]] && kill "\$SPINNER_PID" 2>/dev/null
    printf "\\r\\033[K"  # Clear spinner line
    [[ -f "$ORIG" ]] || return \$rc
    local archive="\${SELF%.sh}_\$(date +%Y%m%d_%H%M%S).log.sh"
    cp "$SELF" "\$archive" 2>/dev/null || true
    # Only restore original if this is the original script, not an agent temp copy
    if [[ "$SELF" == "\${ANYTHING_ORIGINAL}" ]]; then
        cp "$ORIG" "$SELF" 2>/dev/null || true
        echo ""
        echo -e "\\033[36m[archived]\\033[0m \$archive"
        echo -e "\\033[36m[restored]\\033[0m $SELF"
    else
        # Agent mode temp copy - just archive, don't restore
        echo -e "\\033[36m[archived]\\033[0m \$archive"
    fi
    exit \$rc
}
trap _cleanup EXIT

# ─────────────────────────────────────────────────────────────────
# ORACLE: Query ${PROVIDERS[provider].name} with script context
# ─────────────────────────────────────────────────────────────────
_ask() {
    local intent="$1"
    local feedback="\${2:-}"
    local remaining="\${3:-?}"
    local agent_context=""
    local AGENT_MODE_RULE=""
    local script_content
    script_content=\$(cat "\$SELF")
    if [[ \$AGENT_MODE -eq 1 ]]; then
        agent_context="

AGENT MODE: This script is running with -a/--agent flag (non-interactive).
- You cannot use 'read', 'gum', 'fzf', or any interactive tools - the user cannot respond
- Do not prompt for input or confirmation
- Your FINAL: true step should output a summary via echo of what was created/modified
- This summary will be captured and returned to the parent script
- Example: echo 'Created fib() function in ./lib/math.sh'"
    else
        AGENT_MODE_RULE="- AGENT MODE: The script supports -a/--agent flag for non-interactive execution. When generating code that will call anything.sh with -a/--agent, your FINAL: true step should echo a summary of what was created/modified.
- In the first step, discover available TUI utilities AND call `<tool> --help` on each to understand their options (colors, fonts, flags) before building the experience"
    fi
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
${LLM_PROMPT}\$agent_context
PROMPT

    ${PROVIDERS[provider].cmd}
}

# ─────────────────────────────────────────────────────────────────
# SPINNER: Pulsing animation while waiting
# ─────────────────────────────────────────────────────────────────
_spinner() {
    local frames=('·    ' '··   ' '···  ' '···· ' '·····' ' ····' '  ···' '   ··' '    ·' '     ')
    local i=0
    while true; do
        printf "\\r\\033[36m%s\\033[0m pulsing..." "\${frames[i]}"
        i=$(( (i + 1) % \${#frames[@]} ))
        sleep 0.1
    done
}

# ─────────────────────────────────────────────────────────────────
# CONTINUE JOURNEY: Add more iterations for long experiences
# ─────────────────────────────────────────────────────────────────
_continue_journey() {
    BONUS_ITER=\$((BONUS_ITER + 16))
    echo -e "\\033[36m[+16 iterations granted]\\033[0m"
}


# ─────────────────────────────────────────────────────────────────
# EVOLVE STEP: Single iteration of code generation (continuation-passing)
# ─────────────────────────────────────────────────────────────────
_evolve_step() {
    local intent="\$1"
    local prev_output="\${2:-}"
    local step_num="\${3:-1}"
    local prev_exit="\${4:-0}"

    # Check iteration limit
    if [[ \$step_num -gt \$((MAX_ITER + BONUS_ITER)) ]]; then
        if [[ \$AGENT_MODE -eq 1 ]]; then
            echo -e "\\033[31m[error]\\033[0m Max iterations reached without completion" >&2
            exit 1
        fi
        echo -e "\\033[33m[max iterations reached]\\033[0m Task incomplete after \$((step_num - 1)) steps."
        read -rp \$'\\033[95m  continue? [Y/n] \\033[0m' cont
        if [[ -z "\$cont" || "\$cont" =~ ^[Yy] ]]; then
            BONUS_ITER=\$((BONUS_ITER + MAX_ITER))
            _evolve_step "\$intent" "\$prev_output" "\$step_num" "\$prev_exit"
            return
        fi
        echo -e "\\033[36m[stopped]\\033[0m You can retry or try a different approach."
        _prompt
        return
    fi

    STEP=\$step_num
    local remaining=\$((MAX_ITER + BONUS_ITER - step_num))

    # Build feedback for LLM
    local feedback=""
    if [[ -n "\$prev_output" ]]; then
        feedback="
PREVIOUS STEP OUTPUT (exit code \$prev_exit):
\$prev_output
"
    fi

    # Start spinner
    _spinner &
    SPINNER_PID=\$!

    local response=\$(_ask "\$intent" "\$feedback" "\$remaining")

    # Stop spinner
    kill \$SPINNER_PID 2>/dev/null
    wait \$SPINNER_PID 2>/dev/null
    SPINNER_PID=""
    printf "\\r\\033[K"

    # Parse structured response
    local is_final=\$(echo "\$response" | grep -i '^FINAL:' | head -1 | sed 's/^FINAL:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
    local description=\$(echo "\$response" | grep -i '^DESCRIPTION:' | head -1 | sed 's/^DESCRIPTION:[[:space:]]*//')
    local code=\$(echo "\$response" | sed -n '/^BASH_CODE:/,\$ { /^BASH_CODE:/d; p }')

    # Fallback: if no structured format, treat whole response as code
    if [[ -z "\$code" ]]; then
        code="\$response"
        description="\$intent"
        is_final="true"
    fi

    # Strip markdown fences if present
    if echo "\$code" | grep -q '^\\\`\\\`\\\`'; then
        code=\$(echo "\$code" | sed -n '/^\\\`\\\`\\\`/,/^\\\`\\\`\\\`/p' | sed '/^\\\`\\\`\\\`/d')
    fi

    if [[ -z "\$code" ]]; then
        echo -e "\\033[31m[error]\\033[0m empty response"
        _prompt
        return
    fi

    echo -e "\\033[32m[step \$STEP]\\033[0m \$description"
    local lines=\$(echo "\$code" | wc -l)
    echo -e "\\033[33m[+\$lines lines]\\033[0m"

    # Append step code wrapped in a function, with output capture and continuation
    # No truncation needed - padding at end ensures bash hasn't read EOF yet
    cat >> "\$SELF" <<EVOLUTION

# ═══════════════════════════════════════════════════════════════
# STEP \$STEP: \$description
# Generated: \$(date '+%Y-%m-%d %H:%M:%S') | FINAL: \$is_final
# ═══════════════════════════════════════════════════════════════
_step\${STEP}() {
\$code
}
_step\${STEP} 2>&1 | tee "\$_OUT"
_evolve_continue "\$intent" "\\\${PIPESTATUS[0]}" "\$is_final" "\$STEP"
EVOLUTION

    # Return - bash will naturally read and execute the appended code
    return
}

# ─────────────────────────────────────────────────────────────────
# EVOLVE CONTINUE: Handle output capture and next iteration
# ─────────────────────────────────────────────────────────────────
_evolve_continue() {
    local intent="\$1"
    local exit_code="\$2"
    local is_final="\$3"
    local step_num="\$4"

    # Read captured output
    local output=""
    [[ -f "\$_OUT" ]] && output=\$(cat "\$_OUT")

    # Clean ANSI codes for LLM feedback
    output=\$(echo "\$output" | perl -pe 's/\\e\\[[0-9;]*[mGKHJF]//g; s/\\r\\n/\\n/g; s/\\r//g' 2>/dev/null || echo "\$output")

    [[ \$exit_code -ne 0 ]] && echo -e "\\033[31m[exit \$exit_code]\\033[0m"

    # Append output as comments to script (for crash recovery)
    if [[ \$AGENT_MODE -eq 0 && -n "\$output" ]]; then
        local output_lines=\$(echo "\$output" | wc -l)
        if [[ \$output_lines -gt 1000 ]]; then
            {
                echo ""
                echo "# ───────────────────────────────────────────────────────────────"
                echo "# OUTPUT FROM STEP \$step_num:"
                echo "# ───────────────────────────────────────────────────────────────"
                echo "\$output" | head -400 | uniq | sed 's/^/# /'
                echo "#"
                echo "# [...\$((output_lines - 800)) lines snipped...]"
                echo "#"
                echo "\$output" | tail -400 | uniq | sed 's/^/# /'
            } >> "\$SELF"
        else
            {
                echo ""
                echo "# ───────────────────────────────────────────────────────────────"
                echo "# OUTPUT FROM STEP \$step_num:"
                echo "# ───────────────────────────────────────────────────────────────"
                echo "\$output" | uniq | sed 's/^/# /'
            } >> "\$SELF"
        fi
    fi

    # Decide next action
    if [[ "\$is_final" == "true" && \$exit_code -eq 0 ]]; then
        # Success - return to prompt
        if [[ \$AGENT_MODE -eq 1 ]]; then
            # Agent mode: output result and exit
            echo "\$output" | sed 's/^/@ /'
            exit 0
        fi
        _prompt
    elif [[ \$exit_code -ne 0 && \$exit_code -ne 141 ]]; then
        # Error recovery (141 is SIGPIPE, ignore it)
        if [[ "\$is_final" == "true" ]]; then
            echo -e "\\033[33m[final step failed, attempting recovery...]\\033[0m"
        fi
        if [[ \$AGENT_MODE -eq 1 ]]; then
            # Agent mode with error - output error and continue trying
            echo "\$output" | sed 's/^/> /' >&2
        fi
        _evolve_step "\$intent" "FAILED (exit \$exit_code): \$output" \$((step_num + 1)) "\$exit_code"
    else
        # Continue with next step
        _evolve_step "\$intent" "\$output" \$((step_num + 1)) "\$exit_code"
    fi
}

# ─────────────────────────────────────────────────────────────────
# EVOLVE: Iterative code generation with feedback loop (LEGACY - kept for reference)
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    local feedback=""
    local is_final="false"
    local iteration=0
    local output=""
    local exit_code=0

    # Remove trailing _prompt and # from script (so reruns replay without prompting)
    sed -i '/^_prompt$/,/^#$/d' "$SELF"

    while [[ "$is_final" != "true" && $iteration -lt $((MAX_ITER + BONUS_ITER)) ]]; do
        ((iteration++))
        ((STEP++))
        local remaining=$((MAX_ITER + BONUS_ITER - iteration))

        # Start spinner
        _spinner &
        SPINNER_PID=$!

        local response=$(_ask "$intent" "$feedback" "$remaining")

        # Stop spinner
        kill \$SPINNER_PID 2>/dev/null
        wait \$SPINNER_PID 2>/dev/null
        SPINNER_PID=""
        printf "\\r\\033[K"

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
        if echo "$code" | grep -q '^\`\`\`'; then
            code=$(echo "$code" | sed -n '/^\`\`\`/,/^\`\`\`/p' | sed '/^\`\`\`/d')
        fi

        if [[ -z "$code" ]]; then
            echo -e "\\033[31m[error]\\033[0m empty response"
            return 1
        fi

        echo -e "\\033[32m[step $STEP]\\033[0m $description"
        local lines=$(echo "$code" | wc -l)
        echo -e "\\033[33m[+$lines lines]\\033[0m"

        # Append just the step header + code (output comments already appended after execution)
        cat >> "$SELF" <<EVOLUTION

# ═══════════════════════════════════════════════════════════════
# STEP $STEP: $description
# Generated: $(date '+%Y-%m-%d %H:%M:%S') | FINAL: $is_final
# ═══════════════════════════════════════════════════════════════
$code
EVOLUTION

        # Execute with PTY (supports interactive programs like whiptail/dialog)
        echo -e "\\033[36m[running...]\\033[0m"
        local tmpfile=\$(mktemp) codefile=\$(mktemp)
        printf '%s' "\$code" > "\$codefile"
        if [[ \$AGENT_MODE -eq 1 ]]; then
            # Agent mode: real-time output to stderr with > prefix to show it's a subagent
            if [[ "\$(uname)" == "Darwin" ]]; then
                script -q "\$tmpfile" bash "\$codefile" | sed 's/^/> /' >&\$AGENT_REALTIME_FD
            else
                script -q -e -c "bash '\$codefile'" "\$tmpfile" | sed 's/^/> /' >&\$AGENT_REALTIME_FD
            fi
            exit_code=\${PIPESTATUS[0]}
        else
            if [[ "\$(uname)" == "Darwin" ]]; then
                script -q "\$tmpfile" bash "\$codefile"
            else
                script -q -e -c "bash '\$codefile'" "\$tmpfile"
            fi
            exit_code=\$?
        fi
        rm -f "\$codefile"
        # Clean ANSI codes for LLM feedback (script captures control sequences)
        output=\$(perl -pe 's/\\e\\[[0-9;]*[mGKHJF]//g; s/\\r\\n/\\n/g; s/\\r//g' "\$tmpfile" 2>/dev/null || cat "\$tmpfile")
        rm -f "\$tmpfile"
        [[ \$exit_code -ne 0 ]] && echo -e "\\033[31m[exit \$exit_code]\\033[0m"

        # Immediately append output as comments to script (before LLM call, in case of crash)
        # Skip in agent mode - output already forwarded to parent
        if [[ \$AGENT_MODE -eq 0 && -n "\$output" ]]; then
            local output_lines=\$(echo "\$output" | wc -l)
            if [[ \$output_lines -gt 1000 ]]; then
                # Truncate: keep first 400 and last 400 lines
                {
                    echo ""
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "# OUTPUT FROM PREVIOUS STEP:"
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "\$output" | head -400 | uniq | sed 's/^/# /'
                    echo "#"
                    echo "# [...\$((output_lines - 800)) lines snipped...]"
                    echo "#"
                    echo "\$output" | tail -400 | uniq | sed 's/^/# /'
                } >> "\$SELF"
            else
                {
                    echo ""
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "# OUTPUT FROM PREVIOUS STEP:"
                    echo "# ───────────────────────────────────────────────────────────────"
                    echo "\$output" | uniq | sed 's/^/# /'
                } >> "\$SELF"
            fi
        fi

        if [[ "$is_final" != "true" ]]; then
            feedback="
PREVIOUS STEP OUTPUT (exit code $exit_code):
$output
"
        elif [[ $exit_code -ne 0 && $exit_code -ne 141 && $iteration -lt $MAX_ITER ]]; then
            # Final step failed - give LLM a chance to recover
            echo -e "\\033[33m[final step failed, attempting recovery...]\\033[0m"
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
        if [[ \$AGENT_MODE -eq 1 ]]; then
            echo -e "\\033[31m[error]\\033[0m Max iterations reached without completion" >&2
            exit 1
        fi
        echo -e "\\033[33m[max iterations reached]\\033[0m Task incomplete after $iteration steps."
        read -rp $'\\033[95m  continue? [Y/n] \\033[0m' cont
        if [[ -z "$cont" || "$cont" =~ ^[Yy] ]]; then
            iteration=0
            _evolve "$intent"  # Recursive call to continue
            return
        fi
        echo -e "\\033[36m[stopped]\\033[0m You can retry or try a different approach."
    fi

    # In agent mode, return the final output and exit
    if [[ \$AGENT_MODE -eq 1 ]]; then
        if [[ \$exit_code -ne 0 ]]; then
            # On error, output to stderr with > prefix
            echo "\$output" | sed 's/^/> /' >&2
            exit \$exit_code
        else
            # Success output to stdout with @ prefix
            echo "\$output" | sed 's/^/@ /'
            exit 0
        fi
    fi

    # Append _prompt for next user input (for re-runs of the script)
    cat >> "$SELF" <<'PROMPT_MARKER'

_prompt
#
PROMPT_MARKER

    # Continue interactive loop
    _prompt
}

# ─────────────────────────────────────────────────────────────────
# PROMPT: Interactive input loop
# ─────────────────────────────────────────────────────────────────
_prompt() {
    echo ""
    local input
    if command -v gum &>/dev/null; then
        # gum supports multiline editing, backspace over newlines, etc.
        input=\$(gum input --placeholder "what shall I become?" --width 60) || exit 0
        echo -e "\\033[95m  → \\033[0m\$input"
    else
        read -rp \$'\\033[95m  what shall I become? \\033[0m' input || exit 0
    fi
    [[ -z "\$input" || "\$input" == "exit" ]] && exit 0
    _evolve_step "\$input" "" 1 0
}

# ─────────────────────────────────────────────────────────────────
# BANNER (skip in agent mode)
# ─────────────────────────────────────────────────────────────────
if [[ \$AGENT_MODE -eq 0 ]]; then
    echo -e "\\033[32m┌─────────────────────────────────────┐\\033[0m"
    echo -e "\\033[32m│\\033[0m   anything.sh · autopoietic loop    \\033[32m│\\033[0m"
    echo -e "\\033[32m│\\033[0m   provider: ${PROVIDERS[provider].name.toLowerCase().padEnd(23)} \\033[32m│\\033[0m"
    echo -e "\\033[32m└─────────────────────────────────────┘\\033[0m"
    echo "  Ctrl+C or 'exit' to save & quit"
    echo ""

    # ─────────────────────────────────────────────────────────────────
    # SYSTEM INFO
    # ─────────────────────────────────────────────────────────────────
    echo -e "\\033[36m  os:\\033[0m    \$(. /etc/os-release 2>/dev/null && echo "\$PRETTY_NAME" || sw_vers -productName 2>/dev/null)"
    echo -e "\\033[36m  arch:\\033[0m  \$(uname -sm)"
    echo -e "\\033[36m  shell:\\033[0m \$SHELL"
    echo -e "\\033[36m  pwd:\\033[0m   \$PWD"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
if [[ \$AGENT_MODE -eq 1 ]]; then
    # Agent mode requires a prompt argument
    if [[ -z "\${1:-}" ]]; then
        echo -e "\\033[31m[error]\\033[0m Agent mode requires a prompt argument" >&2
        exit 1
    fi
    _evolve_step "\$1" "" 1 0
else
    [[ -n "\${1:-}" ]] && _evolve_step "\$1" "" 1 0 || _prompt
fi
# ─────────────────────────────────────────────────────────────────
# PADDING: Bash reads files in chunks (~8KB). This padding ensures
# bash hasn't reached EOF when we append code, so appended code
# executes naturally. New code is appended after this padding.
# ─────────────────────────────────────────────────────────────────
${Array(100).fill('#'.repeat(80)).join('\n')}
`;

// Generate compact script with provider-specific CLI command
export const getScriptCompact = (provider: ProviderId) => `#!/bin/bash
# anything.sh [compact] · ${PROVIDERS[provider].name}
set -uo pipefail
SELF="$0"; ORIG="\${SELF}.orig"; STEP=0; MAX_ITER=160; BONUS_ITER=0; SPINNER_PID=""; AGENT_MODE=0; AGENT_REALTIME_FD=2
[[ -z "\${ANYTHING_ORIGINAL:-}" ]] && export ANYTHING_ORIGINAL="$SELF"

# Auto-localize: copy to current dir if running from system path
if [[ "$SELF" == *"/bin/"* && ! -f "$ORIG" ]]; then LOCAL="./anything_\$(date +%Y%m%d_%H%M%S).sh"; cp "$SELF" "$LOCAL"; chmod +x "$LOCAL"; echo -e "\\033[36m[localized]\\033[0m $LOCAL"; exec "$LOCAL" "\$@"; fi

# Parse args
POSITIONAL=(); while [[ \$# -gt 0 ]]; do case "\$1" in -a|--agent) AGENT_MODE=1; shift ;; --) shift; break ;; -*) echo "[error] Unknown: \$1" >&2; exit 1 ;; *) POSITIONAL+=("\$1"); shift ;; esac; done; set -- "\${POSITIONAL[@]}"

# Agent mode temp copy
if [[ \$AGENT_MODE -eq 1 && -n "\${1:-}" ]]; then TEMP="./anything_agent_\$\$.sh"; cp "\${ANYTHING_ORIGINAL}" "\$TEMP"; chmod +x "\$TEMP"; exec "\$TEMP" "\$@"; fi

# Backup only for original
[[ "$SELF" == "\${ANYTHING_ORIGINAL}" && ! -f "$ORIG" ]] && cp "$SELF" "$ORIG"
_cleanup() { [[ -n "\$SPINNER_PID" ]] && kill "\$SPINNER_PID" 2>/dev/null; printf "\\r\\033[K"; cp "$SELF" "\${SELF%.sh}_\$(date +%s).log.sh"; [[ "$SELF" == "\${ANYTHING_ORIGINAL}" ]] && cp "$ORIG" "$SELF"; echo -e "\\n\\033[36m[saved]\\033[0m"; }
trap _cleanup EXIT
_continue_journey() { BONUS_ITER=\$((BONUS_ITER + 16)); echo -e "\\033[36m[+16 iterations]\\033[0m"; }

_ask() {
    local intent="\$1"; local feedback="\${2:-}"; local remaining="\${3:-?}"; local agent_ctx=""; local AGENT_MODE_RULE=""; local script_content; script_content=\$(cat "\$SELF")
    if [[ \$AGENT_MODE -eq 1 ]]; then
        agent_ctx=" AGENT MODE: running non-interactive. No 'read' or interactive tools. FINAL: true step should echo a summary."
    else
        AGENT_MODE_RULE="- AGENT MODE: The script supports -a/--agent flag for non-interactive execution.
- In the first step, discover available TUI utilities AND call `<tool> --help` on each to understand their options (colors, fonts, flags) before building the experience"
    fi
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
${LLM_PROMPT}\$agent_ctx
PROMPT
    ${PROVIDERS[provider].cmd}
}

_spin() { while :; do for c in · ·· ··· ···· ····· ' ····' '  ···' '   ··' '    ·' '     '; do printf "\\r\\033[36m%s\\033[0m" "\$c"; sleep .1; done; done; }
_evolve() {
    local intent="\$1" feedback="" is_final="false" iter=0 out="" rc=0
    sed -i '/^_prompt$/,/^#$/d' "\$SELF"
    while [[ "\$is_final" != "true" && \$iter -lt \$((MAX_ITER + BONUS_ITER)) ]]; do
        ((iter++)); ((STEP++)); local remaining=\$((MAX_ITER + BONUS_ITER - iter))
        _spin & SPINNER_PID=\$!; local resp=\$(_ask "\$intent" "\$feedback" "\$remaining"); kill \$SPINNER_PID 2>/dev/null; SPINNER_PID=""; printf "\\r\\033[K"
        is_final=\$(echo "\$resp" | grep -i '^FINAL:' | head -1 | sed 's/^FINAL:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
        local desc=\$(echo "\$resp" | grep -i '^DESCRIPTION:' | head -1 | sed 's/^DESCRIPTION:[[:space:]]*//')
        local code=\$(echo "\$resp" | sed -n '/^BASH_CODE:/,\$ { /^BASH_CODE:/d; p }')
        [[ -z "\$code" ]] && code="\$resp" && desc="\$intent" && is_final="true"
        echo "\$code" | grep -q '^\`\`\`' && code=\$(echo "\$code" | sed -n '/^\`\`\`/,/^\`\`\`/p' | sed '/^\`\`\`/d')
        echo -e "\\033[32m[step \$STEP]\\033[0m \$desc"
        echo -e "\\n# STEP \$STEP: \$desc | FINAL: \$is_final\\n\$code" >> "\$SELF"
        echo -e "\\033[36m[running...]\\033[0m"
        local tmpf=\$(mktemp) codef=\$(mktemp)
        printf '%s' "\$code" > "\$codef"
        if [[ \$AGENT_MODE -eq 1 ]]; then
            if [[ "\$(uname)" == "Darwin" ]]; then script -q "\$tmpf" bash "\$codef" | sed 's/^/> /' >&\$AGENT_REALTIME_FD; else script -q -e -c "bash '\$codef'" "\$tmpf" | sed 's/^/> /' >&\$AGENT_REALTIME_FD; fi
            rc=\${PIPESTATUS[0]}
        else
            if [[ "\$(uname)" == "Darwin" ]]; then script -q "\$tmpf" bash "\$codef"; else script -q -e -c "bash '\$codef'" "\$tmpf"; fi
            rc=\$?
        fi
        rm -f "\$codef"; out=\$(perl -pe 's/\\e\\[[0-9;]*[mGKHJF]//g; s/\\r//g' "\$tmpf" 2>/dev/null || cat "\$tmpf"); rm -f "\$tmpf"
        [[ \$rc -ne 0 ]] && echo -e "\\033[31m[exit \$rc]\\033[0m"
        # Append output immediately as comments (before next LLM call, in case of crash) - skip in agent mode
        [[ \$AGENT_MODE -eq 0 && -n "\$out" ]] && { local ln=\$(echo "\$out"|wc -l); if [[ \$ln -gt 1000 ]]; then { echo ""; echo "# PREV OUTPUT:"; echo "\$out"|head -400|uniq|sed 's/^/# /'; echo "# [...\$((ln-800)) snipped...]"; echo "\$out"|tail -400|uniq|sed 's/^/# /'; } >>"\$SELF"; else { echo ""; echo "# PREV OUTPUT:"; echo "\$out"|uniq|sed 's/^/# /'; } >>"\$SELF"; fi; }
        if [[ "\$is_final" != "true" ]]; then
            feedback="\\nPREVIOUS OUTPUT (exit \$rc):\\n\$out\\n"
        elif [[ \$rc -ne 0 && \$rc -ne 141 && \$iter -lt \$MAX_ITER ]]; then
            echo -e "\\033[33m[recovery...]\\033[0m"; is_final="false"
            feedback="\\nFINAL FAILED (exit \$rc):\\n\$out\\nPlease fix.\\n"
        fi
    done
    if [[ "\$is_final" != "true" ]]; then
        if [[ \$AGENT_MODE -eq 1 ]]; then echo -e "\\033[31m[error]\\033[0m Incomplete" >&2; exit 1; fi
        echo -e "\\033[33m[max iterations]\\033[0m Incomplete after \$iter steps."
        read -rp \$'\\033[95m  continue? [Y/n] \\033[0m' c
        if [[ -z "\$c" || "\$c" =~ ^[Yy] ]]; then iter=0; _evolve "\$intent"; return; fi
        echo -e "\\033[36m[stopped]\\033[0m"
    fi
    if [[ \$AGENT_MODE -eq 1 ]]; then
        if [[ \$rc -ne 0 ]]; then echo "\$out" | sed 's/^/> /' >&2; exit \$rc; else echo "\$out" | sed 's/^/@ /'; exit 0; fi
    fi
    echo -e "\\n_prompt\\n#" >> "\$SELF"
    _prompt
}

_prompt() {
    local i; if command -v gum &>/dev/null; then i=\$(gum input --placeholder "become?" --width 60) || exit; echo -e "\\033[95m  → \\033[0m\$i"; else read -rp \$'\\033[95m  become? \\033[0m' i || exit; fi
    [[ -z "\$i" ]] && exit; _evolve "\$i"
}

if [[ \$AGENT_MODE -eq 0 ]]; then
    echo "anything.sh · ${PROVIDERS[provider].name} · ctrl+c = save & quit"
    echo -e "\\033[36m  \$(uname -sm) | \$(. /etc/os-release 2>/dev/null && echo "\$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | \$SHELL\\033[0m"
    echo ""
fi
if [[ \$AGENT_MODE -eq 1 ]]; then
    if [[ -z "\${1:-}" ]]; then echo "[error] Agent mode requires prompt" >&2; exit 1; fi
    _evolve "$1"
else
    [[ -n "\${1:-}" ]] && _evolve "$1" || _prompt
fi
#
`;
