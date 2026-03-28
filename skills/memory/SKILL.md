# Memory Skill

A PARA-based knowledge management system with three memory layers.

## Commands

### /memory remember <type> <name> <fact>
Store a new fact about an entity.

Types: `project`, `person`, `company`, `resource`

Example:
```
/memory remember person john "Works at Acme as CTO"
```

### /memory recall <name>
Retrieve information about an entity.

Example:
```
/memory recall john
```

### /memory daily <content>
Add an entry to today's daily note.

Example:
```
/memory daily "Met with John to discuss project timeline"
```

### /memory heartbeat
Run the extraction and decay processing:
1. Scan recent conversations for facts
2. Update entity summaries
3. Apply memory decay (Hot → Warm → Cold)
4. Update the index

### /memory search <query>
Search across all memory layers for relevant information.

## Memory Structure

```
~/life/                    # Knowledge Graph (PARA)
├── projects/              # Active work
├── areas/
│   ├── people/           # Relationships
│   └── companies/        # Organizations
├── resources/            # Reference material
├── archives/             # Inactive items
├── index.md              # Quick reference
└── tacit-knowledge.md    # User patterns

~/memory/                  # Daily Notes
└── YYYY-MM-DD.md         # Timeline entries
```

## Fact Schema

```json
{
  "id": "unique-id",
  "fact": "The actual fact",
  "category": "relationship|milestone|status|preference|context",
  "timestamp": "when it happened",
  "source": "where it came from",
  "status": "active|superseded",
  "supersededBy": null,
  "relatedEntities": ["path/to/entity"],
  "lastAccessed": "YYYY-MM-DD",
  "accessCount": 0
}
```

## Memory Decay

- **Hot** (7 days): Prominently included in summary
- **Warm** (8-30 days): Lower priority in summary
- **Cold** (30+ days): Omitted from summary, kept in items.json
