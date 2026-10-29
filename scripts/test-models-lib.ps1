#!/usr/bin/env pwsh
# Tests for models-lib.ps1 (grimdex-d052): model record, expiry, AK detection, notice, set.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'models-lib.ps1')
$script:fail = 0
function Assert($name, $cond) { if ($cond) { Write-Host "PASS: $name" } else { Write-Host "FAIL: $name" -ForegroundColor Red; $script:fail++ } }

$now = [datetimeoffset]::Parse('2026-10-01T12:00:00Z')
function W($a) { [pscustomobject]@{ roles = @('docs'); availability = $a } }
function Rec([hashtable]$h) { [pscustomobject]$h }

Write-Host 'Get-GrimdexAvailability'
$noAvail = [pscustomobject]@{ roles = @('docs') }
Assert 'absent -> available'               ((Get-GrimdexAvailability -Worker $noAvail -Now $now).EffectiveState -eq 'available')
Assert 'bare string kept, never expires'   ((Get-GrimdexAvailability -Worker (W 'scarce') -Now $now).EffectiveState -eq 'scarce')
$known = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'scarce'; as_of = '2026-09-25T00:00:00Z'; window = 'weekly'; valid_until = '2026-10-03T00:00:00Z' })) -Now $now
Assert 'known reset time: still valid before it' (-not $known.Expired -and $known.EffectiveState -eq 'scarce')
$past = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'out'; as_of = '2026-09-25T00:00:00Z'; window = 'weekly'; valid_until = '2026-10-01T11:00:00Z' })) -Now $now
Assert 'known reset time: expired after it -> unknown' ($past.Expired -and $past.EffectiveState -eq 'unknown' -and $past.State -eq 'out')
$short = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'out'; as_of = '2026-10-01T06:00:00Z'; window = '5h' })) -Now $now
Assert '5h window, no reset: expires after 5 hours' ($short.Expired -and $short.ValidUntil -eq [datetimeoffset]::Parse('2026-10-01T11:00:00Z'))
$long = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'scarce'; as_of = '2026-09-28T00:00:00Z'; window = 'weekly' })) -Now $now
Assert 'weekly window, no reset: valid for 7 days' (-not $long.Expired)
$none = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'available'; as_of = '2026-09-20T00:00:00Z'; window = 'none' })) -Now $now
Assert 'window none: long fallback (7 days) -> expired after 11' ($none.Expired)
$pol = Rec @{ availability_fallback_hours = (Rec @{ short = 1; long = 24 }) }
$custom = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'available'; as_of = '2026-09-30T06:00:00Z'; window = 'weekly' })) -Policy $pol -Now $now
Assert 'policy fallback hours are honoured' ($custom.Expired)
$nodate = Get-GrimdexAvailability -Worker (W (Rec @{ state = 'available'; window = 'none' })) -Now $now
Assert 'record without as_of never expires' (-not $nodate.Expired)

Write-Host 'Test-GrimdexModelRecords'
$bad = Rec @{ workers = (Rec @{
    a = (W (Rec @{ state = 'maybe'; as_of = '2026-10-01T00:00:00Z' }))
    b = (W (Rec @{ state = 'out'; as_of = 'yesterday' }))
    c = (W (Rec @{ state = 'out'; window = 'fortnight' }))
    d = (W (Rec @{ state = 'available'; as_of = '2026-10-01T00:00:00Z'; window = '5h' }))
}) }
$probs = @(Test-GrimdexModelRecords -Models $bad)
Assert 'bad state flagged'  (@($probs | Where-Object Name -eq 'a').Count -eq 1)
Assert 'bad time flagged'   (@($probs | Where-Object Name -eq 'b').Count -eq 1)
Assert 'bad window flagged' (@($probs | Where-Object Name -eq 'c').Count -eq 1)
Assert 'good record clean'  (@($probs | Where-Object Name -eq 'd').Count -eq 0)

Write-Host 'Get-GrimdexExpiredModels / notice'
$models = Rec @{ workers = (Rec @{
    fresh = (W (Rec @{ state = 'available'; as_of = '2026-10-01T10:00:00Z'; window = '5h' }))
    old   = (W (Rec @{ state = 'scarce'; as_of = '2026-09-20T00:00:00Z'; window = 'weekly' }))
}); policy = (Rec @{}) }
$exp = @(Get-GrimdexExpiredModels -Models $models -Now $now)
Assert 'only the expired model listed' ($exp.Count -eq 1 -and $exp[0].Name -eq 'old')
$noAk = Get-GrimdexAvailabilityNotice -Models $models -AkInstalled $false -Now $now
Assert 'without AK: notice tells the user about AtomicKestrel' ($noAk -match 'install AtomicKestrel' -and $noAk -match 'old' -and $noAk -match '11 day')
$withAk = Get-GrimdexAvailabilityNotice -Models $models -AkInstalled $true -Now $now
Assert 'with AK: notice points at kes models sync' ($withAk -match 'kes models sync' -and $withAk -notmatch 'install AtomicKestrel')
$allFresh = Rec @{ workers = (Rec @{ fresh = (W (Rec @{ state = 'available'; as_of = '2026-10-01T10:00:00Z'; window = '5h' })) }) }
Assert 'nothing expired -> no notice' ($null -eq (Get-GrimdexAvailabilityNotice -Models $allFresh -AkInstalled $false -Now $now))

Write-Host 'Test-GrimdexAtomicKestrel'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("gx-models-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'ak') | Out-Null
$akModels = Rec @{ policy = (Rec @{ atomickestrel_root = (Join-Path $tmp 'ak') }) }
Assert 'no kes, no root -> not installed' (-not (Test-GrimdexAtomicKestrel -Models (Rec @{ policy = (Rec @{}) }) -KesCommand 'no-such-kes-xyz'))
Assert 'root without kes.ps1 -> not installed' (-not (Test-GrimdexAtomicKestrel -Models $akModels -KesCommand 'no-such-kes-xyz'))
Set-Content (Join-Path $tmp 'ak' 'kes.ps1') '# stub'
Assert 'root with kes.ps1 -> installed' (Test-GrimdexAtomicKestrel -Models $akModels -KesCommand 'no-such-kes-xyz')

Write-Host 'Set-GrimdexAvailability'
$g = Join-Path $tmp 'g'; New-Item -ItemType Directory -Force -Path (Join-Path $g 'config') | Out-Null
$file = Join-Path $g 'config' 'models.json'
Set-Content $file '{"workers":{"codex":{"roles":["on-call"],"gate":"explicit-call-only","availability":{"state":"available","as_of":"2026-09-01T00:00:00Z","window":"none","source":"manual"}},"glm":{"roles":["bulk-code"],"note":"keep — me"}},"policy":{"default_builder":"glm"}}'
$rec = Set-GrimdexAvailability -GrimdexRoot $g -Name codex -State scarce -Window weekly -ValidUntil '2026-10-03T00:00:00Z' -Detail 'weekly 62%' -Source atomickestrel -Now $now
$after = Get-Content $file -Raw | ConvertFrom-Json -DateKind String
Assert 'record written'  ($after.workers.codex.availability.state -eq 'scarce' -and $after.workers.codex.availability.valid_until -eq '2026-10-03T00:00:00Z' -and $after.workers.codex.availability.source -eq 'atomickestrel')
Assert 'as_of is now'    ($after.workers.codex.availability.as_of -eq '2026-10-01T12:00:00Z')
Assert 'other fields untouched' ($after.workers.codex.gate -eq 'explicit-call-only' -and $after.workers.glm.note -eq 'keep — me' -and $after.policy.default_builder -eq 'glm')
Set-GrimdexAvailability -GrimdexRoot $g -Name glm -State out -Window 5h -Now $now | Out-Null
Assert 'adds a record where none existed' ((Get-Content $file -Raw | ConvertFrom-Json).workers.glm.availability.state -eq 'out')
$threw = $false; try { Set-GrimdexAvailability -GrimdexRoot $g -Name nobody -State out | Out-Null } catch { $threw = $true }
Assert 'unknown model refused' $threw
$threw = $false; try { Set-GrimdexAvailability -GrimdexRoot $g -Name codex -State out -ValidUntil 'soon' | Out-Null } catch { $threw = $true }
Assert 'bad ValidUntil refused' $threw
Set-Content $file '{ broken'
$threw = $false; try { Set-GrimdexAvailability -GrimdexRoot $g -Name codex -State out | Out-Null } catch { $threw = $true }
Assert 'malformed file refused, left as is' ($threw -and (Get-Content $file -Raw).Trim() -eq '{ broken')

Write-Host 'Resolve-GrimdexBuilderChain'
$chainJson = @'
{
  "workers": {
    "free-fast":  { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 42 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "free-flip":  { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 99 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "free-slow":  { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 34, "total": 35, "seconds": 400 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "free-untried": { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                      "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "free-weak":  { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 31, "total": 35, "seconds": 10 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "free-out":   { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 5 },
                    "availability": { "state": "out", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "free-stale": { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 5 },
                    "availability": { "state": "available", "as_of": "2026-09-01T12:00:00Z", "window": "none" } },
    "free-failed": { "invoke": "cli:cmd", "offer": { "free": true }, "tier": "cheap",
                    "trial": { "passed": 0, "total": 35, "seconds": 284 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "deal-one":   { "invoke": "cli:cmd", "offer": { "free": false, "deal_label": "Contributor" }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 83 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "deal-scarce": { "invoke": "cli:cmd", "offer": { "free": false }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 90 },
                    "availability": { "state": "scarce", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "deal-nokey": { "invoke": "cli:cmd", "offer": { "deal_label": "50% off" }, "tier": "cheap",
                    "trial": { "passed": 35, "total": 35, "seconds": 70 },
                    "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "no-offer":   { "invoke": "claude-subagent:sonnet" },
    "other":      { "invoke": "cli:agy", "availability": { "state": "available", "as_of": "2026-10-01T12:00:00Z", "window": "none" } },
    "kimi-k3":    { "invoke": "cli:cmd" },
    "openrouter-glm":  { "invoke": "cli:bash" },
    "agy":        { "invoke": "cli:agy" },
    "kiro":       { "invoke": "cli:kiro-cli" },
    "openrouter-free": { "invoke": "cli:bash" }
  },
  "policy": { "builder_chain": [ "@cc-free-best", "@cc-deal-best", "kimi-k3", "openrouter-glm", "agy", "kiro", "openrouter-free" ] }
}
'@
$cm = $chainJson | ConvertFrom-Json -DateKind String
# The fixture stands for one Command Code pool: eight free rows (one untried, one at 88%, one out,
# one stale reading, one a failed trial), two priced rows, and workers with no offer at all.
$chain = @(Resolve-GrimdexBuilderChain -Models $cm -Now $now)
Assert 'no chain in the resolved names' ($chain -notcontains '@cc-free-best')
Assert 'free token: best pass rate first'  ($chain[0] -eq 'free-fast')
Assert 'free token: tie broken on speed'     ($chain[1] -eq 'free-flip')
Assert 'free token: slower one still in'     ($chain[2] -eq 'free-slow')
Assert 'free token: under 90% left out'      ($chain -notcontains 'free-weak')
Assert 'free token: no trial left out'       ($chain -notcontains 'free-untried')
Assert 'free token: out left out'            ($chain -notcontains 'free-out')
Assert 'free token: expired reading left out' ($chain -notcontains 'free-stale')
Assert 'free token: failed trial left out'   ($chain -notcontains 'free-failed')
Assert 'deal token: contributor + scarce + no-free-key, fastest first' ((($chain[3..5]) -join ',') -eq 'deal-nokey,deal-one,deal-scarce')
Assert 'deals never appear in the free token' ($chain.IndexOf('deal-one') -gt $chain.IndexOf('free-slow'))
Assert 'plain names pass through unchanged'  ((($chain[6..10]) -join ',') -eq 'kimi-k3,openrouter-glm,agy,kiro,openrouter-free')
$ghost = [pscustomobject]@{ workers = $cm.workers
                           policy = [pscustomobject]@{ builder_chain = @('ghost', 'other') } }
Assert 'unknown names skipped, no error'     (((Resolve-GrimdexBuilderChain -Models $ghost -Now $now) -join ',') -eq 'other')
Assert 'no duplicates in the resolved chain' ((@($chain | Sort-Object -Unique)).Count -eq $chain.Count)
$dup = [pscustomobject]@{ workers = $cm.workers
                         policy = [pscustomobject]@{ builder_chain = @('kimi-k3', 'kimi-k3', '@cc-free-best', 'kimi-k3') } }
Assert 'a name listed twice is emitted once' (((Resolve-GrimdexBuilderChain -Models $dup -Now $now)[0]) -eq 'kimi-k3')
Assert 'a repeated name keeps its first entry' (((Resolve-GrimdexBuilderChain -Models $dup -Now $now) -join ',') -eq 'kimi-k3,free-fast,free-flip,free-slow')
$noChain = [pscustomobject]@{ workers = $cm.workers; policy = [pscustomobject]@{ default_builder = 'other' } }
Assert 'no policy.builder_chain -> nothing'  (@(Resolve-GrimdexBuilderChain -Models $noChain -Now $now).Count -eq 0)
Assert 'no workers key -> nothing'           (@(Resolve-GrimdexBuilderChain -Models ([pscustomobject]@{ policy = $cm.policy }) -Now $now).Count -eq 0)
$entries = @(Resolve-GrimdexBuilderChain -Models $cm -Now $now -WithEntry)
Assert '-WithEntry reports the winning token' ($entries[0].Entry -eq '@cc-free-best' -and $entries[3].Entry -eq '@cc-deal-best' -and $entries[6].Entry -eq 'kimi-k3')

Write-Host 'Test-GrimdexTrialFailed / Test-GrimdexTrialRate / Test-GrimdexOfferFree'
function TW([hashtable]$t) { [pscustomobject]@{ trial = [pscustomobject]$t } }
function OW($free) { [pscustomobject]@{ offer = [pscustomobject]@{ free = $free } } }
Assert 'no trial is not a failure'      (-not (Test-GrimdexTrialFailed -Worker (Rec @{ roles = @('x') })))
Assert 'trial with no total is unknown' (-not (Test-GrimdexTrialFailed -Worker (TW @{ passed = 0 })))
Assert 'half passed is not a failure'   (-not (Test-GrimdexTrialFailed -Worker (TW @{ passed = 9; total = 18 })))
Assert 'under half passed is a failure' (Test-GrimdexTrialFailed -Worker (TW @{ passed = 16; total = 35 }))
Assert '0 of 35 is a failure'           (Test-GrimdexTrialFailed -Worker (TW @{ passed = 0; total = 35 }))
Assert 'rate is passed/total'           ((Test-GrimdexTrialRate -Worker (TW @{ passed = 34; total = 35 })) -gt 0.97)
Assert 'no offer is not a free offer'   (-not (Test-GrimdexOfferFree -Worker (Rec @{ roles = @('x') })))
Assert 'offer.free true is free'        (Test-GrimdexOfferFree -Worker (OW $true))
Assert 'offer.free false is not free'   (-not (Test-GrimdexOfferFree -Worker (OW $false)))

Write-Host 'Set-GrimdexAvailabilityByInvoke'
$byInvokeJson = @'
{ "workers": {
    "cc-free":  { "invoke": "cli:cmd", "offer": { "free": true },  "roles": ["bulk-code"], "note": "keep" },
    "cc-deal":  { "invoke": "cli:cmd", "offer": { "free": false }, "roles": ["bulk-code"] },
    "cc-plain": { "invoke": "cli:cmd",                             "roles": ["draft"] },
    "cc-5h":    { "invoke": "cli:cmd", "offer": { "free": false }, "roles": ["small-code"] },
    "cc-out":   { "invoke": "cli:cmd", "offer": { "free": false }, "roles": ["draft"],
                  "availability": { "state": "scarce", "as_of": "2026-10-01T00:00:00Z", "window": "none" } },
    "agy":      { "invoke": "cli:agy",  "roles": ["bulk-code"] }
  }, "policy": { "default_builder": "cc-free" } }
'@
Set-Content $file $byInvokeJson
$changed = @(Set-GrimdexAvailabilityByInvoke -GrimdexRoot $g -Invoke 'cli:cmd' -State out -SkipFree -Window monthly -ValidUntil '2026-11-01T00:00:00Z' -Detail 'GOAT credit spent' -Now $now)
$bi = Get-Content $file -Raw | ConvertFrom-Json -DateKind String
Assert 'every worker on the invoke path changed' (($changed | Sort-Object) -join ',' -eq 'cc-5h,cc-deal,cc-out,cc-plain')
Assert 'free models left alone by -SkipFree' ($null -eq $bi.workers.'cc-free'.PSObject.Properties['availability'])
Assert 'another provider untouched'          ($null -eq $bi.workers.agy.PSObject.Properties['availability'])
Assert 'record written with the given window' ($bi.workers.'cc-deal'.availability.state -eq 'out' -and $bi.workers.'cc-deal'.availability.window -eq 'monthly' -and $bi.workers.'cc-deal'.availability.valid_until -eq '2026-11-01T00:00:00Z' -and $bi.workers.'cc-deal'.availability.detail -eq 'GOAT credit spent')
Assert 'overwrites an existing record'       ($bi.workers.'cc-out'.availability.state -eq 'out' -and $bi.workers.'cc-out'.availability.valid_until -eq '2026-11-01T00:00:00Z')
Assert 'other worker fields untouched'       ($bi.workers.'cc-free'.note -eq 'keep' -and $bi.policy.default_builder -eq 'cc-free')
Set-Content $file $byInvokeJson
$all = @(Set-GrimdexAvailabilityByInvoke -GrimdexRoot $g -Invoke 'cli:cmd' -State scarce -Now $now)
$bi = Get-Content $file -Raw | ConvertFrom-Json -DateKind String
Assert 'without -SkipFree the free models go too' ($all.Count -eq 5 -and $bi.workers.'cc-free'.availability.state -eq 'scarce')
Assert 'an unknown invoke changes nothing' (@(Set-GrimdexAvailabilityByInvoke -GrimdexRoot $g -Invoke 'cli:nope' -State out -Now $now).Count -eq 0)
Set-Content $file '{ broken'
$threw = $false; try { Set-GrimdexAvailabilityByInvoke -GrimdexRoot $g -Invoke 'cli:cmd' -State out -Now $now | Out-Null } catch { $threw = $true }
Assert 'malformed file refused by the loop too' ($threw -and (Get-Content $file -Raw).Trim() -eq '{ broken')

Write-Host 'Set-GrimdexModelRecord'
Set-Content $file '{"workers":{"codex":{"roles":["on-call"],"gate":"explicit-call-only","note":"mine"}},"policy":{}}'
$r = Set-GrimdexModelRecord -GrimdexRoot $g -Name 'pixel-canary' -Fields @{ invoke = 'cli:cmd'; roles = @('bulk-code'); offer = @{ free = $true; term = 'stealth preview' } }
$m2 = Get-Content $file -Raw | ConvertFrom-Json
Assert 'new model gets every field' ($r.New -and $m2.workers.'pixel-canary'.invoke -eq 'cli:cmd' -and $m2.workers.'pixel-canary'.offer.free)
$r = Set-GrimdexModelRecord -GrimdexRoot $g -Name codex -Fields @{ note = 'overwritten?'; gate = $null; trial = @{ score = '9/9' } }
$m2 = Get-Content $file -Raw | ConvertFrom-Json
Assert 'existing model: only owned fields change' ($m2.workers.codex.note -eq 'mine' -and $m2.workers.codex.gate -eq 'explicit-call-only' -and $m2.workers.codex.trial.score -eq '9/9' -and ($r.Changed -join ',') -eq 'trial')
$threw = $false; try { Set-GrimdexModelRecord -GrimdexRoot $g -Name '../x' -Fields @{ a = 1 } | Out-Null } catch { $threw = $true }
Assert 'path-shaped name refused' $threw

Write-Host 'Test-GrimdexCodeExcluded'
$pol = [pscustomobject]@{ code_exclude = @('(?i)ling') }
Assert 'ling name excluded' (Test-GrimdexCodeExcluded -Name 'cc-ling-sante' -Worker ([pscustomobject]@{}) -Policy $pol)
Assert 'ling model id in invoke_args excluded' (Test-GrimdexCodeExcluded -Name 'newfree' -Worker ([pscustomobject]@{ invoke_args = 'cmd -p -m inclusionai/Ling-4.0:free' }) -Policy $pol)
Assert 'other model not excluded' (-not (Test-GrimdexCodeExcluded -Name 'space-bunny' -Worker ([pscustomobject]@{ invoke_args = 'cmd -p -m stealth/space-bunny-alpha' }) -Policy $pol))
Assert 'no policy -> nothing excluded' (-not (Test-GrimdexCodeExcluded -Name 'cc-ling' -Worker ([pscustomobject]@{}) -Policy $null))

Write-Host 'Get-GrimdexModels'
Set-Content $file '{"workers":{"x":{"roles":["docs"]}}}'
Assert 'reads config/models.json' ($null -ne (Get-GrimdexModels -GrimdexRoot $g))
Remove-Item $file
Set-Content (Join-Path $g 'config' 'fleet.json') '{"workers":{"x":{"roles":["docs"]}}}'
$legacy = Get-GrimdexModels -GrimdexRoot $g -WarningVariable wv -WarningAction SilentlyContinue
Assert 'falls back to the old fleet.json name, with a warning' ($null -ne $legacy -and ($wv -join ' ') -match 'models.json')

$live = Split-Path $PSScriptRoot -Parent
if (Test-Path (Join-Path $live 'config' 'models.json')) {
    $lm = Get-GrimdexModels -GrimdexRoot $live -WarningVariable lw -WarningAction SilentlyContinue
    Assert 'live models.json: no record problems' (@(Test-GrimdexModelRecords -Models $lm).Count -eq 0)
}
$ex = Get-Content (Join-Path $live 'config' 'models.example.json') -Raw | ConvertFrom-Json -DateKind String
Assert 'example: no record problems' (@(Test-GrimdexModelRecords -Models $ex).Count -eq 0)
Assert 'example: nothing expired for a new user' (@(Get-GrimdexExpiredModels -Models $ex).Count -eq 0)

Remove-Item -Recurse -Force $tmp
if ($script:fail) { Write-Host "$script:fail test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All models-lib tests passed.' -ForegroundColor Green
