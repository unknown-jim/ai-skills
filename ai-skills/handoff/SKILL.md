---
name: handoff
description: 把当前对话压成一份交接文档，让下一个会话或另一个 agent 能接着干时用——换 harness、上下文快满、今天到此为止明天继续、或者把实现交给审计方。文档写到仓库外，只给已有产物（方案、审计报告、commit、diff）的路径而不复述内容，带上 worktree / 分支 / HEAD / 真实验证结果 / 未验证项，脱敏，并指明下一个 agent 该先调哪些 skill。触发短语：交接、handoff、写个交接文档、换个会话继续、接力给下一个 agent、上下文快满了先存一下。
---

# 交接文档

把这段对话压缩成下一个 agent 一遍就能接手的东西。它是索引，不是档案。

## 写到哪

**仓库外**——按 `engineering-discipline` 的过程文档规则，走该项目的交接目录（如 `~/work/<project>-handoffs/<task>-<date>.md`）。写完把路径报给用户，不然没人找得到。

**已经有一份 canonical 交接/审计报告的，更新那一份，不要再建一份。** 同一条任务链上并行存在两份交接文档，下一个 agent 一定会读到过期的那份。

## 必须写进去的

坐标和状态那部分照 `engineering-discipline` 的「Task Resource Reuse and Continuation」清单来（任务范围、仓库 / worktree / 分支、基线与当前 HEAD、改动文件、`git status` 与 diff 摘要、实际跑过的验证命令和退出码、没做完的部分、`[UNVERIFIED]` 项、已知风险、做过或故意没做的外部动作），这里不重抄一遍。这个 skill 额外要求两件事：

- **下一步该干什么**，一句话，动词开头。不是"继续这个任务"，而是"把 X 的边界情况补上，然后重跑 Y"。
- **建议调用的 skill**：下一个 agent 开工前该先调哪几个（典型是 `engineering-discipline`，以及走到哪一步就带上 `design-execute-audit`）。它读不到这段对话，不知道你们在用什么流程。

## 不要写进去的

- **已有产物里的内容不要复述**：方案、审计报告、commit message、diff、issue——给路径、哈希或 URL。复述一遍就是造了第二个事实来源，它会跟原件分叉，然后下一个 agent 读到的是分叉后的那份。
- **中间过程不要写**：试过哪些死路，除非它能省下下一个 agent 的时间（"X 方向排除了，因为 <证据>"是有用的，"我先看了 A 又看了 B"不是）。
- **不要下审计结论**。交接文档不是审计报告，不要写 `PASS`。

## 脱敏

API key、密码、token、个人信息一律不进文档。这份东西可能被直接当成下一个 agent 的 prompt，也可能躺在磁盘上很久。

---

来源：改写自 [mattpocock/skills](https://github.com/mattpocock/skills) 的 `handoff`（MIT, Copyright (c) 2026 Matt Pocock），坐标清单沿用本仓库 `engineering-discipline` 已有的定义。
