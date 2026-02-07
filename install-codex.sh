
#!/usr/bin/env bash

PROVIDER=codex

bun install
bun run build
cp dist/$PROVIDER/full/anything.sh ~/.local/bin/anything.sh

echo ""
echo ""
echo "===  anything.sh for $PROVIDER installed to: ~/.local/bin/anything.sh  ==="
echo ""
