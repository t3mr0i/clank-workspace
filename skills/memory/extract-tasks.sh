#!/bin/bash
# Structured Task Extractor
# Extracts explicit and implicit tasks from Obsidian vault
# Usage: extract-tasks.sh [vault_path] [--json] [--implicit]

set -euo pipefail

# Source configuration
source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_EXTRACTED="${OPENCLAW_EXTRACTED:-$OPENCLAW_VAULT/_System/Extracted}"
}

VAULT="${1:-$OPENCLAW_VAULT}"
OUTPUT_DIR="$OPENCLAW_EXTRACTED"
OUTPUT_JSON=false
INCLUDE_IMPLICIT=false

# Parse args
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --json) OUTPUT_JSON=true; shift ;;
        --implicit) INCLUDE_IMPLICIT=true; shift ;;
        *) shift ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# Implicit task patterns
IMPLICIT_PATTERNS=(
    "need to"
    "should"
    "must"
    "have to"
    "will"
    "going to"
    "want to"
    "plan to"
    "remember to"
    "don't forget"
)

# Extract tasks from TaskNotes frontmatter (individual .md files)
extract_tasknotes_tasks() {
    local tasknotes_dir="$VAULT/TaskNotes/Tasks"
    [[ ! -d "$tasknotes_dir" ]] && return

    while IFS= read -r -d '' file; do
        local rel_path="${file#$VAULT/}"

        # Skip legacy todoist-tasks.md
        [[ "$rel_path" == "00_Inbox/Tasks/todoist-tasks.md" ]] && continue

        # Read frontmatter fields
        local title status priority due todoist_id project
        title=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^title:" | head -1 | sed 's/^title:[[:space:]]*//' | sed 's/^"//;s/"$//')
        status=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^status:" | head -1 | sed 's/^status:[[:space:]]*//')
        priority=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^priority:" | head -1 | sed 's/^priority:[[:space:]]*//')
        due=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^due:" | head -1 | sed 's/^due:[[:space:]]*//')
        todoist_id=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^todoist-id:" | head -1 | sed 's/^todoist-id:[[:space:]]*//' | sed 's/^"//;s/"$//')

        # Extract first project from YAML list
        project=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep -A1 -- "^projects:" | tail -1 | sed 's/^[[:space:]]*- //' | sed 's/^"//;s/"$//')
        [[ "$project" == "projects:" || "$project" == "[]" ]] && project=""

        # Check for task tag in frontmatter
        local has_task_tag
        has_task_tag=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep -cF -- "- task" || true)
        [[ "$has_task_tag" -eq 0 ]] && continue

        # Skip done tasks
        [[ "$status" == "done" ]] && continue

        # Skip empty titles
        [[ -z "$title" ]] && continue

        jq -nc \
            --arg type "tasknote" \
            --arg content "$title" \
            --arg source_file "$rel_path" \
            --arg line "1" \
            --arg project "${project:-Uncategorized}" \
            --arg deadline "${due:-}" \
            --arg confidence "high" \
            --arg status "${status:-open}" \
            --arg priority "${priority:-none}" \
            --arg todoist_id "${todoist_id:-}" \
            '{type: $type, content: $content, source_file: $source_file, line: ($line|tonumber), project: $project, deadline: $deadline, confidence: $confidence, status: $status, priority: $priority, todoist_id: $todoist_id}'
    done < <(find "$tasknotes_dir" -name "*.md" -type f -print0 2>/dev/null)
}

# Extract explicit checkbox tasks
extract_explicit_tasks() {
    local file="$1"
    local rel_path="${file#$VAULT/}"

    grep -n '^\s*- \[ \]' "$file" 2>/dev/null | while IFS=: read -r line_num content; do
        # Clean the task content
        task=$(echo "$content" | sed 's/^\s*- \[ \]\s*//')

        # Try to extract project from path
        local project="Uncategorized"
        if [[ "$rel_path" =~ ^01_Projects/([^/]+) ]]; then
            project="${BASH_REMATCH[1]}"
        elif [[ "$rel_path" =~ ^02_Areas/([^/]+) ]]; then
            project="${BASH_REMATCH[1]}"
        fi

        # Look for deadline patterns
        local deadline=""
        if [[ "$task" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
            deadline="${BASH_REMATCH[1]}"
        fi

        # Output JSON object
        jq -nc \
            --arg type "explicit" \
            --arg content "$task" \
            --arg source_file "$rel_path" \
            --arg line "$line_num" \
            --arg project "$project" \
            --arg deadline "$deadline" \
            --arg confidence "high" \
            '{type: $type, content: $content, source_file: $source_file, line: ($line|tonumber), project: $project, deadline: $deadline, confidence: $confidence}'
    done
}

# Extract implicit tasks from natural language
extract_implicit_tasks() {
    local file="$1"
    local rel_path="${file#$VAULT/}"

    for pattern in "${IMPLICIT_PATTERNS[@]}"; do
        grep -niE "(^|[.!?] )[^.!?]*\b${pattern}\b[^.!?]*" "$file" 2>/dev/null | while IFS=: read -r line_num content; do
            # Skip if it's already a checkbox
            [[ "$content" =~ ^\s*-\ \[ ]] && continue

            # Clean content
            task=$(echo "$content" | sed 's/^[[:space:]]*//' | head -c 200)

            # Get project context
            local project="Uncategorized"
            if [[ "$rel_path" =~ ^01_Projects/([^/]+) ]]; then
                project="${BASH_REMATCH[1]}"
            fi

            jq -nc \
                --arg type "implicit" \
                --arg content "$task" \
                --arg source_file "$rel_path" \
                --arg line "$line_num" \
                --arg project "$project" \
                --arg pattern "$pattern" \
                --arg confidence "medium" \
                '{type: $type, content: $content, source_file: $source_file, line: ($line|tonumber), project: $project, pattern: $pattern, confidence: $confidence}'
        done
    done
}

# Main extraction
main() {
    local all_tasks=()

    # Extract TaskNotes frontmatter tasks first (high priority source)
    while IFS= read -r task; do
        [[ -n "$task" ]] && all_tasks+=("$task")
    done < <(extract_tasknotes_tasks)

    while IFS= read -r -d '' file; do
        # Skip system folders
        [[ "$file" =~ _System|\.trash|\.obsidian ]] && continue
        # Skip TaskNotes directory (already extracted via frontmatter)
        [[ "$file" =~ TaskNotes/Tasks/ ]] && continue
        # Skip legacy todoist-tasks.md
        [[ "$file" =~ todoist-tasks\.md ]] && continue

        # Extract explicit tasks
        while IFS= read -r task; do
            [[ -n "$task" ]] && all_tasks+=("$task")
        done < <(extract_explicit_tasks "$file")

        # Extract implicit tasks if enabled
        if [[ "$INCLUDE_IMPLICIT" == "true" ]]; then
            while IFS= read -r task; do
                [[ -n "$task" ]] && all_tasks+=("$task")
            done < <(extract_implicit_tasks "$file")
        fi
    done < <(find "$VAULT" -name "*.md" -type f -print0 2>/dev/null)

    # Output
    if [[ "$OUTPUT_JSON" == "true" || "${#all_tasks[@]}" -gt 0 ]]; then
        printf '%s\n' "${all_tasks[@]}" | jq -s '.'
    fi

    # Save to file
    printf '%s\n' "${all_tasks[@]}" | jq -s '.' > "$OUTPUT_DIR/all-tasks.json"

    echo "Extracted ${#all_tasks[@]} tasks to $OUTPUT_DIR/all-tasks.json" >&2
}

main
