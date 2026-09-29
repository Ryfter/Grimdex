#!/usr/bin/env pwsh
# Tests for scripts/scrub-lib.ps1 — publish scrubber: replacements, leak shapes, fail-closed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scrub-lib.ps1')

$failures = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "PASS  $label" -ForegroundColor Green }
    else { Write-Host "FAIL  $label" -ForegroundColor Red; $script:failures++ }
}
function Kinds($text, $cfg) { ,@(Find-GrimdexLeaks -Text $text -Config $cfg | ForEach-Object kind) }

$cfg = [pscustomobject]@{
    replacements = @(
        [pscustomobject]@{ find = 'bighost'; replace = '<hub-host>'; regex = $false }
        [pscustomobject]@{ find = '\bbox\d+\b'; replace = '<box>'; regex = $true }
        [pscustomobject]@{ find = '/Users/alice'; replace = '~'; regex = $false }  # grimdex:scrub-ok:home-path
    )
    deny  = @('secretproj', 'Alice')
    allow = @('Copyright \(c\) \d{4} Alice')
}
$empty = [pscustomobject]@{ replacements = @(); deny = @(); allow = @() }

# --- replacements ---
Assert 'literal replacement' ((Invoke-GrimdexScrub -Text 'ssh bighost now' -Config $cfg) -eq 'ssh <hub-host> now')
Assert 'regex replacement' ((Invoke-GrimdexScrub -Text 'box12 and box3' -Config $cfg) -eq '<box> and <box>')
Assert 'path replacement' ((Invoke-GrimdexScrub -Text 'cd /Users/alice/Dev' -Config $cfg) -eq 'cd ~/Dev')  # grimdex:scrub-ok:home-path
Assert 'replacement text with $ is literal' ((Invoke-GrimdexScrub -Text 'bighost' -Config ([pscustomobject]@{ replacements = @([pscustomobject]@{ find = 'bighost'; replace = '$1x'; regex = $true }); deny = @(); allow = @() })) -eq '$1x')

# --- built-in shapes found ---
Assert 'email found'         ((Kinds 'mail a@b.com now' $empty) -contains 'email')  # grimdex:scrub-ok:email
Assert 'mac home found'      ((Kinds 'at /Users/bob/x' $empty) -contains 'home-path')  # grimdex:scrub-ok:home-path
Assert 'windows home found'  ((Kinds 'at C:\Users\bob\x' $empty) -contains 'home-path')  # grimdex:scrub-ok:home-path
Assert 'tailnet ip found'    ((Kinds 'ip 100.101.1.2' $empty) -contains 'tailnet-ip')  # grimdex:scrub-ok:tailnet-ip
Assert 'tailnet host found'  ((Kinds 'http://host.foo.ts.net:80/' $empty) -contains 'tailnet-host')  # grimdex:scrub-ok:tailnet-host
Assert 'lan ip found'        ((Kinds 'ip 192.168.1.5' $empty) -contains 'lan-ip')  # grimdex:scrub-ok:lan-ip
Assert 'lan 10.x found'      ((Kinds 'ip 10.0.4.2' $empty) -contains 'lan-ip')  # grimdex:scrub-ok:lan-ip

# --- look-alikes not flagged ---
Assert 'noreply email ok'    ((Kinds 'noreply@anthropic.com' $empty).Count -eq 0)
Assert 'example email ok'    ((Kinds 'user@example.com' $empty).Count -eq 0)
Assert 'tilde path ok'       ((Kinds 'cd ~/Dev' $empty).Count -eq 0)
Assert 'placeholder home ok' ((Kinds '/Users/<you>/Dev and C:\Users\<you>\x' $empty).Count -eq 0)
Assert 'generic home words ok' ((Kinds '/Users/Shared and C:\Users\Public' $empty).Count -eq 0)
Assert 'non-cgnat 100.x ok'  ((Kinds 'version 100.0.0.1' $empty).Count -eq 0)
Assert 'example tailnet ok'   ((Kinds 'http://dev-box.example.ts.net/ and example.ts.net' $empty).Count -eq 0)
Assert 'placeholder tailnet ok' ((Kinds 'http://<hub-host>.<tailnet>.ts.net/' $empty).Count -eq 0)
Assert 'pwsh escape before @ not email' ((Kinds '"`n@AGENTS.md`n"' $empty).Count -eq 0)
Assert 'backticked email found'      ((Kinds ('`' + 'alice.smith' + '@gmail.com`') $empty) -contains 'email')
Assert 'url-encoded email found'     ((Kinds ('mailto:alice' + '%40gmail.com') $empty) -contains 'email')
Assert 'json-escaped win home found' ((Kinds ('"C:' + '\\Users\\alice\\x"') $empty) -contains 'home-path')
Assert 'tailnet ipv6 found'          ((Kinds ('fd7a:' + '115c:a1e0::1') $empty) -contains 'tailnet-ip')
Assert 'git ssh url not email' ((Kinds 'git@github.com:org/repo.git' $empty).Count -eq 0)

# --- scrub-ok marker: names the shapes it excuses; bare marker excuses nothing; deny never ---
Assert 'named marker excuses its shape' ((Kinds ('a' + '@b.com  # grimdex:' + 'scrub-ok:email') $empty).Count -eq 0)
Assert 'bare marker excuses nothing'    ((Kinds ('a' + '@b.com  # grimdex:' + 'scrub-ok') $empty) -contains 'email')
Assert 'marker excuses only named kind' ((Kinds ('a' + '@b.com 192.' + '168.1.9 # grimdex:' + 'scrub-ok:email') $empty) -contains 'lan-ip')
Assert 'marker never hides deny'        ((Kinds ('secretproj  # grimdex:' + 'scrub-ok:email') $cfg) -contains 'deny')
Assert 'yourname placeholder ok' ((Kinds '/Users/yourname/Dev' $empty).Count -eq 0)

# --- deny + allow ---
Assert 'deny hit found'      ((Kinds 'the secretproj repo' $cfg) -contains 'deny')
Assert 'deny is case-insensitive' ((Kinds 'ALICE was here' $cfg) -contains 'deny')
Assert 'allow suppresses line' ((Kinds 'Copyright (c) 2026 Alice' $cfg).Count -eq 0)
$f = @(Find-GrimdexLeaks -Text "ok`nsecretproj`nok" -Config $cfg -Path 'x.md')
Assert 'finding carries path + line' ($f.Count -eq 1 -and $f[0].path -eq 'x.md' -and $f[0].line -eq 2)

# --- scrub then scan is clean ---
$scrubbed = Invoke-GrimdexScrub -Text 'cd /Users/alice/Dev on bighost' -Config $cfg  # grimdex:scrub-ok:home-path
Assert 'scrubbed output scans clean' ((Kinds $scrubbed $cfg).Count -eq 0)

# --- config loading fails closed ---
$sandbox = Join-Path ([IO.Path]::GetTempPath()) "grimdex-scrub-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'config') | Out-Null
$threw = $false; try { Get-GrimdexScrubConfig -GrimdexRoot $sandbox | Out-Null } catch { $threw = $true }
Assert 'missing scrub config throws' $threw
Set-Content (Join-Path $sandbox 'config' 'publish-scrub.json') '{ not json'
$threw = $false; try { Get-GrimdexScrubConfig -GrimdexRoot $sandbox | Out-Null } catch { $threw = $true }
Assert 'malformed scrub config throws' $threw
Set-Content (Join-Path $sandbox 'config' 'publish-scrub.json') '{ "deny": ["x"] }'
$c = Get-GrimdexScrubConfig -GrimdexRoot $sandbox
Assert 'partial config gets empty lists' ($c.replacements.Count -eq 0 -and $c.allow.Count -eq 0 -and $c.deny.Count -eq 1)

# --- binary detection ---
$bin = Join-Path $sandbox 'img.png'
[IO.File]::WriteAllBytes($bin, [byte[]](0x89, 0x50, 0x00, 0x61, 0x40, 0x62))
$txt = Join-Path $sandbox 'a.md'
Set-Content $txt 'hello'
Assert 'binary detected' (-not (Test-GrimdexTextFile -Path $bin))
Assert 'text detected' (Test-GrimdexTextFile -Path $txt)
$u16 = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes('mail ' + 'bob' + '@corp.io')
Assert 'utf-16 with BOM is text'      (Test-GrimdexTextBytes -Bytes $u16)
Assert 'utf-16 decodes for scanning'  ((Kinds (ConvertFrom-GrimdexBytes -Bytes $u16) $empty) -contains 'email')

Remove-Item -Recurse -Force $sandbox

if ($failures -gt 0) { Write-Host "`n$failures FAILURE(S)" -ForegroundColor Red; exit 1 }
Write-Host "`nAll scrub-lib tests passed." -ForegroundColor Green
