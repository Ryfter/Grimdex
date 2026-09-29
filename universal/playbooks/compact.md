# Playbook: compacting a conversation

Read at the closeout/compact seam — both sides of it. the operator compacts aggressively:
don't wait to be told; when a task group finishes or context grows heavy, run the
closeout and prompt him. This generalizes the two global rules mirrored at
`universal/claude-rules/` (`task-group-closeout.md`, `post-compact-state-report.md`);
those remain the authoritative full text for Claude sessions — this is the
tool-agnostic version any agent can follow.

## Before compacting — closeout (save everything, confirm explicitly)
State the checklist out loud, with specifics:
1. **Decisions** captured as records — name each by id + title.
2. **Specs/plans** written and committed.
3. **Code** committed with clear messages (list SHAs) and **pushed** — the backup
   standing order covers the knowledge repo too.
4. **Memory / handoff docs** updated so other agents keep continuity (shared-core
   doc, model instruction files — whatever the project uses).
5. **Harvest check:** did this work teach a cross-project rule? File a candidate in
   `universal/promotions/<project-id>.md`. Did it *disprove* one? Note that too —
   removal proposals are RIPPEDPAGES material via the gated path.
6. If anything is NOT yet recorded, say so plainly and fix it **before** compacting.
7. Only then prompt the human to compact. Saving comes first, always.

## After compacting — state report (verify ground truth, then log)
1. **Reconcile live state vs memory** — pull the real tracker state (`gh issue list`
   for GitHub projects, else the project's tracker/backlog doc) and compare against
   what the summary/memory *claims*. Surface drift explicitly and fix the stale
   record in the same turn.
2. **Report** (three parts, plain language):
   - **Open items** — number, title, one-word status tag
     (actionable / blocked / deferred / umbrella).
   - **What's next, in order** — recommended sequence with a one-line reason each.
     Defaults when nothing else decides: ascending item number; loose ends before
     new features; honor any explicit re-ordering the operator has given. Call out
     anything NOT autonomously actionable. Where items carry explicit rank labels
     (the cost-engine scale: rank 1 highest → 5 lowest; 0/6 reserved), surface them.
   - **Plain English** — 1–3 sentences per item a non-engineer could read: what it
     is, what blocks it, the next concrete step.
3. **What's coming up:** scheduled/recurring work due before the next likely session
   (sweeps, audits, scheduled jobs) so nothing lands unwatched.
4. **Log it:** append the entry (newest on top) to
   `projects/<project-id>/compact-state-log.md` and push.
5. This is reporting, not authorization: report, log, then wait for direction unless
   a standing rule already authorizes the work.
