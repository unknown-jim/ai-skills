<#
.SYNOPSIS
  Dispatch a pre-written plan to Claude Code CLI running on the GLM endpoint,
  inside an isolated git worktree.

.DESCRIPTION
  Design happens in the Anthropic-backed desktop session; execution is handed
  to GLM here. Env vars are injected into THIS process only, and MCP servers
  are pinned with --strict-mcp-config, so no global config is touched and
  other Claude Code sessions are unaffected.

.EXAMPLE
  glm-dispatch.ps1 -TaskFile plan.md -Worktree stock-badge
  glm-dispatch.ps1 -TaskFile plan.md -Worktree ui-fix -Mcp vision,wechat
#>
param(
    [Parameter(Mandatory=$true)][string]$TaskFile,
    [Parameter(Mandatory=$true)][string]$Worktree,
    [string]$Base = "main",
    [ValidateSet("sonnet","haiku")][string]$Model = "sonnet",
    [ValidateSet("low","medium","high","xhigh","max")][string]$Effort = "max",
    [string]$Branch = "",
    [ValidateSet("search","reader","zread","vision","wechat","ardot")][string[]]$Mcp = @(),
    [string]$Repo = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# --- locate CLI ---
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
    $fallback = Join-Path $env:APPDATA "npm\claude.cmd"
    if (Test-Path $fallback) { $claude = $fallback } else { throw "claude CLI not found. Run: npm install -g @anthropic-ai/claude-code" }
} else { $claude = $claude.Source }

# --- validate plan file ---
if (-not (Test-Path $TaskFile)) { throw "Task file not found: $TaskFile" }
$TaskFile = (Resolve-Path $TaskFile).Path

# --- load GLM env into this process only ---
$envFile = Join-Path $env:USERPROFILE ".claude\glm.env"
if (-not (Test-Path $envFile)) { throw "Missing $envFile" }
foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $i = $t.IndexOf("=")
    if ($i -lt 1) { continue }
    Set-Item -Path ("env:" + $t.Substring(0, $i).Trim()) -Value $t.Substring($i + 1).Trim()
}
$token = $env:ANTHROPIC_AUTH_TOKEN
if ($token -eq "PASTE_YOUR_ZHIPU_KEY_HERE" -or [string]::IsNullOrWhiteSpace($token)) {
    if ($DryRun) { Write-Host "[glm-dispatch] WARN: token not set yet - fine for -DryRun" }
    else { throw "Set ANTHROPIC_AUTH_TOKEN in $envFile first, get it from https://open.bigmodel.cn" }
}
# Ensure no stale Anthropic key shadows the GLM token in this child process.
Remove-Item env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

# --- build pinned MCP config (always strict: execution env is fully declared here) ---
$servers = @{}
foreach ($m in $Mcp) {
    switch ($m) {
        "search" { $servers["web-search-prime"] = @{ type = "http"; url = "https://open.bigmodel.cn/api/mcp/web_search_prime/mcp"; headers = @{ Authorization = "Bearer $token" } } }
        "reader" { $servers["web-reader"]       = @{ type = "http"; url = "https://open.bigmodel.cn/api/mcp/web_reader/mcp";       headers = @{ Authorization = "Bearer $token" } } }
        "zread"  { $servers["zread"]            = @{ type = "http"; url = "https://open.bigmodel.cn/api/mcp/zread/mcp";            headers = @{ Authorization = "Bearer $token" } } }
        "vision" { $servers["zai-vision"]       = @{ type = "stdio"; command = "npx.cmd"; args = @("-y", "@z_ai/mcp-server"); env = @{ Z_AI_API_KEY = $token; Z_AI_MODE = "ZHIPU" } } }
        "wechat" { $servers["wechat-devtools"]  = @{ type = "stdio"; command = "wechatide"; args = @("mcp") } }
        # ardot: 设计稿 MCP，跑在本机 127.0.0.1，无凭据、不外传。派发期间 Ardot 桌面端必须开着。
        "ardot"  { $servers["ardot"]            = @{ type = "http"; url = "http://127.0.0.1:50501/api/v1/mcp" } }
    }
}
$mcpFile = Join-Path $env:TEMP ("glm-mcp-" + [guid]::NewGuid().ToString("N") + ".json")
(@{ mcpServers = $servers } | ConvertTo-Json -Depth 8) | Out-File -FilePath $mcpFile -Encoding utf8

# --- resolve repo + worktree paths ---
if ($Repo -eq "") { $Repo = (git rev-parse --show-toplevel) }
if (-not $Repo) { throw "Not inside a git repository; pass -Repo explicitly." }
$Repo = $Repo -replace "/", "\"
$repoName = Split-Path $Repo -Leaf
$wtPath = Join-Path (Join-Path (Split-Path $Repo -Parent) "$repoName-worktrees") $Worktree
$branch = if ($Branch -ne "") { $Branch } else { "glm/$Worktree" }

if (-not (Test-Path $wtPath)) {
    Write-Host "[glm-dispatch] creating worktree $wtPath on branch $branch"
    if (-not $DryRun) { git -C $Repo worktree add -q -b $branch $wtPath $Base | Out-Null }
} else {
    Write-Host "[glm-dispatch] reusing existing worktree $wtPath"
}

# --- run ---
$logDir = Join-Path $env:USERPROFILE ".claude\glm-runs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("$Worktree-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")

$modelName = if ($Model -eq "haiku") { $env:ANTHROPIC_DEFAULT_HAIKU_MODEL } else { $env:ANTHROPIC_DEFAULT_SONNET_MODEL }
Write-Host "[glm-dispatch] endpoint : $env:ANTHROPIC_BASE_URL"
Write-Host "[glm-dispatch] model    : $Model -> $modelName"
Write-Host "[glm-dispatch] effort   : $Effort"
Write-Host "[glm-dispatch] cwd      : $wtPath"
Write-Host "[glm-dispatch] plan     : $TaskFile"
Write-Host "[glm-dispatch] mcp      : $(if ($Mcp.Count) { $Mcp -join ',' } else { '(none, strict)' })"
Write-Host "[glm-dispatch] log      : $logFile"

if ($DryRun) {
    Write-Host "[glm-dispatch] DRY RUN - generated MCP config:"
    Get-Content $mcpFile | ForEach-Object { "    " + ($_ -replace [regex]::Escape($token), "<REDACTED>") }
    Remove-Item $mcpFile -Force
    exit 0
}

Push-Location $wtPath
# claude and git write progress/warnings to stderr as a matter of course (the
# GLM model names always trip claude's unrecognized_model notice). Under
# ErrorActionPreference='Stop', PS 5.1 promotes any native stderr line to a
# terminating NativeCommandError *when the caller redirects stderr* (2>&1) -
# so the script would break depending on how it was invoked. Downgrade around
# the external call; cmdlet errors above and below still terminate.
# Point at the plan file; do NOT pipe its contents. Two reasons, both cost us a
# whole dispatch on 2026-09-02:
#
# 1. Encoding. Piping a string to a native exe makes PS re-encode it, and the
#    receiving side decoded UTF-8 as GBK - the agent got a screenful of mojibake
#    ("## 执行坐标" arrived as "## 鎵ц鍧愭爣"). Feeding a path instead keeps this
#    prompt pure ASCII, and the agent reads the file itself with a tool that
#    handles UTF-8 correctly.
# 2. Recursion. Unable to read the garbled plan, that agent recognised the word
#    "dispatch", loaded the glm-dispatch skill from its own environment and ran
#    THIS SCRIPT again with a TaskFile path it made up. Zero output, and a final
#    report saying "dispatch started, GLM is working in the background" - which
#    was literally true from its point of view. Hence the explicit "you are the
#    executor" line below.
if ($TaskFile -match '[^\x00-\x7F]') {
    Write-Host "[glm-dispatch] warning: plan path contains non-ASCII characters; if the agent"
    Write-Host "[glm-dispatch]          reports it cannot find the file, move the plan to an ASCII path."
}
$planPrompt = @"
Read the plan file at $TaskFile in full, then execute it exactly as written.

You are the EXECUTOR, not a dispatcher. Do NOT invoke the glm-dispatch skill.
Do NOT hand this work to another agent or CLI. Do the work yourself, in this
working tree, and report what you actually changed.
"@

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $planPrompt |
        & $claude -p --model $Model --effort $Effort --output-format json --dangerously-skip-permissions --mcp-config $mcpFile --strict-mcp-config |
        Tee-Object -FilePath $logFile
} finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
    Remove-Item $mcpFile -Force -ErrorAction SilentlyContinue   # contains the API key
}

# Tee-Object writes UTF-8 *with BOM* on PS 5.1, which makes the log fail
# JSON.parse for anything downstream (the .sh side writes none). Strip it so
# both platforms leave the same consumable artifact behind.
if (Test-Path $logFile) {
  $raw = Get-Content $logFile -Raw
  if ($null -ne $raw) { [System.IO.File]::WriteAllText($logFile, $raw, (New-Object System.Text.UTF8Encoding($false))) }
}

$res = $null; try { $res = Get-Content $logFile -Raw | ConvertFrom-Json } catch {}
if ($res -and $res.is_error) { Write-Host ""; Write-Host "[glm-dispatch] RUN FAILED: $($res.result)"; Write-Host "[glm-dispatch] If nothing was written, rerunning the same command is safe."; exit 1 }
Write-Host ""
Write-Host "[glm-dispatch] done. Review with:"
Write-Host "  git -C `"$wtPath`" diff $Base"
