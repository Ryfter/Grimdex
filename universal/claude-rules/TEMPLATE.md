# claude-rules — mirror of global agent rules

If your agent harness keeps global rules outside any repo (e.g. Claude Code's
`~/.claude/rules/*.md`), mirror them here so they're backed up. `setup.ps1` redeploys
mirror → live on every run: missing files are deployed, identical ones skipped, and a
diverged live copy is **reported, never silently overwritten** (overwrite requires
`-Force` via `Sync-GrimdexRules`).
