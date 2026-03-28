#\!/bin/bash
QUERY="$*"
VAULT=~/obsidian-vault

echo "=== Searching Vault: $QUERY ==="
echo ""
echo "=== Projects ==="
rg -i --type md "$QUERY" $VAULT/02_Projects 2>/dev/null | head -10
echo ""
echo "=== People ==="
rg -i --type md "$QUERY" $VAULT/03_Areas/people 2>/dev/null | head -10
echo ""
echo "=== Companies ==="
rg -i --type md "$QUERY" $VAULT/03_Areas/companies 2>/dev/null | head -10
echo ""
echo "=== Reference ==="
rg -i --type md "$QUERY" $VAULT/04_Reference 2>/dev/null | head -10
echo ""
echo "=== Daily Notes ==="
rg -i --type md "$QUERY" $VAULT/01_Daily 2>/dev/null | head -10
echo ""
echo "=== Inbox ==="
rg -i --type md "$QUERY" $VAULT/00_Inbox 2>/dev/null | head -10
