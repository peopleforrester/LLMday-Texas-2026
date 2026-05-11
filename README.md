# LLMday Texas 2026

**Talk:** Your MLOps Pipeline is your Agentic AI Guardrail
**Speaker:** Michael Forrester, Accenture
**Status:** Accepted
**Slot:** 2026-05-12, 2:30 PM
**Format:** 30-minute Talk, Beginner level

## Thesis

The MLOps pipeline already implements most of what teams are trying to reinvent for agentic systems. Map the stages directly to the controls you would want around an autonomous agent and the structure lines up almost one-to-one. The talk extends that mapping into the **Agentic Covenants Matrix**: three enforcement layers (in-agent, client-side hooks, server-side) crossed with five concerns (identity, authorization, blast radius, approval gating, supply chain). Fifteen cells. The matrix is scoped to NIST CSF 2.0's Protect function; companion frameworks cover Detect, Respond, and Recover.

The matrix and broader prevention model live in their own repo: [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants). This LLMday repo references that framework rather than reproducing it.

## Repo contents

- `mlops-as-agentic-guardrail.md` — the published article (Opinion piece, ready for Micropub)
- `presentations/llmday-austin-2026-mlops-pipeline-guardrail-v06.pptx` — the slide deck (19 slides with speaker notes)
- `docs/outline.md` — 30-minute talk outline (early stub; superseded in practice by the deck and its speaker notes)
- `CLAUDE.md` — project context and writing standards for AI-assisted edits
- `PROJECT_STATE.md` — current status and what comes next

## Related work

- **Agentic Covenants Framework:** [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants) — canonical source for the matrix and prevention model.
- **Sister talks delivered the same week in Austin:**
    - SREday Austin (2026-05-11): "The Day an AI Agent Deleted My Cluster" — the long-form SRE retelling of the incident this talk references.
    - KCD Texas (2026-05-15): "The 90-Minute IDP" hands-on workshop.

## Workflow

Work on `staging`. Open a PR to merge `staging` into `main`. Direct pushes to `main` are blocked by branch protection.

## License

Article and supporting prose in this repo are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution: Michael R Forrester, 2026. See `LICENSE` for the full text.
