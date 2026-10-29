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
    if ($null -ne $json) { Set-Content -LiteralPath (Join-Path (Join-Path $root 'config') 'models.json') -Value $json -Encoding UTF8 }
    return $root
}

$valid = @'
{ "workers": { "haiku": { "invoke": "claude-subagent:haiku", "roles": ["docs"], "tier": "cheap" } },
  "policy": { "default_builder": "grok" } }
'@

Write-Host "Get-GrimdexFleet"
$r1 = New-FleetFixture $valid
$fleet = Get-GrimdexFleet -GrimdexRoot $r1
Assert "parses valid models.json" ($null -ne $fleet -and $fleet.policy.default_builder -eq 'grok')

$r2 = New-FleetFixture $null   # dir exists, no models.json
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
$revx = Select-FleetWorker -Fleet $f -TaskType 'on-call' -Explicit -Name 'codex'
Assert "on-call -Explicit -> codex allowed" ($revx.Name -eq 'codex')
$oncall = Select-FleetWorker -Fleet $f -TaskType 'on-call'
Assert "on-call (no -Explicit) -> null" ($null -eq $oncall)
# Approval is bound to the named worker: with two gated on-call workers, -Explicit returns
# the one named, never the other (security audit 2026-10-29).
$two = $fleetJson | ConvertFrom-Json
$two.workers | Add-Member -NotePropertyName 'codex-b' -NotePropertyValue ($two.workers.codex | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
Assert "two gated: -Name codex-b -> codex-b" ((Select-FleetWorker -Fleet $two -TaskType 'on-call' -Explicit -Name 'codex-b').Name -eq 'codex-b')
Assert "two gated: -Name codex -> codex"     ((Select-FleetWorker -Fleet $two -TaskType 'on-call' -Explicit -Name 'codex').Name -eq 'codex')
$threw = $false; try { Select-FleetWorker -Fleet $two -TaskType 'on-call' -Explicit | Out-Null } catch { $threw = $true }
Assert "-Explicit without -Name refuses" $threw
$none = Select-FleetWorker -Fleet $f -TaskType 'nonexistent-role'
Assert "unknown role -> null"     ($null -eq $none)

# NeedsAsk: a worker with unknown availability
$askJson = @'
{ "workers": { "mystery": { "invoke": "cli:x", "roles": ["docs"], "tier": "cheap", "availability": "unknown" } }, "policy": {} }
'@
$fa = $askJson | ConvertFrom-Json
$ask = Select-FleetWorker -Fleet $fa -TaskType 'docs'
Assert "unknown availability -> NeedsAsk" ($ask.Name -eq 'mystery' -and $ask.NeedsAsk -eq $true)

Write-Host "builder chain (bulk-code, no hard-coded default builder)"
# One Command Code pool (free + deal rows), then the other providers. c-a/c-b are free and
# trialled, c-deal is priced, c-laguna never passed its trial.
$chainJson = @'
{
  "workers": {
    "c-a":      { "invoke": "cli:cmd", "roles": ["bulk-code"], "tier": "cheap",
                  "offer": { "free": true }, "trial": { "passed": 35, "total": 35, "seconds": 42 },
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "c-b":      { "invoke": "cli:cmd", "roles": ["bulk-code"], "tier": "cheap",
                  "offer": { "free": true }, "trial": { "passed": 34, "total": 35, "seconds": 400 },
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "c-deal":   { "invoke": "cli:cmd", "roles": ["bulk-code"], "tier": "cheap",
                  "offer": { "free": false }, "trial": { "passed": 35, "total": 35, "seconds": 83 },
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "c-laguna": { "invoke": "cli:cmd", "roles": ["bulk-code"], "tier": "cheap",
                  "offer": { "free": true }, "trial": { "passed": 0, "total": 35, "seconds": 284 },
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "kimi-k3":  { "invoke": "cli:cmd", "roles": ["bulk-code"], "tier": "build",
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "glm":      { "invoke": "cli:bash", "roles": ["bulk-code"], "tier": "cheap",
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "agy":      { "invoke": "cli:agy", "roles": ["bulk-code"], "tier": "mid",
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "kiro":     { "invoke": "cli:kiro-cli", "roles": ["bulk-code"], "tier": "build",
                  "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } }
  },
  "policy": { "default_builder": "c-a", "builder_chain": [ "@cc-free-best", "@cc-deal-best", "kimi-k3", "glm", "agy", "kiro", "ghost" ] }
}
'@
$cf = $chainJson | ConvertFrom-Json -DateKind String
$now = [datetimeoffset]::Parse('2026-10-01T12:00:00Z')

# Best free model wins, and the reason names the chain entry that chose it.
$bc = Select-FleetWorker -Fleet $cf -TaskType 'bulk-code' -Now $now
Assert "bulk-code -> best free model" ($bc.Name -eq 'c-a')
Assert "reason names the chain entry"  ($bc.Reason -eq 'bulk-code -> c-a (builder chain: @cc-free-best)')

# Next in line: the best free model is out -> the next free one takes over.
$out = $cf.workers.'c-a'.availability; $cf.workers.'c-a'.availability.state = 'out'
$bc2 = Select-FleetWorker -Fleet $cf -TaskType 'bulk-code' -Now $now
Assert "best free out -> next free wins" ($bc2.Name -eq 'c-b' -and $bc2.Reason -like '*(builder chain: @cc-free-best)*')
$cf.workers.'c-b'.availability.state = 'out'

# Every free and deal model out -> the first named provider in the chain.
$cf.workers.'c-deal'.availability.state = 'out'
$bc3 = Select-FleetWorker -Fleet $cf -TaskType 'bulk-code' -Now $now
Assert "all Command Code out -> kimi-k3"  ($bc3.Name -eq 'kimi-k3' -and $bc3.Reason -like '*(builder chain: kimi-k3)*')
$cf.workers.'kimi-k3'.availability.state = 'out'
$bc4 = Select-FleetWorker -Fleet $cf -TaskType 'bulk-code' -Now $now
Assert "kimi out -> the next named worker" ($bc4.Name -eq 'glm')

# A failed trial is never auto-picked, even when it tops its price tier.
Assert "failed trial never auto-picked" (-not (@(Resolve-GrimdexBuilderChain -Models $cf -Now $now) -contains 'c-laguna'))
$cf.workers.'c-laguna'.availability.state = 'out'   # the only way it could surface
Assert "failed trial out of the chain"  (@(Resolve-GrimdexBuilderChain -Models $cf -Now $now) -notcontains 'c-laguna')
$onlyFailed = [pscustomobject]@{ workers = [pscustomobject]@{
        'c-laguna' = [pscustomobject]@{ roles = @('bulk-code'); tier = 'cheap'
                                         trial = [pscustomobject]@{ passed = 3; total = 35 } } }
    policy = [pscustomobject]@{} }
Assert "a failed trial is never the answer" ($null -eq (Select-FleetWorker -Fleet $onlyFailed -TaskType 'bulk-code' -Now $now))
Assert "-Explicit still reaches it"           ((Select-FleetWorker -Fleet $onlyFailed -TaskType 'bulk-code' -Explicit -Name 'c-laguna' -Now $now).Name -eq 'c-laguna')
$halfFailed = [pscustomobject]@{ workers = [pscustomobject]@{
        'half' = [pscustomobject]@{ roles = @('docs'); tier = 'cheap'; trial = [pscustomobject]@{ passed = 17; total = 35 } }
        'fine' = [pscustomobject]@{ roles = @('docs'); tier = 'cheap'; trial = [pscustomobject]@{ passed = 18; total = 35 } } }
    policy = [pscustomobject]@{} }
Assert "under half is out of ANY task type" ((Select-FleetWorker -Fleet $halfFailed -TaskType 'docs' -Now $now).Name -eq 'fine')

# The chain only reorders: role, gate, trial and availability filtering still decide eligibility,
# so a gated or untrialled model in the chain falls through to the next entry.
$gated = [pscustomobject]@{ workers = [pscustomobject]@{
        'g-free'   = [pscustomobject]@{ roles = @('bulk-code'); tier = 'cheap'; gate = 'explicit-call-only'
                                         offer = [pscustomobject]@{ free = $true }
                                         trial = [pscustomobject]@{ passed = 35; total = 35; seconds = 20 } }
        'g-priced' = [pscustomobject]@{ roles = @('bulk-code'); tier = 'cheap'
                                         offer = [pscustomobject]@{ free = $false }
                                         trial = [pscustomobject]@{ passed = 35; total = 35; seconds = 60 } } }
    policy = [pscustomobject]@{ builder_chain = @('@cc-free-best', '@cc-deal-best') } }
$gatedPick = Select-FleetWorker -Fleet $gated -TaskType 'bulk-code' -Now $now
Assert "a gated chain entry falls through" ($gatedPick.Name -eq 'g-priced' -and $gatedPick.Reason -like '*(builder chain: @cc-deal-best)*')
Assert "no roles for a chain name -> next"  (@(Resolve-GrimdexBuilderChain -Models $cf -Now $now -WithEntry | Where-Object Entry -eq 'ghost').Count -eq 0)

# No chain -> the old default_builder behaviour, unchanged.
$plain = [pscustomobject]@{ workers = [pscustomobject]@{
        'p-hint'  = [pscustomobject]@{ roles = @('bulk-code'); tier = 'build' }
        'p-cheap' = [pscustomobject]@{ roles = @('bulk-code'); tier = 'cheap' } }
    policy = [pscustomobject]@{ default_builder = 'p-hint' } }
$nb = Select-FleetWorker -Fleet $plain -TaskType 'bulk-code' -Now $now
Assert "no chain -> default_builder"    ($nb.Name -eq 'p-hint' -and $nb.Reason -like '*(policy hint)*')
$noHint = [pscustomobject]@{ workers = $plain.workers; policy = [pscustomobject]@{ } }
Assert "no chain, no hint -> cheapest"  ((Select-FleetWorker -Fleet $noHint -TaskType 'bulk-code' -Now $now).Name -eq 'p-cheap')
$emptyChain = [pscustomobject]@{ workers = $plain.workers
                                 policy = [pscustomobject]@{ default_builder = 'p-hint'; builder_chain = @() } }
Assert "empty chain -> default_builder"  ((Select-FleetWorker -Fleet $emptyChain -TaskType 'bulk-code' -Now $now).Name -eq 'p-hint')
Assert "the chain is not read for small-code" ($null -eq (Select-FleetWorker -Fleet $cf -TaskType 'docs' -Now $now))

Write-Host "shipped example validates"
$repoRoot = Split-Path $PSScriptRoot -Parent
$examplePath = Join-Path (Join-Path $repoRoot 'config') 'models.example.json'
Assert "models.example.json exists" (Test-Path -LiteralPath $examplePath)
$ex = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
Assert "example has workers"  ($ex.workers.PSObject.Properties.Name.Count -ge 1)
$exSel = Select-FleetWorker -Fleet $ex -TaskType 'docs'
Assert "example routes docs to a worker" ($null -ne $exSel)

Write-Host "Select-FleetWorker -QuotaState"
$qFleetJson = @'
{
  "workers": {
    "sonnet": { "invoke": "claude-subagent:sonnet", "roles": ["small-code","review"], "tier": "mid",   "availability": "available" },
    "haiku":  { "invoke": "claude-subagent:haiku",  "roles": ["small-code","docs"],   "tier": "cheap", "availability": "available" },
    "grok":   { "invoke": "cli:grok",               "roles": ["bulk-code"],           "tier": "build", "availability": "available" },
    "opus":   { "invoke": "claude-subagent:opus",   "roles": ["review"],              "tier": "high",  "availability": "available" },
    "codex":  { "invoke": "plugin:codex-rescue",    "roles": ["on-call"],             "gate": "explicit-call-only" }
  },
  "policy": {}
}
'@
$qf = $qFleetJson | ConvertFrom-Json

function QS($pairs) {
    $h = @{}
    foreach ($k in $pairs.Keys) {
        $h[$k] = [pscustomobject]@{ OverCeiling = $pairs[$k]; Note = "claude 7d 91% > ceiling 85%" }
    }
    return $h
}

# Backward compatibility: omitting -QuotaState changes nothing.
$base = Select-FleetWorker -Fleet $qf -TaskType 'small-code'
Assert "no -QuotaState -> cheapest (haiku)" ($base.Name -eq 'haiku')
Assert "no -QuotaState -> NeedsAsk false"   ($base.NeedsAsk -eq $false)

# Downgrade by fall-through: haiku over ceiling, sonnet available.
$dg = Select-FleetWorker -Fleet $qf -TaskType 'small-code' -QuotaState (QS @{ haiku = $true })
Assert "over-ceiling worker excluded"   ($dg.Name -eq 'sonnet')
Assert "downgrade is not silent"        ($dg.Reason -like '*haiku excluded*')
Assert "reason carries the breach note" ($dg.Reason -like '*91%*')
Assert "downgrade does not ask"         ($dg.NeedsAsk -eq $false)

# Fail open: unknown workers and false values never exclude.
$fo = Select-FleetWorker -Fleet $qf -TaskType 'small-code' -QuotaState (QS @{ grok = $true })
Assert "unrelated breach does not affect role" ($fo.Name -eq 'haiku')
$fo2 = Select-FleetWorker -Fleet $qf -TaskType 'small-code' -QuotaState (QS @{ haiku = $false })
Assert "OverCeiling false does not exclude" ($fo2.Name -eq 'haiku')
$fo3 = Select-FleetWorker -Fleet $qf -TaskType 'small-code' -QuotaState @{}
Assert "empty quota state changes nothing" ($fo3.Name -eq 'haiku')

# Shared-window cascade empties the pool -> return anyway with NeedsAsk.
$allClaude = QS @{ haiku = $true; sonnet = $true }
$empty = Select-FleetWorker -Fleet $qf -TaskType 'small-code' -QuotaState $allClaude
Assert "empty pool still returns a worker" ($null -ne $empty)
Assert "empty pool sets NeedsAsk"          ($empty.NeedsAsk -eq $true)
Assert "empty pool reason names the breach" ($empty.Reason -like '*91%*')
Assert "empty pool reason asks"            ($empty.Reason -like '*ask*')

# Explicit call bypasses quota exclusion entirely.
$ex = Select-FleetWorker -Fleet $qf -TaskType 'small-code' -Explicit -Name 'haiku' -QuotaState (QS @{ haiku = $true })
Assert "-Explicit ignores the ceiling" ($ex.Name -eq 'haiku')
Assert "-Explicit does not force ask"  ($ex.NeedsAsk -eq $false)

# A role with no candidates at all still returns null (quota must not change this).
Assert "unknown role still null" `
    ($null -eq (Select-FleetWorker -Fleet $qf -TaskType 'nonexistent' -QuotaState (QS @{ haiku = $true })))

Write-Host "empty workers map degrades cleanly"
$emptyFleet = '{ "workers": {}, "policy": {} }' | ConvertFrom-Json
$errsBefore = $Error.Count
$emptyPick = Select-FleetWorker -Fleet $emptyFleet -TaskType 'small-code'
Assert "empty workers -> null, no throw" ($null -eq $emptyPick)
Assert "empty workers emits no error records" ($Error.Count -eq $errsBefore)

Write-Host "workers without a roles key (d037 alias rows)"
$aliasFleet = '{ "workers": { "gemini-flash": { "alias_of": "agy", "model": "x" },
                               "haiku": { "roles": ["docs"], "tier": "cheap" } }, "policy": {} }' | ConvertFrom-Json
$errsBefore = $Error.Count
$aliasPick = Select-FleetWorker -Fleet $aliasFleet -TaskType 'docs'
Assert "roles-less worker skipped, no throw" ($aliasPick -and $aliasPick.Name -eq 'haiku')
Assert "roles-less worker emits no error records" ($Error.Count -eq $errsBefore)

Write-Host "gate semantics (grimdex-d051)"
$gf = [pscustomobject]@{ workers = [pscustomobject]@{
    ok1  = [pscustomobject]@{ roles = @('on-call'); gate = 'explicit-call-only' }
    ok2  = [pscustomobject]@{ roles = @('on-call'); gate = 'explicit-call-only; skip-if-weekly>50%' }
    bad  = [pscustomobject]@{ roles = @('bulk-code'); gate = 'separate quota pool (credits)' }
    pool = [pscustomobject]@{ roles = @('bulk-code'); pool = 'separate quota pool (credits)'; availability = 'available' }
} }
$bad = @(Test-GrimdexFleetGates -Fleet $gf)
Assert "descriptive gate flagged"           ($bad.Count -eq 1 -and $bad[0].Name -eq 'bad')
Assert "pool field never filters selection" ((Select-FleetWorker -Fleet $gf -TaskType 'bulk-code').Name -eq 'pool')
$liveRoot = Split-Path $PSScriptRoot -Parent

Write-Host "code_exclude"
$cx = [pscustomobject]@{ workers = [pscustomobject]@{
    'cc-ling' = [pscustomobject]@{ roles = @('bulk-code','docs'); tier = 'cheap' }
    glm       = [pscustomobject]@{ roles = @('bulk-code'); tier = 'cheap' } }
  policy = [pscustomobject]@{ builder_chain = @('cc-ling','glm'); code_exclude = @('(?i)ling') } }
Assert "excluded model skipped in the chain for bulk-code" ((Select-FleetWorker -Fleet $cx -TaskType 'bulk-code').Name -eq 'glm')
Assert "excluded model not picked for code even with -Explicit" ((Select-FleetWorker -Fleet $cx -TaskType 'bulk-code' -Explicit -Name 'cc-ling').Name -eq $null)
Assert "excluded model still used for non-code roles" ((Select-FleetWorker -Fleet $cx -TaskType 'docs').Name -eq 'cc-ling')

if (Test-Path (Join-Path $liveRoot 'config' 'models.json')) {
    $live = Get-GrimdexFleet -GrimdexRoot $liveRoot -WarningAction SilentlyContinue
    Assert "live fleet: every gate is a restriction" (@(Test-GrimdexFleetGates -Fleet $live).Count -eq 0)
    Assert "live fleet: bulk-code has a worker"      ($null -ne (Select-FleetWorker -Fleet $live -TaskType 'bulk-code'))
    $liveChain = @(Resolve-GrimdexBuilderChain -Models $live)
    Assert "live fleet: builder_chain resolves"      ($liveChain.Count -ge 1)
    # The chain head may be 'out' (a promo that ended), so assert the pick came from the chain,
    # not that it is the head.
    $livePick = Select-FleetWorker -Fleet $live -TaskType 'bulk-code'
    Assert "live fleet: the builder chain picks, not default_builder" `
        ($livePick.Name -in $liveChain -and $livePick.Reason -like '*(builder chain:*')
}

if ($script:fail) { Write-Host "`n$script:fail FAILED" -ForegroundColor Red; exit 1 }
else { Write-Host "`nAll passed" -ForegroundColor Green }
