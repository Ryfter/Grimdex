# Promotions inbox

**Normally empty.** This is the staging area for cross-project rule candidates. Each
project writes to **its own file** — `<project-id>.md`, one writer per file, no
contention. The daily sweep processes candidates and empties the inbox; a candidate
sitting here more than 7 days is itself a flagged finding.

How a candidate flows: project session (often the `project-end` harvest step) appends an
entry here → daily sweep conflict-checks it against `GRIMDEX.md`, `PROMOTIONS-LOG.md`
(past rejections), `RIPPEDPAGES.md` (past removals), and other pending candidates →
clean addition: auto-inscribed + logged; conflict/rewrite/removal: deferred for Kevin.

Candidate entry format (append to `<project-id>.md`):

```
## <short rule title>
**Proposed rule:** <one or two sentences, written as law — imperative, general>
**Evidence:** <what happened in this project that proves it; link decisions/lessons>
**Also seen in:** <other projects, if known — acceptance needs ≥2>
**Filed:** YYYY-MM-DD
```
