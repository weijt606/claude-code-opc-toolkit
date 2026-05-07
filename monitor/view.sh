#!/bin/bash
# ~/.claude/monitor/view.sh [--watch]
# Cross-project Claude Code session dashboard.
# Sources of truth:
#   1. ~/.claude/projects/*/<session_id>.jsonl  (Claude Code's own transcripts; mtime = last activity, cwd inside)
#   2. ~/.claude/monitor/events.jsonl           (hook log — cross-project event stream)

PROJ_DIR="$HOME/.claude/projects"
LOG_FILE="$HOME/.claude/monitor/events.jsonl"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Install with: brew install jq" >&2
  exit 1
fi

if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
  C_DIM=$'\033[2m'; C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_DIM=""; C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

# stat works differently on BSD (macOS) vs GNU. Detect once.
if stat -f %m "$0" >/dev/null 2>&1; then
  STAT_MTIME() { stat -f %m "$1" 2>/dev/null; }
else
  STAT_MTIME() { stat -c %Y "$1" 2>/dev/null; }
fi

# Read the real cwd from a transcript JSONL (first line with non-null .cwd).
read_cwd() {
  jq -r 'select(.cwd != null) | .cwd' "$1" 2>/dev/null | head -1
}

human_age() {
  local s="$1"
  if   [ "$s" -lt 60 ];     then printf '%ds ago' "$s"
  elif [ "$s" -lt 3600 ];   then printf '%dm ago' $((s/60))
  elif [ "$s" -lt 86400 ];  then printf '%dh ago' $((s/3600))
  else                           printf '%dd ago' $((s/86400))
  fi
}

# Build a sorted list "<mtime>\t<file>" of all session JSONLs (newest first).
session_files() {
  [ -d "$PROJ_DIR" ] || return
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null | while IFS= read -r f; do
    local mt; mt=$(STAT_MTIME "$f")
    [ -n "$mt" ] && printf '%s\t%s\n' "$mt" "$f"
  done | sort -rn
}

render() {
  clear 2>/dev/null
  local now_epoch; now_epoch=$(date -u +%s)
  local since_24h; since_24h=$(date -u -v-1d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '1 day ago' +"%Y-%m-%dT%H:%M:%SZ")
  local since_7d;  since_7d=$(date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '7 days ago' +"%Y-%m-%dT%H:%M:%SZ")

  printf '%s═══════════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_RESET"
  printf '%s   Claude Code Session Monitor%s        %s\n' "$C_BOLD" "$C_RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '%s═══════════════════════════════════════════════════════════════════%s\n\n' "$C_BOLD" "$C_RESET"

  # Read all sessions once into an array to avoid subshell scope issues.
  local SESS; SESS=$(session_files)

  # ── Active sessions (mtime within last 30 min) ────────────────────────────
  printf '%s🟢  Active sessions%s %s(touched <30 min ago)%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$C_RESET"
  local found_active=0
  while IFS=$'\t' read -r mt f; do
    [ -z "$mt" ] && continue
    local age=$((now_epoch - mt))
    [ "$age" -gt 1800 ] && continue
    local sid; sid=$(basename "$f" .jsonl)
    local cwd; cwd=$(read_cwd "$f")
    [ -z "$cwd" ] && cwd="(unknown — empty transcript)"
    local size; size=$(du -h "$f" 2>/dev/null | cut -f1)
    printf '    %s%-8s%s  %s%-12s%s  %s\n' "$C_CYAN" "$(human_age "$age")" "$C_RESET" "$C_BOLD" "${sid:0:8}" "$C_RESET" "$cwd"
    printf '    %s            resume: claude --resume %s    (%s)%s\n' "$C_DIM" "$sid" "$size" "$C_RESET"
    found_active=1
  done <<< "$SESS"
  [ "$found_active" -eq 0 ] && printf '    %s(no active sessions)%s\n' "$C_DIM" "$C_RESET"

  # ── Recent sessions (last 24h) ────────────────────────────────────────────
  printf '\n%s🕒  Recent sessions%s %s(last 24h, top 8 by recency)%s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET"
  local count=0
  while IFS=$'\t' read -r mt f; do
    [ -z "$mt" ] && continue
    local age=$((now_epoch - mt))
    [ "$age" -gt 86400 ] && continue
    [ "$count" -ge 8 ] && break
    local sid; sid=$(basename "$f" .jsonl)
    local cwd; cwd=$(read_cwd "$f")
    [ -z "$cwd" ] && cwd="(unknown)"
    printf '    %-8s  %s%s%s  %s\n' "$(human_age "$age")" "$C_BOLD" "${sid:0:8}" "$C_RESET" "$cwd"
    count=$((count+1))
  done <<< "$SESS"

  # ── From hook event log (only meaningful after Claude Code restart) ───────
  if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    printf '\n%s📊  Prompts by project%s %s(last 7d, from hook log)%s\n' "$C_YELLOW" "$C_RESET" "$C_DIM" "$C_RESET"
    jq -r --arg since "$since_7d" '
      select(.event == "UserPromptSubmit" and .ts >= $since) | (.cwd // "unknown")
    ' "$LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -8 | sed "s/^/    /"

    printf '\n%s🤖  Subagents finished%s %s(last 24h, from hook log)%s\n' "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
    local sub_count
    sub_count=$(jq -r --arg since "$since_24h" 'select(.event == "SubagentStop" and .ts >= $since) | .ts' "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$sub_count" = "0" ]; then
      printf '    %s(none in window)%s\n' "$C_DIM" "$C_RESET"
    else
      jq -r --arg since "$since_24h" '
        select(.event == "SubagentStop" and .ts >= $since)
        | "    \(.ts | .[11:19])  \(.agent_type // "?")  \((.session_id // "?") | .[0:8])"
      ' "$LOG_FILE" 2>/dev/null | tail -10
    fi
  else
    printf '\n%s(hook log not yet populated — restart Claude Code or run /hooks to load new hooks)%s\n' "$C_DIM" "$C_RESET"
  fi

  printf '\n%scc-resume%s = pick a session interactively   %scc-status --watch%s = live mode (Ctrl-C to quit)\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
}

if [ "$1" = "--watch" ] || [ "$1" = "-w" ]; then
  trap 'tput cnorm 2>/dev/null; printf "\n"; exit 0' INT TERM
  tput civis 2>/dev/null
  while :; do
    render
    sleep "${REFRESH_INTERVAL:-30}"
  done
else
  render
fi
