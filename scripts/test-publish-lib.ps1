#!/usr/bin/env pwsh
# Tests for scripts/publish-lib.ps1 — engine mirror plan/apply + pre-push leak gate,
# all against temp git repos.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'publish-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}
function Write-File($root, $rel, $text) {
    $p = Join-Path $root $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
    [IO.File]::WriteAllText($p, $text, [Text.UTF8Encoding]::new($false))
}
function Commit-All($root) {
    git -C $root add -A 2>$null | Out-Null
    git -C $root -c user.email=t@example.com -c user.name=t commit -q -m c --allow-empty | Out-Null
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) "grimdex-publish-$(Get-Random)"
$src = Join-Path $sandbox 'src'
$eng = Join-Path $sandbox 'engine'
foreach ($r in $src, $eng) { New-Item -ItemType Directory -Force -Path $r | Out-Null; git -C $r init -q -b main }

Write-File $src 'config/publish-scrub.json' '{ "replacements": [ { "find": "bighost", "replace": "<hub-host>" } ], "deny": ["secretproj"], "allow": [] }'
Write-File $src 'config/engine-manifest.json' (@{
    sync         = @('scripts/*.ps1', 'docs/guide.md', 'config/publish-scrub.json')
    engine_owned = @('README.md')
    examples     = @{ 'config/fleet.json' = 'examples/operator-setup/fleet.json' }
    never        = @('config/publish-scrub.json', 'config/fleet.json')
} | ConvertTo-Json -Depth 5)
Write-File $src 'scripts/a.ps1' "# runs on bighost`n"
Write-File $src 'scripts/b.ps1' "# unchanged`n"
Write-File $src 'docs/guide.md' "clean guide`n"
Write-File $src 'config/fleet.json' '{ "hub": "bighost" }'
Write-File $src 'README.md' "private readme`n"
Commit-All $src

Write-File $eng 'README.md' "engine readme`n"
Write-File $eng 'scripts/b.ps1' "# unchanged`n"
Commit-All $eng

$cfg = Get-GrimdexScrubConfig -GrimdexRoot $src
$man = Get-GrimdexEngineManifest -GrimdexRoot $src
Assert 'manifest loads sync list' (@($man.sync).Count -eq 3)

$plan = Get-GrimdexPublishPlan -GrimdexRoot $src -EngineRoot $eng -Config $cfg -Manifest $man
function Item($dest) { $plan.items | Where-Object dest -eq $dest }
Assert 'new file planned'        ((Item 'scripts/a.ps1').action -eq 'new')
Assert 'scrubbed content'        ((Item 'scripts/a.ps1').content -eq "# runs on <hub-host>`n")
Assert 'unchanged detected'      ((Item 'scripts/b.ps1').action -eq 'unchanged')
Assert 'never-listed sync refused' ((Item 'config/publish-scrub.json').action -eq 'refused')
Assert 'owned file reported'     ((Item 'README.md').action -eq 'owned')
Assert 'example planned'         ((Item 'examples/operator-setup/fleet.json').action -eq 'new')
Assert 'example scrubbed'        ((Item 'examples/operator-setup/fleet.json').content -match '<hub-host>')
Assert 'clean plan has no leaks' (@($plan.leaks).Count -eq 0)
Assert 'dry-run wrote nothing'   (-not (Test-Path (Join-Path $eng 'scripts/a.ps1')))

$written = Invoke-GrimdexPublish -Plan $plan -EngineRoot $eng
Assert 'apply writes new+changed only' (@($written).Count -eq 3)
Assert 'apply wrote scrubbed file' ((Get-Content (Join-Path $eng 'scripts/a.ps1') -Raw) -eq "# runs on <hub-host>`n")
Assert 'owned file untouched'    ((Get-Content (Join-Path $eng 'README.md') -Raw) -eq "engine readme`n")
Assert 'refused file not written' (-not (Test-Path (Join-Path $eng 'config/publish-scrub.json')))

# a leak the scrubber cannot fix lands in leaks
Write-File $src 'docs/guide.md' "see secretproj`n"
$plan2 = Get-GrimdexPublishPlan -GrimdexRoot $src -EngineRoot $eng -Config $cfg -Manifest $man
Assert 'unfixable leak reported' (@($plan2.leaks | Where-Object { $_.path -eq 'docs/guide.md' -and $_.kind -eq 'deny' }).Count -eq 1)

# engine-side leak in an owned file is found by the plan and by the tree scan
Write-File $eng 'README.md' "contact a@b.com`n"  # grimdex:scrub-ok:email
Commit-All $eng
$plan3 = Get-GrimdexPublishPlan -GrimdexRoot $src -EngineRoot $eng -Config $cfg -Manifest $man
Assert 'owned-file leak in plan' (@($plan3.leaks | Where-Object path -eq 'README.md').Count -eq 1)
Assert 'tree scan finds leak'    (@(Find-GrimdexTreeLeaks -Root $eng -Config $cfg | Where-Object path -eq 'README.md').Count -eq 1)

# the plan sees uncommitted engine edits; the pre-push (Head) scan sees only commits
Write-File $eng 'README.md' "fixed`n"
$plan4 = Get-GrimdexPublishPlan -GrimdexRoot $src -EngineRoot $eng -Config $cfg -Manifest $man
Assert 'plan reads working tree'  (@($plan4.leaks | Where-Object path -eq 'README.md').Count -eq 0)
Assert 'head scan reads commits'  (@(Find-GrimdexTreeLeaks -Root $eng -Config $cfg | Where-Object path -eq 'README.md').Count -eq 1)
Write-File $eng 'README.md' "contact a@b.com`n"  # grimdex:scrub-ok:email

# binary files are skipped by the tree scan
[IO.File]::WriteAllBytes((Join-Path $eng 'img.png'), [byte[]](0x89, 0x00) + [Text.Encoding]::ASCII.GetBytes('x@y.org'))  # grimdex:scrub-ok:email
Commit-All $eng
Assert 'binary skipped'          (@(Find-GrimdexTreeLeaks -Root $eng -Config $cfg | Where-Object path -eq 'img.png').Count -eq 0)

# missing engine root throws
$threw = $false; try { Get-GrimdexPublishPlan -GrimdexRoot $src -EngineRoot (Join-Path $sandbox 'nope') -Config $cfg -Manifest $man | Out-Null } catch { $threw = $true }
Assert 'missing engine root throws' $threw

# --- pre-push hook: scans every pushed commit (messages + added lines) and the pushed tip ---
function New-HookRepo($name) {
    $r = Join-Path $sandbox $name
    New-Item -ItemType Directory -Force -Path $r | Out-Null
    git -C $r init -q -b main
    $bare = Join-Path $sandbox "$name.git"
    git init -q --bare $bare
    git -C $r remote add origin $bare
    Install-GrimdexEnginePrePush -EngineRoot $r -GrimdexRoot $src -ScriptRoot $PSScriptRoot | Out-Null
    Write-File $r 'README.md' "clean`n"
    Commit-All $r
    return $r
}
$leakText = 'contact ' + 'alice' + '@corp.io'

$h1 = New-HookRepo 'hook-clean'
Assert 'hook installed' (Test-Path (Join-Path $h1 '.git' 'hooks' 'pre-push'))
git -C $h1 push -q origin main 2>$null
Assert 'hook passes clean push' ($LASTEXITCODE -eq 0)

$h2 = New-HookRepo 'hook-tip'
Write-File $h2 'README.md' "$leakText`n"
Commit-All $h2
git -C $h2 push -q origin main 2>$null
Assert 'hook blocks leak in pushed tip' ($LASTEXITCODE -ne 0)

$h3 = New-HookRepo 'hook-history'
git -C $h3 push -q origin main 2>$null
Write-File $h3 'notes.md' "$leakText`n"; Commit-All $h3
Remove-Item (Join-Path $h3 'notes.md'); Commit-All $h3
git -C $h3 push -q origin main 2>$null
Assert 'hook blocks leak added then deleted' ($LASTEXITCODE -ne 0)

$h4 = New-HookRepo 'hook-branch'
git -C $h4 push -q origin main 2>$null
git -C $h4 checkout -q -b side
Write-File $h4 'side.md' "$leakText`n"; Commit-All $h4
git -C $h4 checkout -q main
git -C $h4 push -q origin side 2>$null
Assert 'hook scans the pushed branch, not the checked-out one' ($LASTEXITCODE -ne 0)

$h5 = New-HookRepo 'hook-message'
git -C $h5 push -q origin main 2>$null
Write-File $h5 'x.md' "fine`n"
git -C $h5 add -A | Out-Null
git -C $h5 -c user.email=t@example.com -c user.name=t commit -q -m "thanks $leakText" | Out-Null
git -C $h5 push -q origin main 2>$null
Assert 'hook blocks a leak in a commit message' ($LASTEXITCODE -ne 0)

Remove-Item -Recurse -Force $sandbox

if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll publish-lib tests passed." -ForegroundColor Green
