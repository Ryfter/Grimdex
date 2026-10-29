Set-StrictMode -Version Latest
# Model awareness (grimdex-d052): Grimdex KNOWS the models: which exist, what they are for,
# their pins, gates, caveats and last-known availability. Choosing and metering belong to
# AtomicKestrel (AK). AK, when installed, feeds live availability back into config/models.json.
# Spec: docs/superpowers/specs/2026-10-01-model-awareness-split-design.md

$script:GrimdexAvailabilityStates = @('available', 'scarce', 'out', 'unknown')
$script:GrimdexAvailabilityWindows = @('5h', 'weekly', 'monthly', 'none')

function Get-GrimdexModelsPath {
    # config/models.json; config/fleet.json is read for one release as the old name.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $cfg = Join-Path $GrimdexRoot 'config'
    foreach ($n in 'models.json', 'fleet.json') {
        $p = Join-Path $cfg $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-GrimdexModels {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Get-GrimdexModelsPath -GrimdexRoot $GrimdexRoot
    if (-not $path) { return $null }
    $name = Split-Path $path -Leaf
    if ($name -eq 'fleet.json') { Write-Warning 'config/fleet.json is the old name; rename it to config/models.json (grimdex-d052).' }
    try { $models = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String }
    catch { throw "config/$name is malformed JSON: $($_.Exception.Message)" }
    foreach ($bad in @(Test-GrimdexFleetGates -Fleet $models)) {
        Write-Warning "config/$name worker '$($bad.Name)': gate '$($bad.Gate)' is not a restriction. A gate takes the worker out of automatic selection; quota-pool descriptions belong in 'pool'."
    }
    foreach ($bad in @(Test-GrimdexModelRecords -Models $models)) {
        Write-Warning "config/$name worker '$($bad.Name)': $($bad.Problem)"
    }
    return $models
}

function Test-GrimdexFleetGates {
    # `gate` is a restriction, never a description: any worker carrying one is left out of
    # automatic selection (call it by name with -Explicit). Descriptive quota-pool text in
    # `gate` silently removed every bulk-code worker once (grimdex-d051) — so a gate must
    # start with the keyword `explicit-call-only`, optionally followed by `; <condition>`.
    # Returns the offending workers.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fleet)
    if (-not $Fleet.PSObject.Properties['workers']) { return }
    foreach ($p in $Fleet.workers.PSObject.Properties) {
        $g = $p.Value.PSObject.Properties['gate']
        if ($g -and ([string]$g.Value) -notmatch '^explicit-call-only(;|$)') {
            [pscustomobject]@{ Name = $p.Name; Gate = [string]$g.Value }
        }
    }
}

function Test-GrimdexModelRecords {
    # Shape check of every availability record. Returns one row per problem.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Models)
    if (-not $Models.PSObject.Properties['workers']) { return }
    foreach ($p in $Models.workers.PSObject.Properties) {
        # grimdex-d038: a capability claim (trial, offer score, bench) is folklore unless it names
        # the exact model version. The pin is the structured place for it.
        $w = $p.Value
        $claims = $w.PSObject.Properties['trial'] -or $w.PSObject.Properties['offer'] -or $w.PSObject.Properties['bench']
        $pinned = $w.PSObject.Properties['model_pin'] -and $w.model_pin -and $w.model_pin.PSObject.Properties['default'] -and $w.model_pin.default
        if ($claims -and -not $pinned -and -not ($w.PSObject.Properties['model'] -and $w.model)) {
            [pscustomobject]@{ Name = $p.Name; Problem = 'has trial/offer/bench data but no model_pin.default (grimdex-d038: name the exact model version)' }
        }
        $a = $p.Value.PSObject.Properties['availability']
        if (-not $a -or $null -eq $a.Value -or $a.Value -is [string]) { continue }
        $rec = $a.Value
        $state = if ($rec.PSObject.Properties['state']) { [string]$rec.state } else { '' }
        if ($state -notin $script:GrimdexAvailabilityStates) {
            [pscustomobject]@{ Name = $p.Name; Problem = "availability.state '$state' is not one of $($script:GrimdexAvailabilityStates -join '|')" }
        }
        foreach ($f in 'as_of', 'valid_until') {
            if ($rec.PSObject.Properties[$f] -and $rec.$f -and -not (ConvertTo-GrimdexUtc ([string]$rec.$f))) {
                [pscustomobject]@{ Name = $p.Name; Problem = "availability.$f '$($rec.$f)' is not an ISO-8601 time" }
            }
        }
        if ($rec.PSObject.Properties['window'] -and $rec.window -and ([string]$rec.window) -notin $script:GrimdexAvailabilityWindows) {
            [pscustomobject]@{ Name = $p.Name; Problem = "availability.window '$($rec.window)' is not one of $($script:GrimdexAvailabilityWindows -join '|')" }
        }
    }
}

function ConvertTo-GrimdexUtc {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if (-not $Text) { return $null }
    $dto = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$dto)) {
        return $dto.ToUniversalTime()
    }
    return $null
}

function Get-GrimdexAvailability {
    # Normalizes a worker's availability (old bare string, or the d052 record) and applies
    # expiry: a reading is trusted until its known reset time (valid_until), else until
    # as_of + a fallback chosen by window: 5h -> short (5 h), anything else -> long (7 days).
    # After that the effective state is 'unknown'. A bare string has no time, so never expires.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Worker,
        $Policy,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $short = 5; $long = 168
    if ($Policy -and $Policy.PSObject.Properties['availability_fallback_hours']) {
        $fb = $Policy.availability_fallback_hours
        if ($fb.PSObject.Properties['short']) { $short = [double]$fb.short }
        if ($fb.PSObject.Properties['long'])  { $long  = [double]$fb.long }
    }
    $out = [ordered]@{ State = 'available'; EffectiveState = 'available'; Expired = $false
                       AsOf = $null; ValidUntil = $null; Window = $null; Source = $null; Detail = $null }
    $a = $Worker.PSObject.Properties['availability']
    if (-not $a -or $null -eq $a.Value -or ($a.Value -is [string] -and -not $a.Value)) { return [pscustomobject]$out }
    if ($a.Value -is [string]) {
        $out.State = $a.Value; $out.EffectiveState = $a.Value; $out.Source = 'manual'
        return [pscustomobject]$out
    }
    $rec = $a.Value
    $get = { param($n) if ($rec.PSObject.Properties[$n]) { $rec.$n } else { $null } }
    $out.State = [string](& $get 'state'); if (-not $out.State) { $out.State = 'unknown' }
    $out.Window = [string](& $get 'window')
    $out.Source = [string](& $get 'source')
    $out.Detail = & $get 'detail'
    $out.AsOf = ConvertTo-GrimdexUtc ([string](& $get 'as_of'))
    $out.ValidUntil = ConvertTo-GrimdexUtc ([string](& $get 'valid_until'))
    if (-not $out.ValidUntil -and $out.AsOf) {
        $hours = if ($out.Window -eq '5h') { $short } else { $long }
        $out.ValidUntil = $out.AsOf.AddHours($hours)
    }
    $out.EffectiveState = $out.State
    if ($out.ValidUntil -and $Now -ge $out.ValidUntil) { $out.Expired = $true; $out.EffectiveState = 'unknown' }
    return [pscustomobject]$out
}

function Get-GrimdexExpiredModels {
    # Workers whose availability reading has expired, oldest first.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Models, [datetimeoffset]$Now = [datetimeoffset]::UtcNow)
    if (-not $Models.PSObject.Properties['workers']) { return }
    $policy = if ($Models.PSObject.Properties['policy']) { $Models.policy } else { $null }
    @(foreach ($p in $Models.workers.PSObject.Properties) {
        $av = Get-GrimdexAvailability -Worker $p.Value -Policy $policy -Now $Now
        if ($av.Expired) { [pscustomobject]@{ Name = $p.Name; Availability = $av } }
    }) | Sort-Object { $_.Availability.ValidUntil }
}

function Test-GrimdexAtomicKestrel {
    # Detection never runs AK code: the `kes` command on PATH, or policy.atomickestrel_root
    # naming an AK checkout (it holds kes.ps1).
    [CmdletBinding()]
    param($Models, [string]$KesCommand = 'kes')
    if (Get-Command -Name $KesCommand -ErrorAction SilentlyContinue) { return $true }
    if ($Models -and $Models.PSObject.Properties['policy'] -and $Models.policy.PSObject.Properties['atomickestrel_root']) {
        $root = [string]$Models.policy.atomickestrel_root
        if ($root.StartsWith('~')) { $root = Join-Path $HOME $root.Substring(1).TrimStart('/', '\') }
        if (Test-Path -LiteralPath (Join-Path $root 'kes.ps1')) { return $true }
    }
    return $false
}

function Get-GrimdexAvailabilityNotice {
    # One message for setup/status output when readings have expired; $null when all current.
    # Without AK, the message also says that AK keeps availability current (the operator, 2026-10-01).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Models,
        [Parameter(Mandatory)][bool]$AkInstalled,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $expired = @(Get-GrimdexExpiredModels -Models $Models -Now $Now)
    if (-not $expired.Count) { return $null }
    $names = ($expired | ForEach-Object { $_.Name }) -join ', '
    $oldest = $expired[0].Availability
    $ageDays = if ($oldest.AsOf) { [math]::Floor(($Now - $oldest.AsOf).TotalDays) } else { $null }
    $age = if ($null -ne $ageDays) { "$ageDays day(s)" } else { 'an unknown time' }
    if ($AkInstalled) {
        return "Model availability expired for $($expired.Count) model(s) ($names); the oldest reading is $age old. AtomicKestrel is installed but hasn't synced them: run 'kes models sync'."
    }
    return "Model availability expired for $($expired.Count) model(s) ($names); the oldest reading is $age old. Update by hand (pwsh scripts/set-model-availability.ps1 -Name <model> -State <state>), or install AtomicKestrel, which keeps availability current automatically."
}

function Test-GrimdexOfferFree {
    # $true when the worker carries an `offer` whose free flag is set — a zero-billing model.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Worker)
    $o = $Worker.PSObject.Properties['offer']
    if (-not $o -or $null -eq $o.Value) { return $false }
    return ($o.Value.PSObject.Properties['free'] -and $o.Value.free -eq $true)
}

function Test-GrimdexTrialRate {
    # The hidden-test pass rate of a trialled worker: passed/total, or $null when there is no
    # trial yet, or a trial with no total. Nothing is asserted about a model nobody has tried.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Worker)
    $t = $Worker.PSObject.Properties['trial']
    if (-not $t -or $null -eq $t.Value) { return $null }
    $total = if ($t.Value.PSObject.Properties['total']) { [double]$t.Value.total } else { 0.0 }
    if ($total -le 0) { return $null }
    $passed = if ($t.Value.PSObject.Properties['passed']) { [double]$t.Value.passed } else { 0.0 }
    return ($passed / $total)
}

function Test-GrimdexTrialFailed {
    # $true when a worker has a trial and scored under half its hidden tests. Such a model is
    # never picked automatically, for any role: the trial is the evidence it can't finish, and
    # automatic selection has no way to ask (call it by name with -Explicit to override).
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Worker)
    $rate = Test-GrimdexTrialRate -Worker $Worker
    if ($null -eq $rate) { return $false }
    return ($rate -lt 0.5)
}

function Get-GrimdexOfferPool {
    # The Command Code price tier as rows: workers carrying an `offer`, of one tier or the
    # other (-Free for offer.free, otherwise deals and Contributor tier), that also earned a
    # seat — at least 90% of their hidden tests, and available-or-scarce RIGHT NOW (an expired
    # reading is not now). Best pass rate first, fastest tie-break, because that is the order
    # the operator wants the work done in: free models first, then spend the GOAT credit.
    # The two conditions are deliberately different thresholds — 90% wins a seat in the chain,
    # 50% is the floor below which nothing is auto-picked at all (Test-GrimdexTrialFailed).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Models,
        $Policy,
        [switch]$Free,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    if (-not $Models.PSObject.Properties['workers']) { return }
    $rows = @(foreach ($p in $Models.workers.PSObject.Properties) {
        $w = $p.Value
        $o = $w.PSObject.Properties['offer']
        if (-not $o -or $null -eq $o.Value) { continue }          # no offer: not a Command Code model row
        if ((Test-GrimdexOfferFree -Worker $w) -ne $Free.IsPresent) { continue }
        $rate = Test-GrimdexTrialRate -Worker $w
        if ($null -eq $rate -or $rate -lt 0.9) { continue }
        $state = (Get-GrimdexAvailability -Worker $w -Policy $Policy -Now $Now).EffectiveState
        if ($state -notin @('available', 'scarce')) { continue }
        $secs = 0.0
        $t = $w.PSObject.Properties['trial']
        if ($t.Value.PSObject.Properties['seconds'] -and $null -ne $t.Value.seconds) { $secs = [double]$t.Value.seconds }
        [pscustomobject]@{ Name = $p.Name; Rate = $rate; Seconds = $secs }
    })
    @($rows | Sort-Object @{ Expression = 'Rate'; Descending = $true }, @{ Expression = 'Seconds' })
}

function Resolve-GrimdexBuilderChain {
    # Expands policy.builder_chain into worker names, in order. Two tokens are computed rather
    # than written down, because the models they stand for come and go: when a free stealth
    # preview ends the model reappears under another name, and a hard-coded default goes stale.
    #   @cc-free-best  workers offering free
    #   @cc-deal-best workers with an offer that isn't free — deals, Contributor tier
    # Each token expands to ALL qualifying workers, best first, so when the best one is out the
    # next takes over (operator's wish, 2026-10-05). Plain names pass through; a name that is
    # not a worker here is skipped, never an error; a name is never emitted twice.
    # Returns names, or {Name, Entry} rows with -WithEntry (Entry is the chain token that
    # produced the name, which is what Select-FleetWorker reports in its Reason).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Models,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow,
        [switch]$WithEntry
    )
    if (-not $Models.PSObject.Properties['workers']) { return }
    $policy = if ($Models.PSObject.Properties['policy']) { $Models.policy } else { $null }
    if (-not $policy -or -not $policy.PSObject.Properties['builder_chain']) { return }
    $out = @()
    $seen = @{}
    foreach ($item in @($policy.builder_chain)) {
        $entry = [string]$item
        if (-not $entry) { continue }
        $names = switch ($entry) {
            '@cc-free-best'  { @(Get-GrimdexOfferPool -Models $Models -Policy $policy -Free -Now $Now | ForEach-Object Name) }
            '@cc-deal-best' { @(Get-GrimdexOfferPool -Models $Models -Policy $policy -Now $Now | ForEach-Object Name) }
            default         { @($entry) }
        }
        foreach ($n in $names) {
            if ($seen.ContainsKey($n) -or -not $Models.workers.PSObject.Properties[$n]) { continue }
            if (Test-GrimdexCodeExcluded -Name $n -Worker $Models.workers.$n -Policy $policy) { continue }
            $seen[$n] = $true
            if ($WithEntry) { $out += [pscustomobject]@{ Name = $n; Entry = $entry } } else { $out += $n }
        }
    }
    return @($out)
}

function Read-GrimdexModelsFile {
    # The parsed config/models.json of one root, read ONCE. Both writers below need the file
    # twice (to decide what to write, then to save it) and a second read would not see the
    # first write — so they share this.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path (Join-Path $GrimdexRoot 'config') 'models.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "config/models.json not found under $GrimdexRoot" }
    try { $models = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String }
    catch { throw "config/models.json is malformed JSON; refusing to write: $($_.Exception.Message)" }
    return [pscustomobject]@{ Path = $path; Models = $models }
}

function Write-GrimdexModelsFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Models)
    [IO.File]::WriteAllText($Path, ($Models | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
}

function Set-GrimdexAvailability {
    # Rewrites ONE worker's availability record in config/models.json and nothing else.
    # Refuses when the file doesn't parse or the worker doesn't exist.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('available', 'scarce', 'out', 'unknown')][string]$State,
        [ValidateSet('5h', 'weekly', 'monthly', 'none')][string]$Window = 'none',
        [string]$ValidUntil,
        [string]$Detail,
        [ValidateSet('manual', 'atomickestrel')][string]$Source = 'manual',
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $read = Read-GrimdexModelsFile -GrimdexRoot $GrimdexRoot
    $path = $read.Path; $models = $read.Models
    if (-not $models.workers.PSObject.Properties[$Name]) { throw "No model named '$Name' in config/models.json" }
    if ($ValidUntil -and -not (ConvertTo-GrimdexUtc $ValidUntil)) { throw "ValidUntil '$ValidUntil' is not an ISO-8601 time" }
    $rec = [ordered]@{ state = $State; as_of = $Now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); window = $Window }
    if ($ValidUntil) { $rec.valid_until = (ConvertTo-GrimdexUtc $ValidUntil).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $rec.source = $Source
    if ($Detail) { $rec.detail = $Detail }
    $w = $models.workers.$Name
    if ($w.PSObject.Properties['availability']) { $w.availability = [pscustomobject]$rec }
    else { $w | Add-Member -NotePropertyName availability -NotePropertyValue ([pscustomobject]$rec) }
    Write-GrimdexModelsFile -Path $path -Models $models
    return [pscustomobject]$rec
}

function Set-GrimdexAvailabilityByInvoke {
    # Sets the availability of EVERY worker reached by one `invoke` path — one model provider
    # (cli:cmd, cli:agy, ...) — and returns the names changed. For the Command Code seat it is
    # how a credit is parked: when the $70 or a window cap is gone, `-SkipFree` marks out every
    # GOAT-billed model while leaving the free ones alone, since those don't touch the credit.
    # The names of a pool move (stealth models come and go), so the set is keyed by invoke,
    # never by hand-written names.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Invoke,
        [Parameter(Mandatory)][ValidateSet('available', 'scarce', 'out', 'unknown')][string]$State,
        [ValidateSet('5h', 'weekly', 'monthly', 'none')][string]$Window = 'none',
        [string]$ValidUntil,
        [string]$Detail,
        [switch]$SkipFree,
        [ValidateSet('manual', 'atomickestrel')][string]$Source = 'manual',
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $read = Read-GrimdexModelsFile -GrimdexRoot $GrimdexRoot
    if ($ValidUntil -and -not (ConvertTo-GrimdexUtc $ValidUntil)) { throw "ValidUntil '$ValidUntil' is not an ISO-8601 time" }
    $rec = [ordered]@{ state = $State; as_of = $Now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); window = $Window }
    if ($ValidUntil) { $rec.valid_until = (ConvertTo-GrimdexUtc $ValidUntil).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $rec.source = $Source
    if ($Detail) { $rec.detail = $Detail }
    $changed = @()
    foreach ($p in $read.Models.workers.PSObject.Properties) {
        if (-not $p.Value.PSObject.Properties['invoke'] -or [string]$p.Value.invoke -ne $Invoke) { continue }
        if ($SkipFree -and (Test-GrimdexOfferFree -Worker $p.Value)) { continue }
        $w = $p.Value
        if ($w.PSObject.Properties['availability']) { $w.availability = [pscustomobject]$rec }
        else { $w | Add-Member -NotePropertyName availability -NotePropertyValue ([pscustomobject]$rec) }
        $changed += $p.Name
    }
    if ($changed.Count) { Write-GrimdexModelsFile -Path $read.Path -Models $read.Models }
    return @($changed)
}

function Set-GrimdexModelRecord {
    # Upsert one model's record in config/models.json for a discoverer such as AtomicKestrel's
    # daily Command Code check (grimdex-d053). Merges the given fields and never removes a field.
    # On an existing model it changes only fields listed in -Owned (default: availability,
    # trial, offer); hand-written fields such as roles, gate and note stay the operator's.
    # A new model gets every given field. Refuses a malformed file.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9._-]*$')][string]$Name,
        [Parameter(Mandatory)][hashtable]$Fields,
        [string[]]$Owned = @('availability', 'trial', 'offer')
    )
    $read = Read-GrimdexModelsFile -GrimdexRoot $GrimdexRoot
    $models = $read.Models
    $isNew = -not $models.workers.PSObject.Properties[$Name]
    if ($isNew) { $models.workers | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) }
    $w = $models.workers.$Name
    $changed = @()
    foreach ($k in $Fields.Keys) {
        if (-not $isNew -and $k -notin $Owned) { continue }
        $v = $Fields[$k]; if ($v -is [hashtable]) { $v = [pscustomobject]$v }
        if ($w.PSObject.Properties[$k]) { $w.$k = $v } else { $w | Add-Member -NotePropertyName $k -NotePropertyValue $v }
        $changed += $k
    }
    Write-GrimdexModelsFile -Path $read.Path -Models $models
    return [pscustomobject]@{ Name = $Name; New = $isNew; Changed = $changed }
}

function Test-GrimdexCodeExcluded {
    # True when policy.code_exclude (regex list) matches the worker's name or invoke_args.
    # Operator ruling 2026-10-05: "Don't use Ling for programming." A pattern, not a name list,
    # because the daily Command Code check adds new models (a future Ling) with coding roles.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Worker, $Policy)
    if (-not $Policy -or -not $Policy.PSObject.Properties['code_exclude']) { return $false }
    $args2 = if ($Worker.PSObject.Properties['invoke_args']) { [string]$Worker.invoke_args } else { '' }
    foreach ($p in @($Policy.code_exclude)) {
        if ($Name -match $p -or $args2 -match $p) { return $true }
    }
    return $false
}
