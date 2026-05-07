# claude-code-opc-toolkit

[![English](https://img.shields.io/badge/lang-English-2962FF?style=flat-square)](./README.md)
[![中文](https://img.shields.io/badge/lang-%E4%B8%AD%E6%96%87-lightgrey?style=flat-square)](./README.zh-CN.md)
[![Built for Claude Code](https://img.shields.io/badge/built_for-Claude%20Code-D97757?style=flat-square)](https://claude.com/claude-code)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)](./LICENSE)

> A growing Claude Code productivity toolkit for solo full-stack AI developers — **One-Person Company / Solo Founder / Solo Builder**.

When you're a solo developer running Claude Code as your engineering team, you usually have **multiple sessions and subagents in flight at once** — frontend in one terminal, backend in another, an Agent crawling docs, a background task building. Claude Code's built-in `claude --resume` only knows about the current `cwd`, and there's no native way to see "what is everything I have running right now?".

This toolkit fills that gap:

- **Cross-session, cross-project visibility** — one dashboard, every session, real-time status
- **Multi-agent transparency** — see which subagents finished, in which session, when
- **One-keystroke resume** — fzf picker across every session you've ever opened, anywhere on disk
- **Hook-based event log** — JSONL stream of session lifecycle events for your own analytics

Built and tested on macOS / zsh. **This is a workshop, not a product** — I'll keep extracting and adding small tools (hooks, skills, statuslines, slash commands) from my own daily Claude Code workflow as they prove useful. **Issues and PRs are warmly welcome** — see [Contributing](#contributing).

---

## What's inside

```
claude-code-opc-toolkit/
├── monitor/
│   ├── log.sh         # Hook stdin → events.jsonl (never blocks the harness)
│   ├── view.sh        # Dashboard: active + recent sessions, prompt counts, subagents
│   └── resume.sh      # fzf picker → claude --resume <id>
├── settings.example.json   # 4 hooks ready to merge into ~/.claude/settings.json
└── install.sh         # One-shot: symlinks scripts + adds aliases
```

Scripts read from two sources of truth:

1. `~/.claude/projects/*/<session_id>.jsonl` — Claude Code's own transcripts. `mtime` = last activity, `.cwd` field inside = real working directory. Available without any setup.
2. `~/.claude/monitor/events.jsonl` — populated by the hooks. Adds prompt-by-project stats and subagent activity.

You can use `view.sh` and `resume.sh` **without** the hooks. The hooks add observability for prompts and subagents.

---

## Install

### Prerequisites
- macOS (BSD `stat`) or Linux (GNU `stat`) — both supported
- `bash`, `jq`, `fzf` — `brew install jq fzf`
- Claude Code CLI

### Quick install

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
```

This will:
1. Symlink `monitor/*.sh` into `~/.claude/monitor/`
2. Append 4 aliases (`cc-status`, `cc-watch`, `cc-resume`, `cc-tail`) to your `~/.zshrc`
3. Print the hook config you need to merge into `~/.claude/settings.json`

### Manual install

```bash
# 1. Clone wherever you keep tools
git clone https://github.com/weijt606/claude-code-opc-toolkit.git ~/dev/claude-code-opc-toolkit

# 2. Symlink scripts
mkdir -p ~/.claude/monitor
ln -sf ~/dev/claude-code-opc-toolkit/monitor/log.sh    ~/.claude/monitor/log.sh
ln -sf ~/dev/claude-code-opc-toolkit/monitor/view.sh   ~/.claude/monitor/view.sh
ln -sf ~/dev/claude-code-opc-toolkit/monitor/resume.sh ~/.claude/monitor/resume.sh

# 3. Add aliases to your shell rc
cat >> ~/.zshrc <<'EOF'
alias cc-status='$HOME/.claude/monitor/view.sh'
alias cc-watch='$HOME/.claude/monitor/view.sh --watch'
alias cc-resume='$HOME/.claude/monitor/resume.sh'
alias cc-tail='tail -f $HOME/.claude/monitor/events.jsonl | jq'
EOF

# 4. Merge hooks into ~/.claude/settings.json (see settings.example.json)
#    Then run /hooks inside Claude Code to reload, or restart Claude Code.
```

---

## Usage

### `cc-status` — one-shot snapshot

```
═══════════════════════════════════════════════════════
   Claude Code Session Monitor    2026-05-07 12:04:01
═══════════════════════════════════════════════════════

🟢  Active sessions (touched <30 min ago)
    1m ago    28531e24    /Users/you/dev/frontend
                resume: claude --resume 28531e24-07de-4068-a5fb-b6decd6fdee2    (8.4M)
    1m ago    ff76b1dc    /Users/you/dev/agent-graph
                resume: claude --resume ff76b1dc-79a7-4dec-bb82-12198ff4532a    (2.1M)

🕒  Recent sessions (last 24h, top 8 by recency)
    1m ago    28531e24  /Users/you/dev/frontend
    11m ago   2f9090dc  /Users/you/dev/agentagora
    ...

📊  Prompts by project (last 7d, from hook log)
       128 /Users/you/dev/agent-graph
        82 /Users/you/dev/frontend

🤖  Subagents finished (last 24h, from hook log)
    11:54:23  Explore           ff76b1dc
    12:01:42  claude-code-guide ff76b1dc
```

### `cc-watch` — live mode

```bash
cc-watch                       # default refresh: 30s
REFRESH_INTERVAL=5  cc-watch   # 5s — when actively monitoring
REFRESH_INTERVAL=120 cc-watch  # 2 min — set-and-forget on a side monitor
```

Ctrl-C to exit; cursor restores automatically.

### `cc-resume` — fzf one-key restore

```bash
cc-resume
```

Pops up an fzf picker of your last 50 sessions across all projects, sorted by recency. Pick one → automatically runs `claude --resume <id>`.

**Use this when** you closed a terminal, restarted your machine, or just can't remember which session you were in this morning.

### `cc-tail` — live event stream (debugging hooks)

```bash
cc-tail
```

Tail the JSONL with jq pretty-printing. Useful when adding new hooks or troubleshooting.

---

## Hook configuration

The hooks log session lifecycle events to `~/.claude/monitor/events.jsonl`. Without the hooks, `cc-status` and `cc-resume` still work — they just won't show prompt counts or subagent stats.

See [`settings.example.json`](./settings.example.json) for the exact JSON to merge into `~/.claude/settings.json`. Four events are wired:

| Event | Purpose |
|-------|---------|
| `SessionStart` | Detect new sessions and log their cwd |
| `SessionEnd` | Mark sessions as finished |
| `UserPromptSubmit` | Count prompts per project (rough activity proxy) |
| `SubagentStop` | Track Task-tool subagent runs |

After merging, run `/hooks` inside Claude Code to reload, or restart Claude Code. **New hooks do not apply to the current session.**

---

## Custom queries

Once events are flowing, you can write custom jq queries against `~/.claude/monitor/events.jsonl`:

```bash
# Hourly activity today
jq -r 'select(.ts >= "'$(date -u +%Y-%m-%d)'") | .ts | .[11:13]' \
  ~/.claude/monitor/events.jsonl | sort | uniq -c

# Sessions ranked by prompt count
jq -r 'select(.event == "UserPromptSubmit") | .session_id' \
  ~/.claude/monitor/events.jsonl | sort | uniq -c | sort -rn | head

# This month's session count by project
jq -r --arg m "$(date -u +%Y-%m)" \
  'select(.event == "SessionStart" and (.ts | startswith($m))) | .cwd' \
  ~/.claude/monitor/events.jsonl | sort | uniq -c | sort -rn
```

---

## Known limitations

- **New hooks don't fire in the current session** — run `/hooks` to reload, or restart Claude Code
- **`agent_type` field may be empty** depending on Claude Code version's `SubagentStop` payload
- **`events.jsonl` grows forever** — see Roadmap for log rotation
- **Privacy**: events.jsonl contains the first 80 chars of each prompt and full cwds. Don't push it to public repos. Add it to your `.gitignore` if you check `~/.claude/` into version control.
- **macOS-tested**; the BSD/GNU `stat` detection should make Linux work, but it's untested

---

## Roadmap

- [ ] `install.sh` adds the hook block automatically (with backup)
- [ ] Log rotation built into `log.sh` (when JSONL > 10MB)
- [ ] HTTP webhook hook variant — push to a self-hosted dashboard
- [ ] Daily summary auto-write to Obsidian daily notes
- [ ] More tools: skill-init, statusline templates, slash-command kits

PRs welcome. Issues even more welcome.

---

## Who is this for?

**Solo full-stack AI developers.** Whatever you call yourself, the audience is the same:

- **OPC** — One-Person Company; one person operating like a full team
- **Solo Founder** — running an indie product end-to-end
- **Solo Builder** — shipping side projects or your own startup
- **Indie Hacker** / **Vibe Coder** — same person, different vocabulary

When you're alone with Claude Code as your engineering leverage, observability matters more than in team environments — you can't ask a teammate "where were we?". This toolkit replaces that teammate with a dashboard.

---

## Contributing

This is a personal toolbox that I keep extracting from my own daily Claude Code workflow. Expect a steady trickle of new tools — hooks, skills, statuslines, slash commands, dashboards.

If you have a small friction in your own Claude Code workflow and built a fix → **PR it**.
If you have an idea but no fix → **open an issue**.

The bar for inclusion: *"would I install this in my own `~/.claude/` tomorrow?"* — pragmatic over polished, opinionated over comprehensive.

Bug reports and questions are equally welcome. The project is small enough that I read every issue.

---

## License

[MIT](./LICENSE) — use it, fork it, ship it.

## Author

[@weijt606](https://github.com/weijt606) · Part of an OPC toolbox alongside personal Obsidian knowledge graphs (vibe-coding-bible, GTM playbook, deployment handbook).
