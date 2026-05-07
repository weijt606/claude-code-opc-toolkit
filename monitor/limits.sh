#!/bin/bash
# ~/.claude/monitor/limits.sh [--watch] [--days N] [--plan NAME] [--quota N]
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
#
# PLAN-AWARE BUDGET (optional)
#   Set CC_PLAN to one of: free | pro | max5 | max20 | team | api
#     export CC_PLAN=max20            # or pass --plan max20
#   This adds a "Plan budget" sub-block under the 5h section showing
#   estimated usage %, burn rate, and reset countdown — all approximations
#   from local data. Override the message cap with:
#     export CC_PLAN_MSG_LIMIT_5H=900   # or pass --quota 900
#   Defaults are best-effort community knowledge of Anthropic's published
#   numbers and may drift; override when Anthropic changes them.

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

# ── Plan-aware budget (optional, see PLAN-AWARE BUDGET note above) ──────────
# Approximate published 5h message caps. These DRIFT — override per-shell or
# per-call via CC_PLAN_MSG_LIMIT_5H / --quota when Anthropic changes them.
plan_meta() {
  case "$1" in
    free)            echo "10|Claude Free" ;;
    pro)             echo "225|Claude Pro" ;;
    max5)            echo "225|Claude Max (5×)" ;;
    max|max20)       echo "900|Claude Max (20×)" ;;
    team)            echo "225|Claude Team (per seat)" ;;
    api)             echo "0|Claude API (cost-based, no message cap)" ;;
    "")              echo "" ;;
    *)               echo "0|$1" ;;
  esac
}

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
    --days)  DAYS="$2"; shift 2 ;;
    --plan)  CC_PLAN="$2"; shift 2 ;;
    --quota) CC_PLAN_MSG_LIMIT_5H="$2"; shift 2 ;;
    --watch|-w) WATCH=1; shift ;;
    --help|-h) sed -n '2,28p' "$0" | sed 's/^# \?//'; exit 0 ;;
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

# Earliest assistant-message timestamp in [since, now]. Empty if none.
oldest_ts_in_window() {
  local since="$1"
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | xargs -L 50 -P 1 cat 2>/dev/null \
    | jq -rs --arg since "$since" '
        [ .[] | select(.type == "assistant" and .message.usage != null and (.timestamp // "") >= $since) | .timestamp ]
        | min // ""
      ' 2>/dev/null
}

# ISO8601 (with optional fractional seconds + Z) → epoch seconds, portable
iso_to_epoch() {
  local ts="$1"
  [ -z "$ts" ] && return
  # Strip fractional seconds and Z
  local clean; clean=$(echo "$ts" | sed -E 's/\.[0-9]+Z?$//; s/Z$//')
  date -u -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null \
    || date -u -d "$clean" +%s 2>/dev/null
}

human_dur() {
  # seconds → "2h 18m" or "47m" or "0s" (cap at days for big values)
  local s="$1"
  if   [ "$s" -le 0 ];      then printf '0s'
  elif [ "$s" -lt 60 ];     then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ];   then printf '%dm' $((s/60))
  elif [ "$s" -lt 86400 ];  then printf '%dh %dm' $((s/3600)) $(((s%3600)/60))
  else                           printf '%dd %dh' $((s/86400)) $(((s%86400)/3600))
  fi
}

# Render plan-budget sub-block under the 5h section.
# Args: $1 = m5 (messages in 5h window), $2 = since_5h ISO ts, $3 = now epoch
plan_block() {
  local m5="$1" since_5h="$2" now_epoch="$3"
  local plan="${CC_PLAN:-}"
  [ -z "$plan" ] && return

  local meta; meta=$(plan_meta "$plan")
  local quota label
  quota=$(echo "$meta" | cut -d'|' -f1)
  label=$(echo "$meta" | cut -d'|' -f2)
  [ -n "${CC_PLAN_MSG_LIMIT_5H:-}" ] && quota="$CC_PLAN_MSG_LIMIT_5H"

  printf '\n    %s%s%s' "$C_BOLD" "$label" "$C_RESET"
  printf '  %s(CC_PLAN=%s)%s' "$C_DIM" "$plan" "$C_RESET"
  printf '   %s⚠ estimated, not authoritative%s\n' "$C_YELLOW" "$C_RESET"

  if [ "$quota" -le 0 ]; then
    printf '    %s(no message cap on this plan — see cost line above)%s\n' "$C_DIM" "$C_RESET"
    return
  fi

  # Usage bar
  local pct color
  pct=$(awk -v u="$m5" -v q="$quota" 'BEGIN { printf "%.0f", (u*100)/q }')
  if   [ "$pct" -ge 80 ]; then color="$C_RED"
  elif [ "$pct" -ge 50 ]; then color="$C_YELLOW"
  else                         color="$C_GREEN"
  fi
  printf '    Usage:    %s%s%s / ~%s msgs   %s%s%s  %s%d%%%s\n' \
    "$C_BOLD" "$m5" "$C_RESET" "$quota" \
    "$color" "$(bar "$pct" 14)" "$C_RESET" \
    "$color" "$pct" "$C_RESET"

  # Burn rate + reset countdown — need oldest message in window
  local oldest; oldest=$(oldest_ts_in_window "$since_5h")
  if [ -z "$oldest" ] || [ "$m5" -le 0 ]; then
    printf '    %s(no recent activity — full budget available)%s\n' "$C_DIM" "$C_RESET"
    return
  fi

  local oldest_epoch; oldest_epoch=$(iso_to_epoch "$oldest")
  if [ -z "$oldest_epoch" ]; then
    return
  fi

  local window_age=$((now_epoch - oldest_epoch))
  [ "$window_age" -lt 60 ] && window_age=60   # avoid div-by-zero on very fresh windows

  local rate_per_hr; rate_per_hr=$(awk -v m="$m5" -v s="$window_age" 'BEGIN { printf "%.0f", (m*3600)/s }')
  local remaining=$((quota - m5))

  if [ "$remaining" -gt 0 ] && [ "$rate_per_hr" -gt 0 ]; then
    local eta_sec; eta_sec=$(awk -v r="$remaining" -v rh="$rate_per_hr" 'BEGIN { printf "%.0f", (r*3600)/rh }')
    printf '    Burn:     %s%s msg/hr%s  →  exhaust in ~%s\n' \
      "$C_CYAN" "$rate_per_hr" "$C_RESET" "$(human_dur "$eta_sec")"
  elif [ "$remaining" -le 0 ]; then
    printf '    %sBudget exceeded (%s over)%s — server may already be throttling\n' \
      "$C_RED" "$((m5 - quota))" "$C_RESET"
  fi

  # Window resets when oldest msg falls out of the rolling 5h
  local reset_epoch=$((oldest_epoch + 5*3600))
  local reset_in=$((reset_epoch - now_epoch))
  if [ "$reset_in" -gt 0 ]; then
    printf '    Resets:   %s in %s%s  %s(when oldest msg falls out of 5h window)%s\n' \
      "$C_GREEN" "$(human_dur "$reset_in")" "$C_RESET" "$C_DIM" "$C_RESET"
  fi
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

    # Optional plan-aware budget sub-block (rendered only when CC_PLAN is set)
    plan_block "$m5" "$since_5h" "$now_epoch"
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
  printf '%scc-limits --watch%s = live mode  ·  %s--days 30%s = wider window  ·  %s--plan max20%s = plan-aware budget\n' \
    "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
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
