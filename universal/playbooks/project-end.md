# Playbook: ending a project

Read when finalizing/retiring a project. This is read at most a handful of times per
project — it is deliberately not in the law.

## 1. Finalization
- All branches merged or explicitly abandoned (note why in the project tier); final
  state pushed.
- **Tag the resting state:** `git tag vX.Y-final` + a GitHub release describing what
  the project is, what state it's in, and how to run it cold — the release notes are
  the time capsule a future reader opens first.
- README updated to describe the *final* state (how to run it cold, known limits).
- Open tracker items: close, or move to the project tier with a "parked" note —
  nothing left ambiguous.
- Decision records: statuses updated (`active` → `superseded`/`retired` where true).

## 2. The harvest — write the Grimoire entry
The highest-yield moment for promotions. Ask: **what did this project teach that the
next project should inherit?**
- Walk the project's decisions + lessons; distill candidates into
  `universal/promotions/<project-id>.md` (format in the inbox README). Rules the
  project *disproved* are candidates too — for `RIPPEDPAGES.md` via the gated path.
- Write a short closing summary at the top of the project tier
  (`projects/<project-id>/decision-guidance.md`): what it was, what survived contact
  with reality, what you'd do differently.

## 3. Verify the record
- Project tier is complete: decisions, guidance, cost ledger current, logs present.
- Everything pushed; the weekly audit will treat this project as dormant from now on —
  leave it in a state where "dormant" is accurate, not "abandoned mid-thought".
