#!/usr/bin/env pwsh
# Grimdex model-provenance library — stamp which runner/model did each step into
# projects/<id>/model-usage.md and self-register it in universal/model-catalog.md
# (see docs/2026-06-18-model-provenance-tracking-spec.md). Pure string helpers are
# separated from the file-touching orchestrator so they can be tested in isolation.
Set-StrictMode -Version Latest

# Runners that are frontier (a small, named, authoritative set). Everything else is a
# locally-run model, catalogued bottom-up from observed usage.
$script:GrimdexFrontierRunners = @('claude-code', 'codex')

function Test-GrimdexModelId {
    # True when $Id matches runner/model with an optional ` (params)` suffix, e.g.
    # claude-code/opus-4.8  ·  codex/codex-5.4-mini (reasoning:high).
    param([AllowEmptyString()][AllowNull()][string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    # -cmatch: runner is lowercase by convention; reject mixed/upper case explicitly.
    $Id.Trim() -cmatch '^[a-z0-9][a-z0-9-]*/[^()\s][^()]*?(\s\([^()]+\))?$'
}

function Split-GrimdexModelId {
    # runner/model (params) -> @{ runner; model; params }. params is $null when absent.
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-GrimdexModelId $Id)) { throw "Not a valid model id (expected 'runner/model (params)'): $Id" }
    $id = $Id.Trim()
    $params = $null
    if ($id -match '\s\(([^()]+)\)$') {
        $params = $Matches[1].Trim()
        $id = ($id -replace '\s\([^()]+\)$', '').Trim()
    }
    $slash = $id.IndexOf('/')
    [pscustomobject]@{
        runner = $id.Substring(0, $slash)
        model  = $id.Substring($slash + 1)
        params = $params
    }
}

function Get-GrimdexModelTier {
    # 'frontier' for the named harnesses, else 'local'.
    param([Parameter(Mandatory)][string]$Runner)
    if ($script:GrimdexFrontierRunners -contains $Runner) { 'frontier' } else { 'local' }
}

function Format-GrimdexUsageLine {
    # Pure: build one usage-log line. Decision ids (if any) are appended as ` → d1, d2`.
    param(
        [Parameter(Mandatory)][string]$Timestamp,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Did,
        [string[]]$Decisions
    )
    $line = "- $Timestamp — $Model — $($Did.Trim())"
    $ids = @($Decisions | Where-Object { $_ -and $_.Trim() })
    if ($ids.Count) { $line += ' → ' + (($ids | ForEach-Object { $_.Trim() }) -join ', ') }
    $line
}

function Add-GrimdexUsageLine {
    # Pure string -> string: insert $Line newest-on-top into a project's usage log.
    # Null/empty content seeds a titled log. Existing content gets the line above the
    # first entry. Preserves the file's existing newline style.
    param(
        [AllowEmptyString()][AllowNull()][string]$Content,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$Line
    )
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return "# Model usage — $ProjectId`n`n$Line`n"
    }
    $nl = if ($Content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]($Content -split "`r?`n")
    $firstEntry = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^- ') { $firstEntry = $i; break }
    }
    if ($firstEntry -ge 0) {
        $lines.Insert($firstEntry, $Line)
    } else {
        # No entries yet: drop the line after the title + its blank line (or at the end).
        $insertAt = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^# ') { $insertAt = [Math]::Min($i + 2, $lines.Count); break }
        }
        $lines.Insert($insertAt, $Line)
    }
    return ($lines -join $nl)
}

function Test-GrimdexCatalogHasModel {
    # Pure: does the catalog already carry a row for this runner+model?
    param(
        [Parameter(Mandatory)][string]$Catalog,
        [Parameter(Mandatory)][string]$Runner,
        [Parameter(Mandatory)][string]$Model
    )
    foreach ($l in ($Catalog -split "`r?`n")) {
        if ($l -notmatch '^\s*\|') { continue }
        $cells = ($l -split '\|') | ForEach-Object { $_.Trim() }
        # cells[0] is '' (leading pipe); runner=cells[1], model=cells[2]
        if ($cells.Count -ge 3 -and $cells[1] -eq $Runner -and $cells[2] -eq $Model) { return $true }
    }
    return $false
}

function Add-GrimdexCatalogModel {
    # Pure string -> string: register runner/model into the catalog if absent. Frontier
    # rows land as status=current; local rows are bottom-up (role blank). A local row
    # already present has its last-seen advanced to $Date. The local "(none yet)"
    # placeholder is replaced by the first real local row. Returns the (possibly
    # unchanged) catalog text; the caller diffs to decide the action.
    param(
        [Parameter(Mandatory)][string]$Catalog,
        [Parameter(Mandatory)][string]$Runner,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][ValidateSet('frontier', 'local')][string]$Tier,
        [Parameter(Mandatory)][string]$Date
    )
    $nl = if ($Catalog -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]($Catalog -split "`r?`n")
    $sectionTitle = if ($Tier -eq 'frontier') { '## Frontier models' } else { '## Local models' }

    # Locate the section's data-row span: [first data row .. last data row].
    $sec = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimEnd() -eq $sectionTitle) { $sec = $i; break }
    }
    if ($sec -lt 0) { throw "Catalog section not found: $sectionTitle" }
    $firstData = -1; $lastData = -1; $pipeSeen = 0
    for ($i = $sec + 1; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].TrimStart()
        if ($t.StartsWith('## ')) { break }
        if ($t.StartsWith('|')) {
            $pipeSeen++
            if ($pipeSeen -gt 2) {  # skip header row + separator row
                if ($firstData -lt 0) { $firstData = $i }
                $lastData = $i
            }
        }
    }

    $newRow =
        if ($Tier -eq 'frontier') { "| $Runner | $Model | current | $Date |  |" }
        else { "| $Runner | $Model |  | $Date | $Date | — |" }

    # Already present? Frontier: no-op. Local: advance last-seen.
    if (Test-GrimdexCatalogHasModel -Catalog $Catalog -Runner $Runner -Model $Model) {
        if ($Tier -eq 'local') {
            for ($i = $firstData; $i -le $lastData; $i++) {
                $cells = ($lines[$i] -split '\|') | ForEach-Object { $_.Trim() }
                if ($cells.Count -ge 3 -and $cells[1] -eq $Runner -and $cells[2] -eq $Model) {
                    $cells[5] = $Date  # last-seen
                    $lines[$i] = '| ' + (($cells[1..($cells.Count - 2)]) -join ' | ') + ' |'
                    break
                }
            }
        }
        return ($lines -join $nl)
    }

    # Absent: replace the local placeholder if present, else append after the last row.
    if ($Tier -eq 'local' -and $firstData -ge 0) {
        for ($i = $firstData; $i -le $lastData; $i++) {
            if ($lines[$i] -match '(?i)none yet') { $lines[$i] = $newRow; return ($lines -join $nl) }
        }
    }
    if ($lastData -ge 0) { $lines.Insert($lastData + 1, $newRow) }
    else { throw "No table rows found under $sectionTitle to register against." }
    return ($lines -join $nl)
}

function Add-GrimdexModelStamp {
    # Orchestrator: append the usage-log line AND self-register the model in the catalog.
    # Returns one action object per file touched. $Now is injectable for tests.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Did,
        [string[]]$Decisions,
        [datetime]$Now = (Get-Date)
    )
    if (-not (Test-GrimdexModelId $Model)) {
        throw "Not a valid model id (expected 'runner/model (params)'): $Model"
    }
    $parts = Split-GrimdexModelId $Model
    $tier = Get-GrimdexModelTier -Runner $parts.runner
    $stamp = $Now.ToString('yyyy-MM-ddTHH:mmzzz')
    $date = $Now.ToString('yyyy-MM-dd')
    $results = @()

    # 1. Usage log (newest on top).
    $logPath = Join-Path $GrimdexRoot (Join-Path 'projects' (Join-Path $ProjectId 'model-usage.md'))
    $logDir = Split-Path $logPath -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $existing = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { $null }
    $line = Format-GrimdexUsageLine -Timestamp $stamp -Model $Model -Did $Did -Decisions $Decisions
    $newLog = Add-GrimdexUsageLine -Content $existing -ProjectId $ProjectId -Line $line
    Set-Content -Path $logPath -Value $newLog -NoNewline -Encoding utf8
    $results += [pscustomobject]@{ file = $logPath; action = ($existing ? 'appended' : 'created') }

    # 2. Catalog self-registration (clean add; supersession stays with the audit).
    $catPath = Join-Path $GrimdexRoot (Join-Path 'universal' 'model-catalog.md')
    if (-not (Test-Path $catPath)) { throw "Model catalog not found: $catPath" }
    $cat = Get-Content $catPath -Raw
    # Register the bare runner/model — per-invocation params live in the usage line only.
    $newCat = Add-GrimdexCatalogModel -Catalog $cat -Runner $parts.runner -Model $parts.model -Tier $tier -Date $date
    $catAction = if ($newCat -eq $cat) { 'unchanged' } elseif (Test-GrimdexCatalogHasModel -Catalog $cat -Runner $parts.runner -Model $parts.model) { 'updated' } else { 'registered' }
    if ($catAction -ne 'unchanged') { Set-Content -Path $catPath -Value $newCat -NoNewline -Encoding utf8 }
    $results += [pscustomobject]@{ file = $catPath; action = $catAction }

    return $results
}

function Find-GrimdexStaleModelUsage {
    # Read/report (deterministic): list usage-log steps still on a model the catalog
    # marks superseded. The audit raises these as OPEN CONCERNs; marking supersession
    # itself stays human-gated. Returns @{ project; model; successor; line }.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $catPath = Join-Path $GrimdexRoot (Join-Path 'universal' 'model-catalog.md')
    if (-not (Test-Path $catPath)) { return @() }

    # Build superseded runner/model -> successor from the catalog tables.
    $superseded = @{}
    foreach ($l in (Get-Content $catPath -Raw) -split "`r?`n") {
        if ($l -notmatch '^\s*\|') { continue }
        $cells = ($l -split '\|') | ForEach-Object { $_.Trim() }
        if ($cells.Count -lt 4 -or $cells[1] -eq 'runner' -or $cells[1] -match '^-+$') { continue }
        $id = "$($cells[1])/$($cells[2])"
        # Frontier: status cell (3) says 'superseded → X'. Local: superseded-by cell (6).
        if ($cells[3] -match '(?i)superseded') {
            $succ = if ($cells[3] -match '(?:→|->)\s*(.+)$') { $Matches[1].Trim() } else { '?' }
            $superseded[$id] = $succ
        } elseif ($cells.Count -ge 7 -and $cells[6] -and $cells[6] -notmatch '^[—-]*$') {
            $superseded[$id] = $cells[6]
        }
    }
    if (-not $superseded.Count) { return @() }

    $findings = @()
    $projects = Join-Path $GrimdexRoot 'projects'
    if (-not (Test-Path $projects)) { return @() }
    foreach ($proj in Get-ChildItem $projects -Directory) {
        $log = Join-Path $proj.FullName 'model-usage.md'
        if (-not (Test-Path $log)) { continue }
        foreach ($line in (Get-Content $log)) {
            if ($line -notmatch '^- ') { continue }
            foreach ($id in $superseded.Keys) {
                if ($line.Contains($id)) {
                    $findings += [pscustomobject]@{
                        project    = $proj.Name
                        model      = $id
                        successor  = $superseded[$id]
                        line       = $line.Trim()
                    }
                }
            }
        }
    }
    return $findings
}
