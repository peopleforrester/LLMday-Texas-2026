# Project State

## Current Status

Talk delivered 2026-05-12 at 2:30 PM. Post-talk wrap-up complete: as-delivered v20 deck is in `presentations/` on both branches, the EKS Auto Mode cluster has been torn down with zero AWS artifacts remaining under the `accen-dev` / `nwuser` identity, and a full secret-scanning sweep of the repo (tracked sources, git history, deck binaries) found no exposed credentials.

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
- [x] Delivered the talk live at LLMday Austin 2026 on 2026-05-12 at 2:30 PM
- [x] Added the as-delivered v20 deck under `presentations/` (uploaded to `main` at talk time, backported to `staging` 2026-05-25)
- [x] Tore down the EKS Auto Mode cluster on 2026-05-14 via `bash demo/teardown.sh`; verified 2026-05-25 that zero AWS artifacts remain under `accen-dev` / `nwuser` across us-east-1/2 and us-west-2 (cluster, CFN stack, IAM roles, OIDC provider, CloudWatch log group, EBS, ENIs, SGs, ELBs, NATs all confirmed gone)
- [x] Repo security sweep on 2026-05-16: tracked sources, git history, and both deck binaries scanned for AWS keys, GitHub tokens, JWTs, private keys, account numbers, and webhook URLs; zero exposed credentials. Dependabot, secret-scanning, and vulnerability-alerts all clean on GitHub.

## Next (post-delivery)

- [ ] Publish the article via Micropub after the talk
- [ ] Capture any audience Q&A worth folding back into the article or the agentic-covenants framework repo
- [ ] Decide whether to retain `docs/outline.md` long-term or convert it into a published recap

## Verification Method

- Article and README writing standards verified by grep scan for em-dashes (U+2014) and banned terms (zero hits across all prose).
- Speaker notes scanned for the same banned terms (zero hits); slide bodies intentionally exempt per `CLAUDE.md`.
- Repo state verified against git log and remote (`main` and `staging` synced).
- Deck file path and slide count verified by direct inspection of the unzipped pptx XML.
- Live demo verified by firing each beat against the running cluster: PreToolUse hook denies the agent's tool call, the pre-commit hook rejects the agent's commit, the VAP denies the agent's apply, Falco fires "Agent exec in production" and Talon terminates the pod, the NetworkPolicy drops egress to huggingface.co while internal traffic stays up.
- AWS teardown verified via direct `aws` CLI checks against `accen-dev` (account 515966504359, user nwuser): `eks list-clusters` across three regions, `cloudformation list-stacks`, `iam list-roles`, `iam list-open-id-connect-providers`, `logs describe-log-groups`, plus tag-filtered sweeps for EBS volumes, ENIs, security groups, load balancers, NAT gateways, EC2 instances, and launch templates. All returned empty.
- Repo security sweep verified via `git grep` for AWS key patterns, GitHub tokens, JWT lumps, PEM markers, webhooks; `git log -S/-G` for the same patterns across full history; and `unzip` of both v19 and v20 decks with `grep` over slide XML, speaker notes, and hyperlink relationships. GitHub-side surfaces checked via `gh api` for dependabot, secret-scanning, and code-scanning alerts (zero across all).

## What is NOT verified

- The article has not yet been published through the Micropub pipeline.
- The deck has not been rehearsed end-to-end with a timer in this session; rehearsal is owned by Michael offline.
- Beat 6 (output / LLM Guard) is on slide only; there is no live content-filtering demo wired up.
- Post-talk Q&A capture (`docs/qa.md`) remains a placeholder; any unanticipated audience questions still need to be triaged into FAQ updates or repo issues.
