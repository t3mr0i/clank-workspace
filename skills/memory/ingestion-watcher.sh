#!/bin/bash
# Ingestion Watcher - Auto-classify inbox files
# Runs as user service (no root)

set -euo pipefail

source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_SKILLS="${OPENCLAW_SKILLS:-/home/openclaw/.openclaw/skills}"
}

VAULT="$OPENCLAW_VAULT"
INBOX="$VAULT/00_Inbox"
PROJECTS="$VAULT/01_Projects"
AREAS="$VAULT/02_Areas"
RESOURCES="$VAULT/03_Resources"
ARCHIVE="$VAULT/04_Archive"

mkdir -p "$INBOX"

log() { echo "[$(date -Iseconds)] $*"; }

log_action() {
    [[ -x "$OPENCLAW_SKILLS/memory/log-action.sh" ]] && \
        "$OPENCLAW_SKILLS/memory/log-action.sh" "ingestion" "watcher" "$1" "high"
}

classify_file() {
    local content=$(head -c 2000 "$1" 2>/dev/null || echo "")
    if echo "$content" | grep -qiE "(project|milestone|deadline|sprint)"; then echo "project"
    elif echo "$content" | grep -qiE "(process|routine|recurring|maintenance)"; then echo "area"
    elif echo "$content" | grep -qiE "(article|book|video|tutorial|reference)"; then echo "resource"
    elif echo "$content" | grep -qiE "(completed|archived|deprecated)"; then echo "archive"
    else echo "inbox"; fi
}

process_file() {
    local file="$1" filename=$(basename "$1")
    [[ "$filename" =~ ^\.|\.tmp$|~$ ]] && return
    [[ ! "$filename" =~ \.md$ ]] && return

    log "Processing: $filename"
    local classification=$(classify_file "$file")
    local dest=""

    case "$classification" in
        project) dest="$PROJECTS/Unsorted"; mkdir -p "$dest" ;;
        area) dest="$AREAS/Unsorted"; mkdir -p "$dest" ;;
        resource) dest="$RESOURCES/Unsorted"; mkdir -p "$dest" ;;
        archive) dest="$ARCHIVE/$(date +%Y)"; mkdir -p "$dest" ;;
        *) return ;;
    esac

    if [[ -n "$dest" ]]; then
        mv "$file" "$dest/"
        log "Moved to: $dest/$filename"
        log_action "Moved $filename to $dest"
    fi
}

watch_inbox() {
    log "Starting ingestion watcher on: $INBOX"
    
    if ! command -v inotifywait &> /dev/null; then
        log "inotifywait not found, running in poll mode"
        while true; do
            for file in "$INBOX"/*.md; do
                [[ -f "$file" ]] && process_file "$file"
            done
            sleep 30
        done
    else
        for file in "$INBOX"/*.md; do
            [[ -f "$file" ]] && process_file "$file"
        done
        inotifywait -m -e create -e moved_to --format '%w%f' "$INBOX" | while read -r file; do
            sleep 1
            [[ -f "$file" ]] && process_file "$file"
        done
    fi
}

log_action "Ingestion watcher started"
watch_inbox
