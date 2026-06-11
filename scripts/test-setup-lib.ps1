#!/usr/bin/env pwsh
# Tests for scripts/setup-lib.ps1 — junction state + safe swap, all against temp dirs.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'setup-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}
function New-FakeGrimdexRepo($path) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    git -C $path init -q -b main
    Set-Content -Path (Join-Path $path 'GRIMDEX.md') -Value '# Grimdex'
    git -C $path add -A
    git -C $path -c user.email=t@t -c user.name=t commit -q -m init
}

$sandbox = Join-Path $env:TEMP "grimdex-setup-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
$target = Join-Path $sandbox 'target'
New-FakeGrimdexRepo $target

# --- Test-GrimdexRoot ---
Assert 'valid root accepted' (Test-GrimdexRoot -Root $target)
Assert 'plain dir rejected' (-not (Test-GrimdexRoot -Root $sandbox))

# --- Get-GrimdexJunctionState ---
$kp = Join-Path $sandbox 'knowledge'
Assert 'state: missing' ((Get-GrimdexJunctionState -KnowledgePath $kp -Target $target) -eq 'missing')
New-Item -ItemType Directory -Path $kp | Out-Null
Assert 'state: real-dir' ((Get-GrimdexJunctionState -KnowledgePath $kp -Target $target) -eq 'real-dir')
Remove-Item $kp

# --- Install on missing path -> junction created, no backup ---
$r = Install-GrimdexJunction -KnowledgePath $kp -Target $target
Assert 'missing -> created' ($r.action -eq 'created' -and $null -eq $r.backup)
Assert 'state: linked' ((Get-GrimdexJunctionState -KnowledgePath $kp -Target $target) -eq 'linked')
Assert 'reads through junction' (Test-Path (Join-Path $kp 'GRIMDEX.md'))

# --- Re-run on linked -> no-op ---
$r = Install-GrimdexJunction -KnowledgePath $kp -Target $target
Assert 'linked -> no-op' ($r.action -eq 'none')

# --- linked-elsewhere -> throws ---
$other = Join-Path $sandbox 'other-target'
New-FakeGrimdexRepo $other
Assert 'state: linked-elsewhere' ((Get-GrimdexJunctionState -KnowledgePath $kp -Target $other) -eq 'linked-elsewhere')
$threw = $false
try { Install-GrimdexJunction -KnowledgePath $kp -Target $other | Out-Null } catch { $threw = $true }
Assert 'linked-elsewhere -> throws' $threw
(Get-Item $kp -Force).Delete()

# --- real-dir, clean, same HEAD -> swapped with backup kept ---
$kp2 = Join-Path $sandbox 'knowledge2'
git clone -q $target $kp2
$r = Install-GrimdexJunction -KnowledgePath $kp2 -Target $target
Assert 'clean same-HEAD -> swapped' ($r.action -eq 'swapped')
Assert 'backup kept' (Test-Path "$kp2.bak" -PathType Container)
Assert 'backup still has content' (Test-Path (Join-Path "$kp2.bak" 'GRIMDEX.md'))
Assert 'junction live after swap' ((Get-GrimdexJunctionState -KnowledgePath $kp2 -Target $target) -eq 'linked')

# --- backup already exists -> throws before touching anything ---
$kp3 = Join-Path $sandbox 'knowledge3'
git clone -q $target $kp3
New-Item -ItemType Directory -Path "$kp3.bak" | Out-Null
$threw = $false
try { Install-GrimdexJunction -KnowledgePath $kp3 -Target $target | Out-Null } catch { $threw = $true }
Assert 'existing .bak -> throws' $threw
Assert 'existing .bak -> source untouched (still real dir)' ((Get-GrimdexJunctionState -KnowledgePath $kp3 -Target $target) -eq 'real-dir')
Remove-Item -Recurse -Force "$kp3.bak"

# --- dirty tree -> throws, even with -Force ---
Set-Content -Path (Join-Path $kp3 'dirty.md') -Value 'uncommitted'
$threw = $false
try { Install-GrimdexJunction -KnowledgePath $kp3 -Target $target -Force | Out-Null } catch { $threw = $true }
Assert 'dirty tree -> throws even with -Force' $threw
Remove-Item (Join-Path $kp3 'dirty.md')

# --- HEAD mismatch -> throws without -Force, swaps with -Force ---
Set-Content -Path (Join-Path $target 'extra.md') -Value 'ahead'
git -C $target add -A
git -C $target -c user.email=t@t -c user.name=t commit -q -m ahead
$threw = $false
try { Install-GrimdexJunction -KnowledgePath $kp3 -Target $target | Out-Null } catch { $threw = $true }
Assert 'HEAD mismatch -> throws' $threw
$r = Install-GrimdexJunction -KnowledgePath $kp3 -Target $target -Force
Assert 'HEAD mismatch + -Force -> swapped' ($r.action -eq 'swapped')

# --- non-git real dir -> throws without -Force ---
$kp4 = Join-Path $sandbox 'knowledge4'
New-Item -ItemType Directory -Path $kp4 | Out-Null
Set-Content -Path (Join-Path $kp4 'loose.md') -Value 'x'
$threw = $false
try { Install-GrimdexJunction -KnowledgePath $kp4 -Target $target | Out-Null } catch { $threw = $true }
Assert 'non-git dir -> throws without -Force' $threw
$r = Install-GrimdexJunction -KnowledgePath $kp4 -Target $target -Force
Assert 'non-git dir + -Force -> swapped, backup kept' ($r.action -eq 'swapped' -and (Test-Path (Join-Path "$kp4.bak" 'loose.md')))

# --- Sync-GrimdexRules ---
$rulesRoot = Join-Path $sandbox 'grimdex-with-rules'
$mirror = Join-Path $rulesRoot 'universal' 'claude-rules'
New-Item -ItemType Directory -Force -Path $mirror | Out-Null
Set-Content -Path (Join-Path $mirror 'a.md') -Value 'rule A'
Set-Content -Path (Join-Path $mirror 'b.md') -Value 'rule B'
$liveRules = Join-Path $sandbox 'live-rules'

$r = Sync-GrimdexRules -GrimdexRoot $rulesRoot -RulesPath $liveRules
Assert 'missing live rules -> deployed' (-not ($r | Where-Object action -ne 'deployed') -and $r.Count -eq 2)
Assert 'rules dir auto-created with content' ((Get-Content (Join-Path $liveRules 'a.md') -Raw).Contains('rule A'))

$r = Sync-GrimdexRules -GrimdexRoot $rulesRoot -RulesPath $liveRules
Assert 'identical -> unchanged' (-not ($r | Where-Object action -ne 'unchanged'))

[IO.File]::WriteAllText((Join-Path $mirror 'a.md'), "rule A`r`nline two`r`n")
[IO.File]::WriteAllText((Join-Path $liveRules 'a.md'), "rule A`nline two`n")
$r = Sync-GrimdexRules -GrimdexRoot $rulesRoot -RulesPath $liveRules
Assert 'EOL-only difference -> unchanged' (($r | Where-Object rule -eq 'a.md').action -eq 'unchanged')

Set-Content -Path (Join-Path $liveRules 'b.md') -Value 'locally edited'
$r = Sync-GrimdexRules -GrimdexRoot $rulesRoot -RulesPath $liveRules
Assert 'diverged live rule -> conflict-skipped' (($r | Where-Object rule -eq 'b.md').action -eq 'conflict-skipped')
Assert 'conflict leaves live file alone' ((Get-Content (Join-Path $liveRules 'b.md') -Raw).Contains('locally edited'))

$r = Sync-GrimdexRules -GrimdexRoot $rulesRoot -RulesPath $liveRules -Force
Assert 'conflict + -Force -> overwritten' (($r | Where-Object rule -eq 'b.md').action -eq 'overwritten')
Assert 'overwrite restores mirror content' ((Get-Content (Join-Path $liveRules 'b.md') -Raw).Contains('rule B'))

$r = Sync-GrimdexRules -GrimdexRoot $sandbox -RulesPath $liveRules
Assert 'no mirror dir -> empty result' (@($r).Count -eq 0)

# --- invalid target -> throws ---
$threw = $false
try { Install-GrimdexJunction -KnowledgePath (Join-Path $sandbox 'x') -Target $sandbox | Out-Null } catch { $threw = $true }
Assert 'invalid target -> throws' $threw

# cleanup (delete junctions as links, then the sandbox)
foreach ($p in $kp, $kp2, $kp3, $kp4) {
    if ((Test-Path $p) -and (Get-Item $p -Force).LinkType -eq 'Junction') { (Get-Item $p -Force).Delete() }
}
Remove-Item -Recurse -Force $sandbox
if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll setup-lib tests passed." -ForegroundColor Green
