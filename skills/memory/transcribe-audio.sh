#!/bin/bash
# Audio Transcription & Note Creation
# Usage: transcribe-audio.sh <audio_file> [--title "Title"] [--folder "path"]
# Supports: Whisper API, local whisper, or Groq API

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source ~/.openclaw/config.sh 2>/dev/null || {
    OPENCLAW_VAULT="${OPENCLAW_VAULT:-/home/openclaw/obsidian-vault}"
    OPENCLAW_SKILLS="${OPENCLAW_SKILLS:-/home/openclaw/.openclaw/skills}"
}

VAULT="$OPENCLAW_VAULT"

# Parse arguments
AUDIO_FILE=""
TITLE=""
FOLDER="03_Resources/Transcripts"
OPENAI_KEY="${OPENAI_API_KEY:-}"
GROQ_KEY="${GROQ_API_KEY:-}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --title) TITLE="$2"; shift 2 ;;
        --folder) FOLDER="$2"; shift 2 ;;
        --openai-key) OPENAI_KEY="$2"; shift 2 ;;
        --groq-key) GROQ_KEY="$2"; shift 2 ;;
        *) AUDIO_FILE="$1"; shift ;;
    esac
done

if [[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]]; then
    echo "Error: Audio file not found: $AUDIO_FILE"
    echo "Usage: transcribe-audio.sh <audio_file> [--title \"Title\"] [--folder \"path\"]"
    exit 1
fi

# Generate filename from audio file or title
BASENAME=$(basename "$AUDIO_FILE" | sed "s/\.[^.]*$//")
DATE=$(date +%Y-%m-%d)
if [[ -z "$TITLE" ]]; then
    TITLE="Transcript-${DATE}-${BASENAME}"
fi
SAFE_TITLE=$(echo "$TITLE" | sed "s/[^a-zA-Z0-9äöüÄÖÜß_-]/_/g")

echo "🎙️ Transcribing: $AUDIO_FILE"
echo "📄 Title: $TITLE"

# Log start
"$SCRIPT_DIR/log-action.sh" "transcribe" "audio-processor" "Starting transcription: $BASENAME" "high" >/dev/null 2>&1

# Try transcription methods in order of preference
TRANSCRIPT=""

# Method 1: OpenAI Whisper API
if [[ -n "$OPENAI_KEY" && -z "$TRANSCRIPT" ]]; then
    echo "Using OpenAI Whisper API..."
    TRANSCRIPT=$(curl -s -X POST "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer $OPENAI_KEY" \
        -F "file=@$AUDIO_FILE" \
        -F "model=whisper-1" \
        -F "language=de" \
        -F "response_format=text" 2>/dev/null || echo "")
fi

# Method 2: Groq Whisper API (faster, free tier)
if [[ -n "$GROQ_KEY" && -z "$TRANSCRIPT" ]]; then
    echo "Using Groq Whisper API..."
    TRANSCRIPT=$(curl -s -X POST "https://api.groq.com/openai/v1/audio/transcriptions" \
        -H "Authorization: Bearer $GROQ_KEY" \
        -F "file=@$AUDIO_FILE" \
        -F "model=whisper-large-v3" \
        -F "language=de" \
        -F "response_format=text" 2>/dev/null || echo "")
fi

# Method 3: Local whisper (if installed)
if command -v whisper &> /dev/null && [[ -z "$TRANSCRIPT" ]]; then
    echo "Using local Whisper..."
    TRANSCRIPT=$(whisper "$AUDIO_FILE" --language German --output_format txt 2>/dev/null | cat)
fi

# Method 4: Fallback - placeholder for manual transcription
if [[ -z "$TRANSCRIPT" ]]; then
    echo "⚠️  No transcription method available."
    echo "Install whisper-openai or provide API key via --openai-key or --groq-key"
    TRANSCRIPT="[Transcription pending - audio file: $BASENAME]

> This note was created as a placeholder. Please add transcription manually or configure API access.
> Audio file: $AUDIO_FILE"
fi

echo "✅ Transcription complete (${#TRANSCRIPT} characters)"

# Create output directory
OUTPUT_DIR="$VAULT/$FOLDER"
mkdir -p "$OUTPUT_DIR"

# Generate note with frontmatter
OUTPUT_FILE="$OUTPUT_DIR/${SAFE_TITLE}.md"
TIMESTAMP=$(date -Iseconds)
DURATION=$(ffprobe -i "$AUDIO_FILE" -show_entries format=duration -v quiet -of csv="p=0" 2>/dev/null | cut -d. -f1 || echo "unknown")

cat > "$OUTPUT_FILE" << NOTEEOF
---
title: "$TITLE"
created: $TIMESTAMP
type: transcript
source: audio
original_file: $(basename "$AUDIO_FILE")
duration_seconds: $DURATION
tags:
  - transcript
  - audio
  - meeting
---

# $TITLE

> 🎙️ Audio transcription from $(date +"%d.%m.%Y %H:%M")
> Duration: $((DURATION/60)):$((DURATION%60)) min

---

## Transkript

$TRANSCRIPT

---

## Zusammenfassung

> [TODO: Zusammenfassung hinzufügen]

## Kernpunkte

- [ ] [Kernpunkt 1]
- [ ] [Kernpunkt 2]
- [ ] [Kernpunkt 3]

## Aktionen

- [ ] [Aktion 1]
- [ ] [Aktion 2]

---

*Erstellt mit OpenClaw Audio Transcription*
NOTEEOF

echo "📝 Note created: $OUTPUT_FILE"

# Log completion
"$SCRIPT_DIR/log-action.sh" "transcribe" "audio-processor" "Created transcript note: $SAFE_TITLE" "high" >/dev/null 2>&1

# Output the file path
echo ""
echo "✅ Fertig: $OUTPUT_FILE"
