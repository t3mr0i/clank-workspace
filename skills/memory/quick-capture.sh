#!/bin/bash
# Quick Capture for Second Brain (with Transparency Logging)
# Usage: quick-capture.sh <type> <content>
# Types: link, idea, task, note

SCRIPT_DIR="$(dirname "$0")"
source_log() { "$SCRIPT_DIR/log-action.sh" "$@"; }

TYPE=$1
shift
CONTENT="$*"
VAULT=~/obsidian-vault
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
FILENAME=$(echo "$CONTENT" | head -c 30 | tr ' ' '-' | tr -cd '[:alnum:]-')

case $TYPE in
    link|url)
        TARGET="$VAULT/00_Inbox/Links/$DATE-$FILENAME.md"
        echo "# Link: $CONTENT" > "$TARGET"
        echo "" >> "$TARGET"
        echo "- Captured: $DATE $TIME" >> "$TARGET"
        echo "- Status: unprocessed" >> "$TARGET"
        echo "" >> "$TARGET"
        echo "## Notes" >> "$TARGET"
        echo "[To be summarized]" >> "$TARGET"
        source_log "capture" "quick-capture" "Link saved: $CONTENT" "high"
        echo "✓ Link → 00_Inbox/Links/"
        ;;
    idea|idee)
        TARGET="$VAULT/00_Inbox/ideas/$DATE-$FILENAME.md"
        echo "# 💡 Idee: $CONTENT" > "$TARGET"
        echo "" >> "$TARGET"
        echo "- Captured: $DATE $TIME" >> "$TARGET"
        echo "" >> "$TARGET"
        echo "## Details" >> "$TARGET"
        echo "[Expand later]" >> "$TARGET"
        source_log "capture" "quick-capture" "Idea saved: $CONTENT" "high"
        echo "✓ Idee → 00_Inbox/ideas/"
        ;;
    task|todo|aufgabe)
        TARGET="$VAULT/00_Inbox/Tasks/$DATE-$FILENAME.md"
        echo "# ☐ Task: $CONTENT" > "$TARGET"
        echo "" >> "$TARGET"
        echo "- Created: $DATE $TIME" >> "$TARGET"
        echo "- Status: open" >> "$TARGET"
        echo "- Priority: normal" >> "$TARGET"
        echo "" >> "$TARGET"
        echo "## Details" >> "$TARGET"
        echo "[Add context]" >> "$TARGET"
        source_log "capture" "quick-capture" "Task saved: $CONTENT" "high"
        echo "✓ Task → 00_Inbox/Tasks/"
        ;;
    note|notiz)
        TARGET="$VAULT/00_Inbox/$DATE-$FILENAME.md"
        echo "# Note: $DATE" > "$TARGET"
        echo "" >> "$TARGET"
        echo "$CONTENT" >> "$TARGET"
        echo "" >> "$TARGET"
        echo "---" >> "$TARGET"
        echo "*Captured: $TIME*" >> "$TARGET"
        source_log "capture" "quick-capture" "Note saved: ${CONTENT:0:50}..." "high"
        echo "✓ Notiz → 00_Inbox/"
        ;;
    *)
        TARGET="$VAULT/00_Inbox/$DATE-$FILENAME.md"
        echo "# $CONTENT" > "$TARGET"
        echo "" >> "$TARGET"
        echo "- Captured: $DATE $TIME" >> "$TARGET"
        source_log "capture" "quick-capture" "Item saved: ${CONTENT:0:50}..." "medium"
        echo "✓ Gespeichert → 00_Inbox/"
        ;;
esac
