#!/usr/bin/env pwsh
# Tests for scripts/schedule-lib.ps1 — pure builder only; registration is exercised by
# the live install (Get-ScheduledTask verification), not by this suite.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'schedule-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

$root = 'D:\Some\Grimdex Root'   # space on purpose: argument must stay quoted

$d = Get-GrimdexTaskDefinition -Kind sweep -GrimdexRoot $root
Assert 'sweep task name' ($d.taskName -eq 'Grimdex-Daily-Sweep')
Assert 'sweep is daily' ($d.schedule -eq 'daily' -and $null -eq $d.dayOfWeek)
Assert 'sweep at 05:30' ($d.at -eq '05:30')
Assert 'sweep catch-up enabled' ($d.startWhenAvailable)
Assert 'sweep runs run-scheduled.ps1 -Kind sweep' ($d.argument -like '*run-scheduled.ps1" -Kind sweep')
Assert 'sweep path quoted (space-safe)' ($d.argument -like '*-File "*Grimdex Root*"*')
Assert 'sweep hosts via conhost (movable window)' ($d.execute -like '*conhost.exe')
Assert 'sweep argument launches pwsh full path' ($d.argument -like '"*pwsh.exe" -NoProfile*')

$d = Get-GrimdexTaskDefinition -Kind audit -GrimdexRoot $root
Assert 'audit task name' ($d.taskName -eq 'Grimdex-Weekly-Audit')
Assert 'audit is weekly Sunday' ($d.schedule -eq 'weekly' -and $d.dayOfWeek -eq 'Sunday')
Assert 'audit at 05:30' ($d.at -eq '05:30')
Assert 'audit catch-up enabled' ($d.startWhenAvailable)
Assert 'audit runs run-scheduled.ps1 -Kind audit' ($d.argument -like '*-Kind audit')

if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll schedule-lib tests passed." -ForegroundColor Green
