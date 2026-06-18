# Grimdex — the Grimoire Index for coding

Grimdex is a standalone, **tool-agnostic, file-first** coding knowledge base. Markdown +
frontmatter is the floor: any agent — Claude, Codex, Gemini, Copilot, Cursor, local
models — or plain `git` + grep can read and contribute. No server required.

**If you are an AI coding agent: this file is the law — the only always-read file.**
Everything below holds in every session. Anything that only matters at a specific
moment lives in a playbook (see the routing table). This file ships as a **template**:
the owner's instance grows its own rules here via the maintained loop.

## The law

1. **Programming decisions, rules, and lessons are recorded HERE — not in app repos.**
   Decision records: `projects/<project-id>/decisions/dNNN-<slug>.md` (next free number;
   frontmatter `id, timestamp, project, status, confidence, revisit-if`; body **Chosen /
   Alternatives / Rationale / Feedback** — see `examples/`). Guidance and lessons:
   `projects/<project-id>/decision-guidance.md`. App repos reference decisions by id
   (e.g. `d012`) — never duplicate the record.
2. **Grimdex holds portable coding knowledge only** — decisions, rules, and lessons any
   tool can use. Tool-operational knowledge that models the user or their machine
   (cost/speed stance, hardware inventory, advisory logic) stays in the owning tool.
3. **Write to your own project's tier.** Cross-project rules are not edited directly:
   propose them as candidates in `universal/promotions/<project-id>.md` (see the inbox
   README). The sweep — not you — inscribes them into this file.
4. **This file changes only through the maintained loop:** clean additions via the
   sweep with a `universal/PROMOTIONS-LOG.md` entry; removals only human-gated, with a
   `RIPPEDPAGES.md` entry. Never silently.
5. **Back up everything:** commit and push before a session ends. Sync before you write
   (`git pull --rebase`) — multiple agents may share this repo.
6. **Keep your instance private** — it will hold personal decision history and
   preferences. (This engine repo is the public template; your data never lives here.)
7. **Rules trace to evidence, then escalate to enforcement.** Every rule must cite an
   observed failure or success — never write rules from anticipation (unfollowed rules
   are noise that erodes adherence to the real ones). A rule still being violated
   despite emphasis gets converted into something deterministic — a script, hook,
   gate, or CI check — not more prose. Suggested starter rules: `SUGGESTED-RULES.md`.

## Routing table — when to read what

| Moment | Read |
|---|---|
| Creating/starting a new project | `universal/playbooks/project-start.md` |
| Compacting a conversation (closeout + state report) | `universal/playbooks/compact.md` |
| Ending/finalizing a project | `universal/playbooks/project-end.md` |
| Running the daily consolidation sweep | `universal/playbooks/sweep.md` |
| Running the weekly KB audit | `universal/playbooks/audit.md` |

## Layout

- `projects/<project-id>/` — per-project tier: decisions, guidance, logs. New project =
  new folder; nothing else to register.
- `universal/` — the cross-project shelf: playbooks, the promotions inbox + ledger, and
  whatever reference docs the instance accumulates. **Promotion-gated:** a rule enters
  the law only with evidence from ≥2 projects, via the sweep — never directly.
- `RIPPEDPAGES.md` / `KB-AUDIT-LOG.md` (root) — removals ledger and health log.
- `universal/model-catalog.md` + `projects/<id>/model-usage.md` — model provenance: what
  ran each step (stamped at closeout) so the audit can flag work a model change may affect.
- `scripts/` + `setup.ps1` — setup, wiring, sweep, scheduling (PowerShell 7+). Wire a
  project with `pwsh scripts/wire-project.ps1 -ProjectDir <dir>` (idempotent marked
  block in CLAUDE.md / AGENTS.md / GEMINI.md / .cursorrules / copilot-instructions).
- `config/` — tool-specific configuration backups, isolated so the knowledge itself
  stays tool-neutral.

## Maintenance

Disciplined sweep, not auto-churn: **read-only audit** → **graduated autonomy**
(automation may add clean rules with a full ledger trail; it may never rewrite or
remove — those wait for the human) → **incremental** (only what changed). The law never
drifts without a human gate.
