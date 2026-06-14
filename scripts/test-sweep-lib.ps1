#!/usr/bin/env pwsh
# Tests for scripts/sweep-lib.ps1 — fixtures in temp dirs, no network.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sweep-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

# ---------- fixture: a clean mini-KB (git repo with upstream) ----------
$sandbox = Join-Path $env:TEMP "grimdex-sweep-$(Get-Random)"
$bare = Join-Path $sandbox 'origin.git'
$kb = Join-Path $sandbox 'kb'
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
git init -q --bare $bare
git -C $bare symbolic-ref HEAD refs/heads/main
git init -q -b main $kb
git -C $kb remote add origin $bare
function Commit-Kb($msg) {
    git -C $kb add -A
    git -C $kb -c user.email=t@t -c user.name=t commit -q -m $msg
}
New-Item -ItemType Directory -Force -Path (Join-Path $kb 'universal' 'promotions'), (Join-Path $kb 'projects' 'p1' 'decisions') | Out-Null
Set-Content (Join-Path $kb 'GRIMDEX.md') -Value "# Law`n`nSee [README](README.md)."
Set-Content (Join-Path $kb 'README.md') -Value '# readme'
Set-Content (Join-Path $kb 'universal' 'promotions' 'README.md') -Value '# inbox'
Set-Content (Join-Path $kb 'projects' 'p1' 'decisions' 'd001-first.md') -Value '# d001'
Set-Content (Join-Path $kb 'projects' 'p1' 'decisions' 'd002-second.md') -Value "# d002`nSee [[d001-first]]."
Commit-Kb 'init'
git -C $kb push -q -u origin main

# ---------- clean KB -> zero findings ----------
$findings = @(Invoke-GrimdexMechanicalChecks -GrimdexRoot $kb)
Assert 'clean KB -> zero findings' ($findings.Count -eq 0)
Assert 'clean KB -> empty inbox' (@(Get-GrimdexInboxStatus -GrimdexRoot $kb).Count -eq 0)

# ---------- inbox detection + staleness ----------
$cand = Join-Path $kb 'universal' 'promotions' 'p1.md'
Set-Content $cand -Value "## A rule`n**Proposed rule:** x`n**Filed:** $((Get-Date).ToString('yyyy-MM-dd'))"
$inbox = @(Get-GrimdexInboxStatus -GrimdexRoot $kb)
Assert 'fresh candidate detected' ($inbox.Count -eq 1 -and $inbox[0].candidates -eq 1 -and $inbox[0].project -eq 'p1')
Assert 'fresh candidate not stale' (@(Test-GrimdexInboxStaleness -GrimdexRoot $kb).Count -eq 0)
Set-Content $cand -Value "## Old rule`n**Filed:** 2026-05-01`n## New rule`n**Filed:** $((Get-Date).ToString('yyyy-MM-dd'))"
$inbox = @(Get-GrimdexInboxStatus -GrimdexRoot $kb)
Assert 'two candidates counted' ($inbox[0].candidates -eq 2)
Assert 'oldest Filed date wins' ($inbox[0].oldestDays -gt 7)
$stale = @(Test-GrimdexInboxStaleness -GrimdexRoot $kb)
Assert 'stale candidate -> warn' ($stale.Count -eq 1 -and $stale[0].severity -eq 'warn')
Assert 'README is not a candidate file' (-not ($inbox | Where-Object project -eq 'README'))
Remove-Item $cand

# ---------- *.sync.md is NOT a promotion candidate ----------
Set-Content (Join-Path $kb 'universal' 'promotions' 'laptop.sync.md') `
    -Value "---`nkind: rule-sync`n---`n## not a candidate heading"
Assert 'rule-sync file excluded from inbox status' (@(Get-GrimdexInboxStatus -GrimdexRoot $kb).Count -eq 0)
Remove-Item (Join-Path $kb 'universal' 'promotions' 'laptop.sync.md')

# ---------- dead links ----------
Set-Content (Join-Path $kb 'projects' 'p1' 'notes.md') -Value "[gone](missing-file.md) and [ok](../../README.md) and [web](https://x.test) and [anchor](#sec)"
$f = @(Test-GrimdexLinks -GrimdexRoot $kb)
Assert 'dead relative link -> 1 warn' ($f.Count -eq 1 -and $f[0].severity -eq 'warn' -and $f[0].message.Contains('missing-file.md'))
Set-Content (Join-Path $kb 'projects' 'p1' 'notes.md') -Value "[root-relative](GRIMDEX.md)"
Assert 'root-relative link resolves' (@(Test-GrimdexLinks -GrimdexRoot $kb).Count -eq 0)
Remove-Item (Join-Path $kb 'projects' 'p1' 'notes.md')

# ---------- wikilinks ----------
Set-Content (Join-Path $kb 'projects' 'p1' 'wl.md') -Value @"
Resolves: [[d001-first]]
Partial resolves: [[d001]]
Dangling: [[no_such_entity]]
Intentional: [[future_thing]] <!-- forward-ref -->
"@
$f = @(Test-GrimdexWikilinks -GrimdexRoot $kb)
Assert 'only true dangling flagged' ($f.Count -eq 1 -and $f[0].message.Contains('no_such_entity'))
Assert 'dangling wikilink is info severity' ($f[0].severity -eq 'info')
Remove-Item (Join-Path $kb 'projects' 'p1' 'wl.md')

# ---------- decision ids ----------
Set-Content (Join-Path $kb 'projects' 'p1' 'decisions' 'd002-dupe.md') -Value '# dupe'
$f = @(Test-GrimdexDecisionIds -GrimdexRoot $kb)
Assert 'duplicate id -> warn' (@($f | Where-Object { $_.severity -eq 'warn' -and $_.message.Contains('d002') }).Count -eq 1)
Remove-Item (Join-Path $kb 'projects' 'p1' 'decisions' 'd002-dupe.md')
Set-Content (Join-Path $kb 'projects' 'p1' 'decisions' 'd004-gapped.md') -Value '# d004'
$f = @(Test-GrimdexDecisionIds -GrimdexRoot $kb)
Assert 'gap -> info naming the missing id' (@($f | Where-Object { $_.severity -eq 'info' -and $_.message.Contains('d003') }).Count -eq 1)
Remove-Item (Join-Path $kb 'projects' 'p1' 'decisions' 'd004-gapped.md')

# ---------- repo state ----------
Set-Content (Join-Path $kb 'dirty.md') -Value 'x'
$f = @(Test-GrimdexRepoState -GrimdexRoot $kb)
Assert 'dirty tree -> warn' (@($f | Where-Object message -like '*uncommitted*').Count -eq 1)
Commit-Kb 'dirt'
$f = @(Test-GrimdexRepoState -GrimdexRoot $kb)
Assert 'unpushed commit -> warn' (@($f | Where-Object message -like '*unpushed*').Count -eq 1)
git -C $kb push -q
Assert 'clean+pushed -> no repo findings' (@(Test-GrimdexRepoState -GrimdexRoot $kb).Count -eq 0)

# ---------- Sync-GrimdexRepo (incl. push race) ----------
$kb2 = Join-Path $sandbox 'kb2'
git clone -q $bare $kb2
Set-Content (Join-Path $kb2 'other.md') -Value 'remote work'
git -C $kb2 add -A; git -C $kb2 -c user.email=t@t -c user.name=t commit -q -m other; git -C $kb2 push -q
Set-Content (Join-Path $kb 'local.md') -Value 'local work'
Commit-Kb 'local'
$r = Sync-GrimdexRepo -GrimdexRoot $kb
Assert 'race: rebase + push succeeds' ($r.pushed)
Assert 'race: remote commit present locally' (Test-Path (Join-Path $kb 'other.md'))
Assert 'race: nothing left unpushed' ((git -C $kb rev-list --count '@{u}..HEAD') -eq '0')
$r = Sync-GrimdexRepo -GrimdexRoot $kb -SkipPush
Assert 'SkipPush pulls without pushing' ($r.pulled -and -not $r.pushed)

# ---------- Add-GrimdexLogEntry (newest on top) ----------
$log = Join-Path $kb 'TEST-LOG.md'
Set-Content $log -Value "# Log`n`nintro text`n`n<!-- grimdex:log-top -->`n`n## 2026-06-01 — older entry`nold"
Add-GrimdexLogEntry -LogPath $log -Entry "## 2026-06-10 — newer entry`nnew"
$content = Get-Content $log -Raw
Assert 'new entry above old entry' ($content.IndexOf('newer entry') -lt $content.IndexOf('older entry'))
Assert 'marker still present once' (([regex]::Matches($content, [regex]::Escape('<!-- grimdex:log-top -->'))).Count -eq 1)
Assert 'intro preserved above marker' ($content.IndexOf('intro text') -lt $content.IndexOf('<!-- grimdex:log-top -->'))
$threw = $false
Set-Content (Join-Path $kb 'NOMARK.md') -Value '# no marker'
try { Add-GrimdexLogEntry -LogPath (Join-Path $kb 'NOMARK.md') -Entry 'x' } catch { $threw = $true }
Assert 'missing marker -> throws' $threw

# ---------- Sync-GrimdexRepo -Autostash tolerates a dirty tree ----------
Set-Content (Join-Path $kb 'dirty.txt') -Value 'uncommitted'
$r = Sync-GrimdexRepo -GrimdexRoot $kb -SkipPush -Autostash
Assert 'autostash pull succeeds over dirty tree' ($r.pulled)
Assert 'dirty file restored after autostash' (Test-Path (Join-Path $kb 'dirty.txt'))
Remove-Item (Join-Path $kb 'dirty.txt')

Remove-Item -Recurse -Force $sandbox
if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll sweep-lib tests passed." -ForegroundColor Green
