# 找人与消息

SKILL.md「跨会话通信的硬约束」、第 3 节权限边界和 §0 第 5 件指到这里：找不到人、投递结果拿不准、要叫停或作废一条 chip、
有兄弟统筹在跑时读。下面引的官方说明是 2026-10-06 读到的工具描述原文；工具会改版，用前以当时的描述为准。

## 找人

- 会话 id 只取两处：工具输出（`get_session self`、`list_sessions` / `search_session_transcripts` 结果里的 sessionId）和来信的 `from`。
  - `get_session`：「the literal string "self" for this session」。
  - SendMessage：「To reply to an incoming message, copy its `from` attribute as your `to`.」
  - `mcp__ccd_session_mgmt__send_message`：「Prefer `SendMessage` with `to` set to the target's `local_...` session id
    (the id, not its display name)」。
- 下面这些都被当成过会话 id，都不是：scratchpad 路径里的 uuid（转录 / 工作目录 id）、spawn_task 返回的 task_id（补零也不是）、
  转录文件名、缺 `local_` 前缀的 uuid、占位 id。`ListAgents` 的 `name [ref]` 是 SendMessage 的另一种地址，只覆盖当下活着的 peer、
  代号认不出是谁，派活里不用；它的 ref 也翻不成 sessionId（从转录头反查出 uuid 再发，仍是 not found，2026-09-08）。
- 找不到人时依次试：
  1. 共享文档坐标里登记的 sessionId；
  2. 来信的 `from`；
  3. `list_sessions` 按 cwd＋isRunning 找（cwd 也能核对下游是不是在自己的 worktree 里写）；
  4. `search_session_transcripts` 搜派活原文里最独特的一句——派活方的转录里必然有原文，几乎不误命中；
  5. 集成分支或 chip 分支 commit message 里登记的 id。

  都不行，按派活的决策路径落盘继续，等对方来信再抄它的 `from`。由统筹会话起出来的 chip，`get_session self` 会返回
  `parentSessionId`，`mcp__ccd_session_mgmt__send_message` 在同一 linked family 里也收 `parent`（两处都是工具说明原文，未实测），
  用前对一次标题。
- 标题只作交叉核对：会被编错，也会中途改名。发关键指令前，id 哪怕「记得」也用 `list_sessions` 对一次标题——id 存在不等于是那个人。
- 自证：给自己的 id 发消息会被工具拒（「Refusing to send a message to the current session.」），可以确认手上那个 id 是不是自己。
- 收到「停下 / 回退 / 你写错了」先验它是不是给你的：拿信里的专有符号去数自己 diff 的**新增行**（`^+`；裸 grep 会被上下文行
  假命中），不是就退回发信方并附正确 id（一条「立刻停下」投错了人，收方先验了才没去回退别人的活，2026-09-07）。

## 投递结果

- 官方说明：
  - SendMessage：「messages enqueue and drain at the receiver's next tool round」「A successful send means the message reached
    that session, not that its Claude read it」。权限模式不同的会话会把消息压给它的用户审批（可能过期），会话也可以直接拒收；
    Remote Control、云端、Claude Desktop 会话「nothing reports back, so never treat silence as agreement」。
  - `mcp__ccd_session_mgmt__send_message`：「"delivered" means that session's turn has started on your message; "queued" means
    it is waiting behind that session's current work」；无人值守的会话（定时任务、远程派发）既不能用它，也收不到。
- 实测的读到时机和「下一轮工具调用」不总一致，所以不写死：
  - 对方一个回合从 02:35 跑到 05:24，统筹 03:26、03:38、04:47 发的 4 条在 05:24 一次性入队，另两条泳道因此空等约 2 小时
    （2026-09-24）；
  - 统筹挂着问题卡 7 小时 12 分，其间 9 条泳道消息在问题卡返回后才一起进来；统筹起了一条跑满 600s 的前台 Bash，
    一条「暂时不要合」发出约 15 分钟后才被读到（2026-09-29）。
- 确认对方读到了：等它在回信里引用编号或 SHA（「收到，<SHA> 不合」）；或用 `list_events` 读它最近的转录，看有没有消费这条。
  共享文档里「已让 X 做了 Y」只能由对方的回执背书，没有就写「已发出，未确认」并留一条复核动作。
- 想知道对方什么时候停下：SendMessage 传 `notify_when_idle: true`（只能从主会话传），对方下次空闲时来一条通知；
  不轮询 `ListAgents`，不发「好了没」。
- 多步交付的 chip：每步 push、回报之后结束回合，等统筹回执再继续，统筹的追加项才进得去；完成回报列出「已读到的统筹追加项编号」。

## 消息首行

收件方的人只看得到第一行预览（官方：「The recipient's human sees only the FIRST LINE as a one-line preview」），首行写类型和锚：

| 类型 | 首行示例 |
|---|---|
| 派活 / 再派 | `[派活] 泳道 B 号段 B-D01–B-D09`；`[再派·取代 <旧锚>] …` |
| 报到 | `[报到] 泳道 B <sessionId> <worktree> <分支>` |
| 决策请求 | `[决策请求] B-D03 @ feat/x@1a2b3c4` |
| 知会·不用回 | `[知会·不用回] 集成分支前移到 5d6e7f8，和你的所有权文件无交集` |
| 进度·非完成回报 | `[进度·非完成回报] feat/x@9a8b7c6，第 2/3 步` |
| 完成回报 | `[完成回报] feat/x@<rev-parse 原样 SHA> 可以合` |
| 订正 | `[订正] G253：原裁「…」改为「…」，作废 <旧锚>` |
| 叫停 / 作废 | `[叫停] 泳道 C：停在当前提交，等 G260 定稿`；`[作废] feat/y@<SHA>` |
| 接管 | `[接管] 泳道 B 新 <sessionId> 接手旧 <sessionId>，起点 <分支>@<SHA>` |

改判、订正要自含要点，不写「见上一条」——上一条可能还没读到，或者读到的是更早一版。

## 叫停与作废

先发叫停，让它停在当前提交；再要它用命令交出远端和本地的状态（`git status`、`git rev-parse HEAD`、`git ls-remote`），
只交读数不交结论——它的读数可以给在跑的另一条当独立的一条腿（「你停之后交出来的东西比很多完整交付还有用」，2026-09-08）。
作废已推的分支：消息里声明作废的 SHA，统筹之后只按 SHA 合；删远端分支按 `user-preferences`「对外动作」要用户点头，统筹事后
认可不算授权。被撤换的会话在共享文档的身份表登记作废；叫停返回 queued 时，看结果面（worktree、分支删没删）核实，不看自己的发送记录。

## 本统筹之外的会话

切分之前，和在相邻领域里正在跑的会话（兄弟统筹也算）对一次：

- 把共享面清单发给对方：文件交集、行为依赖、踩过的坑；
- 约定合并顺序和后合者的责任（两个 MR 谁后合入，谁的预算门禁就会超红）；预算型门禁双方都留余量；
- 开工前和合并前，对其它活跃的集成分支各用 `git merge-tree` 试合一次。

相邻会话给的行为依赖要在泳道启动之前拿到：启动之后才到，泳道 3 被重派、出了重复 chip，往来 21 条消息（2026-09-15）。

## 其它 harness 与子代理

- Codex：`mcp__codex_app__list_threads`（有 title / cwd / status）→ `mcp__codex_app__send_message_to_thread`；投递语义没核过，
  一律当「已发出、未确认」。
- Cursor 没有跨会话消息通道：chip 只能是 Task 子代理，或者只靠共享文档。
- 跨 harness 互相看不见会话列表，统筹和 chip 必须同 harness。
- 子代理（Claude Agent、Cursor Task）：最终输出就是回报；它发的跨会话消息走父会话的地址，回信也落到父会话，子代理收不到；
  统筹换了会话，旧子代理接不回来，要重派。
