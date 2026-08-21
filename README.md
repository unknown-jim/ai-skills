# ai-skills

Three user-level skills for coding agents (Claude Code, Cursor, Codex, and
anything else that reads a per-user skill directory), plus always-on personal
preferences and an idempotent installer that symlinks them into place.

```
ai-skills/
  user-preferences/         always-on personal workflow (language, advice, debug)
  engineering-discipline/   worktree isolation, handoff continuity, audit calibration
  design-execute-audit/     design → execute → audit loop across two model tiers
  send-email/               one plain-text email, on explicit request only
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

After install, Cursor discovers the three skills from `~/.cursor/skills` (and
the shared `~/.agents/skills`) in every workspace. Claude Code still uses
`~/.claude/skills`. `user-preferences` is not a discoverable skill: Claude Code
loads it from `~/.claude/rules/` every session. Cursor needs a single Settings
User Rule that reads `~/.ai-skills/user-preferences/SKILL.md`.

## Always-on preferences

**`user-preferences`** — personal workflow that should apply in every session:
reply in Chinese, stop when the goal is unclear, label architecture advice,
instrument with `printf` when analysis is not enough, and suggest new rules or
skills only after confirmation. Edit this file to change behavior in both
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
agent can act on in one pass, and how to calibrate finding severity so P1 keeps
meaning something.

**`design-execute-audit`** — for work that warrants more assurance than a single
pass: a strong model designs, a cheaper model executes mechanical changes
(escalating back when the work needs sustained judgment), a strong model audits,
and failures go back with specific problems until they pass or hit an iteration
cap. Includes the model mapping per harness, because copying Claude model
aliases into another tool's slug namespace is the most common way to break it.

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

## Scope

These are the portable pieces of a larger personal setup. Anything tied to a
specific employer, internal service, or project lives elsewhere and is not
published here.
