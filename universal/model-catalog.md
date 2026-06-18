# Model catalog — what the fleet runs

The reference list of models that contribute to this Grimdex instance. Paired with each
project's `projects/<id>/model-usage.md` log, it answers two questions: *what models do
we use*, and *which of them is now superseded* (so the audit can flag work that may
warrant a second look). Reference, not law — it grows through normal use, not the
promotions gate.

## Model-identity schema

Name every model the same way, here and in usage logs: **`runner/model (params)`**

- `runner` — the app/harness executing the model: `claude-code`, `codex`, `ollama`,
  `lm-studio`.
- `model` — the model name/tag: `opus-4.8`, `sonnet-4.6`, `codex-5.5`,
  `qwen2.5-coder:32b-q4`.
- `params` — runner-specific knobs, omitted when none. Codex reasoning level:
  `(reasoning:high)` — one of `low | medium | high | xhigh`.

Examples: `claude-code/opus-4.8` · `codex/codex-5.4-mini (reasoning:high)` ·
`ollama/qwen2.5-coder:32b-q4`

## How this file is maintained

- **Self-registration (clean add, inline, at closeout/compact).** When an agent stamps
  its usage-log line, it also checks here: if its own `runner/model` is absent — or newer
  than the latest entry for that runner — it adds it as `current`. New versions catalogue
  themselves the first time they run. An add is an observed fact, so it needs no human.
- **Supersession (judgment, weekly audit, human-gated).** Marking a prior entry
  `superseded → <successor>` and flagging dependent usage-log steps is the audit's job —
  never auto-acted. Superseded entries are kept, never deleted (the history is the point).

Frontier and local differ: frontier models are a small, named, authoritative set; local
models have no "latest" feed, so they are catalogued **bottom-up from observed usage**.

## Frontier models

| runner | model | status | first-seen | notes |
|---|---|---|---|---|
| claude-code | fable-5 | current | 2026-06 | |
| claude-code | opus-4.8 | current | 2026-06 | |
| claude-code | sonnet-4.6 | current | 2026-06 | |
| claude-code | haiku-4.5 | current | 2026-06 | |
| codex | codex-5.5 | current | 2026-06 | reasoning: low/medium/high/xhigh |
| codex | codex-5.4 | current | 2026-06 | reasoning: low/medium/high/xhigh |
| codex | codex-5.4-mini | current | 2026-06 | reasoning: low/medium/high/xhigh |

<!-- Seeded with the models known current as of 2026-06. When a newer one is used, it
     self-registers as a new `current` row; the audit later marks the one it replaces
     `superseded → <successor>`. -->

## Local models

Built bottom-up: a local model appears here the first time it shows up in a usage log.
Track the role it plays so a swap reads as a transition, not a silent replacement.

| runner | model | role | first-seen | last-seen | superseded-by |
|---|---|---|---|---|---|
| _(none yet — fills in from observed usage)_ | | | | | |

<!-- Example row, once a local model is in use:
| ollama | qwen2.5-coder:32b-q4 | summaries | 2026-06-15 | 2026-06-18 | — |
-->
