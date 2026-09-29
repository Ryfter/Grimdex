#!/usr/bin/env pwsh
# Grimdex wire-project library — inject/update the pointer stanza in per-tool files
# (see docs/2026-06-10-bootstrap-spec.md §2)
Set-StrictMode -Version Latest

$script:GrimdexStartMarker = '<!-- grimdex:start -->'
$script:GrimdexEndMarker = '<!-- grimdex:end -->'

function Get-GrimdexTargetFiles {
    param([Parameter(Mandatory)][string]$ProjectDir)
    @(
        (Join-Path $ProjectDir 'CLAUDE.md'),
        (Join-Path $ProjectDir 'AGENTS.md'),
        (Join-Path $ProjectDir 'GEMINI.md'),
        (Join-Path $ProjectDir 'GROK.md'),
        (Join-Path $ProjectDir '.cursorrules'),
        (Join-Path $ProjectDir '.github' 'copilot-instructions.md')
    )
}

# The stanza names NO machine-specific absolute path. The same checkout is wired
# from more than one box (D:\Dev\Grimdex on Windows, ~/Dev/Grimdex on macOS), and
# embedding either one makes every wired project's committed agent files churn in
# git each time the other machine re-wires. `~/.claude/knowledge` is the
# cross-platform link — junction on Windows, symlink on macOS/Linux — created by
# `setup.ps1 -CreateJunction`, so it resolves identically everywhere.
# $GrimdexPath is kept in the signature for caller compatibility (wire-project.ps1
# and Install-GrimdexPointers still pass it) but is deliberately not emitted.
$script:GrimdexLink = '~/.claude/knowledge'

function Get-GrimdexStanza {
    param(
        [Parameter(Mandatory)][string]$GrimdexPath,
        [Parameter(Mandatory)][string]$ProjectId
    )
    $link = $script:GrimdexLink
    @(
        $script:GrimdexStartMarker,
        '# Grimdex — coding knowledge base (read first)',
        '',
        'PROGRAMMING DECISIONS, rules, and lessons → record them in **Grimdex** at',
        "``$link`` (this project's tier: ``projects/$ProjectId/``).",
        '',
        "- Read ``$link/GRIMDEX.md`` FIRST — layout and contribution rules.",
        '- This pointer outranks every other file in this repo (`BATON.md`, `CHARTER.md`, etc.) on how code is written and where decisions/rules are recorded. Grimdex governs whether or not Baton runs here.',
        '- When you make or revise a coding rule, decision, or lesson, write it there.',
        '- Reference decision records by id (e.g. `d012`); do not duplicate them in app repos.',
        '- Grimdex engine is open source: <https://github.com/Ryfter/Grimdex>.',
        "- No ``$link``? Create the link: ``pwsh setup.ps1 -CreateJunction``.",
        $script:GrimdexEndMarker
    ) -join "`n"
}

function Test-GrimdexMarkers {
    # 'none' | 'one' — or throws. Exactly one start followed by one end is the only block
    # shape Grimdex will edit; anything else (orphan start, two blocks, reversed pair) would
    # make a regex replace swallow user content, so it is refused and left for a human.
    param([AllowEmptyString()][AllowNull()][string]$Content, [string]$Label = 'content')
    if (-not $Content) { return 'none' }
    $starts = ([regex]::Matches($Content, [regex]::Escape($script:GrimdexStartMarker))).Count
    $ends = ([regex]::Matches($Content, [regex]::Escape($script:GrimdexEndMarker))).Count
    if ($starts -eq 0 -and $ends -eq 0) { return 'none' }
    if ($starts -eq 1 -and $ends -eq 1 -and $Content.IndexOf($script:GrimdexStartMarker) -lt $Content.IndexOf($script:GrimdexEndMarker)) { return 'one' }
    throw "$($Label): malformed Grimdex markers ($starts start, $ends end) — fix by hand so there is exactly one <!-- grimdex:start --> … <!-- grimdex:end --> block (or none); nothing was written."
}

function Set-GrimdexBlock {
    # Pure string -> string: replace the one existing marked block in place, else append.
    # Throws on malformed markers (see Test-GrimdexMarkers).
    param(
        [AllowEmptyString()][AllowNull()][string]$Content,
        [Parameter(Mandatory)][string]$Stanza
    )
    if ((Test-GrimdexMarkers -Content $Content) -eq 'one') {
        $pattern = [regex]::Escape($script:GrimdexStartMarker) + '[\s\S]*?' + [regex]::Escape($script:GrimdexEndMarker)
        # MatchEvaluator sidesteps $-substitution in replacement text (paths may contain $)
        return [regex]::Replace($Content, $pattern, { param($m) $Stanza }.GetNewClosure())
    }
    if ([string]::IsNullOrWhiteSpace($Content)) { return $Stanza + "`n" }
    return $Content.TrimEnd() + "`n`n" + $Stanza + "`n"
}

function Install-GrimdexPointers {
    # Wires one project: injects/updates the Grimdex block in every target file.
    # -Mode classic (default): the pointer stanza everywhere.
    # -Mode agents: AGENTS.md gets the stamped laws block, CLAUDE.md imports it
    # (@AGENTS.md), the other files redirect to it. $GrimdexPath must then be the real
    # Grimdex root (the laws are read from its GRIMDEX.md).
    param(
        [Parameter(Mandatory)][string]$ProjectDir,
        [Parameter(Mandatory)][string]$GrimdexPath,
        [string]$ProjectId,
        [ValidateSet('classic', 'agents')][string]$Mode = 'classic'
    )
    if (-not (Test-Path $ProjectDir -PathType Container)) { throw "Project dir not found: $ProjectDir" }
    if (-not $ProjectId) { $ProjectId = Get-GrimdexProjectId -ProjectDir $ProjectDir -GrimdexPath $GrimdexPath }
    $classic = Get-GrimdexStanza -GrimdexPath $GrimdexPath -ProjectId $ProjectId
    $laws = if ($Mode -eq 'agents') { Get-GrimdexLawsBlock -GrimdexRoot $GrimdexPath -ProjectId $ProjectId } else { $null }
    # Validate every file first so a malformed one leaves the whole project untouched.
    foreach ($file in Get-GrimdexTargetFiles -ProjectDir $ProjectDir) {
        if (Test-Path -LiteralPath $file -PathType Leaf) { Test-GrimdexMarkers -Content ([System.IO.File]::ReadAllText($file)) -Label $file | Out-Null }
    }
    $results = foreach ($file in Get-GrimdexTargetFiles -ProjectDir $ProjectDir) {
        $leaf = Split-Path $file -Leaf
        $stanza = if ($Mode -eq 'classic') { $classic }
                  elseif ($leaf -eq 'AGENTS.md') { $laws }
                  else { Get-GrimdexRedirectStanza -File $leaf }
        Set-GrimdexFileBlock -File $file -Stanza $stanza
    }
    return $results
}

function Get-GrimdexProjectId {
    # The Grimdex tier id for a project folder. Folder names and tier ids differ
    # (BugBounty-Incubator -> bugbounty), so a re-wire must reuse the id already recorded in
    # the project's Grimdex block. Order: recorded id (a real tier) -> a tier matching the
    # folder name case-insensitively -> recorded id -> folder name.
    param([Parameter(Mandatory)][string]$ProjectDir, [string]$GrimdexPath)
    $leaf = Split-Path (Resolve-Path $ProjectDir).Path -Leaf
    $tiers = @()
    if ($GrimdexPath -and (Test-Path (Join-Path $GrimdexPath 'projects') -PathType Container)) {
        $tiers = @(Get-ChildItem (Join-Path $GrimdexPath 'projects') -Directory | ForEach-Object Name)
    }
    $recorded = $null
    $pattern = [regex]::Escape($script:GrimdexStartMarker) + '[\s\S]*?' + [regex]::Escape($script:GrimdexEndMarker)
    foreach ($f in Get-GrimdexTargetFiles -ProjectDir $ProjectDir) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $block = [regex]::Match([System.IO.File]::ReadAllText($f), $pattern)
        if (-not $block.Success) { continue }
        $m = [regex]::Match($block.Value, 'projects/([A-Za-z0-9._-]+)/')
        if ($m.Success) { $recorded = $m.Groups[1].Value; break }
    }
    if ($recorded -and $recorded -cin $tiers) { return $recorded }
    $ci = @($tiers | Where-Object { $_ -ieq $leaf })
    if ($ci.Count) { return $ci[0] }
    if ($recorded) { return $recorded }
    return $leaf
}

function Set-GrimdexFileBlock {
    # Writes one marked block into one file, creating it (and its folder) if needed.
    # UTF-8 without BOM for all read/write. Get-Content/Set-Content -Encoding utf8
    # on Windows can mangle em dashes / arrows and rewrite the whole handoff file.
    # Also match the host file's newline style so a CRLF handoff is not "updated"
    # solely because the stanza was built with LF.
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Stanza)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $parent = Split-Path $File -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $existing = if (Test-Path $File) { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).Path, $utf8) } else { $null }
    $nl = if ($existing -and $existing.Contains("`r`n")) { "`r`n" } else { "`n" }
    $stanzaForFile = ($Stanza -replace "`r?`n", "`n") -replace "`n", $nl
    $new = Set-GrimdexBlock -Content $existing -Stanza $stanzaForFile
    $action =
        if ($null -eq $existing) { 'created' }
        elseif ($new -eq $existing) { 'unchanged' }
        elseif ($existing.Contains($script:GrimdexStartMarker)) { 'updated' }
        else { 'appended' }
    if ($action -ne 'unchanged') {
        [System.IO.File]::WriteAllText($File, $new, $utf8)
    }
    [pscustomobject]@{ file = $File; action = $action }
}

# --- AGENTS.md mode (spec 2026-09-28 Part B) ---

$script:GrimdexLawsStart = '<!-- grimdex:laws:start -->'
$script:GrimdexLawsEnd = '<!-- grimdex:laws:end -->'

function Get-GrimdexLawsSection {
    # The single source of the law: the text between the laws markers in GRIMDEX.md.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path $GrimdexRoot 'GRIMDEX.md'
    if (-not (Test-Path $path)) { throw "GRIMDEX.md not found under $GrimdexRoot" }
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $path).Path, [System.Text.UTF8Encoding]::new($false))
    $a = $text.IndexOf($script:GrimdexLawsStart)
    $b = $text.IndexOf($script:GrimdexLawsEnd)
    if ($a -lt 0 -or $b -lt 0 -or $b -lt $a) {
        throw "GRIMDEX.md has no complete $($script:GrimdexLawsStart) / $($script:GrimdexLawsEnd) pair — cannot stamp the law."
    }
    $start = $a + $script:GrimdexLawsStart.Length
    return ($text.Substring($start, $b - $start) -replace "`r`n", "`n").Trim()
}

function Get-GrimdexLawsVersion {
    # First 12 hex chars of SHA-256 over the LF-normalized, trimmed section.
    param([Parameter(Mandatory)][string]$Text)
    $norm = ($Text -replace "`r`n", "`n").Trim()
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($norm))
    return ([System.Convert]::ToHexString($hash).Substring(0, 12)).ToLowerInvariant()
}

# Bump when the generated block's wording/shape changes, so existing stamps read as stale.
$script:GrimdexBlockFormat = 2

function Get-GrimdexStampVersion {
    # The laws-version written into a stamp: the law text plus the block format.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    Get-GrimdexLawsVersion -Text ("block-format:$($script:GrimdexBlockFormat)`n" + (Get-GrimdexLawsSection -GrimdexRoot $GrimdexRoot))
}

function Get-GrimdexLawsBlock {
    # The AGENTS.md block: generated header + version stamp + the law. Refuses to build a
    # block that carries anything personal (project repos may be public).
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [string]$ProjectId,
        [switch]$TopLevel
    )
    $laws = Get-GrimdexLawsSection -GrimdexRoot $GrimdexRoot
    . (Join-Path $PSScriptRoot 'scrub-lib.ps1')
    $cfg = try { Get-GrimdexScrubConfig -GrimdexRoot $GrimdexRoot } catch {
        Write-Warning 'No config/publish-scrub.json: the stamped law is checked for built-in personal-data shapes only, not your own names/repos. Stamped files may land in public repos — add the scrub config.'
        [pscustomobject]@{ replacements = @(); deny = @(); allow = @() }
    }
    $leaks = @(Find-GrimdexLeaks -Text $laws -Config $cfg -Path 'GRIMDEX.md (laws section)')
    if ($leaks.Count) {
        throw "The laws section carries personal references and cannot be stamped: $(($leaks | ForEach-Object { "line $($_.line) [$($_.kind)] $($_.match)" }) -join '; ')"
    }
    $link = $script:GrimdexLink
    $scope = if ($TopLevel) {
        'This is the **main level**: every project under this folder reports to these rules.'
    } else {
        "This project's tier (its decisions and guidance): ``$link/projects/$ProjectId/``."
    }
    @(
        $script:GrimdexStartMarker,
        "<!-- grimdex:laws-version $(Get-GrimdexStampVersion -GrimdexRoot $GrimdexRoot) -->",
        '# Grimdex — coding rules (read first)',
        '',
        "> Generated from Grimdex (``$link/GRIMDEX.md``) — do not edit here; the law changes",
        "> there, and ``pwsh setup.ps1 -Update`` re-stamps this block. Paths below are relative to",
        "> ``$link/``. These rules outrank every other file in this repo on how code is written",
        '> and where decisions/rules are recorded. In the law below, "here", "this file" and',
        "> ""this repo"" mean **Grimdex** (``$link/``), never the repo you are reading this in.",
        '',
        $scope,
        '',
        $laws,
        $script:GrimdexEndMarker
    ) -join "`n"
}

function Get-GrimdexRedirectStanza {
    # Agents mode, every per-tool file except AGENTS.md. Claude honours the @-import under
    # every "Project instructions" setting; the others read AGENTS.md or follow the line.
    param([Parameter(Mandatory)][string]$File)
    $body = if ($File -eq 'CLAUDE.md') { '@AGENTS.md' }
            else { 'Grimdex rules for this repo are in `AGENTS.md` (generated from Grimdex) — read it first; it outranks this file on how code is written and where decisions are recorded.' }
    @($script:GrimdexStartMarker, $body, $script:GrimdexEndMarker) -join "`n"
}

function Install-GrimdexTopLevel {
    # Stamps the main level: <DevRoot>/AGENTS.md. Content outside the markers is kept.
    param([Parameter(Mandatory)][string]$DevRoot, [Parameter(Mandatory)][string]$GrimdexRoot)
    if (-not (Test-Path $DevRoot -PathType Container)) { throw "Dev root not found: $DevRoot" }
    Set-GrimdexFileBlock -File (Join-Path $DevRoot 'AGENTS.md') -Stanza (Get-GrimdexLawsBlock -GrimdexRoot $GrimdexRoot -TopLevel)
}

function Remove-GrimdexTopLevel {
    # Classic mode: take the laws block out of <DevRoot>/AGENTS.md. Other content is kept
    # exactly (the block and the one newline after it go; the lines around it stay apart);
    # CRLF files stay CRLF. A file left empty (Grimdex created it) is removed.
    # Returns $true when it changed.
    param([Parameter(Mandatory)][string]$DevRoot)
    $f = Join-Path $DevRoot 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    $text = [System.IO.File]::ReadAllText($f)
    if ((Test-GrimdexMarkers -Content $text -Label $f) -ne 'one') { return $false }
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $pattern = [regex]::Escape($script:GrimdexStartMarker) + '[\s\S]*?' + [regex]::Escape($script:GrimdexEndMarker) + '(\r?\n)?'
    $rest = [regex]::Replace($text, $pattern, '')
    if ($rest.Trim()) {
        [System.IO.File]::WriteAllText($f, $rest.TrimEnd() + $nl, [System.Text.UTF8Encoding]::new($false))
    } else { Remove-Item -LiteralPath $f }
    return $true
}

function Find-GrimdexWiredProjects {
    # Immediate subfolders of $DevRoot whose per-tool files carry the Grimdex start marker.
    param([Parameter(Mandatory)][string]$DevRoot)
    if (-not (Test-Path $DevRoot -PathType Container)) { return }
    foreach ($d in Get-ChildItem $DevRoot -Directory) {
        foreach ($f in Get-GrimdexTargetFiles -ProjectDir $d.FullName) {
            if ((Test-Path -LiteralPath $f -PathType Leaf) -and ([System.IO.File]::ReadAllText($f)).Contains($script:GrimdexStartMarker)) {
                $d.FullName; break
            }
        }
    }
}

function Test-GrimdexStamp {
    # current | stale | none — compares the project's AGENTS.md laws-version with GRIMDEX.md.
    param([Parameter(Mandatory)][string]$ProjectDir, [Parameter(Mandatory)][string]$GrimdexRoot)
    $f = Join-Path $ProjectDir 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $f)) { return 'none' }
    $m = [regex]::Match([System.IO.File]::ReadAllText($f), '<!-- grimdex:laws-version ([0-9a-f]{12}) -->')
    if (-not $m.Success) { return 'none' }
    $current = Get-GrimdexStampVersion -GrimdexRoot $GrimdexRoot
    if ($m.Groups[1].Value -eq $current) { 'current' } else { 'stale' }
}

# --- Mode config: config/grimdex-mode.json (private instance data) ---

function Get-GrimdexMode {
    # { mode: classic|agents, dev_root }. Absent file → classic, dev_root = the folder
    # holding the Grimdex checkout. A leading ~ in dev_root is expanded.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path $GrimdexRoot 'config' 'grimdex-mode.json'
    $mode = 'classic'
    $devRoot = Split-Path (Resolve-Path $GrimdexRoot).Path -Parent
    if (Test-Path $path) {
        $raw = Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
        $m = $raw.PSObject.Properties['mode']
        if ($m -and $m.Value) {
            if ($m.Value -notin 'classic', 'agents') { throw "config/grimdex-mode.json: mode must be classic or agents, got '$($m.Value)'" }
            $mode = [string]$m.Value
        }
        $d = $raw.PSObject.Properties['dev_root']
        if ($d -and $d.Value) { $devRoot = [string]$d.Value }
    }
    if ($devRoot.StartsWith('~')) { $devRoot = Join-Path $HOME $devRoot.Substring(1).TrimStart('/', '\') }
    [pscustomobject]@{ mode = $mode; dev_root = $devRoot }
}

function Set-GrimdexMode {
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][ValidateSet('classic', 'agents')][string]$Mode,
        [Parameter(Mandatory)][string]$DevRoot
    )
    $path = Join-Path $GrimdexRoot 'config' 'grimdex-mode.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    $home_ = $HOME.TrimEnd('/', '\')
    $stored = if ($DevRoot.StartsWith($home_)) { '~' + $DevRoot.Substring($home_.Length).Replace('\', '/') } else { $DevRoot }
    $json = [ordered]@{ mode = $Mode; dev_root = $stored } | ConvertTo-Json
    [System.IO.File]::WriteAllText($path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Get-GrimdexMode -GrimdexRoot $GrimdexRoot
}

function Invoke-GrimdexRewire {
    # Re-wires every wired project under $DevRoot in $Mode; in agents mode also stamps the
    # main level. A project that fails is reported, not fatal.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][ValidateSet('classic', 'agents')][string]$Mode,
        [Parameter(Mandatory)][string]$DevRoot
    )
    if ($Mode -eq 'agents') {
        $t = Install-GrimdexTopLevel -DevRoot $DevRoot -GrimdexRoot $GrimdexRoot
        [pscustomobject]@{ project = '(main level)'; changed = [int]($t.action -ne 'unchanged'); error = $null }
    } elseif (Remove-GrimdexTopLevel -DevRoot $DevRoot) {
        # A law left at the main level would still reach every project below it (Claude
        # reads parent folders) and go stale — classic mode takes it down.
        [pscustomobject]@{ project = '(main level)'; changed = 1; error = $null }
    }
    foreach ($p in @(Find-GrimdexWiredProjects -DevRoot $DevRoot)) {
        try {
            $r = @(Install-GrimdexPointers -ProjectDir $p -GrimdexPath $GrimdexRoot -Mode $Mode)
            [pscustomobject]@{ project = $p; changed = @($r | Where-Object action -ne 'unchanged').Count; error = $null }
        } catch {
            [pscustomobject]@{ project = $p; changed = 0; error = $_.Exception.Message }
        }
    }
}
