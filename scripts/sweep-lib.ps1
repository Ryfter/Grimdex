#!/usr/bin/env pwsh
# Grimdex sweep library — mechanical layer of the daily sweep / weekly audit (d002).
# The semantic layer lives in universal/playbooks/sweep.md and audit.md.
Set-StrictMode -Version Latest

$script:GrimdexLogTopMarker = '<!-- grimdex:log-top -->'

function Get-GrimdexMarkdownFiles {
    # Skips machine dirs (.git/.claude/.index/logs) and any `archive/` subtree —
    # archived snapshots are intentionally frozen and must not raise link/id findings.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    Get-ChildItem -Path $GrimdexRoot -Recurse -File -Filter *.md |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.claude|\.index|logs|archive)[\\/]' }
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
    $rows = foreach ($f in Get-ChildItem $inbox -Filter *.md |
        Where-Object { $_.Name -ne 'README.md' -and $_.Name -notlike '*.sync.md' }) {
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
                    # Report the slug WITHOUT [[ ]] so this finding text doesn't itself
                    # get re-flagged when it lands in KB-AUDIT-LOG.md next run.
                    New-GrimdexFinding -Check 'wikilinks' -Severity info -Path $f.FullName `
                        -Message "dangling wikilink: '$slug' — use a backticked name for auto-memory / out-of-repo refs, or <!-- forward-ref --> if intentional"
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
    # A stale candidate (>$MaxDays) with NO disposition in PROMOTIONS-LOG.md means the
    # loop is broken (warn) -- one that already has a logged DEFERRED/ACCEPTED/REJECTED
    # entry there is consciously tracked, awaiting the >=2-project clock, not backlog
    # (info). Without this split every deliberately-retained candidate re-warns forever,
    # which trains you to stop reading the sweep (2026-09-10).
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [int]$MaxDays = 7
    )
    $logPath = Join-Path $GrimdexRoot 'universal' 'PROMOTIONS-LOG.md'
    $log = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { '' }
    $findings = foreach ($row in Get-GrimdexInboxStatus -GrimdexRoot $GrimdexRoot) {
        if ($row.oldestDays -le $MaxDays) { continue }
        $dispositioned = $log -and [regex]::IsMatch($log,
            "(?ms)^##[^\n]*—\s*(DEFERRED|ACCEPTED|REJECTED)[^\n]*\n(?:(?!^## ).)*?\*\*From:\*\*\s*projects/$([regex]::Escape($row.project))\b")
        if ($dispositioned) {
            New-GrimdexFinding -Check 'inbox-stale' -Severity info -Path $row.file `
                -Message "candidate(s) from $($row.project) pending $($row.oldestDays) days (max $MaxDays) -- already logged in PROMOTIONS-LOG.md, retained for the 2nd-project clock"
        } else {
            New-GrimdexFinding -Check 'inbox-stale' -Severity warn -Path $row.file `
                -Message "candidate(s) from $($row.project) pending $($row.oldestDays) days (max $MaxDays) -- no disposition found in PROMOTIONS-LOG.md, loop may be broken"
        }
    }
    return @($findings)
}

function Test-GrimdexStaleLeases {
    # Reaps expired decision-number leases (grimdex-d042) across every project tier
    # and surfaces what it found. Deliberately shells out to the POSIX sh script
    # rather than reimplementing the O_EXCL claim/reap logic in pwsh (grimdex-d043:
    # pwsh is not the language of choice for the fragile mechanical layer).
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $script = Join-Path $GrimdexRoot 'scripts' 'decision-lease.sh'
    if (-not (Test-Path $script)) { return @() }
    $out = & sh $script reap-all 2>$null
    $findings = foreach ($line in $out) {
        if ($line -match '^reaped: (\S+) \(age ([^,]+), project (\S+)\)') {
            New-GrimdexFinding -Check 'stale-lease' -Severity info `
                -Path "projects/$($Matches[3])/decisions/.leases" `
                -Message "reaped expired decision-number lease $($Matches[1]) (age $($Matches[2]))"
        } elseif ($line -match '^stale-warning: (\S+) \(age ([^,]+), project (\S+)\)') {
            New-GrimdexFinding -Check 'stale-lease' -Severity info `
                -Path "projects/$($Matches[3])/decisions/.leases" `
                -Message "live decision-number lease $($Matches[1]) is $($Matches[2]) old -- may indicate a dead session"
        }
    }
    return @($findings)
}

function Get-GrimdexCompiledCheckBinary {
    # Builds (or reuses a cached build of) scripts/grimdex-check -- the Go port
    # of the five checks below (grimdex-d044). Cache lives in a git-ignored
    # .bin/ dir, keyed by source mtime so an edit to any .go file triggers a
    # rebuild. Returns $null (never throws) if `go` isn't on PATH and no cached
    # binary exists -- callers must treat that as "fall back to pwsh", not an
    # error: a missing Go toolchain on some host must never be a hard sweep
    # failure (that would trade one single point of failure for another).
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $srcDir = Join-Path $GrimdexRoot 'scripts' 'grimdex-check'
    if (-not (Test-Path (Join-Path $srcDir 'go.mod'))) { return $null }
    $binDir = Join-Path $srcDir '.bin'
    $bin = Join-Path $binDir 'grimdex-check'
    $goFiles = Get-ChildItem $srcDir -Filter '*.go' -ErrorAction SilentlyContinue
    $newestSrc = ($goFiles | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    $stale = -not (Test-Path $bin) -or ((Get-Item $bin).LastWriteTimeUtc -lt $newestSrc)
    if ($stale) {
        if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
            return $(if (Test-Path $bin) { $bin } else { $null })  # use a stale-but-present binary over none
        }
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        # `-C $srcDir` (Go 1.20+): go's module resolution is based on the
        # process's cwd, NOT the package path argument -- without -C this
        # fails with "cannot find main module" whenever pwsh's cwd is outside
        # scripts/grimdex-check (i.e. always, when called from the repo root).
        & go build '-C' $srcDir -o $bin . 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bin)) {
            return $(if (Test-Path $bin) { $bin } else { $null })
        }
    }
    return $bin
}

function Invoke-GrimdexCompiledChecks {
    # Runs the Go binary's `checks` subcommand and parses its JSONL into the
    # same Finding shape New-GrimdexFinding produces. Returns $null (not an
    # empty array) on any failure so the caller can tell "ran, found nothing"
    # apart from "couldn't run" -- collapsing those would silently hide a
    # broken toolchain as a clean sweep.
    param([Parameter(Mandatory)][string]$GrimdexRoot, [Parameter(Mandatory)][string]$Binary)
    $out = & $Binary checks $GrimdexRoot 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $findings = foreach ($line in $out) {
        if (-not $line.Trim()) { continue }
        $obj = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($obj) { [pscustomobject]@{ check = $obj.check; severity = $obj.severity; path = $obj.path; message = $obj.message } }
    }
    return @($findings)
}

function Invoke-GrimdexMechanicalChecks {
    # Prefers the compiled Go port (grimdex-d044) of the five checks below --
    # falls back to the original pwsh implementations if `go` isn't available
    # and no cached binary exists, or if the binary errors. The pwsh functions
    # are kept, not deleted: they are the fallback, not dead code.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $bin = Get-GrimdexCompiledCheckBinary -GrimdexRoot $GrimdexRoot
    $compiled = if ($bin) { Invoke-GrimdexCompiledChecks -GrimdexRoot $GrimdexRoot -Binary $bin } else { $null }
    if ($null -ne $compiled) {
        return @($compiled) + @(Test-GrimdexStaleLeases -GrimdexRoot $GrimdexRoot)
    }
    @(
        Test-GrimdexLinks -GrimdexRoot $GrimdexRoot
        Test-GrimdexWikilinks -GrimdexRoot $GrimdexRoot
        Test-GrimdexDecisionIds -GrimdexRoot $GrimdexRoot
        Test-GrimdexRepoState -GrimdexRoot $GrimdexRoot
        Test-GrimdexInboxStaleness -GrimdexRoot $GrimdexRoot
        Test-GrimdexStaleLeases -GrimdexRoot $GrimdexRoot
    )
}

function Sync-GrimdexRepo {
    # pull --rebase, then push (one rebase-and-retry on a push race). -SkipPush for
    # read-only runs. -Autostash stashes a dirty tree across the rebase. Never forces;
    # a rebase conflict surfaces as a throw.
    param(
        [Parameter(Mandatory)][string]$GrimdexRoot,
        [switch]$SkipPush,
        [switch]$Autostash
    )
    [string[]]$auto = if ($Autostash) { '--autostash' } else { }
    git -C $GrimdexRoot pull --rebase --quiet @auto 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git pull --rebase failed in $GrimdexRoot" }
    if ($SkipPush) { return [pscustomobject]@{ pulled = $true; pushed = $false } }
    git -C $GrimdexRoot push --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        git -C $GrimdexRoot pull --rebase --quiet @auto 2>&1 | Out-Null
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
