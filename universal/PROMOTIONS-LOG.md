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
