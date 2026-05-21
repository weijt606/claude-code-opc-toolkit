# `cc-limits` — token usage & cost monitor

Cross-project Claude Code usage monitor. Aggregates from your local transcript files (`~/.claude/projects/*/*.jsonl`) — zero network calls, zero credential reads.

> [中文版](./cc-limits.zh-CN.md) · [back to README](../README.md)

---

## Relationship to `/usage`

Claude Code ships a built-in [`/usage` slash command](https://code.claude.com/docs/en/costs#using-the-usage-command). For Pro/Max/Team subscribers, `/usage` shows the **authoritative current 5h plan-usage bar** straight from Anthropic's server. **For "what % am I right now?" — run `/usage` inside Claude Code; that's the ground truth.**

### What `/usage` shows

Type `/usage` in any Claude Code session. Output looks roughly like (per [official docs](https://code.claude.com/docs/en/costs#using-the-usage-command)):

```
Total cost:            $0.55
Total duration (API):  6m 19.7s
Total duration (wall): 6h 33m 10.2s
Total code changes:    0 lines added, 0 lines removed
```

Plus, depending on account type:

- **Pro / Max / Team subscribers** also see **plan-usage bars and activity stats** on the same screen — this is the authoritative 5h-window reading and reset countdown sourced directly from Anthropic's server.
- **API users** see the Session block (token + cost). Note: the `Total cost` figure is *also* a local estimate computed from token counts — same caveat as cc-limits' cost line. For authoritative API billing, see [Claude Console → Usage](https://platform.claude.com/usage).

`/usage` runs interactively only — there's no documented CLI / JSON / file-output form, so it can't drive a statusline or a watch loop.

### Where each tool wins

`cc-limits` is a complement, not a replacement. It does what `/usage` doesn't:

| Question | Best tool |
|----------|-----------|
| What % of my 5h quota am I at *right now*? | **`/usage`** (server-authoritative, subscribers only) |
| What did the last 7 / 30 days cost me? | **`cc-limits -7d` / `-30d`** |
| Which sessions burned the most output? | **`cc-limits` (Top sessions block)** |
| What live Claude Code processes are running across all my projects? | **`cc-limits` (🔥 block)** |
| Continuous dashboard while I code (auto-refresh) | **`cc-limits --watch`** |
| Per-model breakdown across many sessions | **`cc-limits`** |
| Persistent statusline showing token spend | **`sl-cost`** (this toolkit) |

`/usage` is interactive and session-scoped; `cc-limits` is scriptable, historical, and cross-project.

---

## Quick start

```bash
cc-limits                          # default: last 24 hours
cc-limits -7d                      # last 7 days
cc-limits --watch                  # auto-refresh dashboard
```

Optional plan budget block — only useful for statusline / watch-mode display (since one-off authoritative reads should just use `/usage`):

```bash
export CC_PLAN=max5                # pro | max5 | max20 | team | free | api
cc-limits                          # now includes a 🎯 Plan budget block
```

## Optional: calibration (mostly for statusline use)

Since `/usage` exists, **you don't need to calibrate for one-off readings — just run `/usage`**. Calibration is useful only if you want the plan-budget block in `cc-limits --watch` or in `sl-cost` statusline to match the dashboard within ±5pp continuously.

```bash
# 1. Open claude.ai/settings/usage (or run /usage in Claude Code), note the %
# 2. Within a minute or two:
cc-limits --calibrate 40           # whatever % was shown

# Revert anytime:
cc-limits --calibrate-clear
```

The calibrated cap is saved to `~/.claude/monitor/cc-plan.conf`. Anthropic's metering is token-weighted and opaque, so the static per-plan defaults drift — calibration anchors the local estimate to your account's actual weighting. Re-run when drift becomes noticeable.

## Daily reference

```bash
cc-limits                          # default: last 24 hours
cc-limits -30m                     # last 30 minutes
cc-limits -1h                      # last 1 hour
cc-limits -7d                      # last 7 days
cc-limits -30d                     # last 30 days
cc-limits --last 6h                # long form (same as -6h)
cc-limits --days 30                # legacy spelling for -30d
cc-limits -7d --watch              # auto-refresh
cc-limits --calibrate-clear        # revert to plan defaults
```

Window units supported: **`m`** (minutes) · **`h`** (hours) · **`d`** (days) · **`w`** (weeks). Default window if no flag is given: **last 24 hours**.

## Output sections

Every run shows the same blocks (the requested window changes which numbers populate them):

```
🔥  Live processes              ← always: PID, ctx size, busy/idle, cwd
⚡  Last <window>                ← input/output/cache tokens + per-model + est cost
🎯  Plan budget                  ← only when CC_PLAN is set; always 5h-anchored
🏆  Top sessions by output       ← top 5 sessions in <window>
```

The plan budget block is **always anchored to the 5-hour rate-limit window**, regardless of which window you queried. So `cc-limits -30d --plan max5` simultaneously answers two questions: "how much did I burn in the last 30 days?" and "where am I right now on the rolling 5h limit?".

## Pricing override

Defaults assume Claude Opus 4 series (input $15 / output $75 / cache write $18.75 / cache read $1.50 per 1M tokens). Override per-call:

```bash
# Sonnet 4
CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 CC_PRICE_CACHE_WRITE=3.75 CC_PRICE_CACHE_READ=0.30 cc-limits

# Haiku 4
CC_PRICE_INPUT=1 CC_PRICE_OUTPUT=5  CC_PRICE_CACHE_WRITE=1.25 CC_PRICE_CACHE_READ=0.10 cc-limits
```

Set them in `~/.zshrc` for persistent override.

> Claude Code does not expose its internal rate-limit counter, and Anthropic's quota meter is **token-weighted by request size/complexity**, so a static `count ÷ cap` estimate drifts. The cost line shows what the same workload would cost at API rates — useful as a "value extracted" indicator, not a real bill.

## Plan-aware budget

> Reminder: for an authoritative one-off reading, run `/usage` in Claude Code. The block below is a local approximation, mostly useful when you want continuous display in `--watch` or a statusline.

Set `CC_PLAN` (or pass `--plan`) to see estimated 5-hour session budget %, burn rate, and reset countdown:

```bash
export CC_PLAN=max5       # or: pro | max5 | max20 | team | free | api
cc-limits

# Adds a "🎯 Plan budget" block:
#
#     Claude Max 5× ($100/mo)  (CC_PLAN=max5 · cap default)   ⚠ local approximation — run /usage in Claude Code for authoritative %
#     Usage:    216 / ~450 msgs   ████████░░░░░░  48%
#     Burn:     127 msg/hr  →  exhaust in ~1h 50m
#     Resets:   in 3h 10m  (5h after session-start)
```

Defaults (verified **2026-05-08**, reflecting Anthropic's 2026-05-06 announcement that Claude Code 5h limits **doubled** for all paid tiers):

| Plan | 5h cap | Source flag |
|------|--------|------------|
| Free | ~10 | `--plan free` |
| Pro | ~90 | `--plan pro` |
| Max 5× ($100/mo) | ~450 | `--plan max5` (or `--plan max`) |
| Max 20× ($200/mo) | ~1800 | `--plan max20` |
| Team (per seat) | ~450 | `--plan team` |
| API | no cap | `--plan api` |

Override the cap when Anthropic adjusts published quotas:

```bash
export CC_PLAN_MSG_LIMIT_5H=2000
# or per-call:
cc-limits --plan max20 --quota 2000
```

### Tumbling 5-hour windows (how anchoring really works)

Anthropic doesn't use a rolling 5h window or gap-based detection inside it. They use **tumbling 5-hour blocks anchored at your first request of the day** (or first request after a multi-hour break). Window 1 = `[anchor, anchor+5h]`, window 2 = `[anchor+5h, anchor+10h]`, etc. Reset countdown = end of the current block.

`cc-limits` replicates this: it looks back **24 hours** of transcripts (`CC_ANCHOR_LOOKBACK_HOURS=24`), finds the first request after a gap of at least **5 hours** (`CC_SESSION_GAP_MIN=300` minutes — i.e., a fully-elapsed window of inactivity), and uses that as the anchor. Then it computes which 5h block you're currently in, and counts messages **within that block only**.

A 30-minute lunch break or even a 3-hour gap doesn't reset the anchor — only a full 5h+ break does. This matches Anthropic's `claude.ai/settings/usage` behavior empirically (verified 2026-05-09: tool's reset countdown matches dashboard within ~2 minutes).

Tunables (rarely needed):

```bash
export CC_SESSION_GAP_MIN=300         # default: 5h+ gap counts as a fresh anchor
export CC_ANCHOR_LOOKBACK_HOURS=24    # default: how far back to search for the original anchor
```

### Calibrating against your real dashboard reading

The plan defaults are best-effort guidance, but Anthropic's internal `% used` is **opaque-weighted by request size/complexity**, so a static estimate drifts. If `cc-limits --plan max5` says 45% but `claude.ai/settings/usage` says 60%, anchor the tool to your reality:

```bash
cc-limits --calibrate 60         # "I see 60% on the dashboard right now"
# → Computes effective cap from current request count
# → Saves to ~/.claude/monitor/cc-plan.conf
# → Future runs use the calibrated cap, marked "✓ calibrated"
```

Re-calibrate periodically when the underlying weight function drifts. Revert anytime:

```bash
cc-limits --calibrate-clear      # back to plan defaults
```

## How counts are computed

`.messages` and all token totals dedupe by `.requestId`:

> Claude Code writes one JSONL entry per content block (text, tool_use, thinking step…) but ALL entries from one API request share the same `.requestId` and carry **identical** `.message.usage` values. Summing raw entries inflates by 2–15× depending on tool-call density. `cc-limits` does `unique_by(.requestId)` before any aggregation, matching what Anthropic actually bills (one billable request per requestId).

Verified **2026-05-08**: 135 unique requestIds in a 5h window matches `claude.ai/settings/usage`'s 28% reading on a Max 5× plan within ±2 percentage points.

## Caveats

- **`/usage` is the authority for current 5h quota.** `cc-limits`' plan-budget block is a local approximation; for one-off accurate readings always prefer `/usage`. cc-limits owns history, cost, live processes, and continuous display.
- **Token-weighted metering is opaque**. Anthropic weights big-context / heavy-output requests differently. `--calibrate` reduces the gap if you want a continuously displayed % — but `/usage` removes the need entirely.
- **Weekly cap not yet modeled**. Anthropic enforces a separate 7-day rolling cap that this tool doesn't track. See `claude.ai/settings/usage` (or `/usage`) for the truth.
- **Pricing defaults drift**. Overrides update via `CC_PRICE_*` env vars — don't trust the cost line as a real bill.
- **macOS / zsh tested**; Linux should work (BSD/GNU `stat` auto-detected) but not yet verified.

## Watch mode

```bash
cc-limits -7d --watch             # default refresh: 30s
REFRESH_INTERVAL=5  cc-limits -1h --watch    # tighter polling
REFRESH_INTERVAL=120 cc-limits --watch       # set-and-forget on a side monitor
```

Ctrl-C exits cleanly and restores the cursor.

## Where the data lives

| Path | Purpose |
|------|---------|
| `~/.claude/projects/*/*.jsonl` | Claude Code's transcripts — primary data source |
| `~/.claude/sessions/<pid>.json` | Live process metadata (used for the 🔥 block) |
| `~/.claude/monitor/cc-plan.conf` | Saved calibration (created by `--calibrate`) |
| `~/.claude/monitor/events.jsonl` | Hook event log (used by `cc-status` / `cc-daily`, not `cc-limits`) |
