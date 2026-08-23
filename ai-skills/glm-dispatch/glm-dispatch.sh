#!/usr/bin/env bash
# Dispatch a pre-written plan to Claude Code CLI running on the GLM endpoint,
# inside an isolated git worktree.
#
# Design happens in the Anthropic-backed session; execution is handed to GLM
# here. Env vars are exported into THIS process only, and MCP servers are
# pinned with --strict-mcp-config, so no global config is touched and other
# Claude Code sessions are unaffected.
#
# Usage:
#   glm-dispatch.sh --task plan.md --worktree stock-badge
#   glm-dispatch.sh --task plan.md --worktree ui-fix --branch feat/ui-fix --mcp vision,wechat
#
# Targets bash 3.2 (macOS system bash): no associative arrays, no ${var^^}.

set -euo pipefail

TASK=""; WORKTREE=""; BRANCH=""; BASE="main"; MODEL="sonnet"; EFFORT="max"; MCP=""; REPO=""; DRYRUN=0

die() { echo "[glm-dispatch] $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --task|--task-file) TASK="${2:-}"; shift 2 ;;
    --worktree)         WORKTREE="${2:-}"; shift 2 ;;
    --branch)           BRANCH="${2:-}"; shift 2 ;;
    --base)             BASE="${2:-}"; shift 2 ;;
    --model)            MODEL="${2:-}"; shift 2 ;;
    --effort)           EFFORT="${2:-}"; shift 2 ;;
    --mcp)              MCP="${2:-}"; shift 2 ;;
    --repo)             REPO="${2:-}"; shift 2 ;;
    --dry-run)          DRYRUN=1; shift ;;
    -h|--help)          sed -n '2,14p' "$0"; exit 0 ;;
    *)                  die "unknown option: $1" ;;
  esac
done

[ -n "$TASK" ]     || die "--task is required"
[ -n "$WORKTREE" ] || die "--worktree is required"
[ -f "$TASK" ]     || die "task file not found: $TASK"
case "$MODEL" in sonnet|haiku) ;; *) die "--model must be sonnet or haiku" ;; esac
case "$EFFORT" in low|medium|high|xhigh|max) ;; *) die "--effort must be low|medium|high|xhigh|max" ;; esac

command -v claude >/dev/null 2>&1 || die "claude CLI not found. Run: npm install -g @anthropic-ai/claude-code"
TASK="$(cd "$(dirname "$TASK")" && pwd)/$(basename "$TASK")"

# --- load GLM env into this process only ---
ENV_FILE="$HOME/.claude/glm.env"
[ -f "$ENV_FILE" ] || die "missing $ENV_FILE"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  key="${line%%=*}"; val="${line#*=}"
  [ "$key" = "$line" ] && continue
  export "$key=$val"
done < "$ENV_FILE"

TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"
if [ -z "$TOKEN" ] || [ "$TOKEN" = "PASTE_YOUR_ZHIPU_KEY_HERE" ]; then
  if [ "$DRYRUN" -eq 1 ]; then
    echo "[glm-dispatch] WARN: token not set yet - fine for --dry-run"
  else
    die "set ANTHROPIC_AUTH_TOKEN in $ENV_FILE first, get it from https://open.bigmodel.cn"
  fi
fi
unset ANTHROPIC_API_KEY || true   # never let a stale Anthropic key shadow the GLM token

# --- build pinned MCP config (always strict: execution env is fully declared here) ---
http_server() { printf '"%s":{"type":"http","url":"%s","headers":{"Authorization":"Bearer %s"}}' "$1" "$2" "$TOKEN"; }
SERVERS=""
append() { [ -n "$SERVERS" ] && SERVERS="$SERVERS,"; SERVERS="$SERVERS$1"; }
OLD_IFS="$IFS"; IFS=','
for m in $MCP; do
  case "$m" in
    search) append "$(http_server web-search-prime https://open.bigmodel.cn/api/mcp/web_search_prime/mcp)" ;;
    reader) append "$(http_server web-reader       https://open.bigmodel.cn/api/mcp/web_reader/mcp)" ;;
    zread)  append "$(http_server zread            https://open.bigmodel.cn/api/mcp/zread/mcp)" ;;
    vision) append "$(printf '"zai-vision":{"type":"stdio","command":"npx","args":["-y","@z_ai/mcp-server"],"env":{"Z_AI_API_KEY":"%s","Z_AI_MODE":"ZHIPU"}}' "$TOKEN")" ;;
    wechat) append '"wechat-devtools":{"type":"stdio","command":"wechatide","args":["mcp"]}' ;;
    "")     ;;
    *)      IFS="$OLD_IFS"; die "unknown --mcp value: $m (search|reader|zread|vision|wechat)" ;;
  esac
done
IFS="$OLD_IFS"

# mktemp -d with trailing X is the one form both GNU and BSD mktemp agree on.
MCP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/glm-mcp-XXXXXXXX")"
MCP_FILE="$MCP_DIR/mcp.json"
printf '{"mcpServers":{%s}}' "$SERVERS" > "$MCP_FILE"
cleanup() { rm -rf "$MCP_DIR"; }   # contains the API key
trap cleanup EXIT

# --- resolve repo + worktree paths ---
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel)"
[ -n "$REPO" ] || die "not inside a git repository; pass --repo explicitly"
WT_PATH="$(dirname "$REPO")/$(basename "$REPO")-worktrees/$WORKTREE"
[ -n "$BRANCH" ] || BRANCH="glm/$WORKTREE"

if [ ! -d "$WT_PATH" ]; then
  echo "[glm-dispatch] creating worktree $WT_PATH on branch $BRANCH"
  [ "$DRYRUN" -eq 1 ] || git -C "$REPO" worktree add -q -b "$BRANCH" "$WT_PATH" "$BASE"
else
  echo "[glm-dispatch] reusing existing worktree $WT_PATH"
fi

LOG_DIR="$HOME/.claude/glm-runs"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$WORKTREE-$(date +%Y%m%d-%H%M%S).json"

if [ "$MODEL" = "haiku" ]; then MODEL_NAME="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"; else MODEL_NAME="${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"; fi
echo "[glm-dispatch] endpoint : ${ANTHROPIC_BASE_URL:-}"
echo "[glm-dispatch] model    : $MODEL -> $MODEL_NAME"
echo "[glm-dispatch] effort   : $EFFORT"
echo "[glm-dispatch] cwd      : $WT_PATH"
echo "[glm-dispatch] plan     : $TASK"
echo "[glm-dispatch] mcp      : ${MCP:-(none, strict)}"
echo "[glm-dispatch] log      : $LOG_FILE"

if [ "$DRYRUN" -eq 1 ]; then
  echo "[glm-dispatch] DRY RUN - generated MCP config:"
  sed "s|$TOKEN|<REDACTED>|g" "$MCP_FILE" | sed 's/^/    /'
  echo ""
  exit 0
fi

( cd "$WT_PATH" && claude -p --model "$MODEL" --effort "$EFFORT" --output-format json \
    --dangerously-skip-permissions --mcp-config "$MCP_FILE" --strict-mcp-config < "$TASK" ) | tee "$LOG_FILE"

if node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(r.is_error?1:0)' "$LOG_FILE" 2>/dev/null; then
  echo ""
  echo "[glm-dispatch] done. Review with:"
  echo "  git -C \"$WT_PATH\" diff $BASE"
else
  echo ""
  echo "[glm-dispatch] RUN FAILED - see $LOG_FILE"
  echo "[glm-dispatch] If nothing was written, rerunning the same command is safe."
  exit 1
fi
