<!-- EXAMPLE decision-guidance.md, sanitized composite drawn from real use. This is
     the third artifact type alongside the decision record (d014-*.md) and the
     promotion candidate (promotion-*.md): the per-project standing-constraints file
     at projects/<project-id>/decision-guidance.md. Every entry is "scar tissue" —
     it cites the incident that created it (law #7). No rules from anticipation. -->

# <project-id> — decision guidance

Standing constraints and lessons for this project. Agents read this before working
here; agents append to it when an incident teaches something durable. Keep entries
one to three lines: the rule, then the incident that earned it.

- **Run the filtered tests, not the full suite** (`make test FILTER=<area>`): the
  full suite takes 11 minutes; agents timed out and started skipping verification
  entirely. (2026-03-04; cost two broken merges before this was written.)
- **Never edit `schema.sql` directly — write a migration.** An agent "fixed" the
  schema file in place; drift broke the prod restore path. (2026-02-19, see d007.)
- **The vendor API returns HTTP 200 with an error body** — check `body.status`,
  never the status code. (Three separate false "it works" claims traced to this.)
- **The e2e fixtures are generated — edit `fixtures/src/`, then `make fixtures`.**
  Hand-edited output files were silently overwritten on the next build. (2026-04-11.)
- **Don't upgrade `libfoo` past 2.x** until the async rewrite lands — 3.x changes
  the callback ordering this project's queue depends on. (d012; revisit-if is set.)
