Set-StrictMode -Version Latest

# The model record and its validation live in models-lib (grimdex-d052). Selection below moves
# to AtomicKestrel in the d052 migration (spec 2026-10-01, step 2).
. (Join-Path $PSScriptRoot 'models-lib.ps1')

function Get-GrimdexFleet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    return Get-GrimdexModels -GrimdexRoot $GrimdexRoot
}

function Test-FleetWorkerAvailable {
    # Uses the effective state: an expired reading counts as 'unknown', so selection asks.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Worker, $Policy, [datetimeoffset]$Now = [datetimeoffset]::UtcNow)
    switch ((Get-GrimdexAvailability -Worker $Worker -Policy $Policy -Now $Now).EffectiveState) {
        'available' { return 'available' }
        'scarce'    { return 'available' }
        'out'       { return 'unavailable' }
        default     { return 'ask' }   # 'unknown', expired, and anything unrecognized
    }
}

function Select-FleetWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Fleet,
        [Parameter(Mandatory)][string]$TaskType,
        [switch]$Explicit,
        # The worker the user named. With -Explicit, the approval covers this worker only.
        [string]$Name,
        [switch]$LateWindow,
        [hashtable]$QuotaState,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $policy = if ($Fleet.PSObject.Properties['policy']) { $Fleet.policy } else { $null }
    $order = 0
    $cands = @()
    foreach ($p in $Fleet.workers.PSObject.Properties) {
        $wName = $p.Name   # not $name: PowerShell names are case-insensitive and $Name is a parameter
        $w = $Fleet.workers.$wName
        # Not every worker declares roles (d037 added alias rows); strict mode throws on a raw read.
        $roles = if ($w.PSObject.Properties['roles']) { @($w.roles) } else { @() }
        if ($roles -contains $TaskType) {
            $cands += [pscustomobject]@{ Name = $wName; Worker = $w; Order = $order }
        }
        $order++
    }
    if ($Explicit -and -not $Name) {
        # Approval of a gated worker is by name; without one, another gated worker with the
        # same role could be returned instead (security audit 2026-10-29).
        throw 'Select-FleetWorker -Explicit needs -Name: the worker the user approved.'
    }
    if ($Name) { $cands = @($cands | Where-Object { $_.Name -eq $Name }) }
    if (-not $Explicit) {
        $cands = @($cands | Where-Object { -not $_.Worker.PSObject.Properties['gate'] })
        # A failed trial is the evidence a model can't finish, and auto-selection has no way to
        # ask. -Explicit still reaches it by name.
        $cands = @($cands | Where-Object { -not (Test-GrimdexTrialFailed -Worker $_.Worker) })
    }
    if ($TaskType -in 'bulk-code', 'small-code') {
        # Operator ruling: some models are never used for programming, even by name (code_exclude).
        $cands = @($cands | Where-Object { -not (Test-GrimdexCodeExcluded -Name $_.Name -Worker $_.Worker -Policy $policy) })
    }
    $cands = @($cands | Where-Object { (Test-FleetWorkerAvailable $_.Worker -Policy $policy -Now $Now) -ne 'unavailable' })

    $quotaNotes    = @()
    $quotaEmptied  = $false
    if ($QuotaState -and $QuotaState.Count -and -not $Explicit -and $cands.Count) {
        $kept = @()
        foreach ($c in $cands) {
            $q = $QuotaState[$c.Name]
            if ($q -and $q.PSObject.Properties['OverCeiling'] -and $q.OverCeiling) { $quotaNotes += "$($c.Name) excluded: $($q.Note)" }
            else { $kept += $c }
        }
        if ($kept.Count) { $cands = @($kept) }
        elseif ($quotaNotes.Count) { $quotaEmptied = $true }   # keep $cands; ask instead of blocking
    }

    if (-not $cands.Count) { return $null }

    # bulk-code follows policy.builder_chain when there is one: free Command Code models first,
    # then the GOAT credit, then the other providers (operator's wish, 2026-10-05). The chain
    # only reorders these candidates — role, gate, trial and availability filtering above already
    # decided who is eligible, so the first chain name still among them wins.
    $chainEntry = $null
    $chainNames = @()
    if ($TaskType -eq 'bulk-code' -and $policy -and $policy.PSObject.Properties['builder_chain']) {
        $chainNames = @(Resolve-GrimdexBuilderChain -Models $Fleet -Now $Now -WithEntry)
    }

    $hintName = $null
    if ($policy) {
        if ($TaskType -eq 'bulk-code') {
            if ($chainNames.Count) { $hintName = $chainNames[0].Name }   # entry is labelled only if the chain actually picks
            elseif ($policy.PSObject.Properties['default_builder']) { $hintName = $policy.default_builder }
        }
        if ($TaskType -eq 'small-code' -and $policy.PSObject.Properties['small_code_may_use']) { $hintName = $policy.small_code_may_use }
    }
    $chosen = $null
    if ($chainNames.Count) {
        foreach ($entry in $chainNames) {
            $chosen = $cands | Where-Object { $_.Name -eq $entry.Name } | Select-Object -First 1
            if ($chosen) { $chainEntry = $entry.Entry; break }
        }
    }
    elseif ($hintName) { $chosen = $cands | Where-Object { $_.Name -eq $hintName } | Select-Object -First 1 }

    if (-not $chosen) {
        $availRank = { param($s) if ($s -eq 'available') { 0 } elseif ($s -eq 'ask') { 1 } else { 2 } }
        $tierBase  = @{ cheap = 0; mid = 1; build = 2; high = 3 }
        $chosen = $cands | Sort-Object `
            @{ Expression = { & $availRank (Test-FleetWorkerAvailable $_.Worker -Policy $policy -Now $Now) } }, `
            @{ Expression = {
                    $t = if ($_.Worker.PSObject.Properties['tier']) { [string]$_.Worker.tier } else { 'mid' }
                    $rank = if ($tierBase.ContainsKey($t)) { $tierBase[$t] } else { 1 }
                    if ($LateWindow) { 3 - $rank } else { $rank }
              } }, `
            @{ Expression = { $_.Order } } |
            Select-Object -First 1
    }
    if (-not $chosen) { return $null }

    $status = Test-FleetWorkerAvailable $chosen.Worker -Policy $policy -Now $Now
    $reason = "$TaskType -> $($chosen.Name)"
    if ($chainEntry) { $reason += " (builder chain: $chainEntry)" }
    elseif ($hintName -and $chosen.Name -eq $hintName) { $reason += " (policy hint)" }
    elseif ($LateWindow) { $reason += " (late-window: high tier)" }
    else { $reason += " ($status)" }

    $needsAsk = ($status -eq 'ask')
    if ($quotaEmptied) {
        $q = $QuotaState[$chosen.Name]
        $note = if ($q -and $q.PSObject.Properties['Note']) { $q.Note } else { 'over ceiling' }
        $reason += " (quota: $note; every worker for this role is over its ceiling — ask before spending the reserve)"
        $needsAsk = $true
    }
    elseif ($quotaNotes.Count) {
        $reason += " ($($quotaNotes -join '; '))"
    }

    return [pscustomobject]@{
        Name = $chosen.Name; Worker = $chosen.Worker; Reason = $reason
        NeedsAsk = $needsAsk
    }
}
