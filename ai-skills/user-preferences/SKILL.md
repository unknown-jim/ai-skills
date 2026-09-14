---
name: user-preferences
description: Personal workflow preferences for all projects — reply in Chinese, clarify unclear goals before acting, isolate changes in a dedicated worktree, keep every changed line traceable to the request, claim completion only with fresh verification output, label architecture advice with sources and failure cases, use printf logs when code analysis is not enough, and suggest new rules or skills only after confirmation. Apply at the start of every session.
---

# User Preferences

Canonical personal workflow preferences for Cursor and Claude Code. Complements
project-level rules. Cursor loads this file via a Settings pointer; Claude Code
loads it from `~/.claude/rules/` after install.

## 回复语言

用中文回复

## 目标与路径

你不能总是假设我非常清楚自己想要什么和该怎么得到。请保持审慎，从原始需求和问题出发，如果动机和目标不清晰，停下来和我讨论。如果目标清晰但是路径不是最短，告诉我，并且建议更好的办法。

「移除 X」「删掉 X」这类请求，默认范围是把 X 连实现带引用一起清干净——X 已经作废时尤其如此，留一份没人引用的实现不是一种合理的中间状态。直接做，不要为「删到哪一层」开选项让我选。真正需要先确认的只有仓库外不可恢复的那部分（含密钥的本机配置、线上数据这类）。

## 改动隔离

写入代码、配置或其它项目文件前，为当前改动流建立独立 git worktree 和专用分支；不要在仓库主 checkout 或默认/保护分支上开发。只读调查可用主 checkout。在 Cursor 里建好 worktree 后，立刻把当前对话的 workspace 切到该目录再写文件。工作树出现非本任务的意外改动时立刻停止写入并报告。细节见 `engineering-discipline`。

## 改动范围

每一行改动都要能追溯到我的请求。

- 不顺手“改进”相邻的代码、注释或格式；风格跟现有代码保持一致，哪怕你有更好的写法。
- 只清理**你自己**造成的孤儿（改完之后没人用的 import、变量、函数）。发现原有的死代码，说一声，不要删。
- 不做没要求的抽象、配置项和“以后可能用得上”的灵活性，也不为不可能发生的情况写错误处理。

## 完成声明

没有在**当前这条消息里**跑过验证命令，就不要说"完成了 / 修好了 / 测试通过"。先想清楚哪条命令能证明这句话，跑完整的那条，读输出和退出码，再带着证据下结论。

| 要声称的 | 需要的证据 | 不算证据 |
| --- | --- | --- |
| 测试通过 | 本次测试命令的输出，0 失败 | 上一轮跑过、"改完应该就过了" |
| 构建通过 | 构建命令退出码 0 | lint 过了 |
| bug 修好了 | 原始症状按复现步骤跑一遍，不再出现 | 代码已按方案改完 |
| 子代理干完了 | 自己看 diff / `git status` 确认改动真的落地 | 子代理回复"已完成" |
| 回归测试真的有效 | 把修复回退掉，测试变红；恢复，测试变绿 | 测试跑过一次是绿的 |
| 需求满足了 | 逐条对照需求清单 | 测试全绿 |

没有可跑的验证命令时（纯文档、纯配置），如实说明实际做了什么核对——读了哪些文件、比对了什么——不要把"我看过了"讲成"已验证"。半截验证、"应该没问题"、"看起来是对的"一律按未验证处理，直接报告当前真实状态：没验证不丢人，声称验证过了才是问题。

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

对话中发现值得复用的项目约定、工作流或易踩的坑时，主动建议创建 rule（`.cursor/rules/`）或 skill（`.cursor/skills/`）。必须经用户确认后才创建。写之前先过 `writing-for-agents`：它管这条规则该做成独立 skill、并进本文件，还是当作现有 skill 的一节。
