#!/bin/bash
# Task Consolidator - Extracts and consolidates all tasks into a master list
# Creates both JSON and Markdown outputs

SCRIPT_DIR="$(dirname "$0")"
VAULT=~/obsidian-vault
OUTPUT_DIR="$VAULT/_System/Extracted"
DATE=$(date +%Y-%m-%d)

mkdir -p "$OUTPUT_DIR"

"$SCRIPT_DIR/log-action.sh" "execute" "consolidate-tasks" "Starting task consolidation" "high"

# Run extraction
"$SCRIPT_DIR/extract-tasks.sh" "$VAULT" > "$OUTPUT_DIR/tasks-$DATE.json"

# Generate markdown summary
TASKS_MD="$OUTPUT_DIR/tasks-summary.md"

cat > "$TASKS_MD" << HEADER
# 📋 Consolidated Tasks - $DATE

> Auto-extracted from vault. Last run: $(date '+%H:%M')

## Explicit Tasks (High Confidence)

HEADER

# Parse JSON and generate markdown (using basic tools)
grep -A5 '"type": "explicit"' "$OUTPUT_DIR/tasks-$DATE.json" | grep '"content"' | sed 's/.*"content": "/- [ ] /' | sed 's/",.*//' >> "$TASKS_MD"

cat >> "$TASKS_MD" << IMPLICIT

## Implicit Tasks (Medium Confidence)

> These were inferred from text. Review before acting.

IMPLICIT

grep -A5 '"type": "implicit"' "$OUTPUT_DIR/tasks-$DATE.json" | grep '"content"' | sed 's/.*"content": "/- [ ] ⚠️ /' | sed 's/",.*//' >> "$TASKS_MD"

cat >> "$TASKS_MD" << FOOTER

---

## By Project

FOOTER

# Group by project
for project in $VAULT/02_Projects/*/; do
    name=$(basename "$project")
    echo "### $name" >> "$TASKS_MD"
    grep -B2 -A3 "\"project\": \"$name\"" "$OUTPUT_DIR/tasks-$DATE.json" | grep '"content"' | sed 's/.*"content": "/- [ ] /' | sed 's/",.*//' >> "$TASKS_MD"
    echo "" >> "$TASKS_MD"
done

# Count results
explicit=$(grep -c '"type": "explicit"' "$OUTPUT_DIR/tasks-$DATE.json" 2>/dev/null || echo 0)
implicit=$(grep -c '"type": "implicit"' "$OUTPUT_DIR/tasks-$DATE.json" 2>/dev/null || echo 0)

"$SCRIPT_DIR/log-action.sh" "execute" "consolidate-tasks" "Consolidated $explicit explicit + $implicit implicit tasks" "high"

echo "✓ Tasks consolidated: $explicit explicit, $implicit implicit"
echo "  JSON: $OUTPUT_DIR/tasks-$DATE.json"
echo "  Markdown: $TASKS_MD"
