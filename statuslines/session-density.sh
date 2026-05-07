#!/bin/sh
# statuslines/session-density.sh
# Shows: <cwd> | sid:<short> | live <N>/<total today> | 🤖 <subagents today>
# Counts live processes from ~/.claude/sessions/*.json (filtered by `kill -0`)
# and today's subagents from ~/.claude/monitor/events.jsonl (if hooks installed).

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
sid=$(echo "$input" | jq -r '.session_id // ""')
dir=$(basename "$cwd")

SESS_DIR="$HOME/.claude/sessions"
EV="$HOME/.claude/monitor/events.jsonl"

live=0
if [ -d "$SESS_DIR" ]; then
  for sf in "$SESS_DIR"/*.json; do
    [ -f "$sf" ] || continue
    pid=$(jq -r '.pid // ""' "$sf" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && live=$((live+1))
  done
fi

day_start="$(date -u +%Y-%m-%d)T00:00:00Z"
total_today=0
subagents_today=0
if [ -f "$EV" ]; then
  total_today=$(jq -r --arg s "$day_start" 'select(.event == "SessionStart" and .ts >= $s) | .session_id' "$EV" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  subagents_today=$(jq -r --arg s "$day_start" 'select(.event == "SubagentStop" and .ts >= $s) | .ts' "$EV" 2>/dev/null | wc -l | tr -d ' ')
fi

short_sid=""
[ -n "$sid" ] && short_sid="${sid%${sid#????????}}"

out="📁 $dir"
[ -n "$short_sid" ] && out="$out  sid:$short_sid"
out="$out  🟢 live $live/$total_today  🤖 $subagents_today"
printf "%s" "$out"
