#!/usr/bin/env pwsh
<#
  One-command scheduling: registers Grimdex-Daily-Sweep (daily 5:30 am) and
  Grimdex-Weekly-Audit (Sunday 5:30 am) for the current user, both with
  StartWhenAvailable (PC off -> runs when next able). Idempotent; -Uninstall removes.
#>
param(
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'schedule-lib.ps1')

$results = if ($Uninstall) { Uninstall-GrimdexSchedule } else { Install-GrimdexSchedule -GrimdexRoot $GrimdexRoot }
$results | ForEach-Object { Write-Host ("  {0,-11} {1}" -f $_.action, $_.task) }
