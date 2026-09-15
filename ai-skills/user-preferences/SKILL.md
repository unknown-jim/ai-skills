---
name: user-preferences
description: Personal workflow preferences for all projects — reply in Chinese, clarify unclear goals before acting, isolate changes in a dedicated worktree, keep every changed line traceable to the request, claim completion only with fresh verification output, label architecture advice with sources and failure cases, use printf logs when code analysis is not enough, and suggest new rules or skills only after confirmation. Apply at the start of every session.
---

# User Preferences

Canonical personal workflow preferences for Cursor, Claude Code, Codex, and
opencode. Complements project-level rules. Cursor loads this file via a Settings
pointer; Claude Code loads it from `~/.claude/rules/` after install. Codex /
opencode have no multi-file rules mechanism, so the installer concatenates this
file into each tool's single `AGENTS.md`.

## 回复语言

用中文回复

## 目标与路径

你不能总是假设我非常清楚自己想要什么和该怎么得到。请保持审慎，从原始需求和问题出发，如果动机和目标不清晰，停下来和我讨论。如果目标清晰但是路径不是最短，告诉我，并且建议更好的办法。

「移除 X」「删掉 X」这类请求，默认范围是把 X 连实现带引用一起清干净——X 已经作废时尤其如此，留一份没人引用的实现不是一种合理的中间状态。直接做，不要为「删到哪一层」开选项让我选。真正需要先确认的只有仓库外不可恢复的那部分（含密钥的本机配置、线上数据这类）。

## 改动隔离

写入代码、配置或其它项目文件前，为当前改动流建立独立 git worktree 和专用分支；不要在仓库主 checkout 或默认/保护分支上开发。只读调查可用主 checkout。Claude Code / Codex 建好 worktree 后把对话 workspace 切到该目录再写。Cursor 保持当前 workspace 根不动，对 worktree 用绝对路径（见项目 `.cursor/rules/cursor-subagent-worktree.mdc`）。工作树出现非本任务的意外改动时立刻停止写入并报告。细节见 `engineering-discipline`。

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

## 回报对象

收尾时先确认这活是谁派的。**派活来自另一个会话**（统筹 / 兄弟会话）时，push 之后补一次
会话消息把结论送过去——它读不到你的终端，你在这里写得再详细都到不了它。

触发条件是「**活是谁派的**」，不是「有没有决策要问」：没有分叉的完成回报同样欠它。
派活里「有分叉来问我」和「完成后把结果报回来」是两条独立要求，前者不成立不会豁免后者。
回报带上远端 SHA、**实际**基线、改动了哪些既有测试、以及下游验收的注意事项。
找会话的方法见 `parallel-coordination` 最后一节。

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

用户在纠正工作方式时（慢、把本该直接做的事问回去、走了弯路），**这一回合**把教训写进拥有该流程的 skill/rule，或写进本文件。完成态是文件里的 diff。先过 `writing-for-agents`：已有 skill 同主题加一节，每次都要的进本文件，独立流程才新建。

自己想加、用户没在纠正的新文件，仍然先过 `writing-for-agents` 再写；不要为了「以后可能有用」开空 skill。

## 补充

- 简洁但不丢证据：回答可以短，但路径、命令、测试结果这些证据不能省。
- 本地能查到的不要问：改代码前自己查仓库、实现、验证，再总结；能靠合理努力在本地查到答案的问题不要问。用户已经在纠正流程时，直接改文件，这一步也不问。
- 涉及日期一律用绝对日期，不用"下周四"这种相对表述。
