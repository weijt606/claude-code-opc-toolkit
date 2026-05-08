# `cc-limits` — token usage & cost monitor

Cross-project Claude Code usage monitor. Aggregates from your local transcript files (`~/.claude/projects/*/*.jsonl`) — zero network calls, zero credential reads.

> [中文版](./cc-limits.zh-CN.md) · [back to README](../README.md)

---

## Recommended setup (do this once)

The plan budget block is most useful when calibrated to your real `claude.ai/settings/usage` reading. Anthropic's metering is token-weighted and opaque, so static defaults drift; calibration anchors the local `% used` to the dashboard.

```bash
# 1. Set your plan once (add to ~/.zshrc to make it persistent)
export CC_PLAN=max5                  # one of: pro | max5 | max20 | team | free | api

# 2. Open claude.ai/settings/usage, note the "Current session" %
# 3. Calibrate IMMEDIATELY (the longer you wait the staler the snapshot):
cc-limits --calibrate 40             # whatever % the dashboard showed
```

This writes the calibrated cap to `~/.claude/monitor/cc-plan.conf`. From then on, `cc-limits` shows budget % within ±5 pp of the dashboard. Re-calibrate when you notice drift; clear with `--calibrate-clear`.

> If you skip calibration, the tool falls back to Anthropic's published per-plan caps. Those defaults are a rough guide but **will drift** because Anthropic's metering accounts for request size and complexity in ways we can't replicate locally.

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

Set `CC_PLAN` (or pass `--plan`) to see estimated 5-hour session budget %, burn rate, and reset countdown:

```bash
export CC_PLAN=max5       # or: pro | max5 | max20 | team | free | api
cc-limits

# Adds a "🎯 Plan budget" block:
#
#     Claude Max 5× ($100/mo)  (CC_PLAN=max5 · cap default)   ⚠ estimated, not authoritative
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

- **No internal counter exposed**. Claude Code's actual rate-limit state is server-side; `cc-limits` is an aggregation proxy.
- **Token-weighted metering is opaque**. Anthropic weights big-context / heavy-output requests differently. `--calibrate` is the only way to pin local % to the dashboard.
- **Weekly cap not yet modeled**. Anthropic enforces a separate 7-day rolling cap that this tool doesn't track. See `claude.ai/settings/usage` for the truth.
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
