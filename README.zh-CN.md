# claude-code-opc-toolkit

[![English](https://img.shields.io/badge/lang-English-lightgrey?style=flat-square)](./README.md)
[![中文](https://img.shields.io/badge/lang-%E4%B8%AD%E6%96%87-DC2626?style=flat-square)](./README.zh-CN.md)
[![Built for Claude Code](https://img.shields.io/badge/built_for-Claude%20Code-D97757?style=flat-square)](https://claude.com/claude-code)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)](./LICENSE)

[![tools](https://img.shields.io/badge/tools-6-blue?style=flat-square)](#工具)
[![statuslines](https://img.shields.io/badge/statuslines-7-7C3AED?style=flat-square)](./statuslines/)
[![hooks](https://img.shields.io/badge/hooks-4-D97757?style=flat-square)](./settings.example.json)
[![GitHub stars](https://img.shields.io/github/stars/weijt606/claude-code-opc-toolkit?style=flat-square&color=yellow)](https://github.com/weijt606/claude-code-opc-toolkit/stargazers)

> 给独立全栈 AI 开发者用的 Claude Code 效率工具集 —— **One-Person Company / Solo Founder / Solo Builder**。

一个持续生长的工坊，把我日常 Claude Code 工作流里反复用到的小工具沉淀进来：跨 session 可观测性、一键 resume、token 用量、skill 脚手架、每日 worklog、statusline 模板。欢迎 issue 和 PR。

---

## 快速开始

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
source ~/.zshrc

cc-status        # 看所有 Claude Code session
cc-resume        # fzf 选择 → 回到任意历史 session
cc-limits        # 跨所有 transcript 的 token 用量 + 估算费用
```

依赖：`bash`、`jq`、`fzf`。macOS：`brew install jq fzf`。

要拿到 prompt 计数和 subagent 跟踪，把 [`settings.example.json`](./settings.example.json) 里的 `hooks` 块 merge 进 `~/.claude/settings.json`，然后在 Claude Code 输入 `/hooks` 重载（或重启）。

---

## 工具

| 工具 | 状态 | 做什么 |
|------|:----:|--------|
| `cc-status` / `cc-watch` | ✅ | 跨项目 session 仪表盘。`cc-watch` 实时刷新（默认 30s，`REFRESH_INTERVAL=5` 调更紧）|
| `cc-resume` | ✅ | fzf 选择器跨所有历史 session，按时间倒序 → `claude --resume <id>` |
| `cc-limits` | ✅ | Token 用量 + 估算费用：live 进程、5h / 24h / N 天窗口、top session |
| `cc-daily` | ✅ | 给每个项目自动写 `daily-worklog.md`，可选 `--export obsidian` / `--export notion` |
| `cc-skill-init <name>` | ✅ | 一行命令在 `.claude/skills/<name>/` 生成完整 skill 脚手架（含 Step-0 读上下文模式）|
| `cc-tail` | ✅ | `tail -f` hook 事件流 + jq 高亮 |
| Statusline 模板库 | ✅ | 7 套即插即用 `statusLine`，`sl-default` / `sl-cost` / `sl-pomo` / `sl-bip` / `sl-cn` / `sl-minimal` / `sl-session` 一行切换。详见 [`statuslines/`](./statuslines/) |
| Hook 事件流 | ✅ | `SessionStart` / `SessionEnd` / `UserPromptSubmit` / `SubagentStop` → `~/.claude/monitor/events.jsonl` |

---

## 用法

### Session 管理

```bash
cc-status                     # 一次快照
cc-watch                      # 自动刷新（默认 30 秒）
REFRESH_INTERVAL=5 cc-watch   # 5 秒一刷（盯紧时用）
cc-resume                     # fzf 选 → 回任意历史 session
```

### Token 用量 & 费用：`cc-limits`

```bash
cc-limits                     # live 进程 + 5h / 24h / 7d 聚合
cc-limits --days 30 --watch
```

价格默认按 Opus 4 公开费率，可覆盖：

```bash
# Sonnet 4
CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 CC_PRICE_CACHE_WRITE=3.75 CC_PRICE_CACHE_READ=0.30 cc-limits

# Haiku 4
CC_PRICE_INPUT=1 CC_PRICE_OUTPUT=5  CC_PRICE_CACHE_WRITE=1.25 CC_PRICE_CACHE_READ=0.10 cc-limits
```

> Claude Code 不暴露内部速率限制计数器，5h 聚合是 *代理指标* 不是权威配额。订阅 Pro/Max 的话，费用是"按 API 价格折算的价值"，不是实际账单。

### 每日 worklog：`cc-daily`

```bash
cc-daily                      # 给每个有活动的项目写今天的 section
cc-daily 2026-05-06           # 指定日期（YYYY-MM-DD, UTC）
cc-daily --here               # 只处理当前项目
cc-daily --dry-run            # 预览，不写文件
cc-daily --export obsidian    # 同时写到 $CC_OBSIDIAN_VAULT/Daily Notes/<date>.md
cc-daily --export notion      # 同时推到 $NOTION_DB_ID（需要 $NOTION_API_KEY）
```

每个项目一个累积式 `<项目根目录>/daily-worklog.md`，新日期 prepend 到顶部。重跑同一天**只覆盖那天的 section**，你手写的内容纹丝不动。

### 新建 skill：`cc-skill-init`

```bash
cc-skill-init voc-collect -d "每周挖客户原话" --opc
cc-skill-init seo-write -d "从 voice + 大纲起草 SEO 长文" --reads .agents/voice-of-customer.md
cc-skill-init my-utility --global         # 放到 ~/.claude/skills/ 而不是项目本地
```

生成完整 skill 结构（带 frontmatter + `Step 0 · Context check` 的 `SKILL.md`、`README.md`、`prompts/starter.md`、空的 `templates/` 和 `examples/`）。

### Statusline

```bash
sl-default       # 📁 dir  ⎇ branch  ✨ model  ctx N%
sl-cost          # ✨ model  ctx N%  ⏰5h $X  📅24h $Y
sl-session       # 📁 dir  sid:xxx  🟢 live 3/8  🤖 12
sl-pomo          # 🍅 task  📁 dir  ⏱  18:42 focus
sl-bip           # 📁 dir  🪙 142k  💬 35  🐦 6h
sl-cn            # 📁 项目  ✨ 模型  📊 N%  🪙 142k  🕐 14:30
sl-minimal       # model · dir
```

番茄钟：`cc-pomo-start "任务名"` / `cc-pomo-stop`。BIP：`cc-bip-posted` 每次 X / LinkedIn 发完帖跑一次（超 24h 状态栏会显示 ⚠）。

完整 gallery + 自定义说明：[`statuslines/README.md`](./statuslines/README.md)。

---

## Hooks（可选）

加上才有 prompt 计数和 subagent 跟踪。把 [`settings.example.json`](./settings.example.json) 的 `hooks` 块 merge 进 `~/.claude/settings.json`，输入 `/hooks` 重载或重启。

⚠️ 新 hooks **不在当前 session 生效**，只对新启动的 session 起作用。

---

## 注意事项

- **速率限制**：Claude Code 的内部计数器不公开；`cc-limits` 的 5h 块是代理指标。
- **隐私**：`events.jsonl` 和 transcript 文件含 prompt 前缀和完整 cwd 路径 —— **不要 push 到公开仓库**。
- **macOS / zsh 实测**；BSD/GNU `stat` 已自动适配 Linux，但未实际验证。

---

## 谁适合用

独立全栈 AI 开发者，同时跑多个 Claude Code session 的人。你叫自己什么都行 —— **OPC**、**Solo Founder**、**Solo Builder**、**Indie Hacker**、**Vibe Coder** —— 同一类问题，同一套工具。

只有你 + Claude Code 作为工程杠杆时，可观测性比团队场景更重要。这个工具集替代那个不存在的队友，给你一份仪表盘。

---

## 贡献

欢迎 PR。收录标准：*"明天我自己也会装到 `~/.claude/` 里吗？"* —— 实用至上，观点鲜明优于面面俱到。Bug 反馈和提问同样欢迎。

---

## License

[MIT](./LICENSE) —— 随便用、随便 fork、随便 ship。

—— [@weijt606](https://github.com/weijt606) · 是 OPC 工具箱的一部分，与个人 Obsidian 知识图谱（vibe-coding-bible / GTM 知识谱系 / deployment handbook）配套。
