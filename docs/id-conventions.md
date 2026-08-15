# ID conventions — every identifier in the ecosystem, and who owns it

**Status:** authoritative · **Scope:** Grimdex, Grimlore, Baton

This ecosystem uses a lot of numbers. **Most of them cannot be unified, and shouldn't be** —
GitHub owns issue numbers, semver owns version tags, `GRIMDEX.md` owns law numbers. Forcing
them into one scheme would mean building a translation layer worse than the problem it solves.

What *was* fixable is that they were undocumented, so a bare number gave no clue which system
it belonged to. This page is the index. **If you write an identifier anywhere, write it in the
canonical form below.**

## The table

| Id | Form | Owner | Scope | Example |
|---|---|---|---|---|
| **Decision record** | `<prefix>-dNNN` | Grimdex | per project tier | `baton-d107` |
| **Law** | `law #N` | `GRIMDEX.md` | global | `law #7` |
| **Promotion candidate** | file in `universal/promotions/<project-id>.md` | Grimdex | per project | — |
| **GitHub issue** | `#N` | GitHub | per repo | `#115` |
| **Pull request** | `PR #N` | GitHub | per repo | `PR #130` |
| **GitHub Projects item** | `board N / item N` | GitHub | per board | `board 5 / item 12` |
| **Release** | `vX.Y.Z` (semver) | the repo | per repo | `v1.21.0` |
| **Grimlore concept** | bundle-relative path, no `.md` | Grimlore | per bundle | `/models/opus-5` |
| **Paired policy** | `policy_id` slug | Grimlore ⇄ Grimdex | global | `quota-codex-window` |
| **Job** | job id | Baton | per machine | — |

**Rule of thumb:** a leading `#` means **GitHub**. A leading `v` means a **release**. A `dNNN`
means a **decision**. Anything else, check this table before inventing a new one.

## Laws stand apart — and stay exactly as they are

**`law #N` is not being changed, qualified, or renumbered.** It is deliberately unprefixed, and
that is not an oversight in a scheme that qualifies everything else — **the id form encodes the
tier**:

| | **Law** | **Decision record** |
|---|---|---|
| Id | `law #7` — unqualified | `baton-d107` — project-qualified |
| Scope | **global** — binds every project | **local** — one project's tier |
| Standing | has stood the test of time | a considered call, at a point in time |
| Mutability | changes only through the maintained loop (law #4): promotion gate, human gate, `PROMOTIONS-LOG.md` on admission, `RIPPEDPAGES.md` on removal — **never silently** | written freely; superseded by a later record; carries its own `revisit-if` |
| Count | few, aggressively trimmed | many, and growing |

A law is unqualified **because** it is universal — prefixing it would falsely imply a scope it
doesn't have. A decision is qualified **because** it is local. The two forms are visually
distinct at a glance, which is the whole point of this page.

**`[PROVISIONAL]` laws** carry one extra mark. A new framework cannot produce evidence before
it exists, yet cannot function until its governing rules do — so law #7 permits a
maintainer-dictated, structural rule to be admitted on necessity, marked `[PROVISIONAL]`, and
stating the condition that earns it permanence. **The mark describes its evidence, not its
force:** a provisional law binds exactly like any other. The audit flags one whose condition is
met, or whose framework still doesn't exist after two cycles.

**Precedence: a law outranks a decision.** Where a decision record conflicts with a law, the law
governs and the decision is wrong — not the other way round. A decision may *inform* a change to
the law, but only by travelling the law's own route (a promotion candidate, ledgered). It never
overrides one by sitting next to it.

Practical consequence: **do not "fix" a law by writing a decision record that contradicts it.**
That produces two live rules and no resolution. File a promotion candidate instead.

## Decision records — the one we control, in full

Ids are assigned **per project tier**, so a bare `d018` is genuinely ambiguous: in
`projects/baton/` it is *"orchestrator is conductor"*; in `projects/grimdex/` it is *"the
three-layer ecosystem boundary."* The canonical form is therefore **project-qualified**:

```
<prefix>-dNNN          baton-d107   grimdex-d022   canvas-d007
```

### Prefix resolution

1. `projects/<project-id>/.prefix` — a one-line short alias, **only** when the project-id is
   too long to read comfortably in prose.
2. Otherwise, the **project-id itself**. Most projects need no `.prefix` file at all.

Prefixes **must be unique** across every tier. This is enforced mechanically, not by
convention: `scripts/migrate-decision-ids.ps1` hard-fails on a collision, and the id assigner
resolves through the same helper (`Get-DecisionPrefix`).

| Project id | Prefix | |
|---|---|---|
| `baton` | `baton` | default |
| `grimdex` | `grimdex` | default |
| `grimdex-edu` | `grimdex-edu` | default |
| `atomicforge` | `atomicforge` | default |
| `answerbot`, `bbq-bard`, `ed-colony`, `kidsbats`, `bench-gauntlet` | *same as project id* | default |
| `canvas-toolchain` | `canvas` | alias |
| `whimsicalcarving` | `whimsy` | alias |
| `xai-socials-tracker` | `xai` | alias |
| `my-dashboard` | `dash` | alias |
| `atomic-ego-proj` | `atomic-ego` | alias |

**Guideline:** alias when the project-id exceeds ~11 characters. Prefer a real word over a
code — `canvas` needs no decoder ring; `c01` does. Adding an opaque code scheme would create
exactly the kind of extra number type this page exists to reduce.

### Filenames stay bare

```
projects/baton/decisions/d107-authenticated-http-instruments.md
  ---
  id: baton-d107          <- canonical, qualified
  project: baton
  ---
  # baton-d107 — Authenticated HTTP instruments …
```

The **folder** namespaces the file on disk; the **prefix** namespaces the reference. Putting
the prefix in the filename too would make `projects/baton/decisions/baton-d107-….md` — the
project named twice in one path, for no gain.

### When a bare `dNNN` is acceptable

Only **inside that project's own tier** — its decision records, its `decision-guidance.md`.
Everywhere else, qualify. In particular: a bare id in an app repo's docs, in a handoff file,
or in conversation is ambiguous and should be written qualified.

## Cross-referencing GitHub

Grimlore concepts may carry development coordinates — issues, PRs, project-board items,
assignees — via the **`x-grimdex` extension** (see the Grimlore spec, §2b). Those fields hold
**coordinates, not content**: the number that locates the item on GitHub, never a copy of its
title, body, or live status. GitHub is the source of truth for everything it stores; mirroring
it into a knowledge file creates a second, staler copy that nothing reconciles.

## Adding a new id type

Don't, if an existing one fits. If you genuinely must:

1. Add a row to the table above **in the same change** that introduces it.
2. State its owner and its scope (global / per repo / per project / per bundle).
3. Make its form visually distinct from the ones already listed, so a bare instance is
   self-identifying.
