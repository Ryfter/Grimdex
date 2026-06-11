#!/usr/bin/env pwsh
# Tests for scripts/console-lib.ps1 — bounds resolution only. Deliberately does NOT
# call Set-GrimdexConsoleWindow: it would retitle/move the test runner's own console.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'console-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

$b = Get-GrimdexDisplayBounds -Display 2
Assert 'bounds: null or a rectangle, never a throw' ($null -eq $b -or ($b.Width -gt 0 -and $b.Height -gt 0))
$b99 = Get-GrimdexDisplayBounds -Display 99
Assert 'absurd display falls back (or null), never a throw' ($null -eq $b99 -or $b99.Width -gt 0)
Assert 'Set-GrimdexConsoleWindow exported' ((Get-Command Set-GrimdexConsoleWindow -ErrorAction SilentlyContinue) -ne $null)

if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll console-lib tests passed." -ForegroundColor Green
