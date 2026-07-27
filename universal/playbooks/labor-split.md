# Labor split & routing playbook

*This playbook (the method) ships in the Grimdex public engine. The actual policy (`config/fleet.json`) is private instance data — it lives in your own Grimdex instance and is never committed to the public engine.*

## 1. When to read this

Read this playbook before dispatching non-trivial coding work, **only when `config/fleet.json` exists** in the Grimdex root.

If the file is absent, the feature is dormant — work normally with a single model. No routing needed.

If present, the policy describes a **fleet** of workers (subagents, CLI tools, plugins) ranked by tier, availability, and role. Use this playbook to pick the right worker for each task.

## 2. Classify

Classify every task into **exactly one role** from this list. Pick the one that best matches the work:

- **bulk-code** — the lion's share of implementation; a major feature, refactor, or complex build. Primary builder work.
- **small-code** — a small, surgical change that can run in parallel to a bulk build (a typo fix, a one-line config, a test patch). Does not block anything; does not need the full reasoning depth of bulk-code.
- **thinking** — design exploration and decomposition; "what's the right approach?" and "how should this be built?" Precedes bulk-code. Ends with a written plan.
- **planning** — structured plan writing and spec authoring. Takes thinking output and produces a formal deliverable.
- **docs** — technical writing: decision records, playbooks, migration guides, API docs, ADRs. Not inline code comments.
- **summary** — synthesizing or distilling prior work into a brief form: summaries, digests, status reports, or a cross-project recap.
- **language** — low-reasoning language work: copywriting, tone polish, rewrite-for-clarity, translation, or structured content format conversions (not code).
- **review** — checking someone else's code: examining a pull request, auditing security, or analyzing a design for fit. Independent evaluation.
- **repo-op** — repository operations: PR automation, issue triage, release management, branch cleanup, or tag merging. Git and CI/CD work.
- **design-2nd-opinion** — an independent design review or a second opinion on an architectural choice. Async input to a design conversation; not a full design session.
- **on-call** — a gated specialist invoked deliberately by the user (e.g., Codex for a rescue mission). Requires explicit user request; see **Gates** section.

## 3. Select

Call `Select-FleetWorker` with the role you classified:

```powershell
$fleet = Get-GrimdexFleet -GrimdexRoot "<root>"
if ($null -eq $fleet) {
    # Feature is dormant; work with the default model
    return
}
$result = Select-FleetWorker -Fleet $fleet -TaskType "<role>"
```

Add `-Explicit` **only** when the user explicitly names a gated worker by name (e.g., "ask Codex to review this").

Add `-LateWindow` when it is late in the weekly quota window (e.g., Sunday afternoon). This tells the selector to prefer and burn higher-tier models before they reset.

**Honor the returned `Reason` string.** It explains why this worker was chosen (e.g., "bulk-code → Alice (policy hint)", "small-code → Bob (available)").

**If `NeedsAsk` is `true`, or if the result is `$null`**, ask the user **one line** ("No worker available for that role; which would you like?") before proceeding. Do not guess.

## 4. Dispatch adapters

Map the chosen worker's `invoke` prefix to an action:

- **`claude-subagent:<model>`** — Dispatch using the Agent tool (or TaskCreate if available) with that model name as an override. The model string is the exact model identifier (e.g., `claude-opus-4-1`, `claude-haiku-4-5`).
- **`cli:<binary>`** — Execute a Bash call to that binary. On first use, confirm the exact command and arguments (read the config's `invoke` value verbatim). Example: if `invoke` is `cli:codex`, run `codex <args>`.
- **`plugin:<name>`** — Dispatch to a Claude Code plugin or registered subagent by that name. Example: if `invoke` is `plugin:codex-rescue`, use the subagent named `codex-rescue` or the Skill tool if a matching skill exists.

## 5. Autonomy

**Auto-dispatch for everything**, including big builds. Announce the routing decision to the user (e.g., "Routing to Alice for bulk-code (policy hint)") and proceed without waiting for approval.

**Three hard stops** that pause for the user:

1. A worker has a `gate` flag (see **Gates** section).
2. A worker's `availability` is `out`.
3. The selector returns `NeedsAsk: true` or `$null`.

In all other cases, routing is automatic.

## 6. Gates

A gated worker has an optional `gate` property in the policy. It represents a special constraint or a specialist role that should not be invoked casually.

**Never invoke a gated worker unless the user explicitly requests it by name.**

Always honor any written limit in the gate string. Example: if a gate reads `skip-if-weekly>50%`, skip that worker if they are past 50% of their weekly budget. Treat the gate condition as a hard filter; if the condition is met, that worker is not available.

If a user explicitly names a gated worker, pass `-Explicit` to `Select-FleetWorker`; the selector will then include gated workers in the candidate pool.

## 7. Full counsel

When a user invokes **"full counsel"** (an explicit request), run an asynchronous multi-agent review:

1. **Dispatch the counsel roster** — in parallel, send the task to each worker in `policy.counsel` (a roster array of worker names). Each worker reviews independently and produces a written note, **without seeing the others' notes** (blind review).

2. **Cross-review pass** — after all blind reviews return, run **exactly one** second pass where each reviewer sees all the other notes, and writes a synthesis: whether they agree/refute/extend the others, and a final stance.

3. **Synthesize** — compile a consensus (if agreement exists) vs. conflict (if the reviewers differ), along with a recommendation. This is the final counsel output.

Bounded to **one cross-pass only** — do not run further rounds.

Because full counsel is an explicit user call, gated workers in the counsel roster are allowed. Treat it as a deliberate full-team review.

## 8. Note

The selector (`Select-FleetWorker`) is pure and advisory — it selects only; it does not dispatch, spend budget, or produce side effects. Deciding to act on its choice, and actually running the work, is the host agent's job and is implementation-specific (Agent tool, Bash, plugin, etc.).

Use this playbook and these three functions (`Get-GrimdexFleet`, `Test-FleetWorkerAvailable`, `Select-FleetWorker`) together to build a routing layer for your labor-split strategy.

## 9. Default seating (example)

The policy above encodes *your* lineup; this is the reasoning behind a good default seating,
stated in vendor-neutral terms so you can map it onto whatever models/tools you run. **The
guiding principle: put intelligence where it has the most impact.**

| Seat | Tier | Does |
|---|---|---|
| Plan / orchestrate | `high` | Decide *what* needs doing, decompose, write the brief, dispatch, adjudicate reviews. Highest leverage — planning errors cascade downstream. |
| Complex coding + final review | `high`/`build` | The hard, deeper-thinking implementation and the final whole-branch review. |
| Regular coding + integration | `mid` | Prose-/spec-described implementation and multi-file integration — anything needing interpretation. |
| Technical writing + plan-transcription coding | `cheap` | Docs/summaries about existing code, **and implementing a plan that already contains the complete code with tests specified**. |

**The key seam is plan completeness, not task size.** When the plan writes out the *complete
code* (with tests specified), a cheap-tier worker can safely transcribe it — the scaffolding
(complete code + specified tests + a senior review seat) catches any deviation. When the task
is *prose-described* or spans *multiple files needing integration*, it needs interpretation and
belongs a tier up. The failure mode to watch is a task *mislabeled* as transcription-grade that
actually needed interpretation — so classifying the task honestly is the planner's job, not the
implementer's.

**Compact at the plan→dispatch seam.** When planning is done, save off and compact *before*
handing to an implementation seat — switching workers means the next one starts cold, so give
it the compacted plan as its starting point, not the whole planning context. (See
`playbooks/compact.md` and the closeout discipline.)

An explicit orchestrator, if you run one, overrides all of this — its dispatch decisions win.
