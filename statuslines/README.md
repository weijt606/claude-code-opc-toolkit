# Statusline Gallery

Plug-and-play `statusLine` scripts for Claude Code — pick the one that matches what you're working on, swap with one `ln -sf`.

## Available templates

| Script | What it shows | Best for |
|--------|---------------|----------|
| [`default-opc.sh`](./default-opc.sh) | `📁 dir  ⎇ branch  ✨ model  ctx N%` | Daily driver — info-rich without clutter |
| [`cost-watch.sh`](./cost-watch.sh) | `✨ model  ctx N%  ⏰5h $X  📅24h $Y` | High-intensity days — keep cost visible |
| [`session-density.sh`](./session-density.sh) | `📁 dir  sid:xxx  🟢 live 3/8  🤖 12` | Multi-session / multi-agent workflows |
| [`pomodoro.sh`](./pomodoro.sh) | `🍅 task  📁 dir  ⏱  18:42 focus` | Focus mode — 25 min work / 5 min break |
| [`minimal.sh`](./minimal.sh) | `model · dir` | Narrow terminals / minimalists |
| [`build-in-public.sh`](./build-in-public.sh) | `📁 dir  ✨ model  ctx  🪙 142k  💬 35  🐦 6h` | OPC creators — keep BIP reminder visible |
| [`bilingual-cn.sh`](./bilingual-cn.sh) | `📁 dir  ✨ model  📊 N%  🪙 142k  🕐 14:30` | 中文环境 + 北京时间显示 |

## Install

```bash
# 1. Pick one
ln -sf $PWD/statuslines/cost-watch.sh ~/.claude/statusline-command.sh

# 2. Make sure your ~/.claude/settings.json has:
#    "statusLine": { "type": "command", "command": "sh /Users/YOU/.claude/statusline-command.sh" }
#    (install.sh leaves an existing statusLine alone — you may already have it)

# 3. Restart Claude Code or open a new session — statusline updates on every assistant turn.
```

## Swap quickly

```bash
# Aliases (drop in ~/.zshrc):
alias sl-default='ln -sf $HOME/dev/claude-code-opc-toolkit/statuslines/default-opc.sh ~/.claude/statusline-command.sh'
alias sl-cost='ln -sf $HOME/dev/claude-code-opc-toolkit/statuslines/cost-watch.sh ~/.claude/statusline-command.sh'
alias sl-pomo='ln -sf $HOME/dev/claude-code-opc-toolkit/statuslines/pomodoro.sh ~/.claude/statusline-command.sh'
alias sl-bip='ln -sf $HOME/dev/claude-code-opc-toolkit/statuslines/build-in-public.sh ~/.claude/statusline-command.sh'
```

## Pomodoro helpers

`pomodoro.sh` reads state from `~/.claude/monitor/pomodoro.state`. Helper aliases:

```bash
alias cc-pomo-start='_f(){ printf "%s %s\n" "$(date +%s)" "$*" > ~/.claude/monitor/pomodoro.state; }; _f'
alias cc-pomo-stop='rm -f ~/.claude/monitor/pomodoro.state'

# Usage:
cc-pomo-start "fix Stripe webhook 502"
# ... 25 min focus → 5 min break → done
cc-pomo-stop
```

## Build-in-Public last-post tracking

`build-in-public.sh` reads `~/.claude/monitor/last-x-post` (a single ISO timestamp). After you post on X / LinkedIn:

```bash
alias cc-bip-posted='date -u +%Y-%m-%dT%H:%M:%SZ > ~/.claude/monitor/last-x-post'
cc-bip-posted   # run after every BIP post
```

If it's been > 24h, the statusline shows `🐦 2d ⚠` to nudge you.

## Customizing

Each template is a single shell script. The Claude Code statusline command receives JSON on stdin:

```json
{
  "session_id": "abc...",
  "model": { "display_name": "Opus 4.7", "id": "claude-opus-4-7" },
  "workspace": { "current_dir": "/Users/me/dev/foo", "project_name": "foo" },
  "cwd": "/Users/me/dev/foo",
  "context_window": { "used_percentage": 42.3, "used_tokens": 84500, "total_tokens": 200000 }
}
```

Read what you need with `jq`, output one short line on stdout. That's the entire contract.

## Contributing a template

PRs welcome. Each template should:

1. Be a single `.sh` file under `statuslines/`
2. Have a header comment explaining what it shows + how to install
3. Output one line, no trailing newline
4. Stay fast (statusline runs on every assistant turn — keep it under ~200ms)
5. Add a row to the table above
