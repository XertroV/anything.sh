import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Copy, ShieldAlert, FileCode, Skull, Zap, Eye, Command, Download, X } from 'lucide-react';
import { getRandomExitMessage } from './exitMessages';
import { 
  LLM_PROMPT, 
  PROVIDERS, 
  ALL_PROVIDERS, 
  type ProviderId, 
  getScriptFull, 
  getScriptCompact 
} from './scriptGenerator';

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
    } else if (/^(\[\||\]\]|\(\(|\)\)|&&|\|\||[|;<>&])$/.test(text)) {
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

const CopyButton = ({
  onClick,
  copied,
  className = '',
  label = 'Copy Source',
  icon: Icon = Copy
}: {
  onClick: () => void;
  copied: boolean;
  className?: string;
  label?: string;
  icon?: React.ComponentType<{ className?: string }>;
}) => (
  <button
    onClick={onClick}
    className={`flex items-center gap-2 bg-emerald-600 hover:bg-emerald-500 text-black font-bold px-4 py-2 text-xs uppercase tracking-wider transition-all active:translate-y-0.5 ${className}`}
  >
    {copied ? (
      <>Copied <Command className="w-3 h-3" /></>
    ) : (
      <>{label} <Icon className="w-3 h-3" /></>
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

const EXAMPLE_PROMPTS = [
  "build a roguelike dungeon crawler, inspired by Hades and Slay the Spire",
  "scan my network with nmap, find unknown devices and check their ports",
  "build an interactive Python game that uses the same autopoietic self-modifying pattern",
  "teach me shell scripting basics with hands-on interactive examples",
  "analyze my bash history, find most-used commands and suggest aliases",
  "clean up all old unused Docker resources, reclaim disk space safely",
  "create a DNS lookup explainer, trace the path from root to any domain",
  "find my porn stash, locate video files scattered around and organize them",
  "build a system health dashboard, real-time CPU memory disk and process stats",
  "generate a hypnotic terminal screensaver, mesmerizing ASCII animations",
];

export default function AnythingSH() {
  const [activeTab, setActiveTab] = useState<'full' | 'compact'>('full');
  const [provider, setProvider] = useState<ProviderId>(() => {
    // Load from localStorage on mount
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('anything-provider');
      if (saved && ALL_PROVIDERS.includes(saved as ProviderId)) {
        return saved as ProviderId;
      }
    }
    return 'claude';
  });
  const [copied, setCopied] = useState(false);
  const [urlCopied, setUrlCopied] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [exitMessage] = useState(() => getRandomExitMessage());
  const [exampleIndex, setExampleIndex] = useState(0);
  const [warningDismissed, setWarningDismissed] = useState(false);

  // Load warning dismissed state from localStorage
  useEffect(() => {
    const dismissed = localStorage.getItem('anything.sh_warning_dismissed');
    if (dismissed === 'true') {
      setWarningDismissed(true);
    }
  }, []);

  // Generate scripts based on selected provider
  const SCRIPT_FULL = getScriptFull(provider);
  const SCRIPT_COMPACT = getScriptCompact(provider);

  // Typing effect for the "boot" sequence
  useEffect(() => {
    setMounted(true);
  }, []);

  // Cycle through example prompts
  useEffect(() => {
    const interval = setInterval(() => {
      setExampleIndex((prev) => (prev + 1) % EXAMPLE_PROMPTS.length);
    }, 6000); // Change every 6 seconds
    return () => clearInterval(interval);
  }, []);

  // Persist provider choice to localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('anything-provider', provider);
    }
  }, [provider]);

  const handleDismissWarning = () => {
    setWarningDismissed(true);
    localStorage.setItem('anything.sh_warning_dismissed', 'true');
  };

  const handleCopy = () => {
    const text = activeTab === 'full' ? SCRIPT_FULL : SCRIPT_COMPACT;
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // Helper to get base URL including pathname for GitHub Pages subdirectories
  const getBaseUrl = () => {
    if (typeof window === 'undefined') return '';
    const pathParts = window.location.pathname.split('/').filter(Boolean);
    // If we're in a subdirectory (like /anything.sh/), include it
    const basePath = pathParts.length > 0 ? '/' + pathParts[0] : '';
    return window.location.origin + basePath;
  };

  const handleCopyUrl = () => {
    const baseUrl = getBaseUrl();
    const url = `${baseUrl}/${provider}/${activeTab}/anything.sh`;
    navigator.clipboard.writeText(url);
    setUrlCopied(true);
    setTimeout(() => setUrlCopied(false), 2000);
  };

  // Compute download URL
  const baseUrl = getBaseUrl();
  const downloadUrl = `${baseUrl}/${provider}/${activeTab}/anything.sh`;

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

          {/* Warning Banner - Dismissible */}
          {!warningDismissed && (
            <div className="mt-8 mb-4">
              <div className="relative bg-amber-950/30 border border-amber-800/50 p-4 text-amber-400/90 text-xs">
                <button
                  onClick={handleDismissWarning}
                  className="absolute top-2 right-2 p-1 text-amber-600 hover:text-amber-400 transition-colors"
                  title="Dismiss warning"
                >
                  <X className="w-4 h-4" />
                </button>
                <div className="flex gap-4 items-start pr-6">
                  <ShieldAlert className="w-5 h-5 flex-shrink-0 mt-0.5" />
                  <div>
                    <strong className="block mb-1 text-amber-400 uppercase tracking-wide">Here Be Dragons</strong>
                    This script executes LLM-generated code <span className="text-amber-200">without confirmation</span>. It will cheerfully delete your files, email your boss, or reorganise your music collection by astrological sign. The slime mold does not ask permission. <span className="text-amber-200">Use in a VM or container.</span>
                  </div>
                </div>
              </div>
            </div>
          )}

          <div className="pt-8">
            <ManPageSection title="NAME">
              <span className="text-white font-bold">anything.sh</span> — the slime mold of bash. 
            </ManPageSection>

            <ManPageSection title="SYNOPSIS">
              <span className="text-emerald-400">./anything.sh</span> [<span key={exampleIndex} className="text-zinc-500 underline animate-fadeIn">"{EXAMPLE_PROMPTS[exampleIndex]}"</span>]
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
              <p className="mb-4 text-zinc-400 italic">
                Beauty without architecture. Order without structure. Risk without reward.
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

            <ManPageSection title="ENVIRONMENT">
              <p className="mb-2">
                <span className="text-emerald-400">ANYTHING_EXTRA</span> — Optional. Inject custom context into the LLM prompt.
              </p>
              <p className="mb-4 text-zinc-500 text-xs pl-4">
                Use to advertise platform-specific tools (e.g. <code className="text-zinc-400">say</code> on macOS), inform about installed utilities, or add task-specific instructions.
              </p>
              <div className="bg-zinc-950/50 border border-zinc-800 p-3 font-mono text-xs text-zinc-400">
                <span className="text-zinc-600"># Example: macOS text-to-speech</span><br/>
                <span className="text-emerald-400">export</span> ANYTHING_EXTRA=<span className="text-amber-400">"say command available for TTS"</span><br/>
                <span className="text-zinc-400">./anything.sh</span> <span className="text-zinc-500">"narrate a spooky story"</span>
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
            {/* Download URL Section */}
            <div className="border-b border-zinc-800 bg-zinc-900/30 p-3 backdrop-blur-sm mb-2">
              <div className="flex flex-col sm:flex-row sm:items-center gap-2">
                <div className="flex items-center gap-2 text-[10px] text-zinc-500 uppercase tracking-wider flex-shrink-0">
                  <Download className="w-3 h-3" />
                  <span>Download</span>
                </div>
                <div className="flex-1 flex items-center gap-2">
                  <code className="flex-1 bg-zinc-950 border border-zinc-800 px-2 py-1.5 text-xs text-emerald-400 font-mono truncate">
                    {downloadUrl}
                  </code>
                  <CopyButton 
                    onClick={handleCopyUrl} 
                    copied={urlCopied} 
                    label="Copy"
                    className="flex-shrink-0 py-1.5 px-3"
                  />
                </div>
              </div>
            </div>

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
                    onClick={() => setActiveTab('compact')}
                    className={`px-2 py-0.5 uppercase tracking-wide font-bold transition-all duration-150 ${
                      activeTab === 'compact' 
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
                  {(activeTab === 'full' ? SCRIPT_FULL : SCRIPT_COMPACT).split('\n').map((line, i) => (
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
    </div>
  );
}
