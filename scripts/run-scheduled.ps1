#!/usr/bin/env pwsh
<#
  Scheduled-task entry point: runs Claude Code headless against a routine playbook.
  Invoked by the Grimdex-Daily-Sweep / Grimdex-Weekly-Audit scheduled tasks.
  Transcript goes to logs/ (gitignored); the durable record is the committed logs
  (KB-AUDIT-LOG.md, PROMOTIONS-LOG.md) the routine itself writes.
#>
param([Parameter(Mandatory)][ValidateSet('sweep', 'audit')][string]$Kind)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# Label the console and place it on a secondary display when one exists, so a
# 5:30 am routine window is self-explaining and off the primary working screen.
. (Join-Path $PSScriptRoot 'console-lib.ps1')
Set-GrimdexConsoleWindow -Display 1 `
    -Title "Grimdex — scheduled $Kind routine (Claude, Task Scheduler) — $root" | Out-Null
$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$logFile = Join-Path $logs "$(Get-Date -Format 'yyyy-MM-dd-HHmmss')-$Kind.log"

"[$(Get-Date -Format o)] run-scheduled started (kind=$Kind, pid=$PID)" | Set-Content $logFile
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
    "[$(Get-Date -Format o)] claude CLI not found on PATH; aborting." | Add-Content $logFile
    exit 1
}
"[$(Get-Date -Format o)] using claude at $($claude.Source)" | Add-Content $logFile

Set-Location $root
$prompt = "Read universal/playbooks/$Kind.md and follow it exactly. You are the scheduled $Kind routine; work in $root; be terse."
# Tool allow rules live in the repo's committed .claude/settings.json — passing them
# via --allowedTools breaks on Windows arg quoting (rules arrive with literal quotes).
& claude -p $prompt --permission-mode acceptEdits *>&1 | Tee-Object -FilePath $logFile -Append
"[$(Get-Date -Format o)] claude exited with $LASTEXITCODE" | Add-Content $logFile
exit $LASTEXITCODE
