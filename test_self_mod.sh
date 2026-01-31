#!/bin/bash
# Test: Does bash execute code appended to itself during execution?

SELF="$0"
echo "Starting test..."

# Function that appends code to self and returns
append_and_return() {
    echo "In append_and_return, about to append code..."

    # Remove trailing # marker (2 bytes: "#\n")
    head -c -2 "$SELF" > "$SELF.tmp" && mv "$SELF.tmp" "$SELF"

    # Append new code
    cat >> "$SELF" <<'APPENDED'

echo "THIS WAS APPENDED AND EXECUTED!"
echo "Step 2 running..."
#
APPENDED

    echo "Code appended, returning from function..."
    return
}

# Call the function
append_and_return
echo "Back from append_and_return"
#
