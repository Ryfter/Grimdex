# Grimdex ecosystem architecture — the three layers

**Date:** 2026-08-14 · **Status:** authoritative · **Scope:** Grimdex, Grimlore, Grimdex Baton

> **This document is the source of truth for how the three layers divide responsibility.**
> If earlier conversation context, an older design doc, or a handoff note conflicts with
> it, this document wins. Open design questions are marked as such — do not silently
> convert them into settled architecture.

## The Law

**Bloat is the enemy of Grimdex. Context is the purpose of Grimlore. Execution is the
purpose of Baton.**

Shorthand: **Grimdex governs *how*. Grimlore remembers *why*, *who*, and context.
Grimdex Baton determines *what happens next* and executes it.**

Named by role: **Grimdex = the rules layer. Grimlore = the context/knowledge layer.
Grimdex Baton = the action layer.**

## 1. Authoritative definitions

| Component | What it is | Primary responsibility |
|---|---|---|
| **Grimdex** | The public framework. | Governs **how** AI-augmented coding is done: lessons, conventions, schemas, rules, project guidance, universal rules, verification expectations, security expectations, and disciplined promotion. |
| **Grimlore** | An optional long-term knowledge/context layer. | Remembers **why** decisions were made, **who/what** the work is for — design rationale, history, environment, hardware, organization, audience, models, research, and project context. |
| **Grimdex Baton** | The action/orchestration layer. | Determines **what happens next** and **when**, then executes: coding, routing, agents, models, workflows, testing, verification, movement, and delivery. |
| **The private data repo** | A maintainer's private, backed-up personal Grimdex instance. | **Not a separate architecture component.** It is the personalized Grimdex framework holding one owner's accumulated information, kept in its own private repository. |

### What each layer contains

The authoritative content inventory. Each layer is a *bundle of related concerns*, not a single
artifact type:

| **Grimdex** — the rules layer | **Grimlore** — the context layer | **Grimdex Baton** — the action layer |
|---|---|---|
| conventions · lessons · rules | design · rationale · history | orchestrate · execute · route |
| schemas · gates · standards | environment · user · company | build · test · verify · deploy |
| validation · security guidance | audience · hardware · models | agents · models · workflows |
| project rules → universal rules | research · project knowledge | |

Some entries appear in more than one column. That is deliberate and load-bearing: **a layer is
defined by the question it answers, not by the nouns it touches.** The same noun can raise all
three questions, and each answer belongs to a different layer.

#### `models` spans all three layers

| Layer | Question about a model | Contents |
|---|---|---|
| **Grimlore** | *What is it?* | The roster: which models exist, availability, context windows, characteristics, standing observations. Explains; prescribes nothing. |
| **Grimdex** | *What are the rules for using it?* | Restrictions and standards: spend ceilings, which depth tier is permitted at which stakes, what may never be routed to a third-party model. Prescribes. |
| **Baton** | *How do I actually use it?* | Dispatch mechanics: selection, routing, CLI flags, retries — and the **runtime enforcement** of Grimdex's rules. |

Worked example: *"gpt-5.4 has a 400k context window"* is Grimlore. *"Low-stakes tasks may not
exceed the economy cost tier"* is Grimdex. *"…so route this one to the local model, with these
flags, and retry once in a clean worktree"* is Baton.

⚠️ **Grimdex governs the spend rule; Baton enforces it.** Grimdex prescribes and never runs
anything — that is the Law's own "Grimdex prescribes. Grimlore explains. Baton acts." A usage
governor, a cost meter, or a pre-flight quota probe is runtime machinery and belongs to Baton,
which is where it already lives. Reading "Grimdex enforces the rules on models" as *Grimdex
holds the enforcement mechanism* would drag exactly the kind of implementation the anti-bloat
law exists to keep out. The distinction is the same one that governs gates, below.

#### `gates` / `standards` / `validation` (Grimdex) vs `test` / `verify` (Baton)

Grimdex **defines** the gate and the standard it asserts; Baton **runs** it. Grimdex "defines
expectations for how work is coded, checked, and secured without trying to become every tool
that performs those checks" — Baton is one of those tools.

#### `project rules → universal rules` — two content types *and* the gate

Both. **Project rules are content** — they live in that project's tier and may be rich and
permissive. **Universal rules are content** — they live in the always-read law and are trimmed
aggressively. The arrow is the **promotion gate**: a project rule stays project-scoped content
until the gate is tripped, at which point it becomes a universal rule. The row names the two
tiers and the transition between them.

Note the symmetry: **Grimlore has the same shape** — a per-project tier, a universal tier, and a
promotion policy between them (§6). Both knowledge layers are two-tier with a gate; only the
admission bar differs.

### Naming: the context layer is Grimlore

The context layer is **Grimlore**, not "Grimdex Wiki." Grimdex had already reserved the name
*Grimlore* for a future general "second-brain" knowledge base; this layer is what that
reservation was being held for, so it is spent here rather than left dangling beside a
near-duplicate concept. Two consequences:

- **Grimlore is a sibling of Grimdex, not a component of it** — `Grimdex` (rules) /
  `Grimlore` (context) / `Baton` (action). "Grimdex Wiki" implied a part *of* Grimdex, which
  inverts the point: the layer exists precisely so this content does **not** live under
  Grimdex.
- **It inherits the second-brain role.** General, non-coding durable knowledge lands in
  Grimlore rather than in some third store invented later.

"Wiki" is retired as a name — it suggested a browsable human destination, and Grimlore's
primary consumer is an agent assembling context for a task.

### Critical clarification: "rules layer" is a position, not a content list

⚠️ Calling Grimdex "the rules layer" describes **where it sits**, not what it holds. As the
architecture's author put it: *"INSIDE that layer are decisions, lessons, and things like that.
It's not a flat 'this is the rule.' It is also the artifacts and information that back up that
rule."*

A rule stripped of the decisions, lessons, and evidence that produced it is an assertion, and
law #7 requires the opposite — every rule traces to an observed failure or success. So the
backing artifacts are not adjacent to the rules layer; they **are** part of it.

This matters because the mistake has already been made once and corrected (`d009`: *"I thought
Grimdex was rules only"*). The line that keeps it corrected is between the two kinds of *why*:

- **The why behind a *rule*** — the evidence and reasoning justifying a decision or
  convention — is **Grimdex's**.
- **The why behind the *work*** — why the project exists, who it serves, what environment
  and constraints surround it — is **Grimlore's**.

Test: if removing the text would leave a rule unjustified, it belongs to Grimdex. If it would
leave an agent uninformed but still correctly governed, it belongs to Grimlore.

### Critical clarification: the private data repo is not a layer

Do **not** place the private data repo in diagrams as a peer beside Grimdex, Grimlore, or Baton. The
public downloads Grimdex and personalizes it with their own accumulated information;
"the private data repo" is merely the name this project uses for the private backup of that
personalized instance. Every adopter has an equivalent, whatever they call it.

Corollary: the **public** Grimdex repo is not anyone's personal knowledge store. It is
the framework others download and personalize (see `d010` — de-personalize the public engine).

## 2. Boundary tests

When deciding where new information or behavior belongs, run these three tests in order:

1. Will this change **HOW** future coding work should be done? → **Grimdex.**
2. Will this explain **WHY** something exists, **WHO** it is for, or the surrounding
   **CONTEXT**? → **Grimlore.**
3. Does this describe **WHAT** should happen next, **WHEN** it should happen, or does it
   require **ACTION**? → **Grimdex Baton.**

**Secondary rule:** *Grimdex prescribes. Grimlore explains. Baton acts.*

## 3. Grimdex: governance without bloat

Grimdex is deliberately the smallest and most aggressively maintained layer.

- Project-level rules may be richer and more permissive. **Universally promoted rules
  must be trimmed aggressively** because they affect every project.
- Project knowledge and rules can stay project-scoped until evidence justifies broader
  use. This is the existing promotion gate (`universal/promotions/`), not a new one.
- Grimdex defines expectations for how work is **coded, checked, and secured** — without
  trying to become every tool that performs those checks.
- Security scanners, test tools, linters, and review frameworks are **invoked and
  enforced by** Grimdex rules. They do not need to become Grimdex itself.

**Open design question (not settled):** organizing rule families — coding best practices,
code-check/review best practices, security/scanning practices — while keeping one shared
mechanism: *evidence → lesson → project rule → optional universal promotion.*

## 4. Grimlore: the long-term brain

Grimlore is an **optional add-on** to the full coding harness. It carries durable context
that is valuable to agents but would bloat Grimdex if placed there.

- **Format: OKF v0.2 (Open Knowledge Format) — validated and adopted** (`d021`). A directory
  of markdown files with YAML frontmatter: the same substrate Grimdex already uses, plus a
  standard metadata convention carrying provenance (`sources`), trust (`generated`/`verified`),
  and staleness (`status`/`stale_after`). Grimlore adds a stricter local profile — `type`,
  `title`, `description` required — on top of bare OKF conformance.
- **Project-oriented structure:** each project gets its own Grimlore scope — an **OKF bundle**,
  which doubles as the isolation boundary.
- A **universal/context area** may hold selected cross-project information: the user, the
  company, the coding environment, hardware/home lab, audiences, models, model
  availability, and other durable context.
- Grimlore knowledge should be **streamlined and retrievable**. Large does not mean
  indiscriminate.
- Grimlore may hold designs, reasoning, history, research, and environment details that
  do not belong in Grimdex rules.

**Four things it is specifically for:** external **standards** with their canonical links
(`type: Standard`); **research** written up with its *ramifications*, not just its findings;
**global context** — machines and what's on them, mail/calendar/storage accounts, which models
the owner has access to; and **documented policy**, including model/quota rules.

**Paired policy (`d022`).** Quota rules are deliberately duplicated: Grimlore documents the
policy *and its reasoning*, Grimdex carries the enforceable rule, Baton enforces it at dispatch.
The duplication is a forcing function — changing one half should require revisiting the other —
so the halves are bound by a shared `policy_id` and reconciled by the weekly audit rather than
by memory. Baton's config is ground truth for the actual numbers.

Full design: [`2026-08-14-grimlore-spec.md`](2026-08-14-grimlore-spec.md).

OKF references:
- **Spec (v0.2):** <https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>
- Background: <https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing>
- Repo: <https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf>

## 5. Project isolation and knowledge scope

**Project independence is a core design principle.** An agent working on Project A should
not casually receive Project B context.

- **Default access:** universal Grimdex guidance + Project A Grimdex guidance + relevant
  universal Grimlore context + Project A Grimlore context.
- Cross-project retrieval must **not** happen merely because the overall brain can see
  everything.
- Knowledge crosses project boundaries through **deliberate promotion/synthesis**, not
  unrestricted context leakage.

> **Core principle:** projects remain independent. Cross-project learning happens through
> explicit, provenance-backed promotion rather than unrestricted retrieval.

## 6. Promotion policy

Promotion of project knowledge to universal knowledge is **optional and configurable**.
The system asks the user which interaction style they want.

| Mode | Behavior | Required transparency |
|---|---|---|
| **Ask First** | Explain the proposed promotion and why it appears reusable, then ask permission before promoting. | Record the proposal, rationale/evidence, the user's decision, and the resulting action. |
| **Promote + Inform** | Explain what is being promoted and why, perform the promotion automatically, then tell the user. | Record what changed, source project(s), rationale/evidence, timestamp, and that the user was informed. |

**Even automatic promotion is never silent.** Both modes must explain what is being
promoted and why.

## 7. Grimdex Baton: the action layer

Baton is where motion happens. It consumes the governing framework and the relevant
context, then coordinates and executes work:

- Coding and edits.
- Agent/model/tool orchestration and routing.
- Task sequencing and workflow state.
- Testing, verification, review, and security checks **as required by Grimdex governance**.
- Movement from *objective → work → checked result → delivery*.

**Naming:** "Grimdex Baton" is the working name and is not permanently frozen.
Government/company metaphors (a chief-of-staff/orchestrator role, for example) remain
conceptual possibilities. **Do not rename it unless explicitly asked.**

## 8. Interaction model

> Grimdex tells Baton **how** work must be performed. Grimlore gives Baton the durable
> context needed to understand **why** the work exists, **who** it serves, and the
> environment around it. Baton then **executes** the work. The implementation must
> preserve these responsibilities without forcing any one layer to become bloated
> middleware.

**Open design question (not settled):** query routing. Baton must have access to the
relevant Grimdex guidance and Grimlore context, but *whether it queries both directly or uses
a shared context-loading mechanism* is still open. Do not overcommit to one
implementation yet.

## 9. Prior assumptions to discard

- **Open Brain / AWS is not part of this branch of the architecture.** Do not use it to
  shape these decisions unless it is explicitly reintroduced.
- the private data repo is **not** an architectural peer or a separate knowledge service.
- The public Grimdex repo is **not** anyone's personal knowledge store.
- Do **not** collapse Grimlore context into Grimdex merely because it is useful. Useful
  context can still be the wrong *kind* of information for Grimdex.
- Do **not** turn Grimlore into an execution engine. Execution belongs to Baton.
- Do **not** let Baton become the permanent home for durable rules or long-term context
  simply because it discovers them during execution.

## 10. Instructions for any LLM using this brief

1. Treat the Law and the authoritative definitions as stable unless the user explicitly
   changes them.
2. When proposing a new feature, **first classify it** as governance (Grimdex),
   context/knowledge (Grimlore), or action/execution (Baton).
3. Prefer less architecture, fewer universal rules, and cleaner boundaries over feature
   accumulation.
4. If a proposal increases Grimdex's size without changing how future work should be
   governed, **challenge it** (this is law #9 — brutally honest when queried).
5. If contextual knowledge would help an agent but does not prescribe behavior, favor the
   **Grimlore**.
6. If something exists to make work happen *now*, favor **Baton**.
7. Distinguish settled architecture from open design questions; do not silently convert
   brainstorming into law.

## 11. One-paragraph snapshot

Grimdex is the public, compact governance framework for AI-augmented coding: it controls
**how** work should be done and aggressively resists bloat. Grimlore is an optional,
OKF-oriented long-term knowledge layer that remembers **why** decisions were made, **who**
the work serves, and the surrounding project/user/environment context, while preserving
project isolation. Grimdex Baton is the action/orchestration layer that determines **what
happens next** and **when**, then executes the work under Grimdex governance using
relevant Grimlore context. the private data repo is not another component — it is a private,
backed-up, personalized Grimdex instance.

---

## Where this sits relative to existing decisions

| Decision | Relationship |
|---|---|
| `d009` — Grimdex ↔ application-KB boundary (meta vs domain knowledge) | Compatible and extended. d009 split *knowledge about building software* from *an app's subject matter*. This brief adds a third axis inside the first: **how** (Grimdex) vs **why/who/context** (Grimlore). |
| `d010` — de-personalize the public engine | Honored. This copy is the genericized public template; the instance-specific reading lives in the private instance. |
| `d032`/`d033` — Grimdex standalone; Grimdex ↔ Baton mutual independence | Unchanged. Baton consumes Grimdex; neither requires the other to function. |
| Reserved name **Grimlore** (held for a future general "second-brain" KB) | **Closed — spent here.** The context layer *is* Grimlore. The general/non-coding knowledge need d009's revisit-if anticipated lands in it too, rather than in a third store invented later. |

**Source:** authored as the "Grimdex Ecosystem — LLM Context Update" brief, 2026-08-14.
