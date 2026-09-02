---
name: engineering-discipline
description: Working discipline for agents making non-trivial code changes — isolated worktree/branch per change stream, handoff continuity across investigation → implementation → audit → re-audit, keeping process documents out of the repository, writing audit-to-implementation prompts, and calibrating audit severity. Use when starting substantial code work, handing work between agents or sessions, writing a prompt for another agent to implement or re-audit something, or deciding how severe a review finding is.
---

# Engineering Discipline

Cross-project working rules for coding agents. They exist because each one has a
concrete failure it prevents: a second writer silently clobbering an isolated
worktree, a stale investigation report sending a later agent to fix a bug that no
longer exists, an audit prompt so padded with boilerplate that the receiving agent
misses the actual objective, a P1 label spent on a cosmetic gap.

Adapt paths and tool names to your setup; the invariants are what matter.

## Engineering Workflow

- Read existing project rules and skills before changing behavior.
- Prefer evidence-backed debugging: logs, xlog, tests, git history, commit hashes, and exact file paths.
- Do not overwrite user changes. Check git status and work with the current dirty tree.
- Keep durable memory only for findings that will affect future decisions; do not preserve temporary guesses.

### Task Resource Reuse and Continuation

- The always-on one-liner lives in `user-preferences` and any project always-on rule; this section is continuation, handoff, and concurrent-writer detail.
- For any task that will modify code, configuration, or other project files, do not develop directly in the repository's primary checkout or on its default / protected branch. Use one isolated worktree and dedicated branch for each logical task or change stream.
- Treat the **logical task chain**, not an individual Codex thread, Agent, or IDE session, as the worktree owner. Sequential phases such as investigation, implementation, audit, prompt-driven follow-up, test repair, and re-audit should reuse the same worktree and branch so evidence and delivery state remain continuous.
- Treat a user request or implementation prompt as an explicit handoff when it names the exact worktree and branch, identifies the baseline or current HEAD, says the next phase should continue there, and the previous phase has stopped writing. The prompt itself may state that it constitutes the handoff; do not require a second user confirmation merely because execution moved to a new thread or Agent.
- Do not infer handoff from task similarity, a matching directory or branch name, filesystem quietness, or a shared report alone. If another writer is active, the prompt requests an independent parallel implementation, or writer status is genuinely unresolved, use a separate worktree and branch.
- Before the first substantive command in a handed-off worktree, verify and report its exact path, branch, HEAD, and `git status --short`. Compare them with the prompt or canonical report. Expected recorded changes may be continued; unexpected changes or mismatched coordinates must be investigated before writing.
- Read-only inspection may use the primary checkout. Audit a changing implementation only after it reaches a stable snapshot. Once a phase is stable, prefer handing the same task worktree to the auditor or follow-up implementer instead of cloning the task state into another worktree.
- Continue in the same task resources across retries, follow-up fixes, test failures, re-audits, and new Codex tasks when the continuation and coordinates are explicit. Create a replacement only for a genuinely parallel change stream or when the existing resource is damaged, inaccessible, unsafe, or has an unresolved concurrent writer. Record the reason and replacement path; never discard, overwrite, copy from, or strand another task's uncommitted changes.
- If HEAD, status, diff, file mtimes, or test inputs change unexpectedly during inspection or validation, treat that as evidence of an unauthorized concurrent writer: invalidate results, stop commands immediately, do not produce a verdict or repair prompt against that worktree, and report the ownership conflict.
- Apply fixes incrementally in the same task worktree and branch, and re-audit the same resulting artifacts. When a stable report path already exists, update that report with the current commit, actual validation results, and remaining issues rather than creating a parallel or stale report.
- When implementation will be continued or re-audited in another task or agent context, maintain exactly one canonical handoff report. Reuse an existing audit or delivery report when available; otherwise create one at a stable, explicitly reported path outside tracked source. Start it before implementation and update it throughout the task so interrupted work remains recoverable.
- Record the task scope, repository/worktree/branch, audited baseline and current HEAD, changed files, git status and diff summary, actual validation commands with exit codes and results, incomplete work, `[UNVERIFIED]` items, known risks, and any external actions taken or intentionally omitted. Do not claim an independent audit verdict such as `PASS`.
- Treat the handoff report as an orientation index, not audit evidence. A re-auditing agent must first confirm that its recorded HEAD and working-tree state are current, then independently inspect the diff and rerun proportionate validation. If the report is stale or mismatched, update the same report after verification rather than creating another one.
- Creating an isolated worktree, branch, directory, or report does not grant permission to push, open an MR / PR, delete an older resource, or perform any other external or destructive action unless the user explicitly requested it.

### Process Documents Stay Out of the Repository

- Process documents — investigation reports, audit reports, design proposals, handoff/delivery reports, migration checklists, task-scoped prompts — **must not be committed to the repository by default**, even when a project rule points at an in-repo directory such as `docs/investigations/`. Write them to an out-of-tree handoff location for that project (e.g. `~/work/<project>-handoffs/<task>-<date>.md`).
- Rationale: the repository holds durable assets only. Process material is single-use, nobody prunes it, and its conclusions decay fast — a later agent reads a stale report and fixes a bug that no longer exists. Relocating such files inside the repo does not change that failure mode.
- What may be committed: code, tests, project rules and skills, long-lived specifications and design documents, and postmortems. When in doubt, keep it out.
- **If a document genuinely needs to be committed, ask for approval before committing it.** State what the file is, why it belongs in the repository rather than the handoff directory, and where it will live. Do not commit first and offer to remove it afterwards.
- Carry the same discipline into merge requests: put per-change evidence (gap definition, mp/upstream `file:line`, failure scenario) into the individual commit messages, which travel with the code, and say in the MR description that the full report is available on request instead of linking an in-repo path.
- If a process document was already committed by mistake and the branch has no other consumer, drop it with `git reset --hard` plus `git push --force-with-lease` rather than adding a revert commit, then fix any MR description or comment that referenced it.

### Long-Lived Plan Documents

Most process documents are single-use: written once, dated, never edited (`<task>-<date>.md`). Those do not rot from accretion. The exception is the rare document that must survive the whole task chain and be **rewritten repeatedly** — a phased plan, a roadmap, a migration checklist. That one accretes until the remaining work is unfindable and every new agent burns its context reading history instead of working.

- Diagnose the cause correctly: an agent appends because **deleting feels lossy and appending feels safe**. Instructing it to "stay concise" does not change that trade-off. Make deletion provably safe instead, by guaranteeing elsewhere-existence and saying where.
- **Put a "what does not belong here, and where it lives" table at the top of the document.** This is the single highest-leverage intervention: an agent that can see that rationale lives in the review, status in `git log`, and per-round handoff in the dated files will delete from the plan. One that cannot, hoards.
- **Do not create a "Done" / "Completed" / "Changelog" section.** It is the largest single accretion vector. Delete finished items outright rather than marking them `[x]`. Give each item a stable ID, put the ID in commit messages, and derive status with `git log --grep=<id>`. Maintained status rots; derived status cannot.
- **State a line budget as a number** ("over 150 lines means this document is broken"). A number is enforceable; "keep it short" is not.
- **When over budget, require a rewrite from current state, not a diff.** Rewriting forces omission; diffing only ever adds.
- **Separate the read path from the write path.** Hand the implementing agent a scoped single-use prompt covering one phase, never the whole plan. An agent that has not read the whole plan cannot bloat the whole plan.
- **Link, never copy.** A rationale duplicated into the plan will diverge from its source and then contradict it. One fact, one home.
- Write these rules into the document itself, not only into the project's conventions. In-file instructions are followed far more reliably than external ones by whichever agent opens the file next.

### Audit-to-Implementation Prompt Design

- Write implementation prompts as concise, task-local deltas on top of the applicable `AGENTS.md`, project rules, skills, and these user preferences. Do not copy generic workflow rules into every prompt; reference them and restate only task-specific exceptions, coordinates, or safety boundaries that the implementation agent could otherwise miss.
- For a sequential audit-to-fix or re-audit handoff, default to reusing the audited task's existing worktree and branch. Put the exact path, branch, baseline/current HEAD, expected status, and handoff statement in the prompt; this is sufficient authorization for the receiving thread to continue without creating another worktree.
- Require a new worktree only when the previous writer remains active, the user requests parallel or independent work, the task scope is a separate change stream, or the target worktree fails coordinate/status verification. When writer status is genuinely unknown, report the blocker instead of silently choosing either reuse or replacement.
- Optimize for information density, not minimum length. Preserve evidence, exact task resources, required behavior, negative cases, validation commands, and delivery expectations; remove background narrative and repeated constraints that do not change implementation decisions.
- For a prompt covering one or two focused findings, treat roughly 3,000–4,000 Chinese characters as a review threshold rather than a hard limit. If it grows beyond that, compress or move durable detail into the existing audit or delivery report unless the additional complexity is demonstrably necessary.
- Prefer five compact sections: execution coordinates; findings with evidence; required behavior and counterexample tests; scope and validation gates; delivery artifacts and remaining blockers. State each constraint once in its most relevant section.
- Separate verified facts, required outcomes, and optional implementation hints. Specify a particular code shape only when the task is fragile or the evidence rules out reasonable alternatives; otherwise leave implementation freedom and judge the result by behavior and tests.
- Include only validation commands and baselines that are necessary for this change. Do not hard-code historical pass counts as future acceptance thresholds when the suite can legitimately grow; require zero new failures or skips and record the actual current result instead.
- Consolidate report and final-response requirements. Prefer updating one stable task report with full evidence, while the final response contains only status, commit or working-tree state, validation summary, report path, and residual risk.
- Before handing off the prompt, remove duplicated prohibitions, repeated resource paths, stale historical detail, and instructions already guaranteed by loaded rules. Confirm that an implementation agent can identify the objective, exact failure signals, permitted scope, and definition of done in one quick pass.

### Orchestrator Edits Need Their Own Commit Boundary

When the orchestrator fixes something itself after an implementation agent has delivered — a defect spotted while reviewing the diff, a wording correction, a small guard — commit or `git stash create` the agent's delivered state **before** touching it.

The reason is auditability, not ceremony. With everything sitting uncommitted in one working tree, the auditor cannot diff "what the agent delivered" against "what the orchestrator changed on top"; it can only audit the final state and take the orchestrator's word for which part is whose. Observed 2026-09-02: the auditor's strongest available evidence was mtime distribution, which corroborated the account but proved nothing.

This matters most precisely where self-review is weakest — the orchestrator's own edits are the one part of the diff that no independent party has seen before it ships. Give the auditor a boundary it can verify, and tell it explicitly which side of that boundary you wrote.

### Audit Calibration

- Calibrate severity by supported-path reachability, likelihood, and user impact: reserve P1 for reproducible crashes, data loss, security issues, or core-flow failure; use P2 for real user-visible defects; treat rare timing residue, cosmetic issues, and test-only gaps as P3/follow-up.
- Block only on findings caused by the current change or directly preventing the requested behavior. Record unrelated discoveries and pre-existing debt separately; do not expand the original definition of done.
- Treat missing tests as confidence gaps, not automatic production defects. Prefer “primary issue passes with follow-ups” once the requested behavior is fixed.
- Match validation to risk: run focused tests per iteration, the full suite once before final delivery unless shared low-level code changed, and perturbation only for fragile high-risk invariants.

