#!/bin/bash
# Auto-backup OpenClaw config to GitHub
# Usage: backup-to-git.sh [message]

set -euo pipefail

BACKUP_DIR=~/openclaw-backup
MSG="${1:-Auto backup: $(date +%Y-%m-%d_%H:%M)}"

# Update backup files
cp ~/.openclaw/config.yaml "$BACKUP_DIR/"
cp ~/.openclaw/config.sh "$BACKUP_DIR/"
cp -r ~/.openclaw/skills "$BACKUP_DIR/"
cp ~/.config/systemd/user/openclaw-*.service "$BACKUP_DIR/" 2>/dev/null || true

# Sanitized openclaw.json
cat ~/.openclaw/openclaw.json | jq 'del(.gateway.token) | del(.channels)' > "$BACKUP_DIR/openclaw.json.template" 2>/dev/null || true

cd "$BACKUP_DIR"
git add -A
git diff --cached --quiet && { echo "No changes to backup"; exit 0; }
git commit -m "$MSG"
git push origin main

echo "Backup completed: $MSG"
