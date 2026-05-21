<p align="center">
  <img src="./banner.svg" alt="Claude-Code OPC Toolkit" width="100%" />
</p>

<p align="center">
  <a href="./README.md"><img src="https://img.shields.io/badge/lang-English-lightgrey?style=flat-square" alt="English"></a>
  <a href="./README.zh-CN.md"><img src="https://img.shields.io/badge/lang-%E4%B8%AD%E6%96%87-DC2626?style=flat-square" alt="中文"></a>
  &nbsp;·&nbsp;
  <a href="https://claude.com/claude-code"><img src="https://img.shields.io/badge/Claude%20Code-D97757?style=flat-square&logo=anthropic&logoColor=white" alt="Built for Claude Code"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/MIT-yellow?style=flat-square&label=license" alt="License: MIT"></a>
  &nbsp;·&nbsp;
  <a href="#工具"><img src="https://img.shields.io/badge/6-blue?style=flat-square&label=tools" alt="6 tools"></a>
  <a href="./statuslines/"><img src="https://img.shields.io/badge/7-7C3AED?style=flat-square&label=statuslines" alt="7 statuslines"></a>
  <a href="./settings.example.json"><img src="https://img.shields.io/badge/4-D97757?style=flat-square&label=hooks" alt="4 hooks"></a>
  <a href="https://github.com/weijt606/claude-code-opc-toolkit/stargazers"><img src="https://img.shields.io/github/stars/weijt606/claude-code-opc-toolkit?style=flat-square&color=FFCC00&label=%E2%98%85" alt="GitHub stars"></a>
</p>

> 为独立全栈 AI 开发者打造的 Claude Code 效率工具集 —— **One-Person Company / Solo Founder / Solo Builder**。

这是一个持续打磨的工坊，把我日常 Claude Code 工作流里反复要用的小工具沉淀进来：跨 session 可观测、一键回到任意历史 session、token 用量与费用追踪、Skill 脚手架、每日工作日志、状态栏模板。欢迎提 issue 和 PR。

---

## 快速开始

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
source ~/.zshrc

cc-status        # 总览所有 Claude Code session
cc-resume        # 交互式选择 + 回到任意历史 session
cc-limits        # 跨所有 transcript 的 token 用量与估算费用
```

依赖：`bash`、[`jq`](https://stedolan.github.io/jq/)（命令行 JSON 处理工具）、[`fzf`](https://github.com/junegunn/fzf)（终端交互式模糊选择器）。macOS 一键装：`brew install jq fzf`。

要开启 prompt 计数与 subagent 追踪，把 [`settings.example.json`](./settings.example.json) 里的 `hooks` 块并入你的 `~/.claude/settings.json`，再在 Claude Code 里输入 `/hooks` 重载（或重启）。

---

## 工具

| 工具 | 状态 | 功能 |
|------|:----:|------|
| `cc-status` / `cc-watch` | ✅ | 跨项目的 session 仪表盘。`cc-watch` 自动刷新（默认 30 秒，可用 `REFRESH_INTERVAL=5` 缩短刷新间隔）|
| `cc-resume` | ✅ | 用 `fzf` 模糊搜索所有项目的历史 session（按时间倒序），选中回车即跳转到 `claude --resume <id>` |
| `cc-limits` | ✅ | 跨项目 token 用量 + 费用历史，任意窗口、watch 模式、statusline 集成 —— 与 Claude Code 内置 `/usage` 互补（`/usage` 才是当前 5h 配额的权威读数）|
| `cc-daily` | ✅ | 给每个项目自动写 `daily-worklog.md`；可选 `--export obsidian` / `--export notion` 同步到外部 |
| `cc-skill-init <name>` | ✅ | 一行命令在 `.claude/skills/<name>/` 生成完整 Skill 脚手架（含 frontmatter、Step-0 读上下文区块）|
| `cc-pilot suggest` | ✅ | 扫描历史 transcript，找出你手动批准过 ≥ 5 次的 Bash 命令，据此推导 `permissions.allow` 规则。破坏性模式会被自动拦截，并附上触发拦截的具体命令 |
| `cc-pilot safe` / `dev` / `yolo` | ✅ | 用指定权限 profile 启动 Claude Code：`safe`（只读）/ `dev`（safe + 构建测试 + 可回滚 git）/ `yolo`（`--dangerously-skip-permissions`，启动前会检查工作树是否干净、是否不在主分支）。Profile 是 [`pilot/profiles/`](./pilot/profiles/) 下的纯文本文件 |
| `cc-tail` | ✅ | 用 `tail -f` 实时输出 Hook 事件流，并交给 jq 美化格式 |
| Statusline 模板库 | ✅ | 7 套开箱即用的 `statusLine`，`sl-default` / `sl-cost` / `sl-pomo` / `sl-bip` / `sl-cn` / `sl-minimal` / `sl-session` 一键切换。详见 [`statuslines/`](./statuslines/) |
| Hook 事件流 | ✅ | `SessionStart` / `SessionEnd` / `UserPromptSubmit` / `SubagentStop` 事件全部写入 `~/.claude/monitor/events.jsonl`（[JSONL](https://jsonlines.org/) = JSON Lines，每行一个 JSON 对象的追加式事件流）|

---

## 用法

### Session 管理

```bash
cc-status                     # 一次性快照
cc-watch                      # 自动刷新（默认 30 秒）
REFRESH_INTERVAL=5 cc-watch   # 5 秒一刷（盯紧时用）
cc-resume                     # fzf 选择 → 回任意历史 session
```

### Token 用量与费用：`cc-limits`

> **关于 `/usage`**：Claude Code 已经内置了 [`/usage`](https://code.claude.com/docs/en/costs#using-the-usage-command) 斜杠命令。在任意 Claude Code 会话里输入 `/usage`，会显示：当前 session 总成本（API 用户）、API / wall 总时长、代码增删行数；并且对 Pro/Max/Team 订阅用户**额外**显示来自 Anthropic 服务端的**权威** 5h plan-usage 条 + reset 倒计时。想一次性看"我现在到了多少 %"，直接用 `/usage`。它只能交互式运行（没有 JSON / CLI 形式），所以 `cc-limits` 在以下方面互补：跨项目历史、任意窗口费用、活跃进程、watch 模式、statusline 集成。

```bash
cc-limits                            # 默认窗口：最近 24 小时
cc-limits -1h                        # 窗口简写：-30m | -1h | -7d | -30d | --last 6h
cc-limits --watch                    # 自动刷新（30 秒）
```

每个窗口都显示：活跃进程 · 该窗口聚合（token / 费用 / 按模型分类）· top sessions。设了 `CC_PLAN` 还会加一个本地近似的 plan 预算块（锚定到当前 5h tumbling 块）。

**可选 —— plan 预算块**（在 watch / statusline 持续显示时有用）：

```bash
export CC_PLAN=max5                  # 可选值：pro | max5 | max20 | team | free
```

**可选 —— 校准**（仅在 statusline / watch 场景有意义；一次性查询直接用 `/usage`）：

```bash
# 1. 在 Claude Code 里跑 /usage（或打开 claude.ai/settings/usage），记下 %
# 2. 一两分钟内：
cc-limits --calibrate 40             # 把 40 换成实际看到的数字 —— 锚定到你账号的实际加权
cc-limits --calibrate-clear          # 撤销，回到 plan 默认值
```

**完整参考**：[`docs/cc-limits.zh-CN.md`](./docs/cc-limits.zh-CN.md) —— 与 `/usage` 关系详解、Sonnet/Haiku 价格覆盖、tumbling 窗口工作原理、周限额说明、watch 模式环境变量。

### 每日工作日志：`cc-daily`

```bash
cc-daily                      # 给每个有活动的项目写今日 section
cc-daily 2026-05-06           # 指定日期（YYYY-MM-DD，UTC）
cc-daily --here               # 仅处理当前目录所属的项目（cwd = current working directory，当前工作目录）
cc-daily --dry-run            # 仅预览，不写文件
cc-daily --export obsidian    # 同步写到 $CC_OBSIDIAN_VAULT/Daily Notes/<date>.md
cc-daily --export notion      # 同步推到 $NOTION_DB_ID（需要 $NOTION_API_KEY）
```

每个项目维护一份累积式 `<项目根目录>/daily-worklog.md`，新日期 prepend 到顶部。**对同一日期重跑只会替换那一天的 section**，其他日子里你手写的内容完全不动。

### 一行命令新建 Skill：`cc-skill-init`

```bash
cc-skill-init voc-collect -d "每周从 Reddit/G2/X 挖客户原话" --opc
cc-skill-init seo-write -d "依据 voice + 大纲起草 SEO 长文" --reads .agents/voice-of-customer.md
cc-skill-init my-utility --global         # 放到 ~/.claude/skills/，所有项目可用
```

生成完整的 Skill 结构：带 frontmatter 与 `Step 0 · Context check` 的 `SKILL.md`、面向人的 `README.md`、起手 prompt、空的 `templates/` 与 `examples/` 目录。

### 减少权限提示：`cc-pilot`

三个子命令，一个共同目标：少点几次 "yes"，但不要因此打开破坏性操作的口子。

```bash
cc-pilot suggest      # 从历史批准记录推导 permissions.allow 规则
cc-pilot safe         # 用只读 profile 启动
cc-pilot dev          # 用 safe + 构建 + 可回滚 git profile 启动
cc-pilot yolo         # 用 --dangerously-skip-permissions 启动（启动前预检）
```

三个命令都是 session 级，只用官方 Claude Code 标志（`--allowed-tools`、`--disallowed-tools`、`--dangerously-skip-permissions`）。

| Profile | 风险 | 启动前置条件 |
|---------|:----:|------------|
| `safe` | 🟢 | （无前置 —— 永远可以启动）|
| `dev` | 🟡 | （无前置，但显式 deny list 拦截 force-push、`rm -rf`、`sudo` 等）|
| `yolo` | 🔴 | 在 git 仓库内 · 工作树干净 · 分支不是 `main`/`master`/`develop`/`prod`/`production`/`release`/`stable`。强行越过用 `--i-understand-the-risk` |

Profile 是 [`pilot/profiles/`](./pilot/profiles/) 下的纯文本文件 —— 每行一条 [Claude Code 权限规则](https://docs.claude.com/en/docs/claude-code/iam)，`#` 是注释。欢迎 PR 给 `dev.allow` 补充我们尚未覆盖的语言。

**完整参考**：[`docs/cc-pilot.zh-CN.md`](./docs/cc-pilot.zh-CN.md) —— 完整 deny list、只读 verb 白名单、suggest 输出详解、各 profile 内容、yolo 预检规则。

### 状态栏模板库

7 套即插即用的 `statusLine` 脚本。每套都是单文件 shell：读 Claude Code 通过 stdin 传入的 JSON（`.workspace.current_dir`、`.model.display_name`、`.context_window.used_percentage`），输出一行简洁字符串。`sl-*` 别名一键切换，**切换后需重启 Claude Code session 才会生效**。

| 别名 | 显示内容 | 适用场景 |
|------|---------|---------|
| `sl-default` | `📁 dir  ⎇ branch  ✨ model  ctx N%` | **日常通用** —— 信息密度合适，不杂乱 |
| `sl-cost` | `✨ model  ctx N%  ⏰5h $X  📅24h $Y` | **高强度编码日** —— 把 token 花费摆在眼前（用 `CC_PRICE_*` 环境变量调整价格）|
| `sl-session` | `📁 dir  sid:xxx  🟢 live 3/8  🤖 12` | **多 session 协同** —— 看活跃进程数 + 今日 subagent 触发数 |
| `sl-pomo` | `🍅 task  📁 dir  ⏱  18:42 focus` | **专注模式** —— 25 分钟专注 / 5 分钟休息的番茄钟，带任务名 |
| `sl-bip` | `📁 dir  🪙 142k  💬 35  🐦 6h` | **Build-in-Public 创作者** —— 上次发帖超 24 小时会显示 ⚠ 提醒 |
| `sl-cn` | `📁 项目  ✨ 模型  📊 N%  🪙 142k  🕐 14:30` | **国内 OPC** —— 中文 + 北京时间 + 今日 token 总量 |
| `sl-minimal` | `model · dir` | 极简党 / 终端窄的人 |

**番茄钟**状态保存在 `~/.claude/monitor/pomodoro.state`：

```bash
cc-pomo-start "修 Stripe webhook 502"   # 开启一个专注块
cc-pomo-stop                            # 取消
# 默认 25 分钟专注、5 分钟休息 —— 用 CC_POMO_FOCUS / CC_POMO_BREAK（秒）覆盖
```

**Build-in-Public** 上次发帖时间戳保存在 `~/.claude/monitor/last-x-post`：

```bash
cc-bip-posted   # X / LinkedIn 发完帖跑一次 —— 超 24 小时状态栏会显示 ⚠ 提醒
```

每个 statusline 大约 50 行 bash。想自定义？复制 [`statuslines/`](./statuslines/) 里的任意一个，改 `printf` 输出，把你的 `.sh` 放在同目录，再用 `ln -sf` 接到 `~/.claude/statusline-command.sh` 即可。完整 gallery 文档 + stdin 字段参考：[`statuslines/README.md`](./statuslines/README.md)。

---

## Hooks（可选）

加上才有 prompt 计数与 subagent 追踪。把 [`settings.example.json`](./settings.example.json) 的 `hooks` 块合并进 `~/.claude/settings.json`，再在 Claude Code 里 `/hooks` 重载或重启。

⚠️ 新 hooks **不会在当前 session 生效**，只对之后启动的新 session 起作用。

---

## 工作机制 & 安全性

本工具集**只读取 Claude Code 自己写到你机器上的本地文件**。完全不发出站请求、不调用 Anthropic API、不爬 claude.ai、不碰你的 OAuth token 或 API key。

| 行为 | 本工具集 |
|------|:------:|
| 向 Anthropic 发任何数据 | ❌ 从不 |
| 调用 Anthropic API（含未公开端点）| ❌ 从不 |
| 读取/上传 OAuth token 或 API key | ❌ 从不 |
| 爬取 claude.ai 或其他 web UI | ❌ 从不 |
| 循环调用 Claude 制造虚假 usage / 绕过 rate limit | ❌ 从不 |
| 任何形式的 "phone home" 上报 | ❌ 从不 |
| 使用 Claude Code 官方的 `hooks` API | ✅ 被动：读 stdin → 追加 JSONL |
| 读 `~/.claude/projects/*/*.jsonl`（你**自己**的 transcript）| ✅ 你的本地文件 |
| 调用 `claude --resume <id>`（官方公开 CLI 参数）| ✅ 标准用法 |

**关于封号或平台告警风险** —— 我们只能描述本工具实际做什么，无法替 Anthropic 解读它自己的服务条款。能验证的事实：

- 本工具不向 Anthropic 服务发出任何请求（仅有的一次 `curl` 是用户主动启用的 `cc-daily --export notion`，发往 api.notion.com）。
- 只读 Claude Code 自己写到你本地磁盘的文件（`~/.claude/projects/`、`~/.claude/sessions/`）。
- 只使用官方文档中的扩展点：hooks（`SessionStart` / `SessionEnd` / `UserPromptSubmit` / `SubagentStop`）、`claude --resume`、`claude --allowed-tools` / `--disallowed-tools` / `--dangerously-skip-permissions`、`statusLine` 配置。

你账号是否始终合规取决于**你如何使用这些能力**，跟"是否经过工具包装"没有本质关系。用脚本跑 `git push --force` 跟你自己手敲它的性质是一样的 —— 都受你自己判断的约束。

**关于 `cc-limits` 的 "% used" 估算** —— 所有数字都来自你本地的 transcript JSONL 文件。工具数 unique `requestId` 的数量，除以 plan 配额（Anthropic 公开声明的默认值，可通过 `--calibrate` 用 `/usage` 或 dashboard 的真实读数校准）。**想要当前窗口的权威 %，请用 Claude Code 内置的 `/usage`** —— 它直接查服务端。`cc-limits` 的算法全部本地：没有 API 调用、没有爬取、没有触碰 Anthropic 内部数据。

### 真实存在的风险（对你而言）

- **隐私在你自己手上**。`~/.claude/monitor/events.jsonl` 含 prompt 前缀 + 完整 cwd 路径；`~/.claude/projects/*/*.jsonl` 含完整对话内容。**不要 push 到公开仓库**。`.gitignore` 已经处理 `events.jsonl`，如果你把 `~/.claude/` 同步到任何地方，记得把 `projects/` 也排除。
- **估算只是估算**。`cc-limits` 的 plan 预算、burn rate、reset 倒计时、token 费用估算都是本地推算出来的，所以每处都标了 `⚠ estimated, not authoritative`。把它们当参考线用，不要当作权威数字 —— Anthropic 的实际限流可能比预测早或晚发生。
- **Hooks 是双刃剑**。我们装的 4 个 hooks 都只做"读 stdin、写本地文件"这种被动操作，但**未来你或队友再加进去的 hook**（比如自动调外部 API、外发数据）就是另一回事了。随时可以审计当前装了哪些：`jq '.hooks' ~/.claude/settings.json`。

### 本工具集**明确不做**的事

- ❌ 循环调 Claude 来 inflate / game 用量
- ❌ 读取、复制、分享你的 OAuth token / API key
- ❌ 爬取未公开的端点或 web UI
- ❌ 任何形式的 "phone home" 上报数据（连匿名都没有）
- ❌ 修改 Claude Code 二进制 或 注入运行时代码

### 不卸载、临时全停的方法

在 `~/.claude/settings.json` 加：

```json
{ "disableAllHooks": true }
```

Alias 保留（`cc-status` 等仍可只读看现有数据），只是不再追加新事件。删掉这行就恢复。

### 我**没有** 100% 把握的事

我没有逐字读过 Anthropic 的完整服务条款，所以**无法保证它的某一条不会以某种意外的方式适用到本工具上**。上面的判断基于一个简单观察：本工具实际做的事（零网络、只读本地文件、只用官方 API）跟平台通常会管的违规行为（凭证盗用、API 滥用、爬取、刷假用量）完全不沾边。

如果你想要 100% 保险，**最稳妥的做法是给 Anthropic 客服发一封邮件，附上本 README 链接**。如果你拿到了官方反馈，告诉我，我会据此更新文档。

---

## 注意事项

- **平台**：在 macOS / zsh 实测过；BSD 与 GNU `stat` 已自动适配 Linux，但暂未实测。
- **当前 5h 配额的权威读数请用 Claude Code 的 `/usage`**。`cc-limits` 的 plan 预算块只是本地近似 —— watch / statusline 持续显示有用，不是真相。
- **Plan 默认值会漂移**。`cc-limits` 的 5h-cap 默认值校对于 2026-05-07。Anthropic 调整时用 `CC_PLAN_MSG_LIMIT_5H` 覆盖（或者直接看 `/usage`）。
- **周限额尚未建模**。Anthropic 还有独立的 7 天滚动上限；`cc-limits` 目前只显示 5h 窗口。

---

## 适合谁用

同时跑多个 Claude Code session 的独立全栈 AI 开发者。无论你怎么称呼自己 —— **OPC**、**Solo Founder**、**Solo Builder**、**Indie Hacker**、**Vibe Coder** —— 面对的是同一类问题、用得上同一套工具。

一个人把 Claude Code 当工程团队用的时候，可观测性比团队场景更重要 —— 因为没有队友能告诉你"我们昨天到哪了"。这套工具就是来填这个空缺，给你一份你本可以问队友的仪表盘。

---

## 贡献

欢迎 PR。收录标准只有一句：*"明天我自己也会装到 `~/.claude/` 里吗？"* —— 实用至上，观点鲜明优于面面俱到。Bug 反馈和提问同样欢迎。

**语言策略** —— 默认走英文：

- 所有代码、shell 注释、错误与帮助信息、文档全用英文
- `README.zh-CN.md` 是仓库里**唯一**的翻译版本；它跟 `README.md` 在结构上一一对应，方便后续更新时对照同步
- `statuslines/bilingual-cn.sh` 是**唯一**输出中文字符串的脚本（脚本里的注释仍然写英文）
- 语言切换徽章里的 `alt="中文"` 保留中文 —— 那是读者点击切换语言时看到的标签文字

---

## License

[MIT](./LICENSE) —— 随便用、随便 fork、随便 ship。
