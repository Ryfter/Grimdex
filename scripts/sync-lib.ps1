#!/usr/bin/env pwsh
# Grimdex sync library — hub/spoke role + rule-sync proposal model (Sprint 4, d008).
# Dot-sources sweep-lib for New-GrimdexFinding + Add-GrimdexLogEntry (one-way dep).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sweep-lib.ps1')

function Get-GrimdexRole {
    # 'hub' only when config/sync.json's hub matches this machine; 'spoke' otherwise
    # (missing/malformed config, or an absent/blank hub key, defaults to the safe, read-only spoke role).
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [string]$ComputerName = $env:COMPUTERNAME
    )
    $cfg = Join-Path $GrimdexRoot 'config' 'sync.json'
    if (-not (Test-Path $cfg)) { return 'spoke' }
    try { $hub = (Get-Content $cfg -Raw | ConvertFrom-Json).hub } catch { return 'spoke' }
    if ($hub -and $hub.Trim().ToLowerInvariant() -eq $ComputerName.Trim().ToLowerInvariant()) {
        return 'hub'
    }
    return 'spoke'
}

function Get-RuleSyncProposalPath {
    # One pending proposal file per machine; the hub drains daily.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][string]$Machine
    )
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
    $isRule = $norm -like 'universal/claude-rules/*'
    if (-not ($isLaw -or $isRule)) { return $false }
    return Test-Path (Join-Path $GrimdexRoot ($norm -replace '/', '\'))
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
    $abs = Join-Path $GrimdexRoot ($p.target -replace '/', '\')
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
