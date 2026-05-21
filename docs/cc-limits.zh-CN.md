# `cc-limits` —— Token 用量与费用监控

跨项目的 Claude Code 用量监控工具。从你本地的 transcript 文件（`~/.claude/projects/*/*.jsonl`）聚合数据 —— 零网络调用，零凭证读取。

> [English](./cc-limits.md) · [回到 README](../README.zh-CN.md)

---

## 与 `/usage` 的关系

Claude Code 内置了 [`/usage` 斜杠命令](https://code.claude.com/docs/en/costs#using-the-usage-command)。对 Pro/Max/Team 订阅用户来说，`/usage` 显示的是**来自 Anthropic 服务端的权威 5h 配额读数**。**想知道"我现在到了多少 %"——在 Claude Code 里跑 `/usage` 就好，那才是真相。**

### `/usage` 显示什么

在任意 Claude Code 会话里输入 `/usage`。根据[官方文档](https://code.claude.com/docs/en/costs#using-the-usage-command)，输出大致是这样：

```
Total cost:            $0.55
Total duration (API):  6m 19.7s
Total duration (wall): 6h 33m 10.2s
Total code changes:    0 lines added, 0 lines removed
```

此外，根据账号类型还会附加：

- **Pro / Max / Team 订阅用户**：同屏会显示 **plan-usage 条 + activity stats**（活动统计）—— 这是直接来自 Anthropic 服务端的权威 5h 窗口读数和 reset 倒计时。
- **API 用户**：看到的是 Session 区块（token + 费用）。注意：`Total cost` 这个数字**也是本地估算**，从 token 数推算出来 —— 跟 cc-limits 的费用行同样的局限。要查权威 API 账单请打开 [Claude Console → Usage](https://platform.claude.com/usage)。

`/usage` 只能交互式运行 —— 没有公开的 CLI / JSON / 文件输出形式，所以无法驱动 statusline 或 watch 循环。

### 各自擅长什么

`cc-limits` 是 `/usage` 的**补集**，不是替代品。它做的是 `/usage` 不做的事：

| 问题 | 用哪个 |
|------|-------|
| 我现在 5h 配额用了多少 %？ | **`/usage`**（服务端权威，仅订阅用户） |
| 过去 7 / 30 天花了多少？ | **`cc-limits -7d` / `-30d`** |
| 哪些 session 烧的 output 最多？ | **`cc-limits`（Top sessions 区块）** |
| 跨所有项目，当前有哪些 Claude Code 进程在跑？ | **`cc-limits`（🔥 区块）** |
| 写代码时挂个持续刷新的面板 | **`cc-limits --watch`** |
| 跨多个 session 的 per-model 分布 | **`cc-limits`** |
| 状态栏常驻显示 token 花费 | **`sl-cost`**（本工具集） |

`/usage` 是交互式、session 范围内的；`cc-limits` 是可脚本化、历史聚合、跨项目的。

---

## 快速上手

```bash
cc-limits                          # 默认：最近 24 小时
cc-limits -7d                      # 最近 7 天
cc-limits --watch                  # 自动刷新面板
```

可选的 plan 预算块 —— 主要用在 statusline / watch 模式持续显示（一次性看权威读数请直接用 `/usage`）：

```bash
export CC_PLAN=max5                # pro | max5 | max20 | team | free | api
cc-limits                          # 多出一个 🎯 Plan budget 区块
```

## 可选：校准（主要用于 statusline 持续显示）

`/usage` 上线之后，**一次性查询用 `/usage` 即可，不需要校准**。校准只在你想让 `cc-limits --watch` 或 `sl-cost` statusline 里的 plan 预算块持续保持跟 dashboard ±5pp 误差时才有意义。

```bash
# 1. 打开 claude.ai/settings/usage（或在 Claude Code 里跑 /usage），记下当前 %
# 2. 一两分钟内：
cc-limits --calibrate 40           # 把 40 换成实际看到的数字

# 任何时候都可以撤销：
cc-limits --calibrate-clear
```

校准后的 cap 保存在 `~/.claude/monitor/cc-plan.conf`。Anthropic 计费按 token 加权且不透明，所以各档静态默认值会漂移 —— 校准把本地估算锚定到你账号的实际加权曲线。等再偏离了就重新跑一次。

## 日常命令速查

```bash
cc-limits                          # 默认：最近 24 小时
cc-limits -30m                     # 最近 30 分钟
cc-limits -1h                      # 最近 1 小时
cc-limits -7d                      # 最近 7 天
cc-limits -30d                     # 最近 30 天
cc-limits --last 6h                # 长写法（= -6h）
cc-limits --days 30                # 兼容旧用法（= -30d）
cc-limits -7d --watch              # 自动刷新
cc-limits --calibrate-clear        # 撤销校准，回到 plan 默认值
```

支持单位：**`m`**（分钟）· **`h`**（小时）· **`d`**（天）· **`w`**（周）。无参数时默认窗口 = **最近 24 小时**。

## 输出结构

每次运行都展示同样的几个块（你选的窗口决定数字大小）：

```
🔥  Live processes              ← 始终显示：PID、ctx 大小、busy/idle、cwd
⚡  Last <window>                ← 该窗口内 input/output/cache token + per-model + 估算费用
🎯  Plan budget                  ← 仅当设了 CC_PLAN 才显示；永远锚定 5h 滚动窗口
🏆  Top sessions by output       ← 该窗口内输出 token 最多的 5 个 session
```

Plan 预算块**永远锚定 5 小时速率限制窗口**，与你查询的窗口无关。所以 `cc-limits -30d --plan max5` 同时回答两个问题："过去 30 天我烧了多少？" 以及 "我现在在 5h 滚动窗口里到哪儿了？"。

## 价格覆盖

默认按 Claude Opus 4 系列费率（input $15 / output $75 / cache write $18.75 / cache read $1.50 per 1M tokens）。逐次覆盖：

```bash
# Sonnet 4
CC_PRICE_INPUT=3 CC_PRICE_OUTPUT=15 CC_PRICE_CACHE_WRITE=3.75 CC_PRICE_CACHE_READ=0.30 cc-limits

# Haiku 4
CC_PRICE_INPUT=1 CC_PRICE_OUTPUT=5  CC_PRICE_CACHE_WRITE=1.25 CC_PRICE_CACHE_READ=0.10 cc-limits
```

写到 `~/.zshrc` 实现持久覆盖。

> Claude Code 不暴露其内部速率限制计数器，Anthropic 配额是按**请求大小/复杂度内部加权**的，所以静态 `count ÷ cap` 估算会漂移。费用行展示的是"按 API 价折算的等价金额" —— 衡量你从订阅里榨出多少价值，**不是**真实账单。

## Plan 预算

> 再次提醒：要一次性查权威读数，直接在 Claude Code 里跑 `/usage`。下面这个区块是本地近似，主要用于 `--watch` 或 statusline 的持续显示场景。

设置 `CC_PLAN`（或传 `--plan`），即可看到 5 小时 session 预算的估算用量百分比、burn rate 与窗口重置倒计时：

```bash
export CC_PLAN=max5       # 可选值：pro | max5 | max20 | team | free | api
cc-limits

# 增加 "🎯 Plan budget" 块：
#
#     Claude Max 5× ($100/mo)  (CC_PLAN=max5 · cap default)   ⚠ local approximation — run /usage in Claude Code for authoritative %
#     Usage:    216 / ~450 msgs   ████████░░░░░░  48%
#     Burn:     127 msg/hr  →  exhaust in ~1h 50m
#     Resets:   in 3h 10m  (5h after session-start)
```

默认配额（**2026-05-08** 校对，已反映 Anthropic 2026-05-06 公告：Claude Code 5h 上限对所有付费档**翻倍**）：

| 档位 | 5h 上限 | 参数 |
|------|---------|------|
| Free | ~10 | `--plan free` |
| Pro | ~90 | `--plan pro` |
| Max 5× ($100/月) | ~450 | `--plan max5`（也可用 `--plan max`）|
| Max 20× ($200/月) | ~1800 | `--plan max20` |
| Team（按席）| ~450 | `--plan team` |
| API | 无（cost-based）| `--plan api` |

Anthropic 调整配额时手动覆盖：

```bash
export CC_PLAN_MSG_LIMIT_5H=2000
# 或者逐次：
cc-limits --plan max20 --quota 2000
```

### 翻滚式 5 小时窗口（锚点的真实工作方式）

Anthropic 既不用滚动 5h 窗口，也不在窗口内做 gap detection。它用的是**从你当天第一次请求开始的翻滚 5 小时块**（tumbling windows）：第一段窗口 = `[anchor, anchor+5h]`、第二段 = `[anchor+5h, anchor+10h]`，依此类推。Reset 倒计时 = 当前块结束的时间。

`cc-limits` 现在复现了这个模型：往回看 **24 小时**的 transcript（`CC_ANCHOR_LOOKBACK_HOURS=24`），找最近一次**至少 5 小时**的间隔（`CC_SESSION_GAP_MIN=300` 分钟，即"一整个窗口的无活动"），把间隔结束后的第一条请求当作锚点。然后算你当前在哪个 5h 块里，**只统计当前块内的消息数**。

30 分钟的午休、甚至 3 小时的间隔都不会重置锚点 —— 只有完整的 5h+ 中断才会。这跟 `claude.ai/settings/usage` 的实测行为一致（2026-05-09 验证：工具的 reset 倒计时跟 dashboard 误差约 2 分钟）。

可调参数（很少需要动）：

```bash
export CC_SESSION_GAP_MIN=300         # 默认：5h+ 间隔才算重新锚定
export CC_ANCHOR_LOOKBACK_HOURS=24    # 默认：往回看多久找原始锚点
```

### 用真实 dashboard 校准

Plan 默认值是尽力而为的估算，但 Anthropic 内部 `% used` 是按**请求大小/复杂度不透明加权**的，所以静态估算会漂移。如果 `cc-limits --plan max5` 显示 45% 但 `claude.ai/settings/usage` 显示 60%，把工具锚定到真实读数：

```bash
cc-limits --calibrate 60         # "我现在 dashboard 上看到 60%"
# → 用当前请求数反算你的有效 cap
# → 保存到 ~/.claude/monitor/cc-plan.conf
# → 之后所有 cc-limits 跑都用这个校准过的 cap，标记 "✓ calibrated"
```

如果用一段时间觉得估算又开始偏离实际了，重新校准一次就好。任何时候都可以撤销：

```bash
cc-limits --calibrate-clear      # 回到 plan 默认值
```

## 计数原理

`.messages` 和所有 token 总数都按 `.requestId` 去重：

> Claude Code 一次 API 请求会在 JSONL 里写下多条记录（每种 content block 一条：text、tool_use、thinking…），但**这些记录共享同一个 `.requestId`，而且 `.message.usage` 字段里的数字是完全一样的**。如果直接累加每条记录的 token 数，会把同一笔费用重复算 2 到 15 次（取决于 tool call 多少）。`cc-limits` 在聚合前先 `unique_by(.requestId)`，对应 Anthropic 实际"一次请求 = 一次计费"的口径。

实测 **2026-05-08**：5h 窗口内 135 unique requestIds 对照 `claude.ai/settings/usage` Max 5× plan 的 28% 读数，误差 ±2 个百分点。

## 注意事项

- **当前 5h 配额的权威读数请用 `/usage`**。`cc-limits` 的 plan 预算块是本地近似；一次性查询永远优先 `/usage`。cc-limits 负责的是历史、费用、活跃进程、持续显示这些 `/usage` 不做的事。
- **计费按 token 加权，但权重公式不公开**。Anthropic 给上下文大、输出多的请求更高权重，本工具复现不了这部分。`--calibrate` 能缩小 statusline 持续显示的误差 —— 但一次性查询用 `/usage` 就完全没这问题。
- **周限额尚未建模**。Anthropic 还有一个独立的 7 天滚动上限，目前不追踪。要看真实数据请打开 `claude.ai/settings/usage`（或跑 `/usage`）。
- **价格默认值会过期**。用 `CC_PRICE_*` 环境变量覆盖 —— 也别把费用行当成真实账单。
- **macOS / zsh 实测过**；Linux 应该能跑（BSD 和 GNU 版本的 `stat` 已自动适配），但还没在 Linux 上验证过。

## Watch 模式

```bash
cc-limits -7d --watch             # 默认 30 秒一刷
REFRESH_INTERVAL=5  cc-limits -1h --watch    # 5 秒一刷（盯紧）
REFRESH_INTERVAL=120 cc-limits --watch       # 2 分钟一刷（挂着不打扰）
```

Ctrl-C 退出，光标自动恢复。

## 数据存储位置

| 路径 | 用途 |
|------|------|
| `~/.claude/projects/*/*.jsonl` | Claude Code 自带的 transcript —— 主要数据源 |
| `~/.claude/sessions/<pid>.json` | 活跃进程元数据（用于 🔥 块）|
| `~/.claude/monitor/cc-plan.conf` | 校准结果（`--calibrate` 创建）|
| `~/.claude/monitor/events.jsonl` | Hook 事件流（被 `cc-status` / `cc-daily` 用，**不是** `cc-limits` 用）|
