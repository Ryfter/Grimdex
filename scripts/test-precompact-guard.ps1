Set-StrictMode -Version Latest
. "$PSScriptRoot/precompact-lib.ps1"

$script:fail = 0
function Assert($label, $cond) {
    if ($cond) { Write-Host "  PASS: $label" -ForegroundColor Green }
    else { Write-Host "  FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function New-TempDir {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ("cg_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}
function Initialize-Repo($dir) {
    git -C $dir -c init.defaultBranch=main init -q
    git -C $dir config user.email 'test@example.com' | Out-Null
    git -C $dir config user.name  'Test'             | Out-Null
    git -C $dir config commit.gpgsign false          | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'a.txt') -Value 'hello' -Encoding UTF8
    git -C $dir add -A | Out-Null
    git -C $dir commit -q -m 'init' | Out-Null
}

$cleanup = @()
$guard = Join-Path $PSScriptRoot 'precompact-guard.ps1'

Write-Host "Get-CloseoutStatus"

# clean repo
$clean = New-TempDir; $cleanup += $clean; Initialize-Repo $clean
$sc = Get-CloseoutStatus -RepoRoot $clean
Assert "clean repo -> IsRepo true"  ($sc.IsRepo -eq $true)
Assert "clean repo -> Clean true"   ($sc.Clean  -eq $true)

# dirty worktree
$dirty = New-TempDir; $cleanup += $dirty; Initialize-Repo $dirty
Set-Content -LiteralPath (Join-Path $dirty 'b.txt') -Value 'uncommitted' -Encoding UTF8
$sd = Get-CloseoutStatus -RepoRoot $dirty
Assert "dirty repo -> not Clean"        ($sd.Clean -eq $false)
Assert "dirty repo -> Uncommitted > 0"  ($sd.Uncommitted -ge 1)
Assert "dirty repo -> Reason set"       ($null -ne $sd.Reason)

# ahead of upstream (unpushed commit)
$ahead = New-TempDir; $cleanup += $ahead; Initialize-Repo $ahead
$bare = New-TempDir; $cleanup += $bare
git -C $bare init --bare -q | Out-Null
git -C $ahead remote add origin $bare | Out-Null
git -C $ahead push -u origin main -q 2>$null | Out-Null
Set-Content -LiteralPath (Join-Path $ahead 'c.txt') -Value 'new' -Encoding UTF8
git -C $ahead add -A | Out-Null
git -C $ahead commit -q -m 'ahead' | Out-Null
$sa = Get-CloseoutStatus -RepoRoot $ahead
Assert "ahead repo -> not Clean"       ($sa.Clean -eq $false)
Assert "ahead repo -> Unpushed >= 1"   ($sa.Unpushed -ge 1)

# non-repo path -> fail-safe allow
$plain = New-TempDir; $cleanup += $plain
$sp = Get-CloseoutStatus -RepoRoot $plain
Assert "non-repo -> IsRepo false"  ($sp.IsRepo -eq $false)
Assert "non-repo -> Clean (allow)" ($sp.Clean  -eq $true)

# nonexistent path -> allow
$sn = Get-CloseoutStatus -RepoRoot (Join-Path ([System.IO.Path]::GetTempPath()) 'no_such_dir_xyz')
Assert "missing path -> Clean (allow)" ($sn.Clean -eq $true)

Write-Host "precompact-guard.ps1 (hook exit codes)"

function Invoke-Guard($jsonStdin) {
    $jsonStdin | pwsh -NoProfile -File $guard | Out-Null
    return $LASTEXITCODE
}
Assert "clean repo -> exit 0 (allow)"  ((Invoke-Guard (@{ cwd = $clean } | ConvertTo-Json -Compress)) -eq 0)
Assert "dirty repo -> exit 2 (block)"  ((Invoke-Guard (@{ cwd = $dirty } | ConvertTo-Json -Compress)) -eq 2)
Assert "ahead repo -> exit 2 (block)"  ((Invoke-Guard (@{ cwd = $ahead } | ConvertTo-Json -Compress)) -eq 2)
Assert "non-repo -> exit 0 (allow)"    ((Invoke-Guard (@{ cwd = $plain } | ConvertTo-Json -Compress)) -eq 0)
Assert "garbled stdin -> exit 0 (allow)" ((Invoke-Guard 'not json at all') -eq 0)

foreach ($d in $cleanup) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }

if ($script:fail) { Write-Host "`n$script:fail FAILED" -ForegroundColor Red; exit 1 }
else { Write-Host "`nAll passed" -ForegroundColor Green }
