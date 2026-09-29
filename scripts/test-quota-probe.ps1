Set-StrictMode -Version Latest
. "$PSScriptRoot/quota-probe.ps1"

$script:fail = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "  PASS: $label" -ForegroundColor Green }
    else { Write-Host "  FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function New-QuotaFixtureRoot($json) {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("quota_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force | Out-Null
    if ($null -ne $json) {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'config') 'quota.json') `
            -Value $json -Encoding UTF8
    }
    return $root
}

Write-Host "Get-GrimdexQuotaConfig"
$goodJson = @'
{ "defaults": { "ceiling_percent": 85, "relax_min_window_minutes": 10080,
                "relax_within_minutes": 1440 },
  "workers": { "opus": { "provider": "claude", "window": "secondary" } },
  "probe": { "cache_ttl_seconds": 300 } }
'@
$g = New-QuotaFixtureRoot $goodJson
$cfg = Get-GrimdexQuotaConfig -GrimdexRoot $g
Assert "parses valid quota.json"  ($null -ne $cfg -and $cfg.defaults.ceiling_percent -eq 85)
Assert "worker binding readable"  ($cfg.workers.opus.window -eq 'secondary')

$absent = New-QuotaFixtureRoot $null
Assert "absent file returns `$null" ($null -eq (Get-GrimdexQuotaConfig -GrimdexRoot $absent))

$bad = New-QuotaFixtureRoot '{ not json at all'
$threw = $false
try { Get-GrimdexQuotaConfig -GrimdexRoot $bad } catch { $threw = $true }
Assert "malformed JSON throws" $threw

Remove-Item -Recurse -Force $g, $absent, $bad -ErrorAction SilentlyContinue

Write-Host "shipped example validates"
$repoRoot = Split-Path $PSScriptRoot -Parent
$examplePath = Join-Path (Join-Path $repoRoot 'config') 'quota.example.json'
Assert "quota.example.json exists" (Test-Path -LiteralPath $examplePath)
$ex = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
Assert "example has defaults.ceiling_percent" `
    (@($ex.defaults.PSObject.Properties | ForEach-Object { $_.Name }) -contains 'ceiling_percent')
Assert "example relax window is long-only (>= 7d)" ($ex.defaults.relax_min_window_minutes -ge 10080)
Assert "example has at least one worker" (@($ex.workers.PSObject.Properties | ForEach-Object { $_.Name }).Count -ge 1)
foreach ($n in @($ex.workers.PSObject.Properties | ForEach-Object { $_.Name })) {
    Assert "example worker '$n' declares a provider" `
        (@($ex.workers.$n.PSObject.Properties | ForEach-Object { $_.Name }) -contains 'provider')
}

Write-Host "Read-StatuslineRateLimits"
$sensorDir = Join-Path ([System.IO.Path]::GetTempPath()) ("qsensor_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sensorDir -Force | Out-Null
$sensorFile = Join-Path $sensorDir 'grimdex-quota-statusline.json'

Set-Content -LiteralPath $sensorFile -Encoding UTF8 -Value @'
{ "five_hour": { "used_percentage": 5.0,  "resets_at": "2026-07-28T14:20:00Z" },
  "seven_day": { "used_percentage": 91.0, "resets_at": "2026-07-30T21:00:00Z" } }
'@
$rl = Read-StatuslineRateLimits -Path $sensorFile
Assert "reads the sensor file"    ($null -ne $rl)
Assert "seven_day percent present" ($rl.seven_day.used_percentage -eq 91.0)

$reading = ConvertFrom-StatuslineRateLimits $rl
Assert "feeds the normalizer" ($reading.Source -eq 'statusline' -and @($reading.Windows).Count -eq 2)

Assert "missing file -> null" `
    ($null -eq (Read-StatuslineRateLimits -Path (Join-Path $sensorDir 'nope.json')))

Set-Content -LiteralPath $sensorFile -Encoding UTF8 -Value '{ broken'
Assert "malformed file -> null (never throws)" ($null -eq (Read-StatuslineRateLimits -Path $sensorFile))

Set-Content -LiteralPath $sensorFile -Encoding UTF8 -Value ''
Assert "empty file -> null" ($null -eq (Read-StatuslineRateLimits -Path $sensorFile))

Remove-Item -Recurse -Force $sensorDir -ErrorAction SilentlyContinue

Assert "default sensor path is under the user profile" `
    ((Get-StatuslineSensorPath) -like '*grimdex-quota-statusline.json')

Write-Host "shipped statusline snippet"
$snippet = Join-Path (Split-Path $PSScriptRoot -Parent) 'universal/snippets/statusline-quota-sensor.sh'
Assert "snippet exists" (Test-Path -LiteralPath $snippet)
$snippetText = Get-Content -LiteralPath $snippet -Raw
Assert "snippet writes the sensor file" ($snippetText -like '*grimdex-quota-statusline.json*')
Assert "snippet reads rate_limits"      ($snippetText -like '*rate_limits*')

Write-Host "Get-QuotaState"
$stateCfg = @'
{ "defaults": { "ceiling_percent": 85, "relax_min_window_minutes": 10080,
                "relax_within_minutes": 1440 },
  "workers": {
    "opus":   { "provider": "claude", "window": "secondary" },
    "fable":  { "provider": "claude", "window": "claude-weekly-scoped-fable" },
    "codex":  { "provider": "codex",  "window": "secondary", "ceiling_percent": 50 },
    "ghost":  { "provider": "nosuchprovider", "window": "secondary" } },
  "probe": { "cache_ttl_seconds": 300 } }
'@
$sroot = New-QuotaFixtureRoot $stateCfg

$payload = @'
[
  { "cost": null, "provider": "claude", "source": "oauth",
    "usage": {
      "primary":   { "is_informational": false, "used_percent": 5.0,  "window_minutes": 300,
                     "resets_at": "2026-07-28T14:20:00Z" },
      "secondary": { "is_informational": false, "used_percent": 91.0, "window_minutes": 10080,
                     "resets_at": "2026-07-30T21:00:00Z" },
      "extra_rate_windows": [
        { "id": "claude-weekly-scoped-fable", "title": "Fable only",
          "window": { "is_informational": false, "used_percent": 100.0,
                      "window_minutes": 10080, "resets_at": "2026-07-30T21:00:00Z" } } ],
      "updated_at": "2026-07-28T09:35:08Z" } },
  { "cost": null, "provider": "codex", "source": "oauth",
    "usage": { "secondary": { "is_informational": false, "used_percent": 20.0,
                              "window_minutes": 10080, "resets_at": "2026-07-30T21:00:00Z" },
               "updated_at": "2026-07-28T09:35:08Z" } }
]
'@
$probe = { $payload | ConvertFrom-Json }.GetNewClosure()
$noStatusline = { $null }
$now = [datetime]::Parse('2026-07-28T09:40:00Z').ToUniversalTime()

# NOTE: Get-QuotaState falls back to the REAL user cache (Get-QuotaCachePath) whenever
# -CachePath is omitted. Every call below must pass a scoped temp path so the suite never
# touches $env:LOCALAPPDATA\Grimdex\quota-cache.json.
$cacheDir0 = Join-Path ([System.IO.Path]::GetTempPath()) ("qstate_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $cacheDir0 -Force | Out-Null
$cacheFile0 = Join-Path $cacheDir0 'quota-cache.json'

$state = Get-QuotaState -GrimdexRoot $sroot -Now $now -ProbeCommand $probe -StatuslineReader $noStatusline -CachePath $cacheFile0
Assert "state keyed by worker"        ($state -is [hashtable] -and $state.ContainsKey('opus'))
Assert "opus over ceiling (91 > 85)"  ($state['opus'].OverCeiling -eq $true)
Assert "opus note is readable"        ($state['opus'].Note -eq 'claude 7d 91% > ceiling 85%')
Assert "opus source recorded"         ($state['opus'].Source -eq 'codexbar:oauth')
Assert "opus AsOf recorded"           ($null -ne $state['opus'].AsOf)
Assert "fable uses its scoped window" ($state['fable'].OverCeiling -eq $true -and $state['fable'].UsedPercent -eq 100.0)
Assert "codex under its own 50 ceiling" ($state['codex'].OverCeiling -eq $false)
Assert "codex ceiling is 50"          ($state['codex'].CeilingPercent -eq 50)
Assert "unknown provider fails open"  ($state['ghost'].OverCeiling -eq $false)
Assert "unknown provider marked declared" ($state['ghost'].Source -eq 'declared')
Assert "unknown provider carries a suggestion" ($null -ne $state['ghost'].Suggestion)
Assert "measured worker has no suggestion"     ($null -eq $state['opus'].Suggestion)
Assert "no relaxation 2+ days out"    ($state['opus'].RelaxationAvailable -eq $false)

$lastDay = [datetime]::Parse('2026-07-30T09:00:00Z').ToUniversalTime()
$state2 = Get-QuotaState -GrimdexRoot $sroot -Now $lastDay -ProbeCommand $probe -StatuslineReader $noStatusline -CachePath $cacheFile0
Assert "relaxation opens in the last day" ($state2['opus'].RelaxationAvailable -eq $true)

# Layer 2: probe returns nothing, statusline covers Claude.
$deadProbe = { $null }
$statusline = { '{ "seven_day": { "used_percentage": 95.0, "resets_at": "2026-07-30T21:00:00Z" } }' |
    ConvertFrom-Json }.GetNewClosure()
$state3 = Get-QuotaState -GrimdexRoot $sroot -Now $now -ProbeCommand $deadProbe -StatuslineReader $statusline -CachePath $cacheFile0
Assert "falls back to statusline"     ($state3['opus'].Source -eq 'statusline')
Assert "statusline breach detected"   ($state3['opus'].OverCeiling -eq $true)
Assert "non-claude worker falls to declared" ($state3['codex'].Source -eq 'declared')

# Layer 3: nothing at all — everything fails open with a suggestion.
$state4 = Get-QuotaState -GrimdexRoot $sroot -Now $now -ProbeCommand $deadProbe -StatuslineReader $noStatusline -CachePath $cacheFile0
Assert "no probes -> nothing excluded" `
    (@($state4.Keys | Where-Object { $state4[$_].OverCeiling }).Count -eq 0)
Assert "no probes -> suggestion present" ($null -ne $state4['opus'].Suggestion)
Assert "suggestion names CodexBar"       ($state4['opus'].Suggestion -like '*CodexBar*')

# No config at all -> feature inert.
$noCfg = New-QuotaFixtureRoot $null
$state5 = Get-QuotaState -GrimdexRoot $noCfg -Now $now -ProbeCommand $probe -StatuslineReader $noStatusline -CachePath $cacheFile0
Assert "absent quota.json -> empty state" ($state5 -is [hashtable] -and $state5.Count -eq 0)

Write-Host "quota cache"
$cacheDir  = Join-Path ([System.IO.Path]::GetTempPath()) ("qcache_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
$cacheFile = Join-Path $cacheDir 'quota-cache.json'

Assert "missing cache -> null" ($null -eq (Read-QuotaCache -Path $cacheFile -TtlSeconds 300 -Now $now))

Write-QuotaCache -Path $cacheFile -Payload ($payload | ConvertFrom-Json) -Now $now
Assert "cache file written" (Test-Path -LiteralPath $cacheFile)
$fresh = Read-QuotaCache -Path $cacheFile -TtlSeconds 300 -Now $now.AddSeconds(60)
Assert "fresh cache returns payload" ($null -ne $fresh -and @($fresh).Count -eq 2)
Assert "expired cache -> null" `
    ($null -eq (Read-QuotaCache -Path $cacheFile -TtlSeconds 300 -Now $now.AddSeconds(600)))

Set-Content -LiteralPath $cacheFile -Encoding UTF8 -Value '{ broken'
Assert "corrupt cache -> null (never throws)" `
    ($null -eq (Read-QuotaCache -Path $cacheFile -TtlSeconds 300 -Now $now))

# A live probe populates the cache; a later call reuses it without probing again.
# NOTE: a plain `$script:probeCalls++` inside a .GetNewClosure() scriptblock does NOT
# mutate the outer script-scope counter -- GetNewClosure() snapshots a private copy of
# script scope at creation time, so the increment lands on that disconnected copy and
# the real counter never moves. A reference type (hashtable) escapes the snapshot because
# both copies still point at the same object, so mutating a property is visible outside.
$script:probeCalls = @{ n = 0 }
$countingProbe = { $script:probeCalls.n++; $payload | ConvertFrom-Json }.GetNewClosure()
$cacheFile2 = Join-Path $cacheDir 'chain-cache.json'
$c1 = Get-QuotaState -GrimdexRoot $sroot -Now $now -ProbeCommand $countingProbe `
        -StatuslineReader $noStatusline -CachePath $cacheFile2
$c2 = Get-QuotaState -GrimdexRoot $sroot -Now $now.AddSeconds(60) -ProbeCommand $countingProbe `
        -StatuslineReader $noStatusline -CachePath $cacheFile2
Assert "probe ran once, second call served from cache" ($script:probeCalls.n -eq 1)
Assert "cached run yields the same verdict" `
    ($c1['opus'].OverCeiling -eq $true -and $c2['opus'].OverCeiling -eq $true)

$c3 = Get-QuotaState -GrimdexRoot $sroot -Now $now.AddSeconds(600) -ProbeCommand $countingProbe `
        -StatuslineReader $noStatusline -CachePath $cacheFile2
Assert "expired cache re-probes" ($script:probeCalls.n -eq 2)

$c4 = Get-QuotaState -GrimdexRoot $sroot -Now $now.AddSeconds(605) -ProbeCommand $countingProbe `
        -StatuslineReader $noStatusline -CachePath $cacheFile2 -NoCache
Assert "-NoCache always re-probes" ($script:probeCalls.n -eq 3)

Write-Host "sensor file: Baton snapshot shape, observed_at, configured path"
$sensorDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sensor_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sensorDir -Force | Out-Null
$sensorFile = Join-Path $sensorDir 'claude-quota.json'
Set-Content -LiteralPath $sensorFile -Encoding UTF8 -Value (
    '{ "schema": 1, "seven_day": { "used_pct": 95, "resets_at_unix": "' +
    ([DateTimeOffset]$now.AddDays(2)).ToUnixTimeSeconds() + '" } }')
$rl = Read-StatuslineRateLimits -Path $sensorFile
Assert "sensor read stamps observed_at from mtime" ($null -ne $rl.observed_at)
$sensorCfg = New-QuotaFixtureRoot (@{
    defaults = @{ ceiling_percent = 85 }
    workers = @{ opus = @{ provider = 'claude'; window = 'secondary' } }
    probe   = @{ statusline_path = $sensorFile } } | ConvertTo-Json -Depth 5)
$s6 = Get-QuotaState -GrimdexRoot $sensorCfg -Now $now -ProbeCommand $deadProbe -CachePath $cacheFile0
Assert "configured statusline_path is read"  ($s6['opus'].Source -eq 'statusline')
Assert "epoch-reset sensor breach enforced"  ($s6['opus'].OverCeiling -eq $true)
Assert "sensor reading carries AsOf"         ($null -ne $s6['opus'].AsOf)
$s7 = Get-QuotaState -GrimdexRoot $sensorCfg -Now $now.AddDays(3) -ProbeCommand $deadProbe -CachePath $cacheFile0
Assert "sensor past its reset -> not enforced" ($s7['opus'].OverCeiling -eq $false)
$s8 = Get-QuotaState -GrimdexRoot $sensorCfg -Now $now.ToLocalTime() -ProbeCommand $deadProbe -CachePath $cacheFile0
Assert "local-time -Now gives same verdict"  ($s8['opus'].OverCeiling -eq $true)

Write-Host "provider errors surface in notes"
$errProbe = { '[{ "provider": "claude", "error": { "code": 1, "kind": "auth", "message": "token expired" } }]' | ConvertFrom-Json }
$s9 = Get-QuotaState -GrimdexRoot $sroot -Now $now -ProbeCommand $errProbe -StatuslineReader $noStatusline -CachePath $cacheFile0 -NoCache
Assert "errored provider fails open"         ($s9['opus'].OverCeiling -eq $false)
Assert "note names the probe error"          ($s9['opus'].Note -like '*token expired*')
Assert "suggestion is not 'install CodexBar'" ($s9['opus'].Suggestion -notlike '*Install CodexBar*')
Remove-Item -Recurse -Force $sensorDir, $sensorCfg -ErrorAction SilentlyContinue

Remove-Item -Recurse -Force $sroot, $noCfg, $cacheDir, $cacheDir0 -ErrorAction SilentlyContinue

if ($script:fail) { Write-Host "`n$script:fail FAILED" -ForegroundColor Red; exit 1 }
else { Write-Host "`nAll passed" -ForegroundColor Green }
