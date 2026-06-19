# Spec: model provenance tracking

**Date:** 2026-06-18
**Status:** approved (brainstormed with the owner)
**Topic:** record which model/tool+version did each step of the work, so model changes
can later be reconciled against what was built with them.

## Problem

The fleet that contributes to a Grimdex instance is multi-model — Claude Code (Opus
4.8, Sonnet 4.6, Haiku 4.5…), Codex (5.5, 5.4, 5.4-mini, each at a reasoning level),
and local models run under Ollama / LM Studio. Models change. A decision, summary, or
chunk of work produced by one model may warrant a second look once that model is
superseded — but today nothing records *which* model did *which* step, so there is no
way to find the work that a model change might have invalidated.

We want a durable, file-first record of model provenance that any agent can read and
write, consistent with Grimdex's existing conventions (append-only logs, human-gated
judgments, clean-add-vs-judgment split).

## Non-goals

- **No ephemeral "live current model" pointer.** Which model is running *this instant*
  is tool-operational state (GRIMDEX.md law #2 keeps that in the owning tool). We record
  provenance at "done" moments instead, where it becomes knowledge about the work.
- **No auto-watching of external release feeds** for new frontier models.
- **No auto-revising of applications** when a model changes. The maintenance check only
  *flags* superseded work for human review — it never edits anything downstream.

## Design

Three parts: a catalog, a per-project usage log, and wiring into the existing
closeout/audit seams.

### 1. Model-identity schema (shared vocabulary)

Everywhere a model is named, use **`runner/model (params)`**:

- `runner` — the app/harness executing the model: `claude-code`, `codex`, `ollama`,
  `lm-studio`.
- `model` — the model name/tag: `opus-4.8`, `sonnet-4.6`, `codex-5.5`,
  `qwen2.5-coder:32b-q4`.
- `params` — runner-specific knobs, omitted when none. Codex reasoning level is the
  motivating case: `(reasoning:high)` — one of `low | medium | high | xhigh`.

Examples: `claude-code/opus-4.8` · `codex/codex-5.4-mini (reasoning:high)` ·
`ollama/qwen2.5-coder:32b-q4`.

### 2. The model catalog — `universal/model-catalog.md`

One reference file on the cross-project shelf. Two sections, because frontier and local
models behave differently:

- **Frontier** (Claude Code, Codex, …): a small, named, authoritative set. Each entry
  carries a **status** — `current` or `superseded → <successor>` — plus first-seen and
  retired dates. New models are *additions*; superseded ones are marked, never deleted.
- **Local** (Ollama, LM Studio, …): built **bottom-up from observed usage** — there is
  no authoritative "latest" feed. Tracked by `runner/model`, with first-seen, last-seen,
  and an optional **role** (e.g. "summaries") so a swap (`devstral → qwen2.5-coder` for a
  role) is visible as a transition rather than a silent replacement.

### 3. Per-project usage log — `projects/<id>/model-usage.md`

Append-only, newest on top, **one line per closeout/compact (or sprint-end)**. Each line
records the model that did the step and what it did, naming decision ids when the step
produced them:

```
- 2026-06-18T14:30-06:00 — claude-code/opus-4.8 — Sprint 4 multi-machine sync → d017, d018
- 2026-06-15            — ollama/qwen2.5-coder:32b-q4 — summaries (replaces ollama/devstral for this role)
```

Provenance lives only here — **not** on decision-record frontmatter. The log already
answers "what model did what step," dated and ordered; duplicating it onto decisions
would create a second source that drifts. Traceability to a specific decision is by the
decision id the log line already carries (grep the log for `d017`).

### 4. Wiring

**Stamp + self-register — at closeout/compact (daily, normal path).** Add one step to
`universal/playbooks/compact.md`'s closeout. In a single action the agent:

1. Appends the usage-log line for the work just completed.
2. **Self-registers in the catalog.** The agent knows its own `runner/model`. If that is
   absent from the catalog — or newer than the latest entry for that runner — it adds it
   as current/latest right there. New model versions catalogue themselves the first time
   they are used, with no weekly lag. (Sprint-end without a compact: same line, written
   at the seam.)

   Self-registration is a **clean add** (an observed fact about what just ran), so it is
   safe to do inline and unattended — consistent with the sweep's graduated-autonomy rule
   that automation may add but never reword/remove.

**Housekeeping + flag — weekly audit (judgment, human-gated).** Add a "Model provenance"
check to `universal/playbooks/audit.md`:

- *Reconcile / catch misses (mechanical):* any `runner/model` in a
  `projects/*/model-usage.md` not in the catalog — e.g. a tool that didn't self-stamp —
  gets registered.
- *Mark supersession + flag (semantic, flag-only):* where a newer version has landed,
  mark the prior catalog entry `superseded → <successor>` and raise an `OPEN CONCERN`
  on usage-log steps still on the old model ("review whether to revisit"). Declaring
  something superseded and deciding dependent work needs another look is a judgment, so
  it stays human-gated in the audit — never auto-acted.
- *Prune / reconcile* malformed or stale entries.

The split mirrors the rest of Grimdex: **clean additions happen inline; judgments wait
for the human.**

### 5. Discoverability

Add a one-line pointer to `universal/model-catalog.md` in GRIMDEX.md's Layout section so
agents find it. Keep it to one line — the law is deliberately tiny and adherence degrades
with length.

## Files

- **New:** `universal/model-catalog.md` (catalog template, seeded with known current models)
- **New:** `examples/model-usage-sample.md` (sample per-project usage log)
- **New:** `docs/2026-06-18-model-provenance-tracking-spec.md` (this spec)
- **Edit:** `universal/playbooks/compact.md` (stamp + self-register step)
- **Edit:** `universal/playbooks/audit.md` (model-provenance housekeeping check)
- **Edit:** `GRIMDEX.md` (one-line Layout pointer)

## Script + elevation to law (owner decision, 2026-06-18)

The first cut shipped as convention + playbook wiring only, deferring a script per Law #7
(automate after evidence of violation). The owner overrode that: make the stamp
deterministic from day one and elevate it to a numbered law, because provenance is only
useful if it is captured *consistently* — a skipped stamp is a silent hole the audit
can't see. So this revision adds:

- `scripts/model-lib.ps1` — pure helpers (`Test-/Split-GrimdexModelId`,
  `Get-GrimdexModelTier`, `Format-GrimdexUsageLine`, `Add-GrimdexUsageLine`,
  `Add-GrimdexCatalogModel`, `Test-GrimdexCatalogHasModel`) + the `Add-GrimdexModelStamp`
  orchestrator and `Find-GrimdexStaleModelUsage` (the audit's deterministic flagger).
- `scripts/stamp-model.ps1` — the closeout entry point.
- `scripts/test-model-lib.ps1` — the 7th test suite.
- **GRIMDEX.md law #8** — "stamp model provenance at every closeout," naming the script.
- The compact playbook now invokes the script; the audit uses `Find-GrimdexStaleModelUsage`.

Law #7 still governs *future* escalation (e.g. a pre-compact hook that refuses to compact
unstamped) if the law alone proves insufficient.
