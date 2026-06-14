#!/usr/bin/env pwsh
<#
  One-command scheduling. Role-aware (config/sync.json): the hub registers
  Grimdex-Daily-Sweep + Grimdex-Weekly-Audit; a spoke registers Grimdex-Daily-Pull.
  Idempotent; -Uninstall removes all Grimdex tasks. -Role overrides auto-detection.
#>
param(
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('hub', 'spoke')][string]$Role,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync-lib.ps1')      # Get-GrimdexRole (+ sweep-lib)
. (Join-Path $PSScriptRoot 'schedule-lib.ps1')

if ($Uninstall) {
    $results = Uninstall-GrimdexSchedule
} else {
    if (-not $Role) { $Role = Get-GrimdexRole -GrimdexRoot $GrimdexRoot }
    Write-Host "  role: $Role"
    $results = Install-GrimdexSchedule -GrimdexRoot $GrimdexRoot -Role $Role
}
$results | ForEach-Object { Write-Host ("  {0,-11} {1}" -f $_.action, $_.task) }
