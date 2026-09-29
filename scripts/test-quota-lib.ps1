Set-StrictMode -Version Latest
. "$PSScriptRoot/quota-lib.ps1"

$script:fail = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "  PASS: $label" -ForegroundColor Green }
    else { Write-Host "  FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

# Verbatim capture from `codexbar-cli usage -p all --json`, 2026-07-28.
$script:codexbarJson = @'
[
  { "cost": null, "provider": "claude", "source": "oauth",
    "usage": {
      "login_method": "Claude Max 5x",
      "primary":   { "is_informational": false, "used_percent": 5.0,  "window_minutes": 300,
                     "resets_at": "2026-07-28T14:20:00.111760Z", "reset_description": "Jul 28 at 2:20PM" },
      "secondary": { "is_informational": false, "used_percent": 91.0, "window_minutes": 10080,
                     "resets_at": "2026-07-30T21:00:00.111780Z", "reset_description": "Jul 30 at 9:00PM" },
      "extra_rate_windows": [
        { "id": "claude-weekly-scoped-fable", "title": "Fable only",
          "window": { "is_informational": false, "used_percent": 100.0, "window_minutes": 10080,
                      "resets_at": "2026-07-30T21:00:00.111990Z" } } ],
      "updated_at": "2026-07-28T09:35:08.827796200Z" } },
  { "error": "No cookies available for web API", "provider": "cursor" },
  { "cost": null, "provider": "grok", "source": "cli",
    "usage": { "primary": { "is_informational": true, "used_percent": 12.0, "window_minutes": 1440,
                            "resets_at": "2026-07-29T00:00:00Z" },
               "updated_at": "2026-07-28T09:35:08Z" } }
]
'@

Write-Host "ConvertTo-QuotaDateTime"
Assert "parses 9-digit fractional seconds" `
    ((ConvertTo-QuotaDateTime '2026-07-28T09:35:08.827796200Z').Year -eq 2026)
Assert "parses plain Z timestamp" `
    ((ConvertTo-QuotaDateTime '2026-07-30T21:00:00Z').Day -eq 30)
Assert "null in -> null out"     ($null -eq (ConvertTo-QuotaDateTime $null))
Assert "empty string -> null"    ($null -eq (ConvertTo-QuotaDateTime ''))
Assert "garbage -> null"         ($null -eq (ConvertTo-QuotaDateTime 'not a date'))

Write-Host "ConvertFrom-CodexBarUsage"
$readings = ConvertFrom-CodexBarUsage ($script:codexbarJson | ConvertFrom-Json)
Assert "returns one reading per entry" (@($readings).Count -eq 3)

$claude = @($readings) | Where-Object { $_.Provider -eq 'claude' } | Select-Object -First 1
Assert "claude reading found"            ($null -ne $claude)
Assert "source is prefixed"              ($claude.Source -eq 'codexbar:oauth')
Assert "no error on success entry"       ($null -eq $claude.Error)
Assert "AsOf parsed from usage.updated_at" ($claude.AsOf.Year -eq 2026)
Assert "three windows (primary+secondary+extra)" (@($claude.Windows).Count -eq 3)

$sec = @($claude.Windows) | Where-Object { $_.Id -eq 'secondary' } | Select-Object -First 1
Assert "secondary used_percent"  ($sec.UsedPercent -eq 91.0)
Assert "secondary window_minutes" ($sec.WindowMinutes -eq 10080)
Assert "secondary resets_at parsed" ($sec.ResetsAt.Day -eq 30)

$scoped = @($claude.Windows) | Where-Object { $_.Id -eq 'claude-weekly-scoped-fable' } | Select-Object -First 1
Assert "extra window keyed by id"       ($null -ne $scoped)
Assert "extra window reads nested .window" ($scoped.UsedPercent -eq 100.0)

$cursor = @($readings) | Where-Object { $_.Provider -eq 'cursor' } | Select-Object -First 1
Assert "error entry carries Error"   ($cursor.Error -eq 'No cookies available for web API')
Assert "error entry has no windows"  (@($cursor.Windows).Count -eq 0)

$grok = @($readings) | Where-Object { $_.Provider -eq 'grok' } | Select-Object -First 1
Assert "missing extra_rate_windows is fine" (@($grok.Windows).Count -eq 1)
Assert "is_informational preserved" ((@($grok.Windows)[0]).IsInformational -eq $true)

Assert "null payload -> empty array"  (@(ConvertFrom-CodexBarUsage $null).Count -eq 0)
Assert "empty array -> empty array"   (@(ConvertFrom-CodexBarUsage @()).Count -eq 0)
Assert "entry with no provider skipped" (@(ConvertFrom-CodexBarUsage (@'
[{ "source": "oauth", "usage": { "primary": { "used_percent": 1.0 } } }]
'@ | ConvertFrom-Json)).Count -eq 0)

Write-Host "Format-QuotaWindowLabel"
function TW($minutes, $id) { [pscustomobject]@{ Id = $id; WindowMinutes = $minutes } }
Assert "300 -> 5h"        ((Format-QuotaWindowLabel (TW 300 'primary'))     -eq '5h')
Assert "10080 -> 7d"      ((Format-QuotaWindowLabel (TW 10080 'secondary')) -eq '7d')
Assert "43200 -> 30d"     ((Format-QuotaWindowLabel (TW 43200 'secondary')) -eq '30d')
Assert "1440 -> 1d"       ((Format-QuotaWindowLabel (TW 1440 'primary'))    -eq '1d')
Assert "180 -> 3h"        ((Format-QuotaWindowLabel (TW 180 'primary'))     -eq '3h')
Assert "90 -> 90m"        ((Format-QuotaWindowLabel (TW 90 'primary'))      -eq '90m')
Assert "0 -> falls back to Id" ((Format-QuotaWindowLabel (TW 0 'weird-window')) -eq 'weird-window')

Write-Host "ConvertFrom-StatuslineRateLimits"
$rl = @'
{ "five_hour":  { "used_percentage": 5.0,  "resets_at": "2026-07-28T14:20:00Z" },
  "seven_day":  { "used_percentage": 91.0, "resets_at": "2026-07-30T21:00:00Z" } }
'@ | ConvertFrom-Json
$sr = ConvertFrom-StatuslineRateLimits $rl
Assert "provider is claude"      ($sr.Provider -eq 'claude')
Assert "source is statusline"    ($sr.Source -eq 'statusline')
Assert "two windows"             (@($sr.Windows).Count -eq 2)
$sp = @($sr.Windows) | Where-Object { $_.Id -eq 'primary' }   | Select-Object -First 1
$ss = @($sr.Windows) | Where-Object { $_.Id -eq 'secondary' } | Select-Object -First 1
Assert "five_hour -> primary, 300 min"    ($sp.WindowMinutes -eq 300)
Assert "seven_day -> secondary, 10080 min" ($ss.WindowMinutes -eq 10080)
Assert "seven_day percent carried"        ($ss.UsedPercent -eq 91.0)
Assert "reset parsed"                     ($ss.ResetsAt.Day -eq 30)

$partial = '{ "seven_day": { "used_percentage": 40.0 } }' | ConvertFrom-Json
$pr = ConvertFrom-StatuslineRateLimits $partial
Assert "partial payload yields one window" (@($pr.Windows).Count -eq 1)
Assert "missing resets_at -> null"         ($null -eq (@($pr.Windows)[0]).ResetsAt)

Assert "null -> null"        ($null -eq (ConvertFrom-StatuslineRateLimits $null))
Assert "no usable windows -> null" `
    ($null -eq (ConvertFrom-StatuslineRateLimits ('{ "five_hour": {} }' | ConvertFrom-Json)))

Write-Host "Regression: empty objects emit no error records"
$errsBefore = $Error.Count
$null = ConvertFrom-StatuslineRateLimits ('{ "five_hour": {} }' | ConvertFrom-Json)
$null = ConvertFrom-StatuslineRateLimits ('{}' | ConvertFrom-Json)
$null = ConvertFrom-CodexBarUsage ('[{ "provider": "x", "usage": { "primary": {} } }]' | ConvertFrom-Json)
Assert "empty objects emit no error records" ($Error.Count -eq $errsBefore)

Write-Host "Get-QuotaWorkerCeiling"
$qcfg = @'
{ "defaults": { "ceiling_percent": 85, "relax_min_window_minutes": 10080, "relax_within_minutes": 1440 },
  "workers": {
    "codex": { "provider": "codex",  "window": "secondary", "ceiling_percent": 50 },
    "opus":  { "provider": "claude", "window": "secondary" } } }
'@ | ConvertFrom-Json
Assert "per-worker ceiling wins"   ((Get-QuotaWorkerCeiling -Config $qcfg -Worker 'codex') -eq 50)
Assert "falls back to default"     ((Get-QuotaWorkerCeiling -Config $qcfg -Worker 'opus')  -eq 85)
Assert "unknown worker -> default" ((Get-QuotaWorkerCeiling -Config $qcfg -Worker 'nobody') -eq 85)
$bare = '{ "workers": {} }' | ConvertFrom-Json
Assert "no defaults block -> 100 (no holdback)" ((Get-QuotaWorkerCeiling -Config $bare -Worker 'x') -eq 100)

Write-Host "Test-QuotaCeilingBreach"
$claudeReading = ConvertFrom-CodexBarUsage ($script:codexbarJson | ConvertFrom-Json) |
    Where-Object { $_.Provider -eq 'claude' } | Select-Object -First 1

$over = Test-QuotaCeilingBreach -Reading $claudeReading -WindowId 'secondary' -CeilingPercent 85
Assert "91 > 85 is a breach"     ($over.OverCeiling -eq $true)
Assert "breach carries percent"  ($over.UsedPercent -eq 91.0)
Assert "breach note is readable" ($over.Note -eq 'claude 7d 91% > ceiling 85%')

$under = Test-QuotaCeilingBreach -Reading $claudeReading -WindowId 'primary' -CeilingPercent 85
Assert "5 <= 85 is not a breach" ($under.OverCeiling -eq $false)
Assert "under note is readable"  ($under.Note -eq 'claude 5h 5% <= ceiling 85%')

$exact = Test-QuotaCeilingBreach -Reading $claudeReading -WindowId 'secondary' -CeilingPercent 91
Assert "at the boundary is NOT a breach" ($exact.OverCeiling -eq $false)

$scopedBreach = Test-QuotaCeilingBreach -Reading $claudeReading `
    -WindowId 'claude-weekly-scoped-fable' -CeilingPercent 85
Assert "scoped window breaches independently" ($scopedBreach.OverCeiling -eq $true)

# Fail-open paths: none of these may exclude a worker.
Assert "null reading -> no breach" `
    ((Test-QuotaCeilingBreach -Reading $null -WindowId 'secondary' -CeilingPercent 85).OverCeiling -eq $false)
$errReading = ConvertFrom-CodexBarUsage ($script:codexbarJson | ConvertFrom-Json) |
    Where-Object { $_.Provider -eq 'cursor' } | Select-Object -First 1
Assert "errored provider -> no breach" `
    ((Test-QuotaCeilingBreach -Reading $errReading -WindowId 'secondary' -CeilingPercent 85).OverCeiling -eq $false)
Assert "errored provider note names the error" `
    ((Test-QuotaCeilingBreach -Reading $errReading -WindowId 'secondary' -CeilingPercent 85).Note -like '*No cookies*')
Assert "missing window -> no breach" `
    ((Test-QuotaCeilingBreach -Reading $claudeReading -WindowId 'nope' -CeilingPercent 85).OverCeiling -eq $false)

$grokReading = ConvertFrom-CodexBarUsage ($script:codexbarJson | ConvertFrom-Json) |
    Where-Object { $_.Provider -eq 'grok' } | Select-Object -First 1
$infoBreach = Test-QuotaCeilingBreach -Reading $grokReading -WindowId 'primary' -CeilingPercent 5
Assert "informational window never breaches" ($infoBreach.OverCeiling -eq $false)
Assert "informational note says so"          ($infoBreach.Note -like '*informational*')

Write-Host "Get-QuotaRelaxation"
$relaxCfg = @'
{ "defaults": { "ceiling_percent": 85, "relax_min_window_minutes": 10080, "relax_within_minutes": 1440 },
  "workers": {} }
'@ | ConvertFrom-Json
$cbReadings = ConvertFrom-CodexBarUsage ($script:codexbarJson | ConvertFrom-Json)
$cr = @($cbReadings) | Where-Object { $_.Provider -eq 'claude' } | Select-Object -First 1
# secondary resets 2026-07-30T21:00Z; primary resets 2026-07-28T14:20Z
$farOut  = [datetime]::Parse('2026-07-28T09:00:00Z').ToUniversalTime()   # ~60h before reset
$lastDay = [datetime]::Parse('2026-07-30T09:00:00Z').ToUniversalTime()   # 12h before reset

$r1 = Get-QuotaRelaxation -Reading $cr -WindowId 'secondary' -Config $relaxCfg -Now $farOut
Assert "far from reset -> no relaxation" ($r1.RelaxationAvailable -eq $false)
Assert "reason explains the wait"        ($r1.Reason -like '*until reset*')

$r2 = Get-QuotaRelaxation -Reading $cr -WindowId 'secondary' -Config $relaxCfg -Now $lastDay
Assert "inside last day -> relaxation available" ($r2.RelaxationAvailable -eq $true)
Assert "reason names the window and asks"        ($r2.Reason -like '*7d*' -and $r2.Reason -like '*ask*')

$r3 = Get-QuotaRelaxation -Reading $cr -WindowId 'primary' -Config $relaxCfg `
    -Now ([datetime]::Parse('2026-07-28T14:00:00Z').ToUniversalTime())
Assert "5h window never relaxes even 20 min out" ($r3.RelaxationAvailable -eq $false)
Assert "reason says long-window only"            ($r3.Reason -like '*long-window only*')

$r4 = Get-QuotaRelaxation -Reading $cr -WindowId 'secondary' -Config $relaxCfg `
    -Now ([datetime]::Parse('2026-08-05T00:00:00Z').ToUniversalTime())
Assert "reset in the past -> no relaxation" ($r4.RelaxationAvailable -eq $false)
Assert "reason flags staleness"             ($r4.Reason -like '*stale*')

Assert "null reading -> no relaxation" `
    ((Get-QuotaRelaxation -Reading $null -WindowId 'secondary' -Config $relaxCfg -Now $lastDay).RelaxationAvailable -eq $false)
Assert "missing window -> no relaxation" `
    ((Get-QuotaRelaxation -Reading $cr -WindowId 'nope' -Config $relaxCfg -Now $lastDay).RelaxationAvailable -eq $false)

# A 30-day window (GitHub Premium shape) relaxes on the same rule.
$monthly = [pscustomobject]@{
    Provider = 'github'; Source = 'codexbar:web'; AsOf = $null; Error = $null
    Windows = @([pscustomobject]@{
        Id = 'secondary'; UsedPercent = 90.0; WindowMinutes = 43200
        ResetsAt = [datetime]::Parse('2026-08-01T00:00:00Z').ToUniversalTime(); IsInformational = $false })
}
$r5 = Get-QuotaRelaxation -Reading $monthly -WindowId 'secondary' -Config $relaxCfg `
    -Now ([datetime]::Parse('2026-07-31T12:00:00Z').ToUniversalTime())
Assert "30d window relaxes in its last day" ($r5.RelaxationAvailable -eq $true)

Write-Host "CodexBar macOS (camelCase) payload"
# Shape of a live `codexbar usage --provider claude --json` capture, CodexBar 0.56.8, 2026-09-26.
$camel = @'
[ { "provider": "claude", "source": "claude",
    "usage": { "primary":   { "windowMinutes": 300,   "usedPercent": 20, "resetsAt": "2026-09-26T11:30:00Z" },
               "secondary": { "windowMinutes": 10080, "usedPercent": 95, "resetsAt": "2026-10-01T21:00:00Z" },
               "tertiary": null, "updatedAt": "2026-09-26T07:01:02Z" } },
  { "provider": "cli", "error": { "code": 1, "kind": "args", "message": "Unknown option --p" } } ]
'@ | ConvertFrom-Json
$cr = @(ConvertFrom-CodexBarUsage $camel)
$cc = $cr | Where-Object Provider -eq 'claude'
Assert "camelCase windows parsed"      (@($cc.Windows).Count -eq 2)
Assert "camelCase usedPercent read"    ((@($cc.Windows) | Where-Object Id -eq 'secondary').UsedPercent -eq 95)
Assert "camelCase resetsAt read"       ($null -ne (@($cc.Windows) | Where-Object Id -eq 'secondary').ResetsAt)
Assert "camelCase updatedAt -> AsOf"   ($null -ne $cc.AsOf)
$cb = Test-QuotaCeilingBreach -Reading $cc -WindowId 'secondary' -CeilingPercent 85
Assert "camelCase breach detected"     ($cb.OverCeiling -eq $true)
Assert "object error keeps its message" (($cr | Where-Object Provider -eq 'cli').Error -eq 'Unknown option --p')

Write-Host "epoch and zoneless timestamps"
Assert "epoch seconds string -> UTC"   ((ConvertTo-QuotaDateTime '1790422200') -eq [datetime]::Parse('2026-09-26T11:30:00Z').ToUniversalTime())
Assert "epoch seconds number -> UTC"   ((ConvertTo-QuotaDateTime 1790422200) -eq [datetime]::Parse('2026-09-26T11:30:00Z').ToUniversalTime())
$unspec = [datetime]::SpecifyKind([datetime]'2026-07-30 21:00:00', [System.DateTimeKind]::Unspecified)
Assert "Unspecified datetime read as UTC" ((ConvertTo-QuotaDateTime $unspec).Hour -eq 21)
$sl = ConvertFrom-StatuslineRateLimits ('{ "seven_day": { "used_percentage": 50, "resets_at": 1790888400 } }' | ConvertFrom-Json)
Assert "statusline epoch resets_at parsed" ($null -ne $sl.Windows[0].ResetsAt)
$bat = ConvertFrom-StatuslineRateLimits ('{ "seven_day": { "used_pct": 5, "resets_at_unix": "1790888400" } }' | ConvertFrom-Json) -AsOf '2026-09-26T07:00:41Z'
Assert "used_pct/resets_at_unix shape parsed" ($bat -and $bat.Windows[0].UsedPercent -eq 5 -and $null -ne $bat.Windows[0].ResetsAt)
Assert "statusline AsOf carried"       ($null -ne $bat.AsOf)

Write-Host "stale readings fail open"
$stale = [pscustomobject]@{
    Provider = 'claude'; Source = 'statusline'; AsOf = $null; Error = $null
    Windows = @([pscustomobject]@{ Id = 'secondary'; UsedPercent = 97.0; WindowMinutes = 10080
        ResetsAt = [datetime]::Parse('2026-07-30T21:00:00Z').ToUniversalTime(); IsInformational = $false }) }
$sb = Test-QuotaCeilingBreach -Reading $stale -WindowId 'secondary' -CeilingPercent 85 `
    -Now ([datetime]::Parse('2026-08-02T00:00:00Z').ToUniversalTime())
Assert "past-reset reading not enforced" ($sb.OverCeiling -eq $false -and $sb.Note -like '*stale*')
$sb2 = Test-QuotaCeilingBreach -Reading $stale -WindowId 'secondary' -CeilingPercent 85 `
    -Now ([datetime]::Parse('2026-07-29T00:00:00Z').ToUniversalTime())
Assert "pre-reset reading still enforced" ($sb2.OverCeiling -eq $true)

if ($script:fail) { Write-Host "`n$script:fail FAILED" -ForegroundColor Red; exit 1 }
else { Write-Host "`nAll passed" -ForegroundColor Green }
