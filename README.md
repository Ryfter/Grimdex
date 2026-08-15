# Grimdex

**The Grimoire Index for coding** — a tool-agnostic, file-first knowledge base for AI
pair programming. One markdown repo holds your programming decisions, rules, and
lessons; every AI coding agent you use (Claude Code, Codex, Gemini, GitHub Copilot,
Cursor, local models) reads it before working and records what it learns back into it.
A scheduled "librarian" routine keeps it **"aggressively maintained"**.

> **Expectation-setting:** this is an early, experimental personal project, published
> because the pattern is useful — not a turnkey product. Windows + PowerShell 7 first;
> the conventions are portable, the scripts currently are not.

## The idea

- **`GRIMDEX.md` is the law** — the only file agents always read. Kept deliberately
  tiny. Everything situational lives in `universal/playbooks/` and loads only at its
  moment (starting a project, compacting a session, ending a project).
- **Decisions are the product.** Every significant choice becomes a decision record —
  what was chosen, the alternatives, the reasoning — in that project's tier under
  `projects/<id>/`. See `examples/`.
- **Rules earn their way in.** Cross-project rules are *proposed* into a staging inbox
  (`universal/promotions/`). A daily sweep (a headless agent session on a scheduler)
  conflict-checks candidates against the law and two append-only ledgers:
  `PROMOTIONS-LOG.md` (past admissions/rejections) and `RIPPEDPAGES.md` (everything
  ever removed, with the why). Clean additions auto-inscribe with a full paper trail;
  conflicts and removals always wait for the human.
- **Every tool is a contributor.** `wire-project.ps1` injects a marked pointer block
  into a repo's `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `GROK.md`, `.cursorrules`, and
  `.github/copilot-instructions.md`, so whatever agent opens the project finds the
  knowledge base and the contribution rule.
- **Cold-start seeding.** Rules normally earn their way in through observed failures —
  a fresh instance has none yet. [SUGGESTED-RULES.md](SUGGESTED-RULES.md) carries
  seven community-converged conventions (each independently advocated by 3+ prominent
  practitioners), the reasoning behind each, and a paste-into-your-agent prompt that
  files them through the normal promotions inbox.
- **Multi-machine consistency.** Run one knowledge base across several machines via a
  hub-and-spoke, single-writer model: a designated hub is the only writer of rules/law;
  spokes pull read-only and propose edits with `scripts/propose-rule.ps1` (filed as a
  `rule-sync` proposal in `universal/promotions/`), which the hub reviews and publishes
  with `scripts/review-rule-proposals.ps1`. GitHub is the exchange — no merge conflicts
  on shared rules by construction.
- **Model labor-split.** Route each task to the right worker for your rig — bulk builds
  to your highest-capacity coder, reviews to your strongest model, docs to your cheapest —
  via a `config/fleet.json` policy and a tested selector (`scripts/fleet-lib.ps1`). Includes
  a user-invoked multi-model "full counsel" cross-review. See
  [labor-split.md](universal/playbooks/labor-split.md).
- **Learn mode.** An optional teaching layer: the agent narrates the *why* and defines the
  jargon as it works, so a learner builds real vocabulary. A surfacing ledger
  (`scripts/learn-lib.ps1` + a transcript parser) tapers each term deterministically — full
  definition, then a reminder, then only occasionally — so it fades instead of nagging. See
  [learn-mode.md](universal/playbooks/learn-mode.md).
- **Compaction safety.** A `PreCompact` hook (`scripts/precompact-guard.ps1`) blocks a
  conversation compaction while work is uncommitted or unpushed, so context is never
  compressed before the closeout runs. Fail-safe: it only ever blocks on a confirmed
  unsaved-work signal. See [compact-guard.md](universal/playbooks/compact-guard.md).

## Where Grimdex sits — the three-layer ecosystem

Grimdex governs **how** coding work is done. Two sibling layers cover the rest:
**Grimlore** (optional) remembers **why/who/context**, and **Grimdex Baton** decides
**what happens next** and executes it. Grimdex resists bloat precisely *because* those
layers exist to take what doesn't belong here.

The authoritative brief — the Law, definitions, boundary tests, promotion policy, and the
list of assumptions to discard — is
[`docs/2026-08-14-grimdex-ecosystem-architecture.md`](docs/2026-08-14-grimdex-ecosystem-architecture.md).
Grimlore's opening design draft is
[`docs/2026-08-14-grimlore-spec.md`](docs/2026-08-14-grimlore-spec.md) (spec only —
nothing built yet).

**Boundary test, in one line:** changes *how* work is done → Grimdex. Explains *why/who* →
Grimlore. Makes something *happen* → Baton.

## Quick start

```powershell
git clone https://github.com/Ryfter/Grimdex.git
pwsh Grimdex\setup.ps1                      # verify structure, report state
pwsh Grimdex\scripts\wire-project.ps1 -ProjectDir <your-project>
pwsh Grimdex\scripts\install-schedule.ps1   # optional: daily sweep + weekly audit
```

Your knowledge accumulates in `projects/` and `universal/` — **keep your instance
repo private**; it will contain your decision history and preferences. This public
repo is the engine/template only.

Requirements: PowerShell 7+, git. The scheduled routines additionally expect a
headless-capable AI CLI (built against [Claude Code](https://claude.com/claude-code));
everything else is plain files. Tests: `pwsh scripts/test-<area>.ps1` (10 suites).

## Layout

See [GRIMDEX.md](GRIMDEX.md) — it is the canonical description, and the file your
agents read first.

MIT licensed.
