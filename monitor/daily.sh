#!/bin/bash
# monitor/daily.sh
# Generate or update <project>/daily-worklog.md with today's Claude Code activity.
#
# DEFAULT BEHAVIOR
#   For each project that had Claude Code activity in the target day, prepend
#   a new section to that project's <project_root>/daily-worklog.md.
#
# USAGE
#   cc-daily                          # write today's section to every active project
#   cc-daily 2026-05-06               # specific date (YYYY-MM-DD, UTC)
#   cc-daily --here                   # only the current project (cwd)
#   cc-daily --project <path>         # only that project
#   cc-daily --export obsidian        # ALSO write to Obsidian vault
#   cc-daily --export notion          # ALSO push to Notion (requires NOTION_API_KEY + NOTION_DB_ID)
#   cc-daily --global-summary         # ALSO write a cross-project summary at $CC_DAILY_SUMMARY_PATH
#   cc-daily --dry-run                # show what would be written, don't touch files
#
# CONFIG (env vars)
#   CC_OBSIDIAN_VAULT       Path to vault root (e.g. "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/obsidian")
#   CC_OBSIDIAN_DAILY_PATH  Daily-notes subpath inside vault (e.g. "Daily Notes")
#   CC_DAILY_SUMMARY_PATH   Where --global-summary goes (default: $CC_OBSIDIAN_VAULT/Daily Notes if vault set)
#   NOTION_API_KEY          Integration token for Notion export
#   NOTION_DB_ID            Database ID to push pages into
#
# WHAT GOES IN A SECTION
#   ## YYYY-MM-DD
#       totals (messages, tokens out, est cost, sessions, subagents)
#       prompts list (with timestamps + truncated text)
#       subagents list
#       files touched (Edit/Write tool inputs, if hook log present)

set -e

PROJ_DIR="$HOME/.claude/projects"
EVENT_LOG="$HOME/.claude/monitor/events.jsonl"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. brew install jq" >&2
  exit 1
fi

# ── Parse args ──────────────────────────────────────────────────────────────
DATE_ARG=""
ONLY_HERE=0
ONLY_PROJECT=""
EXPORT_OBSIDIAN=0
EXPORT_NOTION=0
GLOBAL_SUMMARY=0
DRY_RUN=0

show_help() { sed -n '2,30p' "$0" | sed 's/^# \?//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)        show_help; exit 0 ;;
    --here)           ONLY_HERE=1; shift ;;
    --project)        ONLY_PROJECT="$2"; shift 2 ;;
    --export)
                      case "$2" in
                        obsidian) EXPORT_OBSIDIAN=1 ;;
                        notion)   EXPORT_NOTION=1 ;;
                        all)      EXPORT_OBSIDIAN=1; EXPORT_NOTION=1 ;;
                        *)        echo "unknown export target: $2" >&2; exit 1 ;;
                      esac
                      shift 2
                      ;;
    --global-summary) GLOBAL_SUMMARY=1; shift ;;
    --dry-run|-n)     DRY_RUN=1; shift ;;
    -*)               echo "unknown flag: $1" >&2; show_help >&2; exit 1 ;;
    *)                if [ -z "$DATE_ARG" ]; then DATE_ARG="$1"; else echo "extra arg: $1" >&2; exit 1; fi; shift ;;
  esac
done

# Default to today (UTC)
[ -z "$DATE_ARG" ] && DATE_ARG=$(date -u +%Y-%m-%d)

# Validate date format
if ! [[ "$DATE_ARG" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "error: date must be YYYY-MM-DD (got '$DATE_ARG')" >&2
  exit 1
fi

DAY_START="${DATE_ARG}T00:00:00Z"
DAY_END="${DATE_ARG}T23:59:59Z"

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
say() { printf '%s%s%s\n' "$1" "$2" "$RESET"; }

# ── Helpers ─────────────────────────────────────────────────────────────────
fmt_n() {
  awk -v n="$1" 'BEGIN {
    if      (n >= 1e9) printf "%.1fB", n/1e9
    else if (n >= 1e6) printf "%.1fM", n/1e6
    else if (n >= 1e3) printf "%.1fk", n/1e3
    else                printf "%d",   n
  }'
}

# Per-session aggregation for the day
session_summary() {
  local f="$1"
  jq -s --arg s "$DAY_START" --arg e "$DAY_END" '
    map(select(.type == "assistant" and .message.usage != null
               and (.timestamp // "") >= $s
               and (.timestamp // "") <= $e))
    | {
        messages: length,
        input:        (map(.message.usage.input_tokens // 0)                | add // 0),
        output:       (map(.message.usage.output_tokens // 0)               | add // 0),
        cache_create: (map(.message.usage.cache_creation_input_tokens // 0) | add // 0),
        cache_read:   (map(.message.usage.cache_read_input_tokens // 0)     | add // 0)
      }
  ' "$f" 2>/dev/null
}

# User prompts for the day, sorted, with truncation
user_prompts() {
  local f="$1"
  jq -s --arg s "$DAY_START" --arg e "$DAY_END" '
    map(select(.type == "user"
               and (.timestamp // "") >= $s
               and (.timestamp // "") <= $e
               and (.message.content // "" | type == "string")))
    | sort_by(.timestamp)
    | map({
        time: ((.timestamp // "") | .[11:16]),
        text: ((.message.content // "" | tostring) | gsub("\n"; " ") | .[0:140])
      })
  ' "$f" 2>/dev/null
}

# Files touched (from Edit/Write tool inputs in transcripts)
files_touched() {
  local f="$1"
  jq -s --arg s "$DAY_START" --arg e "$DAY_END" '
    [ .[] | select(.type == "user"
                   and (.timestamp // "") >= $s
                   and (.timestamp // "") <= $e
                   and .message.content != null
                   and (.message.content | type == "array"))
          | .message.content[]
          | select(.type == "tool_result" and (.content // "" | type == "string"))
    ] | length' "$f" 2>/dev/null
}

# Cost estimate (Opus 4 defaults, override via env vars)
PRICE_INPUT="${CC_PRICE_INPUT:-15.00}"
PRICE_OUTPUT="${CC_PRICE_OUTPUT:-75.00}"
PRICE_CACHE_WRITE="${CC_PRICE_CACHE_WRITE:-18.75}"
PRICE_CACHE_READ="${CC_PRICE_CACHE_READ:-1.50}"

cost_of() {
  awk -v i="$1" -v o="$2" -v cc="$3" -v cr="$4" \
      -v pi="$PRICE_INPUT" -v po="$PRICE_OUTPUT" \
      -v pcc="$PRICE_CACHE_WRITE" -v pcr="$PRICE_CACHE_READ" \
      'BEGIN { printf "%.2f", (i*pi + o*po + cc*pcc + cr*pcr) / 1e6 }'
}

# Get real cwd from a transcript (.cwd field on first non-null line)
read_cwd() { jq -r 'select(.cwd != null) | .cwd' "$1" 2>/dev/null | head -1; }

# Build a markdown section for one transcript
build_section_for_transcript() {
  local f="$1" cwd="$2"
  local sid; sid=$(basename "$f" .jsonl)

  local agg; agg=$(session_summary "$f")
  local m i o cc cr
  m=$(echo "$agg"  | jq -r '.messages')
  i=$(echo "$agg"  | jq -r '.input')
  o=$(echo "$agg"  | jq -r '.output')
  cc=$(echo "$agg" | jq -r '.cache_create')
  cr=$(echo "$agg" | jq -r '.cache_read')
  [ "$m" -eq 0 ] && return  # no activity this day

  local cost; cost=$(cost_of "$i" "$o" "$cc" "$cr")

  printf '### Session %s\n' "${sid:0:8}"
  printf '%s **%s msgs** · out **%s** · cache R **%s** · est ≈ **$%s**\n\n' "$DIM" "$m" "$(fmt_n "$o")" "$(fmt_n "$cr")" "$cost"

  printf '**Top prompts**\n\n'
  user_prompts "$f" | jq -r '.[] | "- `\(.time)` \(.text)"' | head -8

  printf '\n'
}

# ── Build the per-project section ──────────────────────────────────────────
build_project_section() {
  local cwd="$1"
  shift
  local files=("$@")

  # Aggregate totals across all sessions for this project on this day
  local total_msg=0 total_in=0 total_out=0 total_cw=0 total_cr=0
  local subagents=0
  local seen_files=0

  for f in "${files[@]}"; do
    local agg; agg=$(session_summary "$f")
    local m i o cc cr
    m=$(echo "$agg"  | jq -r '.messages')
    i=$(echo "$agg"  | jq -r '.input')
    o=$(echo "$agg"  | jq -r '.output')
    cc=$(echo "$agg" | jq -r '.cache_create')
    cr=$(echo "$agg" | jq -r '.cache_read')
    [ "$m" -eq 0 ] && continue
    seen_files=$((seen_files + 1))
    total_msg=$((total_msg + m))
    total_in=$((total_in + i))
    total_out=$((total_out + o))
    total_cw=$((total_cw + cc))
    total_cr=$((total_cr + cr))
  done

  [ "$seen_files" -eq 0 ] && return

  # Subagent count from event log
  if [ -f "$EVENT_LOG" ]; then
    subagents=$(jq -r --arg cwd "$cwd" --arg s "$DAY_START" --arg e "$DAY_END" '
      select(.event == "SubagentStop" and .cwd == $cwd and .ts >= $s and .ts <= $e) | .ts
    ' "$EVENT_LOG" 2>/dev/null | wc -l | tr -d ' ')
  fi

  local cost; cost=$(cost_of "$total_in" "$total_out" "$total_cw" "$total_cr")

  printf '## %s\n\n' "$DATE_ARG"
  printf '**Sessions**: %s · **Messages**: %s · **Tokens out**: %s · **Subagents**: %s · **Est ≈** $%s\n\n' \
    "$seen_files" "$total_msg" "$(fmt_n "$total_out")" "$subagents" "$cost"

  printf '### What I worked on\n\n'
  printf '<!-- Fill in 1-2 sentences while it'\''s still fresh in your head. -->\n\n'

  for f in "${files[@]}"; do
    build_section_for_transcript "$f" "$cwd"
  done

  if [ "$subagents" -gt 0 ] && [ -f "$EVENT_LOG" ]; then
    printf '### Subagents fired\n\n'
    jq -r --arg cwd "$cwd" --arg s "$DAY_START" --arg e "$DAY_END" '
      select(.event == "SubagentStop" and .cwd == $cwd and .ts >= $s and .ts <= $e)
      | "- `\(.ts | .[11:16])` \(.agent_type // "?") (sid \((.session_id // "?") | .[0:8]))"
    ' "$EVENT_LOG" 2>/dev/null | head -10
    printf '\n'
  fi

  printf '### Lessons / next\n\n'
  printf '<!-- 1-2 things you learned. 1 thing to pick up tomorrow. -->\n\n'
  printf '\n'
}

# ── Prepend section to file (cumulative worklog) ────────────────────────────
prepend_to_worklog() {
  local target="$1" content="$2" project_name="$3"
  local tmp; tmp=$(mktemp)

  if [ -f "$target" ]; then
    # Check if today's section already exists — if so, replace it; else prepend
    if grep -q "^## $DATE_ARG\$" "$target"; then
      # Replace existing section (delete from this date until next ## or EOF)
      awk -v date="$DATE_ARG" '
        BEGIN { skip = 0 }
        /^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/ {
          if ($2 == date) { skip = 1; next }
          else if (skip) { skip = 0 }
        }
        !skip
      ' "$target" > "$tmp"
      # Now prepend new content
      {
        # Read existing header (everything before first ##)
        awk '/^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/ { exit } { print }' "$tmp"
        printf '%s' "$content"
        # Print from first ## onward
        awk 'found { print } /^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/ { found = 1; print }' "$tmp"
      } > "${tmp}.2"
      mv "${tmp}.2" "$target"
      rm -f "$tmp"
    else
      # Prepend after the title block
      {
        awk '/^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/ { exit } { print }' "$target"
        printf '%s' "$content"
        awk 'found { print } /^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/ { found = 1; print }' "$target"
      } > "$tmp"
      mv "$tmp" "$target"
    fi
  else
    # First time: write header + content
    {
      printf '# Daily Worklog · %s\n\n' "$project_name"
      printf '%s%s%s\n' '> Auto-generated by ' '[cc-daily](https://github.com/weijt606/claude-code-opc-toolkit)' '. Newest day first. Edit freely — re-running cc-daily will replace only the day section, not your handwritten parts within it.'
      printf '\n---\n\n'
      printf '%s' "$content"
    } > "$target"
  fi
}

# ── Discover projects with activity on this day ────────────────────────────
# Use a temp file with "cwd<TAB>jsonl_path" lines, sorted by cwd to group
# (avoids `declare -A` which isn't in macOS's default bash 3.2).
PAIRS_FILE=$(mktemp)
trap 'rm -f "$PAIRS_FILE" "$PAIRS_FILE.uniq" 2>/dev/null' EXIT

if [ -d "$PROJ_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    has_activity=$(jq -s --arg s "$DAY_START" --arg e "$DAY_END" '
      [.[] | select(.type == "assistant" and (.timestamp // "") >= $s and (.timestamp // "") <= $e)] | length
    ' "$f" 2>/dev/null)
    [ -z "$has_activity" ] || [ "$has_activity" = "0" ] && continue

    cwd=$(read_cwd "$f")
    [ -z "$cwd" ] && continue

    if [ "$ONLY_HERE" -eq 1 ] && [ "$cwd" != "$(pwd)" ]; then continue; fi
    if [ -n "$ONLY_PROJECT" ] && [ "$cwd" != "$ONLY_PROJECT" ]; then continue; fi

    printf '%s\t%s\n' "$cwd" "$f" >> "$PAIRS_FILE"
  done < <(find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null)
fi

if [ ! -s "$PAIRS_FILE" ]; then
  say "$YELLOW" "No Claude Code activity found for $DATE_ARG (with current filters)."
  exit 0
fi

sort -t $'\t' -k1,1 "$PAIRS_FILE" -o "$PAIRS_FILE"
cut -f1 "$PAIRS_FILE" | sort -u > "$PAIRS_FILE.uniq"

# ── Process each project ────────────────────────────────────────────────────
GLOBAL_SECTIONS=""

while IFS= read -r cwd; do
  [ -z "$cwd" ] && continue

  # Collect files for this cwd
  files=()
  while IFS=$'\t' read -r c f; do
    [ "$c" = "$cwd" ] && files+=("$f")
  done < "$PAIRS_FILE"

  [ "${#files[@]}" -eq 0 ] && continue

  project_name=$(basename "$cwd")
  section=$(build_project_section "$cwd" "${files[@]}")
  [ -z "$section" ] && continue

  target="$cwd/daily-worklog.md"

  if [ "$DRY_RUN" -eq 1 ]; then
    say "$BOLD" "── [DRY RUN] would update $target ──"
    printf '%s\n' "$section"
    say "$DIM" "── (end dry run for $project_name) ──"
    echo ""
  else
    if [ -d "$cwd" ] && [ -w "$cwd" ]; then
      prepend_to_worklog "$target" "$section" "$project_name"
      say "$GREEN" "✓ updated $target"
    else
      say "$YELLOW" "⚠ skipped $target (project dir missing or not writable)"
    fi
  fi

  # Accumulate for global summary
  if [ "$GLOBAL_SUMMARY" -eq 1 ] || [ "$EXPORT_OBSIDIAN" -eq 1 ]; then
    GLOBAL_SECTIONS+=$'\n## '"$project_name"' (`'"$cwd"$'`)\n\n'"$section"
  fi
done < "$PAIRS_FILE.uniq"

# ── Optional: global summary ───────────────────────────────────────────────
if [ "$GLOBAL_SUMMARY" -eq 1 ] || [ "$EXPORT_OBSIDIAN" -eq 1 ]; then
  GLOBAL_TARGET="${CC_DAILY_SUMMARY_PATH:-}"
  if [ -z "$GLOBAL_TARGET" ] && [ -n "$CC_OBSIDIAN_VAULT" ]; then
    daily_subpath="${CC_OBSIDIAN_DAILY_PATH:-Daily Notes}"
    GLOBAL_TARGET="$CC_OBSIDIAN_VAULT/$daily_subpath/$DATE_ARG.md"
  fi

  if [ -z "$GLOBAL_TARGET" ]; then
    say "$YELLOW" "⚠ --global-summary / --export obsidian needs CC_DAILY_SUMMARY_PATH or CC_OBSIDIAN_VAULT set."
  else
    summary=$(printf '# %s · Claude Code daily summary\n\n%s\n' "$DATE_ARG" "$GLOBAL_SECTIONS")
    if [ "$DRY_RUN" -eq 1 ]; then
      say "$BOLD" "── [DRY RUN] would write $GLOBAL_TARGET ──"
      printf '%s\n' "$summary"
    else
      mkdir -p "$(dirname "$GLOBAL_TARGET")"
      printf '%s\n' "$summary" > "$GLOBAL_TARGET"
      say "$GREEN" "✓ wrote summary $GLOBAL_TARGET"
    fi
  fi
fi

# ── Optional: Notion ────────────────────────────────────────────────────────
if [ "$EXPORT_NOTION" -eq 1 ]; then
  if [ -z "$NOTION_API_KEY" ] || [ -z "$NOTION_DB_ID" ]; then
    say "$YELLOW" "⚠ --export notion needs NOTION_API_KEY and NOTION_DB_ID env vars."
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "$BOLD" "── [DRY RUN] would POST to Notion DB $NOTION_DB_ID ──"
  else
    body=$(jq -n --arg db "$NOTION_DB_ID" --arg date "$DATE_ARG" --arg content "$GLOBAL_SECTIONS" '{
      parent: { database_id: $db },
      properties: {
        "Name": { title: [ { text: { content: ("Claude Code · " + $date) } } ] },
        "Date": { date: { start: $date } }
      },
      children: [
        { object: "block", type: "code",
          code: { language: "markdown", rich_text: [ { type: "text", text: { content: $content } } ] } }
      ]
    }')
    resp=$(curl -s -X POST "https://api.notion.com/v1/pages" \
      -H "Authorization: Bearer $NOTION_API_KEY" \
      -H "Content-Type: application/json" \
      -H "Notion-Version: 2022-06-28" \
      -d "$body")
    if echo "$resp" | jq -e '.id' >/dev/null 2>&1; then
      page_url=$(echo "$resp" | jq -r '.url')
      say "$GREEN" "✓ pushed to Notion: $page_url"
    else
      say "$YELLOW" "⚠ Notion push failed:"
      echo "$resp" | jq -r '.message // .' 2>/dev/null | head -3
    fi
  fi
fi
