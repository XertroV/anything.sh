
# anything.sh

<https://github.com/XertroV/anything.sh>

Copy or save the script to `~/.local/bin/anything.sh` (or somewhere in `PATH`) and then just run `anything.sh` or `anything.sh "install docker and docker compose"` (or whatever you want it to do). 

Note: there are different versions of the script for each provider (claude code, groq api, opencode, etc).

## Examples

```bash
anything.sh "text adventure, d&d style and stats, fantasy"
anything.sh "text adventure, d&d style and stats, inspiration: fantasy steampunk gothic bloodborne, pretty TUI"
anything.sh "compile bitcoind from source (use bitcoin knots)"
anything.sh "teach me how to script for the fish shell"
anything.sh "make todd proud and release skyrim for bash, immersive TUI, atmospheric, action RPG"
anything.sh "set git to use different ed25519 key"
anything.sh "install docker and docker compose"
```

## Build & Install

```
bun install
bun run build
cp dist/claude/full/anything.sh ~/.local/bin/anything.sh
```

## Safe Mode

`anything.sh` supports an opt-in safe mode with review gates:

```bash
anything.sh --safe "set up a demo project"
anything.sh --safe --allow-cmd "ls,cat,grep,git,mkdir,touch" "inspect repo and summarize"
anything.sh --safe --safe-show-code "explain and modify my shell config"
```

Safe mode adds:
- Step approval (`approve step? [y/N]`)
- Explicit override prompt for blocked-risk patterns
- Optional command allowlist (`--allow-cmd`)
- Safer provider CLI invocation where available
