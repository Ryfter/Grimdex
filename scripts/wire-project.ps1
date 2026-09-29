#!/usr/bin/env pwsh
<#
  Wire a project into Grimdex: inject/update the marked pointer stanza in the project's
  CLAUDE.md, AGENTS.md, GEMINI.md, GROK.md, .cursorrules, and .github/copilot-instructions.md
  (creating any that are missing). Idempotent — re-runs update the block in place.
  Content follows the mode in config/grimdex-mode.json (classic pointer, or the AGENTS.md
  laws block + redirects); -Mode overrides.
    pwsh scripts/wire-project.ps1 -ProjectDir $HOME/dev/my-project
#>
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [string]$ProjectId,
    [string]$GrimdexPath = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('classic', 'agents')][string]$Mode
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wire-lib.ps1')

if (-not $Mode) { $Mode = (Get-GrimdexMode -GrimdexRoot $GrimdexPath).mode }
$results = Install-GrimdexPointers -ProjectDir $ProjectDir -GrimdexPath $GrimdexPath -ProjectId $ProjectId -Mode $Mode
$results | ForEach-Object { Write-Host ("  {0,-9} {1}" -f $_.action, $_.file) }
