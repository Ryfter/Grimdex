#!/usr/bin/env pwsh
# Tests for scripts/wire-lib.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wire-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

# --- Get-GrimdexStanza ---
$stanza = Get-GrimdexStanza -GrimdexPath 'D:\Dev\Grimdex' -ProjectId 'my-proj'
Assert 'stanza has start marker' ($stanza.StartsWith('<!-- grimdex:start -->'))
Assert 'stanza has end marker' ($stanza.EndsWith('<!-- grimdex:end -->'))
Assert 'stanza names the path' ($stanza.Contains('D:\Dev\Grimdex'))
Assert 'stanza names the project tier' ($stanza.Contains('projects/my-proj/'))
Assert 'stanza points at GRIMDEX.md' ($stanza.Contains('GRIMDEX.md'))
Assert 'stanza carries the contribution rule' ($stanza.Contains('PROGRAMMING DECISIONS'))

# --- Set-GrimdexBlock: pure behaviors ---
$r = Set-GrimdexBlock -Content '' -Stanza $stanza
Assert 'empty content -> stanza only' ($r.TrimEnd() -eq $stanza)

$r = Set-GrimdexBlock -Content "# Existing doc`n`nSome rules.`n" -Stanza $stanza
Assert 'no markers -> appended' ($r.StartsWith('# Existing doc') -and $r.Contains($stanza))
Assert 'append preserves prior content' ($r.Contains('Some rules.'))

$old = "# Doc`n`n<!-- grimdex:start -->`nOLD STANZA`n<!-- grimdex:end -->`n`n## After`n"
$r = Set-GrimdexBlock -Content $old -Stanza $stanza
Assert 'markers -> replaced in place' ($r.Contains($stanza) -and -not $r.Contains('OLD STANZA'))
Assert 'replace preserves surrounding content' ($r.StartsWith('# Doc') -and $r.Contains('## After'))

$twice = Set-GrimdexBlock -Content $r -Stanza $stanza
Assert 'idempotent (second run = no change)' ($twice -eq $r)

$dollarStanza = Get-GrimdexStanza -GrimdexPath 'D:\Odd$path\kb' -ProjectId 'p'
$r = Set-GrimdexBlock -Content $old -Stanza $dollarStanza
Assert 'dollar sign in path survives replacement' ($r.Contains('D:\Odd$path\kb'))

# --- Install-GrimdexPointers against a temp project ---
$tmp = Join-Path $env:TEMP "grimdex-wire-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Set-Content -Path (Join-Path $tmp 'CLAUDE.md') -Value "# My project`n`nHouse rules.`n" -NoNewline

$results = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath 'D:\Dev\Grimdex'
Assert 'five target files reported' ($results.Count -eq 5)
Assert 'CLAUDE.md appended' (($results | Where-Object file -like '*CLAUDE.md').action -eq 'appended')
Assert 'AGENTS.md created' (($results | Where-Object file -like '*AGENTS.md').action -eq 'created')
Assert '.cursorrules created' (Test-Path (Join-Path $tmp '.cursorrules'))
Assert 'copilot-instructions created under .github' (Test-Path (Join-Path $tmp '.github' 'copilot-instructions.md'))
$claude = Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw
Assert 'existing CLAUDE.md content preserved' ($claude.Contains('House rules.'))
Assert 'project id defaults to dir leaf' ($claude.Contains("projects/$(Split-Path $tmp -Leaf)/"))

$rerun = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath 'D:\Dev\Grimdex'
Assert 're-run -> all unchanged' (-not ($rerun | Where-Object action -ne 'unchanged'))

$moved = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath 'E:\Elsewhere\Grimdex'
Assert 'path change -> all updated in place' (-not ($moved | Where-Object action -notin 'updated'))
$claude = Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw
Assert 'updated block has new path only' ($claude.Contains('E:\Elsewhere\Grimdex') -and -not $claude.Contains('D:\Dev\Grimdex'))
Assert 'no duplicate markers after update' (([regex]::Matches($claude, [regex]::Escape('<!-- grimdex:start -->'))).Count -eq 1)

# explicit -ProjectId override
$r = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath 'E:\Elsewhere\Grimdex' -ProjectId 'custom-id'
$claude = Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw
Assert 'explicit ProjectId used' ($claude.Contains('projects/custom-id/'))

# missing project dir throws
$threw = $false
try { Install-GrimdexPointers -ProjectDir (Join-Path $env:TEMP "nope-$(Get-Random)") -GrimdexPath 'D:\x' | Out-Null }
catch { $threw = $true }
Assert 'missing project dir throws' $threw

Remove-Item -Recurse -Force $tmp
if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll wire-lib tests passed." -ForegroundColor Green
