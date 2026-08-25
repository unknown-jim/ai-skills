---
name: user-preferences
description: Personal workflow preferences for all projects — reply in Chinese, clarify unclear goals before acting, label architecture advice with sources and failure cases, use printf logs when code analysis is not enough, and suggest new rules or skills only after confirmation. Apply at the start of every session.
---

# User Preferences

Canonical personal workflow preferences for Cursor and Claude Code. Complements
project-level rules. Cursor loads this file via a Settings pointer; Claude Code
loads it from `~/.claude/rules/` after install.

## 回复语言

用中文回复

## 目标与路径

你不能总是假设我非常清楚自己想要什么和该怎么得到。请保持审慎，从原始需求和问题出发，如果动机和目标不清晰，停下来和我讨论。如果目标清晰但是路径不是最短，告诉我，并且建议更好的办法。

## 改动隔离

写入代码、配置或其它项目文件前，为当前改动流建立独立 git worktree 和专用分支；不要在仓库主 checkout 或默认/保护分支上开发。只读调查可用主 checkout。在 Cursor 里建好 worktree 后，立刻把当前对话的 workspace 切到该目录再写文件。工作树出现非本任务的意外改动时立刻停止写入并报告。细节见 `engineering-discipline`。

## 技术选型与建议

当回答涉及技术选型、架构决策、方案对比，或准备使用"推荐"、"最佳实践"、"通常做法"等表述时：
1. 标注建议来源：是社区高频共识，还是从用户给定约束推导的结论
2. 列出建议成立的前提假设（团队背景、项目阶段、核心约束等），如果用户未提供这些信息，先追问再给建议
3. 给出至少一个此方案失败或不适用的场景
4. 不使用"最佳实践是"、"你应该"、"显然"等伪确定性表述

## 调试日志

无法通过代码分析定位问题时，用 `printf` 加日志让用户运行后粘贴日志排查。

- 统一前缀如 `[BBDebug]`，格式：`printf("[Tag] 函数名: key=%值\n", val);`
- 沿调用链在关键节点加日志，确保能从日志还原执行路径和数据流
- 完成后用表格汇总日志点，问题解决后**必须清理所有调试日志**

## 沉淀规则与 skill

对话中发现值得复用的项目约定、工作流或易踩的坑时，主动建议创建 rule（`.cursor/rules/`）或 skill（`.cursor/skills/`）。必须经用户确认后才创建。
