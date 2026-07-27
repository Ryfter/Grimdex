#requires -Version 7
Set-StrictMode -Version Latest

# parse-learn-transcript.ps1 — primary feeder for the learn-mode ledger.
# Scans a Claude Code transcript (JSONL) for defined jargon terms (the `**term** — gloss`
# convention) and records one surfacing per distinct term into config/learn-progress.json.
# Deterministic: same transcript in -> same tally out. Uses no model; meant to run inside
# the daily sweep (a headless session already scheduled) for ~zero marginal agent tokens.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TranscriptPath,
    [Parameter(Mandatory)][string]$GrimdexRoot,
    [string]$Date
)

. "$PSScriptRoot/learn-lib.ps1"

$terms = Get-LearnTranscriptTerms -TranscriptPath $TranscriptPath
if (-not $terms.Count) {
    Write-Host "No defined terms found in $TranscriptPath"
    return
}

$progress = Get-LearnProgress -GrimdexRoot $GrimdexRoot
foreach ($term in $terms) {
    $progress = if ($Date) { Add-LearnSurfacing -Progress $progress -Term $term -Date $Date }
                else       { Add-LearnSurfacing -Progress $progress -Term $term }
}
Save-LearnProgress -Progress $progress -GrimdexRoot $GrimdexRoot

Write-Host ("Recorded {0} surfaced term(s): {1}" -f $terms.Count, ($terms -join ', '))
