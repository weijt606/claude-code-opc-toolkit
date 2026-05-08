#!/bin/bash
# pilot/pilot.sh — manage Claude Code permission rules safely.
#
# USAGE
#   cc-pilot suggest [flags]   Phase B: learn from your past Bash approvals,
#                              suggest permissions.allow patterns to merge
#                              into ~/.claude/settings.json. Refuses to
#                              suggest patterns matching destructive verbs.
#
# Future:
#   cc-pilot safe              Launch claude with read-only profile
#   cc-pilot dev               Launch claude with dev-friendly profile
#   cc-pilot yolo              Launch claude with bypassPermissions (DANGEROUS)
#
# This tool reads your local transcripts and (with your explicit consent)
# edits ~/.claude/settings.json. It makes zero network calls. It never
# auto-edits without showing you the diff and asking y/N.

set -e

PROJ_DIR="$HOME/.claude/projects"
SETTINGS_FILE="$HOME/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. brew install jq" >&2
  exit 1
fi

if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
  C_DIM=$'\033[2m'; C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_MAG=$'\033[35m'
else
  C_DIM=""; C_RESET=""; C_BOLD=""
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_CYAN=""; C_MAG=""
fi

show_help() {
  sed -n '2,17p' "$0" | sed 's/^# \?//'
}

# ── Subcommand: suggest ─────────────────────────────────────────────────────
#
# Walk transcripts, group Bash invocations into permission patterns, filter
# out anything matching the destructive deny list, drop anything already in
# the user's permissions.allow, and present a sorted "≥ MIN_COUNT" list.
# If user agrees, merge new patterns into ~/.claude/settings.json.

# Patterns we will NEVER suggest, even if the user invoked them often. These
# match a *literal* fragment of the raw command (case-sensitive). Refining
# this list as we learn what's risky.
DENY_PATTERNS=(
  "rm -rf"
  "rm -fr"
  "git push --force"
  "git push -f"
  "git reset --hard"
  "git clean -fd"
  "git clean -f"
  "git branch -D"
  "git checkout ."
  "git restore ."
  "sudo "
  "chmod -R"
  "chown -R"
  "dd if="
  "mkfs"
  "kill -9"
  "killall"
  "shutdown"
  "reboot"
  "format "
  ":(){"          # fork bomb
  "/dev/sda"
  "/dev/null > /dev/"
  "> /etc/"
  "> /usr/"
  "> /System/"
  "> /Library/"
  "> /bin/"
  "> /sbin/"
  "curl "         # any curl — network tool, user should manually allow specific URLs
  "wget "
  "nc "           # netcat
  "<(curl "       # process substitution into exec
  "<(wget "
)

# Read-only inspector verbs. When the FIRST token is one of these, we skip
# substring-based deny checks — the rest of the command is data being looked
# at, not commands being run. Without this, `grep -n "curl http" *.md`
# would falsely match the "curl " deny pattern.
READ_ONLY_VERBS="grep|find|cat|ls|awk|sed|jq|head|tail|wc|sort|uniq|tr|cut|xargs|echo|printf|pwd|which|type|file|du|df|env|basename|dirname|stat|tree|column|fold|fmt|nl|tac|tee|read"

# Shell-control / heredoc tails. If the first token is one of these, the
# "command" we're looking at is actually a heredoc body line, not a real
# command. Skip without recording.
HEREDOC_TAILS="EOF|EOL|HEREDOC|done|fi|else|elif|then|esac|do|while|for|case"

# Derive a permission-rule pattern from a raw command. Strategy:
#   - 1 token  → Bash(<token>)         exact
#   - 2+ tokens → Bash(<tok1> <tok2>*) prefix-wildcard
# Returns "" if the command isn't a real command (heredoc artifact, etc.).
derive_pattern() {
  local cmd="$1"
  # Strip leading whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  local tok1 tok2 rest
  read -r tok1 tok2 rest <<< "$cmd"
  [ -z "$tok1" ] && return
  # Reject heredoc artifacts (single-char tokens like \, control words like fi/done/EOF).
  [ "${#tok1}" -lt 2 ] && return
  if [[ "$tok1" =~ ^($HEREDOC_TAILS)$ ]]; then return; fi
  # Reject tokens that don't look like a command name (must start with letter,
  # digit, underscore, dot, or slash; allow a few normal chars after).
  if ! [[ "$tok1" =~ ^[a-zA-Z0-9_./][a-zA-Z0-9_./-]*$ ]]; then return; fi
  if [ -z "$tok2" ]; then
    printf 'Bash(%s)' "$tok1"
  else
    printf 'Bash(%s %s*)' "$tok1" "$tok2"
  fi
}

# Return 0 if cmd is dangerous, 1 if safe. Skips substring-based deny check
# when the first token is a read-only inspector (so e.g. `grep "rm -rf"`
# isn't flagged for the data it's reading).
is_dangerous() {
  local cmd="$1"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  local tok1; read -r tok1 _ <<< "$cmd"
  if [[ "$tok1" =~ ^($READ_ONLY_VERBS)$ ]]; then return 1; fi
  for pat in "${DENY_PATTERNS[@]}"; do
    if [[ "$cmd" == *"$pat"* ]]; then return 0; fi
  done
  return 1
}

cmd_suggest() {
  local DAYS=7 MIN_COUNT=5 YES=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --days)      DAYS="$2"; shift 2 ;;
      --min-count) MIN_COUNT="$2"; shift 2 ;;
      -y|--yes)    YES=1; shift ;;
      -h|--help)
        cat <<EOF
cc-pilot suggest — recommend permissions.allow patterns from your transcripts

USAGE
  cc-pilot suggest [--days N] [--min-count N] [-y|--yes]

FLAGS
  --days N         Look back this many days of transcripts (default: 7)
  --min-count N    Only suggest patterns invoked at least N times (default: 5)
  -y, --yes        Skip the merge confirmation prompt

EXAMPLE
  cc-pilot suggest --days 14 --min-count 3
EOF
        exit 0
        ;;
      *) shift ;;
    esac
  done

  local since
  since=$(date -u -v-"${DAYS}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
          || date -u -d "${DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ")

  printf '%s═══════════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_RESET"
  printf '%s   cc-pilot suggest — Bash patterns from last %d days%s\n' "$C_BOLD" "$DAYS" "$C_RESET"
  printf '%s═══════════════════════════════════════════════════════════════════%s\n\n' "$C_BOLD" "$C_RESET"

  # 1. Collect every Bash command from transcripts in window.
  local commands_file
  commands_file=$(mktemp)
  trap 'rm -f "$commands_file" "$commands_file.patterns" "$commands_file.allow" 2>/dev/null' EXIT

  # Take only the FIRST line of each command (avoid heredoc bodies/tails
  # leaking in as separate "commands" when bash `read` line-splits a
  # multi-line `.input.command` string downstream).
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | xargs -L 50 -P 1 cat 2>/dev/null \
    | jq -r --arg since "$since" '
        select(.type == "assistant" and (.timestamp // "") >= $since
               and (.message.content // null | type == "array"))
        | (.message.content // [])[]
        | select(.type == "tool_use" and .name == "Bash" and (.input.command // "") != "")
        | .input.command | split("\n")[0]
      ' 2>/dev/null > "$commands_file"

  local total
  total=$(wc -l < "$commands_file" | tr -d ' ')
  printf '  Reviewed %s%s%s Bash invocations\n\n' "$C_BOLD" "$total" "$C_RESET"

  if [ "$total" -eq 0 ]; then
    printf '  %sNo Bash activity found in the window — nothing to suggest.%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  # 2. Read currently-allowed patterns (if any) so we can skip duplicates.
  if [ -f "$SETTINGS_FILE" ]; then
    jq -r '.permissions.allow // [] | .[]' "$SETTINGS_FILE" 2>/dev/null > "$commands_file.allow"
  else
    : > "$commands_file.allow"
  fi
  local already_allowed
  already_allowed=$(wc -l < "$commands_file.allow" | tr -d ' ')

  # 3. For each command, derive pattern + flag dangerous + flag already-allowed.
  #    Output: <pattern>\t<status>\t<truncated_cmd>
  : > "$commands_file.patterns"
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    local pattern
    pattern=$(derive_pattern "$cmd")
    [ -z "$pattern" ] && continue
    local status="ok"
    if is_dangerous "$cmd"; then status="dangerous"; fi
    if grep -Fxq "$pattern" "$commands_file.allow" 2>/dev/null; then
      [ "$status" = "ok" ] && status="already_allowed"
    fi
    # Truncate command to 90 chars for display in blocked-section sample.
    # Drop tabs from cmd since we use tab as field separator.
    local cmd_short="${cmd//$'\t'/ }"
    [ "${#cmd_short}" -gt 90 ] && cmd_short="${cmd_short:0:87}..."
    printf '%s\t%s\t%s\n' "$pattern" "$status" "$cmd_short"
  done < "$commands_file" > "$commands_file.patterns"

  # 4. Group by pattern. CRITICAL: a pattern's status is "dangerous" if
  #    ANY single invocation matched the deny list — even if 99% were safe.
  #    Otherwise `Bash(git push*)` could get recommended on the basis of
  #    50 safe `git push origin` invocations and silently auto-approve
  #    a force-push next time. Status "already_allowed" applies when the
  #    pattern is already in user's allow list (and isn't dangerous).
  local recommended_file
  recommended_file=$(mktemp)

  awk -F'\t' -v min="$MIN_COUNT" '
    {
      counts[$1]++
      if ($2 == "dangerous" && !danger[$1]) {
        danger[$1] = 1
        sample[$1] = $3
      }
      if ($2 == "already_allowed" && !danger[$1]) allowed[$1] = 1
    }
    END {
      for (p in counts) {
        if (counts[p] < min) continue
        if      (danger[p])  { s = "dangerous";       smp = sample[p] }
        else if (allowed[p]) { s = "already_allowed"; smp = "" }
        else                 { s = "ok";              smp = "" }
        printf "%d\t%s\t%s\t%s\n", counts[p], p, s, smp
      }
    }
  ' "$commands_file.patterns" | sort -rn -t$'\t' -k1,1 > "$commands_file.grouped"

  # Section 1: recommended (status == ok)
  printf '%s✅ Recommended%s %s(safe, ≥%d invocations, not yet allowed)%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$MIN_COUNT" "$C_RESET"
  local recommended_count=0
  while IFS=$'\t' read -r count pattern status sample; do
    [ "$status" = "ok" ] && {
      printf '  %s%5d×%s  %s%s%s\n' "$C_BOLD" "$count" "$C_RESET" "$C_CYAN" "$pattern" "$C_RESET"
      printf '%s\n' "$pattern" >> "$recommended_file"
      recommended_count=$((recommended_count + 1))
    }
  done < "$commands_file.grouped"
  [ "$recommended_count" -eq 0 ] && printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"

  # Section 2: already in allow list
  printf '\n%sℹ️  Already in permissions.allow%s %s(no action needed)%s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET"
  local already_count=0
  while IFS=$'\t' read -r count pattern status sample; do
    [ "$status" = "already_allowed" ] && {
      printf '  %s%5d×%s  %s\n' "$C_DIM" "$count" "$C_RESET" "$pattern"
      already_count=$((already_count + 1))
    }
  done < "$commands_file.grouped"
  [ "$already_count" -eq 0 ] && printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"

  # Section 3: blocked from auto-suggesting (matched DENY pattern). Show the
  # specific invocation that triggered the block so the user can judge whether
  # the pattern is genuinely risky or whether one bad compound command is
  # tainting an otherwise-safe pattern (e.g. `git add . && rm -rf temp`
  # blocks `Bash(git add*)`).
  printf '\n%s🚫 Blocked from auto-suggesting%s %s(at least one invocation matched the destructive deny list)%s\n' "$C_RED" "$C_RESET" "$C_DIM" "$C_RESET"
  local blocked_count=0
  while IFS=$'\t' read -r count pattern status sample; do
    [ "$status" = "dangerous" ] && {
      printf '  %s%5d×%s  %s%s%s\n' "$C_DIM" "$count" "$C_RESET" "$C_RED" "$pattern" "$C_RESET"
      [ -n "$sample" ] && printf '         %striggered by:%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$sample" "$C_RESET"
      blocked_count=$((blocked_count + 1))
    }
  done < "$commands_file.grouped"
  [ "$blocked_count" -eq 0 ] && printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"

  # 5. Offer to merge.
  if [ "$recommended_count" -eq 0 ]; then
    rm -f "$recommended_file"
    printf '\n%s(no new patterns to add — your permissions.allow already covers your recent activity)%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  printf '\n'
  if [ "$YES" -ne 1 ]; then
    printf 'Add these %d pattern(s) to ~/.claude/settings.json [permissions.allow]? [y/N] ' "$recommended_count"
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || { printf '%saborted%s\n' "$C_DIM" "$C_RESET"; rm -f "$recommended_file"; return 0; }
  fi

  # 6. Backup and merge.
  local backup; backup="$SETTINGS_FILE.before-cc-pilot-$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS_FILE" "$backup" 2>/dev/null || true

  local new_settings
  new_settings=$(jq --slurpfile additions <(jq -R '.' "$recommended_file" | jq -s '.') '
    .permissions = (.permissions // {})
    | .permissions.allow = ((.permissions.allow // []) + $additions[0]) | .permissions.allow |= unique
    | .
  ' "$SETTINGS_FILE")

  if [ -z "$new_settings" ]; then
    printf '%serror: failed to update settings.json (left untouched)%s\n' "$C_RED" "$C_RESET"
    rm -f "$recommended_file"
    return 1
  fi

  printf '%s\n' "$new_settings" > "$SETTINGS_FILE"
  printf '%s✓ Merged %d pattern(s) into %s%s\n' "$C_GREEN" "$recommended_count" "$SETTINGS_FILE" "$C_RESET"
  printf '%s  backup: %s%s\n' "$C_DIM" "$backup" "$C_RESET"
  printf '\n%sNote:%s new permission rules apply to fresh sessions only — run %s/hooks%s in any\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
  printf '      open Claude Code session to reload settings, or just open a new session.\n'

  rm -f "$recommended_file"
}

# ── Dispatcher ──────────────────────────────────────────────────────────────
case "${1:-help}" in
  suggest)            shift; cmd_suggest "$@" ;;
  safe|dev|yolo)
    echo "cc-pilot $1: not yet implemented (Phase C). For now, see:" >&2
    echo "  cc-pilot suggest    # learn from past approvals (safe)" >&2
    echo "  --dangerously-skip-permissions  # raw bypass (use with caution)" >&2
    exit 1
    ;;
  help|-h|--help)     show_help; exit 0 ;;
  *)
    echo "unknown subcommand: $1" >&2
    echo ""
    show_help
    exit 1
    ;;
esac
