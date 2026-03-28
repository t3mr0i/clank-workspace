#!/bin/bash
# Add fact to entity

TYPE="$1"  # project, person, company, resource
NAME="$2"
FACT="$3"
CATEGORY="${4:-context}"  # Default to context

LIFE_DIR=~/life
TODAY=$(date +%Y-%m-%d)

case $TYPE in
    project) DIR="$LIFE_DIR/projects/$NAME" ;;
    person) DIR="$LIFE_DIR/areas/people/$NAME" ;;
    company) DIR="$LIFE_DIR/areas/companies/$NAME" ;;
    resource) DIR="$LIFE_DIR/resources/$NAME" ;;
    *) echo "Unknown type: $TYPE"; exit 1 ;;
esac

if [ ! -d "$DIR" ]; then
    echo "Entity not found: $DIR"
    echo "Create it first with: create-entity.sh $TYPE $NAME"
    exit 1
fi

ITEMS_FILE="$DIR/items.json"

# Generate unique ID
ID="${TYPE:0:4}-$(date +%s)"

# Create new fact
NEW_FACT=$(cat << EOF
{
  "id": "$ID",
  "fact": "$FACT",
  "category": "$CATEGORY",
  "timestamp": "$TODAY",
  "source": "$TODAY",
  "status": "active",
  "supersededBy": null,
  "relatedEntities": [],
  "lastAccessed": "$TODAY",
  "accessCount": 1
}
EOF
)

# Add to items.json
if [ -f "$ITEMS_FILE" ]; then
    jq ". += [$NEW_FACT]" "$ITEMS_FILE" > "$ITEMS_FILE.tmp" && mv "$ITEMS_FILE.tmp" "$ITEMS_FILE"
else
    echo "[$NEW_FACT]" > "$ITEMS_FILE"
fi

echo "Added fact to $NAME:"
echo "$FACT"
