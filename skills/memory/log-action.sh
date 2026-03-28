#!/bin/bash
# Transparency Ledger - Structured Action Logging
# Usage: log-action.sh <action_type> <source> <description> [confidence]

set -euo pipefail

source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_LOGS="${OPENCLAW_LOGS:-$OPENCLAW_VAULT/_System/Logs}"
}

VAULT="$OPENCLAW_VAULT"
LOG_DIR="$OPENCLAW_LOGS"
JSONL_FILE="$LOG_DIR/actions.jsonl"
DATE=$(date +%Y-%m-%d)
DAILY_FILE="$LOG_DIR/daily/$DATE.md"

ACTION_TYPE="${1:-unknown}"
SOURCE="${2:-manual}"
DESCRIPTION="${3:-No description}"
CONFIDENCE="${4:-high}"

TIMESTAMP=$(date -Iseconds)
TIME=$(date +%H:%M:%S)
ID=$(date +%s%N | sha256sum | head -c 8)

mkdir -p "$LOG_DIR/daily"

cat >> "$JSONL_FILE" << ENTRY
{"id":"$ID","ts":"$TIMESTAMP","type":"$ACTION_TYPE","source":"$SOURCE","desc":"$DESCRIPTION","confidence":"$CONFIDENCE"}
ENTRY

if [ ! -f "$DAILY_FILE" ]; then
    cat > "$DAILY_FILE" << HEADER
---
date: $DATE
type: action-log
---

# Action Log: $DATE

| Time | Action | Source | Description | Confidence |
|------|--------|--------|-------------|------------|
HEADER
fi

echo "| $TIME | \`$ACTION_TYPE\` | $SOURCE | $DESCRIPTION | $CONFIDENCE |" >> "$DAILY_FILE"
echo "$ID"
