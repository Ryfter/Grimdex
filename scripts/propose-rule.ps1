#!/usr/bin/env pwsh
<#
  Spoke-side: propose a change to a rule/law file. Opens a scratch copy of the target
  in an editor; on save, files the result as a rule-sync proposal and pushes it. The
  live target is never edited here — single-writer is the hub's. Refuses to run on the hub.
    pwsh scripts/propose-rule.ps1 -Target universal/claude-rules/context7.md -Note "tighten triggers"
#>
param(
    [Parameter(Mandatory)][string]$Target,            # repo-relative, forward slashes
    [string]$Note = '',
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync-lib.ps1')

if ((Get-GrimdexRole -GrimdexRoot $GrimdexRoot) -eq 'hub') {
    throw "This is the hub — edit the rule directly; proposals are for spokes."
}
$abs = Join-Path $GrimdexRoot ($Target -replace '/', '\')
if (-not (Test-Path $abs)) { throw "Target does not exist: $Target" }

# Scratch copy — the live file is never touched.
$scratch = Join-Path $env:TEMP ("grimdex-propose-{0}.md" -f ([IO.Path]::GetFileNameWithoutExtension($Target)))
Copy-Item $abs $scratch -Force
try {
    $editor = $env:EDITOR
    if ($editor) { & $editor $scratch | Out-Null } else { Start-Process notepad.exe -ArgumentList $scratch -Wait }

    $content = Get-Content $scratch -Raw
    if ($content -eq (Get-Content $abs -Raw)) { Write-Host 'No change — nothing to propose.'; return }

    $path = New-RuleSyncProposal -GrimdexRoot $GrimdexRoot -Target $Target -Content $content `
        -Machine $env:COMPUTERNAME -Timestamp (Get-Date -Format o) -Note $Note
    git -C $GrimdexRoot add -- $path     # absolute path inside the repo; git resolves it
    git -C $GrimdexRoot commit -q -m "propose(rule-sync): $Target from $env:COMPUTERNAME"
    Sync-GrimdexRepo -GrimdexRoot $GrimdexRoot -Autostash | Out-Null
    Write-Host "Proposal filed and pushed: $(Split-Path $path -Leaf)" -ForegroundColor Green
} finally {
    Remove-Item $scratch -ErrorAction SilentlyContinue   # always clean the scratch copy
}
