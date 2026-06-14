#!/usr/bin/env pwsh
<#
  Hub-side: review pending rule-sync proposals. For each, show the diff of proposed vs
  live target, then accept (publish + ledger) or reject (discard + ledger). Refuses on a
  spoke. Pushes once at the end. -Yes auto-accepts all VALID proposals (use with care).
    pwsh scripts/review-rule-proposals.ps1
#>
param(
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync-lib.ps1')

if ((Get-GrimdexRole -GrimdexRoot $GrimdexRoot) -eq 'spoke') {
    throw "This is a spoke — rule decisions are made on the hub."
}
Sync-GrimdexRepo -GrimdexRoot $GrimdexRoot -Autostash | Out-Null

$pending = @(Get-PendingRuleSyncProposals -GrimdexRoot $GrimdexRoot)
if ($pending.Count -eq 0) { Write-Host 'No pending rule-sync proposals.'; return }

$acted = 0
foreach ($r in $pending) {
    if (-not $r.valid) {
        Write-Warning "Skipping malformed proposal $($r.path): $($r.reason)"
        continue
    }
    $p = $r.proposal
    $abs = Join-Path $GrimdexRoot ($p.target -replace '/', '\')
    Write-Host "`n=== $($p.target)  (from $($p.machine), $($p.timestamp)) ===" -ForegroundColor Cyan
    if ($p.note) { Write-Host "note: $($p.note)" }
    $tmp = Join-Path $env:TEMP ("grimdex-review-{0}.md" -f [IO.Path]::GetRandomFileName())
    Set-Content $tmp -Value $p.content -NoNewline -Encoding utf8
    git --no-pager -C $GrimdexRoot diff --no-index -- $abs $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $choice = if ($Yes) { 'a' } else { Read-Host "[a]ccept / [r]eject / [s]kip" }
    switch ($choice) {
        'a' { Approve-RuleSyncProposal -GrimdexRoot $GrimdexRoot -Path $p.path | Out-Null; $acted++; Write-Host 'accepted' -ForegroundColor Green }
        'r' { $why = Read-Host 'reason'; Deny-RuleSyncProposal -GrimdexRoot $GrimdexRoot -Path $p.path -Reason $why | Out-Null; $acted++; Write-Host 'rejected' -ForegroundColor Yellow }
        default { Write-Host 'skipped' }
    }
}
if ($acted -gt 0) {
    git -C $GrimdexRoot add -- universal GRIMDEX.md   # rule files, proposals, ledger — not unrelated trees
    git -C $GrimdexRoot commit -q -m "rule-sync: published $acted proposal decision(s)"
    Sync-GrimdexRepo -GrimdexRoot $GrimdexRoot -Autostash | Out-Null
    Write-Host "`nPublished $acted decision(s) and pushed." -ForegroundColor Green
}
