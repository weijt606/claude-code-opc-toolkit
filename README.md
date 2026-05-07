<p align="center">
  <img src="./banner.svg" alt="Claude-Code OPC Toolkit" width="100%" />
</p>

<p align="center">
  <a href="./README.md"><img src="https://img.shields.io/badge/lang-English-2962FF?style=flat-square" alt="English"></a>
  <a href="./README.zh-CN.md"><img src="https://img.shields.io/badge/lang-%E4%B8%AD%E6%96%87-lightgrey?style=flat-square" alt="中文"></a>
  &nbsp;·&nbsp;
  <a href="https://claude.com/claude-code"><img src="https://img.shields.io/badge/Claude%20Code-D97757?style=flat-square&logo=anthropic&logoColor=white" alt="Built for Claude Code"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/MIT-yellow?style=flat-square&label=license" alt="License: MIT"></a>
  &nbsp;·&nbsp;
  <a href="#tools"><img src="https://img.shields.io/badge/6-blue?style=flat-square&label=tools" alt="6 tools"></a>
  <a href="./statuslines/"><img src="https://img.shields.io/badge/7-7C3AED?style=flat-square&label=statuslines" alt="7 statuslines"></a>
  <a href="./settings.example.json"><img src="https://img.shields.io/badge/4-D97757?style=flat-square&label=hooks" alt="4 hooks"></a>
  <a href="https://github.com/weijt606/claude-code-opc-toolkit/stargazers"><img src="https://img.shields.io/github/stars/weijt606/claude-code-opc-toolkit?style=flat-square&color=FFCC00&label=%E2%98%85" alt="GitHub stars"></a>
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
cc-limits                          # default: last 24 hours
cc-limits -30m                     # last 30 minutes
cc-limits -1h                      # last 1 hour
cc-limits -7d                      # last 7 days
cc-limits -30d                     # last 30 days
cc-limits --last 6h                # long form
cc-limits -7d --watch              # auto-refresh
cc-limits --plan max5              # add plan-aware budget block (see below)
```

Every window shows: live processes · aggregate metrics for the window (input / output / cache / cost / per-model) · plan budget if `CC_PLAN` is set (always 5h-anchored, regardless of window) · top sessions by output in the window.

**Pricing override** — defaults assume Opus 4. Override per-call:

```bash
# Sonnet 4
CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 CC_PRICE_CACHE_WRITE=3.75 CC_PRICE_CACHE_READ=0.30 cc-limits

# Haiku 4
CC_PRICE_INPUT=1 CC_PRICE_OUTPUT=5  CC_PRICE_CACHE_WRITE=1.25 CC_PRICE_CACHE_READ=0.10 cc-limits
```

**Plan-aware budget** — set `CC_PLAN` (or pass `--plan`) to see estimated session budget %, burn rate, and reset countdown:

```bash
export CC_PLAN=max5       # or: pro | max5 | max20 | team | free | api
cc-limits

# Output gains a "🎯 Plan budget" block:
#
#     Claude Max 5× ($100/mo)  (CC_PLAN=max5)   ⚠ estimated, not authoritative
#     Usage:    145 / ~450 msgs   ████░░░░░░░░░░  32%
#     Burn:     123 msg/hr  →  exhaust in ~2h 28m
#     Resets:   in 3h 49m  (5h after session-start)
```

**Session anchoring**: the budget counts requests from the start of your **current session** (the first request after a quiet period), not the full rolling 5h. This matches how Anthropic's `claude.ai/settings/usage` "Current session" counter behaves. The default idle threshold is **30 minutes**; tune via:

```bash
export CC_SESSION_GAP_MIN=60   # 1h+ gap = new session (more conservative)
export CC_SESSION_GAP_MIN=15   # 15min+ gap = new session (more aggressive)
```

**Calibrating against your real dashboard reading**: the plan defaults (Pro ~90, Max 5× ~450, etc.) come from Anthropic's published guidance, but their internal `% used` is **opaque-weighted by request size/complexity**, so a static "count ÷ cap" estimate drifts. If `cc-limits --plan max5` says 45% but `claude.ai/settings/usage` says 60%, anchor the tool to your reality:

```bash
cc-limits --calibrate 60         # "I see 60% on the dashboard right now"
# → Computes your effective cap from the current request count
# → Saves to ~/.claude/monitor/cc-plan.conf
# → Future runs use the calibrated cap, marked "✓ calibrated"
```

Re-calibrate periodically when the underlying weight function drifts. Revert anytime:

```bash
cc-limits --calibrate-clear      # back to plan defaults
```

Defaults (verified **2026-05-07**, reflecting Anthropic's 2026-05-06 announcement that Claude Code 5h limits **doubled** for all paid tiers):

| Plan | 5h cap | Source flag |
|------|--------|------------|
| Free | ~10 | `--plan free` |
| Pro | ~90 | `--plan pro` |
| Max 5× ($100/mo) | ~450 | `--plan max5` (or `--plan max`) |
| Max 20× ($200/mo) | ~1800 | `--plan max20` |
| Team (per seat) | ~450 | `--plan team` |
| API | no cap | `--plan api` |

Override when Anthropic adjusts published quotas:

```bash
export CC_PLAN_MSG_LIMIT_5H=2000   # or: cc-limits --plan max20 --quota 2000
```

> ⚠️ **Anthropic does not expose subscription quota state via any public API**, and metering is **token-based** (a prompt with a big attachment can burn 10× a normal message). The plan budget block is a *local-data approximation*: 5h message count ÷ community-known published cap. Useful as a guardrail, **not** authoritative — server-side throttling can hit earlier or later than the bar suggests. There's also a **separate weekly cap** that this tool does not yet model. On Claude Pro/Max the cost line shows "value at API rates", not a real bill.

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
| `sl-cn` | `📁 项目  ✨ 模型  📊 N%  🪙 142k  🕐 14:30` | **Chinese-localized** — Chinese labels, Beijing time, today's tokens |
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

## How it works & safety

This toolkit reads only **local files Claude Code writes for you**. It makes zero outbound network requests, calls no Anthropic API, scrapes no claude.ai pages, and never touches your OAuth tokens or API keys.

| Behavior | This toolkit |
|----------|:------------:|
| Sends data to Anthropic | ❌ never |
| Calls Anthropic API (incl. private endpoints) | ❌ never |
| Reads / uploads OAuth tokens or API keys | ❌ never |
| Scrapes claude.ai or other web UIs | ❌ never |
| Loops Claude calls to inflate usage / bypass rate limits | ❌ never |
| Phones home with telemetry of any kind | ❌ never |
| Uses Claude Code's official `hooks` API | ✅ passive: read stdin → append JSONL |
| Reads `~/.claude/projects/*/*.jsonl` (your own transcripts) | ✅ your local files |
| Invokes `claude --resume <id>` (documented public CLI flag) | ✅ standard usage |

**Risk of account ban or platform alert**: none we can identify. With zero outbound requests, there's nothing for Anthropic to detect. Hooks, `--resume`, and `statusLine` are all official, publicly-documented extension points — using them as designed isn't a violation.

**The `cc-limits` "% used" estimate** is reverse-engineered from your own local data: count unique `requestId`s in your transcripts, divide by Anthropic's published per-plan caps. Verifying against your own claude.ai dashboard and updating defaults is a normal observation-and-arithmetic exercise, not exploitation.

### Real risks worth knowing about

- **Privacy is on you**. `~/.claude/monitor/events.jsonl` carries prompt previews + full cwd paths; `~/.claude/projects/*/*.jsonl` carries entire conversations. **Don't commit either to a public repo.** `.gitignore` covers `events.jsonl` already; if you sync `~/.claude/` anywhere, exclude `projects/` too.
- **Estimates aren't authoritative**. `cc-limits` plan budget, burn rate, reset countdown, and per-token cost projections are all derived locally and labeled `⚠ estimated, not authoritative` for a reason. Treat them as guardrails, not gospel — Anthropic's real meter can throttle earlier or later.
- **Hooks are powerful**. Our four hooks are passive (stdin → JSONL), but if you or a teammate later adds a hook that calls external services, that's on you. Audit yours anytime: `jq '.hooks' ~/.claude/settings.json`.

### What this toolkit explicitly does NOT do

- ❌ Loop-call Claude to inflate or game usage stats
- ❌ Read, copy, or share your OAuth tokens / API keys
- ❌ Scrape undocumented endpoints or web UIs
- ❌ Phone home with anonymized usage data (or any data at all)
- ❌ Modify Claude Code's binary or inject code into its runtime

### Pause everything without uninstalling

Add to `~/.claude/settings.json`:

```json
{ "disableAllHooks": true }
```

Aliases stay (so `cc-status` etc. still work read-only on the existing data) but no new events get appended. Remove the line to re-enable.

### What I'm NOT 100% certain about

I haven't read every line of Anthropic's full ToS and can't promise some clause doesn't apply in some unusual interpretation. The reasoning above is based on what the toolkit *does* (zero network, local-files-only, official APIs only) being clearly orthogonal to the kinds of behaviors platforms typically police (credential theft, API abuse, scraping, fake usage). If you want full reassurance, the safe move is to email Anthropic support and link this README — happy to amend based on any feedback.

---

## Caveats

- **Tested on macOS / zsh**; should work on Linux (BSD/GNU `stat` auto-detected) but not yet verified.
- **Plan defaults drift**. `cc-limits` ships with 5h-cap defaults verified 2026-05-07. Anthropic adjusts these — override with `CC_PLAN_MSG_LIMIT_5H` when they do.
- **Weekly rate-limit cap is not yet modeled**. Anthropic enforces a separate 7-day rolling cap; `cc-limits` only shows the 5h window.

---

## Who is this for?

Solo full-stack AI developers running multiple Claude Code sessions in parallel. Whatever you call yourself — **OPC**, **Solo Founder**, **Solo Builder**, **Indie Hacker**, **Vibe Coder** — same toolset, same problem.

When you're alone with Claude Code as your engineering leverage, observability matters more than in team environments. This toolkit replaces "where were we?" with a dashboard.

---

## Contributing

PRs welcome. The bar is *"would I install this in my own `~/.claude/` tomorrow?"* — pragmatic over polished, opinionated over comprehensive. Bug reports and questions equally welcome.

**Language policy** — keep things English by default:

- All code, shell comments, error/help messages, and docs → English
- `README.zh-CN.md` is the only translated document; keep its structure aligned 1:1 with `README.md` so future updates can mirror cleanly
- `statuslines/bilingual-cn.sh` is the only script whose **rendered output** is intentionally Chinese (its source comments stay English)
- The `alt="中文"` text inside the language-switcher badge stays as-is — it's the visible label readers click to flip languages

---

## License

[MIT](./LICENSE) — use it, fork it, ship it.
