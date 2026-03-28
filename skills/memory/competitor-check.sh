#!/bin/bash
# Competitor Intelligence Checker
# Scans competitor folder and checks for updates

VAULT=~/obsidian-vault
COMPETE_DIR="$VAULT/03_Areas/companies/competitors"
INTEL_DIR="$VAULT/04_Reference/competitor-intel"
DATE=$(date +%Y-%m-%d)

echo "# 🔍 Competitor Intelligence Report - $DATE"
echo ""

# Check if we have competitors defined
if [ ! -d "$COMPETE_DIR" ] || [ -z "$(ls -A $COMPETE_DIR 2>/dev/null)" ]; then
    echo "⚠️ Keine Competitors definiert in $COMPETE_DIR"
    echo ""
    echo "Erstelle Competitor-Profile mit:"
    echo "- Name"
    echo "- Website"
    echo "- Social Media Links"
    echo "- Hauptprodukte"
    exit 0
fi

echo "## Bekannte Competitors:"
echo ""

for competitor in $COMPETE_DIR/*/; do
    if [ -d "$competitor" ]; then
        name=$(basename "$competitor")
        echo "### $name"
        
        # Check for summary file
        if [ -f "$competitor/summary.md" ]; then
            # Extract website if available
            website=$(grep -i "website\|url\|site" "$competitor/summary.md" | head -1)
            echo "- $website"
        fi
        
        # Check for recent intel
        recent_intel=$(find "$INTEL_DIR" -name "*$name*" -mtime -7 2>/dev/null | wc -l)
        echo "- Intel letzte 7 Tage: $recent_intel Updates"
        echo ""
    fi
done

echo "---"
echo "## 💡 Empfohlene Checks:"
echo "- Website-Änderungen"
echo "- Neue Blog-Posts"
echo "- Social Media Aktivität"
echo "- Pricing-Updates"
echo "- Neue Features/Produkte"
