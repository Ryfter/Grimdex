#!/usr/bin/env bash
# Scheduled-routine entry point — macOS launchd port of run-scheduled.ps1.
# Runs Claude Code headless against a routine playbook. The transcript goes to
# logs/ (gitignored); the durable record is the committed logs the routine itself
# writes (KB-AUDIT-LOG.md, PROMOTIONS-LOG.md).
set -uo pipefail

kind="${1:?usage: run-scheduled.sh <sweep|audit>}"
case "$kind" in
  sweep | audit) ;;
  *) echo "kind must be 'sweep' or 'audit'" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
logs="$root/logs"
mkdir -p "$logs"
logfile="$logs/$(date +%Y-%m-%d-%H%M%S)-$kind.log"

echo "[$(date -u +%FT%TZ)] run-scheduled started (kind=$kind, pid=$$)" > "$logfile"

claude_bin="$(command -v claude || true)"
if [ -z "$claude_bin" ] && [ -x "$HOME/.local/bin/claude" ]; then
  claude_bin="$HOME/.local/bin/claude"
fi
if [ -z "$claude_bin" ]; then
  echo "[$(date -u +%FT%TZ)] claude CLI not found on PATH; aborting." | tee -a "$logfile" >&2
  exit 1
fi
echo "[$(date -u +%FT%TZ)] using claude at $claude_bin" >> "$logfile"

cd "$root"
prompt="Read universal/playbooks/$kind.md and follow it exactly. You are the scheduled $kind routine; work in $root; be terse."

# Tool allow rules live in the repo's committed .claude/settings.json.
"$claude_bin" -p "$prompt" --permission-mode acceptEdits >> "$logfile" 2>&1 && rc=0 || rc=$?
echo "[$(date -u +%FT%TZ)] claude exited with $rc" >> "$logfile"
exit "$rc"
