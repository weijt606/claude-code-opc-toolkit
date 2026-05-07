#!/bin/sh
# statuslines/bilingual-cn.sh
# 中文 OPC 友好版本 · 显示：📁 项目 | ✨ 模型 | ctx | 🪙 今日 token | 北京时间
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
dir=$(basename "$cwd")

PROJ_DIR="$HOME/.claude/projects"
day_start="$(date -u +%Y-%m-%d)T00:00:00Z"

out_today=0
if [ -d "$PROJ_DIR" ]; then
  out_today=$(find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | xargs -L 50 cat 2>/dev/null \
    | jq -s --arg s "$day_start" '
        [.[] | select(.type == "assistant" and .message.usage != null and (.timestamp // "") >= $s)]
        | unique_by(.requestId // "")
        | map(.message.usage.output_tokens // 0) | add // 0
      ' 2>/dev/null)
fi

fmt_tok() { awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.1fk", n/1000; else printf "%d", n }'; }

# 北京时间（UTC+8）
beijing=$(TZ='Asia/Shanghai' date '+%H:%M')

out="📁 $dir  ✨ $model"
[ -n "$used" ] && out=$(printf "%s  📊 %.0f%%" "$out" "$used")
out="$out  🪙 $(fmt_tok "$out_today")  🕐 $beijing"
printf "%s" "$out"
