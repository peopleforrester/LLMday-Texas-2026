# 30-Minute Talk Outline (stub)

Title: Your MLOps Pipeline is your Agentic AI Guardrail
Slot: 2026-05-12, 2:30 PM, 30 minutes, Beginner

This is a stub. The full outline has not been drafted yet. The notes below capture the source materials to draw from and the structural beats the talk needs to hit. Replace this content with the actual outline once it is written.

## Structural beats the talk must hit

1. The incident hook (etcd force-refresh into netplan wipe across all nodes).
2. The wrong lesson (humans-in-the-loop) versus the right lesson (deterministic gates with autonomous operation inside the boundary).
3. The Agentic Covenants Matrix as recognition, not introduction. Six MLOps stages mapped to six covenants. The matrix and broader Agentic Covenants Framework are maintained at `github.com/peopleforrester/agentic-covenants`. Reference that repo on stage and in slides; do not lift content from it into this repo. (See the article for the canonical mapping as it appears in this talk.)
4. The Eight Guardrails Framework as the concrete implementation across three enforcement layers (Claude Code pre-tool-use hooks, Git hooks, Kubernetes infrastructure controls).
5. The failure chain mapped to the gate that would have stopped each step.
6. Gap checklist takeaway so the audience leaves with a usable artifact.

## Source materials to draw from

- `../mlops-as-agentic-guardrail.md` (this repo) — the published article and canonical mapping.
- `events/kubeauto-ai-day/docs/EIGHT-GUARDRAILS.md` — full Eight Guardrails framework.
- `events/kubeauto-ai-day/collateral/slide-outline.md` — reusable slide patterns for the Three-Layer Guardrails diagram and Eight Guardrails table.
- `events/DevOpsDays-Atlanta-2026/layer-1-git-ci/`, `layer-2-kubernetes/`, `layer-3-claude-hooks/` — concrete control implementations across the three layers.
- `events/DevOpsDays-Atlanta-2026/presentation-recovery/PRESENTATION-EXTRACT.md` — narrative arc from the Ignite version, useful as raw material to expand from 5 minutes to 30.
- `events/claude-deleted-my-cluster-2026/context/forensic-evidence.md` and `cfp-incident-references.md` — incident detail.

## Writing standards (apply to slides and speaker notes)

Same as the article: no em-dashes, no AI-isms, no parallel closing sentence pairs.

## Open questions to resolve before drafting

- Live demo or no demo? The KubeAuto talk had a live demo. A 30-min talk at LLMday could either include a guardrails demo (gate firing in real time on a malformed tool call) or stay purely narrative.
- How explicit to make the connection to the standalone Agentic Covenants repo (`github.com/peopleforrester/agentic-covenants`). Brief reference at the end, or a structural callback throughout?
- Which two or three Guardrails to deep-dive versus which to summarize. Eight is too many for 30 minutes at adequate depth.
