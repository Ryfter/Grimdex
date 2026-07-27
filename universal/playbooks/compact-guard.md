# Compact closeout-guard (playbook)

**What it is.** A deterministic backstop for the "save everything off before compacting" rule
(the task-group-closeout / law-#7 discipline). Instead of trusting the agent to remember, a
Claude Code **PreCompact** hook inspects the repo right before any compaction and **blocks** it
if a closeout is still pending — so conversation context is never compressed with unsaved work.

**Why only this half.** A companion idea — a Stop-hook that nudges "you're past ~50%, compact
now" — was evaluated and **dropped** (2026-07-26): a Stop hook cannot surface a message to the
human (its output only feeds the model) and true context-% is not exposed to hooks, so it can't
be made deterministic, and forcing early compaction can cost answer quality. Claude Code's own
auto-compact is the hard ceiling; this guard makes that ceiling *safe* rather than trying to
pre-empt it.

## Behavior

`scripts/precompact-guard.ps1` (driver) + `scripts/precompact-lib.ps1` (`Get-CloseoutStatus`):

- Reads the PreCompact hook JSON on stdin, resolves the git repo at `cwd`.
- **Uncommitted changes** (`git status --porcelain`) or **unpushed commits** (ahead of
  upstream) → **exit 2** with `{"decision":"block","reason":"…"}`; the reason names the repo and
  what's unsaved and tells the agent to save off, then compact again. The retry passes once the
  closeout runs.
- Clean → **exit 0** (allow, silent).
- **Fail-safe:** missing git, a non-repo path, or garbled stdin → **exit 0**. The guard only
  ever blocks on a *confirmed* unsaved-work signal, so it can never wedge a session.
- **Wire it to `manual` only.** PreCompact fires for both triggers, but the guard should be
  scoped to `matcher: "manual"` (the deliberate `/compact`). Blocking an **auto**-compaction —
  the host's own emergency response to a full context window — refuses the session's escape
  hatch at exactly the moment it needs it, and the host's behavior on a refused auto-compact is
  undefined. Guard the deliberate seam; never interfere with the ceiling.

## Wiring (settings.json)

Add to `~/.claude/settings.json` (user-wide) or a project `.claude/settings.json`. Windows /
PowerShell 7:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "manual",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"<grimdex-root>/scripts/precompact-guard.ps1\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

`matcher: "manual"` scopes the guard to the deliberate `/compact` and leaves auto-compaction
alone (see Behavior — do **not** use `""`, which would also gate the host's emergency
compaction). Replace `<grimdex-root>` with the absolute path to your Grimdex instance. On other
platforms swap the `pwsh` invocation as needed; the script itself is cross-platform PowerShell 7.

## Notes

- Blocking on **unpushed** commits enforces the standing "back up to GitHub" step of closeout.
  If an instance wants to allow compacting with committed-but-unpushed work, adjust the lib to
  gate on `Uncommitted` only.
- The script is generic and ships in the public engine; whether to *wire* it is a per-instance
  choice (it edits your live settings), so it is presented, not installed automatically.
