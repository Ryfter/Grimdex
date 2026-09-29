#!/usr/bin/env pwsh
# Tests for scripts/wire-lib.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wire-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}

# Cross-platform fixtures. Absolute paths here are only ever passed as
# -GrimdexPath values; they are never touched on disk, so they must be legal on
# every OS (a 'D:\...' literal makes Join-Path throw on macOS/Linux).
$tempRoot = [System.IO.Path]::GetTempPath()
$pathA = Join-Path $tempRoot 'grimdex-a'
$pathB = Join-Path $tempRoot 'grimdex-b'

# --- Get-GrimdexStanza ---
$stanza = Get-GrimdexStanza -GrimdexPath $pathA -ProjectId 'my-proj'
Assert 'stanza has start marker' ($stanza.StartsWith('<!-- grimdex:start -->'))
Assert 'stanza has end marker' ($stanza.EndsWith('<!-- grimdex:end -->'))
Assert 'stanza names the cross-platform link' ($stanza.Contains('~/.claude/knowledge'))
Assert 'stanza names the project tier' ($stanza.Contains('projects/my-proj/'))
Assert 'stanza points at GRIMDEX.md' ($stanza.Contains('GRIMDEX.md'))
Assert 'stanza carries the contribution rule' ($stanza.Contains('PROGRAMMING DECISIONS'))
Assert 'stanza carries the public engine URL' ($stanza.Contains('https://github.com/Ryfter/Grimdex'))
Assert 'stanza tells you how to create the link' ($stanza.Contains('-CreateJunction'))

# The whole point of the neutral stanza: the machine's own checkout path must
# NOT leak into the block, or committed agent files churn between boxes.
Assert 'stanza omits the machine-specific checkout path' (-not $stanza.Contains($pathA))
$stanzaB = Get-GrimdexStanza -GrimdexPath $pathB -ProjectId 'my-proj'
Assert 'stanza is identical regardless of checkout path' ($stanza -eq $stanzaB)

# --- Set-GrimdexBlock: pure behaviors ---
$r = Set-GrimdexBlock -Content '' -Stanza $stanza
Assert 'empty content -> stanza only' ($r.TrimEnd() -eq $stanza)

$r = Set-GrimdexBlock -Content "# Existing doc`n`nSome rules.`n" -Stanza $stanza
Assert 'no markers -> appended' ($r.StartsWith('# Existing doc') -and $r.Contains($stanza))
Assert 'append preserves prior content' ($r.Contains('Some rules.'))

$old = "# Doc`n`n<!-- grimdex:start -->`nOLD STANZA`n<!-- grimdex:end -->`n`n## After`n"
$r = Set-GrimdexBlock -Content $old -Stanza $stanza
Assert 'markers -> replaced in place' ($r.Contains($stanza) -and -not $r.Contains('OLD STANZA'))
Assert 'replace preserves surrounding content' ($r.StartsWith('# Doc') -and $r.Contains('## After'))

$twice = Set-GrimdexBlock -Content $r -Stanza $stanza
Assert 'idempotent (second run = no change)' ($twice -eq $r)

# Regression: the MatchEvaluator in Set-GrimdexBlock must not perform
# $-substitution on the replacement text. The path no longer reaches the stanza,
# so the project id is now the carrier for a literal '$'.
$dollarStanza = Get-GrimdexStanza -GrimdexPath $pathA -ProjectId 'odd$id'
$r = Set-GrimdexBlock -Content $old -Stanza $dollarStanza
Assert 'dollar sign in stanza survives replacement' ($r.Contains('projects/odd$id/'))

# --- Install-GrimdexPointers against a temp project ---
$tmp = Join-Path $tempRoot "grimdex-wire-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Set-Content -Path (Join-Path $tmp 'CLAUDE.md') -Value "# My project`n`nHouse rules.`n" -NoNewline

$results = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath $pathA
Assert 'six target files reported' ($results.Count -eq 6)
Assert 'CLAUDE.md appended' (($results | Where-Object file -like '*CLAUDE.md').action -eq 'appended')
Assert 'AGENTS.md created' (($results | Where-Object file -like '*AGENTS.md').action -eq 'created')
Assert 'GROK.md created' (($results | Where-Object file -like '*GROK.md').action -eq 'created')
Assert 'GROK.md on disk' (Test-Path (Join-Path $tmp 'GROK.md'))
Assert '.cursorrules created' (Test-Path (Join-Path $tmp '.cursorrules'))
Assert 'copilot-instructions created under .github' (Test-Path (Join-Path $tmp '.github' 'copilot-instructions.md'))
$claude = Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw
Assert 'existing CLAUDE.md content preserved' ($claude.Contains('House rules.'))
Assert 'project id defaults to dir leaf' ($claude.Contains("projects/$(Split-Path $tmp -Leaf)/"))
Assert 'wired file omits the checkout path' (-not $claude.Contains($pathA))

$rerun = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath $pathA
Assert 're-run -> all unchanged' (-not ($rerun | Where-Object action -ne 'unchanged'))

# Re-wiring the SAME project from a DIFFERENT checkout location (the other
# machine) must be a no-op. This is the churn regression the neutral stanza
# exists to prevent — it used to report 'updated' and rewrite every file.
$moved = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath $pathB
Assert 'different checkout path -> still unchanged (no cross-machine churn)' (-not ($moved | Where-Object action -ne 'unchanged'))
$claude = Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw
Assert 'no duplicate markers after re-wire' (([regex]::Matches($claude, [regex]::Escape('<!-- grimdex:start -->'))).Count -eq 1)

# explicit -ProjectId override
$r = Install-GrimdexPointers -ProjectDir $tmp -GrimdexPath $pathB -ProjectId 'custom-id'
$claude = Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw
Assert 'explicit ProjectId used' ($claude.Contains('projects/custom-id/'))

# missing project dir throws
$threw = $false
try { Install-GrimdexPointers -ProjectDir (Join-Path $tempRoot "nope-$(Get-Random)") -GrimdexPath $pathA | Out-Null }
catch { $threw = $true }
Assert 'missing project dir throws' $threw

# ---------- AGENTS.md mode (spec 2026-09-28 Part B) ----------
$ag = Join-Path $tempRoot "grimdex-agents-$(Get-Random)"
$gRoot = Join-Path $ag 'grimdex'
$dev = Join-Path $ag 'dev'
New-Item -ItemType Directory -Force -Path $gRoot, $dev | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)
function Set-Laws($text) {
    [IO.File]::WriteAllText((Join-Path $gRoot 'GRIMDEX.md'), "# Grimdex`n`nintro`n`n<!-- grimdex:laws:start -->`n$text`n<!-- grimdex:laws:end -->`n`n## Layout`n", $utf8)
}
Set-Laws "## The law`n`n1. **Rule one.**"

Assert 'laws: section extracted' ((Get-GrimdexLawsSection -GrimdexRoot $gRoot) -eq "## The law`n`n1. **Rule one.**")
$v1 = Get-GrimdexLawsVersion -Text (Get-GrimdexLawsSection -GrimdexRoot $gRoot)
Assert 'laws: version is 12 hex' ($v1 -match '^[0-9a-f]{12}$')
Assert 'laws: version ignores CRLF/trim' ((Get-GrimdexLawsVersion -Text "  ## The law`r`n`r`n1. **Rule one.**`n") -eq $v1)
$sv1 = Get-GrimdexStampVersion -GrimdexRoot $gRoot
Assert 'stamp version differs from bare law hash (format folded in)' ($sv1 -ne $v1 -and $sv1 -match '^[0-9a-f]{12}$')
$block = Get-GrimdexLawsBlock -GrimdexRoot $gRoot -ProjectId 'p1'
Assert 'laws block: markers'      ($block.StartsWith('<!-- grimdex:start -->') -and $block.EndsWith('<!-- grimdex:end -->'))
Assert 'laws block: version line' ($block.Contains("<!-- grimdex:laws-version $sv1 -->"))
Assert 'laws block: carries law'  ($block.Contains('1. **Rule one.**'))
Assert 'laws block: project tier' ($block.Contains('projects/p1/'))
Assert 'laws block: "here" means Grimdex' ($block.Contains('mean **Grimdex**'))
Assert 'laws block: top level has no tier' (-not (Get-GrimdexLawsBlock -GrimdexRoot $gRoot -TopLevel).Contains('projects/'))

$noMark = Join-Path $ag 'nomark'; New-Item -ItemType Directory -Force -Path $noMark | Out-Null
Set-Content (Join-Path $noMark 'GRIMDEX.md') '# no markers'
$threw = $false; try { Get-GrimdexLawsSection -GrimdexRoot $noMark | Out-Null } catch { $threw = $true }
Assert 'laws: missing markers throws' $threw

Set-Laws "## The law`n`nmail me at someone@gmail.com"  # grimdex:scrub-ok:email
$threw = $false; try { Get-GrimdexLawsBlock -GrimdexRoot $gRoot -ProjectId p | Out-Null } catch { $threw = $true }
Assert 'laws block: personal reference refuses to stamp' $threw
Set-Laws "## The law`n`n1. **Rule one.**"

Assert 'redirect: CLAUDE.md imports AGENTS.md' ((Get-GrimdexRedirectStanza -File 'CLAUDE.md').Contains("`n@AGENTS.md`n"))
Assert 'redirect: others point at AGENTS.md' ((Get-GrimdexRedirectStanza -File 'GEMINI.md') -match 'AGENTS\.md' -and -not (Get-GrimdexRedirectStanza -File 'GEMINI.md').Contains('@AGENTS.md'))

# a project with hand-written content, a CRLF AGENTS.md, and the old classic stanza
$p1 = Join-Path $dev 'p1'; New-Item -ItemType Directory -Force -Path $p1 | Out-Null
Install-GrimdexPointers -ProjectDir $p1 -GrimdexPath $gRoot | Out-Null
$handClaude = "# My project`n`nHand-written notes — keep me.`n`n"
[IO.File]::WriteAllText((Join-Path $p1 'CLAUDE.md'), $handClaude + (Get-GrimdexStanza -GrimdexPath $gRoot -ProjectId p1) + "`n`nTrailing notes.`n", $utf8)
[IO.File]::WriteAllText((Join-Path $p1 'AGENTS.md'), "# Agents`r`n`r`n" + ((Get-GrimdexStanza -GrimdexPath $gRoot -ProjectId p1) -replace "`n", "`r`n") + "`r`n", $utf8)

$r = @(Install-GrimdexPointers -ProjectDir $p1 -GrimdexPath $gRoot -Mode agents)
Assert 'agents: all six files touched' ($r.Count -eq 6 -and -not ($r | Where-Object action -eq 'unchanged'))
$claude = [IO.File]::ReadAllText((Join-Path $p1 'CLAUDE.md'))
$agents = [IO.File]::ReadAllText((Join-Path $p1 'AGENTS.md'))
Assert 'agents: CLAUDE.md is the import'  ($claude.Contains("<!-- grimdex:start -->`n@AGENTS.md`n<!-- grimdex:end -->") -and -not $claude.Contains('GRIMDEX.md FIRST'))
Assert 'agents: hand-written content kept' ($claude.StartsWith($handClaude) -and $claude.Contains('Trailing notes.'))
Assert 'agents: AGENTS.md has the law'     ($agents.Contains('1. **Rule one.**') -and $agents.Contains("laws-version $sv1"))
Assert 'agents: CRLF AGENTS.md stays CRLF' ($agents.Contains("`r`n") -and -not ($agents -replace "`r`n", '').Contains("`n"))
foreach ($leaf in 'GEMINI.md', 'GROK.md', '.cursorrules') {
    Assert "agents: $leaf redirects" ([IO.File]::ReadAllText((Join-Path $p1 $leaf)).Contains('are in `AGENTS.md`'))
}
Assert 'agents: copilot redirects' ([IO.File]::ReadAllText((Join-Path $p1 '.github' 'copilot-instructions.md')).Contains('are in `AGENTS.md`'))
Assert 'agents: re-run is idempotent' (-not (@(Install-GrimdexPointers -ProjectDir $p1 -GrimdexPath $gRoot -Mode agents) | Where-Object action -ne 'unchanged'))

Assert 'stamp: current' ((Test-GrimdexStamp -ProjectDir $p1 -GrimdexRoot $gRoot) -eq 'current')
Set-Laws "## The law`n`n1. **Rule one, revised.**"
Assert 'stamp: stale after the law changes' ((Test-GrimdexStamp -ProjectDir $p1 -GrimdexRoot $gRoot) -eq 'stale')
Install-GrimdexPointers -ProjectDir $p1 -GrimdexPath $gRoot -Mode agents | Out-Null
Assert 'stamp: current after re-stamp' ((Test-GrimdexStamp -ProjectDir $p1 -GrimdexRoot $gRoot) -eq 'current')

# round trip back to classic: no redirect, no law residue
Install-GrimdexPointers -ProjectDir $p1 -GrimdexPath $gRoot -Mode classic | Out-Null
$classicStanza = Get-GrimdexStanza -GrimdexPath $gRoot -ProjectId p1
$claude = [IO.File]::ReadAllText((Join-Path $p1 'CLAUDE.md'))
Assert 'classic: stanza restored'  ($claude.Contains($classicStanza) -and -not $claude.Contains('@AGENTS.md'))
Assert 'classic: law removed from AGENTS.md' (-not [IO.File]::ReadAllText((Join-Path $p1 'AGENTS.md')).Contains('laws-version'))
Assert 'classic: hand content still kept' ($claude.StartsWith($handClaude))
Assert 'stamp: none in classic' ((Test-GrimdexStamp -ProjectDir $p1 -GrimdexRoot $gRoot) -eq 'none')

# discovery + top level
$p2 = Join-Path $dev 'p2'; New-Item -ItemType Directory -Force -Path $p2 | Out-Null
$plain = Join-Path $dev 'unwired'; New-Item -ItemType Directory -Force -Path $plain | Out-Null
Set-Content (Join-Path $plain 'CLAUDE.md') '# not wired'
Install-GrimdexPointers -ProjectDir $p2 -GrimdexPath $gRoot -Mode agents | Out-Null
$found = @(Find-GrimdexWiredProjects -DevRoot $dev | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
Assert 'discovery: wired projects only' (($found -join ',') -eq 'p1,p2')
[IO.File]::WriteAllText((Join-Path $dev 'AGENTS.md'), "# Dev notes`n", $utf8)
$t = Install-GrimdexTopLevel -DevRoot $dev -GrimdexRoot $gRoot
$top = [IO.File]::ReadAllText((Join-Path $dev 'AGENTS.md'))
Assert 'top level: stamped, own notes kept' ($t.action -eq 'appended' -and $top.StartsWith('# Dev notes') -and $top.Contains('main level'))
Assert 'top level: idempotent' ((Install-GrimdexTopLevel -DevRoot $dev -GrimdexRoot $gRoot).action -eq 'unchanged')

# the live GRIMDEX.md law must stamp cleanly (public-safe)
$liveRoot = Split-Path $PSScriptRoot -Parent
$threw = $false; try { Get-GrimdexLawsBlock -GrimdexRoot $liveRoot -ProjectId x | Out-Null } catch { $threw = $true; Write-Host $_ }
Assert 'live GRIMDEX.md law is public-safe' (-not $threw)

# malformed markers: refused, nothing written (reviewer 2026-09-28)
$mk = Join-Path $dev 'malformed'; New-Item -ItemType Directory -Force -Path $mk | Out-Null
$orphan = "<!-- grimdex:start -->`nhalf a block`n`nUSER NOTES KEEP ME`n"
[IO.File]::WriteAllText((Join-Path $mk 'CLAUDE.md'), $orphan, $utf8)
$threw = $false; try { Install-GrimdexPointers -ProjectDir $mk -GrimdexPath $gRoot -Mode agents | Out-Null } catch { $threw = $true }
Assert 'markers: orphan start refused'        $threw
Assert 'markers: orphan file untouched'       ([IO.File]::ReadAllText((Join-Path $mk 'CLAUDE.md')) -eq $orphan)
Assert 'markers: no sibling file written'     (-not (Test-Path (Join-Path $mk 'AGENTS.md')))
$two = (Get-GrimdexStanza -GrimdexPath $gRoot -ProjectId x) + "`nmiddle`n" + (Get-GrimdexStanza -GrimdexPath $gRoot -ProjectId x)
[IO.File]::WriteAllText((Join-Path $mk 'CLAUDE.md'), $two, $utf8)
$threw = $false; try { Install-GrimdexPointers -ProjectDir $mk -GrimdexPath $gRoot | Out-Null } catch { $threw = $true }
Assert 'markers: two blocks refused'          ($threw -and [IO.File]::ReadAllText((Join-Path $mk 'CLAUDE.md')) -eq $two)
$threw = $false; try { Set-GrimdexBlock -Content "<!-- grimdex:end -->`n<!-- grimdex:start -->" -Stanza 'x' | Out-Null } catch { $threw = $true }
Assert 'markers: reversed pair refused'       $threw
Remove-Item -Recurse -Force $mk
$rwErr = Join-Path $dev 'broken'; New-Item -ItemType Directory -Force -Path $rwErr | Out-Null
[IO.File]::WriteAllText((Join-Path $rwErr 'CLAUDE.md'), $orphan, $utf8)
$rw = @(Invoke-GrimdexRewire -GrimdexRoot $gRoot -Mode agents -DevRoot $dev)
Assert 'markers: rewire reports, keeps going' (@($rw | Where-Object { $_.error -and $_.project -like '*broken' }).Count -eq 1 -and @($rw | Where-Object { -not $_.error }).Count -ge 3)
Remove-Item -Recurse -Force $rwErr

# top-level removal keeps surrounding lines apart and CRLF intact
$tl = Join-Path $ag 'tl'; New-Item -ItemType Directory -Force -Path $tl | Out-Null
[IO.File]::WriteAllText((Join-Path $tl 'AGENTS.md'), "Line A`n<!-- grimdex:start -->`nlaw`n<!-- grimdex:end -->`nLine B`n", $utf8)
Remove-GrimdexTopLevel -DevRoot $tl | Out-Null
Assert 'top removal: lines not glued' ([IO.File]::ReadAllText((Join-Path $tl 'AGENTS.md')) -eq "Line A`nLine B`n")
[IO.File]::WriteAllText((Join-Path $tl 'AGENTS.md'), "Line A`r`n<!-- grimdex:start -->`r`nlaw`r`n<!-- grimdex:end -->`r`nLine B`r`n", $utf8)
Remove-GrimdexTopLevel -DevRoot $tl | Out-Null
Assert 'top removal: CRLF kept' ([IO.File]::ReadAllText((Join-Path $tl 'AGENTS.md')) -eq "Line A`r`nLine B`r`n")

# project id: a re-wire keeps the recorded tier, never the folder name
New-Item -ItemType Directory -Force -Path (Join-Path $gRoot 'projects' 'bugbounty'), (Join-Path $gRoot 'projects' 'baton') | Out-Null
$bb = Join-Path $dev 'BugBounty-Incubator'; New-Item -ItemType Directory -Force -Path $bb | Out-Null
Install-GrimdexPointers -ProjectDir $bb -GrimdexPath $gRoot -ProjectId bugbounty | Out-Null
Assert 'project id: recorded tier reused' ((Get-GrimdexProjectId -ProjectDir $bb -GrimdexPath $gRoot) -eq 'bugbounty')
Install-GrimdexPointers -ProjectDir $bb -GrimdexPath $gRoot -Mode agents | Out-Null
Assert 'project id: agents stamp keeps tier' ([IO.File]::ReadAllText((Join-Path $bb 'AGENTS.md')).Contains('projects/bugbounty/'))
Install-GrimdexPointers -ProjectDir $bb -GrimdexPath $gRoot -Mode classic | Out-Null
Assert 'project id: survives the round trip' ([IO.File]::ReadAllText((Join-Path $bb 'CLAUDE.md')).Contains('projects/bugbounty/'))
$bt = Join-Path $dev 'Baton'; New-Item -ItemType Directory -Force -Path $bt | Out-Null
Set-Content (Join-Path $bt 'CLAUDE.md') "<!-- grimdex:start -->`nsee projects/<project>/`n<!-- grimdex:end -->"
Assert 'project id: placeholder -> case-insensitive tier' ((Get-GrimdexProjectId -ProjectDir $bt -GrimdexPath $gRoot) -eq 'baton')
$nw = Join-Path $dev 'NewThing'; New-Item -ItemType Directory -Force -Path $nw | Out-Null
Assert 'project id: brand-new project uses folder name' ((Get-GrimdexProjectId -ProjectDir $nw -GrimdexPath $gRoot) -eq 'NewThing')
Remove-Item -Recurse -Force $bb, $bt, $nw

# mode config
$m = Get-GrimdexMode -GrimdexRoot $gRoot
Assert 'mode: default classic'       ($m.mode -eq 'classic')
Assert 'mode: default dev_root is the parent' ($m.dev_root -eq (Split-Path (Resolve-Path $gRoot).Path -Parent))
$m = Set-GrimdexMode -GrimdexRoot $gRoot -Mode agents -DevRoot (Join-Path $HOME 'SomeDev')
Assert 'mode: set/get round-trips'   ($m.mode -eq 'agents' -and $m.dev_root -eq (Join-Path $HOME 'SomeDev'))
Assert 'mode: home stored as ~'      ((Get-Content (Join-Path $gRoot 'config' 'grimdex-mode.json') -Raw).Contains('"~/SomeDev"'))
Set-Content (Join-Path $gRoot 'config' 'grimdex-mode.json') '{ "mode": "fancy" }'
$threw = $false; try { Get-GrimdexMode -GrimdexRoot $gRoot | Out-Null } catch { $threw = $true }
Assert 'mode: unknown mode throws'   $threw

# rewire: agents stamps main level + every wired project; classic leaves the main level
$rw = @(Invoke-GrimdexRewire -GrimdexRoot $gRoot -Mode agents -DevRoot $dev)
Assert 'rewire agents: main level + 2 projects' ($rw.Count -eq 3 -and $rw[0].project -eq '(main level)')
Assert 'rewire agents: p1 now stamped' ((Test-GrimdexStamp -ProjectDir $p1 -GrimdexRoot $gRoot) -eq 'current')
Assert 'rewire agents: no errors'    (-not ($rw | Where-Object error))
Set-Laws "## The law`n`n1. **Rule one, third cut.**"
$rw = @(Invoke-GrimdexRewire -GrimdexRoot $gRoot -Mode agents -DevRoot $dev)
Assert 'rewire agents: law change re-stamps all' (@($rw | Where-Object changed -gt 0).Count -eq 3)
Assert 'rewire agents: main level current' ([IO.File]::ReadAllText((Join-Path $dev 'AGENTS.md')).Contains('third cut'))
$rw = @(Invoke-GrimdexRewire -GrimdexRoot $gRoot -Mode classic -DevRoot $dev)
Assert 'rewire classic: main-level law removed' (@($rw | Where-Object project -eq '(main level)').Count -eq 1)
Assert 'rewire classic: main-level notes kept' ([IO.File]::ReadAllText((Join-Path $dev 'AGENTS.md')) -eq "# Dev notes`n")
$rw = @(Invoke-GrimdexRewire -GrimdexRoot $gRoot -Mode classic -DevRoot $dev)
Assert 'rewire classic: second run touches no main level' (-not ($rw | Where-Object project -eq '(main level)'))
Remove-Item (Join-Path $dev 'AGENTS.md')
Install-GrimdexTopLevel -DevRoot $dev -GrimdexRoot $gRoot | Out-Null
Invoke-GrimdexRewire -GrimdexRoot $gRoot -Mode classic -DevRoot $dev | Out-Null
Assert 'rewire classic: Grimdex-only main file removed' (-not (Test-Path (Join-Path $dev 'AGENTS.md')))
Assert 'rewire classic: p2 back to classic' ((Test-GrimdexStamp -ProjectDir $p2 -GrimdexRoot $gRoot) -eq 'none')

Remove-Item -Recurse -Force $ag

Remove-Item -Recurse -Force $tmp
if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll wire-lib tests passed." -ForegroundColor Green
