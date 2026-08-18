#!/usr/bin/env bash
# Symlink these skills into the per-user skill directories that coding agents scan.
# Idempotent; an existing real file is backed up as <name>.bak-<timestamp>, never
# silently overwritten.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {                       # link <source> <target>
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    [ "$(readlink "$dst")" = "$src" ] && { echo "ok    $dst"; return; }
    rm "$dst"                  # stale symlink pointing elsewhere
  elif [ -e "$dst" ]; then
    local bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "backup $dst -> $bak"
  fi
  ln -s "$src" "$dst"
  echo "link  $dst -> $src"
}

link "$DIR/ai-skills" "$HOME/.ai-skills"

# Claude Code lists a skill only if it has its own symlink under ~/.claude/skills/.
# Relative targets, so this keeps working wherever ~/.ai-skills points.
for s in "$DIR"/ai-skills/*/; do
  link "../../.ai-skills/$(basename "$s")" "$HOME/.claude/skills/$(basename "$s")"
done

# Skills that every agent should discover need one symlink per tool. ~/.agents/skills
# is the shared path for Cursor / Codex / Gemini CLI / Copilot; the rest are each
# tool's own directory, linked too in case a version does not scan the shared path.
# Claude Code only reads ~/.claude/skills (covered by the loop above).
# All targets live in $HOME/X/skills/, so ../../ lands back on $HOME.
CROSS_AGENT_SKILLS=(send-email)
for name in "${CROSS_AGENT_SKILLS[@]}"; do
  for d in .agents .cursor .codex .gemini .copilot; do
    link "../../.ai-skills/$name" "$HOME/$d/skills/$name"
  done
done

echo
echo "Done. Verify: head -1 ~/.claude/skills/engineering-discipline/SKILL.md"
