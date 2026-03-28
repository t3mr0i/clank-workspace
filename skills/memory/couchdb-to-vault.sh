#!/bin/bash
# CouchDB LiveSync to Vault Filesystem Sync
# Handles chunked document format

set -euo pipefail

COUCH_USER="obsidian"
COUCH_PASS="011RKOAuv8p7vny13nYB"
COUCH_URL="http://127.0.0.1:5984"
DB_NAME="obsidianvault"
VAULT_DIR="$HOME/obsidian-vault"
AUTH="$COUCH_USER:$COUCH_PASS"

log() { echo "[$(date -Iseconds)] $*"; }

# Get document by ID
get_doc() {
    curl -s -u "$AUTH" "$COUCH_URL/$DB_NAME/$1" 2>/dev/null
}

# Reassemble file content from chunks
get_file_content() {
    local doc="$1"
    local children=$(echo "$doc" | jq -r '.children[]? // empty')
    local content=""
    
    for chunk_id in $children; do
        local chunk=$(get_doc "$chunk_id")
        local chunk_data=$(echo "$chunk" | jq -r '.data // empty')
        content+="$chunk_data"
    done
    
    echo "$content"
}

# Sync all files
sync_all() {
    log "Starting sync..."
    mkdir -p "$VAULT_DIR"
    
    # Get all file documents
    local file_ids=$(curl -s -u "$AUTH" "$COUCH_URL/$DB_NAME/_all_docs" | jq -r '.rows[].id' | grep '^f:')
    local count=0
    local total=$(echo "$file_ids" | wc -l)
    
    for doc_id in $file_ids; do
        local doc=$(get_doc "$doc_id")
        local path=$(echo "$doc" | jq -r '.path // empty')
        
        [[ -z "$path" ]] && continue
        [[ "$path" == /\\:%=* ]] && continue  # Skip encrypted
        
        local full_path="$VAULT_DIR/$path"
        mkdir -p "$(dirname "$full_path")"
        
        # Get content from chunks
        local content=$(get_file_content "$doc")
        
        if [[ -n "$content" ]]; then
            echo "$content" > "$full_path"
            ((count++))
            [[ $((count % 50)) -eq 0 ]] && log "Progress: $count/$total"
        fi
    done
    
    log "Synced $count files to $VAULT_DIR"
}

sync_all
