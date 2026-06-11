#!/usr/bin/env pwsh
<#
  Grimdex first-run setup. Idempotent; safe to re-run.
    pwsh setup.ps1                          # verify structure + report junction states
    pwsh setup.ps1 -CreateJunction          # also swap ~/.claude/knowledge -> junction (asks first)
    pwsh setup.ps1 -LinkRules               # also swap ~/.claude/rules -> universal/claude-rules (asks first)
    pwsh setup.ps1 -CreateJunction -Force   # non-interactive (still refuses dirty trees / diverged rules)
#>
param(
    [string]$KnowledgePath = (Join-Path $HOME '.claude' 'knowledge'),
    [string]$RulesPath = (Join-Path $HOME '.claude' 'rules'),
    [switch]$CreateJunction,
    [switch]$LinkRules,
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

# 3. Mirrored global rules: sync state (single 'linked' row when the rules junction is live)
foreach ($r in (Sync-GrimdexRules -GrimdexRoot $root -RulesPath $RulesPath)) {
    Write-Host ("  rule {0,-16} {1}" -f $r.action, $r.rule)
    if ($r.action -eq 'conflict-skipped') {
        Write-Warning "$($r.rule): live copy differs from the Grimdex mirror — reconcile (update the mirror, or re-run sync with -Force via Sync-GrimdexRules)."
    }
}

# 4. Knowledge junction state + optional swap
$state = Get-GrimdexJunctionState -KnowledgePath $KnowledgePath -Target $root
Write-Host "  Junction: $KnowledgePath -> $root : $state"
if ($CreateJunction -and $state -ne 'linked') {
    $go = [bool]$Force
    if (-not $go) {
        Write-Host "  About to replace $KnowledgePath with a junction to $root."
        Write-Host "  The existing directory is kept as $KnowledgePath.bak (never deleted by this script)."
        $go = (Read-Host '  Proceed? [y/N]') -match '^[Yy]'
    }
    if ($go) {
        $result = Install-GrimdexJunction -KnowledgePath $KnowledgePath -Target $root -Force:$Force
        Write-Host ("  Junction {0}. Backup: {1}" -f $result.action, ($result.backup ?? 'n/a')) -ForegroundColor Green
    } else { Write-Host '  Skipped.' }
} elseif ($state -ne 'linked') {
    Write-Host '  (run again with -CreateJunction to link it)'
}

# 5. Rules junction (v2): ~/.claude/rules served FROM universal/claude-rules
$rulesMirror = Join-Path $root 'universal' 'claude-rules'
$rstate = (Test-Path $rulesMirror) ? (Get-GrimdexJunctionState -KnowledgePath $RulesPath -Target $rulesMirror) : 'no-mirror'
Write-Host "  Rules junction: $RulesPath -> $rulesMirror : $rstate"
if ($LinkRules -and $rstate -notin 'linked', 'no-mirror') {
    $go = [bool]$Force
    if (-not $go) {
        Write-Host "  About to replace $RulesPath with a junction to $rulesMirror."
        Write-Host "  The existing directory is kept as $RulesPath.bak (never deleted by this script)."
        $go = (Read-Host '  Proceed? [y/N]') -match '^[Yy]'
    }
    if ($go) {
        $result = Install-GrimdexRulesJunction -GrimdexRoot $root -RulesPath $RulesPath -Force:$Force
        Write-Host ("  Rules junction {0}. Backup: {1}" -f $result.action, ($result.backup ?? 'n/a')) -ForegroundColor Green
    } else { Write-Host '  Skipped.' }
} elseif ($rstate -in 'real-dir', 'missing') {
    Write-Host '  (run again with -LinkRules to serve rules directly from Grimdex)'
}
