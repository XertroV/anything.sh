import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Copy, ShieldAlert, FileCode, Skull, Zap, Eye, Command } from 'lucide-react';
import { getRandomExitMessage } from './exitMessages';

// Shared LLM prompt template (embedded in bash scripts)
const LLM_PROMPT = `You are a bash code generator in an iterative execution loop.

SYSTEM: \$(uname -sm) \$(. /etc/os-release 2>/dev/null && echo "\$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | \$SHELL
CWD: \$PWD
DISPLAY: \$([[ -n "\${WAYLAND_DISPLAY:-}" ]] && echo "wayland:\$WAYLAND_DISPLAY" || [[ -n "\${DISPLAY:-}" ]] && echo "x11:\$DISPLAY" || echo "NONE")\$([[ -n "\${SSH_TTY:-}" ]] && echo " [ssh]")
INSTALLED TUI: \$(for t in whiptail dialog gum fzf figlet toilet cowsay lolcat boxes pv nms chafa glow bat cmatrix slides fastfetch asciinema delta; do command -v \$t &>/dev/null && printf "%s " "\$t"; done)

TASK: \$intent
TURNS REMAINING: \$remaining (if 1-2, prioritize completing the task or informing user why it can't be done)
\$feedback

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
- Declare reusable helper functions globally at the top of your code block - they persist across all steps
- Then define step\${STEP}() which uses those helpers, then call step\${STEP} at the end
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
step\${STEP}() { command -v figlet &>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"; }
step\${STEP}

EXAMPLE (final step after seeing output):
FINAL: true
DESCRIPTION: Install figlet
BASH_CODE:
step\${STEP}() { sudo pacman -S --noconfirm figlet && figlet "Hello"; }
step\${STEP}`;

// LLM CLI Provider configurations
const PROVIDERS = {
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
      -H "Authorization: Bearer $GROQ_API_KEY" -H "Content-Type: application/json" \\
      -d "$(jq -n --arg p "$full_prompt" '{model:"openai/gpt-oss-120b",messages:[{role:"user",content:$p}],temperature:0.7,max_tokens:4096}')" \\
      | jq -r '.choices[0].message.content // empty'`,
  },
  openrouter: {
    name: 'OpenRouter',
    cmd: `curl -s https://openrouter.ai/api/v1/chat/completions \\
      -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \\
      -d "$(jq -n --arg p "$full_prompt" '{model:"anthropic/claude-3.5-sonnet",messages:[{role:"user",content:$p}],max_tokens:4096}')" \\
      | jq -r '.choices[0].message.content // empty'`,
  },
} as const;

type ProviderId = keyof typeof PROVIDERS;

// Generate full script with provider-specific CLI command
const getScriptFull = (provider: ProviderId) => `#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - Autopoietic Self-Modifying Execution Loop       ║
# ║  A script that evolves by appending LLM-generated code.        ║
# ║  Provider: ${PROVIDERS[provider].name.padEnd(49)}   ║
# ╚════════════════════════════════════════════════════════════════╝
# USAGE: ./anything.sh ["initial prompt"]

set -uo pipefail  # -e disabled: we handle errors manually

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────
SELF="$0"
ORIG="\${SELF}.orig"
STEP=0
MAX_ITER=16  # Max LLM calls per task (increase for complex tasks)
BONUS_ITER=0  # Extra iterations granted via _continue_journey()
SPINNER_PID=""  # Track spinner for cleanup

# ─────────────────────────────────────────────────────────────────
# BACKUP: Save original on first run
# ─────────────────────────────────────────────────────────────────
[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG" && echo -e "\\033[36m[backup]\\033[0m $ORIG"

# ─────────────────────────────────────────────────────────────────
# CLEANUP: Runs on EXIT - archives session, restores original
# ─────────────────────────────────────────────────────────────────
_cleanup() {
    local rc=$?
    [[ -n "\$SPINNER_PID" ]] && kill "\$SPINNER_PID" 2>/dev/null
    printf "\\r\\033[K"  # Clear spinner line
    [[ -f "$ORIG" ]] || return $rc
    local archive="\${SELF%.sh}_$(date +%Y%m%d_%H%M%S).log.sh"
    cp "$SELF" "$archive" 2>/dev/null || true
    cp "$ORIG" "$SELF" 2>/dev/null || true
    echo ""
    echo -e "\\033[36m[archived]\\033[0m $archive"
    echo -e "\\033[36m[restored]\\033[0m $SELF"
    exit $rc
}
trap _cleanup EXIT

# ─────────────────────────────────────────────────────────────────
# ORACLE: Query ${PROVIDERS[provider].name} with script context
# ─────────────────────────────────────────────────────────────────
_ask() {
    local intent="$1"
    local feedback="\${2:-}"
    local remaining="\${3:-?}"
    local full_prompt
    read -r -d '' full_prompt <<PROMPT
${LLM_PROMPT}
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
# EVOLVE: Iterative code generation with feedback loop
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    local feedback=""
    local is_final="false"
    local iteration=0

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
        local output exit_code
        local tmpfile=\$(mktemp) codefile=\$(mktemp)
        printf '%s' "\$code" > "\$codefile"
        if [[ "\$(uname)" == "Darwin" ]]; then
            script -q "\$tmpfile" bash "\$codefile"
        else
            script -q -e -c "bash '\$codefile'" "\$tmpfile"
        fi
        exit_code=\$?
        rm -f "\$codefile"
        # Clean ANSI codes for LLM feedback (script captures control sequences)
        output=\$(perl -pe 's/\\e\\[[0-9;]*[mGKHJF]//g; s/\\r\\n/\\n/g; s/\\r//g' "\$tmpfile" 2>/dev/null || cat "\$tmpfile")
        rm -f "\$tmpfile"
        [[ \$exit_code -ne 0 ]] && echo -e "\\033[31m[exit \$exit_code]\\033[0m"

        # Immediately append output as comments to script (before LLM call, in case of crash)
        if [[ -n "\$output" ]]; then
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
        echo -e "\\033[33m[max iterations reached]\\033[0m Task incomplete after $iteration steps."
        read -rp $'\\033[95m  continue? [Y/n] \\033[0m' cont
        if [[ -z "$cont" || "$cont" =~ ^[Yy] ]]; then
            iteration=0
            _evolve "$intent"  # Recursive call to continue
            return
        fi
        echo -e "\\033[36m[stopped]\\033[0m You can retry or try a different approach."
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
    read -rp $'\\033[95m  what shall I become? \\033[0m' input || exit 0
    [[ -z "$input" || "$input" == "exit" ]] && exit 0
    _evolve "$input"
}

# ─────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
[[ -n "\${1:-}" ]] && _evolve "$1" || _prompt
#
`;

// Generate compact script with provider-specific CLI command
const getScriptTerse = (provider: ProviderId) => `#!/bin/bash
# anything.sh [compact] · ${PROVIDERS[provider].name}
set -uo pipefail
SELF="$0"; ORIG="\${SELF}.orig"; STEP=0; MAX_ITER=16; BONUS_ITER=0; SPINNER_PID=""

[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG"
_cleanup() { [[ -n "\$SPINNER_PID" ]] && kill "\$SPINNER_PID" 2>/dev/null; printf "\\r\\033[K"; cp "$SELF" "\${SELF%.sh}_$(date +%s).log.sh"; cp "$ORIG" "$SELF"; echo -e "\\n\\033[36m[saved]\\033[0m"; }
trap _cleanup EXIT
_continue_journey() { BONUS_ITER=\$((BONUS_ITER + 16)); echo -e "\\033[36m[+16 iterations]\\033[0m"; }

_ask() {
    local intent="$1"; local feedback="\${2:-}"; local remaining="\${3:-?}"; local full_prompt
    read -r -d '' full_prompt <<PROMPT
${LLM_PROMPT}
PROMPT
    ${PROVIDERS[provider].cmd}
}

_spin() { while :; do for c in · ·· ··· ···· ····· ' ····' '  ···' '   ··' '    ·' '     '; do printf "\\r\\033[36m%s\\033[0m" "$c"; sleep .1; done; done; }
_evolve() {
    local intent="$1" feedback="" is_final="false" iter=0
    sed -i '/^_prompt$/,/^#$/d' "$SELF"
    while [[ "$is_final" != "true" && $iter -lt $((MAX_ITER + BONUS_ITER)) ]]; do
        ((iter++)); ((STEP++)); local remaining=$((MAX_ITER + BONUS_ITER - iter))
        _spin & SPINNER_PID=$!; local resp=$(_ask "$intent" "$feedback" "$remaining"); kill \$SPINNER_PID 2>/dev/null; SPINNER_PID=""; printf "\\r\\033[K"
        is_final=$(echo "$resp" | grep -i '^FINAL:' | head -1 | sed 's/^FINAL:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
        local desc=$(echo "$resp" | grep -i '^DESCRIPTION:' | head -1 | sed 's/^DESCRIPTION:[[:space:]]*//')
        local code=$(echo "$resp" | sed -n '/^BASH_CODE:/,$ { /^BASH_CODE:/d; p }')
        [[ -z "$code" ]] && code="$resp" && desc="$intent" && is_final="true"
        echo "$code" | grep -q '^\`\`\`' && code=$(echo "$code" | sed -n '/^\`\`\`/,/^\`\`\`/p' | sed '/^\`\`\`/d')
        echo -e "\\033[32m[step $STEP]\\033[0m $desc"
        echo -e "\\n# STEP $STEP: $desc | FINAL: $is_final\\n$code" >> "$SELF"
        echo -e "\\033[36m[running...]\\033[0m"
        local out rc tmpf=\$(mktemp) codef=\$(mktemp)
        printf '%s' "\$code" > "\$codef"
        if [[ "\$(uname)" == "Darwin" ]]; then script -q "\$tmpf" bash "\$codef"; else script -q -e -c "bash '\$codef'" "\$tmpf"; fi
        rm -f "\$codef"
        rc=\$?; out=\$(perl -pe 's/\\e\\[[0-9;]*[mGKHJF]//g; s/\\r//g' "\$tmpf" 2>/dev/null || cat "\$tmpf"); rm -f "\$tmpf"
        [[ \$rc -ne 0 ]] && echo -e "\\033[31m[exit \$rc]\\033[0m"
        # Append output immediately as comments (before next LLM call, in case of crash)
        [[ -n "\$out" ]] && { local ln=\$(echo "\$out"|wc -l); if [[ \$ln -gt 1000 ]]; then { echo ""; echo "# PREV OUTPUT:"; echo "\$out"|head -400|uniq|sed 's/^/# /'; echo "# [...\$((ln-800)) snipped...]"; echo "\$out"|tail -400|uniq|sed 's/^/# /'; } >>"\$SELF"; else { echo ""; echo "# PREV OUTPUT:"; echo "\$out"|uniq|sed 's/^/# /'; } >>"\$SELF"; fi; }
        if [[ "$is_final" != "true" ]]; then
            feedback="\\nPREVIOUS OUTPUT (exit $rc):\\n$out\\n"
        elif [[ $rc -ne 0 && $rc -ne 141 && $iter -lt $MAX_ITER ]]; then
            echo -e "\\033[33m[recovery...]\\033[0m"; is_final="false"
            feedback="\\nFINAL FAILED (exit $rc):\\n$out\\nPlease fix.\\n"
        fi
    done
    if [[ "$is_final" != "true" ]]; then
        echo -e "\\033[33m[max iterations]\\033[0m Incomplete after $iter steps."
        read -rp $'\\033[95m  continue? [Y/n] \\033[0m' c
        if [[ -z "$c" || "$c" =~ ^[Yy] ]]; then iter=0; _evolve "$intent"; return; fi
        echo -e "\\033[36m[stopped]\\033[0m"
    fi
    echo -e "\\n_prompt\\n#" >> "$SELF"
    _prompt
}

_prompt() {
    read -rp $'\\033[95m  become? \\033[0m' i || exit
    [[ -z "$i" ]] && exit; _evolve "$i"
}

echo "anything.sh · ${PROVIDERS[provider].name} · ctrl+c = save & quit"
echo -e "\\033[36m  \$(uname -sm) | \$(. /etc/os-release 2>/dev/null && echo "\$PRETTY_NAME" || sw_vers -productName 2>/dev/null) | \$SHELL\\033[0m"
echo ""
[[ -n "\${1:-}" ]] && _evolve "$1" || _prompt
#
`;

const ASCII_LOGO = `
┌─┐┌┐┌┬ ┬┌┬┐┬ ┬┬┌┐┌┌─┐ ┌─┐┬ ┬
├─┤│││└┬┘ │ ├─┤│││││ ┬ └─┐├─┤
┴ ┴┘└┘ ┴  ┴ ┴ ┴┴┘└┘└─┘o└─┘┴ ┴`;

// Bash syntax highlighter
const highlightBash = (line: string): React.ReactNode[] => {
  // Handle comments first
  const commentMatch = line.match(/^(.*?)(#.*)$/);
  if (commentMatch) {
    const [, before, comment] = commentMatch;
    return [...highlightBash(before), <span key="comment" className="text-zinc-500 italic">{comment}</span>];
  }

  const tokens: React.ReactNode[] = [];
  const keywords = /\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|local|export|readonly|declare|trap|exit|break|continue|in|select|until)\b/g;
  const builtins = /\b(echo|read|cd|pwd|ls|cat|cp|mv|rm|mkdir|chmod|chown|sed|awk|grep|date|wc|test|source|\.|eval)\b/g;
  const operators = /(\[\[|\]\]|\(\(|\)\)|&&|\|\||[|;<>&])/g;
  const strings = /(["'])(?:(?!\1)[^\\]|\\.)*?\1/g;
  const variables = /(\$\{[^}]+\}|\$[a-zA-Z_][a-zA-Z0-9_]*|\$[0-9@#?!$*-])/g;
  const numbers = /\b([0-9]+)\b/g;

  // Combine all patterns
  const combined = new RegExp(
    `(${keywords.source})|(${builtins.source})|(${operators.source})|(${strings.source})|(${variables.source})|(${numbers.source})`,
    'g'
  );

  let lastIndex = 0;
  let match;
  let key = 0;

  while ((match = combined.exec(line)) !== null) {
    // Add text before match
    if (match.index > lastIndex) {
      tokens.push(line.slice(lastIndex, match.index));
    }

    const text = match[0];
    if (/^(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|local|export|readonly|declare|trap|exit|break|continue|in|select|until)$/.test(text)) {
      tokens.push(<span key={key++} className="text-purple-400 font-semibold">{text}</span>);
    } else if (/^(echo|read|cd|pwd|ls|cat|cp|mv|rm|mkdir|chmod|chown|sed|awk|grep|date|wc|test|source|\.|eval)$/.test(text)) {
      tokens.push(<span key={key++} className="text-blue-400">{text}</span>);
    } else if (/^(\[\[|\]\]|\(\(|\)\)|&&|\|\||[|;<>&])$/.test(text)) {
      tokens.push(<span key={key++} className="text-rose-400">{text}</span>);
    } else if (/^["']/.test(text)) {
      tokens.push(<span key={key++} className="text-emerald-400">{text}</span>);
    } else if (/^\$/.test(text)) {
      tokens.push(<span key={key++} className="text-amber-300">{text}</span>);
    } else if (/^[0-9]+$/.test(text)) {
      tokens.push(<span key={key++} className="text-cyan-400">{text}</span>);
    } else {
      tokens.push(text);
    }

    lastIndex = combined.lastIndex;
  }

  // Add remaining text
  if (lastIndex < line.length) {
    tokens.push(line.slice(lastIndex));
  }

  return tokens.length > 0 ? tokens : [line];
};

const ManPageSection = ({ title, children }) => (
  <div className="mb-8">
    <h3 className="text-emerald-500 font-bold uppercase tracking-widest mb-2 border-b border-emerald-900 pb-1 text-sm">
      {title}
    </h3>
    <div className="text-zinc-400 font-mono text-sm leading-relaxed pl-4 border-l border-zinc-800">
      {children}
    </div>
  </div>
);

// All providers in a flat list
const ALL_PROVIDERS: ProviderId[] = [
  'claude', 'codex', 'aider', 'gemini', 'goose', 'continue', 'opencode', 'kimi',
  'groq', 'openrouter'
];

const CopyButton = ({
  onClick,
  copied,
  className = ''
}: {
  onClick: () => void;
  copied: boolean;
  className?: string;
}) => (
  <button
    onClick={onClick}
    className={`flex items-center gap-2 bg-emerald-600 hover:bg-emerald-500 text-black font-bold px-4 py-2 text-xs uppercase tracking-wider transition-all active:translate-y-0.5 ${className}`}
  >
    {copied ? (
      <>Copied <Command className="w-3 h-3" /></>
    ) : (
      <>Copy Source <Copy className="w-3 h-3" /></>
    )}
  </button>
);

const ProviderSelector = ({
  provider,
  setProvider
}: {
  provider: ProviderId;
  setProvider: (p: ProviderId) => void;
}) => (
  <div className="mb-6 flex flex-wrap gap-1.5">
    {ALL_PROVIDERS.map((id) => {
      const isSelected = provider === id;
      return (
        <button
          key={id}
          onClick={() => setProvider(id)}
          className={isSelected
            ? 'px-2 py-1.5 text-xs uppercase tracking-wide font-bold transition-all duration-150 bg-emerald-600 text-black'
            : 'px-2 py-1.5 text-xs uppercase tracking-wide font-bold transition-all duration-150 bg-zinc-800 text-zinc-500 hover:bg-zinc-700 hover:text-zinc-300'
          }
        >
          {PROVIDERS[id].name}
        </button>
      );
    })}
  </div>
);

export default function AnythingSH() {
  const [activeTab, setActiveTab] = useState<'full' | 'terse'>('full');
  const [provider, setProvider] = useState<ProviderId>('claude');
  const [copied, setCopied] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [exitMessage] = useState(() => getRandomExitMessage());

  // Generate scripts based on selected provider
  const SCRIPT_FULL = getScriptFull(provider);
  const SCRIPT_TERSE = getScriptTerse(provider);

  // Typing effect for the "boot" sequence
  useEffect(() => {
    setMounted(true);
  }, []);

  const handleCopy = () => {
    const text = activeTab === 'full' ? SCRIPT_FULL : SCRIPT_TERSE;
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="min-h-screen bg-[#050505] text-zinc-300 font-mono selection:bg-emerald-900 selection:text-emerald-50">
      
      {/* CRT Scanline Effect Overlay */}
      <div className="fixed inset-0 pointer-events-none z-50 bg-[linear-gradient(rgba(18,16,16,0)_50%,rgba(0,0,0,0.25)_50%),linear-gradient(90deg,rgba(255,0,0,0.06),rgba(0,255,0,0.02),rgba(0,0,255,0.06))] bg-[length:100%_4px,3px_100%] opacity-20"></div>

      <div className="max-w-7xl mx-auto p-4 md:p-8 grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 relative z-10">
        
        {/* LEFT COLUMN: Documentation (Man Page Style) */}
        <div className="lg:col-span-5 space-y-8">
          
          {/* Header */}
          <div className="space-y-4">
            <pre className="text-[10px] md:text-xs leading-[0.8] text-emerald-600 font-bold whitespace-pre-wrap select-none overflow-hidden">
              {ASCII_LOGO}
            </pre>
            <div className="flex items-center gap-3">
              <span className="bg-emerald-900/30 text-emerald-400 border border-emerald-800/50 px-2 py-0.5 text-xs uppercase tracking-wider">v0.1.0-alpha</span>
              <span className="text-zinc-500 text-xs uppercase">Autopoietic Execution Loop</span>
            </div>
          </div>

          <div className="pt-8">
            <ManPageSection title="NAME">
              <span className="text-white font-bold">anything.sh</span> — the slime mold of bash. 
			{/* A living, autopoietic execution loop. */}
            </ManPageSection>

            <ManPageSection title="SYNOPSIS">
              <span className="text-emerald-400">./anything.sh</span> [<span className="text-zinc-500 underline">"become something"</span>]
            </ManPageSection>

            <ManPageSection title="DESCRIPTION">
              <p className="mb-4">
                In nature, the slime mold has no brain, no blueprint, no plan. Yet it solves mazes, optimises railway networks, and exhibits a form of memory. It doesn't follow a path — it <span className="text-emerald-400 italic">becomes</span> the path.
              </p>
              <p className="mb-4">
                <span className="text-white">anything.sh</span> is that, but worse. It's a bash script that rewrites itself while running. You type a request. It consults an LLM. The response — raw, executable bash — gets <span className="italic">appended to the script's own body</span> and executed immediately.
              </p>
              <p className="mb-4">
                The script grows. It <span className="text-emerald-400">pulses</span>. It reaches toward your intent like cytoplasm flowing toward food. One moment it's 50 lines. Then it's 200. Then it's whatever it needs to be.
              </p>
              <p className="mb-4 text-zinc-500 italic">
                "Traditional automation is a machine," the naturalist observed, lowering his voice so as not to startle it. "But this... this is <span className="text-white">biological logic</span>."
              </p>
              <p>
                When you press Ctrl+C, the evolved script is archived (a fossil record of computation) and the original is restored. The loop closes. <span className="text-zinc-500">Until next time.</span>
              </p>
            </ManPageSection>

            <ManPageSection title="PHILOSOPHY">
              <p className="mb-4">
                We spent decades writing "perfect" code. Optimising, refactoring, unit testing. <span className="text-white">anything.sh</span> asks: what if we simply <span className="italic">grew</span> the code instead?
              </p>
              <p className="text-zinc-500 italic">
                It's not written. It's <span className="text-emerald-400">grown</span>.
              </p>
            </ManPageSection>

            <ManPageSection title="FLAGS & WARNINGS">
              <div className="flex gap-4 items-start bg-amber-950/20 p-4 border border-amber-900/50 text-amber-500/90 text-xs">
                <ShieldAlert className="w-5 h-5 flex-shrink-0 mt-0.5" />
                <div>
                  <strong className="block mb-1 text-amber-400 uppercase tracking-wide">Here Be Dragons</strong>
                  This script executes LLM-generated code <span className="text-amber-200">without confirmation</span>. It will cheerfully delete your files, email your boss, or reorganise your music collection by astrological sign. The slime mold does not ask permission. <span className="text-amber-200">Use in a VM or container.</span>
                </div>
              </div>
            </ManPageSection>
            
            <div className="pt-12 text-zinc-600 text-xs space-y-1">
              <p>AUTHOR: XertroV</p>
              <p>LICENSE: Unlicense (Public Domain)</p>
              <p className="text-zinc-700 italic pt-2">No slime molds were harmed in the making of this script.</p>
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN: The Source Code */}
        <div className="lg:col-span-7 flex flex-col h-full">

          {/* Provider Selector */}
          <ProviderSelector provider={provider} setProvider={setProvider} />

          <div className="border border-zinc-800 bg-[#0a0a0a] flex-grow flex flex-col shadow-2xl relative overflow-hidden group">
            {/* Window Header */}
            <div className="bg-zinc-900 border-b border-zinc-800 px-4 py-2 flex items-center justify-between select-none">
              <div className="flex items-center gap-4">
                <div className="flex gap-1.5">
                  <div className="w-2.5 h-2.5 rounded-sm bg-zinc-700"></div>
                  <div className="w-2.5 h-2.5 rounded-sm bg-zinc-700"></div>
                  <div className="w-2.5 h-2.5 rounded-sm bg-zinc-700"></div>
                </div>
                <div className="text-xs flex">
                  <button
                    onClick={() => setActiveTab('full')}
                    className={`px-2 py-0.5 uppercase tracking-wide font-bold transition-all duration-150 ${
                      activeTab === 'full' 
                        ? 'bg-emerald-600 text-black' 
                        : 'text-zinc-500 hover:text-zinc-300'
                    }`}
                  >
                    full
                  </button>
                  <button
                    onClick={() => setActiveTab('terse')}
                    className={`px-2 py-0.5 uppercase tracking-wide font-bold transition-all duration-150 ${
                      activeTab === 'terse' 
                        ? 'bg-emerald-600 text-black' 
                        : 'text-zinc-500 hover:text-zinc-300'
                    }`}
                  >
                    compact
                  </button>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-[10px] text-zinc-600 uppercase tracking-widest">
                  {activeTab === 'full' ? '~2.5KB' : '~1KB'}
                </span>
                <CopyButton onClick={handleCopy} copied={copied} />
              </div>
            </div>

            {/* Code Content */}
            <div className="relative flex-grow overflow-auto custom-scrollbar bg-[#0c0c0c]">
               <pre className="p-4 md:p-6 text-xs md:text-sm leading-relaxed text-zinc-300 font-mono">
                <code className="block">
                  {(activeTab === 'full' ? SCRIPT_FULL : SCRIPT_TERSE).split('\n').map((line, i) => (
                    <div key={i} className="table-row">
                      <span className="table-cell text-zinc-700 text-right pr-4 select-none w-8">{i + 1}</span>
                      <span className="table-cell">{highlightBash(line)}</span>
                    </div>
                  ))}
                </code>
              </pre>
            </div>

            {/* Action Bar */}
            <div className="border-t border-zinc-800 bg-zinc-900/50 p-4 flex items-center justify-between backdrop-blur-sm">
              <div className="text-xs text-zinc-500 hidden md:block">
                {exitMessage}
              </div>
              <CopyButton onClick={handleCopy} copied={copied} className="ml-auto" />
            </div>
            
            {/* Visual Flair: Infinite Snake */}
            {activeTab === 'full' && (
              <div className="absolute bottom-16 right-6 pointer-events-none opacity-20 hidden lg:block">
                 <pre className="text-[8px] text-emerald-500 leading-none font-bold">
{`
      O
     / \\
    /   \\
   |  |  |
   |  |  |
   |  |  |
   |  |  |
  /   |   \\
  |   |   |
  |   |   |
  (   |   )
   \\  |  /
    \\ | /
     \\|/
`}
                 </pre>
              </div>
            )}
          </div>
        </div>

      </div>

{/* Custom scrollbar styles are in index.css */}
    </div>
  );
}
