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
    if ($Worker.PSObject.Properties.Name -contains 'availability' -and $Worker.availability) {
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
        [switch]$LateWindow
    )
    $order = 0
    $cands = @()
    foreach ($name in $Fleet.workers.PSObject.Properties.Name) {
        $w = $Fleet.workers.$name
        $roles = @($w.roles)
        if ($roles -contains $TaskType) {
            $cands += [pscustomobject]@{ Name = $name; Worker = $w; Order = $order }
        }
        $order++
    }
    if (-not $Explicit) {
        $cands = @($cands | Where-Object { -not ($_.Worker.PSObject.Properties.Name -contains 'gate') })
    }
    $cands = @($cands | Where-Object { (Test-FleetWorkerAvailable $_.Worker) -ne 'unavailable' })
    if (-not $cands.Count) { return $null }

    $policy = if ($Fleet.PSObject.Properties.Name -contains 'policy') { $Fleet.policy } else { $null }
    $hintName = $null
    if ($policy) {
        if ($TaskType -eq 'bulk-code'  -and $policy.PSObject.Properties.Name -contains 'default_builder')   { $hintName = $policy.default_builder }
        if ($TaskType -eq 'small-code' -and $policy.PSObject.Properties.Name -contains 'small_code_may_use') { $hintName = $policy.small_code_may_use }
    }
    $chosen = $null
    if ($hintName) { $chosen = $cands | Where-Object { $_.Name -eq $hintName } | Select-Object -First 1 }

    if (-not $chosen) {
        $availRank = { param($s) if ($s -eq 'available') { 0 } elseif ($s -eq 'ask') { 1 } else { 2 } }
        $tierBase  = @{ cheap = 0; mid = 1; build = 2; high = 3 }
        $chosen = $cands | Sort-Object `
            @{ Expression = { & $availRank (Test-FleetWorkerAvailable $_.Worker) } }, `
            @{ Expression = {
                    $t = if ($_.Worker.PSObject.Properties.Name -contains 'tier') { [string]$_.Worker.tier } else { 'mid' }
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

    return [pscustomobject]@{
        Name = $chosen.Name; Worker = $chosen.Worker; Reason = $reason
        NeedsAsk = ($status -eq 'ask')
    }
}
