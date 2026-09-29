Set-StrictMode -Version Latest
. "$PSScriptRoot/quota-lib.ps1"

function Get-GrimdexQuotaConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path (Join-Path $GrimdexRoot 'config') 'quota.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $raw = Get-Content -LiteralPath $path -Raw
    try { return ($raw | ConvertFrom-Json) }
    catch { throw "config/quota.json is malformed JSON: $($_.Exception.Message)" }
}

function Get-StatuslineSensorPath {
    [CmdletBinding()]
    param()
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return (Join-Path (Join-Path $home_ '.claude') 'grimdex-quota-statusline.json')
}

function Read-StatuslineRateLimits {
    [CmdletBinding()]
    param([string]$Path)
    if (-not $Path) { $Path = Get-StatuslineSensorPath }
    if ($Path -like '~*') { $Path = $HOME + $Path.Substring(1) }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        # Readings must carry their age (spec: "AsOf travels with every reading"). Prefer the
        # sensor's own observed_at; otherwise stamp the file's write time.
        if ($null -ne $obj -and -not $obj.PSObject.Properties['observed_at']) {
            $obj | Add-Member -NotePropertyName observed_at `
                -NotePropertyValue (Get-Item -LiteralPath $Path).LastWriteTimeUtc.ToString('o')
        }
        return $obj
    } catch { return $null }
}

function Get-QuotaCachePath {
    [CmdletBinding()]
    param()
    if ($env:LOCALAPPDATA) {
        return (Join-Path (Join-Path $env:LOCALAPPDATA 'Grimdex') 'quota-cache.json')
    }
    $home_ = if ($env:HOME) { $env:HOME } else { $HOME }
    return (Join-Path (Join-Path $home_ '.local/state/grimdex') 'quota-cache.json')
}

function Get-QuotaSuggestion {
    [CmdletBinding()]
    param([string]$ProbeError)
    if ($ProbeError) {
        return "Usage probe returned an error ($ProbeError); this worker is not enforced until it reads cleanly."
    }
    return 'No live usage reading. Install CodexBar to enable quota holdback: ' +
           'Win-CodexBar (https://github.com/nesszer/Win-CodexBar) on Windows/WSL, ' +
           'CodexBar (https://github.com/steipete/CodexBar) on macOS. ' +
           'Note: ccusage reports tokens and cost, not quota percentages, and cannot drive a holdback.'
}

function Invoke-CodexBarProbe {
    [CmdletBinding()]
    param([string]$Providers = 'all')
    $exe = $null
    # Win-CodexBar ships `codexbar-cli`; steipete's macOS CodexBar ships `codexbar`.
    $cmd = Get-Command 'codexbar-cli', 'codexbar' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { $exe = $cmd.Source }
    elseif ($env:LOCALAPPDATA) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Programs\CodexBar\codexbar-cli.exe'
        if (Test-Path -LiteralPath $candidate) { $exe = $candidate }
    }
    if (-not $exe) { return $null }
    try {
        $raw = & $exe usage --provider $Providers --json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null }
}

function Read-QuotaCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$TtlSeconds,
        [Parameter(Mandatory)][datetime]$Now
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $on = @($obj.PSObject.Properties | ForEach-Object { $_.Name })
        if ($on -notcontains 'cached_at' -or $on -notcontains 'payload') { return $null }
        $cachedAt = ConvertTo-QuotaDateTime $obj.cached_at
        if ($null -eq $cachedAt) { return $null }
        $age = ($Now - $cachedAt).TotalSeconds
        if ($age -lt 0 -or $age -gt $TtlSeconds) { return $null }
        return $obj.payload
    } catch { return $null }
}

function Write-QuotaCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowNull()]$Payload,
        [Parameter(Mandatory)][datetime]$Now
    )
    if ($null -eq $Payload) { return }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $envelope = [pscustomobject]@{
            cached_at = $Now.ToString('o')
            payload   = $Payload
        }
        # Write via a temp file so a concurrent reader never sees a half-written cache.
        $tmp = "$Path.tmp"
        $envelope | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
    } catch { }   # cache failures must never break selection
    return
}

function Get-QuotaState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [datetime]$Now = ([datetime]::UtcNow),
        [scriptblock]$ProbeCommand,
        [scriptblock]$StatuslineReader,
        [string]$CachePath,
        [switch]$NoCache
    )
    # Every age/reset comparison is in UTC; a caller's local-time -Now would skew both.
    $Now = ConvertTo-QuotaDateTime $Now
    $config = Get-GrimdexQuotaConfig -GrimdexRoot $GrimdexRoot
    if ($null -eq $config) { return @{} }
    $cn = @($config.PSObject.Properties | ForEach-Object { $_.Name })
    if ($cn -notcontains 'workers' -or $null -eq $config.workers) { return @{} }

    $ttl = 300
    if ($cn -contains 'probe' -and $null -ne $config.probe -and
        (@($config.probe.PSObject.Properties | ForEach-Object { $_.Name }) -contains 'cache_ttl_seconds') -and
        $null -ne $config.probe.cache_ttl_seconds) {
        $ttl = [int]$config.probe.cache_ttl_seconds
    }
    if (-not $CachePath) { $CachePath = Get-QuotaCachePath }
    $sensorPath = $null
    if ($cn -contains 'probe' -and $null -ne $config.probe) {
        $sensorPath = Get-QuotaField $config.probe 'statusline_path'
    }

    # Layer 1 — CodexBar, served from cache when the cached reading is still fresh.
    $payload = $null
    if (-not $NoCache) { $payload = Read-QuotaCache -Path $CachePath -TtlSeconds $ttl -Now $Now }
    if ($null -eq $payload) {
        $payload = if ($ProbeCommand) { & $ProbeCommand } else { Invoke-CodexBarProbe }
        if ($null -ne $payload) { Write-QuotaCache -Path $CachePath -Payload $payload -Now $Now }
    }
    $readings = @{}
    foreach ($r in (ConvertFrom-CodexBarUsage $payload)) {
        if (-not $readings.ContainsKey($r.Provider)) { $readings[$r.Provider] = $r }
    }

    # Layer 2 — Claude statusline sensor, only if layer 1 produced nothing usable for Claude.
    $claudeUsable = $readings.ContainsKey('claude') -and
                    -not $readings['claude'].Error -and
                    @($readings['claude'].Windows).Count -gt 0
    if (-not $claudeUsable) {
        $rl = if ($StatuslineReader) { & $StatuslineReader } else { Read-StatuslineRateLimits -Path $sensorPath }
        $sr = ConvertFrom-StatuslineRateLimits $rl -AsOf (Get-QuotaField $rl 'observed_at')
        if ($sr) { $readings['claude'] = $sr }
    }

    # Layer 3 — declared: any worker with no reading simply is not enforced.
    $state = @{}
    foreach ($name in @($config.workers.PSObject.Properties | ForEach-Object { $_.Name })) {
        $wc = $config.workers.$name
        $wn = @($wc.PSObject.Properties | ForEach-Object { $_.Name })
        $provider = if ($wn -contains 'provider') { [string]$wc.provider } else { $name }
        $windowId = if ($wn -contains 'window') { [string]$wc.window } else { 'secondary' }
        $ceiling  = Get-QuotaWorkerCeiling -Config $config -Worker $name

        # Errored readings flow through so the breach/relax notes name the error.
        $reading = $null
        if ($readings.ContainsKey($provider)) { $reading = $readings[$provider] }
        $usable  = $reading -and -not $reading.Error
        $breach = Test-QuotaCeilingBreach -Reading $reading -WindowId $windowId -CeilingPercent $ceiling -Now $Now
        $relax  = Get-QuotaRelaxation -Reading $reading -WindowId $windowId -Config $config -Now $Now

        $state[$name] = [pscustomobject]@{
            Worker              = $name
            Provider            = $provider
            WindowId            = $windowId
            Source              = if ($usable) { $reading.Source } else { 'declared' }
            AsOf                = if ($usable) { $reading.AsOf } else { $null }
            OverCeiling         = $breach.OverCeiling
            UsedPercent         = $breach.UsedPercent
            CeilingPercent      = $ceiling
            Note                = $breach.Note
            RelaxationAvailable = $relax.RelaxationAvailable
            RelaxationReason    = $relax.Reason
            Suggestion          = if ($usable) { $null }
                                  elseif ($reading) { Get-QuotaSuggestion -ProbeError $reading.Error }
                                  else { Get-QuotaSuggestion }
        }
    }
    return $state
}
