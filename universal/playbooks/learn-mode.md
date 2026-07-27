# Learn mode (playbook)

**What it is.** An optional narration mode. When ON, the agent explains what it's doing in
plain English, uses the correct programmer jargon, and immediately defines that jargon — so
a user who is learning to code (e.g. while "vibe coding") builds real, transferable
vocabulary they can use when talking to other developers.

**Teaching layer only.** Learn mode never changes *what* gets built or its quality — only
*how* the work is narrated. (The intent: a user who understands the process writes sharper
prompts and gets better results.)

**When to read this.** Whenever an instance has learn mode enabled (see the toggle below).
The `project-start` playbook MAY offer to turn it on for a new user.

## Behavior when ON

- **Explain the what and the why** of each non-trivial action in a sentence or two of plain
  English — not just *what* changed but *why* it's being done.
- **Use the real terms** — `merge`, `pull request` (PR), `worktree`, `rebase`, `TDD`, `CI`,
  `gate`, `stash` — and **define each one inline the first time** it comes up in a given
  context. A short parenthetical or a one-line aside is enough.
- **Narrate the process, not only the code.** What a merge actually does, what a PR is for
  and who reads it, why the tests run before the implementation (test-driven development),
  what an isolated worktree protects.
- **Keep it tight.** Teaching, not lecturing. Optimize for a learner who wants to speak to
  other developers correctly — clarity over completeness.

## Behavior when OFF

Normal, concise narration. No jargon-defining asides. (The default for a fresh instance is
OFF unless the user opts in.)

## Tapering (fade, don't nag)

Learn mode should *diminish* as the user learns a term, not repeat forever. Taper each
jargon term by how many times it has been surfaced-with-a-definition:

- **First encounters (≈1–9):** explain in full.
- **After ~10 surfacings:** give a short, summarized reminder instead of the full definition.
- **After several more:** stop explaining it every time — refresh only occasionally
  (≈ every 3rd–4th use). The user has effectively learned it.
- **Explicit retire:** the user can say "I've got `<term>`" to stop explaining it immediately.

### The surfacing ledger (deterministic taper)

Cross-session tapering is backed by a **surfacing ledger** — a small per-instance count store,
`config/learn-progress.json` (instance data; never committed to the public engine), driven by
`scripts/learn-lib.ps1`:

- **Query a term's stage** any time with `Get-LearnStage -Progress (Get-LearnProgress -GrimdexRoot <root>) -Term <term>` →
  `full | summarized | occasional`. Map that to the tapering bands above (`full` = explain
  fully, `summarized` = short reminder, `occasional` = refresh only occasionally). An unseen
  term returns `full`. Thresholds live in the ledger (`full_max`, `summarized_max`).
- **Define each term with a consistent convention** so the parser can find it: the first time
  you define a term, write it as **`**term** — gloss`** (bold term, a space, an em dash or
  hyphen, a space, then the definition). That exact shape is what the counter keys on.
- **Recording surfacings — two feeders, same helper:**
  - *Parser (primary):* `scripts/parse-learn-transcript.ps1 -TranscriptPath <jsonl> -GrimdexRoot <root>`
    scans a session transcript for defined terms and records one surfacing each. Deterministic
    and ~free — run it from the daily sweep.
  - *Agent at close (fallback):* if no transcript is handy, at the compact/closeout seam call
    `Add-LearnSurfacing` for each term you defined this session, then `Save-LearnProgress`.

If the ledger is absent, `Get-LearnProgress` returns a default (everything reads as `full`),
so taper by best effort within the session until it fills in.

## Toggle

Learn mode is a **standing per-user preference**, not a per-task flag. Record the choice in
the instance's `universal/user-prefs.md` (and the user's agent memory, so it survives across
sessions). Turn it off with **"learn off"**, back on with **"learn on"** (also accepts
"learn mode off/on"). Do **not** overload "simplify" — that word already names a different
tool (code-simplification), so it makes a confusing off-switch.

This playbook (the generic behavior) is portable and ships in the public engine. The
*choice* to enable it is instance data and stays in `user-prefs.md`.
