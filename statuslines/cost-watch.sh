#!/bin/sh
# statuslines/cost-watch.sh
# Shows: <model> | ctx <N%> | 5h ≈$X | day ≈$Y
# Aggregates today's & last-5h token usage from ~/.claude/projects/*/*.jsonl.
# Install:
#   ln -sf $PWD/statuslines/cost-watch.sh ~/.claude/statusline-command.sh
#
# Override pricing via env vars in your shell:
#   CC_PRICE_INPUT, CC_PRICE_OUTPUT, CC_PRICE_CACHE_WRITE, CC_PRICE_CACHE_READ

input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

PROJ_DIR="$HOME/.claude/projects"
PI=${CC_PRICE_INPUT:-15.00}
PO=${CC_PRICE_OUTPUT:-75.00}
PCW=${CC_PRICE_CACHE_WRITE:-18.75}
PCR=${CC_PRICE_CACHE_READ:-1.50}

# Cost over a window (since ISO timestamp)
cost_since() {
  since="$1"
  if [ ! -d "$PROJ_DIR" ]; then echo "0"; return; fi
  find "$PROJ_DIR" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null \
    | xargs -L 50 cat 2>/dev/null \
    | jq -s --arg s "$since" --arg pi "$PI" --arg po "$PO" --arg pcw "$PCW" --arg pcr "$PCR" '
        ([ .[] | select(.type == "assistant" and .message.usage != null and (.timestamp // "") >= $s) ]
        | {
            i: (map(.message.usage.input_tokens // 0)                | add // 0),
            o: (map(.message.usage.output_tokens // 0)               | add // 0),
            cw: (map(.message.usage.cache_creation_input_tokens // 0) | add // 0),
            cr: (map(.message.usage.cache_read_input_tokens // 0)     | add // 0)
          })
        | (.i * ($pi|tonumber) + .o * ($po|tonumber) + .cw * ($pcw|tonumber) + .cr * ($pcr|tonumber)) / 1000000
      ' 2>/dev/null
}

since_5h=$(date -u -v-5H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '5 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
since_1d=$(date -u -v-1d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '1 day ago'  +"%Y-%m-%dT%H:%M:%SZ")

c5h=$(cost_since "$since_5h" | awk '{printf "%.0f", $1+0.5}')
c1d=$(cost_since "$since_1d" | awk '{printf "%.0f", $1+0.5}')

out="✨ $model"
[ -n "$used" ] && out=$(printf "%s  ctx %.0f%%" "$out" "$used")
out="$out  ⏰5h \$$c5h  📅24h \$$c1d"
printf "%s" "$out"
