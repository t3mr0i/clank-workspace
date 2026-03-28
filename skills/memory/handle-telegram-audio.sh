#!/bin/bash
# Telegram Audio Handler
# Called when audio/voice message is received via OpenClaw
# Usage: handle-telegram-audio.sh <file_id> <chat_id> [caption]

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source ~/.openclaw/config.sh 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
}

BOT_TOKEN=$(cat ~/.openclaw/openclaw.json | jq -r ".channels.telegram.botToken")

FILE_ID="$1"
CHAT_ID="$2"
CAPTION="${3:-Audio Recording}"

TEMP_DIR="/tmp/openclaw-audio"
mkdir -p "$TEMP_DIR"

echo "🎙️ Processing audio: $FILE_ID"

# Get file path from Telegram
FILE_INFO=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${FILE_ID}")
FILE_PATH=$(echo "$FILE_INFO" | jq -r ".result.file_path")

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
    echo "Error: Could not get file path"
    exit 1
fi

# Download file
AUDIO_FILE="$TEMP_DIR/$(basename "$FILE_PATH")"
curl -s "https://api.telegram.org/file/bot${BOT_TOKEN}/${FILE_PATH}" -o "$AUDIO_FILE"

echo "📥 Downloaded: $AUDIO_FILE"

# Convert to wav if needed (for whisper compatibility)
if [[ "$AUDIO_FILE" == *.oga || "$AUDIO_FILE" == *.ogg ]]; then
    WAV_FILE="${AUDIO_FILE%.*}.wav"
    ffmpeg -i "$AUDIO_FILE" -ar 16000 -ac 1 "$WAV_FILE" -y 2>/dev/null
    AUDIO_FILE="$WAV_FILE"
fi

# Generate title from caption and date
DATE=$(date +%Y-%m-%d)
SAFE_CAPTION=$(echo "$CAPTION" | sed "s/[^a-zA-Z0-9äöüÄÖÜß ]/_/g" | head -c 50)
TITLE="${DATE}-${SAFE_CAPTION}"

# Transcribe
RESULT=$("$SCRIPT_DIR/transcribe-audio.sh" "$AUDIO_FILE" --title "$TITLE" 2>&1)

# Extract output file path
OUTPUT_FILE=$(echo "$RESULT" | grep "Fertig:" | sed "s/.*Fertig: //")

# Send confirmation to Telegram
if [[ -n "$OUTPUT_FILE" && -f "$OUTPUT_FILE" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="✅ Audio verarbeitet!

📝 Notiz erstellt: $(basename "$OUTPUT_FILE")
📁 Ordner: 03_Resources/Transcripts

Öffne das Dashboard um die Notiz zu sehen." \
        -d parse_mode="HTML" >/dev/null
else
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="⚠️ Audio empfangen, aber Transkription erfordert API-Key.

Placeholder-Notiz wurde erstellt. Bitte konfiguriere OPENAI_API_KEY oder GROQ_API_KEY für automatische Transkription." >/dev/null
fi

# Cleanup temp files
rm -f "$TEMP_DIR"/*

echo "✅ Done"
