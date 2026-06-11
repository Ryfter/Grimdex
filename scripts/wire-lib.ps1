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
        (Join-Path $ProjectDir '.cursorrules'),
        (Join-Path $ProjectDir '.github' 'copilot-instructions.md')
    )
}

function Get-GrimdexStanza {
    param(
        [Parameter(Mandatory)][string]$GrimdexPath,
        [Parameter(Mandatory)][string]$ProjectId
    )
    $rootFile = Join-Path $GrimdexPath 'GRIMDEX.md'
    @(
        $script:GrimdexStartMarker,
        '# Grimdex — coding knowledge base (read first)',
        '',
        'PROGRAMMING DECISIONS, rules, and lessons → record them in **Grimdex** at',
        "``$GrimdexPath`` (this project's tier: ``projects/$ProjectId/``).",
        '',
        "- Read ``$rootFile`` FIRST — layout and contribution rules.",
        '- When you make or revise a coding rule, decision, or lesson, write it there.',
        '- Reference decision records by id (e.g. `d012`); do not duplicate them in app repos.',
        '- Grimdex engine is open source: <https://github.com/Ryfter/Grimdex>.',
        $script:GrimdexEndMarker
    ) -join "`n"
}

function Set-GrimdexBlock {
    # Pure string -> string: replace an existing marked block in place, else append.
    param(
        [AllowEmptyString()][AllowNull()][string]$Content,
        [Parameter(Mandatory)][string]$Stanza
    )
    $pattern = [regex]::Escape($script:GrimdexStartMarker) + '[\s\S]*?' + [regex]::Escape($script:GrimdexEndMarker)
    if ($Content -and [regex]::IsMatch($Content, $pattern)) {
        # MatchEvaluator sidesteps $-substitution in replacement text (paths may contain $)
        return [regex]::Replace($Content, $pattern, { param($m) $Stanza }.GetNewClosure())
    }
    if ([string]::IsNullOrWhiteSpace($Content)) { return $Stanza + "`n" }
    return $Content.TrimEnd() + "`n`n" + $Stanza + "`n"
}

function Install-GrimdexPointers {
    # Wires one project: injects/updates the stanza in every target file.
    param(
        [Parameter(Mandatory)][string]$ProjectDir,
        [Parameter(Mandatory)][string]$GrimdexPath,
        [string]$ProjectId
    )
    if (-not (Test-Path $ProjectDir -PathType Container)) { throw "Project dir not found: $ProjectDir" }
    if (-not $ProjectId) { $ProjectId = Split-Path (Resolve-Path $ProjectDir).Path -Leaf }
    $stanza = Get-GrimdexStanza -GrimdexPath $GrimdexPath -ProjectId $ProjectId
    $results = foreach ($file in Get-GrimdexTargetFiles -ProjectDir $ProjectDir) {
        $parent = Split-Path $file -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $existing = if (Test-Path $file) { Get-Content $file -Raw } else { $null }
        $new = Set-GrimdexBlock -Content $existing -Stanza $stanza
        $action =
            if ($null -eq $existing) { 'created' }
            elseif ($new -eq $existing) { 'unchanged' }
            elseif ($existing.Contains($script:GrimdexStartMarker)) { 'updated' }
            else { 'appended' }
        if ($action -ne 'unchanged') { Set-Content -Path $file -Value $new -NoNewline -Encoding utf8 }
        [pscustomobject]@{ file = $file; action = $action }
    }
    return $results
}
