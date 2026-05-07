#!/bin/bash
# ~/.claude/monitor/resume.sh
# fzf picker across ALL Claude Code sessions, sorted by recency.
# Pipes the choice into `claude --resume <id>` so you can land back exactly where you were.

PROJ_DIR="$HOME/.claude/projects"

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf not found. Install with: brew install fzf" >&2
  echo "Fallback — Claude Code's built-in picker:  claude --resume" >&2
  exit 1
fi

if [ ! -d "$PROJ_DIR" ]; then
  echo "No sessions found at $PROJ_DIR" >&2
  exit 1
fi

if stat -f %m "$0" >/dev/null 2>&1; then
  STAT_MTIME() { stat -f %m "$1" 2>/dev/null; }
else
  STAT_MTIME() { stat -c %Y "$1" 2>/dev/null; }
fi

read_cwd() {
  jq -r 'select(.cwd != null) | .cwd' "$1" 2>/dev/null | head -1
}

human_age() {
  local s="$1"
  if   [ "$s" -lt 60 ];     then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ];   then printf '%dm' $((s/60))
  elif [ "$s" -lt 86400 ];  then printf '%dh' $((s/3600))
  else                           printf '%dd' $((s/86400))
  fi
}

NOW_EPOCH=$(date -u +%s)

# Build list: "<age>\t<sid_short>\t<size>\t<cwd>\t<sid_full>"
LIST=$(
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | while IFS= read -r f; do
        mt=$(STAT_MTIME "$f")
        [ -n "$mt" ] && printf '%s\t%s\n' "$mt" "$f"
      done \
    | sort -rn \
    | head -50 \
    | while IFS=$'\t' read -r mt f; do
        age=$((NOW_EPOCH - mt))
        sid=$(basename "$f" .jsonl)
        cwd=$(read_cwd "$f")
        [ -z "$cwd" ] && cwd="(empty)"
        size=$(du -h "$f" 2>/dev/null | cut -f1)
        printf '%s\t%s\t%s\t%s\t%s\n' "$(human_age "$age")" "${sid:0:8}" "$size" "$cwd" "$sid"
      done
)

[ -z "$LIST" ] && { echo "No sessions found." >&2; exit 1; }

# Display columns 1-4, hide full session id (column 5) for parsing.
CHOICE=$(printf '%s\n' "$LIST" \
  | awk -F'\t' '{ printf "%-6s  %-8s  %-6s  %s\t%s\n", $1, $2, $3, $4, $5 }' \
  | fzf \
      --delimiter=$'\t' \
      --with-nth=1 \
      --header='Pick a Claude Code session to resume (Esc to cancel)' \
      --height=70% \
      --reverse)

[ -z "$CHOICE" ] && exit 0

SID=$(printf '%s\n' "$CHOICE" | awk -F'\t' '{print $2}')
[ -z "$SID" ] && { echo "Could not parse session id." >&2; exit 1; }

echo "→ claude --resume $SID"
exec claude --resume "$SID"
