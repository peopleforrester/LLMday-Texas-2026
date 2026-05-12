# LLMday Texas 2026

**Talk:** Your MLOps Pipeline Is Your Agentic AI Guardrail
**Speaker:** Michael R Forrester, Accenture
**Status:** Accepted
**Slot:** 2026-05-12, 2:30 PM
**Format:** 30-minute Talk, Beginner level

## Thesis

The MLOps pipeline already implements most of what teams are trying to reinvent for agentic systems. Map the stages directly to the controls you would want around an autonomous agent and the structure lines up almost one-to-one. The talk extends that mapping into the **Agentic Covenants Matrix**: three enforcement layers (in-agent, client-side hooks, server-side) crossed with five concerns (identity, authorization, blast radius, approval gating, supply chain). Fifteen cells. The matrix is scoped to NIST CSF 2.0's Protect function; companion frameworks cover Detect, Respond, and Recover.

The matrix and broader prevention model live in their own repo: [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants). This LLMday repo references that framework rather than reproducing it.

## Where to start

Three audiences, three paths:

- **I just watched the talk and want context.** Read `mlops-as-agentic-guardrail.md` for the full argument; skim `docs/outline.md` for a slide-by-slide summary of what you just saw; check `docs/FAQ.md` if you have one of the common questions.
- **I want to install the hooks on my workstation.** Go to `examples/` — `claude-hooks/` holds the seven Claude Code hooks you can drop into `~/.claude/hooks/`, and `git-hooks/` holds the tiered pre-commit + pre-push you can install in any repo. `examples/README.md` has copy-pasteable install steps.
- **I want to stand up the live demo cluster.** Read `demo/README.md` for prerequisites and the run sequence; the speaker runbook is in `demo/demo-runbook.md`; the build spec (memory budget, sync waves, tool versions) is in `docs/SPEC.md`. Budget: ~25 min provision + ~$15 for a 24-hour cluster lifetime.

## Slide-to-file cross-reference

Map from the slide you remember to the files that prove it on disk:

| Slide | Demo | Layer | Where it lives |
|---|---|---|---|
| 5 | Demo 1 — Claude Code PreToolUse hook | In-agent | `examples/claude-hooks/` (catalog) · `demo/claude-hooks/pretool-use-block-prod.sh` (stage version) |
| 6 | Demo 2 — Git pre-commit / pre-push | Client-side | `examples/git-hooks/` (catalog) · `demo/iac-repo-template/hooks/pre-commit` (stage version) |
| 7 | Demo 3 — Kubernetes ValidatingAdmissionPolicy | Server-side · admission | `demo/gitops/manifests/vap/vap.yaml` |
| 10 | Demo 4 — Falco custom rule + Falco Talon | Server-side · runtime | `demo/gitops/values/falco-values.yaml` (`customRules`) · `demo/gitops/values/falco-talon-values.yaml` (`config.rulesOverride`) |
| 11 | Demo 5 — NetworkPolicy egress allowlist | Server-side · network | `demo/gitops/manifests/cluster-config/vpc-cni-network-policy.yaml` (enable knob) · `demo/gitops/manifests/networkpolicies/netpol.yaml` (the policy) |
| 16 | Demo 6 — Output / LLM Guard | Output | On slide only (closing line: *"Layers 1 through 5 keep the agent from breaking the system. Layer 6 keeps the system from saying things it shouldn't."*) |

## Architecture, at a glance

```
                                    A G E N T   R E Q U E S T   P A T H

  ┌─────────┐   Demo 1     ┌────────────┐   Demo 2     ┌────────────┐   Demo 3     ┌──────────────┐
  │  Agent  │──tool call──▶│ PreToolUse │──git commit─▶│   git      │──kubectl────▶│ K8s API +    │
  │ (shell) │              │ hook       │              │ pre-commit │   apply      │ VAP          │
  └─────────┘              │ (in-agent) │              │(client-sde)│              │(admission)   │
                           └────────────┘              └────────────┘              └──────┬───────┘
                                                                                          │ accepted
                                                                                          ▼
                                                                                   ┌──────────────┐
                                                          Demo 4 (runtime)         │   Pod runs   │
                                                          ┌───────────┐            │              │
                                                          │ Falco +   │◀── eBPF ───┤ kubectl exec │
                                                          │ Talon     │── kill ───▶│              │
                                                          └───────────┘            │              │
                                                                                   │ egress       │
                                                                       Demo 5      │              │
                                                                       ┌─────────┐ │              │
                                                                       │ Network │◀───── TCP SYN──┤
                                                                       │ Policy  │── drop ───╳    │
                                                                       └─────────┘ └──────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
  │  Demo 6 (output / content gate, on slide only): LLM Guard / NeMo Guardrails / Envoy AI Gateway  │
  │  sits between the model's response and the user. Catches what the model SAYS, not what the      │
  │  agent DOES. Different threat model, different layer, separate from the five above.             │
  └─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Repo contents

- `mlops-as-agentic-guardrail.md`: the published article (Opinion piece, ready for Micropub).
- `presentations/llmday-austin-2026-deck-v19.pptx`: the slide deck (16 slides with speaker notes). Only the latest version is retained; earlier drafts are intentionally not kept.
- `docs/outline.md`: as-delivered slide outline derived from the deck.
- `docs/SPEC.md`: build spec for the live demo cluster (memory budget, sync waves, tool versions, acceptance criteria).
- `docs/FAQ.md`: common questions the audience asks about the live demo and the choices behind it.
- `docs/glossary.md`: one-line definitions for `VAP`, `Talon`, `falcosidekick`, `PolicyEndpoint`, `PSS`, and the other terms that show up in the demo without explanation.
- `docs/qa.md`: post-talk capture for audience Q&A (populated after the event).
- `demo/`: live terminal demo for the six-gate arc walked during the talk. Five gates run live on stage; the sixth is on slide. See `demo/README.md` for the student-facing walkthrough and `demo/demo-runbook.md` for the speaker runbook.
- `examples/`: working hook scripts the audience can take home. `examples/claude-hooks/` has seven Claude Code lifecycle hooks (session-start, PreToolUse, PostToolUse, PostCompact, Stop) plus an example `settings.json`; `examples/git-hooks/` has a tiered pre-commit / pre-push pair with a deploy script. Maps directly to Demos 1 and 2 from the talk. See `examples/README.md` for the per-script breakdown and install steps.
- `CLAUDE.md`: project context and writing standards for AI-assisted edits.
- `PROJECT_STATE.md`: current status and what comes next.

## Watch the talk

- Recording: TBD (link will land here once the LLMday Austin recording is published).

## Related work

- **Agentic Covenants Framework:** [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants), the canonical source for the matrix and prevention model.
- **Sister talks delivered the same week in Austin:**
    - SREday Austin (2026-05-11): "The Day an AI Agent Deleted My Cluster", the long-form SRE retelling of the incident this talk references.
    - KCD Texas (2026-05-15): "The 90-Minute IDP" hands-on workshop.

## Workflow

Work on `staging`. Open a PR to merge `staging` into `main`. Direct pushes to `main` are blocked by branch protection.

## License

Article and supporting prose in this repo are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution: Michael R Forrester, 2026. See `LICENSE` for the full text.
