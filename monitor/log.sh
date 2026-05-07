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
  # nz: coerce both null and empty-string to null. Claude Code's hook payloads
  # sometimes use "" for missing fields (notably .agent_type on SubagentStop),
  # which would otherwise render as a blank column in cc-status.
  echo "$INPUT" | jq -c --arg ts "$TS" --arg event "$EVENT" '
    def nz(v): if (v // "") == "" then null else v end;
    {
      ts: $ts,
      event: $event,
      session_id: nz(.session_id),
      cwd: nz(.cwd),
      source: nz(.source),
      transcript_path: nz(.transcript_path),
      prompt_preview: ((.prompt // "") | tostring | .[0:80]),
      agent_type: nz(.agent_type),
      tool_name: nz(.tool_name),
      hook_event_name: nz(.hook_event_name)
    }' >> "$LOG_FILE" 2>/dev/null \
    || printf '{"ts":"%s","event":"%s","raw":"jq_failed"}\n' "$TS" "$EVENT" >> "$LOG_FILE"
else
  printf '{"ts":"%s","event":"%s","raw":"no_jq"}\n' "$TS" "$EVENT" >> "$LOG_FILE"
fi

exit 0
