#!/usr/bin/env pwsh
# Grimdex scheduling library — task definitions (pure, testable) + register/unregister.
Set-StrictMode -Version Latest

function Get-GrimdexTaskDefinition {
    param(
        [Parameter(Mandatory)][ValidateSet('sweep', 'audit', 'pull')][string]$Kind,
        [Parameter(Mandatory)][string]$GrimdexRoot
    )
    $pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source ?? 'pwsh.exe'
    $conhost = Join-Path $env:SystemRoot 'System32' 'conhost.exe'
    if ($Kind -eq 'pull') {
        $entry = Join-Path $GrimdexRoot 'scripts' 'run-sync.ps1'
        $argument = "`"$pwshPath`" -NoProfile -File `"$entry`""
    } else {
        $entry = Join-Path $GrimdexRoot 'scripts' 'run-scheduled.ps1'
        $argument = "`"$pwshPath`" -NoProfile -File `"$entry`" -Kind $Kind"
    }
    $taskName = switch ($Kind) {
        'sweep' { 'Grimdex-Daily-Sweep' }
        'audit' { 'Grimdex-Weekly-Audit' }
        'pull'  { 'Grimdex-Daily-Pull' }
    }
    [pscustomobject]@{
        kind = $Kind
        taskName = $taskName
        execute = $conhost
        argument = $argument
        schedule = if ($Kind -eq 'audit') { 'weekly' } else { 'daily' }
        at = '05:30'
        dayOfWeek = if ($Kind -eq 'audit') { 'Sunday' } else { $null }
        startWhenAvailable = $true
    }
}

function Get-GrimdexScheduleTaskNames {
    # Which scheduled tasks a machine of this role runs.
    param([Parameter(Mandatory)][ValidateSet('hub', 'spoke')][string]$Role)
    if ($Role -eq 'hub') { @('Grimdex-Daily-Sweep', 'Grimdex-Weekly-Audit') } else { @('Grimdex-Daily-Pull') }
}

function Install-GrimdexSchedule {
    # Registers the tasks for the given role. Idempotent.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][ValidateSet('hub', 'spoke')][string]$Role
    )
    $kinds = if ($Role -eq 'hub') { 'sweep', 'audit' } else { @('pull') }
    $results = foreach ($kind in $kinds) {
        $def = Get-GrimdexTaskDefinition -Kind $kind -GrimdexRoot $GrimdexRoot
        $action = New-ScheduledTaskAction -Execute $def.execute -Argument $def.argument
        $trigger = if ($def.schedule -eq 'daily') {
            New-ScheduledTaskTrigger -Daily -At $def.at
        } else {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $def.dayOfWeek -At $def.at
        }
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
        Register-ScheduledTask -TaskName $def.taskName -Action $action -Trigger $trigger `
            -Settings $settings -Description "Grimdex $kind routine (d002/d008)" -Force | Out-Null
        [pscustomobject]@{ task = $def.taskName; action = 'registered' }
    }
    return $results
}

function Uninstall-GrimdexSchedule {
    $results = foreach ($name in 'Grimdex-Daily-Sweep', 'Grimdex-Weekly-Audit', 'Grimdex-Daily-Pull') {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            [pscustomobject]@{ task = $name; action = 'removed' }
        } else {
            [pscustomobject]@{ task = $name; action = 'absent' }
        }
    }
    return $results
}
