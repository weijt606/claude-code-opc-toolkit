#!/bin/sh
# statuslines/default-opc.sh
# Shows: <cwd-basename> | <git branch> | <model> | ctx <N%>
# Install:
#   ln -sf $PWD/statuslines/default-opc.sh ~/.claude/statusline-command.sh
# Then verify with /config in Claude Code.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

dir=$(basename "$cwd")
branch=""
if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

out="📁 $dir"
[ -n "$branch" ] && out="$out  ⎇ $branch"
out="$out  ✨ $model"
if [ -n "$used" ]; then
  out=$(printf "%s  ctx %.0f%%" "$out" "$used")
fi

printf "%s" "$out"
