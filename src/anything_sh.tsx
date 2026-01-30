import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Copy, ShieldAlert, FileCode, Skull, Zap, Eye, Command } from 'lucide-react';

// LLM CLI Provider configurations
const PROVIDERS = {
  claude: {
    name: 'Claude Code',
    cmd: 'claude -p "$full_prompt" --dangerously-skip-permissions 2>/dev/null',
    cmdTerse: 'claude -p "$1" --dangerously-skip-permissions',
  },
  codex: {
    name: 'OpenAI Codex',
    cmd: 'codex exec "$full_prompt" --full-auto 2>/dev/null',
    cmdTerse: 'codex exec "$1" --full-auto',
  },
  aider: {
    name: 'Aider',
    cmd: 'aider --message "$full_prompt" --yes --no-stream 2>/dev/null',
    cmdTerse: 'aider --message "$1" --yes --no-stream',
  },
  gemini: {
    name: 'Gemini CLI',
    cmd: 'gemini -p "$full_prompt" 2>/dev/null',
    cmdTerse: 'gemini -p "$1"',
  },
  goose: {
    name: 'Goose',
    cmd: 'goose run -t "$full_prompt" 2>/dev/null',
    cmdTerse: 'goose run -t "$1"',
  },
  continue: {
    name: 'Continue',
    cmd: 'cn -p "$full_prompt" --allow Write --allow Bash 2>/dev/null',
    cmdTerse: 'cn -p "$1" --allow Write --allow Bash',
  },
  opencode: {
    name: 'OpenCode',
    cmd: 'opencode run "$full_prompt" 2>/dev/null',
    cmdTerse: 'opencode run "$1"',
  },
  kimi: {
    name: 'Kimi CLI',
    cmd: 'kimi --print --command "$full_prompt" 2>/dev/null',
    cmdTerse: 'kimi --print --command "$1"',
  },
  api: {
    name: 'Direct API',
    cmd: `curl -s https://api.anthropic.com/v1/messages -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" -d '{"model":"claude-sonnet-4-20250514","max_tokens":4096,"messages":[{"role":"user","content":"'"$full_prompt"'"}]}' | jq -r '.content[0].text'`,
    cmdTerse: `curl -s https://api.anthropic.com/v1/messages -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" -d '{"model":"claude-sonnet-4-20250514","max_tokens":1024,"messages":[{"role":"user","content":"'"$1"'"}]}' | jq -r '.content[0].text'`,
  },
} as const;

type ProviderId = keyof typeof PROVIDERS;

// Generate full script with provider-specific CLI command
const getScriptFull = (provider: ProviderId) => `#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  anything.sh - The Ouroboros Script                            ║
# ║  A self-modifying bash script that grows with each command.    ║
# ║  Provider: ${PROVIDERS[provider].name.padEnd(49)}║
# ╚════════════════════════════════════════════════════════════════╝
# USAGE: ./anything.sh ["initial prompt"]

set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────
SELF="$0"
ORIG="\${SELF}.orig"
INJECT_MARKER="# @@INJECT@@"

# ─────────────────────────────────────────────────────────────────
# BACKUP: Save original on first run
# ─────────────────────────────────────────────────────────────────
[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG" && echo -e "\\\\033[36m[backup]\\\\033[0m $ORIG"

# ─────────────────────────────────────────────────────────────────
# CLEANUP: Runs on EXIT - archives session, restores original
# ─────────────────────────────────────────────────────────────────
_cleanup() {
    local rc=$?
    [[ -f "$ORIG" ]] || return $rc
    local archive="\${SELF%.sh}_$(date +%Y%m%d_%H%M%S).log.sh"
    cp "$SELF" "$archive" 2>/dev/null || true
    cp "$ORIG" "$SELF" 2>/dev/null || true
    echo ""
    echo -e "\\\\033[36m[archived]\\\\033[0m $archive"
    echo -e "\\\\033[36m[restored]\\\\033[0m $SELF"
    exit $rc
}
trap _cleanup EXIT

# ─────────────────────────────────────────────────────────────────
# ORACLE: Query ${PROVIDERS[provider].name} with script context
# ─────────────────────────────────────────────────────────────────
_ask() {
    local intent="$1"
    # Get script up to injection marker (the "static" part)
    local ctx=$(sed -n "1,/$INJECT_MARKER/p" "$SELF" 2>/dev/null | head -n -1)

    local full_prompt="You are extending a self-modifying bash script.

TASK: $intent

RULES:
- Output ONLY valid bash code, no markdown, no explanation
- Code will be appended and executed immediately
- You may call existing functions: _ask, _evolve, _prompt

CURRENT SCRIPT:
\`\`\`bash
$ctx
\`\`\`"

    ${PROVIDERS[provider].cmd}
}

# ─────────────────────────────────────────────────────────────────
# EVOLVE: Generate code and inject before marker
# ─────────────────────────────────────────────────────────────────
_evolve() {
    local intent="$1"
    echo -e "\\\\033[32m[evolving]\\\\033[0m $intent"

    local code=$(_ask "$intent")
    [[ -z "$code" ]] && echo -e "\\\\033[31m[error]\\\\033[0m empty response" && return 1

    echo -e "\\\\033[33m[+$(echo "$code" | wc -l) lines]\\\\033[0m"

    # Inject code before the marker
    local tmp=$(mktemp)
    awk -v code="$code" -v marker="$INJECT_MARKER" '
        $0 == marker { print "# --- [" strftime("%H:%M:%S") "] ---"; print code; print "_prompt"; print "" }
        { print }
    ' "$SELF" > "$tmp" && mv "$tmp" "$SELF"
    chmod +x "$SELF"
}

# ─────────────────────────────────────────────────────────────────
# PROMPT: Interactive input loop
# ─────────────────────────────────────────────────────────────────
_prompt() {
    echo ""
    read -rp $'\\\\033[35m  what shall I become? \\\\033[0m' input || exit 0
    [[ -z "$input" || "$input" == "exit" ]] && exit 0
    _evolve "$input"
}

# ─────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────
echo -e "\\\\033[32m┌─────────────────────────────────────┐\\\\033[0m"
echo -e "\\\\033[32m│\\\\033[0m   anything.sh · ouroboros protocol  \\\\033[32m│\\\\033[0m"
echo -e "\\\\033[32m│\\\\033[0m   provider: ${PROVIDERS[provider].name.toLowerCase().padEnd(23)}\\\\033[32m│\\\\033[0m"
echo -e "\\\\033[32m└─────────────────────────────────────┘\\\\033[0m"
echo "  Ctrl+C or 'exit' to save & quit"
echo ""

# ─────────────────────────────────────────────────────────────────
# ENTRY: Handle initial prompt or start interactive
# ─────────────────────────────────────────────────────────────────
[[ -n "\${1:-}" ]] && _evolve "$1" || _prompt

$INJECT_MARKER
# ─────────────────────────────────────────────────────────────────
# GENERATED CODE APPEARS ABOVE THIS LINE
# ─────────────────────────────────────────────────────────────────
`;

// Generate compact script with provider-specific CLI command
const getScriptTerse = (provider: ProviderId) => `#!/bin/bash
# anything.sh [compact] - ${PROVIDERS[provider].name}
set -euo pipefail

SELF="$0"; ORIG="\${SELF}.orig"; MARKER="# @@INJECT@@"

# Backup original
[[ ! -f "$ORIG" ]] && cp "$SELF" "$ORIG"

# Cleanup on exit: archive + restore
cleanup() {
    cp "$SELF" "\${SELF%.sh}_$(date +%s).log.sh" 2>/dev/null || true
    cp "$ORIG" "$SELF" 2>/dev/null || true
    echo -e "\\\\n\\\\033[36m[saved & restored]\\\\033[0m"
}
trap cleanup EXIT

# Query LLM
ask() {
    local ctx=$(sed -n "1,/$MARKER/p" "$SELF" | head -n -1)
    local full_prompt="Extend this bash script: $1

Output ONLY bash code.

SCRIPT:
$ctx"
    ${PROVIDERS[provider].cmd}
}

# Evolve: inject code before marker
evolve() {
    echo -e "\\\\033[32m[>]\\\\033[0m $1"
    local code=$(ask "$1")
    [[ -z "$code" ]] && echo "error: empty" && return 1
    local tmp=$(mktemp)
    awk -v c="$code" -v m="$MARKER" '$0==m{print"# ---";print c;print"prompt"}1' "$SELF" > "$tmp"
    mv "$tmp" "$SELF"; chmod +x "$SELF"
}

# Interactive prompt
prompt() {
    read -rp $'\\\\033[35m  become? \\\\033[0m' i || exit
    [[ -z "$i" ]] && exit
    evolve "$i"
}

echo "anything.sh | ${PROVIDERS[provider].name} | ctrl+c to quit"
[[ -n "\${1:-}" ]] && evolve "$1" || prompt

$MARKER
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

export default function AnythingSH() {
  const [activeTab, setActiveTab] = useState<'full' | 'terse'>('full');
  const [provider, setProvider] = useState<ProviderId>('claude');
  const [copied, setCopied] = useState(false);
  const [mounted, setMounted] = useState(false);

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
              <span className="text-zinc-500 text-xs uppercase">Bash Self-Replication Protocol</span>
            </div>
          </div>

          <div className="pt-8">
            <ManPageSection title="NAME">
              <span className="text-white font-bold">anything.sh</span> — a recursive, self-modifying shell agent.
            </ManPageSection>

            <ManPageSection title="SYNOPSIS">
              <span className="text-emerald-400">./anything.sh</span> [<span className="text-zinc-500 underline">initial_prompt</span>]
            </ManPageSection>

            <ManPageSection title="DESCRIPTION">
              <p className="mb-4">
                <span className="text-white">anything.sh</span> is a bash script that writes its own source code during execution.
              </p>
              <p className="mb-4">
                It utilizes the <span className="text-white">claude</span> CLI to generate bash commands based on user intent. These commands are appended to the script file itself (Ouroboros pattern) and executed immediately by the running interpreter.
              </p>
              <p>
                The script effectively functions as an infinite snake, growing longer with every command you issue, creating a permanent audit trail of its own evolution.
              </p>
            </ManPageSection>

            <ManPageSection title="FLAGS & WARNINGS">
              <div className="flex gap-4 items-start bg-amber-950/20 p-4 border border-amber-900/50 text-amber-500/90 text-xs">
                <ShieldAlert className="w-5 h-5 flex-shrink-0 mt-0.5" />
                <div>
                  <strong className="block mb-1 text-amber-400 uppercase tracking-wide">Dangerously Skip Permissions</strong>
                  This script invokes Claude with <code className="bg-amber-900/40 px-1 text-amber-200">--dangerously-skip-permissions</code>. It will execute file deletions, system modifications, and network requests without confirmation. Use inside a VM or container.
                </div>
              </div>
            </ManPageSection>
            
            <div className="pt-12 text-zinc-600 text-xs">
              <p>AUTHOR: XertroV</p>
              <p>LICENSE: Unlicense (Public Domain)</p>
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN: The Source Code */}
        <div className="lg:col-span-7 flex flex-col h-full">

          {/* Provider Selector */}
          <div className="mb-4 flex flex-wrap gap-2">
            {(Object.keys(PROVIDERS) as ProviderId[]).map((id) => (
              <button
                key={id}
                onClick={() => setProvider(id)}
                className={`px-3 py-1.5 text-xs border transition-colors ${
                  provider === id
                    ? 'border-emerald-500 bg-emerald-900/30 text-emerald-400'
                    : 'border-zinc-700 text-zinc-400 hover:border-zinc-500 hover:text-zinc-300'
                }`}
              >
                {PROVIDERS[id].name}
              </button>
            ))}
          </div>

          <div className="border border-zinc-800 bg-[#0a0a0a] flex-grow flex flex-col shadow-2xl relative overflow-hidden group">
            {/* Window Header */}
            <div className="bg-zinc-900 border-b border-zinc-800 px-4 py-2 flex items-center justify-between select-none">
              <div className="flex items-center gap-4">
                <div className="flex gap-1.5">
                  <div className="w-2.5 h-2.5 rounded-sm bg-zinc-700"></div>
                  <div className="w-2.5 h-2.5 rounded-sm bg-zinc-700"></div>
                  <div className="w-2.5 h-2.5 rounded-sm bg-zinc-700"></div>
                </div>
                <div className="text-xs text-zinc-400 flex gap-4">
                  <button
                    onClick={() => setActiveTab('full')}
                    className={`hover:text-white transition-colors ${activeTab === 'full' ? 'text-emerald-400 font-bold' : ''}`}
                  >
                    full
                  </button>
                  <button
                    onClick={() => setActiveTab('terse')}
                    className={`hover:text-white transition-colors ${activeTab === 'terse' ? 'text-emerald-400 font-bold' : ''}`}
                  >
                    compact
                  </button>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-[10px] text-zinc-600 uppercase tracking-widest">
                  {activeTab === 'full' ? '~2.5KB' : '~1KB'}
                </span>
                <button
                  onClick={handleCopy}
                  className="flex items-center gap-1.5 px-2 py-1 text-xs border border-zinc-700 hover:border-emerald-600 hover:text-emerald-400 text-zinc-400 transition-colors"
                >
                  <Copy className="w-3 h-3" />
                  <span className="w-10">{copied ? 'copied!' : 'copy'}</span>
                </button>
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
                Press <span className="text-zinc-300">CTRL+C</span> to kill the snake.
              </div>
              <button 
                onClick={handleCopy}
                className="ml-auto flex items-center gap-2 bg-emerald-600 hover:bg-emerald-500 text-black font-bold px-4 py-2 text-xs uppercase tracking-wider transition-all active:translate-y-0.5"
              >
                {copied ? (
                  <>Copied <Command className="w-3 h-3" /></>
                ) : (
                  <>Copy Source <Copy className="w-3 h-3" /></>
                )}
              </button>
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
