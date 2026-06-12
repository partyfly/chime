# Chime 🐦

一只 macOS 上的**可拖动桌面宠物**,按你自己设定的日程,实时告诉你**现在该做什么**。它悬浮在你的工作之上,为当前时间块倒计时,并在新时间块开始时发出提醒。

[English](README.md) · **中文**

```
┌──────────────────────────────┐
│ 💻 深度工作              ➖  │        缩成药丸后:
│ 09:00–12:30 · 还剩 2h14m     │
│ · 最难的任务先做              │   ┌──────────────┐
│ · 关闭通知                    │   │  💻 2h14m     │
└──────────────────────────────┘   └──────────────┘
```

不占菜单栏、没有 Dock 图标、没有窗口边框——就是一张可以拖到任意位置的小卡片,不用时点一下缩成药丸。

## 为什么做它

大多数时间管理工具都得**打开它**才能看到下一步。Chime 反过来:答案永远在屏幕上,一眼可见,不需要时缩起来就好。它为那些把一天结构化的人设计——深度工作块、运动、创作时间——在每个切换点给你一个温和的、环境式的提醒,而不是一整屏的闹钟。

## 特性

- **常驻一瞥** — 当前时间块、剩余时间、该做的任务,悬浮于一切之上
- **随处拖动** — 位置自动记住,重启不丢
- **缩成药丸** — 只剩 emoji + 倒计时,点击展开
- **系统通知** — 每个时间块开始时提醒(可逐块关闭)
- **纯 JSON 日程** — 只改一个文件,App 在 30 秒内自动热重载
- **面向 Agent** — 附带 `chime` CLI + 内置 Claude Code skill,让 AI agent 读取你的一天并据此行动([详情](#agent-编排))
- **跟随所有桌面空间**(Space),适配深/浅色模式,毛玻璃质感
- **开机自启** — 一键开启
- **零依赖** — 单个 Swift 文件,`swiftc` 直接编译

## 安装

需要 macOS 12+ 和 Xcode 命令行工具(`xcode-select --install`)。

```sh
git clone https://github.com/partyfly/chime.git
cd chime
./build.sh
open Chime.app
```

屏幕右上角会出现一张毛玻璃卡片。首次启动时 macOS 会请求通知权限,允许它,时间块切换才能发提醒。

> Chime 是 ad-hoc 本地签名。首次打开如被 Gatekeeper 拦截,右键 → **打开**,或在「系统设置 → 隐私与安全性」里放行。

## 用法

| 操作 | 效果 |
|---|---|
| **拖动**卡片或药丸 | 移到任意位置,自动保存 |
| 点 **➖**(或点药丸) | 在完整卡片和药丸之间切换 |
| **右键** | 菜单:今日节奏、编辑、重载、开机自启、退出 |
| 再次双击 App | 把宠物带到最前并展开 |

药丸态:时间块进行中显示 `💻 2h14m`;下一块在 90 分钟内开始时显示 `→🌙 32m`;自由时间显示 `🐦`。

## 自定义日程

右键 → **编辑日程(JSON)** 会打开 `~/.config/chime/schedule.json`(首次编辑时创建):

```json
[
  { "start": "09:00", "end": "12:30", "emoji": "💻",
    "title": "深度工作",
    "task": "最难的任务先做;关闭通知",
    "notify": true },
  { "start": "12:30", "end": "13:30", "emoji": "🍽️",
    "title": "午餐", "task": "离开屏幕", "notify": false }
]
```

- `start` / `end` 是 24 小时制 `HH:mm`。`end` 可跨午夜(如 `23:00` → `07:00`)。
- `task` 用 `;` 分隔,在卡片和通知正文里逐行显示。
- `notify: false` 静音该块(适合睡眠、休息、可选时段)。
- 时间块不要重叠;留空档没关系——卡片会显示「自由时间」并倒计时到下一块。

保存后 App 在 30 秒内自动重载(也可右键 → **重新加载日程**)。仓库里附了一份 `schedule.example.json` 作起点。

## 开机自启

右键 → **开机自启**。会写入 `~/Library/LaunchAgents/com.partyfly.chime.plist`;再点一次移除。

## Agent 编排

Chime 的日程是一个纯 JSON 文件——一份机器可读的单一事实源(single source of truth),AI agent 或 shell 脚本都能读取并据此行动。挂件只是它的一个视图。

**`chime` CLI**(只读,随仓库附带)。在仓库里跑 `./chime`,或 `ln -s "$PWD/chime" /usr/local/bin/chime` 装到 PATH 后随处可用:

```sh
chime status          # 当前时间块、剩余时间、下一个是什么
chime status --json   # 同上,机器可读
chime next --json     # 下一个时间块及开始时间
chime today --json    # 今天完整日程,标记当前块
```

```jsonc
// chime status --json
{ "now": "14:32", "free": false,
  "current": { "title": "Focus", "remaining": "2h28m", "task": "...", ... },
  "next":    { "title": "Exercise", "starts_in": "2h28m", ... } }
```

**内置 Claude Code skill。** 仓库包含 `.claude/skills/chime/`——clone 下来,你的 Claude Code(或任何读取项目 skill 的 agent)就能回答"我现在该做什么?"、管理时间块,并**基于当前时间块行动**:在深度工作块保持简洁、在写作块主动帮你起草、为下一个块提前准备。它也能和 cron 或定时 AI 任务配合——早晨的任务可以先 `chime today` 了解今天的结构,再决定跑什么。

日程编码了你对一天的意图;agent 读取它并随之调整,而不是用闹钟反复打扰你。

## 实现原理

单个 Swift 文件,基于 AppKit。挂件是一个无边框、透明、`.floating` 层级的 `NSWindow`,用 `NSVisualEffectView` 做毛玻璃效果,靠 `mouseDownCanMoveWindow` 实现随处拖动。一个 30 秒定时器重新计算当前时间块、重绘卡片、通过 `UserNotifications` 发提醒,并在日程文件修改时间变化时热重载。位置和折叠状态存在 `UserDefaults`。无框架、无包管理器、除 `swiftc` 外无构建系统。

## 许可证

[MIT](LICENSE) © 2026 partyfly
