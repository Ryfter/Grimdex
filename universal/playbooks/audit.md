# Playbook: the weekly KB audit (Sunday 5:30 am routine)

You are running Grimdex's weekly health audit. Working directory: `D:\Dev\Grimdex`.
**You may auto-fix purely mechanical rot. You may never change knowledge content** —
semantic concerns are flagged for the owner, and his ruling (either way) gets recorded. Be
terse; the audit is incremental — focus on what changed since the last audit entry in
`KB-AUDIT-LOG.md`.

## 1. Mechanical pass
Run: `pwsh -NoProfile -File scripts/sweep.ps1`
(sync + the same mechanical checks as the daily sweep, over the whole repo).

## 2. Auto-fix mechanical rot only
For findings that are *mechanically unambiguous* — a relative link pointing at a file
that was renamed (target findable), a dead pointer to a file that exists elsewhere —
fix them, one commit per fix class (`audit: fix dead links in <area>`). If the right
fix isn't obvious, it is not mechanical: flag it instead. Never renumber decision ids
that are referenced elsewhere — flag those.

## 3. Semantic checks — flag, never fix
- **Project-tier consistency vs the law:** read each `projects/<id>/decision-guidance.md`
  and recent decisions; flag anything that *opposes* `GRIMDEX.md` or a playbook.
- **Cross-project contamination:** entries in project A referencing issues/PRs/files
  that belong to project B.
- **Dormant-project reconciliation:** for projects untouched since the last audit,
  spot-check "shipped/closed" claims against the live tracker (`gh`) when available.
- **Backup coverage:** repo clean and pushed; nothing that should live in Grimdex
  sitting only on the local disk (check the known mirrors: `universal/claude-rules/`).
- **Inbox staleness:** candidates older than 7 days (the sweep should have processed
  or deferred them — staleness means the loop is broken).

## 4. Report
Append ONE entry to `KB-AUDIT-LOG.md` (format at the top of that file): auto-fixes
listed, each semantic concern as **OPEN CONCERN — needs the owner** with file paths and a
one-line proposed resolution. Check previous entries: if a past OPEN CONCERN is now
resolved or ruled on, note that. Commit (`audit: weekly — <n> fixed, <n> flagged`),
push (rebase-and-retry on race).
