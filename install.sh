#!/bin/bash
# install.sh — symlink monitor scripts into ~/.claude/monitor/
#               and append shell aliases to ~/.zshrc (or ~/.bashrc).
#
# Idempotent: safe to run multiple times.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITOR_SRC="$REPO_DIR/monitor"
MONITOR_DST="$HOME/.claude/monitor"
SKILLS_SRC="$REPO_DIR/skills"
SKILLS_DST="$HOME/.claude/skills-bin"   # 'skills-bin' not 'skills' — Claude Code reads ~/.claude/skills/ for actual skills
PILOT_SRC="$REPO_DIR/pilot"
PILOT_DST="$HOME/.claude/pilot"

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

say() { printf '%s%s%s\n' "$1" "$2" "$RESET"; }

# ── 1. Sanity checks ─────────────────────────────────────────────────────────
if [ ! -d "$MONITOR_SRC" ]; then
  say "$YELLOW" "✗ monitor/ not found at $MONITOR_SRC"
  exit 1
fi

for tool in jq fzf; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    say "$YELLOW" "⚠️  $tool not found. Install with: brew install $tool"
  fi
done

# ── 2. Symlink scripts ───────────────────────────────────────────────────────
mkdir -p "$MONITOR_DST"
for f in log.sh view.sh resume.sh limits.sh daily.sh; do
  ln -sf "$MONITOR_SRC/$f" "$MONITOR_DST/$f"
  say "$GREEN" "✓ symlinked $MONITOR_DST/$f -> $MONITOR_SRC/$f"
done

if [ -d "$SKILLS_SRC" ]; then
  mkdir -p "$SKILLS_DST"
  for f in "$SKILLS_SRC"/*.sh; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    ln -sf "$f" "$SKILLS_DST/$base"
    say "$GREEN" "✓ symlinked $SKILLS_DST/$base -> $f"
  done
fi

if [ -d "$PILOT_SRC" ]; then
  mkdir -p "$PILOT_DST"
  for f in "$PILOT_SRC"/*.sh; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    ln -sf "$f" "$PILOT_DST/$base"
    say "$GREEN" "✓ symlinked $PILOT_DST/$base -> $f"
  done
fi

# Statusline gallery — symlinked into ~/.claude/statuslines/, picked via `sl-<name>` aliases
SL_SRC="$REPO_DIR/statuslines"
SL_DST="$HOME/.claude/statuslines"
if [ -d "$SL_SRC" ]; then
  mkdir -p "$SL_DST"
  for f in "$SL_SRC"/*.sh; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    ln -sf "$f" "$SL_DST/$base"
    say "$GREEN" "✓ symlinked $SL_DST/$base -> $f"
  done
  say "$DIM" "  Switch with: ln -sf $SL_DST/<name>.sh ~/.claude/statusline-command.sh"
fi

# ── 3. Append aliases (idempotent) ───────────────────────────────────────────
RC_FILE=""
if [ -f "$HOME/.zshrc" ]; then RC_FILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then RC_FILE="$HOME/.bashrc"
fi

ALIAS_BLOCK_MARKER="# claude-code-opc-toolkit aliases"
ALIAS_BLOCK=$(cat <<'EOF'

# claude-code-opc-toolkit aliases
alias cc-status='$HOME/.claude/monitor/view.sh'
alias cc-watch='$HOME/.claude/monitor/view.sh --watch'
alias cc-resume='$HOME/.claude/monitor/resume.sh'
alias cc-limits='$HOME/.claude/monitor/limits.sh'
alias cc-daily='$HOME/.claude/monitor/daily.sh'
alias cc-tail='tail -f $HOME/.claude/monitor/events.jsonl | jq'
alias cc-skill-init='$HOME/.claude/skills-bin/skill-init.sh'
alias cc-pilot='$HOME/.claude/pilot/pilot.sh'

# statusline switchers (run, then restart Claude Code or open a new session)
alias sl-default='ln -sf $HOME/.claude/statuslines/default-opc.sh $HOME/.claude/statusline-command.sh && echo "→ default-opc"'
alias sl-cost='ln -sf $HOME/.claude/statuslines/cost-watch.sh $HOME/.claude/statusline-command.sh && echo "→ cost-watch"'
alias sl-session='ln -sf $HOME/.claude/statuslines/session-density.sh $HOME/.claude/statusline-command.sh && echo "→ session-density"'
alias sl-pomo='ln -sf $HOME/.claude/statuslines/pomodoro.sh $HOME/.claude/statusline-command.sh && echo "→ pomodoro"'
alias sl-minimal='ln -sf $HOME/.claude/statuslines/minimal.sh $HOME/.claude/statusline-command.sh && echo "→ minimal"'
alias sl-bip='ln -sf $HOME/.claude/statuslines/build-in-public.sh $HOME/.claude/statusline-command.sh && echo "→ build-in-public"'
alias sl-cn='ln -sf $HOME/.claude/statuslines/bilingual-cn.sh $HOME/.claude/statusline-command.sh && echo "→ bilingual-cn"'

# pomodoro helpers (state at ~/.claude/monitor/pomodoro.state)
alias cc-pomo-start='_f(){ printf "%s %s\n" "$(date +%s)" "$*" > $HOME/.claude/monitor/pomodoro.state; }; _f'
alias cc-pomo-stop='rm -f $HOME/.claude/monitor/pomodoro.state'

# build-in-public last-post timestamp
alias cc-bip-posted='date -u +%Y-%m-%dT%H:%M:%SZ > $HOME/.claude/monitor/last-x-post && echo "BIP timestamp updated"'
EOF
)

if [ -n "$RC_FILE" ]; then
  if grep -qF "$ALIAS_BLOCK_MARKER" "$RC_FILE"; then
    say "$DIM" "✓ aliases already present in $RC_FILE (skipped)"
  else
    printf '%s\n' "$ALIAS_BLOCK" >> "$RC_FILE"
    say "$GREEN" "✓ added aliases to $RC_FILE"
    say "$DIM"   "  run: source $RC_FILE  (or open a new terminal)"
  fi
else
  say "$YELLOW" "⚠️  No ~/.zshrc or ~/.bashrc found — add aliases manually:"
  printf '%s\n' "$ALIAS_BLOCK"
fi

# ── 4. Print hook config to copy ─────────────────────────────────────────────
say "$BOLD" ""
say "$BOLD" "Next step: merge hooks into ~/.claude/settings.json"
say "$BOLD" "═══════════════════════════════════════════════════════════════════"
cat <<'EOF'

Add this `hooks` block to your settings.json (merge with existing keys):

  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "/Users/$USER/.claude/monitor/log.sh SessionStart" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/Users/$USER/.claude/monitor/log.sh SessionEnd" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Users/$USER/.claude/monitor/log.sh UserPromptSubmit" }] }],
    "SubagentStop":     [{ "hooks": [{ "type": "command", "command": "/Users/$USER/.claude/monitor/log.sh SubagentStop" }] }]
  }

⚠️  Replace $USER with your actual home username (Claude Code does not expand $USER in hook commands).

After merging:
  1. Inside Claude Code, type /hooks to reload — OR restart Claude Code.
  2. New hooks DO NOT fire in the current session.

Verify with:
  cc-status                # should now show prompt counts after a few prompts in a fresh session
  cc-tail                  # live-tail the event stream as you work

Full template: ./settings.example.json
EOF

say "$BOLD" "═══════════════════════════════════════════════════════════════════"
say "$GREEN" "✓ install.sh done."
