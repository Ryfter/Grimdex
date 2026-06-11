#!/usr/bin/env pwsh
# Grimdex scheduling library — task definitions (pure, testable) + register/unregister.
Set-StrictMode -Version Latest

function Get-GrimdexTaskDefinition {
    # Pure: describes one of the two scheduled tasks. Registration consumes this.
    param(
        [Parameter(Mandatory)][ValidateSet('sweep', 'audit')][string]$Kind,
        [Parameter(Mandatory)][string]$GrimdexRoot
    )
    $entry = Join-Path $GrimdexRoot 'scripts' 'run-scheduled.ps1'
    # Task Scheduler does not resolve PATH like a shell — pin the full pwsh path.
    $pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source ?? 'pwsh.exe'
    # Host via conhost: under Windows Terminal the console MoveWindow is a no-op, so
    # the routine window can't be placed on the target display. Classic conhost moves.
    $conhost = Join-Path $env:SystemRoot 'System32' 'conhost.exe'
    [pscustomobject]@{
        kind = $Kind
        taskName = if ($Kind -eq 'sweep') { 'Grimdex-Daily-Sweep' } else { 'Grimdex-Weekly-Audit' }
        execute = $conhost
        argument = "`"$pwshPath`" -NoProfile -File `"$entry`" -Kind $Kind"
        schedule = if ($Kind -eq 'sweep') { 'daily' } else { 'weekly' }
        at = '05:30'
        dayOfWeek = if ($Kind -eq 'audit') { 'Sunday' } else { $null }
        startWhenAvailable = $true   # PC off at 5:30 -> run as soon as it is next able
    }
}

function Install-GrimdexSchedule {
    # Registers (or replaces) both tasks for the current user. Idempotent.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $results = foreach ($kind in 'sweep', 'audit') {
        $def = Get-GrimdexTaskDefinition -Kind $kind -GrimdexRoot $GrimdexRoot
        $action = New-ScheduledTaskAction -Execute $def.execute -Argument $def.argument
        $trigger = if ($def.schedule -eq 'daily') {
            New-ScheduledTaskTrigger -Daily -At $def.at
        } else {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $def.dayOfWeek -At $def.at
        }
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
        Register-ScheduledTask -TaskName $def.taskName -Action $action -Trigger $trigger `
            -Settings $settings -Description "Grimdex $kind routine (d002)" -Force | Out-Null
        [pscustomobject]@{ task = $def.taskName; action = 'registered' }
    }
    return $results
}

function Uninstall-GrimdexSchedule {
    $results = foreach ($name in 'Grimdex-Daily-Sweep', 'Grimdex-Weekly-Audit') {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            [pscustomobject]@{ task = $name; action = 'removed' }
        } else {
            [pscustomobject]@{ task = $name; action = 'absent' }
        }
    }
    return $results
}
