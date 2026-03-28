#!/bin/bash
# Quick recall - Get entity summary

NAME="$1"
LIFE_DIR=~/life

if [ -z "$NAME" ]; then
    echo "Usage: recall.sh <entity-name>"
    exit 1
fi

# Search for entity
FOUND=$(find $LIFE_DIR -type d -name "$NAME" 2>/dev/null | head -1)

if [ -z "$FOUND" ]; then
    echo "Entity not found: $NAME"
    echo ""
    echo "Available entities:"
    find $LIFE_DIR -name "summary.md" -exec dirname {} \; | xargs -I{} basename {} | sort -u
    exit 1
fi

echo "=== $NAME ==="
if [ -f "$FOUND/summary.md" ]; then
    cat "$FOUND/summary.md"
fi

if [ -f "$FOUND/items.json" ]; then
    echo ""
    echo "=== Active Facts ==="
    jq '.[] | select(.status == "active") | .fact' "$FOUND/items.json" 2>/dev/null
fi
