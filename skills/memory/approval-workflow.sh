#!/bin/bash
# Approval Workflow System
# Usage: approval-workflow.sh <command> [args]

set -euo pipefail

source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_PENDING="${OPENCLAW_PENDING:-$OPENCLAW_VAULT/_System/Pending}"
    OPENCLAW_SKILLS="${OPENCLAW_SKILLS:-/home/openclaw/.openclaw/skills}"
}

PENDING_DIR="$OPENCLAW_PENDING"
APPROVED_DIR="$PENDING_DIR/approved"
REJECTED_DIR="$PENDING_DIR/rejected"
INDEX_FILE="$PENDING_DIR/index.json"

mkdir -p "$PENDING_DIR" "$APPROVED_DIR" "$REJECTED_DIR"
[[ -f "$INDEX_FILE" ]] || echo '{"proposals": []}' > "$INDEX_FILE"

log_action() {
    if [[ -x "$OPENCLAW_SKILLS/memory/log-action.sh" ]]; then
        "$OPENCLAW_SKILLS/memory/log-action.sh" "$1" "approval-workflow" "$2" "high"
    fi
}

generate_id() { date +%s%N | sha256sum | head -c 8; }

propose() {
    local type="$1" title="$2" description="$3" payload="${4:-}" confidence="${5:-medium}"
    local id=$(generate_id) timestamp=$(date -Iseconds)
    local filename="$PENDING_DIR/${id}-${type}.md"

    cat > "$filename" << PROPOSAL
---
id: $id
type: $type
title: $title
status: pending
confidence: $confidence
created: $timestamp
---

# Proposal: $title

**Type**: $type | **ID**: \`$id\` | **Confidence**: $confidence

## Description
$description

## Proposed Action
\`\`\`
$payload
\`\`\`

## Commands
- \`approval-workflow.sh approve $id\`
- \`approval-workflow.sh reject $id "reason"\`
PROPOSAL

    local entry=$(jq -nc --arg id "$id" --arg type "$type" --arg title "$title" \
        --arg status "pending" --arg created "$timestamp" --arg file "$filename" \
        '{id: $id, type: $type, title: $title, status: $status, created: $created, file: $file}')
    jq --argjson entry "$entry" '.proposals += [$entry]' "$INDEX_FILE" > "${INDEX_FILE}.tmp"
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
    log_action "proposal_created" "New: $type - $title (ID: $id)"
    echo "$id"
}

list_proposals() {
    local status="${1:-pending}"
    echo "=== Proposals ($status) ==="
    jq -r --arg status "$status" \
        '.proposals[] | select(.status == $status) | "[\(.id)] \(.type): \(.title)"' "$INDEX_FILE"
}

approve() {
    local id="$1"
    local proposal=$(jq -r --arg id "$id" '.proposals[] | select(.id == $id)' "$INDEX_FILE")
    [[ -z "$proposal" || "$proposal" == "null" ]] && { echo "Not found: $id" >&2; exit 1; }
    local file=$(echo "$proposal" | jq -r '.file')
    local title=$(echo "$proposal" | jq -r '.title')
    jq --arg id "$id" '(.proposals[] | select(.id == $id)).status = "approved"' "$INDEX_FILE" > "${INDEX_FILE}.tmp"
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
    [[ -f "$file" ]] && mv "$file" "$APPROVED_DIR/"
    log_action "proposal_approved" "Approved: $title (ID: $id)"
    echo "Approved: $id"
}

reject() {
    local id="$1" reason="${2:-No reason}"
    local proposal=$(jq -r --arg id "$id" '.proposals[] | select(.id == $id)' "$INDEX_FILE")
    [[ -z "$proposal" || "$proposal" == "null" ]] && { echo "Not found: $id" >&2; exit 1; }
    local file=$(echo "$proposal" | jq -r '.file')
    local title=$(echo "$proposal" | jq -r '.title')
    jq --arg id "$id" '(.proposals[] | select(.id == $id)).status = "rejected"' "$INDEX_FILE" > "${INDEX_FILE}.tmp"
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
    [[ -f "$file" ]] && mv "$file" "$REJECTED_DIR/"
    log_action "proposal_rejected" "Rejected: $title - $reason"
    echo "Rejected: $id"
}

summary() {
    echo "=== Approval Workflow ==="
    local pending=$(jq '[.proposals[] | select(.status == "pending")] | length' "$INDEX_FILE")
    local approved=$(jq '[.proposals[] | select(.status == "approved")] | length' "$INDEX_FILE")
    local rejected=$(jq '[.proposals[] | select(.status == "rejected")] | length' "$INDEX_FILE")
    echo "Pending: $pending | Approved: $approved | Rejected: $rejected"
    [[ $pending -gt 0 ]] && list_proposals pending
}

case "${1:-summary}" in
    propose) shift; propose "$@" ;;
    list) list_proposals "${2:-pending}" ;;
    approve) approve "$2" ;;
    reject) shift; reject "$@" ;;
    summary) summary ;;
    *) echo "Commands: propose, list, approve, reject, summary" ;;
esac
