Set-StrictMode -Version Latest

# precompact-lib.ps1 — the closeout-state check behind the PreCompact hook.
# Pure-ish: inspects a git repo and reports whether the closeout ran (nothing uncommitted,
# nothing unpushed). No writes. Fail-safe by construction: anything it can't determine
# (missing git, not a repo, bad path) reports Clean=$true so the guard never blocks a compact
# on a false signal.

function Get-CloseoutStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $result = [pscustomobject]@{
        IsRepo = $false; Clean = $true; Uncommitted = 0; Unpushed = 0; Reason = $null
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $result }
    if (-not $RepoRoot -or -not (Test-Path -LiteralPath $RepoRoot)) { return $result }

    $inside = & git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or "$inside" -ne 'true') { return $result }
    $result.IsRepo = $true

    $porcelain = & git -C $RepoRoot status --porcelain 2>$null
    $result.Uncommitted = @($porcelain | Where-Object { $_ -and $_.Trim() }).Count

    # Unpushed only counts when an upstream exists; a branch with no upstream can't be judged
    # (fail-safe: 0), so it never blocks purely for lack of a remote.
    $upstream = & git -C $RepoRoot rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstream) {
        $ahead = & git -C $RepoRoot rev-list --count '@{u}..HEAD' 2>$null
        if ($LASTEXITCODE -eq 0 -and $ahead) { $result.Unpushed = [int]$ahead }
    }

    if ($result.Uncommitted -gt 0 -or $result.Unpushed -gt 0) {
        $result.Clean = $false
        $repoName = Split-Path $RepoRoot -Leaf
        $parts = @()
        if ($result.Uncommitted -gt 0) { $parts += "$($result.Uncommitted) uncommitted file(s)" }
        if ($result.Unpushed -gt 0)    { $parts += "$($result.Unpushed) unpushed commit(s)" }
        $result.Reason = "Closeout not complete before compact: '$repoName' has " +
            ($parts -join ' and ') +
            ". Save off (commit/push, capture decisions, update memory), then compact again."
    }
    return $result
}
