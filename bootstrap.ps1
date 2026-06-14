#!/usr/bin/env pwsh
<#
  One-command onboarding for a machine that has already cloned your Grimdex data repo.
  Links the knowledge + rules junctions and registers the role-appropriate scheduled tasks.
    pwsh bootstrap.ps1            # interactive (setup asks before swapping)
    pwsh bootstrap.ps1 -Force     # non-interactive
  Clone first:  git clone <your-grimdex-data-repo-url> <path>
#>
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
& (Join-Path $root 'setup.ps1') -CreateJunction -LinkRules -Force:$Force
& (Join-Path $root 'scripts' 'install-schedule.ps1')
Write-Host "`nGrimdex is set up on this machine." -ForegroundColor Green
