# Promotions inbox

**Normally empty.** The daily sweep drains it. Two channels live here, told apart by a
`kind:` frontmatter field and filename.

## 1. Promotion candidates — `<project-id>.md`

A learned coding rule proposed for the universal law (`GRIMDEX.md`), promoted only on
≥2-project evidence. Each project writes to **its own file** — one writer per file, no
contention. The daily sweep conflict-checks each candidate against `GRIMDEX.md`,
`PROMOTIONS-LOG.md` (past rejections), `RIPPEDPAGES.md` (past removals), and other pending
candidates → clean addition: auto-inscribed + logged; conflict/rewrite/removal: **deferred
for the human maintainer**. A candidate sitting here more than 7 days is itself a flagged
finding.

Candidate entry format (append to `<project-id>.md`):

```
## <short rule title>
**Proposed rule:** <one or two sentences, written as law — imperative, general>
**Evidence:** <what happened in this project that proves it; link decisions/lessons>
**Also seen in:** <other projects, if known — acceptance needs ≥2>
**Filed:** YYYY-MM-DD
```

A worked example (sanitized from real use):
[`examples/promotion-personal-data-tree.md`](../../examples/promotion-personal-data-tree.md).

## 2. Rule-sync proposals — `<machine>.sync.md`

A rule/law edit authored on a *spoke* machine in a multi-machine setup, queued for the
*hub* to publish (see `scripts/sync-lib.ps1` and the `propose-rule` /
`review-rule-proposals` drivers). Frontmatter `kind: rule-sync`, with `machine`,
`timestamp`, `target` (the rule/law file to change), and a `note`; the body is the full
proposed content of that target. Filed by `scripts/propose-rule.ps1` on a spoke. The sweep
only *surfaces* these (it never applies them — a law edit is human-gated); the hub runs
`scripts/review-rule-proposals.ps1` to accept (publish to the target + ledger) or reject.
Targets are restricted to `GRIMDEX.md` and `universal/claude-rules/*`.
