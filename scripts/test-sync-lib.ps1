#!/usr/bin/env pwsh
# Tests for scripts/sync-lib.ps1 — temp-dir fixtures, no network.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

# ---------- fixture: a mini-KB root ----------
$root = Join-Path $env:TEMP "grimdex-sync-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $root 'config') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root 'universal' 'promotions') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root 'universal' 'claude-rules') | Out-Null
Set-Content (Join-Path $root 'GRIMDEX.md') -Value "# Law"
Set-Content (Join-Path $root 'universal' 'claude-rules' 'context7.md') -Value "original rule"
$promoLog = Join-Path $root 'universal' 'PROMOTIONS-LOG.md'
Set-Content $promoLog -Value "# Promotions log`n`n<!-- grimdex:log-top -->`n"

# ---------- role detection ----------
Set-Content (Join-Path $root 'config' 'sync.json') -Value '{ "hub": "HUBPC" }'
Assert 'hub hostname -> hub' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'HUBPC') -eq 'hub')
Assert 'hub match is case-insensitive' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'hubpc') -eq 'hub')
Assert 'other hostname -> spoke' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'LAPTOP') -eq 'spoke')
Remove-Item (Join-Path $root 'config' 'sync.json')
Assert 'missing config -> spoke (safe default)' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'HUBPC') -eq 'spoke')
Set-Content (Join-Path $root 'config' 'sync.json') -Value 'not json {'
Assert 'malformed config -> spoke' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'HUBPC') -eq 'spoke')
Set-Content (Join-Path $root 'config' 'sync.json') -Value '{ "hub": "HUBPC" }' # restore config for later tasks

# ---------- proposal build + parse ----------
$pp = New-RuleSyncProposal -GrimdexRoot $root `
    -Target 'universal/claude-rules/context7.md' -Content "new proposed body`nline two" `
    -Machine 'LAPTOP' -Timestamp '2026-06-12T22:00:00-06:00' -Note 'tighten triggers'
Assert 'proposal written to <machine>.sync.md' ((Split-Path $pp -Leaf) -eq 'laptop.sync.md')
Assert 'proposal lives in promotions inbox' ($pp -like '*universal*promotions*')
$parsed = ConvertFrom-RuleSyncProposal -Path $pp
Assert 'parsed kind'    ($parsed.kind -eq 'rule-sync')
Assert 'parsed machine' ($parsed.machine -eq 'LAPTOP')
Assert 'parsed target'  ($parsed.target -eq 'universal/claude-rules/context7.md')
Assert 'parsed note'    ($parsed.note -eq 'tighten triggers')
Assert 'parsed content round-trips' ($parsed.content -eq "new proposed body`nline two")
Remove-Item $pp

# ---------- validation ----------
$good = New-RuleSyncProposal -GrimdexRoot $root -Target 'universal/claude-rules/context7.md' `
    -Content 'body' -Machine 'LAPTOP' -Timestamp '2026-06-12T22:00:00-06:00'
Assert 'valid proposal passes' ((Test-RuleSyncProposal -GrimdexRoot $root -Path $good).valid)

$badTarget = New-RuleSyncProposal -GrimdexRoot $root -Target 'projects/p1/decisions/d001.md' `
    -Content 'body' -Machine 'WORKBOX' -Timestamp '2026-06-12T22:00:00-06:00'
$bt = Test-RuleSyncProposal -GrimdexRoot $root -Path $badTarget
Assert 'non-rule target rejected' (-not $bt.valid -and $bt.reason -match 'rule/law')

$missingTarget = New-RuleSyncProposal -GrimdexRoot $root -Target 'universal/claude-rules/nope.md' `
    -Content 'body' -Machine 'TABLET' -Timestamp '2026-06-12T22:00:00-06:00'
Assert 'absent target rejected' (-not (Test-RuleSyncProposal -GrimdexRoot $root -Path $missingTarget).valid)

$empty = New-RuleSyncProposal -GrimdexRoot $root -Target 'GRIMDEX.md' `
    -Content '   ' -Machine 'DESK' -Timestamp '2026-06-12T22:00:00-06:00'
Assert 'empty content rejected' (-not (Test-RuleSyncProposal -GrimdexRoot $root -Path $empty).valid)

$noFm = Join-Path $root 'universal' 'promotions' 'junk.sync.md'
Set-Content $noFm -Value 'no frontmatter here'
$nf = Test-RuleSyncProposal -GrimdexRoot $root -Path $noFm
Assert 'no-frontmatter rejected, path preserved' (-not $nf.valid -and $nf.path -eq $noFm)

# ---------- pending enumeration ----------
$pending = @(Get-PendingRuleSyncProposals -GrimdexRoot $root)
Assert 'all *.sync.md enumerated' ($pending.Count -eq 5)
Assert 'mix of valid + invalid' (@($pending | Where-Object valid).Count -eq 1)
Get-ChildItem (Join-Path $root 'universal' 'promotions') -Filter '*.sync.md' | Remove-Item

# ---------- approve ----------
Set-Content (Join-Path $root 'universal' 'claude-rules' 'context7.md') -Value 'original rule'
$prop = New-RuleSyncProposal -GrimdexRoot $root -Target 'universal/claude-rules/context7.md' `
    -Content 'the new approved rule body' -Machine 'LAPTOP' -Timestamp '2026-06-12T22:00:00-06:00' -Note 'why'
$res = Approve-RuleSyncProposal -GrimdexRoot $root -Path $prop -DecidedDate '2026-06-13'
Assert 'approve reports accepted' ($res.action -eq 'accepted')
Assert 'target rewritten' ((Get-Content (Join-Path $root 'universal' 'claude-rules' 'context7.md') -Raw) -eq 'the new approved rule body')
Assert 'proposal file removed' (-not (Test-Path $prop))
Assert 'promotions-log got ACCEPTED entry' ((Get-Content $promoLog -Raw) -match 'rule-sync.*ACCEPTED')
Assert 'log entry newest-on-top' (((Get-Content $promoLog -Raw) -split 'grimdex:log-top -->')[1].TrimStart() -match '^## ')

# ---------- reject ----------
$prop2 = New-RuleSyncProposal -GrimdexRoot $root -Target 'GRIMDEX.md' `
    -Content '# tampered law' -Machine 'WORKBOX' -Timestamp '2026-06-12T23:00:00-06:00'
$lawBefore = Get-Content (Join-Path $root 'GRIMDEX.md') -Raw
$res2 = Deny-RuleSyncProposal -GrimdexRoot $root -Path $prop2 -Reason 'not wanted' -DecidedDate '2026-06-13'
Assert 'reject reports rejected' ($res2.action -eq 'rejected')
Assert 'reject leaves target untouched' ((Get-Content (Join-Path $root 'GRIMDEX.md') -Raw) -eq $lawBefore)
Assert 'rejected proposal removed' (-not (Test-Path $prop2))
Assert 'promotions-log got REJECTED entry' ((Get-Content $promoLog -Raw) -match 'rule-sync.*REJECTED')

# ---------- sweep surfacing ----------
$valid = New-RuleSyncProposal -GrimdexRoot $root -Target 'GRIMDEX.md' `
    -Content '# proposed' -Machine 'LAPTOP' -Timestamp '2026-06-12T22:00:00-06:00'
Set-Content (Join-Path $root 'universal' 'promotions' 'bad.sync.md') -Value 'no frontmatter'
$rf = @(Test-GrimdexRuleSyncProposals -GrimdexRoot $root)
Assert 'valid proposal -> info finding'  (@($rf | Where-Object { $_.severity -eq 'info' }).Count -eq 1)
Assert 'malformed proposal -> warn finding' (@($rf | Where-Object { $_.severity -eq 'warn' }).Count -eq 1)
Get-ChildItem (Join-Path $root 'universal' 'promotions') -Filter '*.sync.md' | Remove-Item

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
Write-Host ""
if ($failures -gt 0) { Write-Host "$failures FAILED" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASSED" -ForegroundColor Green
