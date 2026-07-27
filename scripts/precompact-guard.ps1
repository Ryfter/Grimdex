#requires -Version 7
Set-StrictMode -Version Latest

# precompact-guard.ps1 — Claude Code PreCompact hook entry point.
# Reads the hook JSON on stdin, resolves the git repo at `cwd`, and blocks the compaction
# (exit 2 + {"decision":"block","reason":...}) when a closeout is still pending — so context
# is never compressed with uncommitted/unpushed work. Fires on both /compact and auto-compact.
# Fail-safe: any error, missing/garbled input, or non-repo path -> exit 0 (allow), never wedge.
#
# Wiring (settings.json, hooks.PreCompact):
#   { "type": "command",
#     "command": "pwsh -NoProfile -File \"<grimdex>/scripts/precompact-guard.ps1\"" }

. "$PSScriptRoot/precompact-lib.ps1"

try {
    $raw = [Console]::In.ReadToEnd()
    $cwd = $null
    if ($raw -and $raw.Trim()) {
        try {
            $j = $raw | ConvertFrom-Json
            if ($j.PSObject.Properties['cwd']) { $cwd = [string]$j.cwd }
        } catch { exit 0 }   # garbled stdin -> allow
    }
    if (-not $cwd) { $cwd = (Get-Location).Path }

    $status = Get-CloseoutStatus -RepoRoot $cwd
    if ($status.Clean) { exit 0 }

    (@{ decision = 'block'; reason = $status.Reason } | ConvertTo-Json -Compress)
    exit 2
} catch {
    exit 0
}
