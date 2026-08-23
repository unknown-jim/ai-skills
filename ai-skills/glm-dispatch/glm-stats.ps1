<#
.SYNOPSIS
  Usage statistics for the dispatch logs glm-dispatch writes to
  ~\.claude\glm-runs\<worktree>-<timestamp>.json - one file per dispatch.

.DESCRIPTION
  Prints one line per dispatch (turns / tokens / duration), then totals.
  Turns are the billing unit on per-prompt plans, so the totals answer
  "how much did GLM execution cost this week".

  INPUT column = usage.input_tokens + usage.cache_read_input_tokens.
  The camelCase modelUsage fields are deliberately NOT used: they are a
  per-model breakdown, and summing them double-counts tokens.

  Older logs carry a UTF-8 BOM (PS 5.1 Tee-Object legacy); it is stripped
  before parsing so both old and new log formats read. Unparseable files
  are skipped and reported, never fatal.

  Output matches glm-stats.sh (run under LC_ALL=C): files are listed in
  byte order and numbers use invariant thousands separators.

.EXAMPLE
  glm-stats.ps1
#>
$ErrorActionPreference = "Stop"

$LogDir = Join-Path $env:USERPROFILE ".claude\glm-runs"

if (-not (Test-Path $LogDir)) {
    Write-Host "[glm-stats] log directory ~/.claude/glm-runs does not exist yet - nothing to stat."
    exit 0
}

$files = @(Get-ChildItem -LiteralPath $LogDir -Filter *.json -File)
if ($files.Count -eq 0) {
    Write-Host "[glm-stats] no *.json logs in ~/.claude/glm-runs - nothing to stat yet."
    exit 0
}

function Num([object]$v) { if ($null -eq $v) { [long]0 } else { [long]$v } }
function Fmt([long]$n)  { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:N0}", $n) }

# ordinal (byte-order) sort so rows match glm-stats.sh under LC_ALL=C
$names = [System.Collections.ArrayList]::new()
foreach ($f in $files) { [void]$names.Add($f.Name) }
$names.Sort([System.StringComparer]::Ordinal)

$rows     = [System.Collections.Generic.List[object]]::new()
$skipped  = [System.Collections.Generic.List[string]]::new()
$totTurns = [long]0; $totFail = 0; $totIn = [long]0; $totOut = [long]0; $totMs = [long]0

foreach ($name in $names) {
    $path = Join-Path $LogDir $name
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $task = $base; $stamp = "-"
    if ($base -match '^(.*)-(\d{8})-(\d{6})$') {
        $d = $Matches[2]; $t = $Matches[3]; $task = $Matches[1]
        $stamp = $d.Substring(0,4) + "-" + $d.Substring(4,2) + "-" + $d.Substring(6,2) + " " + `
                 $t.Substring(0,2) + ":" + $t.Substring(2,2)
    }
    try {
        # UTF8 ReadAllText already honours a BOM; the extra strip keeps the
        # same guarantee as glm-stats.sh in case the decode path ever changes.
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        $r = $text | ConvertFrom-Json
    } catch {
        $skipped.Add($name)
        continue
    }
    $u = $r.usage
    if ($null -eq $u) { $u = @{} }
    $turns  = Num $r.num_turns
    $failed = [bool]$r.is_error
    $inTok  = (Num $u.input_tokens) + (Num $u.cache_read_input_tokens)
    $outTok = Num $u.output_tokens
    $ms     = Num $r.duration_ms
    $rows.Add([pscustomobject]@{ Task=$task; Stamp=$stamp; Turns=$turns; Failed=$failed; In=$inTok; Out=$outTok; Ms=$ms })
    $totTurns += $turns
    if ($failed) { $totFail++ }
    $totIn += $inTok; $totOut += $outTok; $totMs += $ms
}

Write-Host ""
Write-Host "[glm-stats] reading ~/.claude/glm-runs: $($files.Count) json files"

# column widths from the formatted values
$wTask=4; $wStamp=5; $wTurns=5; $wIn=5; $wOut=6; $wMs=11
foreach ($row in $rows) {
    if ($row.Task.Length  -gt $wTask)  { $wTask  = $row.Task.Length }
    if ($row.Stamp.Length -gt $wStamp) { $wStamp = $row.Stamp.Length }
    if ((Fmt $row.Turns).Length -gt $wTurns) { $wTurns = (Fmt $row.Turns).Length }
    if ((Fmt $row.In).Length    -gt $wIn)    { $wIn    = (Fmt $row.In).Length }
    if ((Fmt $row.Out).Length   -gt $wOut)   { $wOut   = (Fmt $row.Out).Length }
    if ((Fmt $row.Ms).Length    -gt $wMs)    { $wMs    = (Fmt $row.Ms).Length }
}

if ($rows.Count -gt 0) {
    Write-Host ""
    Write-Host ("TASK".PadRight($wTask) + "  " + "STAMP".PadRight($wStamp) + "  " + `
        "TURNS".PadLeft($wTurns) + "  " + "INPUT".PadLeft($wIn) + "  " + "OUTPUT".PadLeft($wOut) + "  " + `
        "DURATION_MS".PadLeft($wMs) + "  " + "STATUS")
    foreach ($row in $rows) {
        $status = "ok"
        if ($row.Failed) { $status = "FAIL" }
        Write-Host ($row.Task.PadRight($wTask) + "  " + $row.Stamp.PadRight($wStamp) + "  " + `
            (Fmt $row.Turns).PadLeft($wTurns) + "  " + (Fmt $row.In).PadLeft($wIn) + "  " + `
            (Fmt $row.Out).PadLeft($wOut) + "  " + (Fmt $row.Ms).PadLeft($wMs) + "  " + $status)
    }
} else {
    Write-Host ""
    Write-Host "[glm-stats] no parseable logs found."
}

if ($skipped.Count -gt 0) {
    Write-Host ""
    foreach ($s in $skipped) { Write-Host "[glm-stats] skipped unparseable log: $s" }
}

# totals
$tenth  = [long][math]::Floor($totMs / 6000.0)
$minFmt = "{0}.{1}" -f [int][math]::Floor($tenth / 10), ($tenth % 10)
# note: pscustomobject rows, because @() flattens nested arrays in PS 5.1
$tots = @(
    [pscustomobject]@{ Label = "dispatches";    Value = Fmt $rows.Count }
    [pscustomobject]@{ Label = "failures";      Value = Fmt $totFail }
    [pscustomobject]@{ Label = "turns";         Value = Fmt $totTurns }
    [pscustomobject]@{ Label = "input tokens";  Value = Fmt $totIn }
    [pscustomobject]@{ Label = "output tokens"; Value = Fmt $totOut }
    [pscustomobject]@{ Label = "duration";      Value = Fmt $totMs; Suffix = " ms ($minFmt min)" }
)
$wTot = 0
foreach ($t in $tots) { if ($t.Value.Length -gt $wTot) { $wTot = $t.Value.Length } }
$totalW = $wTask + 2 + $wStamp + 2 + $wTurns + 2 + $wIn + 2 + $wOut + 2 + $wMs + 2 + 6
Write-Host ""
Write-Host ("-" * $totalW)
foreach ($t in $tots) {
    $suffix = ""
    if ($t.Suffix) { $suffix = $t.Suffix }
    Write-Host ($t.Label.PadRight(13) + "  " + $t.Value.PadLeft($wTot) + $suffix)
}
exit 0
