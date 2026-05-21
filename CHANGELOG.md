# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [CalVer](https://calver.org/) (`vYYYY.MM.DD`) for releases.

## [Unreleased]

### Changed — `cc-limits` repositioned as complement to Claude Code's `/usage`

Claude Code shipped a built-in [`/usage`](https://code.claude.com/docs/en/costs#using-the-usage-command) slash command that returns the **authoritative** current 5h plan-usage bar (server-side truth, not local approximation). `cc-limits` now positions itself explicitly as a complement, not a competitor:

- **`/usage` owns**: current 5h quota %, real reset countdown.
- **`cc-limits` owns**: cross-project / cross-pid live processes, arbitrary historical windows (-30m / -1h / -7d / -30d), cost in custom windows, per-model breakdown across many sessions, top-sessions ranking, watch mode, statusline integration.

User-facing changes:

- **Plan-budget block label**: `⚠ estimated, not authoritative` → `⚠ local approximation — run /usage in Claude Code for authoritative %`. Calibrated rows now say `✓ calibrated (still local; /usage is the truth source)`.
- **New footer hint** on every `cc-limits` run: tells users to run `/usage` inside Claude Code for the authoritative reading.
- **Calibration demoted from "recommended setup" to "optional"**. Since `/usage` now exists, calibration is only worth doing if you want a continuously displayed % in `cc-limits --watch` or in the `sl-cost` statusline. One-off readings should just use `/usage`. README, both docs/cc-limits.md (EN + ZH), and the `--calibrate` post-success message updated accordingly.
- **README "Tools" table** rewords the `cc-limits` description to lead with cross-project history / watch / statusline integration and explicitly defer current-quota authority to `/usage`.
- **Caveat** added in both READMEs and both docs/cc-limits files: prefer `/usage` for authoritative current-window %; cc-limits' approximation is for continuous display, not ground truth.

No behavioral changes to the math — `cc-limits` still aggregates the same local-only data the same way. The change is purely positioning + labeling so users aren't misled into trusting cc-limits' local % over `/usage`'s server-side reading.

### Fixed — `cc-limits --calibrate` baseline mismatch

- `--calibrate <pct>` was counting messages from the **original day-anchor** instead of the **current tumbling-window start**, so on a 3rd-window-of-the-day it summed up to 15h of requests instead of just the current ≤5h block. The resulting `cap = count / (pct/100)` was inflated 2-3×, and the live `Plan budget` block (which correctly counts only the current window) then displayed ~25% when the dashboard said 55%. Calibration now uses the same `anchor_ts() + window_n` math as `plan_block()` — `observed count` and the displayed `Usage` numerator are now from the same source.

### Changed — `cc-limits` accuracy

- **Tumbling 5-hour windows** replace gap-detected rolling windows. Anthropic's metering uses tumbling blocks anchored at first-request-of-day (window N = `[anchor + 5N·h, anchor + 5(N+1)·h]`), not a rolling 5h that resets after a 30-minute lunch. New `anchor_ts()` looks back 24h for the first request after a ≥5h gap; `plan_block()` then computes the current tumbling block and counts only messages within it. Reset countdown now matches `claude.ai/settings/usage` within ~2 minutes (down from ~1h 35m off). Tunables: `CC_SESSION_GAP_MIN=300`, `CC_ANCHOR_LOOKBACK_HOURS=24`.
- **Calibration is now the recommended setup, not a fallback.** README and `docs/cc-limits.md` (EN + ZH) now lead with the `export CC_PLAN=max5` + `cc-limits --calibrate <pct>` flow. Static plan caps are token-weighted by Anthropic and drift; `--calibrate` is the only way to pin local % to dashboard reality.

## [v2026.05.08] — 2026-05-08

### Added — `cc-pilot` (Phase B + C)

- `cc-pilot suggest`: scans transcripts (default 7d), extracts Bash invocations, derives `Bash(prefix*)` permission patterns, filters out destructive contexts (`rm -rf`, `git push --force`, `sudo`, `curl `, …), shows recommended / already-allowed / blocked sections with the exact triggering command for blocked entries. Optional `--days N`, `--min-count N`, `-y` to skip confirmation. Backs up `settings.json` before merging.
- `cc-pilot safe` / `dev` / `yolo`: profile-based session launchers. Each profile is a plain-text file under `pilot/profiles/` (one rule per line, `#` comments).
  - **safe**: 41 read-only patterns (Read/Glob/Grep + `ls`/`cat`/`grep`/`find`/read-only git).
  - **dev**: 116 allow patterns (safe + Edit/Write + builds/tests + reversible git) and 23 deny patterns (force-push, hard-reset, `rm -rf`, `sudo`, curl-piped-to-shell).
  - **yolo**: passes `--dangerously-skip-permissions` after enforcing preflight (must be in a git repo, working tree clean, branch not in `main|master|develop|prod|production|release|stable`). Override with `--i-understand-the-risk`.
- `cc-pilot show <profile>` and `cc-pilot list-profiles` for inspecting profile contents.

### Changed — `cc-limits`

- **Token / cost dedupe by `requestId`**: previously summed token usage across every JSONL entry, but Claude Code copies per-request totals onto every entry within that request. Costs were inflated 2–15× depending on tool-call density. Now correctly counts each unique `requestId` once. Verified against `claude.ai/settings/usage`: tool-reported "Plan budget" now matches dashboard within ±3%.
- **Session-anchored "Current session"**: previously used a pure rolling 5h window for the plan budget. Anthropic actually anchors session-start at the first request after a quiet period. New `session_start_ts()` helper detects gaps ≥ `CC_SESSION_GAP_MIN` minutes (default 30). Reset countdown now matches the dashboard within ~6 minutes (UI-rounding territory).
- **`--calibrate <pct>` / `--calibrate-clear`**: anchor the budget % to your actual `claude.ai/settings/usage` reading. Tool back-computes the effective cap from your current session count and saves it to `~/.claude/monitor/cc-plan.conf`. Future runs use the calibrated cap, marked `✓ calibrated`.
- **Window shorthand**: `cc-limits -30m | -1h | -7d | -30d | --last 6h`. Default window is now last 24 hours.

### Changed — `cc-status`

- **Prompt counts now read from transcripts, not the hook log**, so `Your prompt count, by project` reflects real 7-day history regardless of when hooks were installed.
- **Subagents Finished**: now shows the project (cwd basename), aligned columns, and a legend explaining `?` (Claude Code's `SubagentStop` payload only fills `agent_type` for explicit `Task(subagent_type=…)` calls).

### Added — open-source readiness

- `CONTRIBUTING.md`, `CHANGELOG.md`, `.github/` issue / PR templates.
- GitHub Actions workflow: `bash -n` syntax check on every PR.
- Banner SVG, lean README, language policy section, fzf/jq/JSONL/cwd glossary.

## [v2026.05.07] — initial public release

### Added

- `cc-status`, `cc-watch`, `cc-resume`, `cc-tail`: cross-project session dashboard, live mode, fzf-driven resume picker, hook-event tail.
- `cc-limits`: token usage + estimated cost (Opus 4 defaults; per-call price overrides via `CC_PRICE_*`).
- `cc-daily`: per-project `daily-worklog.md` writer with optional Obsidian / Notion export.
- `cc-skill-init <name>`: scaffold Claude Code skills with frontmatter, Step-0 read-context block, README, prompts, templates/examples dirs.
- 7 plug-and-play `statusLine` scripts (default-opc, cost-watch, session-density, pomodoro, minimal, build-in-public, bilingual-cn) with `sl-*` swap aliases.
- 4 hook events wired into `~/.claude/monitor/events.jsonl`: `SessionStart` / `SessionEnd` / `UserPromptSubmit` / `SubagentStop`.
- Bilingual READMEs (English + Chinese), MIT license.
