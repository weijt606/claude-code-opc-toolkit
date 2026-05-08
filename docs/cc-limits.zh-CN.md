# `cc-limits` —— Token 用量与费用监控

跨项目的 Claude Code 用量监控工具。从你本地的 transcript 文件（`~/.claude/projects/*/*.jsonl`）聚合数据 —— 零网络调用，零凭证读取。

> [English](./cc-limits.md) · [回到 README](../README.zh-CN.md)

---

## 命令速查

```bash
cc-limits                          # 默认：最近 24 小时
cc-limits -30m                     # 最近 30 分钟
cc-limits -1h                      # 最近 1 小时
cc-limits -7d                      # 最近 7 天
cc-limits -30d                     # 最近 30 天
cc-limits --last 6h                # 长写法（= -6h）
cc-limits --days 30                # 兼容旧用法（= -30d）
cc-limits -7d --watch              # 自动刷新
cc-limits --plan max5              # 加上 plan 预算块
cc-limits --calibrate 60           # 校准预算 % 到 dashboard
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

设置 `CC_PLAN`（或传 `--plan`），即可看到 5 小时 session 预算的估算用量百分比、burn rate 与窗口重置倒计时：

```bash
export CC_PLAN=max5       # 可选值：pro | max5 | max20 | team | free | api
cc-limits

# 增加 "🎯 Plan budget" 块：
#
#     Claude Max 5× ($100/mo)  (CC_PLAN=max5 · cap default)   ⚠ estimated, not authoritative
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

### Session 锚点

预算只统计**当前 session 起**（最近一次安静期后第一条请求开始）的请求数，**不是**整个 5h 滚动窗口。这跟 `claude.ai/settings/usage` 的 "Current session" 计数器行为一致。默认空闲阈值 **30 分钟**：

```bash
export CC_SESSION_GAP_MIN=60   # 1h+ 空闲才算新 session（更保守）
export CC_SESSION_GAP_MIN=15   # 15min+ 空闲就算新 session（更激进）
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

- **真实速率限制状态在服务端，本工具看不到**。`cc-limits` 显示的所有数字都是从你本地 transcript 聚合出来的近似值。
- **计费按 token 加权，但权重公式不公开**。Anthropic 给上下文大、输出多的请求更高权重，本工具复现不了这部分。`--calibrate` 是把本地估算锚定到 dashboard 真实读数的唯一办法。
- **周限额尚未建模**。Anthropic 还有一个独立的 7 天滚动上限，目前不追踪。要看真实数据请打开 `claude.ai/settings/usage`。
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
