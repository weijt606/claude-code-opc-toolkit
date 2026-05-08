# `cc-pilot` — permission management for Claude Code

Three subcommands that share one goal: stop clicking "yes" on routine prompts without opening yourself up to destructive operations.

> [中文版](./cc-pilot.zh-CN.md) · [back to README](../README.md)

---

## Quick reference

```bash
cc-pilot suggest                  # learn from past approvals → recommend allow patterns
cc-pilot safe                     # launch with read-only profile
cc-pilot dev                      # launch with safe + builds + reversible git
cc-pilot yolo                     # launch with --dangerously-skip-permissions (preflight gated)
cc-pilot show <profile>           # print profile contents
cc-pilot list-profiles            # available profiles
```

All three are **session-scoped** — no global config mutation, no merge into your existing settings. They use the official Claude Code flags `--allowed-tools`, `--disallowed-tools`, and `--dangerously-skip-permissions`.

## `cc-pilot suggest`

Tired of clicking "yes" on the same `git status`, `npm test`, `ls -la` 50× a day? `cc-pilot suggest` reads your transcript history, finds Bash patterns you've manually approved repeatedly, and (with your consent) merges them into `~/.claude/settings.json`'s `permissions.allow`.

```bash
cc-pilot suggest                  # last 7d, ≥5 invocations, default
cc-pilot suggest --days 14        # widen the window
cc-pilot suggest --min-count 3    # lower the bar
cc-pilot suggest -y               # skip the merge confirmation
```

### What it does

1. Walks `~/.claude/projects/*/*.jsonl` in the time window, extracts every Bash command Claude actually ran
2. Derives a permission pattern (e.g. `git status -s` → `Bash(git status*)`)
3. Filters out patterns where ANY invocation matched a built-in destructive deny list:
   `rm -rf` · `git push --force` · `git reset --hard` · `git clean -f` · `git branch -D` · `git checkout .` · `sudo` · `chmod -R` · `chown -R` · `dd if=` · `mkfs` · `kill -9` · `killall` · `shutdown` · `reboot` · `format` · fork bombs · redirects to `/etc/`/`/usr/`/`/System/`/`/Library/`/`/bin/`/`/sbin/` · `curl ` · `wget ` · `nc ` · `<(curl ` · `<(wget `
4. Skips substring-match deny check when the **first token** is a read-only inspector — so `grep -n "rm -rf" *.sh` isn't false-positive flagged for the data it reads. Read-only verbs: `grep find cat ls awk sed jq head tail wc sort uniq tr cut xargs echo printf pwd which type file du df env basename dirname stat tree column fold fmt nl tac tee read`
5. Drops patterns already in your `permissions.allow`
6. Renders three sections (with the **exact triggering command** shown for blocked entries)
7. Asks `[y/N]` before merging — backs up `settings.json` first to `settings.json.before-cc-pilot-<timestamp>`

### Sample output

```
✅ Recommended (safe, ≥5 invocations, not yet allowed)
    133×  Bash(grep -n*)
    102×  Bash(pnpm --filter*)
     57×  Bash(git status*)
     ...

ℹ️ Already in permissions.allow (no action needed)
  (none)

🚫 Blocked from auto-suggesting (at least one invocation matched the destructive deny list)
    112×  Bash(git add*)
         triggered by: git add . && git push --force origin main
     25×  Bash(curl -s*)
         triggered by: curl -s https://api.github.com/repos/...
      5×  Bash(rm -rf*)
         triggered by: rm -rf /tmp/scratch && ls

Add these 39 pattern(s) to ~/.claude/settings.json [permissions.allow]? [y/N]
```

When a pattern is **blocked**, the "triggered by" line tells you why so you can manually refine. For example, if `Bash(git add*)` is blocked because of one compound force-push command, you might add the safer `Bash(git add)` or `Bash(git add .)` exact patterns instead.

## `cc-pilot safe` / `dev` / `yolo`

Launch Claude Code with a permission profile pre-applied to the session. Three risk tiers:

| Profile | Allows | Denies | Risk |
|---------|--------|--------|------|
| `safe` | Read/Glob/Grep + read-only Bash (`ls`, `cat`, `grep`, `find`, `awk`, read-only `git`, etc.) | (nothing — pure additive) | 🟢 nearly zero |
| `dev` | Everything in safe + `Edit`/`Write` + build & test runners (`npm`, `pnpm`, `yarn`, `cargo`, `go test`, `pytest`, `make`, `mvn`, `dotnet`, …) + reversible git (`add`, `commit`, `stash`, `pull`, `fetch`, plain `push`) | force-push, hard-reset, `rm -rf`, `sudo`, curl-piped-to-shell, `chmod -R` | 🟡 medium — git rollback covers most damage |
| `yolo` | Everything (`bypassPermissions = true`) | (nothing) | 🔴 high — only inside a worktree / container |

```bash
cc-pilot safe                     # launch with safe profile
cc-pilot dev "fix the bug"        # launch with dev profile + initial prompt
cc-pilot yolo                     # launch with full bypass (preflight gated)
```

### `safe` profile

41 allow patterns, all read-only. View with `cc-pilot show safe` — they live in [`pilot/profiles/safe.allow`](../pilot/profiles/safe.allow).

Use this when:
- You want Claude to investigate a codebase without ever touching it
- You're letting someone else use your terminal briefly
- You're nervous and want maximum guardrails

### `dev` profile

116 allow patterns across multiple language ecosystems, 23 explicit deny patterns. Profile lives in [`pilot/profiles/dev.allow`](../pilot/profiles/dev.allow) and [`pilot/profiles/dev.deny`](../pilot/profiles/dev.deny).

Includes:
- Everything in `safe`
- `Edit` and `Write` (file mutations)
- Build/test/dev-loop verbs: `npm` · `npx` · `pnpm` · `yarn` · `bun` · `node` · `deno` · `python(3)` · `pip` · `uv` · `pytest` · `ruff` · `black` · `mypy` · `go` (test/build/run/vet/fmt) · `cargo` (build/test/run/check/clippy/fmt) · `rustc` · `make` · `cmake` · `ruby` · `bundle` · `gem` · `rspec` · `elixir` · `mix` · `swift` · `xcodebuild` · `gradle` · `mvn` · `java` · `javac` · `dotnet`
- Reversible git: `git add`, `git commit`, `git stash`, `git checkout <branch>`, `git pull`, `git fetch`, `git merge`, `git rebase`, plain `git push` (without `--force`), `git tag`, `git restore`, `git reflog`
- GitHub CLI read + safe mutations: `gh repo view`, `gh pr list`, `gh pr view`, `gh pr diff`, `gh issue list`, `gh api`

Excludes:
- Force-push (`git push --force`, `git push -f`, `git push --force-with-lease`)
- Hard reset / clean (`git reset --hard`, `git clean -fd`, `git branch -D`)
- Privileged ops (`sudo`, `chmod -R`, `chown`)
- Network exec patterns (`curl|sh`, `wget|sh`)
- Disk ops (`dd`, `mkfs`)

### `yolo` profile

`yolo` doesn't use a profile file — it passes `--dangerously-skip-permissions` directly to claude. It refuses to start unless **all** preconditions are met:

1. ✅ Inside a git repo (so you can recover via `git reset --hard`)
2. ✅ Working tree is clean (no uncommitted changes)
3. ✅ Current branch is **not** in: `main`, `master`, `develop`, `prod`, `production`, `release`, `stable`

If any precondition fails, `cc-pilot yolo` exits with the exact reason. To override:

```bash
cc-pilot yolo --i-understand-the-risk
```

That flag is **per-invocation** — no way to make it default. Forces a deliberate decision every time.

When all preconditions pass, you get a confirmation prompt showing your branch, HEAD, and the recovery command:

```
═══════════════════════════════════════════════════════════════════
   cc-pilot yolo — about to launch Claude with NO permission checks
═══════════════════════════════════════════════════════════════════

  Branch:    yolo-20260508-143052
  HEAD:      a1b2c3d
  Worktree:  clean ✓
  Recovery:  git reset --hard a1b2c3d

  Claude can run any shell command without asking. This is intended for
  short, sandboxed work in throwaway worktrees / containers.

Proceed? [y/N]
```

## Profile file format

Profiles are plain text under [`pilot/profiles/`](../pilot/profiles/). One [Claude Code permission rule](https://docs.claude.com/en/docs/claude-code/iam) per line, `#` for comments, blank lines OK.

Example (`pilot/profiles/safe.allow`):

```
# Built-in read-only tools
Read
Glob
Grep

# Read-only Bash inspectors
Bash(ls*)
Bash(cat *)
Bash(head *)
...
```

To **extend a profile**: just edit the file and PR. Common additions:
- New language ecosystem to `dev.allow` (e.g. `Bash(elixir *)`, `Bash(mix *)`)
- New explicit deny to `dev.deny` (e.g. an organization-specific destructive command)

To **add a new profile** (e.g. `data-science`): drop both `pilot/profiles/data-science.allow` and (optional) `pilot/profiles/data-science.deny` files. They'll appear in `cc-pilot list-profiles` automatically — no shell changes needed.

## How it composes with other tools

| Tool | What it does | When to use |
|------|--------------|-------------|
| `cc-pilot suggest` | Mutates `~/.claude/settings.json` permanently (after y/N) | Once a week to harvest stable patterns from your routine |
| `cc-pilot safe/dev/yolo` | Session-scoped, no persistent change | Per-session, when you want to dial trust up or down for a specific task |

A common workflow:
1. Run `cc-pilot suggest` weekly → drift your `permissions.allow` toward your actual habits
2. For sensitive work: launch with `cc-pilot safe`
3. For daily building: just `claude` (your accumulated allow rules + Claude Code's defaults)
4. For yolo experiments: `cc-pilot yolo` in a throwaway branch

## Safety summary

- All three subcommands use **only official Claude Code flags** (`--allowed-tools`, `--disallowed-tools`, `--dangerously-skip-permissions`).
- `suggest` will **never** add a pattern that ever appeared in a destructive context, even with `-y`.
- `yolo` **always** requires the safety preconditions OR the explicit `--i-understand-the-risk` flag (no env var, no config file — must type it).
- Profile files are plain text — what you see is what gets passed to claude.

See the [How it works & safety](../README.md#how-it-works--safety) section of the main README for the broader threat model.
