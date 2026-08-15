# Promotions log — admissions ledger

Every candidate that leaves the inbox (`universal/promotions/`) gets exactly one
disposition entry here. Append-only, newest on top. The sweep checks new candidates
against past **rejections** here (nothing gets re-litigated from scratch) and against
`RIPPEDPAGES.md` (nothing expelled sneaks back in).

Entry format:

```
## YYYY-MM-DD — <candidate short title> — ACCEPTED | REJECTED | DEFERRED
**From:** projects/<id> (candidate filed YYYY-MM-DD)
**Candidate:** <the proposed rule, verbatim or faithful summary>
**Disposition reasoning:** <why admitted / refused / parked>
**Evidence:** <projects where this held — ≥2 required for acceptance>
**Inscribed into:** GRIMDEX.md | playbooks/<name>.md (accepted only)
```

<!-- grimdex:log-top -->

## 2026-08-15 — Provisional laws (law #7 exception) — ACCEPTED
**From:** projects/grimdex (no inbox file filed — maintainer-directed, per grimdex-d020)
**Candidate:** An exception clause on **law #7**: a rule may be admitted **provisionally** when it
is maintainer-dictated (never an agent), structural (a new layer or redrawn boundary), marked
`[PROVISIONAL]`, states the condition that earns it permanence, and is ledgered. It **binds
exactly like a permanent law** — the mark describes its evidence, not its force. The audit flags
any provisional law whose condition is met, or whose framework still doesn't exist after two
cycles. Ordinary rules get no exemption.
**Disposition reasoning:** Law #7 forbids anticipatory rules, but a new framework cannot generate
evidence before it exists and cannot be built before its rules do — taken literally, law #7 makes
every new framework unbuildable. Kevin, 2026-08-15: *"You can't earn the status of law, when you
need the laws to be created for the new frameworks to function."* A named, marked, audited
exception preserves law #7's prohibition; silently ignoring the law when inconvenient (the default
outcome) would corrode every rule that did earn its place. **Applied surgically, not as a
blanket:** only the Grimlore-dependent statements are marked provisional — the id-qualification
rule was earned by an observed defect, and Grimdex's and Baton's roles are backed by years of
practice. ⚠️ The audit check that enforces review is **owed, not built**; until it exists this
mechanism relies on memory, which is the failure mode it was designed to prevent.
**Evidence:** n/a by construction — that is the point of the exception.
**Inscribed into:** `GRIMDEX.md` — law #7 exception clause; `⚑ [PROVISIONAL]` block under
`## Where Grimdex sits`; `[PROVISIONAL]` tag on law #2's Grimlore clause. Mirrored to the engine.
**Decision record:** grimdex-d025.

## 2026-08-15 — Project-qualified decision ids + law/decision precedence — ACCEPTED
**From:** projects/grimdex (no inbox file filed — maintainer-directed convention/scope change)
**Candidate:** (a) **Law #1:** decision ids are project-qualified `<prefix>-dNNN`; prefix =
project-id, or a short alias in `projects/<id>/.prefix` for long ids; prefixes unique;
**filenames stay bare** `dNNN-<slug>.md`; bare `dNNN` valid only inside its own tier; pointer to
`docs/id-conventions.md`. (b) **Law #4:** *a law outranks a decision record* — where the two
conflict the law governs; a decision may inform a law change only via the maintained loop.
**Disposition reasoning:** Maintainer-directed, definitional, and narrowing — the same bounded
path as the 2026-08-14 scope entry, ledgered here rather than swept. (a) resolves a real
ambiguity: ids are assigned per project tier, so a bare `dNNN` names different decisions in
different projects, and cross-project references had already been written wrong in practice.
(b) makes explicit a precedence the law only implied. **Law ids are deliberately NOT qualified** —
the form encodes the scope: unqualified `#N` = global, `<prefix>-dNNN` = project-local.
**Evidence:** n/a — definitional, not generalized from practice.
**Inscribed into:** `GRIMDEX.md` (law #1 id clause; law #4 precedence clause); new reference page
`docs/id-conventions.md`.

## 2026-08-14 — Grimdex is the rules layer of a three-layer harness (scope definition) — ACCEPTED
**From:** projects/grimdex (no inbox file filed — human-directed scope change; see reasoning)
**Candidate:** A new `## Where Grimdex sits` section in `GRIMDEX.md` defining Grimdex as the
**rules layer** (*how* work is done) beside **Grimlore**, the context/knowledge layer (*why/who/
context*), and **Grimdex Baton**, the action layer (*what happens next, when*); the boundary test
("Grimdex prescribes. Grimlore explains. Baton acts."); the anti-bloat rationale; and an explicit
guard that "rules layer" describes Grimdex's *position*, not its contents (law #1 stands —
decisions and lessons remain here). Plus a clause on law #2 routing prescription-free context to
Grimlore.
**Disposition reasoning:** Not routed through the sweep, deliberately, and the exception is narrow.
Law #4 exists so the law never drifts *silently* or *unilaterally*; the sweep is the mechanism for
candidate rules bubbling up from project evidence. This is instead a **scope definition handed
down by the human maintainer** — the gate law #4 protects was satisfied directly and up front, so
an inbox round-trip would have been ceremony, not review. The ≥2-project evidence bar is likewise
inapplicable: it governs *rules generalized from observed practice*, and a definitional statement
of what the repo is has no such evidence shape. **This entry is not a precedent for ordinary rule
additions bypassing the sweep** — only for maintainer-directed scope/definition changes.
**Evidence:** n/a — definitional, not generalized from practice.
**Inscribed into:** `GRIMDEX.md` (new `## Where Grimdex sits` section; law #2 clause).
