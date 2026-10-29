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
$root = Join-Path ([IO.Path]::GetTempPath()) "grimdex-sync-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $root 'config') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root 'universal' 'promotions') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root 'universal' 'claude-rules') | Out-Null
Set-Content (Join-Path $root 'GRIMDEX.md') -Value "# Law"
Set-Content (Join-Path $root 'universal' 'claude-rules' 'context7.md') -Value "original rule"
$promoLog = Join-Path $root 'universal' 'PROMOTIONS-LOG.md'
Set-Content $promoLog -Value "# Promotions log`n`n<!-- grimdex:log-top -->`n"

# ---------- hostname helper (cross-platform; $env:COMPUTERNAME is Windows-only) ----------
Assert 'Get-GrimdexHostName returns non-empty' (-not [string]::IsNullOrWhiteSpace((Get-GrimdexHostName)))

# ---------- role detection ----------
Set-Content (Join-Path $root 'config' 'sync.json') -Value '{ "hub": "HUBPC" }'
Assert 'hub hostname -> hub' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'HUBPC') -eq 'hub')
Assert 'hub match is case-insensitive' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'hubpc') -eq 'hub')
Assert 'hub match tolerates a .local/DNS suffix' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'hubpc.local') -eq 'hub')
Assert 'config hub with suffix also matches short name' ((& {
    Set-Content (Join-Path $root 'config' 'sync.json') -Value '{ "hub": "hubpc.lan" }'
    $r = Get-GrimdexRole -GrimdexRoot $root -ComputerName 'HUBPC'
    Set-Content (Join-Path $root 'config' 'sync.json') -Value '{ "hub": "HUBPC" }'
    $r
}) -eq 'hub')
Assert 'other hostname -> spoke' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName 'LAPTOP') -eq 'spoke')
Assert 'empty ComputerName -> spoke (never false-positive hub)' ((Get-GrimdexRole -GrimdexRoot $root -ComputerName '') -eq 'spoke')
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

$outsideTarget = Join-Path $root 'outside.md'
Set-Content $outsideTarget -Value 'outside'
$traversalTarget = New-RuleSyncProposal -GrimdexRoot $root `
    -Target 'universal/claude-rules/../../outside.md' -Content 'overwrite' `
    -Machine 'ESCAPE' -Timestamp '2026-06-12T22:00:00-06:00'
Assert 'traversal-shaped rule target rejected' (-not (Test-RuleSyncProposal -GrimdexRoot $root -Path $traversalTarget).valid)

$threw = $false
try { Get-RuleSyncProposalPath -GrimdexRoot $root -Machine '../escape' | Out-Null } catch { $threw = $true }
Assert 'machine name cannot escape the promotions inbox' $threw

$empty = New-RuleSyncProposal -GrimdexRoot $root -Target 'GRIMDEX.md' `
    -Content '   ' -Machine 'DESK' -Timestamp '2026-06-12T22:00:00-06:00'
Assert 'empty content rejected' (-not (Test-RuleSyncProposal -GrimdexRoot $root -Path $empty).valid)

$noFm = Join-Path $root 'universal' 'promotions' 'junk.sync.md'
Set-Content $noFm -Value 'no frontmatter here'
$nf = Test-RuleSyncProposal -GrimdexRoot $root -Path $noFm
Assert 'no-frontmatter rejected, path preserved' (-not $nf.valid -and $nf.path -eq $noFm)

# ---------- pending enumeration ----------
$pending = @(Get-PendingRuleSyncProposals -GrimdexRoot $root)
Assert 'all *.sync.md enumerated' ($pending.Count -eq 6)
Assert 'mix of valid + invalid' (@($pending | Where-Object valid).Count -eq 1)
Get-ChildItem (Join-Path $root 'universal' 'promotions') -Filter '*.sync.md' | Remove-Item

# ---------- target traversal / symlink breakout (regression) ----------
$rulesDir = Join-Path $root 'universal' 'claude-rules'
Set-Content (Join-Path $rulesDir 'a.md') -Value 'rule a'
$secretIn  = Join-Path $root 'secret.md'
$outDir    = Join-Path ([IO.Path]::GetTempPath()) "grimdex-sync-out-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$secretOut = Join-Path $outDir 'secret.md'
Set-Content $secretIn -Value 'inside-root secret'
Set-Content $secretOut -Value 'outside-root secret'
$bad = @(
    'universal/claude-rules/../../secret.md', 'universal/claude-rules/../../../x/secret.md',
    'universal/claude-rules/./a.md', './GRIMDEX.md', '../GRIMDEX.md', '/etc/hosts', $secretOut,
    'universal\claude-rules\..\..\secret.md', 'universal\claude-rules\..\GRIMDEX.md',
    'C:\Windows\win.ini', 'universal/claude-rules/', 'universal/claude-rules/sub/a.md'
)
foreach ($t in $bad) {
    Assert "target rejected: $t" (-not (Test-RuleSyncTargetAllowed -GrimdexRoot $root -Target $t))
}
Assert 'normal rule target still allowed' (Test-RuleSyncTargetAllowed -GrimdexRoot $root -Target 'universal/claude-rules/a.md')
Assert 'GRIMDEX.md still allowed' (Test-RuleSyncTargetAllowed -GrimdexRoot $root -Target 'GRIMDEX.md')
if (-not $IsWindows) {
    # symlinked rule file -> outside
    New-Item -ItemType SymbolicLink -Path (Join-Path $rulesDir 'link.md') -Target $secretOut | Out-Null
    Assert 'symlinked rule file rejected' (-not (Test-RuleSyncTargetAllowed -GrimdexRoot $root -Target 'universal/claude-rules/link.md'))
    # symlinked rules dir -> outside
    $root2 = Join-Path ([IO.Path]::GetTempPath()) "grimdex-sync2-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path (Join-Path $root2 'universal') | Out-Null
    Set-Content (Join-Path $root2 'GRIMDEX.md') -Value '# Law'
    Set-Content (Join-Path $outDir 'b.md') -Value 'outside rule'
    New-Item -ItemType SymbolicLink -Path (Join-Path $root2 'universal' 'claude-rules') -Target $outDir | Out-Null
    Assert 'symlinked claude-rules dir rejected' (-not (Test-RuleSyncTargetAllowed -GrimdexRoot $root2 -Target 'universal/claude-rules/b.md'))
    # symlinked universal dir -> outside
    $root3 = Join-Path ([IO.Path]::GetTempPath()) "grimdex-sync3-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $root3 | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir 'claude-rules') | Out-Null
    Set-Content (Join-Path $outDir 'claude-rules' 'c.md') -Value 'outside rule c'
    New-Item -ItemType SymbolicLink -Path (Join-Path $root3 'universal') -Target $outDir | Out-Null
    Assert 'symlinked universal dir rejected' (-not (Test-RuleSyncTargetAllowed -GrimdexRoot $root3 -Target 'universal/claude-rules/c.md'))
    # write-time recheck: valid proposal, then the target is swapped for a symlink before approve
    $swap = New-RuleSyncProposal -GrimdexRoot $root -Target 'universal/claude-rules/a.md' `
        -Content 'attacker body' -Machine 'SWAP' -Timestamp '2026-06-12T22:00:00-06:00'
    Remove-Item (Join-Path $rulesDir 'a.md')
    New-Item -ItemType SymbolicLink -Path (Join-Path $rulesDir 'a.md') -Target $secretOut | Out-Null
    $threw = $false
    try { Approve-RuleSyncProposal -GrimdexRoot $root -Path $swap | Out-Null } catch { $threw = $true }
    Assert 'approve refuses a target swapped for a symlink' $threw
    Assert 'approve left the outside file untouched' ((Get-Content $secretOut -Raw).Trim() -eq 'outside-root secret')
    Remove-Item (Join-Path $rulesDir 'a.md'), (Join-Path $rulesDir 'link.md'), $swap
    Set-Content (Join-Path $rulesDir 'a.md') -Value 'rule a'
    # cleanup: drop the links first so nothing recurses outside the temp fixtures
    (Get-Item (Join-Path $root2 'universal' 'claude-rules') -Force).Delete()
    (Get-Item (Join-Path $root3 'universal') -Force).Delete()
    Remove-Item -Recurse $root2, $root3
}
Remove-Item -Recurse $outDir
Assert 'inside-root secret unchanged' ((Get-Content $secretIn -Raw).Trim() -eq 'inside-root secret')

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
