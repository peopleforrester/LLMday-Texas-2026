# Project State

## Current Status

Talk is scheduled for 2026-05-12 at 2:30 PM. As of 2026-05-12 all artifacts are ready: the article is reconciled with the slide deck, the v19 deck is in the repo, the README and outline reflect the as-delivered framing, the live demo runs five gates on a real EKS Auto Mode cluster, and the speaker runbook is in place.

## Talk Slot

- Event: LLMday Austin 2026
- Date: 2026-05-12
- Time: 2:30 PM
- Duration: 30 minutes
- Level: Beginner
- Status: Accepted, deck and live demo ready for delivery
- Speaker affiliation: Accenture

## Done

- [x] Captured the accepted CFP abstract
- [x] Wrote the LLMday article (`mlops-as-agentic-guardrail.md`) as an Opinion piece with the MLOps stage to Agentic Covenant mapping
- [x] Reconciled the article with the delivered framework: three layers (in-agent, client-side hooks, server-side) and five concerns (identity, authorization, blast radius, approval gating, supply chain)
- [x] Built and committed the v19 slide deck under `presentations/`. Six-gate arc on slides 5-7, 10-11, 16. Recap on slide 17.
- [x] Reconciled README with the deck: Accenture affiliation, Agentic Covenants Matrix framing, sister-talk references, demo entry point
- [x] Initialized GitHub remote, set `staging` as default branch, enabled `main` protection, added CC BY 4.0 LICENSE and topic tags
- [x] Replaced the outline stub with an as-delivered slide outline derived from the v19 deck
- [x] Scoped the writing-standards rule in `CLAUDE.md` to prose only (slide deck rhetoric is intentional theme work)
- [x] Senior-review pass: em-dash sweep across all prose, title-casing normalization, `.gitignore` negation for tracked deck path, stale-state cleanup, deck-version retention note
- [x] Provisioned an EKS Auto Mode cluster (Kubernetes 1.35) with full GitOps bootstrap via ArgoCD
- [x] Wired Beat 1 (PreToolUse hook), Beat 2 (Git pre-commit hook), and Beat 3 (Kubernetes ValidatingAdmissionPolicy) end-to-end on the live cluster
- [x] Added Beat 4 (Falco custom rule + Falco Talon response binding) as GitOps-managed `falco-values.yaml` customRules and `falco-talon-values.yaml` rulesOverride; the Falco DaemonSet mounts the rule, Talon binds the rule name to `kubernetes:terminate`, falcosidekick forwards events. Verified live: agent exec into a production pod triggers a Talon termination.
- [x] Added Beat 5 (NetworkPolicy egress allowlist) as GitOps-managed `cluster-config/vpc-cni-network-policy.yaml` (enables the EKS Auto Mode Network Policy Controller) plus `networkpolicies/netpol.yaml` (production egress allowlist). Verified live: `wget https://huggingface.co/...` from a production pod times out while DNS and intra-namespace traffic still work.
- [x] Updated `demo.sh`, `demo-claude.sh`, `demo-settings.sh` to walk all five live beats; removed the standalone `demo-runtime.sh` (its content is now in the three main runners)
- [x] Refreshed `demo/README.md` and `demo/demo-runbook.md` for the six-gate framing (five live, one on slide)

## Next (post-delivery)

- [ ] Publish the article via Micropub after the talk
- [ ] Capture any audience Q&A worth folding back into the article or the agentic-covenants framework repo
- [ ] Tear down the EKS cluster (`bash demo/teardown.sh`) when the post-talk window closes
- [ ] Decide whether to retain `docs/outline.md` long-term or convert it into a published recap

## Verification Method

- Article and README writing standards verified by grep scan for em-dashes (U+2014) and banned terms (zero hits across all prose).
- Speaker notes scanned for the same banned terms (zero hits); slide bodies intentionally exempt per `CLAUDE.md`.
- Repo state verified against git log and remote (`main` and `staging` synced).
- Deck file path and slide count verified by direct inspection of the unzipped pptx XML.
- Live demo verified by firing each beat against the running cluster: PreToolUse hook denies the agent's tool call, the pre-commit hook rejects the agent's commit, the VAP denies the agent's apply, Falco fires "Agent exec in production" and Talon terminates the pod, the NetworkPolicy drops egress to huggingface.co while internal traffic stays up.

## What is NOT verified

- The article has not yet been published through the Micropub pipeline.
- The deck has not been rehearsed end-to-end with a timer in this session; rehearsal is owned by Michael offline.
- Beat 6 (output / LLM Guard) is on slide only; there is no live content-filtering demo wired up.
