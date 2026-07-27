Set-StrictMode -Version Latest
. "$PSScriptRoot/learn-lib.ps1"

$script:fail = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "  PASS: $label" -ForegroundColor Green }
    else { Write-Host "  FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function New-LearnFixture($json) {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("learn_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force | Out-Null
    if ($null -ne $json) { Set-Content -LiteralPath (Join-Path (Join-Path $root 'config') 'learn-progress.json') -Value $json -Encoding UTF8 }
    return $root
}

Write-Host "Get-LearnProgress"
$valid = @'
{ "thresholds": { "full_max": 10, "summarized_max": 25 },
  "terms": { "worktree": { "count": 12, "last_seen": "2026-07-26" } } }
'@
$r1 = New-LearnFixture $valid
$p = Get-LearnProgress -GrimdexRoot $r1
Assert "parses valid learn-progress.json" ($p.terms.worktree.count -eq 12)

$r2 = New-LearnFixture $null
$pd = Get-LearnProgress -GrimdexRoot $r2
Assert "absent file returns default thresholds" ($null -ne $pd -and $pd.thresholds.full_max -eq 10)
Assert "default has no terms" (@($pd.terms.PSObject.Properties).Count -eq 0)

$r3 = New-LearnFixture '{ this is not json'
$threw = $false
try { Get-LearnProgress -GrimdexRoot $r3 } catch { $threw = $true }
Assert "malformed JSON throws" $threw

# partial ledger (no thresholds) gets defaults filled
$r4 = New-LearnFixture '{ "terms": { "a": { "count": 2 } } }'
$pp = Get-LearnProgress -GrimdexRoot $r4
Assert "partial ledger gets default thresholds" ($pp.thresholds.summarized_max -eq 25)

Remove-Item -Recurse -Force $r1, $r2, $r3, $r4 -ErrorAction SilentlyContinue

Write-Host "Get-LearnStage"
$boundJson = @'
{ "thresholds": { "full_max": 10, "summarized_max": 25 },
  "terms": { "a": {"count":10}, "b":{"count":11}, "c":{"count":25}, "d":{"count":26} } }
'@
$pb = $boundJson | ConvertFrom-Json
Assert "unknown term -> full"       ((Get-LearnStage -Progress $pb -Term 'neverseen') -eq 'full')
Assert "count 10 -> full"           ((Get-LearnStage -Progress $pb -Term 'a') -eq 'full')
Assert "count 11 -> summarized"     ((Get-LearnStage -Progress $pb -Term 'b') -eq 'summarized')
Assert "count 25 -> summarized"     ((Get-LearnStage -Progress $pb -Term 'c') -eq 'summarized')
Assert "count 26 -> occasional"     ((Get-LearnStage -Progress $pb -Term 'd') -eq 'occasional')
Assert "stage lookup is case-insensitive" ((Get-LearnStage -Progress $pb -Term 'A') -eq 'full')

Write-Host "Add-LearnSurfacing"
$pAdd = '{ "thresholds": {"full_max":10,"summarized_max":25}, "terms": { "worktree": {"count":3,"last_seen":"2026-07-01"} } }' | ConvertFrom-Json
$pAdd = Add-LearnSurfacing -Progress $pAdd -Term 'worktree' -Date '2026-07-26'
Assert "existing term increments"   ($pAdd.terms.worktree.count -eq 4)
Assert "last_seen updated"          ($pAdd.terms.worktree.last_seen -eq '2026-07-26')
$pAdd = Add-LearnSurfacing -Progress $pAdd -Term 'idempotent' -Date '2026-07-26'
Assert "new term created at count 1" ($pAdd.terms.idempotent.count -eq 1)
Assert "sibling untouched"          ($pAdd.terms.worktree.count -eq 4)
$pAdd = Add-LearnSurfacing -Progress $pAdd -Term 'WORKTREE' -Date '2026-07-27'
Assert "case-insensitive add merges into same term" ($pAdd.terms.worktree.count -eq 5)
$pDefault = New-LearnDefaultProgress
$pDefault = Add-LearnSurfacing -Progress $pDefault -Term 'closure' -Date '2026-07-26'
Assert "add works on default (empty) progress" ($pDefault.terms.closure.count -eq 1)

Write-Host "Save-LearnProgress round-trip"
$rSave = New-LearnFixture $null
$pv = Get-LearnProgress -GrimdexRoot $rSave
$pv = Add-LearnSurfacing -Progress $pv -Term 'monad' -Date '2026-07-26'
Save-LearnProgress -Progress $pv -GrimdexRoot $rSave
$reloaded = Get-LearnProgress -GrimdexRoot $rSave
Assert "save -> get round-trip persists count" ($reloaded.terms.monad.count -eq 1)
Assert "save writes file" (Test-Path -LiteralPath (Join-Path (Join-Path $rSave 'config') 'learn-progress.json'))
Remove-Item -Recurse -Force $rSave -ErrorAction SilentlyContinue

Write-Host "Get-LearnDefinedTerms (detector)"
$text = "A **worktree** — an isolated copy. Also **idempotent** — same result each time. But **bold-only** here has no gloss. Em dash **selector** — routes work."
$terms = Get-LearnDefinedTerms $text
Assert "detects em-dash definition (worktree)" ($terms -contains 'worktree')
Assert "detects hyphen definition (idempotent)" ($terms -contains 'idempotent')
Assert "detects second em-dash def (selector)" ($terms -contains 'selector')
Assert "ignores bold without a gloss dash" (-not ($terms -contains 'bold-only'))
$dupText = "**closure** — captured scope. Later, **closure** — same term again."
Assert "dedups repeated term within text" (@(Get-LearnDefinedTerms $dupText).Count -eq 1)
Assert "empty text -> no terms" (@(Get-LearnDefinedTerms '').Count -eq 0)

Write-Host "Get-LearnTranscriptTerms (JSONL)"
$tf = Join-Path ([System.IO.Path]::GetTempPath()) ("transcript_" + [guid]::NewGuid().ToString('N') + ".jsonl")
$lines = @(
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"A **worktree** — isolated copy of the repo."}]}}',
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Again a **worktree** — still isolated, and **closure** — captured scope."}]}}',
  '{"type":"user","message":{"content":[{"type":"text","text":"what about **ignored** — this is user text not assistant"}]}}',
  '{ this line is not valid json and must be skipped',
  ''
)
Set-Content -LiteralPath $tf -Value $lines -Encoding UTF8
$tterms = Get-LearnTranscriptTerms -TranscriptPath $tf
Assert "aggregates assistant terms across lines (worktree)" ($tterms -contains 'worktree')
Assert "aggregates assistant terms (closure)" ($tterms -contains 'closure')
Assert "dedups worktree across lines" (@($tterms | Where-Object { $_ -eq 'worktree' }).Count -eq 1)
Assert "ignores terms defined in USER text" (-not ($tterms -contains 'ignored'))
Assert "missing transcript -> empty" (@(Get-LearnTranscriptTerms -TranscriptPath (Join-Path ([System.IO.Path]::GetTempPath()) 'nope_does_not_exist.jsonl')).Count -eq 0)
Remove-Item -LiteralPath $tf -Force -ErrorAction SilentlyContinue

Write-Host "shipped example validates"
$repoRoot = Split-Path $PSScriptRoot -Parent
$examplePath = Join-Path (Join-Path $repoRoot 'config') 'learn-progress.example.json'
Assert "learn-progress.example.json exists" (Test-Path -LiteralPath $examplePath)
$ex = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
Assert "example has thresholds"    ($ex.thresholds.full_max -ge 1)
Assert "example stage lookup works" ((Get-LearnStage -Progress $ex -Term 'worktree') -in @('full','summarized','occasional'))

if ($script:fail) { Write-Host "`n$script:fail FAILED" -ForegroundColor Red; exit 1 }
else { Write-Host "`nAll passed" -ForegroundColor Green }
