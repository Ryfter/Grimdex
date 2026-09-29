# Grimdex quota sensor — statusline snippet.
#
# Claude Code hands the statusline a JSON payload on stdin that includes
# rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}. The statusline
# normally prints and discards it. This snippet also persists it so Grimdex can
# read live Claude usage without any external dependency.
#
# Install: paste into your statusline script AFTER `input` holds the stdin JSON.
# Requires: jq.
#
# The sensor file is deliberately outside any synced or mirrored directory —
# usage data reveals plan details and must not travel with the knowledge base.

grimdex_sensor="$HOME/.claude/grimdex-quota-statusline.json"
grimdex_rl=$(echo "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$grimdex_rl" ]; then
  mkdir -p "$(dirname "$grimdex_sensor")"
  # Write via a temp file so a concurrent reader never sees a half-written file.
  # Use PID for uniqueness to protect against concurrent writers.
  grimdex_tmp="${grimdex_sensor}.tmp.$$"
  printf '%s' "$grimdex_rl" > "$grimdex_tmp" 2>/dev/null &&
    mv -f "$grimdex_tmp" "$grimdex_sensor" 2>/dev/null
  rm -f "$grimdex_tmp" 2>/dev/null
fi
