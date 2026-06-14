#!/usr/bin/env pwsh
<#
  Grimdex mechanical sweep driver — run by the daily/weekly routine playbooks (and by
  hand). Syncs the repo, reports inbox status + mechanical findings, and prints a
  STATUS line the semantic layer keys on:
    STATUS: heartbeat-ok     -> inbox empty, no warn-level findings (daily: log + stop)
    STATUS: action-needed    -> candidates to process and/or warnings to handle
#>
param(
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$NoSync
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync-lib.ps1')   # also dot-sources sweep-lib.ps1

if (-not $NoSync) {
    $sync = Sync-GrimdexRepo -GrimdexRoot $GrimdexRoot -SkipPush
    Write-Host "  sync: pulled=$($sync.pulled)"
}

$inbox = @(Get-GrimdexInboxStatus -GrimdexRoot $GrimdexRoot)
Write-Host "  inbox: $($inbox.Count) project file(s) with candidates"
foreach ($row in $inbox) {
    Write-Host ("    {0}: {1} candidate(s), oldest {2} day(s)  [{3}]" -f $row.project, $row.candidates, $row.oldestDays, $row.file)
}

$findings = @(Invoke-GrimdexMechanicalChecks -GrimdexRoot $GrimdexRoot)
$findings += @(Test-GrimdexRuleSyncProposals -GrimdexRoot $GrimdexRoot)
$warns = @($findings | Where-Object severity -eq 'warn')
$infos = @($findings | Where-Object severity -eq 'info')
$pendingSync = @($findings | Where-Object check -eq 'rule-sync')
Write-Host "  findings: $($warns.Count) warn, $($infos.Count) info"
foreach ($f in $findings) {
    Write-Host ("    {0,-4} [{1}] {2} — {3}" -f $f.severity, $f.check, $f.path, $f.message)
}

if ($inbox.Count -eq 0 -and $warns.Count -eq 0 -and $pendingSync.Count -eq 0) { Write-Host 'STATUS: heartbeat-ok' }
else { Write-Host 'STATUS: action-needed' }
