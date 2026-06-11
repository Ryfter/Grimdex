#!/usr/bin/env pwsh
# Grimdex setup library — junction state + safe swap (see docs/2026-06-10-bootstrap-spec.md §1)
Set-StrictMode -Version Latest

function Test-GrimdexRoot {
    # A valid Grimdex root has the front-door file and is a git repo.
    param([Parameter(Mandatory)][string]$Root)
    (Test-Path (Join-Path $Root 'GRIMDEX.md')) -and (Test-Path (Join-Path $Root '.git'))
}

function Get-GrimdexJunctionState {
    # Classifies $KnowledgePath relative to $Target: missing | linked | linked-elsewhere | real-dir
    param(
        [Parameter(Mandatory)][string]$KnowledgePath,
        [Parameter(Mandatory)][string]$Target
    )
    if (-not (Test-Path $KnowledgePath)) { return 'missing' }
    $item = Get-Item $KnowledgePath -Force
    if ($item.LinkType -ne 'Junction') { return 'real-dir' }
    $resolvedTarget = (Resolve-Path $Target).Path.TrimEnd('\')
    $linkTarget = ([string]$item.Target).TrimEnd('\')
    if ($linkTarget -ieq $resolvedTarget) { return 'linked' } else { return 'linked-elsewhere' }
}

function Sync-GrimdexRules {
    <#
      Redeploys the mirrored global rules (universal/claude-rules/*.md) to the live
      rules dir. Grimdex is the source of truth, but a live file that differs from its
      mirror is never silently overwritten: it is reported as a conflict and skipped
      unless -Force. Missing live files are deployed; identical ones are left alone.
      When the rules junction (v2, Install-GrimdexRulesJunction) is live, there is
      nothing to copy — the live dir IS the mirror — and a single 'linked' row returns.
    #>
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [string]$RulesPath = (Join-Path $HOME '.claude' 'rules'),
        [switch]$Force
    )
    $mirror = Join-Path $GrimdexRoot 'universal' 'claude-rules'
    if (-not (Test-Path $mirror)) { return @() }
    if ((Get-GrimdexJunctionState -KnowledgePath $RulesPath -Target $mirror) -eq 'linked') {
        return ,([pscustomobject]@{ rule = '(all)'; action = 'linked' })
    }
    if (-not (Test-Path $RulesPath)) { New-Item -ItemType Directory -Force -Path $RulesPath | Out-Null }
    $results = foreach ($src in Get-ChildItem $mirror -Filter *.md) {
        $dst = Join-Path $RulesPath $src.Name
        # compare EOL-insensitively: git autocrlf rewrites the mirror's line endings
        $same = (Test-Path $dst) -and
            (((Get-Content $src.FullName -Raw) -replace "`r`n", "`n") -eq ((Get-Content $dst -Raw) -replace "`r`n", "`n"))
        $action =
            if (-not (Test-Path $dst)) { 'deployed' }
            elseif ($same) { 'unchanged' }
            elseif ($Force) { 'overwritten' }
            else { 'conflict-skipped' }
        if ($action -in 'deployed', 'overwritten') { Copy-Item $src.FullName $dst -Force }
        [pscustomobject]@{ rule = $src.Name; action = $action }
    }
    return $results
}

function Install-GrimdexRulesJunction {
    <#
      Rules migration v2: replaces the live rules dir with a junction to the Grimdex
      mirror (universal/claude-rules) so rules are SERVED from Grimdex — one physical
      file set, no sync, no drift. Safety (real-dir case): every live *.md must match
      its mirror EOL-insensitively and have a mirror counterpart, and no non-md files
      or subdirs may be present (-Force overrides all three). The old dir is kept as
      "<RulesPath>.bak" (never overwritten); rolls back on any failure.
    #>
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [string]$RulesPath = (Join-Path $HOME '.claude' 'rules'),
        [switch]$Force
    )
    if (-not (Test-GrimdexRoot -Root $GrimdexRoot)) {
        throw "Not a valid Grimdex root (needs GRIMDEX.md + .git): $GrimdexRoot"
    }
    $mirror = Join-Path $GrimdexRoot 'universal' 'claude-rules'
    if (-not (Test-Path $mirror -PathType Container)) {
        throw "Rules mirror missing: $mirror. Nothing to serve rules from."
    }
    $state = Get-GrimdexJunctionState -KnowledgePath $RulesPath -Target $mirror
    switch ($state) {
        'linked' { return [pscustomobject]@{ state = 'linked'; action = 'none'; backup = $null } }
        'linked-elsewhere' {
            $existing = (Get-Item $RulesPath -Force).Target
            throw "$RulesPath is already a junction to a different target: $existing. Refusing to touch it."
        }
        'missing' {
            New-Item -ItemType Junction -Path $RulesPath -Target $mirror | Out-Null
            return [pscustomobject]@{ state = 'linked'; action = 'created'; backup = $null }
        }
    }

    # real-dir: content-equality gate (the rules dir is not a repo, so compare per file)
    $backup = "$RulesPath.bak"
    if (Test-Path $backup) {
        throw "Backup path already exists: $backup. Remove or rename it first; this script never overwrites a backup."
    }
    if (-not $Force) {
        $problems = @(foreach ($live in Get-ChildItem $RulesPath -File -Filter *.md) {
            $src = Join-Path $mirror $live.Name
            if (-not (Test-Path $src)) { "$($live.Name): no mirror counterpart" }
            elseif (((Get-Content $src -Raw) -replace "`r`n", "`n") -ne ((Get-Content $live.FullName -Raw) -replace "`r`n", "`n")) {
                "$($live.Name): content differs from mirror"
            }
        })
        $problems += @(Get-ChildItem $RulesPath -File | Where-Object Extension -ne '.md' |
            ForEach-Object { "$($_.Name): non-md file, not mirrored" })
        $problems += @(Get-ChildItem $RulesPath -Directory |
            ForEach-Object { "subdir '$($_.Name)' not mirrored" })
        $problems = @($problems | Where-Object { $_ })
        if ($problems.Count) {
            throw "Live rules diverge from the mirror — reconcile first (Sync-GrimdexRules / update the mirror), or pass -Force (the dir is kept as .bak): $($problems -join '; ')"
        }
    }

    Rename-Item -Path $RulesPath -NewName (Split-Path $backup -Leaf)
    try {
        New-Item -ItemType Junction -Path $RulesPath -Target $mirror | Out-Null
        if (-not (Get-ChildItem $RulesPath -Filter *.md | Select-Object -First 1)) {
            throw 'Junction verification failed: no rule files readable through the junction.'
        }
    } catch {
        if (Test-Path $RulesPath) { (Get-Item $RulesPath -Force).Delete() }
        Rename-Item -Path $backup -NewName (Split-Path $RulesPath -Leaf)
        throw "Rules junction swap failed and was rolled back: $($_.Exception.Message)"
    }
    return [pscustomobject]@{ state = 'linked'; action = 'swapped'; backup = $backup }
}

function Install-GrimdexJunction {
    <#
      Replaces $KnowledgePath with a junction to $Target.
      Safety (real-dir case): tree must be clean (no override), HEADs must match
      (-Force overrides), backup path must not already exist. Renames the old dir to
      "$KnowledgePath.bak" and keeps it; rolls back on any failure.
    #>
    param(
        [Parameter(Mandatory)][string]$KnowledgePath,
        [Parameter(Mandatory)][string]$Target,
        [switch]$Force
    )
    if (-not (Test-GrimdexRoot -Root $Target)) {
        throw "Target is not a valid Grimdex root (needs GRIMDEX.md + .git): $Target"
    }
    $state = Get-GrimdexJunctionState -KnowledgePath $KnowledgePath -Target $Target
    switch ($state) {
        'linked' { return [pscustomobject]@{ state = 'linked'; action = 'none'; backup = $null } }
        'linked-elsewhere' {
            $existing = (Get-Item $KnowledgePath -Force).Target
            throw "$KnowledgePath is already a junction to a different target: $existing. Refusing to touch it."
        }
        'missing' {
            New-Item -ItemType Junction -Path $KnowledgePath -Target $Target | Out-Null
            return [pscustomobject]@{ state = 'linked'; action = 'created'; backup = $null }
        }
    }

    # real-dir: full swap protocol
    $backup = "$KnowledgePath.bak"
    if (Test-Path $backup) {
        throw "Backup path already exists: $backup. Remove or rename it first; this script never overwrites a backup."
    }
    if (Test-Path (Join-Path $KnowledgePath '.git')) {
        $dirty = git -C $KnowledgePath status --porcelain
        if ($LASTEXITCODE -ne 0) { throw "git status failed in $KnowledgePath" }
        if ($dirty) { throw "$KnowledgePath has uncommitted changes. Commit/push them first; dirty trees are never swapped." }
        $srcHead = git -C $KnowledgePath rev-parse HEAD
        $dstHead = git -C $Target rev-parse HEAD
        if ($srcHead -ne $dstHead -and -not $Force) {
            throw "HEAD mismatch: $KnowledgePath=$srcHead vs $Target=$dstHead. Sync them first, or pass -Force if the target is intentionally ahead."
        }
    } elseif (-not $Force) {
        throw "$KnowledgePath is not a git repo, so content equality cannot be verified. Pass -Force to swap anyway (the dir is kept as .bak)."
    }

    Rename-Item -Path $KnowledgePath -NewName (Split-Path $backup -Leaf)
    try {
        New-Item -ItemType Junction -Path $KnowledgePath -Target $Target | Out-Null
        if (-not (Test-Path (Join-Path $KnowledgePath 'GRIMDEX.md'))) {
            throw 'Junction verification failed: GRIMDEX.md not readable through the junction.'
        }
    } catch {
        if (Test-Path $KnowledgePath) { (Get-Item $KnowledgePath -Force).Delete() }
        Rename-Item -Path $backup -NewName (Split-Path $KnowledgePath -Leaf)
        throw "Junction swap failed and was rolled back: $($_.Exception.Message)"
    }
    return [pscustomobject]@{ state = 'linked'; action = 'swapped'; backup = $backup }
}
