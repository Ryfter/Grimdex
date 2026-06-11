#!/usr/bin/env pwsh
# Grimdex sweep library — mechanical layer of the daily sweep / weekly audit (d002).
# The semantic layer lives in universal/playbooks/sweep.md and audit.md.
Set-StrictMode -Version Latest

$script:GrimdexLogTopMarker = '<!-- grimdex:log-top -->'

function Get-GrimdexMarkdownFiles {
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    Get-ChildItem -Path $GrimdexRoot -Recurse -File -Filter *.md |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.claude|\.index|logs)[\\/]' }
}

function New-GrimdexFinding {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('info', 'warn')][string]$Severity,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message
    )
    [pscustomobject]@{ check = $Check; severity = $Severity; path = $Path; message = $Message }
}

function Get-GrimdexInboxStatus {
    # One row per project candidate file in universal/promotions/ (README excluded).
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $inbox = Join-Path $GrimdexRoot 'universal' 'promotions'
    if (-not (Test-Path $inbox)) { return @() }
    $rows = foreach ($f in Get-ChildItem $inbox -Filter *.md | Where-Object Name -ne 'README.md') {
        $content = Get-Content $f.FullName -Raw
        $candidates = @([regex]::Matches($content, '(?m)^## ')).Count
        if ($candidates -eq 0) { continue }
        # age from the oldest **Filed:** date when present, else file mtime
        $filed = [regex]::Matches($content, '\*\*Filed:\*\*\s*(\d{4}-\d{2}-\d{2})') |
            ForEach-Object { [datetime]$_.Groups[1].Value } | Sort-Object | Select-Object -First 1
        $oldest = if ($filed) { $filed } else { $f.LastWriteTime }
        [pscustomobject]@{
            file = $f.FullName
            project = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            candidates = $candidates
            oldestDays = [int]((Get-Date) - $oldest).TotalDays
        }
    }
    return @($rows)
}

function Test-GrimdexLinks {
    # Relative markdown links must resolve (warn). External/anchor links are skipped.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $findings = foreach ($f in Get-GrimdexMarkdownFiles -GrimdexRoot $GrimdexRoot) {
        $content = Get-Content $f.FullName -Raw
        foreach ($m in [regex]::Matches($content, '\[[^\]]*\]\(([^)\s]+)\)')) {
            $target = $m.Groups[1].Value
            if ($target -match '^(https?:|mailto:|#)') { continue }
            $target = ($target -split '#')[0] -replace '/', '\'
            if (-not $target) { continue }
            $fromFile = Join-Path (Split-Path $f.FullName -Parent) $target
            $fromRoot = Join-Path $GrimdexRoot $target
            if (-not (Test-Path $fromFile) -and -not (Test-Path $fromRoot)) {
                New-GrimdexFinding -Check 'links' -Severity warn -Path $f.FullName `
                    -Message "dead relative link: ($($m.Groups[1].Value))"
            }
        }
    }
    return @($findings)
}

function Test-GrimdexWikilinks {
    # [[slug]] should match some md file's basename (info when dangling — wikilinks may
    # reference memory entities). Lines tagged <!-- forward-ref --> are intentional.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $files = Get-GrimdexMarkdownFiles -GrimdexRoot $GrimdexRoot
    $basenames = $files | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) }
    $findings = foreach ($f in $files) {
        foreach ($line in (Get-Content $f.FullName)) {
            if ($line -match '<!--\s*forward-ref\s*-->') { continue }
            foreach ($m in [regex]::Matches($line, '\[\[([^\]\|]+)\]\]')) {
                $slug = $m.Groups[1].Value.Trim()
                $hit = $basenames | Where-Object { $_ -eq $slug -or $_ -like "*$slug*" } | Select-Object -First 1
                if (-not $hit) {
                    New-GrimdexFinding -Check 'wikilinks' -Severity info -Path $f.FullName `
                        -Message "dangling wikilink: [[$slug]] (add <!-- forward-ref --> if intentional)"
                }
            }
        }
    }
    return @($findings)
}

function Test-GrimdexDecisionIds {
    # Per project: duplicate dNNN ids are warn; gaps in the sequence are info.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $projects = Join-Path $GrimdexRoot 'projects'
    if (-not (Test-Path $projects)) { return @() }
    $findings = foreach ($proj in Get-ChildItem $projects -Directory) {
        $decisions = Join-Path $proj.FullName 'decisions'
        if (-not (Test-Path $decisions)) { continue }
        $ids = Get-ChildItem $decisions -Filter 'd*.md' |
            ForEach-Object { if ($_.Name -match '^d(\d{3})-') { [int]$Matches[1] } }
        $ids = @($ids)
        if ($ids.Count -eq 0) { continue }
        $dupes = $ids | Group-Object | Where-Object Count -gt 1
        foreach ($d in $dupes) {
            New-GrimdexFinding -Check 'decision-ids' -Severity warn -Path $decisions `
                -Message "duplicate decision id d$('{0:d3}' -f [int]$d.Name) in $($proj.Name)"
        }
        $sorted = $ids | Sort-Object -Unique
        $expected = 1..($sorted[-1])
        $gaps = $expected | Where-Object { $_ -notin $sorted }
        foreach ($g in $gaps) {
            New-GrimdexFinding -Check 'decision-ids' -Severity info -Path $decisions `
                -Message "gap in decision ids: d$('{0:d3}' -f $g) missing in $($proj.Name)"
        }
    }
    return @($findings)
}

function Test-GrimdexRepoState {
    # Dirty tree or unpushed commits are warn — the backup order says always pushed.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $findings = @()
    $dirty = git -C $GrimdexRoot status --porcelain
    if ($LASTEXITCODE -ne 0) {
        return @(New-GrimdexFinding -Check 'repo-state' -Severity warn -Path $GrimdexRoot -Message 'git status failed')
    }
    if ($dirty) {
        $findings += New-GrimdexFinding -Check 'repo-state' -Severity warn -Path $GrimdexRoot `
            -Message "uncommitted changes ($(@($dirty).Count) paths)"
    }
    $ahead = git -C $GrimdexRoot rev-list --count '@{u}..HEAD' 2>$null
    if ($LASTEXITCODE -eq 0 -and [int]$ahead -gt 0) {
        $findings += New-GrimdexFinding -Check 'repo-state' -Severity warn -Path $GrimdexRoot `
            -Message "$ahead unpushed commit(s)"
    }
    return @($findings)
}

function Test-GrimdexInboxStaleness {
    # A candidate older than $MaxDays means the loop is broken (warn).
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [int]$MaxDays = 7
    )
    $findings = foreach ($row in Get-GrimdexInboxStatus -GrimdexRoot $GrimdexRoot) {
        if ($row.oldestDays -gt $MaxDays) {
            New-GrimdexFinding -Check 'inbox-stale' -Severity warn -Path $row.file `
                -Message "candidate(s) from $($row.project) pending $($row.oldestDays) days (max $MaxDays)"
        }
    }
    return @($findings)
}

function Invoke-GrimdexMechanicalChecks {
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    @(
        Test-GrimdexLinks -GrimdexRoot $GrimdexRoot
        Test-GrimdexWikilinks -GrimdexRoot $GrimdexRoot
        Test-GrimdexDecisionIds -GrimdexRoot $GrimdexRoot
        Test-GrimdexRepoState -GrimdexRoot $GrimdexRoot
        Test-GrimdexInboxStaleness -GrimdexRoot $GrimdexRoot
    )
}

function Sync-GrimdexRepo {
    # pull --rebase, then push (one rebase-and-retry on a push race). -SkipPush for
    # read-only runs. Never forces; a rebase conflict surfaces as a throw.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [switch]$SkipPush
    )
    git -C $GrimdexRoot pull --rebase --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git pull --rebase failed in $GrimdexRoot" }
    if ($SkipPush) { return [pscustomobject]@{ pulled = $true; pushed = $false } }
    git -C $GrimdexRoot push --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        git -C $GrimdexRoot pull --rebase --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git pull --rebase (retry) failed in $GrimdexRoot" }
        git -C $GrimdexRoot push --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git push failed twice in $GrimdexRoot" }
    }
    return [pscustomobject]@{ pulled = $true; pushed = $true }
}

function Add-GrimdexLogEntry {
    # Newest-on-top append: insert the entry right below the log-top marker.
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Entry
    )
    $content = Get-Content $LogPath -Raw
    if (-not $content.Contains($script:GrimdexLogTopMarker)) {
        throw "Log file has no '$script:GrimdexLogTopMarker' marker: $LogPath"
    }
    $new = $content.Replace($script:GrimdexLogTopMarker,
        $script:GrimdexLogTopMarker + "`n`n" + $Entry.TrimEnd())
    Set-Content -Path $LogPath -Value $new -NoNewline -Encoding utf8
}
