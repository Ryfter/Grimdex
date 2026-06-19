# Playbook: compacting a conversation (stub — flesh out with your conventions)

Read at the closeout/compact seam — both sides of it.

## Before compacting — closeout
1. Decisions captured as records (name each by id + title).
2. Code committed with clear messages and pushed; specs/plans committed.
3. Handoff docs/memory updated so other agents keep continuity.
4. **Harvest check:** did this work teach a cross-project rule? File a candidate in
   `universal/promotions/<project-id>.md`.
5. **Stamp model provenance (law #8).** Record what ran this step:
   `pwsh scripts/stamp-model.ps1 -ProjectId <id> -Model '<runner/model (params)>' -Did '<what>' [-Decisions d017,d018]`.
   Use YOUR OWN model as `runner/model` per the schema in `universal/model-catalog.md`
   (e.g. `claude-code/opus-4.8`, `codex/codex-5.4-mini (reasoning:high)`). The script
   appends to `projects/<id>/model-usage.md` (newest on top) and self-registers the model
   in the catalog (a clean add; marking supersession is the audit's job).
6. Fix anything unrecorded BEFORE compacting; then prompt the human.

## After compacting — state report
1. Reconcile claimed state against the live tracker; fix drift in the same turn.
2. Report: open items + status, recommended order with reasons, plain-English next
   steps, upcoming scheduled work.
3. Append to `projects/<project-id>/compact-state-log.md` (newest on top) and push.
4. Report, then wait for direction unless a standing rule authorizes the work.
