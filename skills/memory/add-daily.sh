#!/bin/bash
# Add entry to today's daily note

CONTENT="$*"
MEMORY_DIR=~/memory
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%H:%M)
NOTE_FILE="$MEMORY_DIR/$TODAY.md"

if [ -z "$CONTENT" ]; then
    echo "Usage: add-daily.sh <content>"
    exit 1
fi

# Create note if doesn't exist
if [ ! -f "$NOTE_FILE" ]; then
    cat > "$NOTE_FILE" << HEADER
# Daily Note: $TODAY

## Events
HEADER
fi

# Append entry
echo "" >> "$NOTE_FILE"
echo "### $NOW" >> "$NOTE_FILE"
echo "$CONTENT" >> "$NOTE_FILE"

echo "Added to daily note: $NOTE_FILE"
