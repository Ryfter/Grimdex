#!/usr/bin/env pwsh
<#
  Stamp model provenance at a closeout/compact (Grimdex law #8). Appends one line to
  projects/<id>/model-usage.md and self-registers the model in universal/model-catalog.md.
  Use YOUR OWN model id, per the schema in universal/model-catalog.md.
    pwsh scripts/stamp-model.ps1 -ProjectId my-proj -Model 'claude-code/opus-4.8' `
        -Did 'Sprint 4 multi-machine sync' -Decisions d017,d018
    pwsh scripts/stamp-model.ps1 -ProjectId my-proj -Model 'codex/codex-5.4-mini (reasoning:high)' `
        -Did 'refactored sweep-lib tests'
#>
param(
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][string]$Did,
    [string[]]$Decisions,
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'model-lib.ps1')

$results = Add-GrimdexModelStamp -GrimdexRoot $GrimdexRoot -ProjectId $ProjectId -Model $Model -Did $Did -Decisions $Decisions
$results | ForEach-Object { Write-Host ("  {0,-11} {1}" -f $_.action, $_.file) }
