# Contributing to claude-code-opc-toolkit

Thanks for considering a contribution! This is a personal workshop turned public — the bar is *"would I install this in my own `~/.claude/` tomorrow?"*. Pragmatic over polished, opinionated over comprehensive.

## Quick rules

- **Language**: code, comments, error/help messages, English README → **English**. The Chinese README (`README.zh-CN.md`) is the only translated file. The bilingual-cn statusline's *output* is intentionally Chinese.
- **No new network calls**: the toolkit stays local-files-only. The one exception (`cc-daily --export notion`) is documented and opt-in.
- **No new credential access**: don't read OAuth tokens, keychain entries, or API keys. User-provided env vars (e.g., `NOTION_API_KEY`) are fine.
- **Conservative by default**: any tool that adds permissions or runs commands must show what it's doing and ask `[y/N]` before applying.
- **Pass `bash -n`**: every shell script must parse cleanly. CI will check.

## Repo layout

```
monitor/          Read-only observability tools (cc-status, cc-limits, cc-daily, …)
pilot/            Permission-rule helpers (cc-pilot suggest/safe/dev/yolo)
pilot/profiles/   Plain-text profiles, one rule per line — easy to extend
skills/           Skill scaffolding (cc-skill-init)
statuslines/      Plug-and-play statusLine scripts (sl-*)
banner.svg        README banner
install.sh        Idempotent symlink installer + alias appender
```

## Getting set up locally

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
source ~/.zshrc
```

After that, your local `~/.claude/monitor/`, `~/.claude/pilot/`, etc. are symlinked back to the cloned repo. **Edit a `.sh` file → next `cc-*` invocation runs the new code immediately.** No re-install needed for code changes.

## Common contribution shapes

### 1. Extending a `cc-pilot` profile

`pilot/profiles/safe.allow`, `dev.allow`, `dev.deny` are plain text — one [Claude Code permission rule](https://docs.claude.com/en/docs/claude-code/iam) per line, `#` lines are comments.

If your stack needs `Bash(elixir *)` auto-allowed, add it to `dev.allow` and PR. Add a brief comment if the addition isn't self-explanatory.

For new profiles entirely (e.g. `data-science.allow`), drop both files in `pilot/profiles/` and they'll show up under `cc-pilot list-profiles` automatically.

### 2. Adding a statusline

Create `statuslines/<name>.sh`. It receives Claude Code's stdin JSON (`.workspace.current_dir`, `.model.display_name`, `.context_window.used_percentage`, `.session_id`, …) and outputs **one short line**. Keep it under ~200ms — the script runs on every assistant turn.

Add a row to `statuslines/README.md` and a `sl-<name>` alias to `install.sh`. Update the EN + ZH READMEs' statusline gallery table.

### 3. New tool / subcommand

Aim for the same shape as existing tools:
- Single shell script, no compile step
- `--help` text near the top of the file (sed extracts it)
- `bash -n` clean
- Reads only local files; emits to stdout / writes to `~/.claude/<area>/`
- Idempotent — running twice has the same effect as once

Wire into `install.sh` (symlink + alias) and add a row to the EN + ZH READMEs' Tool List.

### 4. Bug reports

Use the GitHub issue template. The most useful bug reports include:
- The command you ran
- What you expected
- What you got
- Output of `bash --version`, `jq --version`, `claude --version` if relevant
- Whether `cc-status` / `cc-limits` was running cleanly *before* the bug

## Style

- Bash: lowercase function names, `local` for function-local variables, prefer `[ ]` over `[[ ]]` for portability when possible (we test on macOS bash 3.2 + recent bash; macOS is the primary target).
- jq: parameterize with `--arg` / `--argjson`, never interpolate user data into the program text.
- Readability > cleverness. If a one-liner needs a comment to explain it, prefer two lines that don't.
- One short comment per non-obvious section (`# Why`-comments, not `# What`-comments).

## Releasing

This project uses lightweight CalVer-ish tags (`v2026.05.08` style) when meaningful milestones land. Maintainer pushes the tag.

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/) — add an entry under `## [Unreleased]` in your PR.

## Code of conduct

Be kind, assume good intent, criticize the code not the person. We're all trying to ship.

## License

By submitting a PR you agree your contribution is licensed under [MIT](./LICENSE) — same as the rest of the repo.
