#!/usr/bin/env pwsh
<#
  Record a model's availability by hand in config/models.json (grimdex-d052).
  AtomicKestrel, when installed, writes these records itself ('kes models sync').

  One model:

    pwsh scripts/set-model-availability.ps1 -Name codex -State scarce -Window weekly -ValidUntil 2026-10-03T00:00:00Z -Detail 'weekly pool 62% used'

  Every model on one provider, by `invoke` — for a credit that ran out or a provider that went
  down. With -SkipFree the models whose `offer.free` is true are left alone, which is the
  Command Code case: the free ones don't spend GOAT credit, so parking the credit shouldn't
  park them. The names of a provider's models move (stealth models come and go), so this keys
  on `invoke`, never on a hand-written list of names.

    pwsh scripts/set-model-availability.ps1 -Invoke cli:cmd -State out -SkipFree -Window monthly -ValidUntil 2026-11-01T00:00:00Z -Detail 'GOAT $70 spent'

  Without -SkipFree the whole provider goes out, free models included. -Name is not accepted
  with -Invoke; use one or the other.
#>
[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByName')][string]$Name,
    [Parameter(Mandatory, ParameterSetName = 'ByInvoke')][string]$Invoke,
    [Parameter(Mandatory)][ValidateSet('available', 'scarce', 'out', 'unknown')][string]$State,
    [ValidateSet('5h', 'weekly', 'monthly', 'none')][string]$Window = 'none',
    [string]$ValidUntil,
    [string]$Detail,
    [switch]$SkipFree,
    [string]$GrimdexRoot = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'models-lib.ps1')
if ($PSCmdlet.ParameterSetName -eq 'ByInvoke') {
    $changed = @(Set-GrimdexAvailabilityByInvoke -GrimdexRoot $GrimdexRoot -Invoke $Invoke -State $State `
        -Window $Window -ValidUntil $ValidUntil -Detail $Detail -SkipFree:$SkipFree)
    if ($changed.Count) {
        $until = if ($ValidUntil) { ", valid until $ValidUntil" } else { '' }
        Write-Host ("{0} model(s) via {1} -> {2}{3}: {4}" -f $changed.Count, $Invoke, $State, $until, ($changed -join ', '))
    }
    else { Write-Host "no model in config/models.json is reached by invoke '$Invoke' (after -SkipFree); nothing written" }
    exit 0
}
$rec = Set-GrimdexAvailability -GrimdexRoot $GrimdexRoot -Name $Name -State $State -Window $Window -ValidUntil $ValidUntil -Detail $Detail
Write-Host ("{0}: {1} (as of {2}, window {3}{4})" -f $Name, $rec.state, $rec.as_of, $rec.window, $(if ($rec.PSObject.Properties['valid_until']) { ", valid until $($rec.valid_until)" } else { '' }))
