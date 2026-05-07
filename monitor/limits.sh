#!/bin/bash
# ~/.claude/monitor/limits.sh [--watch] [--days N]
# Claude Code usage / limits monitor.
#
# DATA SOURCES
#   1. ~/.claude/projects/*/*.jsonl     — every assistant message has .message.usage
#                                          {input_tokens, output_tokens,
#                                           cache_creation_input_tokens,
#                                           cache_read_input_tokens, model}
#   2. ~/.claude/sessions/<pid>.json    — live processes (sessionId, cwd, status, pid)
#
# CAVEATS
#   * Claude Code does NOT expose its internal rate-limit counter.
#     The "last 5h" block here is an APPROXIMATION based on aggregated usage,
#     not Anthropic's authoritative quota state.
#   * Pricing defaults assume Claude Opus 4 series (Anthropic published rates).
#     Override with env vars (see PRICING below).

PROJ_DIR="$HOME/.claude/projects"
SESS_DIR="$HOME/.claude/sessions"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. brew install jq" >&2
  exit 1
fi

# ── Pricing (USD per 1M tokens) — override via env vars ─────────────────────
PRICE_INPUT="${CC_PRICE_INPUT:-15.00}"          # input_tokens
PRICE_OUTPUT="${CC_PRICE_OUTPUT:-75.00}"        # output_tokens
PRICE_CACHE_WRITE="${CC_PRICE_CACHE_WRITE:-18.75}"  # cache_creation_input_tokens (5m default)
PRICE_CACHE_READ="${CC_PRICE_CACHE_READ:-1.50}"     # cache_read_input_tokens

if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
  C_DIM=$'\033[2m'; C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_MAG=$'\033[35m'
else
  C_DIM=""; C_RESET=""; C_BOLD=""
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_CYAN=""; C_MAG=""
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
DAYS="${DAYS:-7}"
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --watch|-w) WATCH=1; shift ;;
    --help|-h) sed -n '2,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) shift ;;
  esac
done

if stat -f %m "$0" >/dev/null 2>&1; then
  STAT_MTIME() { stat -f %m "$1" 2>/dev/null; }
else
  STAT_MTIME() { stat -c %Y "$1" 2>/dev/null; }
fi

read_cwd() { jq -r 'select(.cwd != null) | .cwd' "$1" 2>/dev/null | head -1; }

fmt_n() {
  # 1234567 → "1.2M"  (k/M/B)
  local n="$1"
  awk -v n="$n" 'BEGIN {
    if (n >= 1e9)      printf "%.1fB", n/1e9
    else if (n >= 1e6) printf "%.1fM", n/1e6
    else if (n >= 1e3) printf "%.1fk", n/1e3
    else                printf "%d", n
  }'
}

fmt_usd() {
  awk -v n="$1" 'BEGIN { printf "$%.2f", n }'
}

bar() {
  # bar <pct 0-100> <width 10>  → string of unicode blocks
  local pct="$1" width="${2:-10}"
  local filled
  filled=$(awk -v p="$pct" -v w="$width" 'BEGIN { printf "%d", (p * w + 50) / 100 }')
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$filled" -lt 0 ] && filled=0
  local empty=$((width - filled))
  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
}

cost_of() {
  # cost_of <input> <output> <cache_create> <cache_read> → USD
  awk -v i="$1" -v o="$2" -v cc="$3" -v cr="$4" \
      -v pi="$PRICE_INPUT" -v po="$PRICE_OUTPUT" \
      -v pcc="$PRICE_CACHE_WRITE" -v pcr="$PRICE_CACHE_READ" \
      'BEGIN {
        total = (i*pi + o*po + cc*pcc + cr*pcr) / 1e6
        printf "%.2f", total
      }'
}

# ── Aggregate one JSONL → totals JSON via jq ────────────────────────────────
sum_jsonl() {
  # arg1: file
  # arg2: optional ISO8601 lower bound (only count messages with .timestamp >= arg2)
  local f="$1" since="$2"
  jq -s --arg since "$since" '
    map(select(.type == "assistant" and .message.usage != null))
    | (if $since == "" then . else map(select((.timestamp // "") >= $since)) end)
    | {
        messages: length,
        input:        (map(.message.usage.input_tokens // 0)                    | add // 0),
        output:       (map(.message.usage.output_tokens // 0)                   | add // 0),
        cache_create: (map(.message.usage.cache_creation_input_tokens // 0)     | add // 0),
        cache_read:   (map(.message.usage.cache_read_input_tokens // 0)         | add // 0),
        models:       (map(.message.model // "?") | group_by(.) | map({(.[0]): length}) | add // {})
      }
  ' "$f" 2>/dev/null
}

# Aggregate ALL JSONLs into ONE jq pass (faster than per-file)
sum_all() {
  local since="$1"
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | xargs -L 50 -P 1 cat 2>/dev/null \
    | jq -s --arg since "$since" '
        map(select(.type == "assistant" and .message.usage != null))
        | (if $since == "" then . else map(select((.timestamp // "") >= $since)) end)
        | {
            messages: length,
            input:        (map(.message.usage.input_tokens // 0)                | add // 0),
            output:       (map(.message.usage.output_tokens // 0)               | add // 0),
            cache_create: (map(.message.usage.cache_creation_input_tokens // 0) | add // 0),
            cache_read:   (map(.message.usage.cache_read_input_tokens // 0)     | add // 0),
            models:       (map(.message.model // "?") | group_by(.) | map({(.[0]): length}) | add // {})
          }
      ' 2>/dev/null
}

# ── Render one snapshot ─────────────────────────────────────────────────────
render() {
  clear 2>/dev/null
  local now_epoch; now_epoch=$(date -u +%s)
  local since_5h since_1d since_nd
  since_5h=$(date -u -v-5H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '5 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  since_1d=$(date -u -v-1d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '1 day ago' +"%Y-%m-%dT%H:%M:%SZ")
  since_nd=$(date -u -v-"${DAYS}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "${DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ")

  printf '%s═══════════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_RESET"
  printf '%s   Claude Code Usage Monitor%s     %s\n' "$C_BOLD" "$C_RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '%s═══════════════════════════════════════════════════════════════════%s\n\n' "$C_BOLD" "$C_RESET"

  # ── Live processes from ~/.claude/sessions/<pid>.json ─────────────────────
  printf '%s🔥  Live processes%s %s(approx context size = last assistant turn input)%s\n' "$C_RED" "$C_RESET" "$C_DIM" "$C_RESET"
  local live_count=0
  if [ -d "$SESS_DIR" ]; then
    for sf in "$SESS_DIR"/*.json; do
      [ -f "$sf" ] || continue
      local sid status cwd pid
      sid=$(jq -r '.sessionId // ""' "$sf" 2>/dev/null)
      status=$(jq -r '.status // "?"' "$sf" 2>/dev/null)
      cwd=$(jq -r '.cwd // "?"' "$sf" 2>/dev/null)
      pid=$(jq -r '.pid // "?"' "$sf" 2>/dev/null)
      [ -z "$sid" ] && continue

      # Verify process is alive
      if ! kill -0 "$pid" 2>/dev/null; then continue; fi

      # Find the transcript jsonl for this sid
      local tj
      tj=$(find "$PROJ_DIR" -maxdepth 2 -name "${sid}.jsonl" -type f 2>/dev/null | head -1)
      local ctx="?"
      if [ -n "$tj" ]; then
        ctx=$(tail -200 "$tj" 2>/dev/null | jq -s '
          map(select(.type == "assistant" and .message.usage != null)) | last
          | (.message.usage.input_tokens + .message.usage.cache_creation_input_tokens + .message.usage.cache_read_input_tokens)
        ' 2>/dev/null)
        [ -z "$ctx" ] || [ "$ctx" = "null" ] && ctx="?"
      fi

      # Color status
      local sc
      case "$status" in
        busy)    sc="$C_YELLOW" ;;
        idle)    sc="$C_GREEN" ;;
        *)       sc="$C_DIM" ;;
      esac

      printf '    pid %-6s  %s%-12s%s  ctx %s%-7s%s  %s%-5s%s  %s\n' \
        "$pid" "$C_BOLD" "${sid:0:8}" "$C_RESET" \
        "$C_CYAN" "$(fmt_n "$ctx")" "$C_RESET" \
        "$sc" "$status" "$C_RESET" \
        "$cwd"
      live_count=$((live_count+1))
    done
  fi
  [ "$live_count" -eq 0 ] && printf '    %s(no live Claude Code processes)%s\n' "$C_DIM" "$C_RESET"

  # ── Last 5 hours (rolling rate-limit window proxy) ────────────────────────
  printf '\n%s⚡  Last 5 hours%s %s(rolling rate-limit window proxy — not authoritative)%s\n' "$C_YELLOW" "$C_RESET" "$C_DIM" "$C_RESET"
  local agg5; agg5=$(sum_all "$since_5h")
  if [ -z "$agg5" ]; then
    printf '    %s(no data)%s\n' "$C_DIM" "$C_RESET"
  else
    local m5 i5 o5 cc5 cr5 cost5
    m5=$(echo "$agg5"  | jq -r '.messages')
    i5=$(echo "$agg5"  | jq -r '.input')
    o5=$(echo "$agg5"  | jq -r '.output')
    cc5=$(echo "$agg5" | jq -r '.cache_create')
    cr5=$(echo "$agg5" | jq -r '.cache_read')
    cost5=$(cost_of "$i5" "$o5" "$cc5" "$cr5")
    printf '    Messages: %-8s   Input: %-7s  Output: %-7s  Cache W: %-7s  Cache R: %-7s  ≈ %s\n' \
      "$m5" "$(fmt_n "$i5")" "$(fmt_n "$o5")" "$(fmt_n "$cc5")" "$(fmt_n "$cr5")" "$(fmt_usd "$cost5")"
  fi

  # ── Today (last 24h) ──────────────────────────────────────────────────────
  printf '\n%s📊  Last 24 hours%s\n' "$C_BLUE" "$C_RESET"
  local agg1; agg1=$(sum_all "$since_1d")
  if [ -n "$agg1" ]; then
    local m1 i1 o1 cc1 cr1 cost1
    m1=$(echo "$agg1"  | jq -r '.messages')
    i1=$(echo "$agg1"  | jq -r '.input')
    o1=$(echo "$agg1"  | jq -r '.output')
    cc1=$(echo "$agg1" | jq -r '.cache_create')
    cr1=$(echo "$agg1" | jq -r '.cache_read')
    cost1=$(cost_of "$i1" "$o1" "$cc1" "$cr1")
    printf '    Messages: %-8s   Input: %-7s  Output: %-7s  Cache W: %-7s  Cache R: %-7s  ≈ %s\n' \
      "$m1" "$(fmt_n "$i1")" "$(fmt_n "$o1")" "$(fmt_n "$cc1")" "$(fmt_n "$cr1")" "$(fmt_usd "$cost1")"
    echo "$agg1" | jq -r '.models | to_entries | map("    \(.value)× \(.key)") | .[]' 2>/dev/null
  fi

  # ── Last N days ───────────────────────────────────────────────────────────
  printf '\n%s📅  Last %d days%s\n' "$C_MAG" "$DAYS" "$C_RESET"
  local aggn; aggn=$(sum_all "$since_nd")
  if [ -n "$aggn" ]; then
    local mn ina on ccn crn costn
    mn=$(echo "$aggn"  | jq -r '.messages')
    ina=$(echo "$aggn" | jq -r '.input')
    on=$(echo "$aggn"  | jq -r '.output')
    ccn=$(echo "$aggn" | jq -r '.cache_create')
    crn=$(echo "$aggn" | jq -r '.cache_read')
    costn=$(cost_of "$ina" "$on" "$ccn" "$crn")
    printf '    Messages: %-8s   Input: %-7s  Output: %-7s  Cache W: %-7s  Cache R: %-7s  ≈ %s\n' \
      "$mn" "$(fmt_n "$ina")" "$(fmt_n "$on")" "$(fmt_n "$ccn")" "$(fmt_n "$crn")" "$(fmt_usd "$costn")"
  fi

  # ── Top sessions in window (by output tokens) ─────────────────────────────
  printf '\n%s🏆  Top sessions by output (last %d days)%s\n' "$C_GREEN" "$DAYS" "$C_RESET"
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null | while IFS= read -r f; do
    local mt; mt=$(STAT_MTIME "$f")
    [ -z "$mt" ] && continue
    local age=$((now_epoch - mt))
    [ "$age" -gt $((DAYS * 86400)) ] && continue
    local sid; sid=$(basename "$f" .jsonl)
    local out; out=$(jq -s --arg since "$since_nd" '
      map(select(.type == "assistant" and .message.usage != null and (.timestamp // "") >= $since))
      | map(.message.usage.output_tokens // 0) | add // 0
    ' "$f" 2>/dev/null)
    [ -z "$out" ] || [ "$out" = "0" ] && continue
    local cwd; cwd=$(read_cwd "$f")
    [ -z "$cwd" ] && cwd="(unknown)"
    printf '%s\t%s\t%s\n' "$out" "${sid:0:8}" "$cwd"
  done | sort -rn | head -5 | while IFS=$'\t' read -r out sid cwd; do
    printf '    %s%-7s%s  %-9s  %s\n' "$C_BOLD" "$(fmt_n "$out")" "$C_RESET" "$sid" "$cwd"
  done

  # ── Footer ────────────────────────────────────────────────────────────────
  printf '\n%sPricing assumes Opus 4 series%s %s(input $%.2f / output $%.2f / cache W $%.2f / cache R $%.2f per 1M)%s\n' \
    "$C_DIM" "$C_RESET" "$C_DIM" "$PRICE_INPUT" "$PRICE_OUTPUT" "$PRICE_CACHE_WRITE" "$PRICE_CACHE_READ" "$C_RESET"
  printf '%sOverride: CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 cc-limits   (e.g. for Sonnet 4)%s\n' "$C_DIM" "$C_RESET"
  printf '%scc-limits --watch%s = live mode  ·  %scc-limits --days 30%s = wider window\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
}

if [ "$WATCH" = 1 ]; then
  trap 'tput cnorm 2>/dev/null; printf "\n"; exit 0' INT TERM
  tput civis 2>/dev/null
  while :; do
    render
    sleep "${REFRESH_INTERVAL:-60}"
  done
else
  render
fi
