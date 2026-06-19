#!/usr/bin/env pwsh
# Tests for scripts/model-lib.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'model-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

# --- Test-GrimdexModelId ---
Assert 'valid frontier id' (Test-GrimdexModelId 'claude-code/opus-4.8')
Assert 'valid id with params' (Test-GrimdexModelId 'codex/codex-5.4-mini (reasoning:high)')
Assert 'valid local tag with colon' (Test-GrimdexModelId 'ollama/qwen2.5-coder:32b-q4')
Assert 'empty -> invalid' (-not (Test-GrimdexModelId ''))
Assert 'no slash -> invalid' (-not (Test-GrimdexModelId 'opus-4.8'))
Assert 'uppercase runner -> invalid' (-not (Test-GrimdexModelId 'Claude-Code/opus'))
Assert 'parens without space -> invalid' (-not (Test-GrimdexModelId 'codex/codex(x)'))

# --- Split-GrimdexModelId ---
$s = Split-GrimdexModelId 'claude-code/opus-4.8'
Assert 'split runner' ($s.runner -eq 'claude-code')
Assert 'split model' ($s.model -eq 'opus-4.8')
Assert 'split params null when absent' ($null -eq $s.params)
$s = Split-GrimdexModelId 'codex/codex-5.4-mini (reasoning:high)'
Assert 'split runner with params' ($s.runner -eq 'codex')
Assert 'split model strips params' ($s.model -eq 'codex-5.4-mini')
Assert 'split params captured' ($s.params -eq 'reasoning:high')

# --- Get-GrimdexModelTier ---
Assert 'claude-code is frontier' ((Get-GrimdexModelTier 'claude-code') -eq 'frontier')
Assert 'codex is frontier' ((Get-GrimdexModelTier 'codex') -eq 'frontier')
Assert 'ollama is local' ((Get-GrimdexModelTier 'ollama') -eq 'local')
Assert 'lm-studio is local' ((Get-GrimdexModelTier 'lm-studio') -eq 'local')

# --- Format-GrimdexUsageLine ---
$l = Format-GrimdexUsageLine -Timestamp '2026-06-18T14:30-06:00' -Model 'claude-code/opus-4.8' -Did 'did a thing' -Decisions @('d017', 'd018')
Assert 'line starts with bullet + timestamp' ($l.StartsWith('- 2026-06-18T14:30-06:00 — '))
Assert 'line names the model' ($l.Contains('claude-code/opus-4.8'))
Assert 'line lists decision ids' ($l.Contains(' → d017, d018'))
$l2 = Format-GrimdexUsageLine -Timestamp 't' -Model 'm/x' -Did 'no decisions'
Assert 'no decisions -> no arrow' (-not $l2.Contains(' → '))

# --- Add-GrimdexUsageLine ---
$fresh = Add-GrimdexUsageLine -Content $null -ProjectId 'proj-x' -Line '- A'
Assert 'fresh log is titled' ($fresh.Contains('# Model usage — proj-x'))
Assert 'fresh log carries the line' ($fresh.Contains('- A'))
$two = Add-GrimdexUsageLine -Content $fresh -ProjectId 'proj-x' -Line '- B'
Assert 'second entry added' ($two.Contains('- A') -and $two.Contains('- B'))
Assert 'newest on top (B above A)' ($two.IndexOf('- B') -lt $two.IndexOf('- A'))
Assert 'title stays above entries' ($two.IndexOf('# Model usage') -lt $two.IndexOf('- B'))

# --- catalog fixture ---
$catalog = @'
# Model catalog

## Frontier models

| runner | model | status | first-seen | notes |
|---|---|---|---|---|
| claude-code | opus-4.8 | current | 2026-06 | |
| codex | codex-5.5 | current | 2026-06 | |

## Local models

| runner | model | role | first-seen | last-seen | superseded-by |
|---|---|---|---|---|---|
| _(none yet — fills in from observed usage)_ | | | | | |
'@

# --- Test-GrimdexCatalogHasModel ---
Assert 'seeded frontier model found' (Test-GrimdexCatalogHasModel -Catalog $catalog -Runner 'claude-code' -Model 'opus-4.8')
Assert 'absent model not found' (-not (Test-GrimdexCatalogHasModel -Catalog $catalog -Runner 'claude-code' -Model 'opus-4.9'))
Assert 'placeholder is not a real model' (-not (Test-GrimdexCatalogHasModel -Catalog $catalog -Runner 'ollama' -Model 'devstral'))

# --- Add-GrimdexCatalogModel: frontier ---
$c1 = Add-GrimdexCatalogModel -Catalog $catalog -Runner 'claude-code' -Model 'opus-4.9' -Tier frontier -Date '2026-07-01'
Assert 'new frontier model registered' (Test-GrimdexCatalogHasModel -Catalog $c1 -Runner 'claude-code' -Model 'opus-4.9')
Assert 'new frontier row marked current' ($c1 -match '\|\s*claude-code\s*\|\s*opus-4\.9\s*\|\s*current\s*\|')
$c1b = Add-GrimdexCatalogModel -Catalog $catalog -Runner 'claude-code' -Model 'opus-4.8' -Tier frontier -Date '2026-07-01'
Assert 'present frontier model -> unchanged' ($c1b -eq $catalog)

# --- Add-GrimdexCatalogModel: local replaces placeholder, then appends ---
$c2 = Add-GrimdexCatalogModel -Catalog $catalog -Runner 'ollama' -Model 'devstral' -Tier local -Date '2026-06-15'
Assert 'first local model registered' (Test-GrimdexCatalogHasModel -Catalog $c2 -Runner 'ollama' -Model 'devstral')
Assert 'placeholder removed' (-not ($c2 -match '(?i)none yet'))
$c3 = Add-GrimdexCatalogModel -Catalog $c2 -Runner 'ollama' -Model 'qwen2.5-coder:32b-q4' -Tier local -Date '2026-06-16'
Assert 'second local model appended' ((Test-GrimdexCatalogHasModel -Catalog $c3 -Runner 'ollama' -Model 'devstral') -and (Test-GrimdexCatalogHasModel -Catalog $c3 -Runner 'ollama' -Model 'qwen2.5-coder:32b-q4'))
# re-stamp advances last-seen, no duplicate row
$c4 = Add-GrimdexCatalogModel -Catalog $c3 -Runner 'ollama' -Model 'devstral' -Tier local -Date '2026-06-20'
$devstralRows = @([regex]::Matches($c4, '(?m)^\|\s*ollama\s*\|\s*devstral\s*\|')).Count
Assert 're-stamp does not duplicate the row' ($devstralRows -eq 1)
Assert 're-stamp advances last-seen' ($c4 -match '\|\s*ollama\s*\|\s*devstral\s*\|[^|]*\|[^|]*\|\s*2026-06-20\s*\|')

# --- integration: Add-GrimdexModelStamp against a temp root ---
$tmp = Join-Path $env:TEMP "grimdex-model-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'universal') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'projects') | Out-Null
Set-Content -Path (Join-Path $tmp 'universal/model-catalog.md') -Value $catalog -NoNewline -Encoding utf8
$now = [datetime]'2026-06-18T14:30:00'

$r = Add-GrimdexModelStamp -GrimdexRoot $tmp -ProjectId 'p1' -Model 'claude-code/opus-4.8' -Did 'first step' -Decisions @('d001') -Now $now
Assert 'usage log created' (($r | Where-Object { $_.file -match 'model-usage' }).action -eq 'created')
$logFile = Join-Path $tmp 'projects/p1/model-usage.md'
Assert 'usage file exists on disk' (Test-Path $logFile)
$logged = Get-Content $logFile -Raw
Assert 'logged line carries model + decision' ($logged.Contains('claude-code/opus-4.8') -and $logged.Contains('→ d001'))
Assert 'seeded model -> catalog unchanged action' (($r | Where-Object { $_.file -match 'model-catalog' }).action -eq 'unchanged')

$r2 = Add-GrimdexModelStamp -GrimdexRoot $tmp -ProjectId 'p1' -Model 'ollama/devstral' -Did 'summaries' -Now $now
Assert 'second stamp appends to log' (($r2 | Where-Object { $_.file -match 'model-usage' }).action -eq 'appended')
Assert 'new local model registered via orchestrator' (($r2 | Where-Object { $_.file -match 'model-catalog' }).action -eq 'registered')
$cat2 = Get-Content (Join-Path $tmp 'universal/model-catalog.md') -Raw
Assert 'catalog on disk has the local model' (Test-GrimdexCatalogHasModel -Catalog $cat2 -Runner 'ollama' -Model 'devstral')
$logged2 = Get-Content $logFile -Raw
Assert 'newest entry on top after second stamp' ($logged2.IndexOf('ollama/devstral') -lt $logged2.IndexOf('claude-code/opus-4.8'))

# invalid model id throws
$threw = $false
try { Add-GrimdexModelStamp -GrimdexRoot $tmp -ProjectId 'p1' -Model 'bogus' -Did 'x' | Out-Null } catch { $threw = $true }
Assert 'invalid model id throws' $threw

# --- Find-GrimdexStaleModelUsage ---
# mark devstral superseded in the catalog, then expect the p1 usage line flagged
$catStale = (Get-Content (Join-Path $tmp 'universal/model-catalog.md') -Raw) -replace '(\|\s*ollama\s*\|\s*devstral\s*\|[^|]*\|[^|]*\|[^|]*\|)\s*—\s*\|', '$1 qwen2.5-coder:32b-q4 |'
Set-Content -Path (Join-Path $tmp 'universal/model-catalog.md') -Value $catStale -NoNewline -Encoding utf8
$stale = @(Find-GrimdexStaleModelUsage -GrimdexRoot $tmp)
Assert 'stale usage detected' ($stale.Count -ge 1)
Assert 'stale finding names the model' (($stale | Where-Object { $_.model -eq 'ollama/devstral' }).Count -ge 1)
Assert 'stale finding names the successor' (($stale | Where-Object { $_.successor -match 'qwen2.5-coder' }).Count -ge 1)

# no supersession marks -> no findings
$tmp2 = Join-Path $env:TEMP "grimdex-model2-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $tmp2 'universal') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $tmp2 'projects/p1') | Out-Null
Set-Content -Path (Join-Path $tmp2 'universal/model-catalog.md') -Value $catalog -NoNewline -Encoding utf8
Set-Content -Path (Join-Path $tmp2 'projects/p1/model-usage.md') -Value "# Model usage — p1`n`n- t — claude-code/opus-4.8 — x`n" -NoNewline -Encoding utf8
Assert 'no supersession -> no stale findings' (@(Find-GrimdexStaleModelUsage -GrimdexRoot $tmp2).Count -eq 0)

Remove-Item -Recurse -Force $tmp, $tmp2
if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll model-lib tests passed." -ForegroundColor Green
