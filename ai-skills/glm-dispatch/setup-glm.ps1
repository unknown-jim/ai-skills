<#
.SYNOPSIS
  One-time per-machine setup for GLM dispatch (Windows).
.DESCRIPTION
  Idempotent: never overwrites an existing glm.env, so re-running cannot lose
  your key. The dispatch script itself needs no install - it lives in this repo
  and ~/.ai-skills already points here (created by install.ps1).
.EXAMPLE
  & "$env:USERPROFILE\.ai-skills\glm-dispatch\setup-glm.ps1"
#>
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[setup-glm] $m" }

$envFile = Join-Path $env:USERPROFILE ".claude\glm.env"

# --- 1. claude CLI ---
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { $fb = Join-Path $env:APPDATA "npm\claude.cmd"; if (Test-Path $fb) { $claude = $fb } }
if ($claude) {
  Say "claude CLI: found"
} else {
  Say "claude CLI not found, installing via npm..."
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Say "npm not found - install Node.js first, then re-run."; exit 1 }
  npm install -g @anthropic-ai/claude-code
  if ($LASTEXITCODE -ne 0) { Say "npm install failed."; exit 1 }
}

# --- 2. glm.env ---
$claudeDir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

if (Test-Path $envFile) {
  Say "found existing $envFile - leaving it untouched"
} else {
  $template = @'
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
'@
  # No BOM: the parser in glm-dispatch reads this line by line.
  [System.IO.File]::WriteAllText($envFile, $template, (New-Object System.Text.UTF8Encoding($false)))
  Say "created $envFile (switch is off, key is a placeholder)"
}

# --- 3. status ---
$hasKey  = -not (Select-String -Path $envFile -Pattern '^ANTHROPIC_AUTH_TOKEN=PASTE_YOUR_ZHIPU_KEY_HERE' -Quiet)
$enabled = Select-String -Path $envFile -Pattern '^GLM_DISPATCH_ENABLED=true' -Quiet

if (-not $hasKey) {
  Say "NEXT: put your key in $envFile (open.bigmodel.cn > 个人编程套餐 > 套餐概览),"
  Say "      set GLM_DISPATCH_ENABLED=true, then re-run this script to verify."
  exit 0
}
if (-not $enabled) {
  Say "key is set but GLM_DISPATCH_ENABLED is not true - dispatch stays off by design."
  Say "NEXT: flip it to true and re-run to verify."
  exit 0
}

# --- 4. connectivity check (costs one tiny call) ---
Say "verifying endpoint (one small call)..."
foreach ($line in Get-Content $envFile) {
  $t = $line.Trim()
  if ($t -eq "" -or $t.StartsWith("#")) { continue }
  $i = $t.IndexOf("="); if ($i -lt 1) { continue }
  Set-Item -Path ("env:" + $t.Substring(0, $i).Trim()) -Value $t.Substring($i + 1).Trim()
}
Remove-Item env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
$probe = Join-Path $env:TEMP ("glm-probe-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $probe -Force | Out-Null
Push-Location $probe
try {
  $reply = "Reply with exactly two characters: OK" | & $claude -p --model sonnet --dangerously-skip-permissions
} finally {
  Pop-Location
  Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
}
if ("$reply" -match 'OK') {
  Say "endpoint OK - GLM dispatch is READY on this machine."
} else {
  Say "unexpected reply: $reply"
  Say "check the key and the model names in $envFile."
  exit 1
}
