#!/bin/bash
# ~/.claude/monitor/log.sh <event_type>
# Reads hook input JSON from stdin, appends one JSONL line to events.jsonl.
# Designed to never block the harness: errors silently fall through.

EVENT="$1"
LOG_DIR="$HOME/.claude/monitor"
LOG_FILE="$LOG_DIR/events.jsonl"
mkdir -p "$LOG_DIR"

INPUT="$(cat)"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Try jq path first; on any failure, write a minimal raw line so we never lose the event.
if command -v jq >/dev/null 2>&1; then
  echo "$INPUT" | jq -c --arg ts "$TS" --arg event "$EVENT" '{
    ts: $ts,
    event: $event,
    session_id: (.session_id // null),
    cwd: (.cwd // null),
    source: (.source // null),
    transcript_path: (.transcript_path // null),
    prompt_preview: ((.prompt // "") | tostring | .[0:80]),
    agent_type: (.agent_type // null),
    tool_name: (.tool_name // null),
    hook_event_name: (.hook_event_name // null)
  }' >> "$LOG_FILE" 2>/dev/null \
    || printf '{"ts":"%s","event":"%s","raw":"jq_failed"}\n' "$TS" "$EVENT" >> "$LOG_FILE"
else
  printf '{"ts":"%s","event":"%s","raw":"no_jq"}\n' "$TS" "$EVENT" >> "$LOG_FILE"
fi

exit 0
