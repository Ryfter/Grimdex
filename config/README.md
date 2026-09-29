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
| `grimdex-mode.json` | Rules-file mode (`classic` \| `agents`) + dev root. Asked on first run; `setup.ps1 -Mode` switches. Never seeded from an example. |
| `publish-scrub.json` | **Private.** Your identifiers: replacements, deny and allow patterns for the public-engine scrubber. `publish-engine.ps1` refuses to run without it. Never seeded, never mirrored. |

**Tracked, public-safe:** `engine-manifest.json` — which files reach the public engine
(sync / engine_owned / examples / never). Publish only via
`pwsh scripts/publish-engine.ps1 -EngineRoot <engine checkout>`; `-InstallHook` adds the
pre-push leak gate there.

**Starting points:** first-run `setup.ps1` offers each missing file from the engine's
`examples/operator-setup/` (a real operator's setup, scrubbed) or the plain
`*.example.json` (`-Examples operator|plain|skip`).

Keep machine-specific hostnames, API keys, and ceilings out of any repo you
intend to share or publish. The public **Grimdex-engine** ships `*.example.json`
and the scrubbed `examples/operator-setup/` only; your private data repo holds the real
`config/*.json` files.
