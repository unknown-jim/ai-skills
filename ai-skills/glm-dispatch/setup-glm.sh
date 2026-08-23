#!/usr/bin/env bash
# One-time per-machine setup for GLM dispatch (macOS / Linux).
# Idempotent: never overwrites an existing glm.env, so re-running can't lose your key.
#
#   ~/.ai-skills/glm-dispatch/setup-glm.sh
#
# The dispatch script itself needs no install: it lives in this repo and
# ~/.ai-skills already points here (created by install.sh).

set -uo pipefail

ENV_FILE="$HOME/.claude/glm.env"
say() { echo "[setup-glm] $1"; }

# --- 1. claude CLI ---
if command -v claude >/dev/null 2>&1; then
  say "claude CLI: $(claude --version 2>/dev/null | head -1)"
else
  say "claude CLI not found, installing via npm..."
  command -v npm >/dev/null 2>&1 || { say "npm not found - install Node.js first, then re-run."; exit 1; }
  if ! npm install -g @anthropic-ai/claude-code; then
    say "npm install failed. If it was a permissions error, fix your npm prefix"
    say "(npm config set prefix ~/.npm-global) rather than using sudo, then re-run."
    exit 1
  fi
fi

# --- 2. glm.env ---
mkdir -p "$HOME/.claude"
if [ -f "$ENV_FILE" ]; then
  say "found existing $ENV_FILE - leaving it untouched"
else
  cat > "$ENV_FILE" <<'ENVEOF'
# GLM (Zhipu) endpoint for dispatched Claude Code CLI runs.
# Loaded ONLY by glm-dispatch into its child process.
# Never source this globally - that would switch every Claude Code session on
# this machine to GLM, because ANTHROPIC_BASE_URL outranks everything else.

# Master switch. Only "true" lets the glm-dispatch skill hand execution to GLM.
GLM_DISPATCH_ENABLED=false

ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
ANTHROPIC_AUTH_TOKEN=PASTE_YOUR_ZHIPU_KEY_HERE

# Model tier mapping. Check docs.bigmodel.cn/cn/guide/develop/claude for current
# names - the published docs have lagged behind the actual endpoint before.
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3[1m]
ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7

API_TIMEOUT_MS=3000000
CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
ENVEOF
  chmod 600 "$ENV_FILE"
  say "created $ENV_FILE (switch is off, key is a placeholder)"
fi

# --- 3. status ---
has_key=0; enabled=0
grep -q '^ANTHROPIC_AUTH_TOKEN=PASTE_YOUR_ZHIPU_KEY_HERE' "$ENV_FILE" || has_key=1
grep -q '^GLM_DISPATCH_ENABLED=true' "$ENV_FILE" && enabled=1

if [ "$has_key" -eq 0 ]; then
  say "NEXT: put your key in $ENV_FILE (open.bigmodel.cn > 个人编程套餐 > 套餐概览),"
  say "      set GLM_DISPATCH_ENABLED=true, then re-run this script to verify."
  exit 0
fi
if [ "$enabled" -eq 0 ]; then
  say "key is set but GLM_DISPATCH_ENABLED is not true - dispatch stays off by design."
  say "NEXT: flip it to true and re-run to verify."
  exit 0
fi

# --- 4. connectivity check (costs one tiny call) ---
say "verifying endpoint (one small call)..."
set -a; . "$ENV_FILE"; set +a
unset ANTHROPIC_API_KEY || true
reply="$(cd "$(mktemp -d)" && echo "Reply with exactly two characters: OK" \
  | claude -p --model sonnet --dangerously-skip-permissions 2>/dev/null | tail -1)"
case "$reply" in
  *OK*) say "endpoint OK - GLM dispatch is READY on this machine." ;;
  *)    say "unexpected reply: ${reply:-<empty>}"
        say "check the key and the model names in $ENV_FILE."; exit 1 ;;
esac
