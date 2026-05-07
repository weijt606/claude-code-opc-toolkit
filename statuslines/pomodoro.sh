#!/bin/sh
# statuslines/pomodoro.sh
# Shows: 🍅 <task> | <MM:SS elapsed> | <break/work>
# State file: ~/.claude/monitor/pomodoro.state  (epoch_start TASK)
# Control with helper aliases (see README for cc-pomo-start / cc-pomo-stop).
# Defaults: 25 min focus, 5 min break (override CC_POMO_FOCUS / CC_POMO_BREAK in seconds).

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
dir=$(basename "$cwd")

STATE="$HOME/.claude/monitor/pomodoro.state"
FOCUS=${CC_POMO_FOCUS:-1500}
BREAK=${CC_POMO_BREAK:-300}

if [ ! -f "$STATE" ]; then
  printf "🍅 idle  📁 %s  (cc-pomo-start \"task\" to begin)" "$dir"
  exit 0
fi

start=$(awk '{print $1}' "$STATE")
task=$(awk '{$1=""; sub(/^ /,""); print}' "$STATE")
[ -z "$task" ] && task="(no task)"

now=$(date +%s)
elapsed=$((now - start))

if [ "$elapsed" -lt "$FOCUS" ]; then
  remaining=$((FOCUS - elapsed))
  printf "🍅 %s  📁 %s  ⏱  %02d:%02d focus" "$task" "$dir" $((remaining/60)) $((remaining%60))
elif [ "$elapsed" -lt "$((FOCUS + BREAK))" ]; then
  remaining=$((FOCUS + BREAK - elapsed))
  printf "☕ %s  📁 %s  ⏱  %02d:%02d break" "$task" "$dir" $((remaining/60)) $((remaining%60))
else
  printf "✅ %s  📁 %s  done — cc-pomo-stop or cc-pomo-start \"next\"" "$task" "$dir"
fi
