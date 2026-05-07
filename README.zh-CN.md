# claude-code-opc-toolkit

[![English](https://img.shields.io/badge/lang-English-lightgrey?style=flat-square)](./README.md)
[![中文](https://img.shields.io/badge/lang-%E4%B8%AD%E6%96%87-2962FF?style=flat-square)](./README.zh-CN.md)
[![Built for Claude Code](https://img.shields.io/badge/built_for-Claude%20Code-D97757?style=flat-square)](https://claude.com/claude-code)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)](./LICENSE)

> 给一人公司（OPC）用的 Claude Code 工具集 —— 一眼看到所有 session，一键回到任意一个。

当你同时跑多个 Claude Code session（前端、后端、内容、运维……），不小心关了 terminal 就找不回之前的进度 —— Claude Code 自带的 `claude --resume` 只看当前 `cwd` 的 session。这套工具给你：

- **跨项目可视化** —— 一个仪表盘看完所有 session 的实时状态
- **一键 resume** —— fzf 选择器跨所有项目的全部历史 session
- **Hook 事件流** —— session 生命周期事件流式写入 JSONL，可做数据分析

macOS / zsh 实测，专为 indie 开发者 / 一人公司 / OPC 用户设计。

---

## 仓库结构

```
claude-code-opc-toolkit/
├── monitor/
│   ├── log.sh         # 接 hook stdin → 写 events.jsonl（永不阻塞 harness）
│   ├── view.sh        # 仪表盘：active / recent session、prompt 计数、subagent 活动
│   └── resume.sh      # fzf 选择器 → claude --resume <id>
├── settings.example.json   # 可直接 merge 进 ~/.claude/settings.json 的 4 个 hook
└── install.sh         # 一键：软链脚本 + 加 alias
```

脚本数据来自两个 source of truth：

1. **`~/.claude/projects/*/<session_id>.jsonl`** —— Claude Code 自带的 transcript。`mtime` = 最后活动时间，文件内 `.cwd` 字段 = 真实工作目录。**不需要任何配置即可工作**。
2. **`~/.claude/monitor/events.jsonl`** —— hooks 写入。提供 prompt-by-project 统计和 subagent 活动。

`view.sh` 和 `resume.sh` **不需要 hooks** 也能工作。Hooks 只是补充 prompt / subagent 维度的可观测性。

---

## 安装

### 前置依赖
- macOS（BSD `stat`）或 Linux（GNU `stat`）—— 都支持
- `bash`、`jq`、`fzf` —— `brew install jq fzf`
- Claude Code CLI

### 一键安装

```bash
git clone https://github.com/weijt606/claude-code-opc-toolkit.git
cd claude-code-opc-toolkit
./install.sh
```

会做三件事：
1. 把 `monitor/*.sh` 软链到 `~/.claude/monitor/`
2. 在 `~/.zshrc` 追加 4 个 alias（`cc-status`、`cc-watch`、`cc-resume`、`cc-tail`）
3. 打印需要 merge 进 `~/.claude/settings.json` 的 hook 配置

### 手动安装

```bash
# 1. clone 到任何你放工具的地方
git clone https://github.com/weijt606/claude-code-opc-toolkit.git ~/dev/claude-code-opc-toolkit

# 2. 软链脚本
mkdir -p ~/.claude/monitor
ln -sf ~/dev/claude-code-opc-toolkit/monitor/log.sh    ~/.claude/monitor/log.sh
ln -sf ~/dev/claude-code-opc-toolkit/monitor/view.sh   ~/.claude/monitor/view.sh
ln -sf ~/dev/claude-code-opc-toolkit/monitor/resume.sh ~/.claude/monitor/resume.sh

# 3. 加 alias 到 shell rc
cat >> ~/.zshrc <<'EOF'
alias cc-status='$HOME/.claude/monitor/view.sh'
alias cc-watch='$HOME/.claude/monitor/view.sh --watch'
alias cc-resume='$HOME/.claude/monitor/resume.sh'
alias cc-tail='tail -f $HOME/.claude/monitor/events.jsonl | jq'
EOF

# 4. 把 settings.example.json 里的 hook 配置 merge 进 ~/.claude/settings.json
#    然后在 Claude Code 里输入 /hooks 重载，或重启 Claude Code。
```

---

## 用法

### `cc-status` —— 一次快照

```
═══════════════════════════════════════════════════════
   Claude Code Session Monitor    2026-05-07 12:04:01
═══════════════════════════════════════════════════════

🟢  Active sessions (touched <30 min ago)
    1m ago    28531e24    /Users/you/dev/frontend
                resume: claude --resume 28531e24-07de-4068-a5fb-b6decd6fdee2    (8.4M)
    1m ago    ff76b1dc    /Users/you/dev/agent-graph
                resume: claude --resume ff76b1dc-79a7-4dec-bb82-12198ff4532a    (2.1M)

🕒  Recent sessions (last 24h, top 8 by recency)
    1m ago    28531e24  /Users/you/dev/frontend
    11m ago   2f9090dc  /Users/you/dev/agentagora

📊  Prompts by project (last 7d, from hook log)
       128 /Users/you/dev/agent-graph
        82 /Users/you/dev/frontend

🤖  Subagents finished (last 24h, from hook log)
    11:54:23  Explore           ff76b1dc
    12:01:42  claude-code-guide ff76b1dc
```

### `cc-watch` —— 实时刷新

```bash
cc-watch                       # 默认 30 秒一刷
REFRESH_INTERVAL=5  cc-watch   # 5 秒一刷（盯紧时用）
REFRESH_INTERVAL=120 cc-watch  # 2 分钟一刷（挂着不打扰）
```

Ctrl-C 退出，光标自动恢复。

### `cc-resume` —— fzf 一键回到

```bash
cc-resume
```

弹出 fzf 选择器，按时间倒序列最近 50 个 session（跨所有项目）。选中 → 自动跑 `claude --resume <id>`。

**典型场景**：terminal 关了 / 电脑重启 / 早上不记得昨天进度到哪 → `cc-resume` 一秒找回。

### `cc-tail` —— 实时事件流（调 hook 用）

```bash
cc-tail
```

实时尾随 JSONL，jq 高亮。加新 hook 时验证有没有触发。

---

## Hook 配置

Hooks 把 session 生命周期事件写到 `~/.claude/monitor/events.jsonl`。**不装 hooks 也能用** `cc-status` 和 `cc-resume`，只是不会有 prompt 计数和 subagent 统计。

具体 JSON 配置见 [`settings.example.json`](./settings.example.json)。共 4 个事件：

| 事件 | 作用 |
|-----|------|
| `SessionStart` | 检测新 session 启动并记录 cwd |
| `SessionEnd` | 标记 session 结束 |
| `UserPromptSubmit` | 按项目统计 prompt 数（粗略活动度）|
| `SubagentStop` | 追踪 Task tool 启动的 subagent |

⚠️ **新 hooks 不会在当前 session 生效**。Merge 完后输入 `/hooks` 重载，或重启 Claude Code。

---

## 自定义查询

事件流起来之后，可以对 `~/.claude/monitor/events.jsonl` 写自定义 jq 查询：

```bash
# 今天每小时的活动量
jq -r 'select(.ts >= "'$(date -u +%Y-%m-%d)'") | .ts | .[11:13]' \
  ~/.claude/monitor/events.jsonl | sort | uniq -c

# 按 prompt 数排序的 session
jq -r 'select(.event == "UserPromptSubmit") | .session_id' \
  ~/.claude/monitor/events.jsonl | sort | uniq -c | sort -rn | head

# 本月每个项目的 session 数
jq -r --arg m "$(date -u +%Y-%m)" \
  'select(.event == "SessionStart" and (.ts | startswith($m))) | .cwd' \
  ~/.claude/monitor/events.jsonl | sort | uniq -c | sort -rn
```

---

## 已知限制

- **新 hook 不在当前 session 生效** —— 输入 `/hooks` 重载，或重启
- **`agent_type` 字段可能为空** —— 看 Claude Code 版本的 `SubagentStop` payload 结构
- **`events.jsonl` 会一直长** —— 见 Roadmap 的日志轮转
- **隐私**：events.jsonl 含每个 prompt 前 80 字符 + 完整 cwd 路径。**不要 push 到公开仓库**。如果你把 `~/.claude/` 加进版本控制，记得放进 `.gitignore`。
- **macOS 实测**；BSD/GNU `stat` 检测应该能在 Linux 工作，但未实测

---

## Roadmap

- [ ] `install.sh` 自动 merge hook（含 settings.json 备份）
- [ ] `log.sh` 内置日志轮转（JSONL > 10MB 自动归档）
- [ ] HTTP webhook 类型 hook —— 推到自托管 dashboard
- [ ] 每日自动汇总到 Obsidian daily note
- [ ] 更多工具：skill-init、statusline 模板、slash-command 套件

欢迎 PR。issue 更欢迎。

---

## 为什么叫 "OPC"

OPC = **One-Person Company**（一人公司）。

这套工具的心智模型：一个人，把 Claude Code 当成全栈工程团队。一人作业时，可观测性更重要 —— 没人能告诉你"我们昨天到哪了？"

如果你不熟"OPC"这个词，把它换成 indie hacker / solo founder / vibe coder 都成立。**同一类问题，同一类解。**

---

## License

MIT —— 见 [LICENSE](./LICENSE)。

## 作者

[@weijt606](https://github.com/weijt606) · 这套工具是 OPC 工具箱的一部分，与个人 Obsidian 知识图谱（vibe-coding-bible / GTM 知识谱系）配套。
