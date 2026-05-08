# `cc-pilot` —— Claude Code 权限管理

三个子命令，一个共同目标：**少点几次 "yes"，又不至于把破坏性操作的口子放开**。

> [English](./cc-pilot.md) · [回到 README](../README.zh-CN.md)

---

## 命令速查

```bash
cc-pilot suggest                  # 从历史批准记录推荐 allow 模式
cc-pilot safe                     # 用只读 profile 启动
cc-pilot dev                      # 用 safe + 构建 + 可回滚 git profile 启动
cc-pilot yolo                     # 用 --dangerously-skip-permissions 启动（启动前预检）
cc-pilot show <profile>           # 查看 profile 内容
cc-pilot list-profiles            # 列出可用 profile
```

三个命令都是 **session 级**的 —— 不修改你的全局配置，也不动现有的 settings。底层走的是官方 Claude Code 参数（`--allowed-tools`、`--disallowed-tools`、`--dangerously-skip-permissions`）。

## `cc-pilot suggest`

每天点 50 次 "yes" 批准 `git status`、`npm test`、`ls -la` 是不是已经麻木了？`cc-pilot suggest` 扫描你的 transcript 历史，找出你**已经手动批准过 ≥ 5 次**的 Bash 模式，征得你同意后合并到 `~/.claude/settings.json` 的 `permissions.allow` 里。

```bash
cc-pilot suggest                  # 默认 7 天窗口，≥ 5 次出现
cc-pilot suggest --days 14        # 拓宽窗口
cc-pilot suggest --min-count 3    # 降低阈值
cc-pilot suggest -y               # 跳过合并确认
```

### 工作原理

1. 扫描时间窗口内所有 `~/.claude/projects/*/*.jsonl`，提取 Claude 实际跑过的每条 Bash 命令
2. 推导出权限模式（例：`git status -s` → `Bash(git status*)`）
3. 过滤掉**任何曾经在破坏性上下文中出现过**的模式（内置 deny list 子串匹配）：
   `rm -rf` · `git push --force` · `git reset --hard` · `git clean -f` · `git branch -D` · `git checkout .` · `sudo` · `chmod -R` · `chown -R` · `dd if=` · `mkfs` · `kill -9` · `killall` · `shutdown` · `reboot` · `format` · fork bomb · 重定向到 `/etc/`/`/usr/`/`/System/`/`/Library/`/`/bin/`/`/sbin/` · `curl ` · `wget ` · `nc ` · `<(curl ` · `<(wget `
4. 跳过只读类命令（**第一个 token** 在白名单里时，跳过子串 deny 检查），避免 `grep -n "rm -rf" *.sh` 这种**只是搜代码内容**的命令被误判。只读 verb 白名单：`grep find cat ls awk sed jq head tail wc sort uniq tr cut xargs echo printf pwd which type file du df env basename dirname stat tree column fold fmt nl tac tee read`
5. 跳过已经在 `permissions.allow` 里的模式
6. 三段输出：✅ 推荐 · ℹ️ 已存在 · 🚫 被拦截（**附触发拦截的具体命令**）
7. 合并前问 `[y/N]`，先备份 `settings.json` 到 `settings.json.before-cc-pilot-<时间戳>`

### 输出示例

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

**模式被拦截**时，"triggered by" 那行告诉你**为什么** —— 你可以据此手动调整。比如 `Bash(git add*)` 因为某条带 force-push 的复合命令被拦了，你可以改成更精确的 `Bash(git add)` 或 `Bash(git add .)`，避免一条危险的复合命令污染整条规则。

## `cc-pilot safe` / `dev` / `yolo`

用预先配置好的权限 profile 启动 Claude Code。三档风险：

| Profile | 允许 | 禁止 | 风险 |
|---------|------|------|------|
| `safe` | Read/Glob/Grep + 只读 Bash（`ls`、`cat`、`grep`、`find`、`awk`、只读 `git` 等）| （无 —— 纯加白）| 🟢 几乎为零 |
| `dev` | safe 全部 + `Edit`/`Write` + 构建测试工具（`npm`、`pnpm`、`yarn`、`cargo`、`go test`、`pytest`、`make`、`mvn`、`dotnet` 等）+ 可回滚 git（`add`、`commit`、`stash`、`pull`、`fetch`、普通 `push`）| force-push、hard reset、`rm -rf`、`sudo`、curl-piped-to-shell、`chmod -R` | 🟡 中 —— git 回滚能覆盖大部分损害 |
| `yolo` | 一切（`bypassPermissions = true`）| （无）| 🔴 高 —— **仅在 worktree / 容器中用** |

```bash
cc-pilot safe                     # safe profile 启动
cc-pilot dev "fix the bug"        # dev profile 启动 + 初始 prompt
cc-pilot yolo                     # 完全 bypass（启动前预检）
```

### `safe` profile

41 条 allow 规则，全部只读。`cc-pilot show safe` 查看 —— 文件在 [`pilot/profiles/safe.allow`](../pilot/profiles/safe.allow)。

适合场景：
- 让 Claude 调研代码库但不动它
- 你的终端短暂给别人用
- 心里没底，想要最大保护

### `dev` profile

116 条 allow 规则覆盖多个语言生态，23 条显式 deny。文件在 [`pilot/profiles/dev.allow`](../pilot/profiles/dev.allow) 和 [`pilot/profiles/dev.deny`](../pilot/profiles/dev.deny)。

包含：
- safe 全部
- `Edit` 和 `Write`（文件写入）
- 构建/测试/开发循环：`npm` · `npx` · `pnpm` · `yarn` · `bun` · `node` · `deno` · `python(3)` · `pip` · `uv` · `pytest` · `ruff` · `black` · `mypy` · `go`（test/build/run/vet/fmt）· `cargo`（build/test/run/check/clippy/fmt）· `rustc` · `make` · `cmake` · `ruby` · `bundle` · `gem` · `rspec` · `elixir` · `mix` · `swift` · `xcodebuild` · `gradle` · `mvn` · `java` · `javac` · `dotnet`
- 可回滚 git：`git add`、`git commit`、`git stash`、`git checkout <branch>`、`git pull`、`git fetch`、`git merge`、`git rebase`、普通 `git push`（不带 `--force`）、`git tag`、`git restore`、`git reflog`
- GitHub CLI 只读 + 安全写入：`gh repo view`、`gh pr list`、`gh pr view`、`gh pr diff`、`gh issue list`、`gh api`

排除：
- Force-push（`git push --force`、`git push -f`、`git push --force-with-lease`）
- Hard reset / clean（`git reset --hard`、`git clean -fd`、`git branch -D`）
- 特权操作（`sudo`、`chmod -R`、`chown`）
- 网络执行模式（`curl|sh`、`wget|sh`）
- 磁盘操作（`dd`、`mkfs`）

### `yolo` profile

`yolo` 不用 profile 文件 —— 直接给 claude 传 `--dangerously-skip-permissions`。**任一前置条件不满足就拒启动**：

1. ✅ 在 git 仓库里（这样可以 `git reset --hard` 回滚）
2. ✅ 工作树干净（无未提交修改）
3. ✅ 当前分支**不是**：`main` / `master` / `develop` / `prod` / `production` / `release` / `stable`

任一条件失败，`cc-pilot yolo` 立即退出并打印具体原因。强行越过：

```bash
cc-pilot yolo --i-understand-the-risk
```

这个 flag **每次都要手打** —— 没有环境变量、也没有配置文件能让它变成默认行为。强制你每次都做出明确的决定。

预检通过后会有确认提示，明确显示分支、HEAD、回滚命令：

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

## Profile 文件格式

Profile 是 [`pilot/profiles/`](../pilot/profiles/) 下的纯文本文件。每行一条 [Claude Code 权限规则](https://docs.claude.com/en/docs/claude-code/iam)，`#` 是注释，空行 OK。

示例（`pilot/profiles/safe.allow`）：

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

**扩展现有 profile**：直接编辑文件并 PR。常见添加：
- 新语言生态加进 `dev.allow`（例：`Bash(elixir *)`、`Bash(mix *)`）
- 组织特定的破坏性命令加进 `dev.deny`

**新建 profile**（例：`data-science`）：在 `pilot/profiles/` 下新建 `data-science.allow`，再可选地配一个 `data-science.deny`。`cc-pilot list-profiles` 会自动识别 —— 不需要改 shell 代码。

## 与其他工具的配合

| 工具 | 做什么 | 何时用 |
|------|--------|--------|
| `cc-pilot suggest` | 永久修改 `~/.claude/settings.json`（你确认 y 之后才会改）| 每周跑一次，把稳定的常用模式从习惯里挑出来 |
| `cc-pilot safe/dev/yolo` | Session 级，不持久化 | 单次任务调整信任档位 |

典型工作流：
1. 每周 `cc-pilot suggest` 一次 → 让 `permissions.allow` 跟你的实际习惯对齐
2. 敏感工作：`cc-pilot safe` 启动
3. 日常开发：直接 `claude`（用你累积的 allow 规则 + Claude Code 默认行为）
4. Yolo 实验：`cc-pilot yolo` 在一个 throwaway 分支里跑

## 安全保证

- 三个子命令都**只用官方 Claude Code 参数**（`--allowed-tools`、`--disallowed-tools`、`--dangerously-skip-permissions`）
- `suggest` **永远不会**把任何曾在破坏性上下文中出现过的模式添加到 allow list，即使加了 `-y` 也不行
- `yolo` **每次都要求**安全预检通过，或者显式加上 `--i-understand-the-risk`（没有任何环境变量或配置文件能让它默认）
- Profile 文件就是纯文本 —— 你看到啥，就是 claude 收到啥

更宽泛的威胁模型见主 README 的 [How it works & safety / 工作机制 & 安全性](../README.zh-CN.md#工作机制--安全性) 章节。
