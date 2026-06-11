# Playbook: starting a project (stub — flesh out with your conventions)

Read when creating or bootstrapping a new project.

1. **Repo:** create it (private by default), seed a README, push the first commit
   before writing more. Add your branch/merge discipline here.
2. **Tracking:** decide where work items live (issues, board, backlog doc) and the
   labeling scheme.
3. **Wire into Grimdex:** `pwsh <grimdex>/scripts/wire-project.ps1 -ProjectDir <dir>` —
   injects the pointer stanza into every agent instruction file (idempotent).
4. **Knowledge tier:** create `projects/<project-id>/` with `decisions/`. Capture the
   first decision record (d001) by end of day one — format in `GRIMDEX.md` law #1.
5. Add your repo conventions (folder layout, test patterns, scripting limits) here so
   a project bootstraps with zero tribal knowledge.
