#!/usr/bin/env pwsh
<#
  Wire a project into Grimdex: inject/update the marked pointer stanza in the project's
  CLAUDE.md, AGENTS.md, GEMINI.md, .cursorrules, and .github/copilot-instructions.md
  (creating any that are missing). Idempotent — re-runs update the block in place.
    pwsh scripts/wire-project.ps1 -ProjectDir D:\Dev\my-project
#>
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [string]$ProjectId,
    [string]$GrimdexPath = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wire-lib.ps1')

$results = Install-GrimdexPointers -ProjectDir $ProjectDir -GrimdexPath $GrimdexPath -ProjectId $ProjectId
$results | ForEach-Object { Write-Host ("  {0,-9} {1}" -f $_.action, $_.file) }
