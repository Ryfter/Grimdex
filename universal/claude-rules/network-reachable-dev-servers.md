# Network-reachable dev servers

When the **operator's browser** is not on the same machine as the dev server,
`127.0.0.1` / `localhost` URLs are wrong — they only work on the box that is
listening. This is a standing seating rule, not a preference.

**Instance profile:** `config/operator-network.json` (created on first
`pwsh setup.ps1` run, or copy from `config/operator-network.example.json`).
Agents must read it before starting or announcing HTTP dev servers.

## Is LAN binding harder than localhost?

**No — usually one flag.** Vite/Next/uvicorn/FastAPI/etc. accept
`--host 0.0.0.0` or equivalent. That is the whole bind change.

What actually breaks remote operators is **announcing localhost** after binding
correctly, or forgetting the profile exists. Capture hostnames once in setup;
agents print the right URL every time.

## Modes (from `operator-network.json`)

| Mode | When | Bind | Announce |
|---|---|---|---|
| `localhost-only` | Browser on the same machine as the server | `127.0.0.1` OK | `http://127.0.0.1:<port>/` |
| `lan` | Another device on the home/office LAN | `0.0.0.0` | `http://<lan-hostname>:<port>/` |
| `lan+tailnet` | Also work off-LAN via Tailscale (or similar) | `0.0.0.0` | LAN hostname **and** tailnet MagicDNS name |

Prefer **hostname over raw IP** (IPs rot). Raw IP is fallback only.

## Bind

- **`lan` / `lan+tailnet`:** bind **`0.0.0.0`** (all interfaces), never
  `127.0.0.1` alone.
- Map framework flags: Vite `server.host`, uvicorn `--host`, Flask
  `host='0.0.0.0'`, etc.

## Announce (URL handed to the operator)

Use the profile's `announce` block:

| Path | URL pattern |
|---|---|
| Home LAN | `http://<lan.hostname>:<port>/` |
| Office / off-LAN (tailnet) | `http://<tailnet.hostname>.<tailnet.magic_dns_suffix>:<port>/` |

When MagicDNS search domain is enabled, the short tailnet hostname often works
too: `http://<tailnet.hostname>:<port>/`.

**Do** print these URLs in start logs, README smoke lines, and agent reports.
**Do not** hand `localhost` when `announce.localhost_ok` is `false`.
**Do not** default to SSH tunnels when LAN or tailnet already reach the host.

## First-run setup (`setup.ps1`)

If `config/operator-network.json` is missing, `setup.ps1` asks:

1. **Same machine?** — If yes → `localhost-only` (done).
2. **More than one PC / remote browser?** — If yes → need LAN binding.
3. **Tailscale (or tailnet VPN)?** — If yes → collect MagicDNS hostname +
   tailnet suffix (`*.ts.net`). If no → `lan` mode only.

Re-run anytime: `pwsh setup.ps1 -ConfigureNetwork`

## Quick checks

```bash
# listening on all interfaces?
lsof -nP -iTCP:<port> -sTCP:LISTEN
# want *:PORT or 0.0.0.0:PORT when mode is lan or lan+tailnet
```

## Evidence

Promoted from operator pain (browser on a different machine than the factory
host). Instance configs hold hostnames; this rule stays generic.
