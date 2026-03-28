#!/bin/bash
# Comprehensive Morning Briefing for OpenClaw
# Sends detailed actionable briefing via Telegram

SCRIPT_DIR="$(dirname "$0")"
VAULT=~/obsidian-vault
DATE=$(date +%Y-%m-%d)
WEEKDAY=$(date +%A)
WEEK_NUM=$(date +%V)

# German weekday names
case $WEEKDAY in
    Monday) WEEKDAY_DE="Montag" ;;
    Tuesday) WEEKDAY_DE="Dienstag" ;;
    Wednesday) WEEKDAY_DE="Mittwoch" ;;
    Thursday) WEEKDAY_DE="Donnerstag" ;;
    Friday) WEEKDAY_DE="Freitag" ;;
    Saturday) WEEKDAY_DE="Samstag" ;;
    Sunday) WEEKDAY_DE="Sonntag" ;;
esac

# Telegram config
CHAT_ID=$(cat ~/.openclaw/credentials/telegram-allowFrom.json 2>/dev/null | jq -r '.allowFrom[0]')
BOT_TOKEN=$(cat ~/.openclaw/openclaw.json 2>/dev/null | jq -r '.channels.telegram.botToken')

# Log start
"$SCRIPT_DIR/log-action.sh" "brief" "morning-brief" "Generating comprehensive briefing" "high" >/dev/null 2>&1

# ========== COLLECT DATA ==========

# Get all open tasks
TASKS=$(grep -r "^\s*- \[ \]" "$VAULT" --include="*.md" 2>/dev/null | grep -v "_System\|Archive" | sed 's/.*- \[ \] /• /' | head -15)
TASK_COUNT=$(grep -r "^\s*- \[ \]" "$VAULT" --include="*.md" 2>/dev/null | grep -v "_System\|Archive" | wc -l)

# Get completed yesterday
DONE_YESTERDAY=$(grep -r "^\s*- \[x\]" "$VAULT" --include="*.md" 2>/dev/null | grep -v "_System\|Archive" | wc -l)

# Check each project
PROJECTS=""
for project_dir in "$VAULT"/01_Projects/*/ "$VAULT"/02_Projects/*/; do
    [ -d "$project_dir" ] || continue
    name=$(basename "$project_dir")
    [[ "$name" == "Weekly-Plans" ]] && continue
    
    open=$(grep -r "^\s*- \[ \]" "$project_dir" 2>/dev/null | wc -l)
    done=$(grep -r "^\s*- \[x\]" "$project_dir" 2>/dev/null | wc -l)
    recent=$(find "$project_dir" -name "*.md" -mtime -3 2>/dev/null | wc -l)
    
    if [ $recent -gt 0 ]; then
        status="🟢"
    elif [ $recent -eq 0 ] && [ $open -gt 0 ]; then
        status="🟡"
    else
        status="⚪"
    fi
    
    PROJECTS+="$status $name: $open offen, $done erledigt"$'\n'
done

# Check inbox
INBOX_COUNT=$(find "$VAULT/00_Inbox" -name "*.md" -type f 2>/dev/null | wc -l)

# Get recent activity
RECENT=$(find "$VAULT" -name "*.md" -mmin -1440 -type f 2>/dev/null | grep -v "_System\|\.obsidian" | wc -l)

# Check deadlines this week
DEADLINES=$(grep -r -i "deadline\|due\|fällig" "$VAULT" --include="*.md" 2>/dev/null | grep -v "_System\|Archive" | head -5)

# ========== BUILD MESSAGE ==========

MSG="☀️ GUTEN MORGEN - $WEEKDAY_DE, $DATE
━━━━━━━━━━━━━━━━━━━━━━━━

📊 TAGESÜBERSICHT
• Offene Tasks: $TASK_COUNT
• Gestern erledigt: $DONE_YESTERDAY
• Inbox: $INBOX_COUNT Items
• Aktive Dateien (24h): $RECENT

━━━━━━━━━━━━━━━━━━━━━━━━

✅ OFFENE TASKS
$TASKS
"

if [ -z "$TASKS" ]; then
    MSG+="Keine offenen Tasks gefunden!
Tipp: Erstelle Tasks mit '- [ ] Aufgabe' in deinen Notizen.
"
fi

MSG+="
━━━━━━━━━━━━━━━━━━━━━━━━

📁 PROJEKTE
$PROJECTS
🟢 = aktiv (letzte 3 Tage)
🟡 = braucht Aufmerksamkeit
⚪ = inaktiv

━━━━━━━━━━━━━━━━━━━━━━━━

🎯 EMPFOHLENER FOKUS HEUTE
"

# Smart recommendations
if [ $TASK_COUNT -eq 0 ]; then
    MSG+="1. Plane deinen Tag - erstelle Tasks für heute
2. Review deine Projekte - was steht an?
3. Check Inbox und sortiere neue Items
"
elif [ $TASK_COUNT -gt 5 ]; then
    MSG+="1. Priorisiere: Wähle die 3 wichtigsten Tasks
2. Fokus-Block: 2h ungestörte Arbeit
3. Quick Wins: Erledige kleine Tasks zuerst
"
else
    MSG+="1. Arbeite die offenen Tasks ab
2. Dokumentiere Fortschritte
3. Plan für morgen vorbereiten
"
fi

# Add project-specific recommendations
for project_dir in "$VAULT"/01_Projects/*/ "$VAULT"/02_Projects/*/; do
    [ -d "$project_dir" ] || continue
    name=$(basename "$project_dir")
    recent=$(find "$project_dir" -name "*.md" -mtime -7 2>/dev/null | wc -l)
    if [ $recent -eq 0 ]; then
        MSG+="
⚠️ $name braucht Aufmerksamkeit - keine Aktivität seit 7 Tagen"
    fi
done

MSG+="

━━━━━━━━━━━━━━━━━━━━━━━━

💡 TIPP DES TAGES
"

# Random tips
TIPS=(
    "Nutze die 2-Minuten-Regel: Dauert es <2min, mach es sofort!"
    "Timeboxing: Setze feste Zeitblöcke für Aufgaben."
    "Eat the frog: Erledige die schwierigste Aufgabe zuerst."
    "Pomodoro: 25min Fokus, 5min Pause."
    "Weekly Review: Plane Sonntag die kommende Woche."
    "Inbox Zero: Verarbeite täglich alle Eingänge."
)
TIP_IDX=$((RANDOM % ${#TIPS[@]}))
MSG+="${TIPS[$TIP_IDX]}

━━━━━━━━━━━━━━━━━━━━━━━━
📅 KW $WEEK_NUM | ⏰ $(TZ='Europe/Berlin' date '+%H:%M') Uhr Berlin
🤖 Dein OpenClaw Assistent"

# ========== SAVE & SEND ==========

# Save to file
BRIEF_FILE="$VAULT/01_Daily/briefings/$DATE-briefing.md"
mkdir -p "$(dirname $BRIEF_FILE)"
echo "$MSG" > "$BRIEF_FILE"

# Send via Telegram
if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ] && [ "$CHAT_ID" != "null" ]; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$MSG" > /dev/null 2>&1
    
    "$SCRIPT_DIR/log-action.sh" "notify" "morning-brief" "Sent comprehensive briefing via Telegram" "high" >/dev/null 2>&1
fi

echo "$MSG"
