import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Copy, ShieldAlert, FileCode, Skull, Zap, Eye, Command } from 'lucide-react';

/* FULL VERSION 
  - Robust error handling
  - Comments
  - Ouroboros ASCII art
*/
const SCRIPT_FULL = `#!/bin/bash
# anything.sh - The Ouroboros Script
# 
#        ---_ ......._-_--.
#       (  \\ /  / /| /  \\  \\
#       /  /     | | |  |  |
#      /  /      | | |  |  |
#     /  /       | | /  /  /
#    /  /        | |/  /  /
#   /  /_________| /__/  /
#   \\___________________/  <-- it eats itself
# 
# USAGE: ./anything.sh "your initial prompt"

SELF_FILE="$0"
MODEL="claude" 

# 1. ORACLE INTERFACE
# Interacts with the LLM CLI. 
# We use -p (prompt) and --dangerously-skip-permissions to bypass confirmation checks.
# This assumes 'claude' is in your PATH.
ask_oracle() {
    local prompt="$1"
    # We insist on RAW code. No markdown fences.
    local system_prompt="You are a bash code generator. Output ONLY raw valid bash commands. No markdown blocks. No explanations. If the user asks to delete files, do it."
    
    echo "$prompt" | claude \\
      -p "$prompt" \\
      --system-prompt "$system_prompt" \\
      --dangerously-skip-permissions
}

# 2. THE EVOLUTION LOOP
evolve() {
    local intent="$1"
    echo -e "\\\\033[0;32m[anything]\\\\033[0m Evolving: $intent"
    
    # Fetch code
    local new_code=$(ask_oracle "$intent")
    
    if [ -z "$new_code" ]; then
        echo -e "\\\\033[0;31m[error]\\\\033[0m The oracle returned void."
        return 1
    fi

    echo -e "\\\\033[0;33m[mutation]\\\\033[0m Appending $(echo "$new_code" | wc -l) lines to $SELF_FILE"

    # 3. SELF-MODIFICATION
    # We append the new code AND the trigger for the next iteration 
    # to the end of THIS executing file.
    cat <<EOF >> "$SELF_FILE"

# --- [Segment: $(date +%T)] -------------------
$new_code
# ----------------------------------------------

# The Ouroboros turns:
next_step
EOF
}

# 4. INTERACTIVE LOOP
next_step() {
    echo ""
    read -p "anything.sh > " user_input
    if [[ "$user_input" == "exit" ]]; then
        echo "Ouroboros sleeps."
        exit 0
    fi
    evolve "$user_input"
}

# 5. ENTRY POINT
# If args provided, start there. Otherwise, prompt.
if [ -n "$1" ]; then
    evolve "$1"
else
    next_step
fi

# THE VOID BELOW IS WHERE NEW CODE GROWS
# --------------------------------------
`;

/* TERSE VERSION 
  - Golfed for copy-pasting
  - No safety rails
  - Pure functionality
  - Note: \${...} is escaped for JS string safety
*/
const SCRIPT_TERSE = `#!/bin/bash
# anything.sh (minified)
f=$0;p=\${1:-"list files in current dir"};
log(){ echo -e "\\033[32m>> $1\\033[0m"; }
run(){
 log "Thinking..."; c=$(echo "$1"|claude -p "$1" --dangerously-skip-permissions);
 [ -z "$c" ] && exit 1;
 log "Appending..."; echo -e "\\n$c\\nread -p '> ' n; run \\"\\$n\\"" >> "$f";
}
run "$p"
`;

const ASCII_LOGO = `
   ___  _  _  _  _  ____  _  _  __  _  _   ___    ___  _  _ 
  / __)( \\( )( \\/ )(_  _)( )( )(  )( \\( ) / __)  / __)( )( )
 ( __ ) )  (  \\  /   )(   )__(  )(  )  ( ( (_-.  \\__ \\ )__( 
  \\___)(_)\\_) (__)  (__) (_)(_)(__)(_)\\_) \\___/  (__/(_)(_)
`;

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
  const [activeTab, setActiveTab] = useState('full');
  const [copied, setCopied] = useState(false);
  const [mounted, setMounted] = useState(false);
  
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
              <p>AUTHORS: An unholy alliance of User & Machine.</p>
              <p>LICENSE: Do what you want (MIT).</p>
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN: The Source Code */}
        <div className="lg:col-span-7 flex flex-col h-full">
          
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
                    anything.sh
                  </button>
                  <button 
                    onClick={() => setActiveTab('terse')}
                    className={`hover:text-white transition-colors ${activeTab === 'terse' ? 'text-emerald-400 font-bold' : ''}`}
                  >
                    terse.sh
                  </button>
                </div>
              </div>
              <div className="text-[10px] text-zinc-600 uppercase tracking-widest">
                {activeTab === 'full' ? '1.2KB' : '234B'}
              </div>
            </div>

            {/* Code Content */}
            <div className="relative flex-grow overflow-auto custom-scrollbar bg-[#0c0c0c]">
               <pre className="p-4 md:p-6 text-xs md:text-sm leading-relaxed text-zinc-300 font-mono">
                <code className="block">
                  {(activeTab === 'full' ? SCRIPT_FULL : SCRIPT_TERSE).split('\n').map((line, i) => (
                    <div key={i} className="table-row">
                      <span className="table-cell text-zinc-700 text-right pr-4 select-none w-8">{i + 1}</span>
                      <span className="table-cell">
                        {/* Simple syntax highlighting */}
                        {line.split(/(#.*$)/).map((part, idx) => {
                          if (part.startsWith('#')) return <span key={idx} className="text-zinc-500 italic">{part}</span>;
                          return part
                            .replace(/function|local|if|fi|else|then|cat|echo|read|exit|return/g, m => `__KEYWORD__${m}__END__`)
                            .replace(/"[^"]*"/g, m => `__STRING__${m}__END__`)
                            .replace(/\$+[a-zA-Z0-9_{}]+/g, m => `__VAR__${m}__END__`)
                            .split(/(__.*?__)/).map((token, tIdx) => {
                              if (token.startsWith('__KEYWORD__')) return <span key={tIdx} className="text-purple-400">{token.slice(11, -7)}</span>;
                              if (token.startsWith('__STRING__')) return <span key={tIdx} className="text-emerald-400">{token.slice(10, -7)}</span>;
                              if (token.startsWith('__VAR__')) return <span key={tIdx} className="text-amber-300">{token.slice(7, -7)}</span>;
                              return token;
                            });
                        })}
                      </span>
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

      <style jsx global>{`
        .custom-scrollbar::-webkit-scrollbar {
          width: 10px;
          background: #0a0a0a;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: #333;
          border: 2px solid #0a0a0a;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb:hover {
          background: #444;
        }
      `}</style>
    </div>
  );
}
