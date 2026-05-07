#!/bin/sh
# statuslines/build-in-public.sh
# Shows: <cwd> | model | today's tokens | last X post age | today's prompts
# Designed for OPC who post Build-in-Public regularly — keeps context visible.
#
# Configure last-post timestamp by writing an ISO date to ~/.claude/monitor/last-x-post:
#   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > ~/.claude/monitor/last-x-post

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
dir=$(basename "$cwd")

PROJ_DIR="$HOME/.claude/projects"
EV="$HOME/.claude/monitor/events.jsonl"
LAST_POST="$HOME/.claude/monitor/last-x-post"

day_start="$(date -u +%Y-%m-%d)T00:00:00Z"

# Today's output tokens across all projects (rough activity signal)
out_today=0
if [ -d "$PROJ_DIR" ]; then
  out_today=$(find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | xargs -L 50 cat 2>/dev/null \
    | jq -s --arg s "$day_start" '
        [.[] | select(.type == "assistant" and .message.usage != null and (.timestamp // "") >= $s)]
        | map(.message.usage.output_tokens // 0) | add // 0
      ' 2>/dev/null)
fi

# Today's prompt count from event log
prompts_today=0
if [ -f "$EV" ]; then
  prompts_today=$(jq -r --arg s "$day_start" 'select(.event == "UserPromptSubmit" and .ts >= $s) | .ts' "$EV" 2>/dev/null | wc -l | tr -d ' ')
fi

# Time since last X post
post_str=""
if [ -f "$LAST_POST" ]; then
  last=$(cat "$LAST_POST" 2>/dev/null)
  if [ -n "$last" ]; then
    last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last" +%s 2>/dev/null || date -d "$last" +%s 2>/dev/null)
    if [ -n "$last_epoch" ]; then
      now_epoch=$(date +%s)
      diff=$((now_epoch - last_epoch))
      if [ "$diff" -lt 3600 ];      then post_str=$(printf "🐦 %dm" $((diff/60)))
      elif [ "$diff" -lt 86400 ];   then post_str=$(printf "🐦 %dh" $((diff/3600)))
      else                                post_str=$(printf "🐦 %dd ⚠" $((diff/86400))); fi
    fi
  fi
fi

# Format output tokens
fmt_tok() {
  awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.1fk", n/1000; else printf "%d", n }'
}

out="📁 $dir  ✨ $model"
[ -n "$used" ] && out=$(printf "%s  ctx %.0f%%" "$out" "$used")
out="$out  🪙 $(fmt_tok "$out_today")  💬 $prompts_today"
[ -n "$post_str" ] && out="$out  $post_str"

printf "%s" "$out"
