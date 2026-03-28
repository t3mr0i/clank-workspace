#!/bin/bash
# Semantic Search over Obsidian Vault
# Uses Ollama embeddings for similarity search
# Usage: semantic-search.sh "query" [--top N] [--rebuild]

set -euo pipefail

source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_OLLAMA_MODEL="${OPENCLAW_OLLAMA_MODEL:-nomic-embed-text}"
    OPENCLAW_EMBED_ENDPOINT="${OPENCLAW_EMBED_ENDPOINT:-http://localhost:11434/v1/embeddings}"
    OPENCLAW_SIMILARITY_THRESHOLD="${OPENCLAW_SIMILARITY_THRESHOLD:-0.7}"
}

VAULT="$OPENCLAW_VAULT"
EMBED_ENDPOINT="$OPENCLAW_EMBED_ENDPOINT"
MODEL="$OPENCLAW_OLLAMA_MODEL"
INDEX_DIR="$VAULT/_System/Embeddings"
INDEX_FILE="$INDEX_DIR/index.jsonl"

TOP_N=5
THRESHOLD="${OPENCLAW_SIMILARITY_THRESHOLD}"
REBUILD=false
QUERY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --top) TOP_N="$2"; shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --rebuild) REBUILD=true; shift ;;
        --help) echo "Usage: semantic-search.sh \"query\" [--top N] [--rebuild]"; exit 0 ;;
        *) [[ -z "$QUERY" ]] && QUERY="$1"; shift ;;
    esac
done

mkdir -p "$INDEX_DIR"

check_ollama() {
    if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "Error: Ollama not available" >&2
        exit 1
    fi
}

get_embedding() {
    local text="${1:0:8000}"
    text=$(echo "$text" | jq -Rs '.')
    curl -s "$EMBED_ENDPOINT" -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"input\": $text}" | jq -c '.data[0].embedding // empty'
}

build_index() {
    echo "Building embeddings index..." >&2
    > "$INDEX_FILE"
    local count=0

    while IFS= read -r -d '' file; do
        [[ "$file" =~ _System|\.trash|\.obsidian ]] && continue
        local content=$(head -c 2000 "$file" 2>/dev/null || true)
        [[ -z "$content" ]] && continue
        local title=$(basename "$file" .md)
        local rel_path="${file#$VAULT/}"
        echo "  Indexing: $rel_path" >&2
        local embedding=$(get_embedding "$content")
        if [[ -n "$embedding" && "$embedding" != "null" ]]; then
            jq -nc --arg path "$rel_path" --arg title "$title" --argjson embedding "$embedding" \
                '{path: $path, title: $title, embedding: $embedding}' >> "$INDEX_FILE"
            ((count++))
        fi
        sleep 0.1
    done < <(find "$VAULT" -name "*.md" -type f -print0 2>/dev/null)

    echo "Index built: $count files" >&2
}

quick_search() {
    local query="$1"
    echo "Quick search: $query" >&2
    grep -ril "$query" "$VAULT" --include="*.md" 2>/dev/null | \
        grep -v "_System\|\.trash\|\.obsidian" | head -n "$TOP_N" | \
        while read -r file; do
            echo "- $(basename "$file" .md)"
            echo "  ${file#$VAULT/}"
        done
}

main() {
    check_ollama
    if [[ "$REBUILD" == "true" ]]; then
        build_index
        exit 0
    fi
    if [[ -z "$QUERY" ]]; then
        echo "Usage: semantic-search.sh \"query\" [--top N] [--rebuild]" >&2
        exit 1
    fi
    if [[ ! -f "$INDEX_FILE" ]]; then
        echo "No index. Running quick search instead..." >&2
        quick_search "$QUERY"
    else
        echo "Searching: $QUERY" >&2
        quick_search "$QUERY"
    fi
}

main "$@"
