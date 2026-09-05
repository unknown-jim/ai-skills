# ai-skills

Ten user-level skills for coding agents (Claude Code, Cursor, Codex, and
anything else that reads a per-user skill directory), plus always-on personal
preferences and an idempotent installer that symlinks them into place.

```
ai-skills/
  user-preferences/         always-on personal workflow (language, scope, verification)
  grilling/                 interrogate an unclear request into a shared design
  design-execute-audit/     design → execute → audit loop across two model tiers
  test-driven-development/  red → green → refactor, and when to skip it
  engineering-discipline/   worktree isolation, finishing, ADRs, audit calibration
  parallel-coordination/    one session coordinating several parallel worktree chips
  handoff/                  compact a session into a pickup document
  retro/                    mine a session for environment improvements
  writing-for-agents/       writing SKILL.md, AGENTS.md, and agent-facing prompts
  send-email/               one plain-text email, on explicit request only
  glm-dispatch/             Claude Code only: mechanical execution handed to GLM
install.sh                  Unix/macOS: creates the symlinks; idempotent, backs up real files
install.ps1                 Windows: same layout via directory junctions
```

## Install

Unix / macOS:

```bash
git clone <this-repo> ~/ai-config && ~/ai-config/install.sh
```

Windows (PowerShell):

```powershell
git clone <this-repo> $HOME\ai-config; & "$HOME\ai-config\install.ps1"
```

Re-run it any time; existing correct links are left alone and a real file in
the way is moved to `<name>.bak-<timestamp>` rather than overwritten.

After install, Cursor discovers the workflow skills from `~/.cursor/skills` (and
the shared `~/.agents/skills`) in every workspace. Claude Code still uses
`~/.claude/skills`. `user-preferences` is not a discoverable skill: Claude Code
loads it from `~/.claude/rules/` every session. Cursor needs a single Settings
User Rule that reads `~/.ai-skills/user-preferences/SKILL.md`.

## Always-on preferences

**`user-preferences`** — personal workflow that should apply in every session:
reply in Chinese, stop when the goal is unclear, isolate every change stream in
its own worktree, keep every changed line traceable to the request, refuse to
call anything done without verification output from this turn, label architecture advice, instrument with `printf` when analysis is
not enough, and suggest new rules or skills only after confirmation. Edit this file to change behavior in both
Cursor and Claude Code.

## The skills

**`engineering-discipline`** — rules for agents making non-trivial code changes.
One isolated worktree and branch per change stream; the *logical task chain*
(investigation → implementation → audit → fix → re-audit) owns that worktree
rather than any single session, so a handoff prompt naming path, branch, and
baseline HEAD is sufficient authorization to continue there. Process documents
(investigation reports, audit reports, handoff notes) stay out of the repository
— they are single-use, nobody prunes them, and their conclusions decay fast
enough that a later agent will read a stale one and go fix a bug that no longer
exists. Also covers how to write an audit-to-implementation prompt that another
agent can act on in one pass, how to close a change stream once it is green (the
integration choice is the user's, and a refused `git worktree remove` means those
files exist nowhere else), when a decision earns an ADR (hard to reverse,
surprising without context, a real trade-off — all three or skip it), how to
calibrate finding severity so P1 keeps meaning something, and how to receive a
review: a finding is a claim about the codebase, so verify it before implementing
it and push back with reasoning rather than dropping it silently.

**`design-execute-audit`** — for work that warrants more assurance than a single
pass: a strong model designs, a cheaper model executes mechanical changes
(escalating back when the work needs sustained judgment), a strong model audits,
and failures go back with specific problems until they pass or hit an iteration
cap. Includes the model mapping per harness, because copying Claude model
aliases into another tool's slug namespace is the most common way to break it.

**`glm-dispatch`** — Claude Code only. Hands the *mechanical execution* tier of
`design-execute-audit` to a `claude` CLI pointed at Zhipu's GLM endpoint, so that
tier bills to a third party instead of your Claude quota. Gated on a per-machine
switch (`GLM_DISPATCH_ENABLED` in `~/.claude/glm.env`) that the skill probes
before every dispatch: a machine that never configured it falls back to Sonnet
silently rather than nagging you to set it up. Design and audit stay on the
strong model — swapping the executor changes who pays, not the capability tier.
Not linked into Cursor, which has no `claude` CLI to dispatch to.

**`parallel-coordination`** — for one session coordinating several worktree
"chips" that all deliver into a shared integration branch. Splits work along
file/token ownership rather than surface position, so conflicts happen at the
split line instead of inside it; the five-part handoff prompt adds a decision
path (scope, ownership, verification criteria, and known pitfalls are covered
by `engineering-discipline`) so a chip that cannot decide something bypasses
the coordinator rather than stalling on it. Decisions get written into the
shared document, not just relayed in messages — cross-session messages are
rate-limited and arrive out of order, the document is the only thing everyone
re-reads. The coordinator can rule on technical calls and merge order but
cannot approve a push, open a PR, or message anyone outside the session. Use
`engineering-discipline` for a single change stream, `design-execute-audit`
for a straight-line design → execute → audit pass, and `handoff` to hand one
session to the next — this only pays for itself when multiple lanes are
landing into one branch at the same time.

**`writing-for-agents`** — for writing anything an agent reads: a `SKILL.md`, an
`AGENTS.md`, a project rule, a prompt handed to a subagent. Its first section is
the one that gets used most — whether a new rule should be a skill at all, or a
line in `user-preferences`, or a section of a skill that already exists; a rule
that must fire every time makes a bad skill, because a skill only loads when its
description matches. The rest covers why a description is a *pointer* whose
wording decides whether the material is ever loaded, what to inline versus push
behind that pointer, completion criteria sharp enough that the agent cannot
declare itself done early, and the no-op test for pruning: if a sentence does not
change behavior versus the model's default, delete the sentence.

**`grilling`** — the front end nothing else covered: every other skill here starts
from a task that is already clear. It maps the open decisions as a tree and works
the *frontier* — the questions whose prerequisites are already settled — one round
at a time, each question carrying its recommended answer so pushing back is
cheaper than composing one. Facts are the agent's job (dispatch a subagent rather
than asking you what the code says); decisions are yours. It opens by stating its
current reading and a confidence number, which is the part that makes it honest.

**`test-driven-development`** — red, green, refactor, with the point kept in view:
if you never watched the test fail, you do not know what it tests. A test that
fails because of a typo is not red. For a bug the shape is a reproduction test
first, and the regression test is only proven by reverting the fix and watching it
go red again. Names its own skip conditions — no test infrastructure, throwaway
scripts, config-only changes — because a bolted-on TDD ritual is worse than none.

**`handoff`** — compacts the current session into the document the next agent
picks up: coordinates and validation state from the `engineering-discipline`
checklist, one imperative next step, and which skills to load first. Paths and
hashes instead of copies of anything that already exists, so the handoff cannot
diverge from the artifacts it points at.

**`retro`** — a session postmortem aimed at the *environment*, not the output:
missing navigation pointers, mistakes an automated check could have caught, no-op
lines in always-on files, expensive tool calls, information the agent could not
reach. It presents candidates ranked and stops, because turning findings into
rules needs your confirmation. Carries one idea worth the read on its own — coding
standards belong on the reviewer, which has a diff and no context pressure, not on
the implementer, which has neither.

**`send-email`** — sends one plain-text email via the Resend HTTPS API, with an
SMTP fallback. Deliberately narrow: only on an explicit request in the current
turn, never wired to a timer, cron entry, git hook, or CI step. Credentials come
from the environment or a config file outside the repository; the script scrubs
secret values out of anything it prints, and exits non-zero naming the missing
variable rather than pretending a send succeeded.

## Configuration and secrets

Nothing here contains credentials. `send-email` reads `RESEND_API_KEY` or SMTP
settings from the environment or `~/.config/agent-mail.env`, which is
intentionally not tracked. If none of its config paths are readable it writes a
`.example` file listing the variables it needs.

`glm-dispatch` reads `~/.claude/glm.env`, also untracked, holding the Zhipu
endpoint, its API key, and the `GLM_DISPATCH_ENABLED` switch. The file's absence
is a valid state meaning "this machine does not dispatch" — the skill probes for
it and falls back to the normal executor rather than erroring.
Its `setup-glm.ps1` / `setup-glm.sh` create that file from a template with the
switch off and the key blank, install the `claude` CLI if missing, and verify the
endpoint once you have filled the key in — they never overwrite an existing
`glm.env`, so re-running cannot lose your key.

## Scope

These are the portable pieces of a larger personal setup. Anything tied to a
specific employer, internal service, or project lives elsewhere and is not
published here.
