#!/bin/bash
# Health Check System (Log-Based)
# Usage: health-check.sh [--quiet] [--json]

set -euo pipefail

source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_HEALTH="${OPENCLAW_HEALTH:-$OPENCLAW_VAULT/_System/Health}"
    OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
    OPENCLAW_OLLAMA_PORT="${OPENCLAW_OLLAMA_PORT:-11434}"
    OPENCLAW_COUCHDB_PORT="${OPENCLAW_COUCHDB_PORT:-5984}"
    OPENCLAW_BROWSER_PORT="${OPENCLAW_BROWSER_PORT:-18801}"
    OPENCLAW_DISK_WARNING="${OPENCLAW_DISK_WARNING:-80}"
    OPENCLAW_DISK_CRITICAL="${OPENCLAW_DISK_CRITICAL:-90}"
    OPENCLAW_MEMORY_WARNING="${OPENCLAW_MEMORY_WARNING:-80}"
    OPENCLAW_MEMORY_CRITICAL="${OPENCLAW_MEMORY_CRITICAL:-95}"
}

HEALTH_DIR="$OPENCLAW_HEALTH"
STATUS_FILE="$HEALTH_DIR/status.json"
HISTORY_FILE="$HEALTH_DIR/history.jsonl"

QUIET=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet|-q) QUIET=true; shift ;;
        --json|-j) JSON_OUTPUT=true; shift ;;
        *) shift ;;
    esac
done

mkdir -p "$HEALTH_DIR"

TIMESTAMP=$(date -Iseconds)
OVERALL_STATUS="healthy"

check_service() {
    local name="$1"
    local check_cmd="$2"
    local status="unknown"
    local latency=0
    local message=""
    local start=$(date +%s%N)

    if eval "$check_cmd" > /dev/null 2>&1; then
        status="healthy"
        message="OK"
    else
        status="unhealthy"
        message="Service check failed"
        OVERALL_STATUS="degraded"
    fi

    local end=$(date +%s%N)
    latency=$(( (end - start) / 1000000 ))

    jq -nc --arg name "$name" --arg status "$status" --argjson latency "$latency" --arg message "$message" \
        '{name: $name, status: $status, latency_ms: $latency, message: $message}'
}

check_disk() {
    local usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    local status="healthy"
    local message="$usage% used"

    if [[ $usage -ge $OPENCLAW_DISK_CRITICAL ]]; then
        status="critical"
        OVERALL_STATUS="critical"
    elif [[ $usage -ge $OPENCLAW_DISK_WARNING ]]; then
        status="warning"
        [[ "$OVERALL_STATUS" != "critical" ]] && OVERALL_STATUS="degraded"
    fi

    jq -nc --arg name "disk" --arg status "$status" --argjson usage "$usage" --arg message "$message" \
        '{name: $name, status: $status, usage_percent: $usage, message: $message}'
}

check_memory() {
    local usage=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    local status="healthy"
    local message="$usage% used"

    if [[ $usage -ge $OPENCLAW_MEMORY_CRITICAL ]]; then
        status="critical"
        OVERALL_STATUS="critical"
    elif [[ $usage -ge $OPENCLAW_MEMORY_WARNING ]]; then
        status="warning"
        [[ "$OVERALL_STATUS" != "critical" ]] && OVERALL_STATUS="degraded"
    fi

    jq -nc --arg name "memory" --arg status "$status" --argjson usage "$usage" --arg message "$message" \
        '{name: $name, status: $status, usage_percent: $usage, message: $message}'
}

run_checks() {
    local services=()
    services+=("$(check_service "gateway" "curl -s --connect-timeout 5 http://localhost:$OPENCLAW_GATEWAY_PORT/health")")
    services+=("$(check_service "ollama" "curl -s --connect-timeout 5 http://localhost:$OPENCLAW_OLLAMA_PORT/api/tags")")
    services+=("$(check_service "couchdb" "curl -s --connect-timeout 5 http://localhost:$OPENCLAW_COUCHDB_PORT/")")
    services+=("$(check_service "browser" "curl -s --connect-timeout 5 http://localhost:$OPENCLAW_BROWSER_PORT/json/version")")
    services+=("$(check_disk)")
    services+=("$(check_memory)")

    printf '%s\n' "${services[@]}" | jq -s \
        --arg timestamp "$TIMESTAMP" --arg overall "$OVERALL_STATUS" \
        '{timestamp: $timestamp, overall_status: $overall, services: .}'
}

main() {
    local result=$(run_checks)
    echo "$result" > "$STATUS_FILE"
    echo "$result" | jq -c '.' >> "$HISTORY_FILE"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "$result" | jq .
    elif [[ "$QUIET" == "false" ]]; then
        echo "=== Health Check: $(date) ==="
        echo ""
        echo "$result" | jq -r '
            "Overall: \(.overall_status | ascii_upcase)",
            "",
            (.services[] | "[\(.status | if . == "healthy" then "OK" elif . == "warning" then "!!" else "XX" end)] \(.name): \(.message)")
        '
    fi

    case "$OVERALL_STATUS" in
        healthy) exit 0 ;;
        degraded) exit 1 ;;
        critical) exit 2 ;;
        *) exit 3 ;;
    esac
}

main
