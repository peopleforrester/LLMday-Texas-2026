# Talk Outline: Your MLOps Pipeline Is Your Agentic AI Guardrail

As-delivered outline derived from the v06 slide deck. The deck at `../presentations/llmday-austin-2026-mlops-pipeline-guardrail-v06.pptx` and its speaker notes are the canonical artifacts. This file is the readable summary for anyone landing in the repo without PowerPoint.

Slot: 2026-05-12, 2:30 PM, 30 minutes, Beginner. 19 slides.

## Section 1: Open and thesis (~3 min, slides 1-3)

- Slide 1: Title. Open straight into the inversion. No long bio.
- Slide 2: "You already built it. You just called it MLOps." Mapping table from MLOps stages (feature store, model registry, validation gates, canary deployment) to four of the five Protect concerns. Drift detection and rollback automation live in the companion Detect and Recover matrices, not in Protect.
- Slide 3: The principle. Don't use probabilistic AI to enforce deterministic requirements.

## Section 2: Why the MLOps assumption breaks (~3 min, slides 4-5)

- Slide 4: MLOps assumed the agent was inside the pipeline. Agentic AI puts the agent driving it. The wrong instinct: humans-in-loop on every action. Why it fails: alert fatigue and a ~93% rubber-stamp rate.
- Slide 5: Three public incidents (AWS Kiro December 2025, PocketOS April 2026, Replit/SaaStr July 2025) plus a verbal nod to the SREday cluster story for audience overlap.

## Section 3: The Agentic Covenants Matrix (~3 min, slides 6-7)

- Slide 6: Matrix reveal. Three layers (in-agent, client-side hooks, server-side) crossed with five concerns (identity, authorization, blast radius, approval gating, supply chain). Fifteen cells. Walk left-to-right per row, asking: if the agent decides to violate this concern, what stops it at this layer?
- Slide 7: Scope to NIST CSF 2.0 Protect. Detect, Respond, and Recover are separate matrices that compose with this one. Most "AI guardrail" content mixes the four functions; that is the bug this matrix corrects.

## Section 4: The three layers, walked (~6 min, slides 8-10)

- Slide 8: Layer 1, in-agent. A vibe, not a control. Bypass paths: prompt injection, jailbreak, compaction wiping the rules.
- Slide 9: Layer 2, client-side hooks. The unsung hero. Catches casual misuse. Bypass paths: `--no-verify`, equivalent commands the pattern does not match, filesystem tampering.
- Slide 10: Layer 3, server-side. Different in kind, not just in degree. Requires a separate principal compromise to defeat.

## Section 5: Translation across platforms (~2 min, slide 11)

- Slide 11: Same matrix, two vocabularies. Kubernetes-native (PreToolUse, RBAC, Kyverno) and MLOps-native (MLflow client wrapper, SageMaker execution role, registry stage policy). If you do not run Kubernetes, the matrix still applies.

## Section 6: The other four concerns (~2 min, slide 12)

- Slide 12: Top-hits view of identity, blast radius, approval gating, supply chain. Full matrix in the resources slide. Each concern is a different surface area on the agent.

## Section 7: Walking the failure chain through the matrix (~3 min, slide 13)

- Slide 13: Same five beats from the SREday cluster incident, mapped to the cells that would have stopped each beat. Closure of the narrative arc opened on slide 6.

## Section 8: Defense in depth, honestly framed (~3 min, slides 14-15)

- Slide 14: The stack works together. Server-side is where the buck stops. In-agent and client-side both fall to language attacks. Server-side requires a separate principal compromise.
- Slide 15: Three bypasses (`--no-verify`, equivalent commands defeating pattern matching, lockfile pinning without server validation). Each defeats one upper layer; none defeats server-side.

## Section 9: Monday-morning playbook (~3 min, slides 16-18)

- Slide 16: Audit one pipeline against the matrix. Four outcomes per row (all three populated, only in-agent, only server-side, deliberately empty). Empty cells are okay; empty by accident is not.
- Slide 17: The four cells most teams share: over-scoped authorization, no supply-chain admission, humans-only approval gating, shared identity. Four tickets to file Monday, not eight.
- Slide 18: Closer. Detection is not Protection. Response is not Protection. Recovery is not Protection. Build the column you do not have.

## Section 10: Resources and Q&A (~2 min, slide 19)

- Slide 19: Personal site (`michaelrishiforrester.com`), sister talks (SREday Austin yesterday, KCD Texas Friday), Agentic Covenants Framework repo (`github.com/peopleforrester/agentic-covenants`), Q&A.

## Timing target

Content ~30 minutes plus Q&A buffer. If running long, slide 12 is the trim candidate; its full content is in the resources slide.

## Sister talks referenced from this deck

- SREday Austin (2026-05-11): "The Day an AI Agent Deleted My Cluster"
- KCD Texas (2026-05-15): "The 90-Minute IDP" hands-on workshop
