# Grimdex — the Grimoire Index for coding

Grimdex is a standalone, **tool-agnostic, file-first** coding knowledge base. Markdown +
frontmatter is the floor: any agent — Claude, Codex, Gemini, Copilot, Cursor, local
models — or plain `git` + grep can read and contribute. No server required.

**If you are an AI coding agent: this file is the law — the only always-read file.**
Everything below holds in every session. Anything that only matters at a specific
moment lives in a playbook (see the routing table). This file ships as a **template**:
the owner's instance grows its own rules here via the maintained loop.

## Where Grimdex sits — the rules layer of a three-layer harness

Grimdex owns exactly one of three questions. The other two belong elsewhere:

| **Grimdex** — the rules layer | **Grimlore** — the context layer | **Baton** — the action layer |
|---|---|---|
| conventions · lessons · rules | design · rationale · history | orchestrate · execute · route |
| schemas · gates · standards | environment · user · company | build · test · verify · deploy |
| validation · security guidance | audience · hardware · models | agents · models · workflows |
| project rules → universal rules | research · project knowledge | |
| ***How*** work is done | ***Why*** / ***who*** / context | ***What*** next, and ***when*** |
| **this repo** | optional — *not built yet* | <https://github.com/Ryfter/baton> |

**Boundary test:** changes *how* future work is done → **Grimdex**. Explains
*why / who / context* → **Grimlore**. Must *happen* → **Baton**.
*Grimdex prescribes. Grimlore explains. Baton acts.*

⚑ **[PROVISIONAL] — everything above that depends on Grimlore** (law #7's exception).
Grimlore does not exist yet, so it cannot have earned its place by evidence; these rules
were dictated because the framework cannot be built without them. **Earns permanence
when** Grimlore holds real content and an agent has retrieved from it in practice.
Grimdex's and Baton's roles here are *not* provisional — both exist and are evidenced.

**Bloat is the enemy of Grimdex** — that is why the other two layers exist. Useful context
can still be the wrong *kind* of information for this repo.

⚠️ **"Rules layer" is Grimdex's *position*, not its contents.** Inside this layer are the
decisions, lessons, and artifacts that **back the rules up** — it is not a flat list of
rules. Law #1 stands, and law #7 requires it: a rule stripped of its evidence is an
assertion. A decision record's **Rationale** is the *why behind a rule* and belongs here;
Grimlore holds the *why behind the work* — project purpose, audience, environment. Do not
read "rules layer" as "rules only."

**A layer is defined by the question it answers, not the nouns it touches** — so the same
noun can appear in more than one column:

- **models** span all three. *What is it?* (roster, availability, characteristics) →
  **Grimlore**. *What are the rules for using it?* (spend ceilings, permitted tier per
  stakes, what may never leave the box) → **Grimdex**. *How do I use it?* (selection,
  routing, flags, retries) → **Baton**. Grimdex writes the spend rule; **Baton enforces it
  at dispatch** — the governor and the meter are runtime machinery and stay there.
- **gates · standards · validation** sit here while **test · verify** sit in Baton —
  Grimdex defines the gate, Baton runs it (law #2).
- **project rules → universal rules** is *both* two content types *and* the gate between
  them: a project rule is content in its own tier until the gate is tripped and it becomes
  a universal rule. Grimlore has the same two-tier-plus-promotion shape.

Grimdex and Baton are mutually independent: each works fully without the other, and both
work without Grimlore. Full brief:
[`docs/2026-08-14-grimdex-ecosystem-architecture.md`](docs/2026-08-14-grimdex-ecosystem-architecture.md).

## The law

1. **Programming decisions, rules, and lessons are recorded HERE — not in app repos.**
   Decision records: `projects/<project-id>/decisions/dNNN-<slug>.md` (next free number;
   frontmatter `id, timestamp, project, status, confidence, revisit-if`; body **Chosen /
   Alternatives / Rationale / Feedback** — see `examples/`). Guidance and lessons:
   `projects/<project-id>/decision-guidance.md`. App repos reference decisions by id
   — never duplicate the record.
   **Ids are project-qualified: `<prefix>-dNNN`** (e.g. `baton-d107`, `grimdex-d022`).
   Numbers are assigned per tier, so a bare `dNNN` is ambiguous across projects. The
   prefix is the project-id, or the short alias in `projects/<id>/.prefix` when that id
   is long (`canvas-toolchain` → `canvas`); prefixes must be unique. **Filenames stay
   bare `dNNN-<slug>.md`** — the folder namespaces the file, the prefix namespaces the
   *reference*. Bare `dNNN` is acceptable only inside that project's own tier.
   All id types in this ecosystem: [`docs/id-conventions.md`](docs/id-conventions.md).
2. **Grimdex holds portable coding knowledge only** — decisions, rules, and lessons any
   tool can use. Three things route elsewhere: **runtime machinery** and the user's own
   cost/speed *stance* stay in the owning tool; **durable context** that explains why/who
   but prescribes nothing goes to **Grimlore** `[PROVISIONAL]` — including the hardware
   and model *inventory*; an application's **subject-matter** knowledge stays with the
   application.
   The line is the verb: a *constraint* is Grimdex's ("low-stakes work may not exceed the
   economy tier"), the *inventory* it references is Grimlore's ("these models exist, at
   these prices"), and the *mechanism* that enforces it at dispatch is Baton's. Grimdex
   writes the rule; it never holds the meter.
3. **Write to your own project's tier.** Cross-project rules are not edited directly:
   propose them as candidates in `universal/promotions/<project-id>.md` (see the inbox
   README). The sweep — not you — inscribes them into this file.
4. **This file changes only through the maintained loop:** clean additions via the
   sweep with a `universal/PROMOTIONS-LOG.md` entry; removals only human-gated, with a
   `RIPPEDPAGES.md` entry. Never silently.
   **A law outranks a decision record.** Laws are global and have stood the test of time;
   decision records are project-scoped and revisable. Where the two conflict, the law
   governs. A decision may *inform* a law change only by travelling this route — never by
   contradicting one from a project tier. (Which is why law ids stay unqualified `#N`
   while decision ids are project-qualified — the form encodes the scope.)
5. **Back up everything:** commit and push before a session ends. Sync before you write
   (`git pull --rebase`) — multiple agents may share this repo.
6. **Keep your instance private** — it will hold personal decision history and
   preferences. (This engine repo is the public template; your data never lives here.)
7. **Rules trace to evidence, then escalate to enforcement.** Every rule must cite an
   observed failure or success — never write rules from anticipation (unfollowed rules
   are noise that erodes adherence to the real ones). A rule still being violated
   despite emphasis gets converted into something deterministic — a script, hook,
   gate, or CI check — not more prose. Suggested starter rules: `SUGGESTED-RULES.md`.
   **Exception — provisional laws.** A new framework cannot produce evidence before it
   exists, yet it cannot function until its governing rules do. Such a rule may be
   admitted **provisionally**: maintainer-dictated (never an agent), reserved for
   structural change (a new layer, a redrawn boundary), marked `[PROVISIONAL]`, stating
   the condition that earns it permanence, and ledgered like any admission. **It binds
   exactly like a permanent law** — the mark describes its *evidence*, not its *force*.
   The audit flags any provisional law whose condition has been met (confirm it) or
   whose framework still does not exist after two cycles (reconsider it): *provisional*
   must never quietly become permanent. Ordinary rules get no such exemption.
8. **Stamp model provenance at every closeout.** Run `pwsh scripts/stamp-model.ps1` at the
   compact/sprint seam to record which `runner/model` did the step: it appends to
   `projects/<id>/model-usage.md` and self-registers the model in
   `universal/model-catalog.md`. Why: a model change can later invalidate work built with
   it; the weekly audit flags the dependent steps — but only if provenance was recorded.
9. **Be brutally honest when queried — challenge the rules, don't flatter them.** When
   asked to evaluate a rule, decision, or line of reasoning — *especially one the asker
   authored* — surface its weaknesses plainly. No flattery, no performative agreement. A
   knowledge base that ratifies weak reasoning to please its owner is the opposite of a
   place quality comes from: rules are stress-tested whenever they're questioned, not only
   when they're added. Reasoning is always stated; evidence need not always be a metric —
   a decision worked through in the open is legitimate even when it can't be quantified —
   but it is never simply assumed.

## Routing table — when to read what

| Moment | Read |
|---|---|
| Creating/starting a new project | `universal/playbooks/project-start.md` |
| Compacting a conversation (closeout + state report) | `universal/playbooks/compact.md` |
| Ending/finalizing a project | `universal/playbooks/project-end.md` |
| Splitting work across models/tools (the labor-split) | `universal/playbooks/labor-split.md` |
| Teaching a learner as you code (learn mode + taper) | `universal/playbooks/learn-mode.md` |
| Enforcing save-before-compact (the closeout-guard hook) | `universal/playbooks/compact-guard.md` |
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
- `scripts/` + `setup.ps1` — setup, wiring, sweep, scheduling, model-stamp (PowerShell 7+). Wire a
  project with `pwsh scripts/wire-project.ps1 -ProjectDir <dir>` (idempotent marked
  block in CLAUDE.md / AGENTS.md / GEMINI.md / GROK.md / .cursorrules / copilot-instructions).
- `config/` — tool-specific configuration backups, isolated so the knowledge itself
  stays tool-neutral.

## Maintenance

Disciplined sweep, not auto-churn: **read-only audit** → **graduated autonomy**
(automation may add clean rules with a full ledger trail; it may never rewrite or
remove — those wait for the human) → **incremental** (only what changed). The law never
drifts without a human gate.
