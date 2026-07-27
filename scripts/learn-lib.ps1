Set-StrictMode -Version Latest

# learn-lib.ps1 — mechanism-agnostic ledger for learn-mode's deterministic taper.
# Pure compute (Get-LearnProgress read, Get-LearnStage, Add-LearnSurfacing, the term
# detector) is separated from the single IO writer (Save-LearnProgress). Either feeder —
# the transcript parser (primary) or the agent at close (fallback) — calls the same helpers.

# Property existence via the indexer (returns $null when absent) — safe even on an object
# with zero properties, where `.PSObject.Properties.Name -contains x` throws under StrictMode.
function Test-LearnProp($obj, $name) { return ($null -ne $obj.PSObject.Properties[$name]) }

function Set-LearnProp($obj, $name, $value) {
    if (Test-LearnProp $obj $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}

function New-LearnDefaultProgress {
    [pscustomobject]@{
        thresholds = [pscustomobject]@{ full_max = 10; summarized_max = 25 }
        terms      = [pscustomobject]@{}
    }
}

function Get-LearnProgress {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path (Join-Path $GrimdexRoot 'config') 'learn-progress.json'
    if (-not (Test-Path -LiteralPath $path)) { return (New-LearnDefaultProgress) }
    $raw = Get-Content -LiteralPath $path -Raw
    try { $obj = $raw | ConvertFrom-Json }
    catch { throw "config/learn-progress.json is malformed JSON: $($_.Exception.Message)" }
    # Normalize: a partial ledger still gets working thresholds + a terms bag.
    if (-not (Test-LearnProp $obj 'thresholds') -or $null -eq $obj.thresholds) {
        Set-LearnProp $obj 'thresholds' ([pscustomobject]@{ full_max = 10; summarized_max = 25 })
    } else {
        if (-not (Test-LearnProp $obj.thresholds 'full_max'))       { Set-LearnProp $obj.thresholds 'full_max' 10 }
        if (-not (Test-LearnProp $obj.thresholds 'summarized_max')) { Set-LearnProp $obj.thresholds 'summarized_max' 25 }
    }
    if (-not (Test-LearnProp $obj 'terms') -or $null -eq $obj.terms) {
        Set-LearnProp $obj 'terms' ([pscustomobject]@{})
    }
    return $obj
}

function Get-LearnStage {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Progress, [Parameter(Mandatory)][string]$Term)
    $key = $Term.Trim().ToLowerInvariant()
    $count = 0
    if (Test-LearnProp $Progress.terms $key) {
        $t = $Progress.terms.$key
        if (Test-LearnProp $t 'count') { $count = [int]$t.count }
    }
    $fullMax = [int]$Progress.thresholds.full_max
    $summMax = [int]$Progress.thresholds.summarized_max
    if ($count -le $fullMax)      { return 'full' }
    elseif ($count -le $summMax)  { return 'summarized' }
    else                          { return 'occasional' }
}

function Add-LearnSurfacing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Progress,
        [Parameter(Mandatory)][string]$Term,
        [string]$Date
    )
    if (-not $Date) { $Date = (Get-Date -Format 'yyyy-MM-dd') }
    $key = $Term.Trim().ToLowerInvariant()
    if (Test-LearnProp $Progress.terms $key) {
        $t = $Progress.terms.$key
        $cur = 0
        if (Test-LearnProp $t 'count') { $cur = [int]$t.count }
        Set-LearnProp $t 'count' ($cur + 1)
        Set-LearnProp $t 'last_seen' $Date
    } else {
        Set-LearnProp $Progress.terms $key ([pscustomobject]@{ count = 1; last_seen = $Date })
    }
    return $Progress
}

function Save-LearnProgress {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Progress, [Parameter(Mandatory)][string]$GrimdexRoot)
    $dir = Join-Path $GrimdexRoot 'config'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir 'learn-progress.json'
    ($Progress | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
}

# --- transcript parser support (deterministic term detection) ---
# Learn-mode defines a term the first time with the convention:  **term** — gloss
# (bold term, space, em dash or hyphen, space, gloss). The detector matches exactly that.

function Get-LearnDefinedTerms {
    [CmdletBinding()]
    param([string]$Text)
    $terms = @()
    if (-not $Text) { return $terms }
    $rx = [regex]'\*\*([^*\r\n]+?)\*\*\s*[-—]\s'
    foreach ($m in $rx.Matches($Text)) {
        $t = $m.Groups[1].Value.Trim().ToLowerInvariant()
        if ($t) { $terms += $t }
    }
    return @($terms | Select-Object -Unique)
}

function Get-LearnAssistantText {
    [CmdletBinding()]
    param($LineObj)
    $sb = [System.Text.StringBuilder]::new()
    if ((Test-LearnProp $LineObj 'message') -and $LineObj.message) {
        $msg = $LineObj.message
        if ((Test-LearnProp $msg 'content') -and $msg.content) {
            foreach ($block in @($msg.content)) {
                if ($block -is [string]) { [void]$sb.Append(' ').Append($block); continue }
                if ((Test-LearnProp $block 'text') -and $block.text) {
                    [void]$sb.Append(' ').Append([string]$block.text)
                }
            }
        }
    }
    return $sb.ToString()
}

function Get-LearnTranscriptTerms {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TranscriptPath)
    if (-not (Test-Path -LiteralPath $TranscriptPath)) { return @() }
    $found = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $TranscriptPath) {
        if (-not $line.Trim()) { continue }
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        if (-not (Test-LearnProp $obj 'type')) { continue }
        if ($obj.type -ne 'assistant') { continue }
        foreach ($term in (Get-LearnDefinedTerms (Get-LearnAssistantText $obj))) { $found[$term] = $true }
    }
    return @($found.Keys)
}
