# claude-code-opc-toolkit

<p align="center">
  <a href="./README.md"><img src="https://img.shields.io/badge/lang-English-2962FF?style=flat-square" alt="English"></a>
  <a href="./README.zh-CN.md"><img src="https://img.shields.io/badge/lang-%E4%B8%AD%E6%96%87-lightgrey?style=flat-square" alt="中文"></a>
  &nbsp;
  <a href="https://claude.com/claude-code"><img src="https://img.shields.io/badge/built_for-Claude%20Code-D97757?style=flat-square" alt="Built for Claude Code"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow?style=flat-square" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="#tools"><img src="https://img.shields.io/badge/tools-6-blue?style=flat-square" alt="6 tools"></a>
  <a href="./statuslines/"><img src="https://img.shields.io/badge/statuslines-7-7C3AED?style=flat-square" alt="7 statuslines"></a>
  <a href="./settings.example.json"><img src="https://img.shields.io/badge/hooks-4-D97757?style=flat-square" alt="4 hooks"></a>
  <a href="https://github.com/weijt606/claude-code-opc-toolkit/stargazers"><img src="https://img.shields.io/github/stars/weijt606/claude-code-opc-toolkit?style=flat-square&color=yellow" alt="GitHub stars"></a>
</p>

> Claude Code productivity toolkit for solo full-stack AI developers — **One-Person Company / Solo Founder / Solo Builder**.

A growing workshop of small tools I extract from my own daily Claude Code workflow: cross-session visibility, one-keystroke resume, token usage tracking, skill scaffolding, daily worklogs, statusline templates. Issues and PRs welcome.

---

## Quickstart

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
source ~/.zshrc

cc-status        # see all your Claude Code sessions
cc-resume        # fzf back to any past session, anywhere on disk
cc-limits        # token usage + cost across all transcripts
```

Requires `bash`, `jq`, `fzf`. On macOS: `brew install jq fzf`.

For prompt-count stats and subagent tracking, also merge the `hooks` block from [`settings.example.json`](./settings.example.json) into `~/.claude/settings.json` and run `/hooks` inside Claude Code (or restart).

---

## Tools

| Tool | Status | What it does |
|------|:------:|--------------|
| `cc-status` / `cc-watch` | ✅ | Cross-project session dashboard. Live mode with `cc-watch` (30s default; `REFRESH_INTERVAL=5` for tighter). |
| `cc-resume` | ✅ | fzf picker across every past session, sorted by recency → `claude --resume <id>`. |
| `cc-limits` | ✅ | Token usage + estimated cost. Live processes, 5h / 24h / N-day windows, top sessions. |
| `cc-daily` | ✅ | Per-project `daily-worklog.md` writer. Optional `--export obsidian` / `--export notion`. |
| `cc-skill-init <name>` | ✅ | Scaffold `.claude/skills/<name>/` with frontmatter, Step-0 read-context, README, prompts, templates. |
| `cc-tail` | ✅ | `tail -f` the hook event log with jq pretty-print. |
| Statusline gallery | ✅ | 7 plug-and-play `statusLine` scripts; swap with `sl-default` / `sl-cost` / `sl-pomo` / `sl-bip` / `sl-cn` / `sl-minimal` / `sl-session`. See [`statuslines/`](./statuslines/). |
| Hook event log | ✅ | `SessionStart` / `SessionEnd` / `UserPromptSubmit` / `SubagentStop` → `~/.claude/monitor/events.jsonl`. |

---

## Usage

### Sessions

```bash
cc-status                     # one-shot dashboard
cc-watch                      # auto-refresh (30s default)
REFRESH_INTERVAL=5 cc-watch   # tighter polling
cc-resume                     # fzf picker — pick any past session, Enter to resume
```

### Token usage & cost: `cc-limits`

```bash
cc-limits                     # live processes + 5h / 24h / 7d aggregates
cc-limits --days 30 --watch
```

Pricing defaults assume Opus 4 published rates. Override per-call:

```bash
# Sonnet 4
CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 CC_PRICE_CACHE_WRITE=3.75 CC_PRICE_CACHE_READ=0.30 cc-limits

# Haiku 4
CC_PRICE_INPUT=1 CC_PRICE_OUTPUT=5  CC_PRICE_CACHE_WRITE=1.25 CC_PRICE_CACHE_READ=0.10 cc-limits
```

> Claude Code does not expose its internal rate-limit counter — the 5h aggregate is a proxy, not authoritative quota state. On Claude Pro/Max the cost line is "value extracted at API rates", not a real bill.

### Daily worklog: `cc-daily`

```bash
cc-daily                      # write today's section to every active project
cc-daily 2026-05-06           # specific date (YYYY-MM-DD, UTC)
cc-daily --here               # only the current project (cwd)
cc-daily --dry-run            # preview without writing
cc-daily --export obsidian    # ALSO write to $CC_OBSIDIAN_VAULT/Daily Notes/<date>.md
cc-daily --export notion      # ALSO push to $NOTION_DB_ID (needs $NOTION_API_KEY)
```

Each project gets a single cumulative `<project_root>/daily-worklog.md` — newest day on top, prepended. Re-running for the same date replaces **only that day's section**; days you already annotated stay untouched.

### New skill in 1 command: `cc-skill-init`

```bash
cc-skill-init voc-collect -d "Mine customer quotes weekly" --opc
cc-skill-init seo-write -d "Draft SEO blog from voice + outline" --reads .agents/voice-of-customer.md
cc-skill-init my-utility --global         # ~/.claude/skills/ instead of ./.claude/skills/
```

Generates a complete skill structure (`SKILL.md` with frontmatter and `Step 0 · Context check`, `README.md`, `prompts/starter.md`, empty `templates/` and `examples/`).

### Statusline gallery

7 plug-and-play `statusLine` scripts. Each is a single shell file that reads Claude Code's stdin JSON (`.workspace.current_dir`, `.model.display_name`, `.context_window.used_percentage`) and prints one short line. `sl-*` aliases swap the active statusline with one keystroke — restart the Claude Code session for it to take effect.

| Alias | Shows | Best for |
|-------|-------|----------|
| `sl-default` | `📁 dir  ⎇ branch  ✨ model  ctx N%` | **Daily driver** — info-rich without clutter |
| `sl-cost` | `✨ model  ctx N%  ⏰5h $X  📅24h $Y` | **High-intensity days** — keep token spend visible (override pricing with `CC_PRICE_*` env vars) |
| `sl-session` | `📁 dir  sid:xxx  🟢 live 3/8  🤖 12` | **Multi-session work** — see live process count and today's subagent fires |
| `sl-pomo` | `🍅 task  📁 dir  ⏱  18:42 focus` | **Focus mode** — 25min focus / 5min break Pomodoro with task label |
| `sl-bip` | `📁 dir  🪙 142k  💬 35  🐦 6h` | **Build-in-Public** creators — nudges with ⚠ when last post > 24h |
| `sl-cn` | `📁 项目  ✨ 模型  📊 N%  🪙 142k  🕐 14:30` | **国内 OPC** — 中文 + 北京时间 + 今日 token |
| `sl-minimal` | `model · dir` | Narrow terminals / minimalists |

**Pomodoro** state lives at `~/.claude/monitor/pomodoro.state`:

```bash
cc-pomo-start "fix Stripe webhook 502"   # start a focus block
cc-pomo-stop                             # cancel
# defaults: 25 min focus, 5 min break — override with CC_POMO_FOCUS / CC_POMO_BREAK in seconds
```

**Build-in-Public** posting timestamp at `~/.claude/monitor/last-x-post`:

```bash
cc-bip-posted   # run after each X / LinkedIn post — statusline shows ⚠ if > 24h ago
```

Each statusline is ~50 lines of bash. Want a custom one? Copy any of the existing scripts in [`statuslines/`](./statuslines/), tweak the `printf`, drop your `.sh` next to them, and `ln -sf` it into `~/.claude/statusline-command.sh`. Full gallery doc + stdin schema reference: [`statuslines/README.md`](./statuslines/README.md).

---

## Hooks (optional)

Adds prompt counts, subagent tracking, and per-project activity stats. Merge the `hooks` block from [`settings.example.json`](./settings.example.json) into `~/.claude/settings.json`, then run `/hooks` inside Claude Code or restart.

⚠️ New hooks do **not** fire in the current session — only in fresh ones.

---

## Caveats

- **Rate limits**: Claude Code's internal counter is not exposed; the 5h block in `cc-limits` is a proxy.
- **Privacy**: `events.jsonl` and transcript files contain prompt previews and full cwd paths — don't push them to public repos.
- **Tested on macOS / zsh**; should work on Linux (BSD/GNU `stat` auto-detected) but not yet verified.

---

## Who is this for?

Solo full-stack AI developers running multiple Claude Code sessions in parallel. Whatever you call yourself — **OPC**, **Solo Founder**, **Solo Builder**, **Indie Hacker**, **Vibe Coder** — same toolset, same problem.

When you're alone with Claude Code as your engineering leverage, observability matters more than in team environments. This toolkit replaces "where were we?" with a dashboard.

---

## Contributing

PRs welcome. The bar is *"would I install this in my own `~/.claude/` tomorrow?"* — pragmatic over polished, opinionated over comprehensive. Bug reports and questions equally welcome.

---

## License

[MIT](./LICENSE) — use it, fork it, ship it.
