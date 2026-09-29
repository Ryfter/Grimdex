#!/usr/bin/env bash
# One-command scheduling for macOS — launchd port of install-schedule.ps1.
#
# The hub registers two LaunchAgents:
#   com.grimdex.daily-sweep   -> run-scheduled.sh sweep   (daily   05:30)
#   com.grimdex.weekly-audit  -> run-scheduled.sh audit   (Sunday  05:30)
# A spoke registers nothing here (its daily pull rides the sync path).
# Idempotent; safe to re-run.
#
#   scripts/install-schedule.sh              # auto-detect role from config/sync.json
#   scripts/install-schedule.sh --role hub   # force hub
#   scripts/install-schedule.sh --uninstall  # remove all Grimdex LaunchAgents
#
# launchd note: StartCalendarInterval coalesces a missed fire and runs once on the
# next wake — the closest equivalent to Task Scheduler's -StartWhenAvailable.
# scripts/audit-staleness-check.py is the backstop for longer gaps.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
la="$HOME/Library/LaunchAgents"
role=""
uninstall=0

while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="${2:-}"; shift 2 ;;
    --uninstall) uninstall=1; shift ;;
    -h | --help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

labels=(com.grimdex.daily-sweep com.grimdex.weekly-audit)

remove_all() {
  for l in "${labels[@]}"; do
    launchctl unload "$la/$l.plist" 2>/dev/null || true
    if [ -f "$la/$l.plist" ]; then rm -f "$la/$l.plist"; echo "  removed     $l"; else echo "  absent      $l"; fi
  done
}

if [ "$uninstall" -eq 1 ]; then
  remove_all
  exit 0
fi

this_host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
hub=""
if [ -z "$role" ]; then
  hub="$(/usr/bin/python3 -c 'import json,sys
try:
    print((json.load(open(sys.argv[1])).get("hub") or "").strip())
except Exception:
    print("")' "$root/config/sync.json" 2>/dev/null || true)"
  shopt -s nocasematch
  if [ -n "$hub" ] && [[ "$hub" == "$this_host" ]]; then role="hub"; else role="spoke"; fi
  shopt -u nocasematch
fi

echo "  host: $this_host   hub in config/sync.json: ${hub:-<unset>}   role: $role"

if [ "$role" != "hub" ]; then
  echo "  spoke -> no local sweep/audit LaunchAgents registered."
  echo "  (this machine is the hub? set config/sync.json hub to \"$this_host\", or re-run with --role hub)"
  exit 0
fi

mkdir -p "$la" "$root/logs"
runner="$root/scripts/run-scheduled.sh"
chmod +x "$runner"

write_plist() {
  # $1 label   $2 kind   $3 weekday (empty => daily)
  local label="$1" kind="$2" weekday="${3:-}"
  local weekday_line=""
  if [ -n "$weekday" ]; then
    weekday_line="        <key>Weekday</key><integer>${weekday}</integer>"$'\n'
  fi
  cat > "$la/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${runner}</string>
        <string>${kind}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
${weekday_line}        <key>Hour</key><integer>5</integer>
        <key>Minute</key><integer>30</integer>
    </dict>
    <key>RunAtLoad</key><false/>
    <key>StandardOutPath</key><string>${root}/logs/launchd-${kind}.out.log</string>
    <key>StandardErrorPath</key><string>${root}/logs/launchd-${kind}.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLIST
  launchctl unload "$la/$label.plist" 2>/dev/null || true
  launchctl load "$la/$label.plist"
  echo "  registered  $label"
}

write_plist com.grimdex.daily-sweep  sweep ""
write_plist com.grimdex.weekly-audit audit 0

echo "  done. verify:  launchctl list | grep grimdex"
