# Playbook: starting a project

Read when creating or bootstrapping a new project. (The law in `GRIMDEX.md` still
applies; this is the moment-specific checklist.) Work top to bottom — a project
bootstrapped from this playbook alone should need no tribal knowledge.

## 1. Repo
- Create the GitHub repo under `Ryfter/`, **private** by default.
- Default branch **`main`** for new projects (existing repos keep their convention).
- Seed `README.md`: what the project is, how to run it cold, current status.
- **Push the first commit before writing more** — the backup standing order applies
  from minute one: everything to GitHub, every session, don't ask.
- Tag-worthy milestones get tags; the final resting state gets `vX.Y-final`
  (see the project-end playbook).

## 2. Work tracking
- **GitHub Issues + a Project board from day one.** Issues carry a tier label
  (`Tier-1` = must, `Tier-2` = should, `Tier-3` = nice) and enough body to be worked
  cold: scope, risks, acceptance criteria.
- `gh` CLI notes: issue/PR bodies via `--body-file` (965-byte rule, below);
  `gh issue create --project` needs the `project` auth scope.
- Work item flow: issue → branch → gated merge → `Closes #N` in the merge commit
  auto-closes and moves the board.

## 3. Shipping discipline
- **Gated merges:** every work item on its own branch; the test gate must be green
  before merge; the default branch stays green, always.
- the operator gates anything user-facing, destructive, or scope-changing. Mechanical
  follow-ups within an approved scope may merge on a green gate.

## 4. Repo conventions
- `scripts/` — automation in the **lib + thin-driver** pattern: logic in
  `<area>-lib.ps1` (testable functions), drivers stay shallow.
- Tests: `scripts/test-<area>.ps1` — plain pwsh, an `Assert` helper, exit 1 on any
  failure. **Tests run entirely against temp-dir fixtures; never mutate the live
  knowledge store or the user's real config** (proven across grimdex +
  baton).
- `docs/` — specs and plans, dated: `docs/YYYY-MM-DD-<slug>-spec.md`. Design-first
  for non-trivial work: brainstorm → lean spec → build; the spec names what was
  decided and why.
- **965-byte shell-argument ceiling:** never pass long content (commit message,
  prompt, file body) as one shell argument — write a file and read it; prefer small
  separate commands over long `&&` chains.

## 5. Multi-agent setup
- Run `pwsh $HOME/dev/Grimdex/scripts/wire-project.ps1 -ProjectDir <dir>` — injects the
  Grimdex pointer stanza into `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` /
  `.cursorrules` / `.github/copilot-instructions.md` (idempotent; commit on a branch).
- If multiple agents will work the repo, use the **shared-core + registry** pattern
  (anti-drift, proven in baton's `docs/agent-handoffs.md`):
  shared rules live in ONE doc; each model's instruction file *references* it and
  adds only model-specific notes; every divergence is listed in a registry table.
  Re-copying shared rules between model files is how drift starts — don't.

## 6. Knowledge wiring
- Create the project's Grimdex tier: `projects/<project-id>/` with `decisions/`.
- **Decision capture from day one:** any choice with real alternatives that shapes
  direction (architecture, scope, approach, tech) becomes
  `decisions/dNNN-<slug>.md` — frontmatter `id, timestamp, project, status,
  confidence, revisit-if`; body **Chosen / Alternatives / Rationale / Feedback**.
  Threshold: "would this belong in a spec's Decisions section?" Skip micro-choices.
  d001 usually exists by the end of day one — if it doesn't, ask what went uncaptured.
- Standing constraints and norms go in `projects/<project-id>/decision-guidance.md`.
- Cross-project rule ideas → `universal/promotions/<project-id>.md` (inbox README has
  the format) — never edit the law directly.
