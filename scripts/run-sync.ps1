#!/usr/bin/env pwsh
<#
  Scheduled-task entry for spokes: a two-way git refresh (pull --rebase --autostash,
  then push) so canonical rules arrive and local proposals/project-tier commits leave.
  Never writes rule/law files — that is the hub's job. Transcript to logs/ (gitignored).
#>
param([string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sweep-lib.ps1')

$logs = Join-Path $GrimdexRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$logFile = Join-Path $logs "$(Get-Date -Format 'yyyy-MM-dd-HHmmss')-sync.log"
try {
    $r = Sync-GrimdexRepo -GrimdexRoot $GrimdexRoot -Autostash
    "[$(Get-Date -Format o)] sync ok pulled=$($r.pulled) pushed=$($r.pushed)" | Set-Content $logFile
    exit 0
} catch {
    "[$(Get-Date -Format o)] sync FAILED: $_" | Set-Content $logFile
    exit 1
}
