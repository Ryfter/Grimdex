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

$sandbox = Join-Path ([IO.Path]::GetTempPath()) "grimdex-setup-$(Get-Random)"
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

# --- Install-GrimdexRulesJunction ---
$rjRoot = Join-Path $sandbox 'grimdex-rules-junction'
New-FakeGrimdexRepo $rjRoot
$rjMirror = Join-Path $rjRoot 'universal' 'claude-rules'
New-Item -ItemType Directory -Force -Path $rjMirror | Out-Null
[IO.File]::WriteAllText((Join-Path $rjMirror 'a.md'), "rule A`r`nline two`r`n")  # CRLF, like a checkout
[IO.File]::WriteAllText((Join-Path $rjMirror 'b.md'), "rule B`n")

# missing live dir -> junction created
$rl = Join-Path $sandbox 'rules-live'
$r = Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl
Assert 'rules-junction: missing -> created' ($r.action -eq 'created' -and $null -eq $r.backup)
Assert 'rules-junction: rules readable through junction' ((Get-Content (Join-Path $rl 'a.md') -Raw).Contains('rule A'))

# linked -> no-op; Sync short-circuits
$r = Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl
Assert 'rules-junction: linked -> no-op' ($r.action -eq 'none')
$r = Sync-GrimdexRules -GrimdexRoot $rjRoot -RulesPath $rl
Assert 'rules-junction: sync reports linked, copies nothing' (@($r).Count -eq 1 -and @($r)[0].action -eq 'linked')
(Get-Item $rl -Force).Delete()

# real dir, EOL-only differences -> swapped, backup kept
New-Item -ItemType Directory -Path $rl | Out-Null
[IO.File]::WriteAllText((Join-Path $rl 'a.md'), "rule A`nline two`n")  # LF live copy
[IO.File]::WriteAllText((Join-Path $rl 'b.md'), "rule B`n")
$r = Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl
Assert 'rules-junction: matching real dir -> swapped' ($r.action -eq 'swapped')
Assert 'rules-junction: backup kept with content' ((Get-Content (Join-Path "$rl.bak" 'a.md') -Raw).Contains('rule A'))
Assert 'rules-junction: linked after swap' ((Get-GrimdexJunctionState -KnowledgePath $rl -Target $rjMirror) -eq 'linked')
(Get-Item $rl -Force).Delete(); Remove-Item -Recurse -Force "$rl.bak"

# diverged live file -> throws; -Force overrides
New-Item -ItemType Directory -Path $rl | Out-Null
[IO.File]::WriteAllText((Join-Path $rl 'a.md'), "locally edited`n")
$threw = $false
try { Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl | Out-Null } catch { $threw = $true }
Assert 'rules-junction: diverged -> throws' $threw
Assert 'rules-junction: diverged -> live dir untouched' ((Get-GrimdexJunctionState -KnowledgePath $rl -Target $rjMirror) -eq 'real-dir')
$r = Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl -Force
Assert 'rules-junction: diverged + -Force -> swapped' ($r.action -eq 'swapped')
(Get-Item $rl -Force).Delete(); Remove-Item -Recurse -Force "$rl.bak"

# live-only file (no mirror counterpart) -> throws
New-Item -ItemType Directory -Path $rl | Out-Null
[IO.File]::WriteAllText((Join-Path $rl 'orphan.md'), "only live`n")
$threw = $false
try { Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl | Out-Null } catch { $threw = $true }
Assert 'rules-junction: live-only file -> throws' $threw
Remove-Item -Recurse -Force $rl

# existing .bak -> throws even with -Force
New-Item -ItemType Directory -Path $rl | Out-Null
New-Item -ItemType Directory -Path "$rl.bak" | Out-Null
$threw = $false
try { Install-GrimdexRulesJunction -GrimdexRoot $rjRoot -RulesPath $rl -Force | Out-Null } catch { $threw = $true }
Assert 'rules-junction: existing .bak -> throws even with -Force' $threw
Remove-Item -Recurse -Force $rl, "$rl.bak"

# missing mirror dir -> throws
$threw = $false
try { Install-GrimdexRulesJunction -GrimdexRoot $target -RulesPath (Join-Path $sandbox 'rules-x') | Out-Null } catch { $threw = $true }
Assert 'rules-junction: missing mirror -> throws' $threw

# --- invalid target -> throws ---
$threw = $false
try { Install-GrimdexJunction -KnowledgePath (Join-Path $sandbox 'x') -Target $sandbox | Out-Null } catch { $threw = $true }
Assert 'invalid target -> throws' $threw

# --- Operator network profile ---
$onRoot = Join-Path $sandbox 'operator-network-root'
New-FakeGrimdexRepo $onRoot
$onPath = Get-OperatorNetworkConfigPath -GrimdexRoot $onRoot
Assert 'operator-network: missing path' (-not (Test-Path $onPath))

$cfg = New-OperatorNetworkConfig -OperatorBrowserOnServer $false -LanHostname 'dev-box' `
    -TailnetEnabled $true -TailnetHostname 'dev-box' -MagicDnsSuffix 'example.ts.net'
Save-OperatorNetworkConfig -GrimdexRoot $onRoot -Config $cfg | Out-Null
$loaded = Get-OperatorNetworkConfig -GrimdexRoot $onRoot
Assert 'operator-network: roundtrip mode' ($loaded.mode -eq 'lan+tailnet')
Assert 'operator-network: roundtrip lan hostname' ($loaded.announce.home_lan.hostname -eq 'dev-box')
Assert 'operator-network: localhost-only mode' (
    (New-OperatorNetworkConfig -OperatorBrowserOnServer $true).mode -eq 'localhost-only'
)

$skip = Initialize-OperatorNetworkConfig -GrimdexRoot $onRoot -NonInteractive
Assert 'operator-network: existing -> exists' ($skip.action -eq 'exists')

$fresh = Join-Path $sandbox 'operator-network-fresh'
New-FakeGrimdexRepo $fresh
$skip2 = Initialize-OperatorNetworkConfig -GrimdexRoot $fresh -NonInteractive
Assert 'operator-network: missing + non-interactive -> skipped' ($skip2.action -eq 'skipped')

# cleanup (delete junctions as links, then the sandbox)
foreach ($p in $kp, $kp2, $kp3, $kp4) {
    if ((Test-Path $p) -and (Get-Item $p -Force).LinkType -in 'Junction', 'SymbolicLink') { (Get-Item $p -Force).Delete() }
}
# --- Initialize-GrimdexExampleConfigs (seeded operator examples, spec 2026-09-28) ---
$ex = Join-Path $sandbox 'ex-root'
New-Item -ItemType Directory -Force -Path (Join-Path $ex 'config'), (Join-Path $ex 'examples' 'operator-setup') | Out-Null
Set-Content (Join-Path $ex 'config' 'fleet.example.json') '{"plain":true}'
Set-Content (Join-Path $ex 'config' 'quota.example.json') '{"plain":true}'
Set-Content (Join-Path $ex 'config' 'sync.example.json') '{"plain":true}'
Set-Content (Join-Path $ex 'examples' 'operator-setup' 'fleet.json') '{"operator":true}'
Set-Content (Join-Path $ex 'config' 'sync.json') '{"mine":true}'
Set-Content (Join-Path $ex 'config' 'publish-scrub.example.json') '{}'
Set-Content (Join-Path $ex 'config' 'grimdex-mode.example.json') '{}'
$r = @(Initialize-GrimdexExampleConfigs -GrimdexRoot $ex -Choice operator)
function ExRow($n) { $r | Where-Object name -eq $n }
Assert 'examples: operator copy used when present' ((ExRow 'fleet.json').action -eq 'copied-operator' -and (Get-Content (Join-Path $ex 'config' 'fleet.json') -Raw) -match 'operator')
Assert 'examples: plain fallback when no operator example' ((ExRow 'quota.json').action -eq 'copied-plain')
Assert 'examples: existing config never overwritten' ((ExRow 'sync.json').action -eq 'exists' -and (Get-Content (Join-Path $ex 'config' 'sync.json') -Raw) -match 'mine')
Assert 'examples: scrub + mode configs never seeded' (-not (ExRow 'publish-scrub.json') -and -not (ExRow 'grimdex-mode.json') -and -not (Test-Path (Join-Path $ex 'config' 'publish-scrub.json')))
Remove-Item (Join-Path $ex 'config' 'fleet.json'), (Join-Path $ex 'config' 'quota.json')
$r = @(Initialize-GrimdexExampleConfigs -GrimdexRoot $ex -Choice plain)
Assert 'examples: plain choice ignores operator example' ((ExRow 'fleet.json').action -eq 'copied-plain' -and (Get-Content (Join-Path $ex 'config' 'fleet.json') -Raw) -match 'plain')
Remove-Item (Join-Path $ex 'config' 'fleet.json'), (Join-Path $ex 'config' 'quota.json')
$r = @(Initialize-GrimdexExampleConfigs -GrimdexRoot $ex -NonInteractive)
Assert 'examples: non-interactive without choice skips' ((ExRow 'fleet.json').action -eq 'skipped' -and -not (Test-Path (Join-Path $ex 'config' 'fleet.json')))
$r = @(Initialize-GrimdexExampleConfigs -GrimdexRoot (Join-Path $sandbox 'no-such'))
Assert 'examples: no config dir -> nothing to do' ($r.Count -eq 0)

Remove-Item -Recurse -Force $sandbox
if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll setup-lib tests passed." -ForegroundColor Green
