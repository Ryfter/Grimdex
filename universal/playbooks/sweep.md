# Playbook: the daily consolidation sweep (5:30 am routine)

You are running Grimdex's daily maintenance. Working directory: the Grimdex repository root (this repo).
**Autonomy is graduated (d002):** you may inscribe clean *additions* into the law; you
may never rewrite or remove existing law — those are deferred to the owner. Be terse.

## 1. Mechanical pass
Run: `pwsh -NoProfile -File scripts/sweep.ps1`
It syncs the repo (pull --rebase), reports inbox status, and runs the mechanical checks
(links, wikilinks, decision-id sequence, repo state, stale candidates). Read its output;
the last line is `STATUS: heartbeat-ok` or `STATUS: action-needed`.

## 2. `STATUS: heartbeat-ok`? Heartbeat and stop.
Append a one-line heartbeat entry to
`KB-AUDIT-LOG.md` (newest on top, under the `<!-- grimdex:log-top -->` marker):
`## <date time> — daily sweep` / `**Result:** clean heartbeat`. Commit (`sweep: daily
heartbeat`), push, **end**.

## 3. Process promotion candidates (graduated autonomy)
For each candidate in `universal/promotions/*.md` (skip README.md), conflict-check
against ALL of: `GRIMDEX.md` (the law), `universal/playbooks/*`, `universal/PROMOTIONS-LOG.md`
(past rejections — don't re-litigate), `RIPPEDPAGES.md` (past removals — don't re-admit),
and the other pending candidates (they may oppose each other).

- **Clean addition** (contradicts nothing, ≥2-project evidence, genuinely cross-project):
  inscribe it — into `GRIMDEX.md` only if it's true in every session all the time, else
  into the right playbook — then add an ACCEPTED entry to `PROMOTIONS-LOG.md` and
  delete the candidate from the inbox file.
- **Clean but evidence is single-project:** leave it in the inbox; add/refresh a
  DEFERRED ledger entry (reason: awaiting second project) **only if not already logged**.
- **Conflicts with law, rewrites law, or implies a removal:** leave it in the inbox;
  add a DEFERRED entry marked **needs the owner** with the specific conflict named. Never
  inscribe, never remove law yourself.
- **Plainly out of scope / duplicate of existing law:** REJECTED entry with reasons;
  remove from inbox.

## 4. Log, commit, push
Append one entry to `KB-AUDIT-LOG.md` (the format is at the top of that file):
mechanical findings + a one-line disposition summary (e.g. "2 accepted, 1 deferred").
Commit everything (`sweep: <n> accepted / <n> deferred / <n> rejected`), push.
If the push races, `git pull --rebase` and push again.
