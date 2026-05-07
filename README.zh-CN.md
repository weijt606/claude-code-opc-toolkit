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

一个持续打磨的工具工坊，沉淀我日常 Claude Code 工作流里反复用到的小工具：跨 session 可观测性、一键回到任意历史 session、token 用量与费用追踪、Skill 脚手架、每日工作日志、状态栏模板。欢迎提 issue 和 PR。

---

## 快速开始

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
source ~/.zshrc

cc-status        # 总览所有 Claude Code session
cc-resume        # 用 fzf 选回任意历史 session
cc-limits        # 跨所有 transcript 的 token 用量与估算费用
```

依赖：`bash`、`jq`、`fzf`。macOS 一键装：`brew install jq fzf`。

要开启 prompt 计数与 subagent 追踪，把 [`settings.example.json`](./settings.example.json) 中的 `hooks` 块合并进 `~/.claude/settings.json`，然后在 Claude Code 里输入 `/hooks` 重载（或重启 Claude Code）。

---

## 工具

| 工具 | 状态 | 功能 |
|------|:----:|------|
| `cc-status` / `cc-watch` | ✅ | 跨项目的 session 仪表盘。`cc-watch` 自动刷新（默认 30 秒，`REFRESH_INTERVAL=5` 可调更紧）|
| `cc-resume` | ✅ | 跨硬盘所有项目历史 session 的 fzf 选择器，按时间倒序，回车直达 `claude --resume <id>` |
| `cc-limits` | ✅ | Token 用量与估算费用：当前活跃进程的上下文大小、5h / 24h / N 日窗口、消耗 top session |
| `cc-daily` | ✅ | 给每个项目自动写 `daily-worklog.md`；可选 `--export obsidian` / `--export notion` 同步到外部 |
| `cc-skill-init <name>` | ✅ | 一行命令在 `.claude/skills/<name>/` 生成完整 Skill 脚手架（含 frontmatter、Step-0 读上下文区块）|
| `cc-tail` | ✅ | 实时 `tail -f` Hook 事件流，jq 自动高亮 |
| Statusline 模板库 | ✅ | 7 套即插即用的 `statusLine`，`sl-default` / `sl-cost` / `sl-pomo` / `sl-bip` / `sl-cn` / `sl-minimal` / `sl-session` 一键切换。详见 [`statuslines/`](./statuslines/) |
| Hook 事件流 | ✅ | `SessionStart` / `SessionEnd` / `UserPromptSubmit` / `SubagentStop` 事件全部写入 `~/.claude/monitor/events.jsonl` |

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

```bash
cc-limits                          # 活跃进程 + 5h / 24h / 7d 聚合
cc-limits --days 30 --watch        # 拓宽窗口 + 自动刷新
cc-limits --plan max20             # 加上 plan-aware 预算块（见下）
```

**价格覆盖** —— 默认按 Opus 4 公开费率：

```bash
# Sonnet 4
CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 CC_PRICE_CACHE_WRITE=3.75 CC_PRICE_CACHE_READ=0.30 cc-limits

# Haiku 4
CC_PRICE_INPUT=1 CC_PRICE_OUTPUT=5  CC_PRICE_CACHE_WRITE=1.25 CC_PRICE_CACHE_READ=0.10 cc-limits
```

**Plan-aware 预算** —— 设置 `CC_PLAN`（或传 `--plan`），即可看到 5 小时滚动窗口的估算用量百分比、burn rate 与窗口重置倒计时：

```bash
export CC_PLAN=max20      # 可选值：pro | max5 | team | free | api
cc-limits

# "Last 5 hours" 下面会多出一段：
#
#     Claude Max (20×)  (CC_PLAN=max20)   ⚠ estimated, not authoritative
#     Usage:    624 / ~900 msgs   ██████████░░░░  69%
#     Burn:     125 msg/hr  →  exhaust in ~2h 12m
#     Resets:   in 1h 47m  (when oldest msg falls out of 5h window)
```

Anthropic 调整配额时手动覆盖默认值：

```bash
export CC_PLAN_MSG_LIMIT_5H=1500   # 或：cc-limits --plan max20 --quota 1500
```

> ⚠️ **Anthropic 没有公开订阅档配额的 API**。这个 plan 预算块是**本地数据的近似估算**：5 小时窗口的 message 数 ÷ 社区已知的公开配额上限。把它当 guardrail，**不要**当权威 —— 实际限流可能早于或晚于进度条暗示。订阅 Pro/Max 时，费用行展示的是"按 API 价格折算的价值"，不是真实账单。

### 每日工作日志：`cc-daily`

```bash
cc-daily                      # 给每个有活动的项目写今日 section
cc-daily 2026-05-06           # 指定日期（YYYY-MM-DD，UTC）
cc-daily --here               # 仅处理当前目录所属的项目
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

## 注意事项

- **速率限制**：Claude Code 内部计数器不公开；`cc-limits` 的 5h 块是代理指标。
- **隐私**：`events.jsonl` 与 transcript 文件包含 prompt 前缀和完整 cwd 路径 —— **不要 push 到公开仓库**。
- **平台**：在 macOS / zsh 实测过；BSD 与 GNU `stat` 已自动适配 Linux，但暂未实测。

---

## 适合谁用

同时跑多个 Claude Code session 的独立全栈 AI 开发者。无论你叫自己什么 —— **OPC**、**Solo Founder**、**Solo Builder**、**Indie Hacker**、**Vibe Coder** —— 同一类问题，同一套工具。

一个人 + Claude Code 当工程团队的时候，可观测性比团队场景更重要。这套工具替代那个不存在的队友，给你一份仪表盘。

---

## 贡献

欢迎 PR。收录标准只有一句：*"明天我自己也会装到 `~/.claude/` 里吗？"* —— 实用至上，观点鲜明优于面面俱到。Bug 反馈和提问同样欢迎。

---

## License

[MIT](./LICENSE) —— 随便用、随便 fork、随便 ship。
