#!/bin/sh
# statuslines/minimal.sh
# Shows: <model> | <cwd basename>
# For narrow terminals or minimalists.
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
printf "%s · %s" "$model" "$(basename "$cwd")"
