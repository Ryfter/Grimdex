Set-StrictMode -Version Latest

function Get-GrimdexFleet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path (Join-Path $GrimdexRoot 'config') 'fleet.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $raw = Get-Content -LiteralPath $path -Raw
    try { return ($raw | ConvertFrom-Json) }
    catch { throw "config/fleet.json is malformed JSON: $($_.Exception.Message)" }
}

function Test-FleetWorkerAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Worker)
    $avail = 'available'
    if ($Worker.PSObject.Properties['availability'] -and $Worker.availability) {
        $avail = [string]$Worker.availability
    }
    switch ($avail) {
        'available' { return 'available' }
        'scarce'    { return 'available' }
        'out'       { return 'unavailable' }
        default     { return 'ask' }   # 'unknown' and anything unrecognized
    }
}

function Select-FleetWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Fleet,
        [Parameter(Mandatory)][string]$TaskType,
        [switch]$Explicit,
        [switch]$LateWindow,
        [hashtable]$QuotaState
    )
    $order = 0
    $cands = @()
    foreach ($p in $Fleet.workers.PSObject.Properties) {
        $name = $p.Name
        $w = $Fleet.workers.$name
        # Not every worker declares roles (d037 added alias rows); strict mode throws on a raw read.
        $roles = if ($w.PSObject.Properties['roles']) { @($w.roles) } else { @() }
        if ($roles -contains $TaskType) {
            $cands += [pscustomobject]@{ Name = $name; Worker = $w; Order = $order }
        }
        $order++
    }
    if (-not $Explicit) {
        $cands = @($cands | Where-Object { -not $_.Worker.PSObject.Properties['gate'] })
    }
    $cands = @($cands | Where-Object { (Test-FleetWorkerAvailable $_.Worker) -ne 'unavailable' })

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

    $policy = if ($Fleet.PSObject.Properties['policy']) { $Fleet.policy } else { $null }
    $hintName = $null
    if ($policy) {
        if ($TaskType -eq 'bulk-code'  -and $policy.PSObject.Properties['default_builder'])   { $hintName = $policy.default_builder }
        if ($TaskType -eq 'small-code' -and $policy.PSObject.Properties['small_code_may_use']) { $hintName = $policy.small_code_may_use }
    }
    $chosen = $null
    if ($hintName) { $chosen = $cands | Where-Object { $_.Name -eq $hintName } | Select-Object -First 1 }

    if (-not $chosen) {
        $availRank = { param($s) if ($s -eq 'available') { 0 } elseif ($s -eq 'ask') { 1 } else { 2 } }
        $tierBase  = @{ cheap = 0; mid = 1; build = 2; high = 3 }
        $chosen = $cands | Sort-Object `
            @{ Expression = { & $availRank (Test-FleetWorkerAvailable $_.Worker) } }, `
            @{ Expression = {
                    $t = if ($_.Worker.PSObject.Properties['tier']) { [string]$_.Worker.tier } else { 'mid' }
                    $rank = if ($tierBase.ContainsKey($t)) { $tierBase[$t] } else { 1 }
                    if ($LateWindow) { 3 - $rank } else { $rank }
              } }, `
            @{ Expression = { $_.Order } } |
            Select-Object -First 1
    }
    if (-not $chosen) { return $null }

    $status = Test-FleetWorkerAvailable $chosen.Worker
    $reason = "$TaskType -> $($chosen.Name)"
    if ($hintName -and $chosen.Name -eq $hintName) { $reason += " (policy hint)" }
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
