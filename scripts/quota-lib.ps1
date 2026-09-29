Set-StrictMode -Version Latest

# Read the first present, non-null field among $Names. CodexBar's JSON is camelCase
# (usedPercent, resetsAt) while Win-CodexBar and the spec fixtures are snake_case, so
# every payload field is looked up under both spellings.
function Get-QuotaField {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowNull()]$Object,
        [Parameter(Mandatory, Position = 1)][string[]]$Names
    )
    if ($null -eq $Object) { return $null }
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if ($p -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}

function ConvertTo-QuotaDateTime {
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        # ConvertFrom-Json turns ISO strings into [datetime]; a zoneless one arrives as
        # Unspecified and must be read as UTC, same as the string path below.
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }
        return $Value.ToUniversalTime()
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    # Claude Code's statusline reports resets_at as Unix epoch seconds.
    if ($s -match '^\d{9,11}$') {
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$s).UtcDateTime
    }
    # CodexBar emits up to 9 fractional-second digits. PowerShell 7 truncates those fine,
    # but that is undocumented runtime behavior, so normalize to 7 rather than rely on it.
    $s = [regex]::Replace($s, '(\.\d{7})\d+', '$1')
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal `
        -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($s, [cultureinfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed }
    return $null
}

function ConvertTo-QuotaWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][AllowNull()]$Raw
    )
    if ($null -eq $Raw) { return $null }
    $used = Get-QuotaField $Raw 'used_percent', 'usedPercent'
    if ($null -eq $used) { return $null }
    $minutes = 0
    $wm = Get-QuotaField $Raw 'window_minutes', 'windowMinutes'
    if ($null -ne $wm) { $minutes = [int]$wm }
    $resets = ConvertTo-QuotaDateTime (Get-QuotaField $Raw 'resets_at', 'resetsAt')
    $info = [bool](Get-QuotaField $Raw 'is_informational', 'isInformational')
    return [pscustomobject]@{
        Id              = $Id
        UsedPercent     = [double]$used
        WindowMinutes   = $minutes
        ResetsAt        = $resets
        IsInformational = $info
    }
}

function ConvertFrom-CodexBarUsage {
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$Payload)
    $out = @()
    if ($null -eq $Payload) { return $out }
    foreach ($entry in @($Payload)) {
        if ($null -eq $entry) { continue }
        $names = @($entry.PSObject.Properties | ForEach-Object { $_.Name })
        $provider = $null
        if ($names -contains 'provider' -and $entry.provider) { $provider = [string]$entry.provider }
        if (-not $provider) { continue }

        if ($names -contains 'error' -and $entry.error) {
            # CodexBar reports errors as {code, kind, message}; keep the message readable.
            $err = $entry.error
            $msg = Get-QuotaField $err 'message'
            $errText = if ($err -isnot [string] -and $null -ne $msg) { [string]$msg } else { [string]$err }
            $out += [pscustomobject]@{
                Provider = $provider; Source = 'codexbar'; AsOf = $null
                Windows = @(); Error = $errText
            }
            continue
        }
        if ($names -notcontains 'usage' -or $null -eq $entry.usage) {
            $out += [pscustomobject]@{
                Provider = $provider; Source = 'codexbar'; AsOf = $null
                Windows = @(); Error = 'no usage data in payload'
            }
            continue
        }

        $u  = $entry.usage
        $un = @($u.PSObject.Properties | ForEach-Object { $_.Name })
        $windows = @()
        foreach ($slot in @('primary', 'secondary')) {
            if ($un -contains $slot) {
                $w = ConvertTo-QuotaWindow -Id $slot -Raw $u.$slot
                if ($w) { $windows += $w }
            }
        }
        $extra = Get-QuotaField $u 'extra_rate_windows', 'extraRateWindows'
        if ($null -ne $extra) {
            foreach ($x in @($extra)) {
                if ($null -eq $x) { continue }
                $xn = @($x.PSObject.Properties | ForEach-Object { $_.Name })
                if ($xn -notcontains 'id' -or $xn -notcontains 'window') { continue }
                $w = ConvertTo-QuotaWindow -Id ([string]$x.id) -Raw $x.window
                if ($w) { $windows += $w }
            }
        }
        $source = 'codexbar'
        if ($names -contains 'source' -and $entry.source) { $source = "codexbar:$([string]$entry.source)" }
        $asOf = ConvertTo-QuotaDateTime (Get-QuotaField $u 'updated_at', 'updatedAt')

        $out += [pscustomobject]@{
            Provider = $provider; Source = $source; AsOf = $asOf
            Windows = $windows; Error = $null
        }
    }
    return $out
}

function Format-QuotaWindowLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)]$Window)
    $m = [int]$Window.WindowMinutes
    if ($m -le 0) { return [string]$Window.Id }
    if ($m % 1440 -eq 0) { return "$([int]($m / 1440))d" }
    if ($m % 60 -eq 0)   { return "$([int]($m / 60))h" }
    return "${m}m"
}

function ConvertFrom-StatuslineRateLimits {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowNull()]$RateLimits,
        [AllowNull()]$AsOf
    )
    if ($null -eq $RateLimits) { return $null }
    $names = @($RateLimits.PSObject.Properties | ForEach-Object { $_.Name })
    $map = @(
        @{ Key = 'five_hour'; Id = 'primary';   Minutes = 300 },
        @{ Key = 'seven_day'; Id = 'secondary'; Minutes = 10080 }
    )
    $windows = @()
    foreach ($m in $map) {
        if ($names -notcontains $m.Key) { continue }
        $slot = $RateLimits.($m.Key)
        if ($null -eq $slot) { continue }
        # Claude Code's rate_limits use used_percentage / resets_at; the Baton statusline
        # snapshot (~/.baton/claude-quota.json) stores used_pct / resets_at_unix.
        $used = Get-QuotaField $slot 'used_percentage', 'used_pct'
        if ($null -eq $used) { continue }
        $resets = ConvertTo-QuotaDateTime (Get-QuotaField $slot 'resets_at', 'resets_at_unix')
        $windows += [pscustomobject]@{
            Id              = $m.Id
            UsedPercent     = [double]$used
            WindowMinutes   = $m.Minutes
            ResetsAt        = $resets
            IsInformational = $false
        }
    }
    if (-not $windows.Count) { return $null }
    return [pscustomobject]@{
        Provider = 'claude'; Source = 'statusline'; AsOf = (ConvertTo-QuotaDateTime $AsOf)
        Windows = $windows; Error = $null
    }
}

function Get-QuotaWorkerCeiling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Worker
    )
    $cn = @($Config.PSObject.Properties | ForEach-Object { $_.Name })
    if ($cn -contains 'workers' -and $null -ne $Config.workers) {
        $wn = @($Config.workers.PSObject.Properties | ForEach-Object { $_.Name })
        if ($wn -contains $Worker -and $null -ne $Config.workers.$Worker) {
            $wc = $Config.workers.$Worker
            if ((@($wc.PSObject.Properties | ForEach-Object { $_.Name }) -contains 'ceiling_percent') -and
                $null -ne $wc.ceiling_percent) {
                return [double]$wc.ceiling_percent
            }
        }
    }
    if ($cn -contains 'defaults' -and $null -ne $Config.defaults) {
        $dn = @($Config.defaults.PSObject.Properties | ForEach-Object { $_.Name })
        if ($dn -contains 'ceiling_percent' -and $null -ne $Config.defaults.ceiling_percent) {
            return [double]$Config.defaults.ceiling_percent
        }
    }
    return [double]100
}

function Test-QuotaCeilingBreach {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Reading,
        [Parameter(Mandatory)][string]$WindowId,
        [Parameter(Mandatory)][double]$CeilingPercent,
        [Nullable[datetime]]$Now
    )
    $clear = {
        param($note)
        [pscustomobject]@{
            OverCeiling = $false; UsedPercent = $null
            CeilingPercent = $CeilingPercent; WindowId = $WindowId; Note = $note
        }
    }
    if ($null -eq $Reading) { return (& $clear 'no reading available') }
    if ($Reading.Error)     { return (& $clear "no reading: $($Reading.Error)") }

    $w = @($Reading.Windows) | Where-Object { $_.Id -eq $WindowId } | Select-Object -First 1
    if (-not $w) { return (& $clear "$($Reading.Provider) does not report window '$WindowId'") }

    $label = Format-QuotaWindowLabel $w
    if ($w.IsInformational) {
        return (& $clear "$($Reading.Provider) $label is informational; not enforced")
    }
    # A window whose reset has already passed has since refilled: the reading is stale,
    # and d017 says a missing/unusable reading fails open, never closed.
    if ($null -ne $Now -and $null -ne $w.ResetsAt -and $w.ResetsAt -lt (ConvertTo-QuotaDateTime $Now)) {
        return (& $clear "$($Reading.Provider) $label reset time is in the past; reading is stale")
    }

    $over = ($w.UsedPercent -gt $CeilingPercent)
    $cmp  = if ($over) { '>' } else { '<=' }
    $note = "$($Reading.Provider) $label $([int][math]::Round($w.UsedPercent))% $cmp " +
            "ceiling $([int][math]::Round($CeilingPercent))%"
    return [pscustomobject]@{
        OverCeiling = $over; UsedPercent = $w.UsedPercent
        CeilingPercent = $CeilingPercent; WindowId = $WindowId; Note = $note
    }
}

function Get-QuotaRelaxation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Reading,
        [Parameter(Mandatory)][string]$WindowId,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][datetime]$Now
    )
    $minWindow = 10080
    $within    = 1440
    $cn = @($Config.PSObject.Properties | ForEach-Object { $_.Name })
    if ($cn -contains 'defaults' -and $null -ne $Config.defaults) {
        $dn = @($Config.defaults.PSObject.Properties | ForEach-Object { $_.Name })
        if ($dn -contains 'relax_min_window_minutes' -and $null -ne $Config.defaults.relax_min_window_minutes) {
            $minWindow = [int]$Config.defaults.relax_min_window_minutes
        }
        if ($dn -contains 'relax_within_minutes' -and $null -ne $Config.defaults.relax_within_minutes) {
            $within = [int]$Config.defaults.relax_within_minutes
        }
    }
    $no = { param($why) [pscustomobject]@{ RelaxationAvailable = $false; Reason = $why } }

    if ($null -eq $Reading) { return (& $no 'no reading available') }
    if ($Reading.Error)     { return (& $no "no reading: $($Reading.Error)") }

    $w = @($Reading.Windows) | Where-Object { $_.Id -eq $WindowId } | Select-Object -First 1
    if (-not $w) { return (& $no "$($Reading.Provider) does not report window '$WindowId'") }

    $label = Format-QuotaWindowLabel $w
    if ($w.WindowMinutes -lt $minWindow) {
        return (& $no "$label is a short window; relaxation is long-window only")
    }
    if ($null -eq $w.ResetsAt) { return (& $no "no reset time reported for $label") }

    $mins = [int][math]::Round(($w.ResetsAt - (ConvertTo-QuotaDateTime $Now)).TotalMinutes)
    if ($mins -lt 0)      { return (& $no "$label reset time is in the past; reading is stale") }
    if ($mins -gt $within) { return (& $no "$mins min until reset; relaxation opens inside $within min") }

    return [pscustomobject]@{
        RelaxationAvailable = $true
        Reason = "$label resets in $mins min (inside the $within-min relax window) — ask the human before spending the reserve"
    }
}
