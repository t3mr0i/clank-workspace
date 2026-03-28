#!/bin/bash
# Todoist <-> TaskNotes Bidirectional Sync
# Syncs tasks between Todoist API and individual TaskNotes files in Obsidian
# Usage: todoist-sync.sh [--dry-run] [--verbose] [--pull-only] [--push-only]
#
# Sync directions:
#   Phase 1 - Pull: Todoist -> TaskNotes/Tasks/*.md (individual files)
#   Phase 2 - Complete: TaskNotes (status:done) -> Todoist close
#   Phase 3 - Push: AI-todo.md / todo.md -> TaskNotes + Todoist

set -euo pipefail

# Source configuration
source "${OPENCLAW_CONFIG_SH:-/home/openclaw/.openclaw/config.sh}" 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_LOGS="${OPENCLAW_LOGS:-$OPENCLAW_VAULT/_System/Logs}"
    OPENCLAW_SKILLS="${OPENCLAW_SKILLS:-/home/openclaw/.openclaw/skills}"
}

# Configuration
VAULT="$OPENCLAW_VAULT"
TASKNOTES_DIR="$VAULT/TaskNotes/Tasks"
ARCHIVE_DIR="$VAULT/TaskNotes/Archive"
TASKS_DIR="$VAULT/00_Inbox/Tasks"
NOTIZEN_DIR="$VAULT/00_Inbox/Notizen"
AI_TODO_FILE="$TASKS_DIR/AI-todo.md"
TODO_FILE="$TASKS_DIR/todo.md"
LEGACY_TODOIST_FILE="$TASKS_DIR/todoist-tasks.md"
SYNC_STATE_DIR="$VAULT/_System/Extracted"
FILE_MAP="$SYNC_STATE_DIR/todoist-file-map.json"
LOG_FILE="/tmp/todoist-sync.log"

TODOIST_API="https://api.todoist.com/api/v1"
TODOIST_API_KEY="${TODOIST_API_KEY:-}"

DRY_RUN=false
VERBOSE=false
PULL_ONLY=false
PUSH_ONLY=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --pull-only) PULL_ONLY=true; shift ;;
        --push-only) PUSH_ONLY=true; shift ;;
        *) shift ;;
    esac
done

# Logging
log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date -Iseconds)
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
    [[ "$VERBOSE" == "true" ]] && echo "[$ts] [$level] $msg" >&2 || true
}

# Transparency ledger integration
log_action() {
    if [[ -x "$OPENCLAW_SKILLS/memory/log-action.sh" ]]; then
        "$OPENCLAW_SKILLS/memory/log-action.sh" "$1" "todoist-sync" "$2" "${3:-high}" 2>/dev/null || true
    fi
}

# Validate prerequisites
check_prerequisites() {
    if [[ -z "$TODOIST_API_KEY" ]]; then
        log "ERROR" "TODOIST_API_KEY not set. Export it or add to ~/.bashrc"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        log "ERROR" "curl is required but not installed"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        log "ERROR" "jq is required but not installed"
        exit 1
    fi

    mkdir -p "$TASKNOTES_DIR" "$ARCHIVE_DIR" "$TASKS_DIR" "$SYNC_STATE_DIR"
}

# ============================================================
# FILE MAP: Unified sync state (replaces old state files)
# ============================================================

init_file_map() {
    if [[ ! -f "$FILE_MAP" ]]; then
        jq -nc '{
            version: 2,
            last_sync: null,
            id_to_file: {},
            source_hashes: [],
            stats: { pulled: 0, completed: 0, created: 0 }
        }' > "$FILE_MAP"
    fi
}

get_file_map() {
    cat "$FILE_MAP"
}

save_file_map() {
    local map="$1"
    echo "$map" > "$FILE_MAP"
}

# Register a todoist-id -> filename mapping
register_file_mapping() {
    local todoist_id="$1"
    local rel_path="$2"
    local map
    map=$(get_file_map)
    map=$(echo "$map" | jq --arg id "$todoist_id" --arg path "$rel_path" '.id_to_file[$id] = $path')
    save_file_map "$map"
}

# Look up filename by todoist-id in map
lookup_file_by_id() {
    local todoist_id="$1"
    local map
    map=$(get_file_map)
    echo "$map" | jq -r --arg id "$todoist_id" '.id_to_file[$id] // empty'
}

# Check if source hash already synced
is_hash_synced() {
    local hash="$1"
    local map
    map=$(get_file_map)
    echo "$map" | jq -e --arg h "$hash" '.source_hashes | index($h) != null' >/dev/null 2>&1
}

# Add source hash to synced list
add_synced_hash() {
    local hash="$1"
    local map
    map=$(get_file_map)
    map=$(echo "$map" | jq --arg h "$hash" '.source_hashes += [$h] | .source_hashes |= unique')
    save_file_map "$map"
}

# ============================================================
# TODOIST API
# ============================================================

todoist_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local args=(
        -s -S
        --max-time 30
        -H "Authorization: Bearer $TODOIST_API_KEY"
        -H "Content-Type: application/json"
        -X "$method"
    )

    [[ -n "$data" ]] && args+=(-d "$data")

    local response
    local http_code
    response=$(curl "${args[@]}" -w "\n%{http_code}" "${TODOIST_API}${endpoint}" 2>&1)
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "$body"
        return 0
    else
        log "ERROR" "Todoist API $method $endpoint returned HTTP $http_code: $body"
        return 1
    fi
}

fetch_todoist_tasks() {
    log "INFO" "Fetching tasks from Todoist..."
    local response all_tasks="[]" cursor="" page=0
    while true; do
        local url="/tasks?limit=200"
        [[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
        response=$(todoist_api "GET" "$url") || {
            log "ERROR" "Failed to fetch Todoist tasks"
            return 1
        }
        local page_tasks
        page_tasks=$(echo "$response" | jq '.results')
        all_tasks=$(echo "$all_tasks $page_tasks" | jq -s 'add')
        cursor=$(echo "$response" | jq -r '.next_cursor // empty')
        page=$((page + 1))
        [[ -z "$cursor" ]] && break
        [[ $page -gt 20 ]] && { log "WARN" "Pagination limit reached"; break; }
    done
    local count
    count=$(echo "$all_tasks" | jq 'length')
    log "INFO" "Fetched $count tasks from Todoist"
    echo "$all_tasks"
}

fetch_todoist_projects() {
    local response all_projects="[]" cursor="" page=0
    while true; do
        local url="/projects?limit=200"
        [[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
        response=$(todoist_api "GET" "$url") || {
            log "WARN" "Failed to fetch Todoist projects, using IDs only"
            echo "[]"
            return 0
        }
        local page_projects
        page_projects=$(echo "$response" | jq '.results')
        all_projects=$(echo "$all_projects $page_projects" | jq -s 'add')
        cursor=$(echo "$response" | jq -r '.next_cursor // empty')
        page=$((page + 1))
        [[ -z "$cursor" ]] && break
        [[ $page -gt 10 ]] && break
    done
    echo "$all_projects"
}

# ============================================================
# HELPERS: Filename, priority mapping, frontmatter
# ============================================================

# Strip unsafe characters from filenames, truncate to 100 chars
sanitize_filename() {
    local name="$1"
    # Remove characters invalid in filenames
    name=$(echo "$name" | sed 's/[\/\\:*?"<>|]//g')
    # Collapse multiple spaces
    name=$(echo "$name" | sed 's/  */ /g')
    # Trim leading/trailing whitespace
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Truncate to 100 chars
    echo "${name:0:100}"
}

# Todoist priority (1=normal, 4=urgent) -> TaskNotes priority
map_priority_to_tasknotes() {
    local todoist_priority="$1"
    case "$todoist_priority" in
        4) echo "high" ;;
        3) echo "normal" ;;
        2) echo "low" ;;
        *) echo "none" ;;
    esac
}

# TaskNotes priority -> Todoist priority
map_priority_to_todoist() {
    local tn_priority="$1"
    case "$tn_priority" in
        high) echo 4 ;;
        normal) echo 3 ;;
        low) echo 2 ;;
        *) echo 1 ;;
    esac
}

# Read a single frontmatter field value from a file
read_frontmatter_field() {
    local file="$1"
    local field="$2"
    # Extract value between --- markers
    sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/^"//;s/"$//'
}

# Create a TaskNotes markdown file with YAML frontmatter
create_tasknotes_file() {
    local filepath="$1"
    local title="$2"
    local status="${3:-open}"
    local priority="${4:-none}"
    local due="${5:-}"
    local project="${6:-}"
    local todoist_id="${7:-}"
    local todoist_project="${8:-}"
    local source="${9:-todoist}"
    local description="${10:-}"
    local labels="${11:-}"
    local today
    today=$(date +%Y-%m-%d)

    # Build tags line (always includes "task")
    local tags_line="  - task"
    if [[ -n "$labels" ]]; then
        while IFS= read -r label; do
            [[ -n "$label" ]] && tags_line="$tags_line"$'\n'"  - $label"
        done <<< "$labels"
    fi

    # Build projects line
    local projects_line=""
    if [[ -n "$project" ]]; then
        projects_line="projects:
  - \"$project\""
    else
        projects_line="projects: []"
    fi

    cat > "$filepath" <<FRONTMATTER
---
title: "$title"
status: $status
priority: $priority
due: $due
scheduled:
contexts: []
${projects_line}
tags:
${tags_line}
timeEstimate: 0
recurrence:
blockedBy:
todoist-id: "$todoist_id"
todoist-project: "$todoist_project"
source: "$source"
dateCreated: "$today"
---

${description}
FRONTMATTER
}

# Update specific frontmatter fields in an existing file
update_tasknotes_file() {
    local filepath="$1"
    local field="$2"
    local value="$3"

    if [[ ! -f "$filepath" ]]; then
        log "WARN" "Cannot update $filepath: file not found"
        return 1
    fi

    # Use sed to replace the field value in frontmatter
    # Handle both quoted and unquoted values
    if grep -q "^${field}:" "$filepath" 2>/dev/null; then
        sed -i "s|^${field}:.*|${field}: ${value}|" "$filepath"
    fi
}

# Find TaskNotes file by todoist-id (file-map first, grep fallback)
find_file_by_todoist_id() {
    local todoist_id="$1"

    # Fast path: check file map
    local mapped_path
    mapped_path=$(lookup_file_by_id "$todoist_id")
    if [[ -n "$mapped_path" && -f "$VAULT/$mapped_path" ]]; then
        echo "$VAULT/$mapped_path"
        return 0
    fi

    # Slow path: grep through all TaskNotes files
    local found
    found=$(grep -rl "todoist-id: \"${todoist_id}\"" "$TASKNOTES_DIR"/ 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]]; then
        # Update the file map for next time
        local rel_path="${found#$VAULT/}"
        register_file_mapping "$todoist_id" "$rel_path"
        echo "$found"
        return 0
    fi

    return 1
}

# ============================================================
# PHASE 1: PULL (Todoist -> TaskNotes)
# ============================================================

pull_todoist_to_tasknotes() {
    local tasks="$1"
    local projects="$2"

    log "INFO" "Phase 1: Pulling Todoist tasks to TaskNotes..."

    # Build project ID -> name map
    local project_map
    project_map=$(echo "$projects" | jq -r 'map({(.id): .name}) | add // {}')

    local pulled=0
    local updated=0
    local total
    total=$(echo "$tasks" | jq 'length')

    # Track active todoist IDs for deletion detection
    local active_ids
    active_ids=$(echo "$tasks" | jq -r '.[].id')

    # Process each Todoist task
    local i=0
    while [[ $i -lt $total ]]; do
        local task
        task=$(echo "$tasks" | jq ".[$i]")

        local task_id content priority due_date project_id labels_json
        task_id=$(echo "$task" | jq -r '.id')
        content=$(echo "$task" | jq -r '.content')
        priority=$(echo "$task" | jq -r '.priority')
        due_date=$(echo "$task" | jq -r '.due.date // empty')
        project_id=$(echo "$task" | jq -r '.project_id')
        labels_json=$(echo "$task" | jq -r '.labels // [] | .[]')
        local description
        description=$(echo "$task" | jq -r '.description // empty')

        # Map priority and project
        local tn_priority
        tn_priority=$(map_priority_to_tasknotes "$priority")
        local project_name
        project_name=$(echo "$project_map" | jq -r --arg pid "$project_id" '.[$pid] // "Inbox"')

        # Check if file already exists for this task
        local existing_file
        existing_file=$(find_file_by_todoist_id "$task_id" 2>/dev/null || true)

        if [[ -n "$existing_file" ]]; then
            # Update existing file if Todoist has changes
            local current_priority current_due
            current_priority=$(read_frontmatter_field "$existing_file" "priority")
            current_due=$(read_frontmatter_field "$existing_file" "due")

            local needs_update=false
            if [[ "$current_priority" != "$tn_priority" ]]; then
                needs_update=true
            fi
            if [[ "$current_due" != "$due_date" ]]; then
                needs_update=true
            fi

            if [[ "$needs_update" == "true" && "$DRY_RUN" == "false" ]]; then
                update_tasknotes_file "$existing_file" "priority" "$tn_priority"
                update_tasknotes_file "$existing_file" "due" "$due_date"
                updated=$((updated + 1))
                log "INFO" "Updated: $content (priority=$tn_priority, due=$due_date)"
            fi
        else
            # Create new TaskNotes file
            local safe_name
            safe_name=$(sanitize_filename "$content")
            local filepath="$TASKNOTES_DIR/${safe_name}.md"

            # Handle filename collisions
            if [[ -f "$filepath" ]]; then
                filepath="$TASKNOTES_DIR/${safe_name} (${task_id}).md"
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY-RUN] Would create: $filepath"
            else
                # Determine project for TaskNotes (use Obsidian-style link if project exists)
                local tn_project="$project_name"

                create_tasknotes_file \
                    "$filepath" \
                    "$content" \
                    "open" \
                    "$tn_priority" \
                    "$due_date" \
                    "$tn_project" \
                    "$task_id" \
                    "$project_name" \
                    "todoist" \
                    "$description" \
                    "$labels_json"

                # Register in file map
                local rel_path="${filepath#$VAULT/}"
                register_file_mapping "$task_id" "$rel_path"

                pulled=$((pulled + 1))
                log "INFO" "Created: $safe_name (id=$task_id, project=$project_name)"
            fi
        fi

        i=$((i + 1))
    done

    # Check for tasks deleted in Todoist (mark as done in TaskNotes)
    local deleted=0
    if [[ "$DRY_RUN" == "false" ]]; then
        local map
        map=$(get_file_map)
        local mapped_ids
        mapped_ids=$(echo "$map" | jq -r '.id_to_file | keys[]')

        for mapped_id in $mapped_ids; do
            # Check if this ID is still active in Todoist
            if ! echo "$active_ids" | grep -q "^${mapped_id}$"; then
                local file_path
                file_path=$(lookup_file_by_id "$mapped_id")
                if [[ -n "$file_path" && -f "$VAULT/$file_path" ]]; then
                    local current_status
                    current_status=$(read_frontmatter_field "$VAULT/$file_path" "status")
                    if [[ "$current_status" != "done" ]]; then
                        update_tasknotes_file "$VAULT/$file_path" "status" "done"
                        deleted=$((deleted + 1))
                        log "INFO" "Marked done (deleted in Todoist): $file_path"
                    fi
                fi
            fi
        done
    fi

    # Update stats in file map
    local map
    map=$(get_file_map)
    map=$(echo "$map" | jq --arg ts "$(date -Iseconds)" --argjson p "$pulled" \
        '.last_sync = $ts | .stats.pulled = $p')
    save_file_map "$map"

    log "INFO" "Phase 1 complete: $pulled created, $updated updated, $deleted marked done"
}

# ============================================================
# PHASE 2: COMPLETE (TaskNotes -> Todoist)
# ============================================================

sync_completed_to_todoist() {
    log "INFO" "Phase 2: Syncing completed TaskNotes to Todoist..."

    local completed_count=0

    # Scan all TaskNotes files for status=done with a todoist-id
    while IFS= read -r -d '' file; do
        local status todoist_id
        status=$(read_frontmatter_field "$file" "status")
        todoist_id=$(read_frontmatter_field "$file" "todoist-id")

        # Only process files that are done and have a todoist ID
        [[ "$status" != "done" ]] && continue
        [[ -z "$todoist_id" ]] && continue

        log "INFO" "Closing Todoist task $todoist_id"

        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would close Todoist task $todoist_id"
            continue
        fi

        local close_result close_out
        close_out=$(todoist_api "POST" "/tasks/$todoist_id/close" "" 2>&1) && close_result=0 || close_result=$?
        if [[ $close_result -eq 0 ]]; then
            completed_count=$((completed_count + 1))
            log "INFO" "Closed Todoist task $todoist_id"
            local map
            map=$(get_file_map)
            map=$(echo "$map" | jq --arg id "$todoist_id" 'del(.id_to_file[$id])')
            save_file_map "$map"
        elif echo "$close_out" | grep -q "V1_ID_CANNOT_BE_USED\|deprecated"; then
            log "INFO" "Clearing deprecated todoist-id $todoist_id from $file"
            sed -i "s|^todoist-id: \"${todoist_id}\"|todoist-id: |" "$file" 2>/dev/null || true
        else
            log "WARN" "Failed to close Todoist task $todoist_id: $close_out"
        fi
    done < <(find "$TASKNOTES_DIR" -name "*.md" -type f -print0 2>/dev/null)

    if [[ "$completed_count" -gt 0 ]]; then
        log_action "todoist_complete" "Closed $completed_count tasks in Todoist from TaskNotes"
        local map
        map=$(get_file_map)
        map=$(echo "$map" | jq --argjson c "$completed_count" '.stats.completed = $c')
        save_file_map "$map"
    fi

    log "INFO" "Phase 2 complete: $completed_count tasks closed in Todoist"
}

# ============================================================
# PHASE 3: PUSH (AI-todo.md / todo.md -> TaskNotes + Todoist)
# ============================================================

# Generate a stable hash for a task line (file:content)
task_hash() {
    echo -n "$1" | sha256sum | head -c 16
}

# Check if a line is a task worth syncing
# mode=strict: only checkboxes (for Notizen/reference files)
# mode=smart: plain text lines under task headers (for todo/task files)
is_task_line() {
    local line="$1"
    local mode="${2:-strict}"
    local trimmed
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

    # Universal skip rules
    [[ -z "$trimmed" ]] && return 1
    [[ "$trimmed" =~ ^# ]] && return 1
    [[ "$trimmed" =~ ^--- ]] && return 1
    [[ "$trimmed" =~ ^\> ]] && return 1
    [[ "$trimmed" =~ \#todoist-id: ]] && return 1
    [[ "$trimmed" =~ ^-\ \[x\] ]] && return 1
    [[ ${#trimmed} -lt 5 ]] && return 1
    # Skip frontmatter/metadata
    [[ "$trimmed" =~ ^(date|type|synced|source|task_count): ]] && return 1
    # Skip italic/bold notes
    [[ "$trimmed" =~ ^\*.*\*$ ]] && return 1

    # Checkboxes always count as tasks in any mode
    [[ "$trimmed" =~ ^-\ \[\ \] ]] && return 0

    # Strict mode (for Notizen): ONLY checkboxes pass
    [[ "$mode" == "strict" ]] && return 1

    # Smart mode (for task files): plain text lines that look like tasks
    # Skip instruction-like lines
    [[ "$trimmed" =~ ^(Each|Tasks\ are|Instructions) ]] && return 1

    return 0
}

# Extract clean task content from a line
extract_task_content() {
    local line="$1"
    echo "$line" | sed \
        -e 's/^[[:space:]]*//' \
        -e 's/^- \[ \][[:space:]]*//' \
        -e 's/^- //' \
        -e 's/^[0-9]\+\.[[:space:]]*//' \
        -e 's/^[*][[:space:]]*//' \
        | head -c 200
}

# Create a Todoist task and corresponding TaskNotes file
create_task_with_tasknote() {
    local content="$1"
    local source_file="$2"

    # Extract deadline if present
    local due_string=""
    if [[ "$content" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        due_string="${BASH_REMATCH[1]}"
    fi

    # Build JSON payload
    local payload
    local desc="Quelle: $source_file"
    if [[ -n "$due_string" ]]; then
        payload=$(jq -nc --arg c "$content" --arg d "$due_string" --arg desc "$desc" \
            '{content: $c, due_string: $d, description: $desc}')
    else
        payload=$(jq -nc --arg c "$content" --arg desc "$desc" \
            '{content: $c, description: $desc}')
    fi

    # Create in Todoist first
    local response
    if ! response=$(todoist_api "POST" "/tasks" "$payload"); then
        log "WARN" "Failed to create Todoist task: $content"
        return 1
    fi

    local task_id
    task_id=$(echo "$response" | jq -r '.id')
    [[ -z "$task_id" || "$task_id" == "null" ]] && return 1

    # Create TaskNotes file
    local safe_name
    safe_name=$(sanitize_filename "$content")
    local filepath="$TASKNOTES_DIR/${safe_name}.md"

    # Handle filename collisions
    if [[ -f "$filepath" ]]; then
        filepath="$TASKNOTES_DIR/${safe_name} (${task_id}).md"
    fi

    create_tasknotes_file \
        "$filepath" \
        "$content" \
        "open" \
        "none" \
        "$due_string" \
        "" \
        "$task_id" \
        "Inbox" \
        "ai-todo" \
        "" \
        ""

    # Register in file map
    local rel_path="${filepath#$VAULT/}"
    register_file_mapping "$task_id" "$rel_path"

    log "INFO" "Created task $task_id + TaskNote: $safe_name"
    echo "$task_id"
}

# Process a single source file: find task lines and push to Todoist + TaskNotes
sync_file_to_todoist() {
    local file="$1"
    local mode="${2:-strict}"
    local rel_path="${file#$VAULT/}"
    local created=0
    local in_task_section=false

    [[ ! -f "$file" ]] && return 0

    # Skip the legacy todoist-tasks.md file
    [[ "$file" == "$LEGACY_TODOIST_FILE" ]] && return 0

    log "INFO" "Scanning $rel_path for tasks..."

    local temp_file
    temp_file=$(mktemp)
    local file_modified=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Track section headers for smart mode
        if [[ "$line" =~ ^##[[:space:]] ]]; then
            local header_lower
            header_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
            if [[ "$header_lower" =~ (task|todo|diese\ woche|backlog|aufgaben|erledigen) ]]; then
                in_task_section=true
            else
                in_task_section=false
            fi
            echo "$line" >> "$temp_file"
            continue
        fi

        # In smart mode, only process lines in task sections
        local effective_mode="$mode"
        if [[ "$mode" == "smart" && "$in_task_section" == "false" ]]; then
            effective_mode="strict"
        fi

        if is_task_line "$line" "$effective_mode"; then
            local content
            content=$(extract_task_content "$line")

            [[ -z "$content" ]] && { echo "$line" >> "$temp_file"; continue; }

            # Check if already synced via hash
            local hash
            hash=$(task_hash "${rel_path}:${content}")

            if is_hash_synced "$hash"; then
                echo "$line" >> "$temp_file"
                continue
            fi

            log "INFO" "New task from $rel_path: $content"

            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY-RUN] Would create: $content"
                echo "$line" >> "$temp_file"
                continue
            fi

            local new_id
            new_id=$(create_task_with_tasknote "$content" "$rel_path" 2>/dev/null || true)

            if [[ -n "$new_id" ]]; then
                # For checkbox-style lines, append the ID
                if [[ "$line" =~ ^[[:space:]]*-\ \[\ \] ]]; then
                    echo "$line #todoist-id:$new_id" >> "$temp_file"
                else
                    echo "$line" >> "$temp_file"
                fi
                add_synced_hash "$hash"
                created=$((created + 1))
                file_modified=true
            else
                echo "$line" >> "$temp_file"
                log "WARN" "Failed to create task: $content"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$file"

    # Only update file if checkbox lines got todoist IDs appended
    if [[ "$file_modified" == "true" ]]; then
        cp "$temp_file" "$file"
    fi
    rm -f "$temp_file"

    echo "$created"
}

# Scan all configured sources for new tasks
push_new_tasks() {
    log "INFO" "Phase 3: Pushing new tasks from vault to Todoist + TaskNotes..."

    local total_created=0

    # Source files to scan (explicit task files)
    local source_files=(
        "$AI_TODO_FILE"
        "$TODO_FILE"
    )

    # Process explicit task files (smart mode)
    for file in "${source_files[@]}"; do
        if [[ -f "$file" ]]; then
            local count
            count=$(sync_file_to_todoist "$file" "smart")
            total_created=$((total_created + count))
        fi
    done

    # Scan Notizen directory (strict mode: only checkboxes)
    if [[ -d "$NOTIZEN_DIR" ]]; then
        while IFS= read -r -d '' file; do
            local count
            count=$(sync_file_to_todoist "$file" "strict")
            total_created=$((total_created + count))
        done < <(find "$NOTIZEN_DIR" -name "*.md" -type f -print0 2>/dev/null)
    fi

    if [[ "$total_created" -gt 0 ]]; then
        log_action "todoist_push" "Created $total_created tasks in Todoist + TaskNotes from vault"
        local map
        map=$(get_file_map)
        map=$(echo "$map" | jq --argjson c "$total_created" '.stats.created = $c')
        save_file_map "$map"
    fi

    log "INFO" "Phase 3 complete: $total_created new tasks created"
}

# ============================================================
# MIGRATION: Archive legacy todoist-tasks.md
# ============================================================

migrate_legacy_file() {
    if [[ -f "$LEGACY_TODOIST_FILE" ]]; then
        local is_archived
        is_archived=$(read_frontmatter_field "$LEGACY_TODOIST_FILE" "archived" 2>/dev/null || true)

        if [[ "$is_archived" != "true" ]]; then
            log "INFO" "Archiving legacy todoist-tasks.md..."

            if [[ "$DRY_RUN" == "false" ]]; then
                local today
                today=$(date +%Y-%m-%d)
                cat > "$LEGACY_TODOIST_FILE" <<EOF
---
archived: true
---
# [ARCHIVIERT] Todoist Tasks
> Migriert zu TaskNotes/Tasks/ am $today
>
> Alle Aufgaben sind jetzt als individuelle Dateien in TaskNotes/Tasks/ verfuegbar.
> Diese Datei wird nicht mehr aktualisiert.
EOF
                log "INFO" "Legacy todoist-tasks.md archived"
                log_action "todoist_migrate" "Archived legacy todoist-tasks.md, migrated to TaskNotes/Tasks/"
            else
                log "INFO" "[DRY-RUN] Would archive legacy todoist-tasks.md"
            fi
        fi
    fi
}

# ============================================================
# MAIN
# ============================================================

main() {
    log "INFO" "=== Todoist <-> TaskNotes Sync Starting ==="

    check_prerequisites
    init_file_map

    if [[ "$PUSH_ONLY" == "false" ]]; then
        # Phase 1: Todoist -> TaskNotes
        local tasks
        tasks=$(fetch_todoist_tasks) || {
            log "ERROR" "Aborting sync: could not fetch Todoist tasks"
            exit 1
        }

        local projects
        projects=$(fetch_todoist_projects)

        pull_todoist_to_tasknotes "$tasks" "$projects"

        # Migrate legacy file on first run
        migrate_legacy_file
    fi

    if [[ "$PULL_ONLY" == "false" ]]; then
        # Phase 2: TaskNotes -> Todoist (completed tasks)
        sync_completed_to_todoist

        # Phase 3: Vault -> Todoist + TaskNotes (new tasks)
        push_new_tasks
    fi

    log "INFO" "=== Todoist <-> TaskNotes Sync Complete ==="
}

main
