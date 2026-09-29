#!/usr/bin/env pwsh
<#
  Mirror the engine-bound files to the public engine checkout, scrubbed, and check that
  nothing personal remains. Never commits or pushes.

    pwsh scripts/publish-engine.ps1 -EngineRoot ~/Dev/Grimdex-engine              # dry run: report only
    pwsh scripts/publish-engine.ps1 -EngineRoot ~/Dev/Grimdex-engine -Apply       # write the files
    pwsh scripts/publish-engine.ps1 -EngineRoot ~/Dev/Grimdex-engine -ScanOnly    # leak scan of the engine tree
    pwsh scripts/publish-engine.ps1 -EngineRoot ~/Dev/Grimdex-engine -InstallHook # pre-push gate

  Needs config/publish-scrub.json (private) and config/engine-manifest.json.
  Exit 0 = clean; 1 = leaks or refused files.
#>
param(
    [Parameter(Mandatory)][string]$EngineRoot,
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Apply,
    [switch]$ScanOnly,
    [switch]$PrePush,
    [switch]$InstallHook
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'publish-lib.ps1')
if ($EngineRoot.StartsWith('~')) { $EngineRoot = Join-Path $HOME $EngineRoot.Substring(1).TrimStart('/', '\') }

function Show-Leaks($leaks) {
    foreach ($l in $leaks) { Write-Host ("  LEAK  {0}:{1}  [{2}]  {3}" -f $l.path, $l.line, $l.kind, $l.match) -ForegroundColor Red }
}

$cfg = Get-GrimdexScrubConfig -GrimdexRoot $GrimdexRoot

if ($InstallHook) {
    $h = Install-GrimdexEnginePrePush -EngineRoot $EngineRoot -GrimdexRoot $GrimdexRoot
    Write-Host "  pre-push gate installed: $h" -ForegroundColor Green
    exit 0
}

if ($ScanOnly) {
    # -PrePush: git's pre-push stdin names the pushed ranges; scan those (history + tip).
    $leaks = @(if ($PrePush) {
        $refLines = @([Console]::In.ReadToEnd() -split "`r?`n" | Where-Object { $_ })
        Find-GrimdexPushLeaks -Root $EngineRoot -Config $cfg -RefLines $refLines
    } else { Find-GrimdexTreeLeaks -Root $EngineRoot -Config $cfg })
    if ($leaks.Count) {
        Write-Host "Grimdex publish gate: $($leaks.Count) personal reference(s) in $EngineRoot — push blocked." -ForegroundColor Red
        Show-Leaks $leaks
        exit 1
    }
    Write-Host 'Grimdex publish gate: engine tree is clean.' -ForegroundColor Green
    exit 0
}

$man = Get-GrimdexEngineManifest -GrimdexRoot $GrimdexRoot
$plan = Get-GrimdexPublishPlan -GrimdexRoot $GrimdexRoot -EngineRoot $EngineRoot -Config $cfg -Manifest $man
foreach ($group in $plan.items | Group-Object action | Sort-Object Name) {
    Write-Host ("{0} ({1})" -f $group.Name, $group.Count)
    if ($group.Name -ne 'unchanged') {
        foreach ($it in $group.Group) { Write-Host ("  {0}{1}" -f $it.dest, $(if ($it.note) { "  — $($it.note)" } else { '' })) }
    }
}
$refused = @($plan.items | Where-Object action -eq 'refused')
if ($plan.leaks.Count) { Write-Host "`n$($plan.leaks.Count) leak(s):" -ForegroundColor Red; Show-Leaks $plan.leaks }

if ($Apply) {
    if ($plan.leaks.Count -or $refused.Count) {
        Write-Host "`nNot applied: fix the leaks/refusals first (add replacements to config/publish-scrub.json or edit the source)." -ForegroundColor Red
        exit 1
    }
    $written = @(Invoke-GrimdexPublish -Plan $plan -EngineRoot $EngineRoot)
    Write-Host "`nWrote $($written.Count) file(s) into $EngineRoot. Review with git diff there; commit and push are yours." -ForegroundColor Green
}
if ($plan.leaks.Count -or $refused.Count) { exit 1 }
exit 0
