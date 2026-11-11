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

write_agents() {             # write_agents <目标路径>
  local dst="$1" tmp bak
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp "$dst.generated.XXXXXX")"
  {
    cat "$DIR/ai-skills/user-preferences/SKILL.md"
  } >"$tmp"
  chmod 600 "$tmp"

  if [ ! -L "$dst" ] && [ -f "$dst" ] && cmp -s "$dst" "$tmp"; then
    chmod 600 "$dst"
    rm "$tmp"
    echo "ok   $dst"
    return
  fi

  if [ -L "$dst" ]; then
    rm "$dst"                 # 旧版安装留下的软链，无需保留副本
  elif [ -e "$dst" ]; then
    bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "备份 $dst -> $bak"
  fi
  mv "$tmp" "$dst"
  echo "生成 $dst"
}


link "$DIR/ai-skills" "$HOME/.ai-skills"

# Always-on personal preferences are Claude *rules*, not on-demand skills.
ALWAYS_ON_RULES=(user-preferences)

# Claude Code lists a skill only if it has its own symlink under ~/.claude/skills/.
# Relative targets, so this keeps working wherever ~/.ai-skills points.
for s in "$DIR"/ai-skills/*/; do
  name="$(basename "$s")"
  skip=
  for r in "${ALWAYS_ON_RULES[@]}"; do
    [ "$name" = "$r" ] && { skip=1; break; }
  done
  [ -n "$skip" ] && continue
  link "../../.ai-skills/$name" "$HOME/.claude/skills/$name"
done

for name in "${ALWAYS_ON_RULES[@]}"; do
  link "../../.ai-skills/$name" "$HOME/.claude/rules/$name"
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

# Cursor scans ~/.cursor/skills and the shared ~/.agents/skills. The
# coding-agent workflow skills belong there too; send-email is already linked.
CURSOR_SKILLS=(engineering-discipline design-execute-audit writing-for-agents
               grilling handoff retro test-driven-development parallel-coordination
               debug-observability)
for name in "${CURSOR_SKILLS[@]}"; do
  for d in .agents .cursor; do
    link "../../.ai-skills/$name" "$HOME/$d/skills/$name"
  done
done

for dst in "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.zcode/AGENTS.md" "$HOME/.cursor/AGENTS.md"; do
  write_agents "$dst"
done

echo
echo "Done. Verify: head -1 ~/.claude/skills/engineering-discipline/SKILL.md"
