# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [CalVer](https://calver.org/) (`vYYYY.MM.DD`) for releases.

## [Unreleased]

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
- Bilingual READMEs (English + 中文), MIT license.
