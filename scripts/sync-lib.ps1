#!/usr/bin/env pwsh
# Grimdex sync library — hub/spoke role + rule-sync proposal model (Sprint 4, d008).
# Dot-sources sweep-lib for New-GrimdexFinding + Add-GrimdexLogEntry (one-way dep).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sweep-lib.ps1')

function Get-GrimdexHostName {
    # This machine's short hostname, cross-platform. $env:COMPUTERNAME is Windows-only —
    # empty under pwsh on macOS/Linux — so fall back to .NET, then the `hostname` binary.
    if ($env:COMPUTERNAME) { return $env:COMPUTERNAME }
    try { $n = [System.Net.Dns]::GetHostName(); if ($n) { return $n } } catch { }
    try { $n = (& hostname 2>$null); if ($n) { return "$n".Trim() } } catch { }
    return ''
}

function Get-GrimdexRole {
    # 'hub' only when config/sync.json's hub matches this machine; 'spoke' otherwise
    # (missing/malformed config, or an absent/blank hub key, defaults to the safe, read-only spoke role).
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [string]$ComputerName = (Get-GrimdexHostName)
    )
    $cfg = Join-Path $GrimdexRoot 'config' 'sync.json'
    if (-not (Test-Path $cfg)) { return 'spoke' }
    try { $hub = (Get-Content $cfg -Raw | ConvertFrom-Json).hub } catch { return 'spoke' }
    if (-not $hub) { return 'spoke' }
    # Compare on the short name (strip any .local / DNS suffix on either side), case-insensitively.
    $short = { param($s) (("$s" -split '\.')[0]).Trim().ToLowerInvariant() }
    if ((& $short $hub) -and ((& $short $hub) -eq (& $short $ComputerName))) { return 'hub' }
    return 'spoke'
}

function Get-RuleSyncProposalPath {
    # One pending proposal file per machine; the hub drains daily.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Machine
    )
    if ($Machine -notmatch '^[A-Za-z0-9._-]+$') {
        throw "machine name contains path or frontmatter metacharacters: $Machine"
    }
    Join-Path $GrimdexRoot 'universal' 'promotions' ("{0}.sync.md" -f $Machine.ToLowerInvariant())
}

function New-RuleSyncProposal {
    # Writes a rule-sync proposal (frontmatter + full proposed target content). Returns path.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Target,      # repo-relative, forward slashes
        [Parameter(Mandatory)][string]$Content,     # full proposed content of the target file
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Timestamp,   # ISO 8601
        [string]$Note = ''
    )
    $fm = @(
        '---'
        'kind: rule-sync'
        "machine: $Machine"
        "timestamp: $Timestamp"
        "target: $Target"
        "note: $Note"
        '---'
        ''
    ) -join "`n"
    $path = Get-RuleSyncProposalPath -GrimdexRoot $GrimdexRoot -Machine $Machine
    Set-Content -Path $path -Value ($fm + $Content) -NoNewline -Encoding utf8
    return $path
}

function ConvertFrom-RuleSyncProposal {
    # Parse a *.sync.md into an object. Returns $null when there is no frontmatter.
    param([Parameter(Mandatory)][string]$Path)
    $raw = Get-Content $Path -Raw
    $m = [regex]::Match($raw, '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
    if (-not $m.Success) { return $null }
    $meta = @{}
    foreach ($line in ($m.Groups[1].Value -split "\r?\n")) {
        if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.*)$') {
            $meta[$Matches[1].ToLowerInvariant()] = $Matches[2].Trim()
        }
    }
    [pscustomobject]@{
        path      = $Path
        kind      = $meta['kind']
        machine   = $meta['machine']
        timestamp = $meta['timestamp']
        target    = $meta['target']
        note      = $meta['note']
        content   = $m.Groups[2].Value
    }
}

function Test-RuleSyncTargetAllowed {
    # A target must be GRIMDEX.md or a file under universal/claude-rules/, and exist.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Target
    )
    $norm = $Target -replace '\\', '/'
    $isLaw  = $norm -eq 'GRIMDEX.md'
    # Rules are direct Markdown children. Reject traversal, nested paths and alternate
    # separators before Join-Path ever sees the value from proposal frontmatter.
    $isRule = $norm -match '^universal/claude-rules/[A-Za-z0-9._-]+\.md$'
    if (-not ($isLaw -or $isRule)) { return $false }
    $root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $GrimdexRoot).ProviderPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $abs = [IO.Path]::GetFullPath((Join-Path $root ($norm -replace '/', [IO.Path]::DirectorySeparatorChar)))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $abs.StartsWith($root + [IO.Path]::DirectorySeparatorChar, $comparison)) { return $false }
    if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { return $false }
    # No component below the root (dirs or the file itself) may be a symlink/reparse point.
    $cur = $root
    foreach ($seg in ($norm -split '/')) {
        $cur = Join-Path $cur $seg
        $item = Get-Item -LiteralPath $cur -Force -ErrorAction SilentlyContinue
        if (-not $item -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    }
    return $true
}

function Test-RuleSyncProposal {
    # Returns { valid; reason; path; proposal }. `path` is always set.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Path
    )
    $p = ConvertFrom-RuleSyncProposal -Path $Path
    $base = [pscustomobject]@{ valid = $false; reason = $null; path = $Path; proposal = $p }
    if (-not $p)                 { $base.reason = 'no frontmatter';                 return $base }
    if ($p.kind -ne 'rule-sync') { $base.reason = "kind '$($p.kind)' != rule-sync"; return $base }
    if (-not $p.target)          { $base.reason = 'no target';                       return $base }
    if (-not (Test-RuleSyncTargetAllowed -GrimdexRoot $GrimdexRoot -Target $p.target)) {
        $base.reason = "target is not an existing rule/law file: $($p.target)";      return $base
    }
    if (-not ($p.content.Trim())) { $base.reason = 'empty content';                  return $base }
    $base.valid = $true
    return $base
}

function Get-PendingRuleSyncProposals {
    # One validation result per *.sync.md in the promotions inbox.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $inbox = Join-Path $GrimdexRoot 'universal' 'promotions'
    if (-not (Test-Path $inbox)) { return @() }
    $rows = foreach ($f in Get-ChildItem $inbox -Filter '*.sync.md') {
        Test-RuleSyncProposal -GrimdexRoot $GrimdexRoot -Path $f.FullName
    }
    return @($rows)
}

function Approve-RuleSyncProposal {
    # Hub-only write: publish the proposed content to its target, remove the proposal,
    # and ledger it. Refuses an invalid proposal.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Path,
        [string]$DecidedDate = (Get-Date -Format 'yyyy-MM-dd')
    )
    $r = Test-RuleSyncProposal -GrimdexRoot $GrimdexRoot -Path $Path
    if (-not $r.valid) { throw "cannot approve invalid proposal ($($r.reason)): $Path" }
    $p = $r.proposal
    # Validation above has already constrained this to GRIMDEX.md or one direct rule file.
    # Re-check immediately before writing (the target may have changed since validation).
    if (-not (Test-RuleSyncTargetAllowed -GrimdexRoot $GrimdexRoot -Target $p.target)) {
        throw "target no longer allowed at write time: $($p.target)"
    }
    $abs = Join-Path $GrimdexRoot ($p.target -replace '/', [IO.Path]::DirectorySeparatorChar)
    Set-Content -Path $abs -Value $p.content -NoNewline -Encoding utf8
    Remove-Item $Path
    $entry = @(
        "## $DecidedDate — rule-sync: $($p.target) (from $($p.machine)) — ACCEPTED"
        "**From:** $($p.machine) (proposed $($p.timestamp))"
        "**Candidate:** rule-sync edit to $($p.target)"
        "**Disposition reasoning:** $($p.note)"
        "**Inscribed into:** $($p.target)"
    ) -join "`n"
    Add-GrimdexLogEntry -LogPath (Join-Path $GrimdexRoot 'universal' 'PROMOTIONS-LOG.md') -Entry $entry
    [pscustomobject]@{ action = 'accepted'; target = $p.target; machine = $p.machine }
}

function Test-GrimdexRuleSyncProposals {
    # Sweep surfacing: info per valid pending proposal (hub review needed),
    # warn per malformed one. Never applies anything — application is hub-gated.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $findings = foreach ($r in Get-PendingRuleSyncProposals -GrimdexRoot $GrimdexRoot) {
        if ($r.valid) {
            New-GrimdexFinding -Check 'rule-sync' -Severity info -Path $r.path `
                -Message "rule-sync proposal pending hub review: $($r.proposal.target) (from $($r.proposal.machine))"
        } else {
            New-GrimdexFinding -Check 'rule-sync' -Severity warn -Path $r.path `
                -Message "malformed rule-sync proposal: $($r.reason)"
        }
    }
    return @($findings)
}

function Deny-RuleSyncProposal {
    # Remove a proposal without applying it; ledger the rejection. Target is never touched.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Reason,
        [string]$DecidedDate = (Get-Date -Format 'yyyy-MM-dd')
    )
    $p = ConvertFrom-RuleSyncProposal -Path $Path
    $target  = if ($p) { $p.target }  else { '(unparseable)' }
    $machine = if ($p) { $p.machine } else { '(unknown)' }
    Remove-Item $Path
    $entry = @(
        "## $DecidedDate — rule-sync: $target (from $machine) — REJECTED"
        "**From:** $machine"
        "**Candidate:** rule-sync edit to $target"
        "**Disposition reasoning:** $Reason"
    ) -join "`n"
    Add-GrimdexLogEntry -LogPath (Join-Path $GrimdexRoot 'universal' 'PROMOTIONS-LOG.md') -Entry $entry
    [pscustomobject]@{ action = 'rejected'; target = $target; reason = $Reason }
}
