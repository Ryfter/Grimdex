---
id: d014
timestamp: 2026-06-04T23:51:11-06:00
project: coding-agent-orchestrator
job: null
phase: null
status: active
confidence: high
revisit-if: "a tool needs a fundamentally incompatible knowledge format, forcing per-tool silos"
flag: null
---

<!-- EXAMPLE decision record, drawn (lightly sanitized) from real use. This is the
     format the law's rule #1 describes: frontmatter + Chosen / Alternatives /
     Rationale / Feedback. -->

# Knowledge base is model/tool-agnostic, named `knowledge` (not claude-knowledge)

**Chosen:** Maintain one private, vendor-neutral knowledge repo (renamed from `claude-knowledge`) as the system of record for decisions, guidance, routing, and per-project data. Any agent — GitHub Copilot, Grok, Gemini, ChatGPT/Codex, Claude, local models, and future tools — reads and contributes to it. Tool/harness-specific config is isolated under `config/` so the neutral core stays clean.

**Alternatives:**
- `claude-knowledge` tied to Claude — rejected: silos knowledge to one vendor while the user runs a multi-model fleet.
- Per-tool knowledge bases — rejected: duplication + drift; decisions are about the work, not the model reading them.
- Keep knowledge only inside app repos — rejected: records scatter and can't be reused across projects/tools.

**Rationale:** The accumulated decisions, preferences, and routing describe the work and the user, independent of whichever model reads them. A single neutral knowledge layer lets the whole fleet — and tools not yet invented — share one brain. Isolating harness config under `config/` keeps the portable knowledge free of vendor specifics. Reinforced by the multi-model handoffs (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) all pointing at the same shared knowledge.

## Feedback

<!-- consolidated 2026-06-05 -->
