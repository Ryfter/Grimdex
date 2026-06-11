#!/usr/bin/env pwsh
<#
  Grimdex first-run setup. Idempotent; safe to re-run.
    pwsh setup.ps1                          # verify structure + report junction state
    pwsh setup.ps1 -CreateJunction          # also swap ~/.claude/knowledge -> junction (asks first)
    pwsh setup.ps1 -CreateJunction -Force   # non-interactive swap (still refuses dirty trees)
#>
param(
    [string]$KnowledgePath = (Join-Path $HOME '.claude' 'knowledge'),
    [switch]$CreateJunction,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts' 'setup-lib.ps1')
$root = $PSScriptRoot

# 1. Structure: tier dirs exist (no-op when already present)
foreach ($dir in 'projects', 'universal', 'config', 'scripts', 'docs') {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null
}

# 2. Root files: report, never overwrite
foreach ($f in 'GRIMDEX.md', 'KNOWLEDGE.md', 'README.md') {
    $ok = Test-Path (Join-Path $root $f)
    Write-Host ("  {0}  {1}" -f ($ok ? 'OK     ' : 'MISSING'), $f) -ForegroundColor ($ok ? 'Green' : 'Red')
    if (-not $ok) { Write-Warning "$f is missing — restore it from git before using this clone." }
}
if (-not (Test-GrimdexRoot -Root $root)) { throw "This directory is not a valid Grimdex root: $root" }

# 3. Redeploy mirrored global rules (universal/claude-rules -> ~/.claude/rules)
foreach ($r in (Sync-GrimdexRules -GrimdexRoot $root)) {
    Write-Host ("  rule {0,-16} {1}" -f $r.action, $r.rule)
    if ($r.action -eq 'conflict-skipped') {
        Write-Warning "$($r.rule): live copy differs from the Grimdex mirror — reconcile (update the mirror, or re-run sync with -Force via Sync-GrimdexRules)."
    }
}

# 4. Junction state + optional swap
$state = Get-GrimdexJunctionState -KnowledgePath $KnowledgePath -Target $root
Write-Host "  Junction: $KnowledgePath -> $root : $state"
if (-not $CreateJunction) {
    if ($state -ne 'linked') { Write-Host '  (run again with -CreateJunction to link it)' }
    return
}
if ($state -eq 'linked') { Write-Host '  Already linked — nothing to do.' -ForegroundColor Green; return }
if (-not $Force) {
    Write-Host "  About to replace $KnowledgePath with a junction to $root."
    Write-Host "  The existing directory is kept as $KnowledgePath.bak (never deleted by this script)."
    if ((Read-Host '  Proceed? [y/N]') -notmatch '^[Yy]') { Write-Host '  Aborted.'; return }
}
$result = Install-GrimdexJunction -KnowledgePath $KnowledgePath -Target $root -Force:$Force
Write-Host ("  Junction {0}. Backup: {1}" -f $result.action, ($result.backup ?? 'n/a')) -ForegroundColor Green
