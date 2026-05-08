#!/bin/bash
# pilot/pilot.sh — manage Claude Code permission rules safely.
#
# SUBCOMMANDS
#   cc-pilot suggest [flags]   Phase B: learn from your past Bash approvals,
#                              suggest permissions.allow patterns to merge
#                              into ~/.claude/settings.json.
#
#   cc-pilot safe [args...]    Launch claude with read-only profile
#                              (Read/Glob/Grep + safe Bash inspectors).
#   cc-pilot dev [args...]     Launch with dev profile (safe + Edit/Write
#                              + builds/tests + reversible git mutations).
#                              Force-push, rm -rf, sudo etc. are denied.
#   cc-pilot yolo [args...]    Launch with --dangerously-skip-permissions.
#                              Refuses to start unless: (a) inside a git repo,
#                              (b) working tree is clean, (c) current branch
#                              is NOT main/master/develop/prod/release.
#                              Override with --i-understand-the-risk.
#
#   cc-pilot show <profile>    Print what a profile allows / denies.
#   cc-pilot list-profiles     List available profile files.
#
# Profiles live as plain text files in pilot/profiles/. Each line is one
# permission pattern (Claude Code rule syntax). Lines starting with # are
# comments. PRs welcome to extend the patterns.
#
# This tool reads only local files and uses official Claude Code flags
# (--allowed-tools, --disallowed-tools, --dangerously-skip-permissions).
# Zero network calls.

set -e

PROJ_DIR="$HOME/.claude/projects"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Resolve script's real directory even when invoked through a symlink, so
# we can find the profiles/ dir regardless of how the user installed.
_resolve_path() {
  local p="$1"
  while [ -L "$p" ]; do
    local target; target=$(readlink "$p")
    case "$target" in
      /*) p="$target" ;;
      *)  p="$(dirname "$p")/$target" ;;
    esac
  done
  echo "$p"
}
SCRIPT_PATH=$(_resolve_path "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/profiles"

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
  sed -n '2,30p' "$0" | sed 's/^# \?//'
}

# ── Profile-based launcher (Phase C) ────────────────────────────────────────
#
# Read a profile file (one rule per line, # = comment), build the args list
# for `claude --allowed-tools` / `--disallowed-tools`, and exec claude.

read_profile_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  # Print non-empty, non-comment lines.
  awk 'NF && !/^[[:space:]]*#/' "$f"
}

print_profile_summary() {
  local profile="$1" allow_count="$2" deny_count="$3"
  printf '%s═══════════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_RESET"
  printf '%s   cc-pilot %s%s — launching Claude Code with this profile\n' "$C_BOLD" "$profile" "$C_RESET"
  printf '%s═══════════════════════════════════════════════════════════════════%s\n\n' "$C_BOLD" "$C_RESET"
  printf '  %sAllow:%s   %s patterns auto-pass (no prompt)\n' "$C_GREEN" "$C_RESET" "$allow_count"
  if [ "$deny_count" -gt 0 ]; then
    printf '  %sDeny:%s    %s patterns force-prompt regardless of your global allow list\n' "$C_RED" "$C_RESET" "$deny_count"
  fi
  printf '  %sShow:%s    cc-pilot show %s\n' "$C_DIM" "$C_RESET" "$profile"
  printf '\n'
}

launch_with_profile() {
  local profile="$1"; shift
  local allow_file="$PROFILES_DIR/$profile.allow"
  local deny_file="$PROFILES_DIR/$profile.deny"

  if [ ! -f "$allow_file" ]; then
    echo "error: profile '$profile' not found at $allow_file" >&2
    echo "available profiles:" >&2
    ls "$PROFILES_DIR" 2>/dev/null | sed -E 's/\.(allow|deny)$//' | sort -u | sed 's/^/  /' >&2
    exit 1
  fi

  # Build arrays from profile files
  local allow_args=() deny_args=()
  while IFS= read -r line; do
    [ -n "$line" ] && allow_args+=("$line")
  done < <(read_profile_file "$allow_file")
  while IFS= read -r line; do
    [ -n "$line" ] && deny_args+=("$line")
  done < <(read_profile_file "$deny_file")

  print_profile_summary "$profile" "${#allow_args[@]}" "${#deny_args[@]}"

  # Build the claude command
  local cmd=(claude)
  if [ "${#allow_args[@]}" -gt 0 ]; then
    cmd+=(--allowed-tools "${allow_args[@]}")
  fi
  if [ "${#deny_args[@]}" -gt 0 ]; then
    cmd+=(--disallowed-tools "${deny_args[@]}")
  fi
  cmd+=("$@")

  exec "${cmd[@]}"
}

# Yolo preconditions — refuse to launch unless the user is set up to recover.
yolo_preflight() {
  local override="$1"

  if [ "$override" = "1" ]; then
    printf '%s⚠ %s--i-understand-the-risk%s — skipping safety preconditions.%s\n\n' \
      "$C_YELLOW" "$C_BOLD" "$C_RESET$C_YELLOW" "$C_RESET"
    return 0
  fi

  # Must be in a git repo
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s✗ yolo refuses: not inside a git repo.%s\n' "$C_RED" "$C_RESET"
    printf '  Recovery requires git history. Run %scd %s some_repo%s first, or pass\n' "$C_BOLD" "$C_RESET" ""
    printf '  %s--i-understand-the-risk%s if you really want to.\n' "$C_BOLD" "$C_RESET"
    exit 1
  fi

  # Working tree must be clean
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    printf '%s✗ yolo refuses: working tree has uncommitted changes.%s\n' "$C_RED" "$C_RESET"
    printf '  Run %sgit commit%s or %sgit stash%s first so you can recover via\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '  %sgit reset --hard%s if Claude does something unexpected.\n' "$C_BOLD" "$C_RESET"
    printf '  Or pass %s--i-understand-the-risk%s.\n' "$C_BOLD" "$C_RESET"
    exit 1
  fi

  # Current branch must not be a protected name
  local branch; branch=$(git branch --show-current 2>/dev/null)
  case "$branch" in
    main|master|develop|production|prod|release|stable)
      printf '%s✗ yolo refuses: you are on protected branch %s%s%s.%s\n' "$C_RED" "$C_BOLD" "$branch" "$C_RESET$C_RED" "$C_RESET"
      printf '  Switch to a feature/throwaway branch first:\n'
      printf '    %sgit checkout -b yolo-$(date +%%Y%%m%%d-%%H%%M%%S)%s\n' "$C_BOLD" "$C_RESET"
      printf '  Or pass %s--i-understand-the-risk%s.\n' "$C_BOLD" "$C_RESET"
      exit 1
      ;;
  esac

  # Show the situation and confirm
  local head; head=$(git rev-parse --short HEAD 2>/dev/null)
  printf '%s═══════════════════════════════════════════════════════════════════%s\n' "$C_RED" "$C_RESET"
  printf '%s   cc-pilot yolo — about to launch Claude with NO permission checks%s\n' "$C_BOLD" "$C_RESET"
  printf '%s═══════════════════════════════════════════════════════════════════%s\n\n' "$C_RED" "$C_RESET"
  printf '  Branch:    %s%s%s\n' "$C_BOLD" "$branch" "$C_RESET"
  printf '  HEAD:      %s\n' "$head"
  printf '  Worktree:  %sclean ✓%s\n' "$C_GREEN" "$C_RESET"
  printf '  Recovery:  %sgit reset --hard %s%s\n\n' "$C_BOLD" "$head" "$C_RESET"
  printf '  Claude can run any shell command without asking. This is intended for\n'
  printf '  short, sandboxed work in throwaway worktrees / containers.\n\n'
  printf 'Proceed? [y/N] '
  read -r ans
  [[ "$ans" =~ ^[Yy] ]] || { printf '%saborted%s\n' "$C_DIM" "$C_RESET"; exit 1; }
}

cmd_safe() { launch_with_profile "safe" "$@"; }
cmd_dev()  { launch_with_profile "dev"  "$@"; }

cmd_yolo() {
  local override=0
  local args=()
  for a in "$@"; do
    case "$a" in
      --i-understand-the-risk) override=1 ;;
      *) args+=("$a") ;;
    esac
  done
  yolo_preflight "$override"
  printf '\n%sLaunching: claude --dangerously-skip-permissions%s\n\n' "$C_DIM" "$C_RESET"
  exec claude --dangerously-skip-permissions "${args[@]}"
}

cmd_show() {
  local profile="$1"
  if [ -z "$profile" ]; then
    echo "usage: cc-pilot show <profile>" >&2
    cmd_list_profiles
    exit 1
  fi
  local allow_file="$PROFILES_DIR/$profile.allow"
  local deny_file="$PROFILES_DIR/$profile.deny"
  if [ ! -f "$allow_file" ] && [ ! -f "$deny_file" ]; then
    echo "no profile '$profile' found at $PROFILES_DIR" >&2
    cmd_list_profiles
    exit 1
  fi
  if [ -f "$allow_file" ]; then
    printf '%s═══ %s.allow %s═══%s\n' "$C_GREEN" "$profile" "(auto-pass)" "$C_RESET"
    sed 's/^/  /' "$allow_file"
    printf '\n'
  fi
  if [ -f "$deny_file" ]; then
    printf '%s═══ %s.deny %s═══%s\n' "$C_RED" "$profile" "(force-prompt)" "$C_RESET"
    sed 's/^/  /' "$deny_file"
    printf '\n'
  fi
}

cmd_list_profiles() {
  printf '%sAvailable profiles%s (in %s):\n' "$C_BOLD" "$C_RESET" "$PROFILES_DIR"
  if [ ! -d "$PROFILES_DIR" ]; then
    echo "  (profiles directory missing — try re-running install.sh)"
    return 0
  fi
  ls "$PROFILES_DIR" | sed -E 's/\.(allow|deny)$//' | sort -u | while read -r p; do
    [ -z "$p" ] && continue
    local n_allow n_deny
    n_allow=$(read_profile_file "$PROFILES_DIR/$p.allow" 2>/dev/null | wc -l | tr -d ' ')
    n_deny=$(read_profile_file "$PROFILES_DIR/$p.deny" 2>/dev/null | wc -l | tr -d ' ')
    printf '  %s%-8s%s  %s allow  %s%s deny%s\n' "$C_BOLD" "$p" "$C_RESET" "$n_allow" "$C_DIM" "$n_deny" "$C_RESET"
  done
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
  # `c` rather than `cmd` so shellcheck doesn't conflate this string-typed
  # local with launch_with_profile()'s array-typed `cmd` (different scopes,
  # different types — but SC2178 doesn't track scope).
  local c="$1"
  c="${c#"${c%%[![:space:]]*}"}"
  local tok1 tok2 rest
  read -r tok1 tok2 rest <<< "$c"
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
  local c="$1"
  c="${c#"${c%%[![:space:]]*}"}"
  local tok1; read -r tok1 _ <<< "$c"
  if [[ "$tok1" =~ ^($READ_ONLY_VERBS)$ ]]; then return 1; fi
  for pat in "${DENY_PATTERNS[@]}"; do
    if [[ "$c" == *"$pat"* ]]; then return 0; fi
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
  safe)               shift; cmd_safe "$@" ;;
  dev)                shift; cmd_dev "$@" ;;
  yolo)               shift; cmd_yolo "$@" ;;
  show)               shift; cmd_show "$@" ;;
  list|list-profiles) cmd_list_profiles ;;
  help|-h|--help)     show_help; exit 0 ;;
  *)
    echo "unknown subcommand: $1" >&2
    echo ""
    show_help
    exit 1
    ;;
esac
