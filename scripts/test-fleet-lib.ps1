Set-StrictMode -Version Latest
. "$PSScriptRoot/fleet-lib.ps1"

$script:fail = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "  PASS: $label" -ForegroundColor Green }
    else { Write-Host "  FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function New-FleetFixture($json) {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("fleet_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force | Out-Null
    if ($null -ne $json) { Set-Content -LiteralPath (Join-Path (Join-Path $root 'config') 'fleet.json') -Value $json -Encoding UTF8 }
    return $root
}

$valid = @'
{ "workers": { "haiku": { "invoke": "claude-subagent:haiku", "roles": ["docs"], "tier": "cheap" } },
  "policy": { "default_builder": "grok" } }
'@

Write-Host "Get-GrimdexFleet"
$r1 = New-FleetFixture $valid
$fleet = Get-GrimdexFleet -GrimdexRoot $r1
Assert "parses valid fleet.json" ($null -ne $fleet -and $fleet.policy.default_builder -eq 'grok')

$r2 = New-FleetFixture $null   # dir exists, no fleet.json
Assert "absent file returns `$null" ($null -eq (Get-GrimdexFleet -GrimdexRoot $r2))

$r3 = New-FleetFixture '{ this is not json'
$threw = $false
try { Get-GrimdexFleet -GrimdexRoot $r3 } catch { $threw = $true }
Assert "malformed JSON throws" $threw

Remove-Item -Recurse -Force $r1, $r2, $r3 -ErrorAction SilentlyContinue

Write-Host "Test-FleetWorkerAvailable"
function W($avail) {
    if ($null -eq $avail) { return ([pscustomobject]@{ roles = @('x') }) }
    return ([pscustomobject]@{ roles = @('x'); availability = $avail })
}
Assert "available -> available"   ((Test-FleetWorkerAvailable (W 'available')) -eq 'available')
Assert "scarce -> available"      ((Test-FleetWorkerAvailable (W 'scarce'))    -eq 'available')
Assert "absent -> available"      ((Test-FleetWorkerAvailable (W $null))       -eq 'available')
Assert "out -> unavailable"       ((Test-FleetWorkerAvailable (W 'out'))       -eq 'unavailable')
Assert "unknown -> ask"           ((Test-FleetWorkerAvailable (W 'unknown'))   -eq 'ask')
Assert "garbage -> ask"           ((Test-FleetWorkerAvailable (W 'wat'))       -eq 'ask')

Write-Host "Select-FleetWorker"
$fleetJson = @'
{
  "workers": {
    "grok":   { "invoke": "cli:grok",              "roles": ["bulk-code"],           "tier": "build", "availability": "available" },
    "sonnet": { "invoke": "claude-subagent:sonnet","roles": ["small-code"],           "tier": "mid",   "availability": "available" },
    "fable":  { "invoke": "claude-subagent:fable", "roles": ["thinking","planning"],  "tier": "high",  "availability": "out" },
    "opus":   { "invoke": "claude-subagent:opus",  "roles": ["thinking","planning","review","docs"], "tier": "high", "availability": "scarce" },
    "haiku":  { "invoke": "claude-subagent:haiku", "roles": ["docs","summary"],       "tier": "cheap", "availability": "available" },
    "codex":  { "invoke": "plugin:codex-rescue",   "roles": ["on-call","review"],     "gate": "explicit-call-only" },
    "gh":     { "invoke": "cli:gh",                "roles": ["repo-op"] }
  },
  "policy": { "default_builder": "grok", "small_code_may_use": "sonnet",
              "late_window_burn_high_tiers": true, "counsel": ["codex","grok","opus"] }
}
'@
$f = $fleetJson | ConvertFrom-Json

$b = Select-FleetWorker -Fleet $f -TaskType 'bulk-code'
Assert "bulk-code -> grok"        ($b.Name -eq 'grok')
$s = Select-FleetWorker -Fleet $f -TaskType 'small-code'
Assert "small-code -> sonnet"     ($s.Name -eq 'sonnet')
$t = Select-FleetWorker -Fleet $f -TaskType 'thinking'
Assert "thinking(Fable out) -> opus" ($t.Name -eq 'opus')
$d = Select-FleetWorker -Fleet $f -TaskType 'docs'
Assert "docs -> haiku (cheap pref)" ($d.Name -eq 'haiku')
$dl = Select-FleetWorker -Fleet $f -TaskType 'docs' -LateWindow
Assert "docs -LateWindow -> opus (high pref)" ($dl.Name -eq 'opus')
$g = Select-FleetWorker -Fleet $f -TaskType 'repo-op'
Assert "repo-op -> gh"            ($g.Name -eq 'gh')
$rev = Select-FleetWorker -Fleet $f -TaskType 'review'
Assert "review -> opus (codex gated out)" ($rev.Name -eq 'opus')
$revx = Select-FleetWorker -Fleet $f -TaskType 'on-call' -Explicit
Assert "on-call -Explicit -> codex allowed" ($revx.Name -eq 'codex')
$oncall = Select-FleetWorker -Fleet $f -TaskType 'on-call'
Assert "on-call (no -Explicit) -> null" ($null -eq $oncall)
$none = Select-FleetWorker -Fleet $f -TaskType 'nonexistent-role'
Assert "unknown role -> null"     ($null -eq $none)

# NeedsAsk: a worker with unknown availability
$askJson = @'
{ "workers": { "mystery": { "invoke": "cli:x", "roles": ["docs"], "tier": "cheap", "availability": "unknown" } }, "policy": {} }
'@
$fa = $askJson | ConvertFrom-Json
$ask = Select-FleetWorker -Fleet $fa -TaskType 'docs'
Assert "unknown availability -> NeedsAsk" ($ask.Name -eq 'mystery' -and $ask.NeedsAsk -eq $true)

Write-Host "shipped example validates"
$repoRoot = Split-Path $PSScriptRoot -Parent
$examplePath = Join-Path (Join-Path $repoRoot 'config') 'fleet.example.json'
Assert "fleet.example.json exists" (Test-Path -LiteralPath $examplePath)
$ex = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
Assert "example has workers"  ($ex.workers.PSObject.Properties.Name.Count -ge 1)
$exSel = Select-FleetWorker -Fleet $ex -TaskType 'docs'
Assert "example routes docs to a worker" ($null -ne $exSel)

if ($script:fail) { Write-Host "`n$script:fail FAILED" -ForegroundColor Red; exit 1 }
else { Write-Host "`nAll passed" -ForegroundColor Green }
