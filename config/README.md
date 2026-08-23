# config — tool-specific configuration backups

Harness/tool config snapshots live here, isolated so the knowledge itself stays
tool-neutral. Ships examples only; your instance fills the real files.

## Instance files (copy from `*.example.json` or use `setup.ps1`)

| File | Purpose |
|---|---|
| `operator-network.json` | How dev servers bind/announce (localhost vs LAN vs Tailscale). First-run prompt in `setup.ps1`. |
| `fleet.json` | Labor-split worker roster (`fleet.example.json`) |
| `quota.json` | Usage ceilings (`quota.example.json`) |
| `learn-progress.json` | Learn-mode progress (`learn-progress.example.json`) |
| `sync.json` | Multi-machine hub/spoke role |

Keep machine-specific hostnames, API keys, and ceilings out of any repo you
intend to share or publish. The public **Grimdex-engine** ships `*.example.json`
only; private `grimdex-know` may hold the real `config/*.json` files.
