# Grimlore — the context/knowledge layer (design spec, v0)

**Date:** 2026-08-14 · **Status:** draft spec — nothing built · **Layer:** context/knowledge
**Parent:** [`2026-08-14-grimdex-ecosystem-architecture.md`](2026-08-14-grimdex-ecosystem-architecture.md)

> Sections 1–3 and 5 are settled (they come from the authoritative ecosystem brief).
> Section 6 is a list of **open questions**, deliberately unresolved. Do not treat them as
> decided.

## 0. The name

**Grimlore**, not "Grimdex Wiki." Grimdex already reserved the name *Grimlore* for a future
general "second-brain" knowledge base; this layer is what that reservation was being held
for, so it is spent here rather than left dangling beside a near-duplicate concept.

Two things follow:

- Grimlore is a **sibling** of Grimdex in the naming family, not a sub-product of it —
  `Grimdex` (rules) / `Grimlore` (context) / `Baton` (action).
- The general, non-coding knowledge need that Grimdex's `d009` revisit-if anticipated lands
  **here**. Grimlore is coding-harness context first, but it is the layer that inherits the
  second-brain role — not a third store invented later.

"Wiki" is retired as a name. It suggested a browsable human destination; Grimlore's primary
consumer is an agent assembling context.

## 1. What Grimlore is (settled)

An **optional long-term knowledge/context layer**. It remembers **why** decisions were made,
**who/what** the work is for, and the environment around it: design rationale, history,
hardware, organization, audience, models, research, project context.

**Purpose statement:** *Context is the purpose of Grimlore.*

It exists because that context is genuinely useful to an agent but would **bloat Grimdex** if
placed there — and Grimdex's first principle is that bloat is its enemy. Grimlore is the
pressure-release valve that lets Grimdex stay small without discarding the context. Naming a
*destination* is what makes "no" cheap for Grimdex.

### What belongs here — the authoritative inventory

```
design · rationale · history
environment · user · company
audience · hardware · models
research · project knowledge
```

Expanded, with the concrete cases that motivated the layer:

- **design · rationale · history** — architectural reasoning in long form; what was tried,
  what was abandoned, what the project used to be.
- **environment · user · company** — the coding environment, who the owner is and how they
  work, the organization and its stakeholders.
- **audience · hardware · models** — who the work serves; the rig, home lab, machine
  inventory, network; the model roster, availability, characteristics, standing observations.
- **research · project knowledge** — source material, references, and the durable
  project-surrounding facts that don't prescribe behavior.

### Four things Grimlore is specifically for

1. **Standards and external references.** A concept per standard, with the canonical link.
   OKF's own `resource` field exists for exactly this — *"canonical URI for the underlying
   asset."* The OKF spec itself is the first entry: an agent that needs the format's rules
   follows the link rather than relying on a summary someone wrote once and never refreshed.
   `type: Standard`.
2. **Research, kept readable.** The point is not an archive — it is that research can be
   *re-read*: what was investigated, what it found, and **what the ramifications are**. A
   `Research` concept should end with its implications, not just its findings, because the
   implications are what a human returns to and what an agent needs to reason from.
3. **Global context — the rig and the accounts.** What machines exist and what is on them;
   email, calendar, storage; which models the owner actually has access to. This is durable,
   changes slowly, is expensive to re-derive, and prescribes nothing — a textbook fit.
   `type: Environment`, `Hardware`, `Account`, `Model`.
4. **Documented policy — including model/quota rules.** The owner's rules on model usage,
   written out with their reasoning: *"use up to 50% of Codex, but on the last day of the
   window you may use up to 100%"*; *"hold a few percent of Claude in reserve until the last
   day."* Grimlore **documents** these. Grimdex carries the corresponding enforceable rule,
   and Baton enforces it at dispatch. `type: Quota Policy` — see §2a.

⚠️ **`models` span all three layers, deliberately** — a layer is defined by the question it
answers, not the nouns it touches:

- *What is it?* — roster, availability, context windows, characteristics, standing
  observations → **Grimlore** (here).
- *What are the rules for using it?* — spend ceilings, permitted depth tier per stakes, what
  may never be routed off-box → **Grimdex**.
- *How do I use it?* — selection, routing, flags, retries, and enforcing Grimdex's rules at
  dispatch → **Baton**.

So Grimlore holds *"gpt-5.4 has a 400k context window"*; Grimdex holds *"low-stakes work may
not exceed the economy tier"*; Baton holds the dispatch and the meter that enforces it. A
model's observed behavior is Grimlore's; a rule derived from that observation is Grimdex's.

### What does NOT belong here

| Not this | Goes to |
|---|---|
| A rule about how code must be written | Grimdex |
| A decision record (chosen / alternatives / rationale) | Grimdex `projects/<id>/decisions/` |
| Anything that must *happen* — a task, workflow, or dispatch | Baton |
| An application's own domain/subject-matter KB | The application (per `d009`) |
| Context that merely *seems* useful, with no consumer | Nowhere. Large ≠ indiscriminate. |

### The sharpest boundary: two kinds of "why"

Grimlore owns *why*, and Grimdex's decision records have a **Rationale** section. These do
not collide, and the line is worth stating precisely because it will otherwise be
re-litigated every time:

- **The why behind a *rule*** — the evidence and reasoning that justify a decision or
  convention — stays in **Grimdex**. Law #7 requires rules to trace to evidence; severing
  rationale from rule would gut that.
- **The why behind the *work*** — why this project exists, who it serves, what constraints
  and environment surround it — is **Grimlore's**.

Test: if removing the text would leave a rule unjustified, it is Grimdex's. If it would
leave an agent *uninformed but still correctly governed*, it is Grimlore's.

## 2. Format: OKF v0.2 — **validated, adopted**

**OKF — Open Knowledge Format, v0.2.** Spec:
<https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md> ·
[background](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing)

This was previously flagged as an unvalidated direction on the grounds that OKF's origin is
data-catalog interchange rather than LLM context loading. **Reading the spec retires that
objection.** OKF's stated design goals are that knowledge be *"readable by humans without
tooling, parseable by agents without bespoke SDKs, diffable in version control, portable
across tools, organizations, and time,"* and it defines an explicit **agent consumption
model**. That is Grimlore's requirement, almost verbatim.

### Why it fits (per the spec)

| OKF property | What it gives Grimlore |
|---|---|
| A directory of markdown files with YAML frontmatter; nothing else required | **Identical substrate to Grimdex's existing floor.** No new runtime, no server, no SDK. Any agent or plain `git` + grep reads it. |
| `type` is the **only** required field, and types are **not centrally registered** | Grimlore defines its own vocabulary (`Environment`, `Audience`, `Model`, …) without fighting an imposed taxonomy. The spec explicitly declines to define fixed taxonomies. |
| Trust family: `generated: {by, at}`, `verified: [{by, at}]`, actor convention `human:<id>` vs `<producer>/<version>` | **Model provenance, already standardized.** This is engine law #8 (stamp `runner/model` at closeout) expressed in a portable schema — and its derived trust tiers (unverified → machine-confirmed → human-reviewed) give the audit a signal it currently has to infer. |
| `status: draft\|stable\|deprecated` + `stale_after: <date>` | **The anti-rot mechanism.** "Large does not mean indiscriminate" becomes a deterministic date check the weekly audit can enforce — law #7's "escalate to a script, not more prose." |
| `sources[]` with `author`, `usage_count`, `last_modified`, plus per-claim footnote attribution keyed to `sources[].id` | **Provenance-backed promotion** (§5) gets a real carrier. Promotion between tiers needs to cite where knowledge came from; this is that field. |
| A **bundle** = a directory | A natural unit for **project isolation** (§4): one bundle per project scope. |
| Consumers **MUST tolerate broken links**; links are ordinary markdown | Sidesteps the dangling-cross-reference problem entirely — no link-integrity gate to build or maintain. |
| Bundle-relative absolute paths (`/tables/x.md`) survive file moves | Reorganizing a project's context doesn't break references into it. |

### The local Grimlore profile

OKF conformance requires only a parseable frontmatter block with a non-empty `type`. Grimlore
tightens that locally — permitted, since stricter local conventions remain conformant:

- **Required in Grimlore:** `type`, `title`, `description`. Description quality drives whether
  an agent retrieves the right context at all; leaving it optional would be false economy.
- **Required on anything an agent wrote:** `generated: {by, at}`, using the actor convention
  (`claude/opus-5`, `human:maintainer`, `process:sweep`).
- **Type vocabulary (initial, extend freely):** `Rationale`, `History`, `Audience`,
  `Organization`, `Environment`, `Hardware`, `Model`, `Research`, `Constraint`, `Standard`
  (an external spec, with its canonical link in `resource`), `Account` (a service the owner
  holds — mail, calendar, storage), `Quota Policy` (a documented usage rule; see §2a).
- **Paired-policy fields (local extension):** `policy_id`, `pairs_with`, `last_reviewed` —
  see §2a. OKF requires consumers to tolerate unknown keys, so these remain conformant.
- **`okf_version: "0.2"` pinned** in each bundle-root `index.md`.
- **Not used:** `Attested Computation` and its `runtime`/`executor`/`attester` fields — that is
  OKF's data-catalog heritage and has no Grimlore role. Unused, not harmful.

### What OKF does *not* solve

Adopting the format closes the container question and nothing else. Still Grimlore's problem:

- **Isolation enforcement.** OKF has no notion of "this agent may read bundle A but not B."
  Bundles give a clean boundary to enforce *at*; the enforcement is ours to build (§4).
- **Retrieval.** OKF is a format, not an index. Grep vs. embeddings is untouched (§6 q3).
- **Typed relationships.** Links are deliberately untyped — *"semantics conveyed by surrounding
  prose."* For an agent assembling context, edges like `supersedes` or `serves-audience` would
  be better. Mitigated by `type` + `tags`; accepted as a real limitation.
- **Spec churn.** v0.2 is young and its v0.1→v0.2 bump was **breaking** (`timestamp` →
  `generated`, body `# Citations` → frontmatter `sources`). Pinning `okf_version` bounds this,
  but a v1.0 could still require a migration pass.

## 2a. Deliberate duplication: paired policy

**The requirement.** Some facts are wanted in *both* Grimlore and Grimdex — model quota
policy is the driving case. Grimlore documents the policy and its reasoning; Grimdex carries
the enforceable rule. This duplication is **intentional**: the owner wants a change in one
place to *require* the same change in the other, so a policy can't quietly shift in the rule
without the reasoning being revisited.

**The honest problem with that as stated.** A convention that says "remember to update both"
is a hope, not a mechanism, and unenforced duplication drifts — reliably. Grimdex's own law #7
already rules on this class of problem: *a rule still being violated despite emphasis gets
converted into something deterministic — a script, hook, gate, or CI check — not more prose.*
There is also an anti-duplication precedent in law #1 (*"app repos reference decisions by id —
never duplicate the record"*), so paired policy is a deliberate **exception** to house style
and has to earn it by being mechanically checked.

**The resolution: pair by id, verify in the audit.** Keep the duplication; bind it.

- Every duplicated policy gets a **`policy_id`** — a stable slug, e.g. `quota-codex-window`.
- The Grimlore concept carries `policy_id`, `pairs_with` (where the enforceable rule lives),
  and `last_reviewed`. OKF explicitly requires consumers to tolerate unknown keys, so these
  local fields stay conformant.
- The Grimdex rule cites the same `policy_id`.
- The **weekly KB audit** checks that every `policy_id` resolves on both sides, and flags any
  pair whose halves were last touched more than one review cycle apart. Divergence surfaces as
  a finding; it is not left to memory.

```yaml
---
type: Quota Policy
title: Codex weekly window — 50% soft cap, 100% on the final day
description: Hold half the Codex weekly allowance in reserve until the window's last day.
policy_id: quota-codex-window
pairs_with: grimdex:universal/decision-guidance.md#quota-codex-window
last_reviewed: 2026-08-15
status: stable
---

Reserve ~50% of the Codex weekly allowance through the window, releasing to 100% on the
final day (use-it-or-lose-it). **Why:** …
```

⚠️ **There is a third copy, and it is the one that actually governs behavior.** Baton already
implements this mechanism — pre-flight soft caps and "surplus spend near reset" are live
features, and the real numbers live in its fleet config. So a quota policy exists in *three*
places: the reasoning (Grimlore), the rule (Grimdex), and the **executable values** (Baton).
Recommendation: treat Baton's config as ground truth for the *numbers* and have the audit
check the other two against it. Two copies of prose that agree with each other while the
running system uses a third value is the worst available outcome, and it is the one that
happens by default.

## 2b. The `x-grimdex` extension — development coordinates

OKF describes knowledge in general; it has nothing for the development world a coding harness
lives in. Grimdex adds one **clearly-labelled extension block** for that.

**Why `x-grimdex:` and not bare keys:** the `x-` prefix is the universally recognized "this is
a vendor extension, not core spec" marker (HTTP headers, OpenAPI). It makes the boundary
obvious to any reader, and it guarantees no collision with a future OKF core field. Everything
non-core lives in exactly one block — nothing to hunt for.

Conformance is unaffected: OKF requires consumers to *"not reject documents for… unknown
keys,"* so a document carrying `x-grimdex` remains a valid OKF document, readable by any
OKF-aware tool that ignores the block entirely.

### Fields

```yaml
---
type: Rationale
title: Why the roadmap runs on GitHub Projects
description: The board is the live tracker; Grimlore holds the reasoning behind its shape.

x-grimdex:
  project: canvas-toolchain        # Grimdex project-id (the same key used everywhere else)
  repo: Ryfter/canvas-toolchain    # owner/name

  issues:  [47, 51]                # GitHub issue numbers
  prs:     [128, 130]              # associated pull requests
  board:   5                       # GitHub Projects board number
  items:   [12]                    # item number(s) within that board
  milestone: v2.0                  # optional

  decisions: [canvas-d007]         # qualified decision ids (see id-conventions.md)
  assignees: [human:maintainer, claude/opus-5]   # OKF actor convention — see below
---
```

| Field | Meaning |
|---|---|
| `project` | The Grimdex project-id. One key addresses a project's governance tier, its Grimlore bundle, and this block. |
| `repo` | `owner/name`, so a number is resolvable without guessing which repo it belongs to. |
| `issues` / `prs` | GitHub issue and pull-request numbers. |
| `board` / `items` | GitHub Projects board number and item number(s) within it — the "what # it is in the project's roadmap" coordinate. |
| `milestone` | Optional milestone name. |
| `decisions` | Qualified decision ids (`canvas-d007`) linking the context back to the governing decision. |
| `assignees` | **Who did or owns this work**, in OKF's actor convention. |

**`assignees` reuses OKF's actor convention deliberately** — `human:maintainer`,
`claude/opus-5`, `process:sweep`. In this harness a model genuinely is an assignee: Baton
dispatches labor to instruments, and "gpt-5.4 built this, a human reviewed it" is a fact worth
carrying. It also means `assignees` and OKF's own `generated.by` / `verified.by` speak one
vocabulary rather than two.

### The rule that keeps this from rotting

> **The extension carries coordinates, not content.**

Store the *number that locates* an item on GitHub. Never mirror its title, body, comments, or
live status into the concept. GitHub stores that richly and keeps it current; a copy here is a
second, staler version that nothing reconciles — the exact drift `grimdex-d022` had to build a
whole audit check to contain, and here it would be gratuitous, because the data already has a
perfectly good home.

Corollary on `assignees`: it records **who did the work** (a historical fact about this
concept), not a live mirror of GitHub's assignee field. Those diverge the moment someone
reassigns an issue, and only one of them is knowledge.

### Still owed — the cross-project convention

The maintainer's requirement that *"how that is implemented [be] implemented across all projects"* is a
**Grimdex** concern, not a Grimlore one: "every project tracks work on a GitHub Projects board
with this field set" is a convention — it changes *how* work is done. The `x-grimdex` block
gives that convention a place to be *referenced from*; it does not create it.

**That convention is not yet written.** It needs: which board fields every project carries, how
a roadmap item is numbered, and what an agent must do when opening work. Until it exists,
`x-grimdex` blocks will vary between projects — which is the problem, deferred rather than
solved.

## 3. Structure (settled shape, unbuilt)

Two tiers, each an **OKF bundle**, mirroring Grimdex's own shape so the mental model transfers:

```
<grimlore-root>/
  universal/              # OKF bundle — cross-project durable context
    index.md              # okf_version: "0.2"; bundle listing
    log.md                # chronological history (OKF reserved name)
    user/       …         # who the owner is, working style
    organization/ …       # company, stakeholders, audiences served
    environment/ …        # coding environment, hardware, home lab, network
    models/     …         # model roster, availability, standing observations
  projects/
    <project-id>/         # OKF bundle — one per project scope
      index.md            # okf_version: "0.2"
      log.md
      why/      …         # rationale, design history
      context/  …         # audience, constraints, surrounding facts
      research/ …         # source material, references
```

- **A bundle is the unit of isolation.** `<project-id>` matches the Grimdex project id exactly,
  so a project's governance tier and its context tier share one key — and "load Project A's
  context" is "load two bundles," not "run a filtered query over everything."
- `universal/` is **selected** cross-project context, not a dumping ground. Grimlore may be
  larger than Grimdex, but "larger" is not "indiscriminate" — `stale_after` is the enforcement.
- The subdirectories are conventional, not load-bearing: OKF derives a concept's id from its
  path, so the folder is organization for humans and a prefix for agents. `type` is what
  routing actually keys on.

A representative concept file:

```markdown
---
type: Environment
title: Primary workstation — ~/dev rig
description: Windows 11 + PowerShell 7 development box; where every ~/dev project is built.
tags: [hardware, windows, local]
generated: { by: "claude/opus-5", at: "2026-08-14T19:00:00-06:00" }
verified: [{ by: "human:maintainer", at: "2026-08-14T19:30:00-06:00" }]
status: stable
stale_after: 2027-02-14
---

Windows 11 Pro, PowerShell 7 primary … see [the model roster](/models/index.md).
```

## 4. Project isolation — the hard requirement

**An agent working on Project A must not casually receive Project B context.**

Default context an agent receives:

```
universal Grimdex guidance
  + Project A Grimdex guidance
  + relevant universal Grimlore context
  + Project A Grimlore context
```

Cross-project retrieval must not happen merely because the store *can* see everything.
Knowledge crosses a project boundary only through **deliberate, provenance-backed promotion
or synthesis**.

**OPEN — how isolation is enforced:** filesystem/scope boundaries at load time? per-project
index shards? a retrieval filter? Unresolved. The *guarantee* is the requirement; the
mechanism is not yet chosen.

## 5. Promotion policy (settled policy, unbuilt)

Promoting project context into universal context is **optional and configurable**. The system
asks the user which mode they want:

| Mode | Behavior | Must record |
|---|---|---|
| **Ask First** | Explain the proposed promotion and why it looks reusable, then ask permission. | Proposal, rationale/evidence, user decision, resulting action. |
| **Promote + Inform** | Explain what and why, promote automatically, then tell the user. | What changed, source project(s), rationale/evidence, timestamp, that the user was informed. |

**Neither mode is ever silent.** Automatic ≠ invisible.

This deliberately parallels Grimdex's promotions inbox + `PROMOTIONS-LOG.md` discipline.
**OPEN:** whether Grimlore reuses that machinery or runs a sibling of it.

## 6. Open questions

| # | Question | Why it matters |
|---|---|---|
| 1 | **How is isolation enforced?** Bundle-scoped loading, per-bundle index shards, or a retrieval filter? | OKF gives a clean boundary (the bundle) but no enforcement. The guarantee in §4 is the requirement; the mechanism is unchosen. |
| 2 | **How does Baton reach Grimlore?** Direct query, or a shared context-loading mechanism serving both Grimdex and Grimlore? | The ecosystem brief explicitly says *do not overcommit yet*. Deciding early risks making some layer bloated middleware. |
| 3 | **Retrieval mechanism.** Grep + frontmatter scan, embeddings, or both? | Grimdex already has an embedding index (`.index/`). Reuse vs. rebuild is a real cost fork. OKF's `type`/`tags` make a cheap non-embedding first pass viable. |
| 4 | **Own repo, or a tier inside an existing one?** | Grimlore is *optional* — Grimdex must run without it, which argues for separation. Private-by-default matters too: its content is personal (hardware, organization, audiences). |
| 5 | **What triggers a write?** Does an agent write Grimlore entries as it discovers context, or only at a seam (closeout/compact)? | Uncontrolled writes are precisely how "streamlined and retrievable" decays into a dumping ground. `stale_after` limits the damage but does not prevent it. |
| 6 | **Does Grimlore serve non-coding knowledge from day one**, or only harness context, with the second-brain role arriving later? | It inherits `d009`'s reservation. Serving both immediately may impose structure the coding case doesn't need. |

**Closed:**
- *"What is the relationship to the reserved name Grimlore?"* — it **is** this layer (§0).
- *"Does OKF actually fit?"* — **yes; adopted at v0.2** (§2, decision `d021`). The container
  question is settled; questions 1–6 are all *mechanism*, not *format*.

## 7. Explicit non-goals

- Grimlore is **not** an execution engine. It never dispatches, schedules, or runs
  anything — that is Baton's.
- Grimlore is **not** where rules live. If content prescribes behavior, it belongs in
  Grimdex.
- Grimlore is **not** required. Grimdex and Baton must both function fully without it.

## 8. Next step

Nothing is built, but the gating question is now answered: **the format is OKF v0.2** (`d021`).
That unblocks a concrete first step, in this order:

1. **Pilot one bundle, hand-written.** Convert context that already exists — the model roster
   (`universal/model-catalog.md`), the environment/rig facts, and one project's design
   rationale — into ~10 OKF concepts under `universal/`. No tooling, no scripts. The point is
   to find out whether the Grimlore profile (§2) survives contact with real content, and
   whether `type` + `description` are actually enough for an agent to retrieve the right file.
2. **Answer q4 (where it lives)** on the evidence of that pilot — its size and sensitivity will
   make the own-repo-vs-tier call obvious.
3. **Then** decide q1/q3 (isolation enforcement and retrieval), which are implementation
   choices the pilot's shape should drive rather than precede.

Deliberately *not* first: scaffolding empty directory trees, or building a writer/indexer. Both
would commit to mechanism before the content has argued for it.
