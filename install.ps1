# Junction these skills into the per-user skill directories that coding agents scan.
# Windows counterpart of install.sh. Native symlinks need Administrator here, so
# this script uses directory junctions (idempotent; a real file in the way is
# backed up as <name>.bak-<timestamp>, never silently overwritten).
$ErrorActionPreference = 'Stop'

$Dir = $PSScriptRoot
if (-not $Dir) {
  $Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

function Get-LinkTarget {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force
  $target = $item.Target
  if ($target -is [array]) { $target = $target[0] }
  return [string]$target
}

function Test-SamePath {
  param([string]$Left, [string]$Right)
  $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\')
  $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
  return $leftFull.Equals($rightFull, [StringComparison]::OrdinalIgnoreCase)
}

function Remove-ReparsePoint {
  param([string]$Path)
  # Never Remove-Item -Recurse a junction: that can delete the source tree.
  cmd /c "rmdir `"$Path`"" | Out-Null
  if (Test-Path -LiteralPath $Path) {
    throw "Failed to remove reparse point: $Path"
  }
}

function Link-Dir {
  param([string]$Src, [string]$Dst)
  $srcFull = [System.IO.Path]::GetFullPath($Src)
  $dstDir = Split-Path -Parent $Dst
  if (-not (Test-Path -LiteralPath $dstDir)) {
    New-Item -ItemType Directory -Path $dstDir | Out-Null
  }

  if (Test-Path -LiteralPath $Dst) {
    $item = Get-Item -LiteralPath $Dst -Force
    if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
      $current = Get-LinkTarget $Dst
      if ($current -and (Test-SamePath $current $srcFull)) {
        Write-Output "ok    $Dst"
        return
      }
      Remove-ReparsePoint $Dst
    } else {
      $stamp = Get-Date -Format 'yyyyMMddHHmmss'
      $bak = "$Dst.bak-$stamp"
      Move-Item -LiteralPath $Dst -Destination $bak
      Write-Output "backup $Dst -> $bak"
    }
  }

  $out = cmd /c "mklink /J `"$Dst`" `"$srcFull`"" 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "mklink failed for $Dst -> $srcFull : $out"
  }
  Write-Output "link  $Dst -> $srcFull"
}

Link-Dir (Join-Path $Dir 'ai-skills') (Join-Path $UserHome '.ai-skills')

$alwaysOnRules = @('user-preferences')

Get-ChildItem -LiteralPath (Join-Path $Dir 'ai-skills') -Directory | ForEach-Object {
  $name = $_.Name
  if ($alwaysOnRules -contains $name) { return }
  Link-Dir (Join-Path $UserHome ".ai-skills\$name") (Join-Path $UserHome ".claude\skills\$name")
}

foreach ($name in $alwaysOnRules) {
  Link-Dir (Join-Path $UserHome ".ai-skills\$name") (Join-Path $UserHome ".claude\rules\$name")
}

$crossAgentSkills = @('send-email')
foreach ($name in $crossAgentSkills) {
  foreach ($d in @('.agents', '.cursor', '.codex', '.gemini', '.copilot')) {
    Link-Dir (Join-Path $UserHome ".ai-skills\$name") (Join-Path $UserHome "$d\skills\$name")
  }
}

$cursorSkills = @('engineering-discipline', 'design-execute-audit', 'writing-for-agents')
foreach ($name in $cursorSkills) {
  foreach ($d in @('.agents', '.cursor')) {
    Link-Dir (Join-Path $UserHome ".ai-skills\$name") (Join-Path $UserHome "$d\skills\$name")
  }
}

Write-Output ''
Write-Output "Done. Verify: Get-Content `"$UserHome\.cursor\skills\engineering-discipline\SKILL.md`" -TotalCount 1"
