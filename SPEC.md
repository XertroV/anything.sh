# anything.sh - Specification

## Overview

**anything.sh** is a self-modifying bash script that uses LLM coding assistants to generate code that gets appended to itself during execution. The project consists of a website that showcases and allows users to copy these scripts.

The script follows an autopoietic pattern where it grows longer with each user command, creating a permanent audit trail of its own evolution.

## Core Concept

1. User runs `./anything.sh "do something"`
2. Script queries an LLM with the request + current script context
3. LLM generates bash code
4. Generated code is injected into the script file itself
5. Script continues executing, prompting for the next command
6. On exit (Ctrl+C or "exit"), the evolved script is archived and the original is restored

## Script Requirements

### File Structure

```
#!/bin/bash
<configuration: SELF, ORIG, STEP>
<backup initialization>
<cleanup function - runs via trap EXIT>
<_ask: query LLM with shared prompt>
<_evolve: append generated code>
<_prompt: interactive input>
<banner>
<entry point>
#   ← script ends with trailing comment
    ← generated code appends here with _prompt call
```

### Append-Based Execution

Instead of marker injection, the script simply appends:
```bash
# STEP N: user intent
step_N() { ... }
step_N
_prompt
#
```

Each `_prompt` call continues the loop until exit.

### Shared LLM Prompt

Both full and compact scripts use the same prompt template:

```
You are part of an AUTOPOIETIC, SELF-MODIFYING EXECUTION LOOP.

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
- Output ONLY valid bash code - NO markdown, NO explanation
- Your code is appended to this script and runs immediately
- Available: _ask, _evolve, _prompt, _cleanup
- Current STEP: $STEP
```

### Key Behaviors

1. **Backup on First Run**: Save original script to `anything.sh.orig`
2. **Archive on Exit**: Copy evolved script to `anything_YYYYMMDD_HHMMSS.log.sh`
3. **Restore on Exit**: Copy original back to `anything.sh`
4. **Context-Aware Prompting**: Send current script content to LLM for informed code generation
5. **Injection Before Marker**: New code inserted before `# @@INJECT@@` marker, not appended

### Supported LLM Providers

| Provider | CLI Command | Notes |
|----------|-------------|-------|
| Claude Code | `claude -p "..." --dangerously-skip-permissions` | Anthropic's official CLI |
| OpenAI Codex | `codex exec "..." --full-auto --model gpt-5.1-codex-mini --skip-git-repo-check` | OpenAI's coding agent |
| Aider | `aider --message "..." --yes --no-stream` | Open source AI pair programmer |
| Gemini CLI | `gemini -p "..."` | Google's CLI |
| Goose | `goose run -t "..."` | Block's coding agent |
| Continue | `cn -p "..." --allow Write --allow Bash` | Open source coding assistant |
| OpenCode | `opencode run "..."` | Open source terminal AI |
| Kimi CLI | `kimi --print --command "..."` | Moonshot's coding agent |
| Groq API | `curl` to Groq (Llama 3.3 70B) | Fast inference, free tier |
| OpenRouter | `curl` to OpenRouter | Access to multiple models |

### Script Variants

1. **Full Version** (~2.5KB)
   - Well-commented with section headers
   - Verbose output with colors
   - Full LLM prompt with detailed rules
   - `set -euo pipefail` for safety

2. **Compact Version** (~1KB)
   - Same functionality, shorter code
   - Readable if you know bash
   - Minimal comments
   - Suitable for quick copy-paste

## Website Requirements

### Tech Stack

- **Runtime**: Bun
- **Framework**: React 19
- **Styling**: Tailwind CSS
- **Icons**: Lucide React
- **Server**: Bun.serve() with HMR

### UI Components

1. **Left Column**: Documentation (man page style)
   - ASCII logo (Calvin S figlet font)
   - Version badge
   - NAME section
   - SYNOPSIS section
   - DESCRIPTION section
   - FLAGS & WARNINGS section
   - Author/License footer

2. **Right Column**: Code Display
   - Provider selector buttons (9 options)
   - Tab toggle: full / compact
   - Syntax-highlighted code view
   - Line numbers
   - Copy button
   - File size indicator

### Syntax Highlighting

Bash syntax highlighting with colors:
- **Purple**: Keywords (if, then, for, while, etc.)
- **Blue**: Builtins (echo, cat, sed, etc.)
- **Rose**: Operators (&&, ||, |, [[, ]])
- **Emerald**: Strings
- **Amber**: Variables ($VAR, ${VAR})
- **Cyan**: Numbers
- **Gray italic**: Comments

### Visual Design

- Dark terminal aesthetic (#050505 background)
- CRT scanline effect overlay
- Emerald accent color
- Monospace font throughout
- Custom scrollbar styling

## API/Direct Mode

For users without CLI tools installed, provide direct API access:

### Primary: Groq API
- Endpoint: `https://api.groq.com/openai/v1/chat/completions`
- Model: `llama-3.3-70b-versatile` (or latest)
- Requires: `GROQ_API_KEY` environment variable
- Fast inference, free tier available

### Alternative: OpenRouter API
- Endpoint: `https://openrouter.ai/api/v1/chat/completions`
- Model: User's choice via OpenRouter
- Requires: `OPENROUTER_API_KEY` environment variable
- Access to multiple models

## Safety Considerations

1. **Permission Bypass**: Scripts use `--dangerously-skip-permissions` or equivalent
2. **Sandbox Recommended**: Users should run in VM/container
3. **File Modification**: Script modifies itself - potential for data loss
4. **Network Access**: LLM queries require internet
5. **Code Execution**: Generated code runs immediately without review
6. **Safe Mode (Opt-in)**: `--safe` adds step approvals, high-risk command override prompts, and optional command allowlist via `--allow-cmd`.

## Development

```bash
# Install dependencies
bun install

# Run dev server (includes Tailwind watcher)
bun run dev

# Build for production
bun run build

# Run tests
bun test
```

## File Structure

```
anything.sh/
├── src/
│   ├── index.ts          # Bun server
│   ├── index.html         # Entry HTML
│   ├── index.css          # Tailwind + custom CSS
│   ├── frontend.tsx       # React entry point
│   ├── App.tsx            # App wrapper
│   └── anything_sh.tsx    # Main component + scripts
├── package.json
├── tailwind.config.js
├── tsconfig.json
├── CLAUDE.md              # AI assistant instructions
├── SPEC.md                # This file
└── README.md
```

## License

Unlicense (Public Domain)

## Author

XertroV
