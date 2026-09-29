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
    # Windows uses a junction; macOS/Linux have no junctions, so a directory symlink is the equivalent.
    if ($item.LinkType -notin 'Junction', 'SymbolicLink') { return 'real-dir' }
    $resolvedTarget = (Resolve-Path $Target).Path.TrimEnd('\', '/')
    $linkTarget = ([string]$item.Target).TrimEnd('\', '/')
    if ($linkTarget -ieq $resolvedTarget) { return 'linked' } else { return 'linked-elsewhere' }
}

function New-GrimdexLink {
    # Junction on Windows (no admin needed); directory symlink elsewhere.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Target)
    $type = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $type -Path $Path -Target $Target | Out-Null
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
            New-GrimdexLink -Path $RulesPath -Target $mirror
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
        New-GrimdexLink -Path $RulesPath -Target $mirror
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
            New-GrimdexLink -Path $KnowledgePath -Target $Target
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
        New-GrimdexLink -Path $KnowledgePath -Target $Target
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

# --- Operator network profile (dev-server bind/announce) ---

function Get-OperatorNetworkConfigPath {
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    Join-Path $GrimdexRoot 'config' 'operator-network.json'
}

function Get-OperatorNetworkConfig {
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Get-OperatorNetworkConfigPath -GrimdexRoot $GrimdexRoot
    if (-not (Test-Path $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    } catch {
        throw "config/operator-network.json is malformed JSON: $($_.Exception.Message)"
    }
}

function Save-OperatorNetworkConfig {
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [Parameter(Mandatory)][object]$Config
    )
    $path = Get-OperatorNetworkConfigPath -GrimdexRoot $GrimdexRoot
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($Config | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    return $path
}

function New-OperatorNetworkConfig {
    param(
        [Parameter(Mandatory)][bool]$OperatorBrowserOnServer,
        [string]$LanHostname = '',
        [bool]$TailnetEnabled = $false,
        [string]$TailnetHostname = '',
        [string]$MagicDnsSuffix = ''
    )
    if ($OperatorBrowserOnServer) {
        return [ordered]@{
            mode                         = 'localhost-only'
            operator_browser_on_server   = $true
            bind                         = 'loopback'
            announce                     = [ordered]@{
                localhost_ok = $true
                home_lan     = $null
                tailnet      = [ordered]@{ enabled = $false }
            }
            notes = 'Browser on the server — localhost URLs are fine.'
        }
    }
    $mode = if ($TailnetEnabled) { 'lan+tailnet' } else { 'lan' }
    $tailHost = if ($TailnetHostname) { $TailnetHostname } else { $LanHostname }
    $notes = "Home LAN: http://${LanHostname}:<port>/"
    if ($TailnetEnabled -and $MagicDnsSuffix) {
        $notes += " — Office (tailnet): http://${tailHost}.${MagicDnsSuffix}:<port>/"
    }
    return [ordered]@{
        mode                         = $mode
        operator_browser_on_server   = $false
        bind                         = 'all-interfaces'
        announce                     = [ordered]@{
            localhost_ok = $false
            home_lan     = [ordered]@{ hostname = $LanHostname }
            tailnet      = [ordered]@{
                enabled            = [bool]$TailnetEnabled
                hostname           = $tailHost
                magic_dns_suffix   = $(if ($TailnetEnabled) { $MagicDnsSuffix } else { $null })
            }
        }
        notes = $notes
    }
}

function Initialize-OperatorNetworkConfig {
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [switch]$Reconfigure,
        [switch]$NonInteractive
    )
    $path = Get-OperatorNetworkConfigPath -GrimdexRoot $GrimdexRoot
    if ((Test-Path $path) -and -not $Reconfigure) {
        return [pscustomobject]@{ action = 'exists'; path = $path }
    }
    if ($NonInteractive -and -not $Reconfigure) {
        return [pscustomobject]@{
            action = 'skipped'
            path   = $path
            reason = 'non-interactive and no profile yet — copy config/operator-network.example.json'
        }
    }

    Write-Host ''
    Write-Host '  Operator network profile (dev-server URLs)' -ForegroundColor Cyan
    Write-Host '  Browsers on another machine cannot open http://127.0.0.1 — bind 0.0.0.0 and'
    Write-Host '  announce a hostname instead. LAN bind is usually one extra flag (--host 0.0.0.0).'
    Write-Host ''

    $sameMachine = (Read-Host '  Is your browser usually on THIS machine? [y/N]') -match '^[Yy]'
    if ($sameMachine) {
        $cfg = New-OperatorNetworkConfig -OperatorBrowserOnServer $true
        Save-OperatorNetworkConfig -GrimdexRoot $GrimdexRoot -Config $cfg | Out-Null
        return [pscustomobject]@{ action = 'created'; path = $path; mode = 'localhost-only' }
    }

    Write-Host '  Remote browser → bind all interfaces (0.0.0.0), not loopback only.'
    $defaultHost = try { [System.Net.Dns]::GetHostName() } catch { 'dev-box' }
    $lanHost = Read-Host "  LAN hostname for this server [$defaultHost]"
    if ([string]::IsNullOrWhiteSpace($lanHost)) { $lanHost = $defaultHost }

    $useTailnet = (Read-Host '  Use Tailscale (or another tailnet VPN) for off-LAN access? [y/N]') -match '^[Yy]'
    $tailHost = $lanHost
    $suffix = ''
    if ($useTailnet) {
        $tailHost = Read-Host "  Tailnet MagicDNS hostname [$lanHost]"
        if ([string]::IsNullOrWhiteSpace($tailHost)) { $tailHost = $lanHost }
        $suffix = Read-Host '  Tailnet DNS suffix (e.g. example.ts.net)'
        while ([string]::IsNullOrWhiteSpace($suffix)) {
            Write-Host '  Suffix required when tailnet is enabled (find it in the Tailscale admin DNS page).'
            $suffix = Read-Host '  Tailnet DNS suffix'
        }
    }

    $cfg = New-OperatorNetworkConfig -OperatorBrowserOnServer $false `
        -LanHostname $lanHost -TailnetEnabled:$useTailnet `
        -TailnetHostname $tailHost -MagicDnsSuffix $suffix
    Save-OperatorNetworkConfig -GrimdexRoot $GrimdexRoot -Config $cfg | Out-Null
    $mode = if ($useTailnet) { 'lan+tailnet' } else { 'lan' }
    return [pscustomobject]@{ action = 'created'; path = $path; mode = $mode }
}

# --- Seeded example configs (spec 2026-09-28 Part A) ---

function Initialize-GrimdexExampleConfigs {
    <#
      Offers a starting point for each instance config that is missing. Candidates are
      config/<name>.example.json (plain, generic) and examples/operator-setup/<name>.json
      (a scrubbed copy of a real operator's setup, shipped by the engine). Existing configs
      are never touched. -Choice operator falls back to plain when no operator example exists.
    #>
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [ValidateSet('operator', 'plain', 'skip')][string]$Choice,
        [switch]$NonInteractive,
        # Never seeded: the mode is asked for by setup itself, and a copied scrub config
        # would silently defeat the publish scrubber's fail-closed check.
        [string[]]$Exclude = @('grimdex-mode.json', 'publish-scrub.json')
    )
    $configDir = Join-Path $GrimdexRoot 'config'
    if (-not (Test-Path $configDir -PathType Container)) { return }
    $opDir = Join-Path $GrimdexRoot 'examples' 'operator-setup'
    $names = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($f in Get-ChildItem $configDir -Filter '*.example.json' -File) { [void]$names.Add(($f.Name -replace '\.example\.json$', '.json')) }
    if (Test-Path $opDir) { foreach ($f in Get-ChildItem $opDir -Filter '*.json' -File) { [void]$names.Add($f.Name) } }

    foreach ($x in $Exclude) { [void]$names.Remove($x) }
    $missing = @($names | Where-Object { -not (Test-Path (Join-Path $configDir $_)) })
    if (-not $Choice -and $missing.Count) {
        if ($NonInteractive) { $Choice = 'skip' }
        else {
            Write-Host "  Missing instance configs: $($missing -join ', ')"
            $hasOp = Test-Path $opDir
            $prompt = if ($hasOp) { '  Start from [o]perator example setup (modelled on a real rig), [p]lain examples, or [s]kip? [s]' } else { '  Start from [p]lain examples, or [s]kip? [s]' }
            $a = Read-Host $prompt
            $Choice = if ($hasOp -and $a -match '^[Oo]') { 'operator' } elseif ($a -match '^[Pp]') { 'plain' } else { 'skip' }
        }
    }
    foreach ($n in $names) {
        $dest = Join-Path $configDir $n
        if (Test-Path $dest) { [pscustomobject]@{ name = $n; action = 'exists' }; continue }
        $op = Join-Path $opDir $n
        $plain = Join-Path $configDir ($n -replace '\.json$', '.example.json')
        $action = 'skipped'
        if ($Choice -eq 'operator' -and (Test-Path $op)) { Copy-Item $op $dest; $action = 'copied-operator' }
        elseif ($Choice -in 'operator', 'plain' -and (Test-Path $plain)) { Copy-Item $plain $dest; $action = 'copied-plain' }
        [pscustomobject]@{ name = $n; action = $action }
    }
}
