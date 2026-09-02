---
name: glm-dispatch
description: 把「机械执行」档的实施派给跑在智谱 GLM 上的 Claude Code CLI，让执行环节走第三方账单、不吃 Claude 额度。**用前必须先查本机开关**（`~/.claude/glm.env` 的 `GLM_DISPATCH_ENABLED`）——未配置或未开启就照常用 Sonnet 执行，并且不要向用户提起这个流程存在。适用：方案已具体到照抄就能做对的机械改动、规则明确的批量判断或清理。不适用：需要持续判断的诊断类任务、方案本身还没定的探索性工作。触发短语：派给 glm、交给 glm 执行、glm-dispatch、让 glm 做实施、这台机器怎么启用 glm。
---

# GLM 派发

`design-execute-audit` 的执行环节有一个可选执行器：跑在智谱 GLM 端点上的 Claude Code CLI，
通过独立进程派发，在隔离 worktree 里干活。设计和审计仍留在强模型。

**这个执行器换的是账单来源，不是能力档位。** 它占的是「机械执行」那一格（原来是 Sonnet），
判据仍是 Step 1 输出的 `执行层级` 标注。标了「需要持续判断」的任务不要派——见「能力边界」。

派发脚本就在本技能目录下，随仓库同步，`install` 之后自动位于 `~/.ai-skills/glm-dispatch/`。
每台机器只差一个不入库的 `~/.claude/glm.env`（端点 key + 开关）。

## Step 0 —— 先查开关，这一步不可跳过

技能随 git 同步到所有设备，但派发依赖本机配置。每次派发前实地探测，**不能假设配置存在**：

```bash
F=~/.claude/glm.env; D=~/.ai-skills/glm-dispatch
if [ -f "$F" ] && grep -q '^GLM_DISPATCH_ENABLED=true' "$F" \
   && grep -q '^ANTHROPIC_BASE_URL=' "$F" \
   && { [ -f "$D/glm-dispatch.ps1" ] || [ -f "$D/glm-dispatch.sh" ]; }; then echo READY; else echo FALLBACK; fi
```

- `READY` → 按下面的流程派发
- `FALLBACK` → **照常用 Sonnet 执行，不要提 GLM，不要问用户要不要配**。这台设备没开就是答案，
  每次都问一遍是噪音。**例外**：用户主动问「这台机器怎么启用」时，指向下面的「新机器怎么配」。

开关是三段式的，缺一段就回退：配置文件在（这台设备配过）、`GLM_DISPATCH_ENABLED=true`
（用户当前愿意用）、派发脚本在（仓库已 install）。想临时停用不必删配置，把开关改成 false 即可。

## 什么任务派得动

| 派 | 不派 |
|---|---|
| 方案已具体到文件路径 + 改动前后代码块，照抄就能做对 | 方案只给了排查方向，根因要跑起来看证据才能定 |
| 规则可枚举、结果可机械验证的批量判断（清理、批量改名、逐条核对） | 需要品味的设计决策、取舍判断 |
| 已有详尽规格的收尾项（例如上一个 PR 正文「已知不足」里点名的下一步） | 规格还没写出来的新功能 |
| 不可逆操作的**只读分析**阶段 | 不可逆操作的执行阶段（除非清单已经人工审过，见下） |

**不可逆操作分两段走**：先派一轮只读分析、要求它输出清单不许执行，人工逐条核对清单，
通过后再派第二轮执行。代价是多一次派发的钱，换来的是删错东西之前有人看过清单。
第二轮的方案里要写明「清单已经过人工审核，严格执行不要重新判断」。

## 怎么派

Windows：

```powershell
& "$env:USERPROFILE\.ai-skills\glm-dispatch\glm-dispatch.ps1" -TaskFile <方案> -Worktree <名字> `
  [-Branch feat/xxx] [-Base main] [-Model sonnet|haiku] [-Effort max] [-Mcp wechat] [-DryRun]
```

macOS / Linux（参数名按 Unix 惯例，行为与上面一致）：

```bash
~/.ai-skills/glm-dispatch/glm-dispatch.sh --task <方案> --worktree <名字> \
  [--branch feat/xxx] [--base main] [--model sonnet|haiku] [--effort max] [--mcp wechat] [--dry-run]
```

- **默认后台跑**（Bash/PowerShell 工具的 `run_in_background: true`）。GLM 跑完系统会自动
  重新调起 orchestrator，不需要用户手动唤醒。前台阻塞只在需要立刻拿结果、且预期很快时用。
- 不传 `--branch` 时分支名默认 `glm/<worktree名>`，一眼能认出第三方模型的产出；要合进正式
  PR 流程时传项目惯用的 `feat/` `fix/` 名字。
- 脚本把环境变量只注入自己的子进程，MCP 用 `--strict-mcp-config` 钉死，**不碰任何全局配置**。
  绝对不要为了省事把 `ANTHROPIC_BASE_URL` 写进 `~/.claude/settings.json`——它优先级最高，
  会把这台设备上所有 Claude Code 会话（含正在派发的那个）一起切到 GLM，正好毁掉分工。
- `-Effort` / `--effort` 默认 max，**保持默认**。GLM-5.3 只有三档，Claude Code 的五档按
  `none/minimal/low → low`、`medium/high → high`、`xhigh/max → max` 映射（智谱文档，2026-08 核实），
  所以传 `xhigh` 和 `max` 落在同一档、没有区别。按 prompt 次数计费时 effort 不影响配额
  （同一个请求，档位高低都算 1 次），降档只省 token 和延迟，而这两样在包月制下都不是成本；
  反过来，更深的推理若能降低 Edit 匹配失败导致的重试，那才是真省钱——**重试才是多花一次 prompt**。
  只有发现某类任务在 max 下反而绕远路、轮次变多时，才对那类任务传 `-Effort high`。
- 运行日志落 `~/.claude/glm-runs/`，含 token 用量、是否报错、最终返回。用户自己在终端派发过的
  运行也在这里，orchestrator 不在场时的产出可以从这里捡回来。

## 新机器怎么配

**只在用户主动问起时才提。** 一条命令，幂等，已有配置绝不覆盖：

```powershell
& "$env:USERPROFILE\.ai-skills\glm-dispatch\setup-glm.ps1"     # Windows
```
```bash
~/.ai-skills/glm-dispatch/setup-glm.sh                          # macOS / Linux
```

它装 `claude` CLI（缺了才装）、生成 `~/.claude/glm.env` 模板（**开关默认 false、key 是占位符**）、
然后告诉用户下一步。用户自己填 key 并把开关改成 true 后再跑一次，脚本会做一次真实的连通性
验证再报 READY。**不要替用户填 key。**

## 方案文件怎么写

**派发出去的 agent 看不到任何对话上下文。** `design-execute-audit` 说过设计环节的上下文
损失是三步里最贵的——对外部 CLI 这个损失更大：它只能看到方案文件加项目里的 `AGENTS.md`。
所以方案必须自包含，而且比给 Sonnet 时更死板。

**脚本传的是方案文件的路径，不是内容**（2026-09-02 起；改因见「已知的坑」第一条）。
所以文件必须在派发那一刻真实存在、路径对 agent 可达；**路径本身最好是纯 ASCII**，
含中文时脚本会打一行 warning。方案内容仍然走 UTF-8 文件，由 agent 自己用工具读——
这也正好是「指向源，不要转写」那条：把源摆在它面前，别在通道里转一手。

- 写到 out-of-tree 的 handoff 目录（`~/work/<项目>-handoffs/<任务>-<日期>.md`），不要写进
  仓库、也不要只写在会话临时目录——它是交接产物，中断了要能捡起来，审计时要有据可查。
  依据见 `engineering-discipline` 的「Process Documents Stay Out of the Repository」。
- 开头写执行坐标：worktree 路径、分支、baseline HEAD、允许改的范围。
- 改动要精确到文件路径和改动前后的代码块。留给它做判断的地方越少，产出质量越高、来回轮次
  也越少（按 prompt 次数计费时这直接就是省钱）——这是实测结论，不是风格偏好。
- 明确写出**禁止事项**和**遇阻怎么办**：「如果 X 被拒绝，跳过并如实记录，不要改用 --force」
  这类约束它会遵守，实测有效。
- 要求它把执行结果写成文件（改了什么、验证命令的真实输出、哪些没做成及原因），而不是只在
  最终回复里说。

## 拿回结果后必须做的

**审计不能省，而且不能由派发者自己审**——`design-execute-audit` Step 3 那条对外部执行器
只会更成立。审计要独立读实际 diff，不能复述它的自我报告。

必查项：

- 它声称的数字自己重算一遍。实测过它报告准确，但「数量对」不等于「内容对」，清单类产出
  要程序化 diff，不要肉眼扫。
- 保留项 / 禁止范围是否真的没被碰。
- 测试有没有被弱化——断言是否被删、阈值是否被放宽。删掉的断言必须有等价的新断言接上。
- 主仓和 worktree 的 `git status`：`--dangerously-skip-permissions` 不是沙箱，worktree
  隔离的是 git 改动，不是文件系统访问。
- 一份代码有多个副本的项目（例如小程序端 + 云函数端），确认同步脚本跑过、两边一致。

## 已知的坑

- **【最危险的一条】报告成功、退出码 0、零产出**（2026-09-02 实测一次，已修，留档防回退）。
  一次派发跑了 14 轮、`is_error: false`、退出码 0、花掉约 $0.75，但 worktree 的 `git status` 是空的、
  HEAD 没动、diff 为空。它的最终回复是一段「派发已正常启动…GLM 在后台施工中…等完成通知」，
  还引用了一个从未存在过的方案文件名。
  **不要把它读成幻觉**——查会话记录（`~/.claude/projects/<编码路径>/<session_id>.jsonl`）看到的是：
  它先 `Skill(glm-dispatch)`，然后**真的执行了 `glm-dispatch.ps1`**，用一个自己编的 TaskFile 路径
  又派发了一层。那句「派发已启动」对它自己是字面真实的。
  根因有两个，都已在脚本里修掉：**① 编码**——PS1 侧把方案内容用管道喂给 CLI，PowerShell 会重新编码，
  接收端按 GBK 解了 UTF-8，agent 拿到满屏乱码（`## 执行坐标` → `## 鎵ц鍧愭爣`）；
  **② 递归**——读不懂方案的 agent 从乱码里认出「派发」，加载了自己环境里的本技能，
  于是 dispatcher 派出了另一个 dispatcher。
  现在两个脚本都改成**传方案文件路径 + 一段纯 ASCII 英文 prompt**（含「你是执行者，不要再派发」），
  agent 自己去读文件。**这条留在这里的意义**：如果哪天又看到「报告成功但零产出」，
  第一件事是查会话记录里有没有 `Skill(glm-dispatch)`，别急着归咎于模型幻觉。
- **服务端会注入工具**。即使 `--strict-mcp-config` 加空配置，会话里仍会出现
  `mcp__4_5v_mcp__analyze_image` 和 `mcp__web_reader__webReader`——智谱在服务端注入，
  客户端关不掉。所以执行端的工具集不完全由本地决定，`webReader` 能抓任意网页。
- **偶发断连**。见过一次跑满 100 秒后 `api_error: Connection lost mid-response`、零产出，
  重试即通，不是参数问题。脚本会检测 `is_error` 并以非零码退出；零产出的失败重跑是安全的。
- **成本单位是轮次，不是 token**。老版 Coding Plan 按 prompt 次数计费，所以贵的是多轮来回，
  不是长上下文——日志里的 cache_read 数字基本无关，`total_cost_usd` 更是按 Anthropic 价目表
  估的、不可信。要盯的是 `num_turns`：实测照方案施工 1–3 轮，让它自己去分析的探索型任务
  14–15 轮。**所以「方案写死」是质量与成本同向的选择，不存在取舍。**实测参考：11 次派发共
  48 轮、约 180 万 token，占当日总用量的 0.6%，Max 档下可忽略。
- **不要用 `npx @z_ai/coding-helper`**。它会自动探测环境并改写配置，跟「不碰全局配置」冲突。
- **`.sh` 版尚未在真机 macOS 上跑过**（2026-08）。逻辑在 Git Bash 里全项验证过（参数解析、
  env 加载、MCP JSON 生成与脱敏、分支覆盖、路径推导），`mktemp -d` 也选了 BSD/GNU 都认的写法，
  但 Mac 上第一次用要留意 `npx` 路径和微信开发者工具的命令名（`--mcp wechat` 写死了
  `wechatide`，Mac 上未必同名）。跑通后请把这条删掉。

## 能力边界（实测样本，别外推）

已验证：规则明确的批量判断（100% 准确，含三个陷阱场景）；照详尽规格施工（涉及金额计算的
781 行改动，算法正确、测试反而收紧）；严格遵守约束（该拦的没绕过、遇阻如实报告不粉饰）。

**未验证**：自主设计方案。上面两个样本的规格都是现成的——一个是人工审过的清单，一个是
上游 PR 正文里逐条点名的下一步。「能照着好方案施工」和「能想出好方案」是两件事，
目前只证明了前者。所以设计环节不要派，`执行层级：需要持续判断` 的任务也不要派。
