# Suggested rules — community-converged starting candidates

Grimdex's law (rule #7) says rules earn their way in with **evidence from observed
failures** — you shouldn't write rules from anticipation. That creates a cold-start
problem: a fresh instance has no incidents yet. This file is the bridge. Every rule
below was independently advocated by **three or more prominent practitioners** of
AI-assisted coding — meaning the community already paid the incident cost for you.

Treat these as *candidates*, not law. Adopt the ones that fit how you work, skip the
rest, and let your own incidents add the next rules. A bigger instruction file is not
a better one: frontier models reliably follow roughly 150–200 instructions, and your
harness's system prompt already spends ~50 of that budget. Spend the rest carefully.

> Some coding harnesses (plugins, skills, system prompts) already enforce a few of
> these. Enumerate them anyway: a Grimdex instance travels to *every* tool — Claude,
> Codex, Gemini, Copilot, Cursor, local models — and a rule that lives only inside
> one tool's plugin is invisible to the rest of the fleet.

## The convergence table

| # | Convention | Independently advocated by |
|---|---|---|
| 1 | Verify before claiming done | Anthropic best-practices, Boris Cherny, Harper Reed, Sabrina Ramonov |
| 2 | Root cause, not symptom | Anthropic, Harper Reed, Jesse Vincent |
| 3 | Tests are load-bearing — never delete, weaken, or mock them away | Harper Reed, Geoffrey Huntley, Sabrina Ramonov |
| 4 | Surgical diffs — every changed line traces to the request | Andrej Karpathy, Builder.io, AGENTS.md ecosystem |
| 5 | Dependency gate — no new deps without approval | Builder.io, Anthropic, AGENTS.md ecosystem |
| 6 | Comment policy — no narration, evergreen wording | Sabrina Ramonov, Harper Reed, GitLab |
| 7 | Autonomy tiers — green / yellow / red | Harper Reed, Sabrina Ramonov, Andrej Karpathy |

## The rules

Each block is written as law — imperative and general — so it can be pasted directly
into an instance's `GRIMDEX.md`, a `decision-guidance.md`, or filed through the
promotions inbox (recommended; see the prompt at the bottom).

### 1. Verify before claiming done

> Run the project's tests, typecheck, and lint — and read the output — before saying
> "done", "fixed", or "passing". Evidence before assertions: if verification was not
> run, say so plainly instead of claiming success.

**Why:** the most common agent failure is the confident false "it works". Boris
Cherny (Claude Code's creator) calls giving the agent a way to verify its work his
single highest-leverage tip, estimating 2–3× output quality. Simon Willison: without
tests "your agent might claim something works without having actually tested it at
all."

### 2. Root cause, not symptom

> Fix the cause, never the symptom. Do not suppress an error, disable functionality,
> or special-case around a bug to make output green. If two fix attempts fail, stop
> and re-diagnose instead of trying a third variation.

**Why:** agents under pressure to show progress will route around a bug rather than
into it — the fix that "makes the red go away" while the defect ships. The
two-attempts-then-rethink threshold is Harper Reed's; the rest is consensus.

### 3. Tests are load-bearing

> Never delete, skip, or weaken a failing test to make a run pass. Never present
> mock, stub, or placeholder implementations as complete work. Prefer integration
> tests over heavy mocking.

**Why:** the cheapest way to "pass" is to remove the thing that fails, and agents
find it. Geoffrey Huntley's looped-agent setups carry an all-caps anti-placeholder
rule because unattended agents otherwise converge on stubs; Harper Reed's testing
section is titled "NO EXCEPTIONS POLICY" for the same reason.

### 4. Surgical diffs

> Every changed line must trace directly to the request. Do not refactor unrelated
> code, reformat untouched files, or "improve" working code without being asked.
> Match the surrounding style even where you would choose differently.

**Why:** drive-by changes bloat review, hide the real diff, and introduce regressions
in code nobody asked you to touch. Karpathy's phrasing: "Touch only what the user's
request requires."

### 5. Dependency gate

> Do not add a new dependency without explicit approval. Prefer the libraries already
> in the project; prefer writing a small amount of code over importing a large
> dependency for one function.

**Why:** each dependency is a supply-chain, maintenance, and licensing decision the
human owns. Agents reach for a package by reflex because training data does.

### 6. Comment policy

> Comments state only what the code cannot: constraints, invariants, and gotchas.
> No narration comments (restating what the next line does, or that something
> changed). Comment wording must be evergreen — never "new", "improved", "now
> handles", or other words that date the moment of writing.

**Why:** agents narrate their work into the code, talking to the reviewer instead of
the next reader. Those comments are noise the moment they merge — and "temporal"
comments are wrong within weeks.

### 7. Autonomy tiers

> Green — do autonomously: fix failing tests, lint errors, typos, and obvious
> mechanical follow-ups within the approved scope.
> Yellow — propose first: multi-file changes, new features, API or schema changes,
> new patterns.
> Red — always ask: rewriting working code, security-sensitive code, anything
> destructive or hard to reverse.

**Why:** "ask when uncertain" is too vague to follow; a three-tier boundary is
concrete enough to act on. This is Harper Reed's green/yellow/red framework, the
single most-copied autonomy rule in circulation.

## Meta-rules — about the instruction file itself

These govern the KB rather than the code, and they are already partially built into
Grimdex (law #7, the audit playbook). Listed so adopters see the reasoning:

- **Every line traces to an observed failure.** Rules written from anticipation go
  unfollowed ("rules made from scratch are usually not followed" — community
  consensus). Mitchell Hashimoto on Ghostty's agent file: "each line in that file is
  based on a bad agent behavior."
- **Prune ruthlessly.** Anthropic's test: "for each line ask — would removing this
  cause mistakes? If not, cut it." Bloated files cause the *important* rules to be
  ignored.
- **Escalate instead of repeating.** Advisory prose → emphasis (IMPORTANT / NEVER) →
  on-demand playbook → objective gate → hook/CI. A rule violated twice despite
  emphasis becomes a script, not a louder sentence. (Anthropic: "instructions are
  advisory, hooks are deterministic.")
- **Plant a canary.** One harmless quirk instruction in the law; if output stops
  honoring it, the file isn't being loaded — a plumbing problem no amount of rule
  wording fixes.
- **Position and phrasing matter.** Critical rules go first or last (mid-file recall
  is weakest); phrase positively where possible ("Always X" over "Never Y" — negative
  rules can prime the very behavior they forbid).

## Seeding your instance — hand this file to your LLM

Paste this prompt into your coding agent inside your Grimdex instance:

```
Read GRIMDEX.md first, then SUGGESTED-RULES.md. Walk me through the seven suggested
rules one at a time: for each, ask me adopt / adapt / skip, and apply any wording
changes I give you. File every adopted rule as a candidate in
universal/promotions/seed.md using the inbox format from universal/promotions/README.md,
with evidence "community-sourced: SUGGESTED-RULES.md convergence table" and a note
that admission is human-gated (the ≥2-project evidence bar cannot be met at seeding
time, so my explicit approval substitutes). Do NOT inscribe anything into GRIMDEX.md
directly — that is the sweep's job after I approve. Finish by showing me the seed.md
file and reminding me the rules become law only when the sweep processes them.
```

This keeps seeding honest with the same paper trail as organic rules: inbox →
ledger → law, with you as the gate.

---

*Sources behind the table: Anthropic's Claude Code best-practices guide; Boris
Cherny's published workflow; Mitchell Hashimoto's Ghostty AGENTS.md and "harness
engineering" posts; Harper Reed's and Jesse Vincent's public CLAUDE.md files; Sabrina
Ramonov's ai-coding-rules; Karpathy's CLAUDE.md principles; Builder.io's AGENTS.md
guide; the agents.md ecosystem (ghostty, openai/codex, vercel/next.js,
apache/airflow). Empirical caveats that shaped the meta-rules: instruction-following
degrades past ~150–200 instructions; LLM-generated instruction files that duplicate
repo-discoverable content measurably hurt task success while raising cost; nested
scoped files outperform consolidated monoliths.*
