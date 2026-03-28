#!/bin/bash
# Memory Heartbeat - Run periodically to process memory decay and update summaries

TODAY=$(date +%Y-%m-%d)
WEEK_AGO=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)
MONTH_AGO=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)

LIFE_DIR=~/life
MEMORY_DIR=~/memory

echo "=== Memory Heartbeat: $TODAY ==="

# Function to process entity items.json and update summary based on decay
process_entity() {
    local entity_dir=$1
    local items_file="$entity_dir/items.json"
    local summary_file="$entity_dir/summary.md"
    
    if [ ! -f "$items_file" ]; then
        return
    fi
    
    echo "Processing: $entity_dir"
    
    # Count facts by tier (using jq if available, otherwise skip)
    if command -v jq &> /dev/null; then
        hot=$(jq "[.[] | select(.status == \"active\" and .lastAccessed >= \"$WEEK_AGO\")] | length" "$items_file" 2>/dev/null || echo 0)
        warm=$(jq "[.[] | select(.status == \"active\" and .lastAccessed < \"$WEEK_AGO\" and .lastAccessed >= \"$MONTH_AGO\")] | length" "$items_file" 2>/dev/null || echo 0)
        cold=$(jq "[.[] | select(.status == \"active\" and .lastAccessed < \"$MONTH_AGO\")] | length" "$items_file" 2>/dev/null || echo 0)
        echo "  Hot: $hot, Warm: $warm, Cold: $cold"
    fi
}

# Process all entities
echo ""
echo "=== Processing Projects ==="
for dir in $LIFE_DIR/projects/*/; do
    [ -d "$dir" ] && process_entity "$dir"
done

echo ""
echo "=== Processing People ==="
for dir in $LIFE_DIR/areas/people/*/; do
    [ -d "$dir" ] && process_entity "$dir"
done

echo ""
echo "=== Processing Companies ==="
for dir in $LIFE_DIR/areas/companies/*/; do
    [ -d "$dir" ] && process_entity "$dir"
done

echo ""
echo "=== Processing Resources ==="
for dir in $LIFE_DIR/resources/*/; do
    [ -d "$dir" ] && process_entity "$dir"
done

# Update index
echo ""
echo "=== Updating Index ==="
cat > $LIFE_DIR/index.md << INDEX
# Knowledge Graph Index

Last updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Active Projects
$(ls -1 $LIFE_DIR/projects/ 2>/dev/null | while read p; do echo "- [$p](projects/$p/summary.md)"; done)

## Key People
$(ls -1 $LIFE_DIR/areas/people/ 2>/dev/null | while read p; do echo "- [$p](areas/people/$p/summary.md)"; done)

## Key Companies
$(ls -1 $LIFE_DIR/areas/companies/ 2>/dev/null | while read c; do echo "- [$c](areas/companies/$c/summary.md)"; done)

## Recent Daily Notes
$(ls -1 $MEMORY_DIR/*.md 2>/dev/null | tail -5 | while read f; do
    name=$(basename "$f" .md)
    echo "- [$name](../memory/$name.md)"
done)
INDEX

echo "Index updated: $LIFE_DIR/index.md"
echo ""
echo "=== Heartbeat Complete ==="
