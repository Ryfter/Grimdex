#!/usr/bin/env pwsh
# Grimdex engine publish — plan/apply the scrubbed mirror to the public engine checkout and
# gate every push with a leak scan. Never commits or pushes: publishing stays the
# maintainer's call. (Spec: docs/superpowers/specs/2026-09-28-agents-md-mode-and-publish-hook-design.md, Part A.)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'scrub-lib.ps1')

function Get-GrimdexEngineManifest {
    # config/engine-manifest.json: { sync:[path|glob], engine_owned:[path], examples:{src:dest}, never:[path|glob] }
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path $GrimdexRoot 'config' 'engine-manifest.json'
    if (-not (Test-Path $path)) { throw "No engine manifest at $path." }
    $raw = Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
    $list = { param($n) $p = $raw.PSObject.Properties[$n]; if ($p -and $null -ne $p.Value) { , @($p.Value) } else { , @() } }
    $examples = [ordered]@{}
    $ex = $raw.PSObject.Properties['examples']
    if ($ex -and $ex.Value) { foreach ($p in $ex.Value.PSObject.Properties) { $examples[$p.Name] = [string]$p.Value } }
    [pscustomobject]@{
        sync         = & $list 'sync'
        engine_owned = & $list 'engine_owned'
        examples     = $examples
        never        = & $list 'never'
    }
}

function Test-GrimdexPathMatch {
    # True when a repo-relative path matches any entry (exact or -like glob).
    param([string]$Path, [object[]]$Patterns)
    foreach ($p in @($Patterns)) { if ($Path -eq $p -or $Path -like $p) { return $true } }
    return $false
}

function Read-GrimdexText {
    param([string]$Path)
    [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath, [Text.UTF8Encoding]::new($false))
}

function Get-GrimdexGitBytes {
    # Raw bytes of a git object (e.g. "HEAD:path") — no text decoding on the way.
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Spec)
    $psi = [System.Diagnostics.ProcessStartInfo]::new('git')
    foreach ($a in '-C', $Root, 'cat-file', 'blob', $Spec) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $ms = [IO.MemoryStream]::new()
    $proc.StandardOutput.BaseStream.CopyTo($ms)
    $proc.WaitForExit()
    return , $ms.ToArray()
}

function Find-GrimdexTreeLeaks {
    # Scans the tracked files in $Root. -Source Head (the pre-push gate) reads the committed
    # bytes at -Rev (default HEAD); -Source Disk (the publish plan) reads the working tree,
    # so uncommitted engine fixes count. Binaries are skipped; UTF-16 with a BOM is decoded
    # and scanned. -Exclude skips paths scanned elsewhere.
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Config,
        [string[]]$Exclude = @(),
        [ValidateSet('Head', 'Disk')][string]$Source = 'Head',
        [string]$Rev = 'HEAD'
    )
    $files = if ($Source -eq 'Head') { @(git -C $Root ls-tree -r --name-only $Rev 2>$null) } else { @(git -C $Root ls-files 2>$null) }
    foreach ($f in $files) {
        if ($f -in $Exclude) { continue }
        if ($Source -eq 'Head') {
            $bytes = Get-GrimdexGitBytes -Root $Root -Spec "$($Rev):$f"
        } else {
            $disk = Join-Path $Root $f
            if (-not (Test-Path -LiteralPath $disk -PathType Leaf)) { continue }
            $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $disk).ProviderPath)
        }
        if (-not (Test-GrimdexTextBytes -Bytes $bytes)) { continue }
        Find-GrimdexLeaks -Text (ConvertFrom-GrimdexBytes -Bytes $bytes) -Config $Config -Path $f
    }
}

function Find-GrimdexPushLeaks {
    # The pre-push gate. $RefLines are git's stdin lines: "<local ref> <local sha> <remote
    # ref> <remote sha>". For each pushed range it scans every commit's message and added
    # lines (so a leak added then deleted still blocks — history is public too) plus the
    # full tree at the pushed tip (whatever branch is pushed, not the checked-out one).
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Config,
        [AllowEmptyCollection()][string[]]$RefLines = @()
    )
    foreach ($ln in $RefLines) {
        $parts = -split $ln
        if ($parts.Count -lt 4) { continue }
        $localSha = $parts[1]; $remoteSha = $parts[3]
        if ($localSha -match '^0+$') { continue }   # deleting a remote ref publishes nothing
        $commits = if ($remoteSha -match '^0+$') { @(git -C $Root rev-list $localSha --not --remotes 2>$null) }
                   else { @(git -C $Root rev-list "$remoteSha..$localSha" 2>$null) }
        foreach ($c in $commits) {
            $short = $c.Substring(0, [Math]::Min(8, $c.Length))
            $msg = (git -C $Root log -1 --format=%B $c 2>$null) -join "`n"
            Find-GrimdexLeaks -Text $msg -Config $Config -Path "commit $short (message)"
            $current = $null
            $added = [ordered]@{}
            foreach ($d in @(git -C $Root show --format= --no-color --unified=0 $c 2>$null)) {
                if ($d -match '^\+\+\+ (?:b/)?(.*)$') { $current = $Matches[1]; continue }
                if ($d.StartsWith('+') -and $current) {
                    if (-not $added.Contains($current)) { $added[$current] = [System.Collections.Generic.List[string]]::new() }
                    $added[$current].Add($d.Substring(1))
                }
            }
            foreach ($k in $added.Keys) {
                Find-GrimdexLeaks -Text ($added[$k] -join "`n") -Config $Config -Path "$k (added in commit $short)"
            }
        }
        Find-GrimdexTreeLeaks -Root $Root -Config $Config -Source Head -Rev $localSha
    }
}

function Get-GrimdexPublishPlan {
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$EngineRoot,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Manifest
    )
    if (-not (Test-Path (Join-Path $EngineRoot '.git'))) { throw "Engine root is not a git checkout: $EngineRoot" }
    $tracked = @(git -C $GrimdexRoot ls-files 2>$null)
    $pairs = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Manifest.sync)) {
        $hits = if ($entry -match '[\*\?\[]') { @($tracked | Where-Object { $_ -like $entry }) } else { @($entry) }
        foreach ($h in $hits) { if (-not ($pairs | Where-Object src -eq $h)) { $pairs.Add([pscustomobject]@{ src = $h; dest = $h }) } }
    }
    foreach ($k in $Manifest.examples.Keys) { $pairs.Add([pscustomobject]@{ src = $k; dest = $Manifest.examples[$k] }) }

    $items = [System.Collections.Generic.List[object]]::new()
    $leaks = [System.Collections.Generic.List[object]]::new()
    foreach ($pr in $pairs) {
        $srcPath = Join-Path $GrimdexRoot $pr.src
        $isExample = $Manifest.examples.Contains($pr.src)
        if (-not $isExample -and (Test-GrimdexPathMatch -Path $pr.src -Patterns $Manifest.never)) {
            $items.Add([pscustomobject]@{ src = $pr.src; dest = $pr.dest; action = 'refused'; content = $null; note = 'listed in never' }); continue
        }
        if (Test-GrimdexPathMatch -Path $pr.dest -Patterns $Manifest.never) {
            $items.Add([pscustomobject]@{ src = $pr.src; dest = $pr.dest; action = 'refused'; content = $null; note = 'destination listed in never' }); continue
        }
        if (-not (Test-Path -LiteralPath $srcPath -PathType Leaf)) {
            $items.Add([pscustomobject]@{ src = $pr.src; dest = $pr.dest; action = 'refused'; content = $null; note = 'source missing' }); continue
        }
        if (-not (Test-GrimdexTextFile -Path $srcPath)) {
            $items.Add([pscustomobject]@{ src = $pr.src; dest = $pr.dest; action = 'refused'; content = $null; note = 'binary source' }); continue
        }
        $content = Invoke-GrimdexScrub -Text (Read-GrimdexText $srcPath) -Config $Config
        foreach ($l in @(Find-GrimdexLeaks -Text $content -Config $Config -Path $pr.dest)) { $leaks.Add($l) }
        $destPath = Join-Path $EngineRoot $pr.dest
        $action = if (-not (Test-Path -LiteralPath $destPath)) { 'new' }
                  elseif ((Read-GrimdexText $destPath) -ceq $content) { 'unchanged' }
                  else { 'changed' }
        $items.Add([pscustomobject]@{ src = $pr.src; dest = $pr.dest; action = $action; content = $content; note = $null })
    }
    foreach ($o in @($Manifest.engine_owned)) {
        $items.Add([pscustomobject]@{ src = $null; dest = $o; action = 'owned'; content = $null; note = $null })
    }
    # Everything else already in the engine is scanned as it stands (owned files included).
    $planned = @($items | Where-Object { $_.action -in 'new', 'changed', 'unchanged' } | ForEach-Object dest)
    foreach ($l in @(Find-GrimdexTreeLeaks -Root $EngineRoot -Config $Config -Exclude $planned -Source Disk)) { $leaks.Add($l) }
    [pscustomobject]@{ items = $items.ToArray(); leaks = $leaks.ToArray() }
}

function Invoke-GrimdexPublish {
    # Writes new/changed items into the engine working tree. Returns the written items.
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$EngineRoot)
    $utf8 = [Text.UTF8Encoding]::new($false)
    foreach ($it in @($Plan.items | Where-Object { $_.action -in 'new', 'changed' })) {
        $dest = Join-Path $EngineRoot $it.dest
        New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
        [IO.File]::WriteAllText($dest, $it.content, $utf8)
        $it
    }
}

function Install-GrimdexEnginePrePush {
    # Local, never-committed hook: every push from the engine checkout runs the leak scan.
    # It embeds this machine's Grimdex root because the scrub config is private.
    param(
        [Parameter(Mandatory)][string]$EngineRoot,
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [string]$ScriptRoot = $PSScriptRoot
    )
    $hook = Join-Path $EngineRoot '.git' 'hooks' 'pre-push'
    New-Item -ItemType Directory -Force -Path (Split-Path $hook -Parent) | Out-Null
    $publish = Join-Path $ScriptRoot 'publish-engine.ps1'
    $body = @(
        '#!/bin/sh',
        '# Grimdex publish gate (installed by publish-engine.ps1 -InstallHook). Blocks a push',
        '# when the engine tree holds anything personal. Local only; never committed.',
        "exec pwsh -NoProfile -File '$publish' -EngineRoot '$EngineRoot' -GrimdexRoot '$GrimdexRoot' -ScanOnly -PrePush"
    ) -join "`n"
    [IO.File]::WriteAllText($hook, $body + "`n", [Text.UTF8Encoding]::new($false))
    if (-not $IsWindows) { chmod +x $hook }
    return $hook
}
