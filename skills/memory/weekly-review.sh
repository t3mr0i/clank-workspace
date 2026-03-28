#!/bin/bash
# Weekly Review Generator

VAULT=~/obsidian-vault
WEEK=$(date +%Y-W%V)

echo "# 📊 Weekly Review - $WEEK"
echo ""

# Project Progress
echo "## 🎯 Projekt-Fortschritt"
echo ""
for project in $VAULT/02_Projects/*/; do
    name=$(basename "$project")
    created=$(find "$project" -name "*.md" -mtime -7 2>/dev/null | wc -l)
    modified=$(find "$project" -name "*.md" -mtime -7 2>/dev/null | wc -l)
    echo "### $name"
    echo "- Neue/bearbeitete Dateien: $modified"
    
    # Count tasks
    open=$(grep -r -c "- \[ \]" "$project" 2>/dev/null | awk -F: '{sum+=$2}END{print sum}')
    done=$(grep -r -c "- \[x\]" "$project" 2>/dev/null | awk -F: '{sum+=$2}END{print sum}')
    echo "- Tasks: ☐ ${open:-0} offen | ☑ ${done:-0} erledigt"
    echo ""
done

# Inbox Metrics
echo "## 📥 Inbox Metriken"
echo ""
total=$(find $VAULT/00_Inbox -name "*.md" 2>/dev/null | wc -l)
old=$(find $VAULT/00_Inbox -name "*.md" -mtime +7 2>/dev/null | wc -l)
echo "- Gesamt: $total Items"
echo "- Älter als 7 Tage: $old Items"

# Activity Summary
echo ""
echo "## 📝 Aktivitäts-Summary"
echo ""
notes_created=$(find $VAULT -name "*.md" -mtime -7 ! -path "*/.obsidian/*" 2>/dev/null | wc -l)
echo "- Notizen erstellt/bearbeitet: $notes_created"

# Knowledge Growth
echo ""
echo "## 🧠 Wissens-Wachstum"
echo ""
people=$(find $VAULT/03_Areas/people -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
companies=$(find $VAULT/03_Areas/companies -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
refs=$(find $VAULT/04_Reference -name "*.md" 2>/dev/null | wc -l)
echo "- Personen erfasst: $people"
echo "- Unternehmen erfasst: $companies"
echo "- Referenz-Dokumente: $refs"

# Recommendations
echo ""
echo "## 💡 Empfehlungen für nächste Woche"
echo ""
if [ "$old" -gt 5 ]; then
    echo "- ⚠️ Inbox aufräumen ($old alte Items)"
fi
if [ "$total" -gt 20 ]; then
    echo "- ⚠️ Inbox ist überfüllt - Zeit für Triage"
fi

echo ""
echo "---"
echo "*Report generiert: $(date '+%Y-%m-%d %H:%M')*"
