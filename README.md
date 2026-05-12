# LLMday Texas 2026

**Talk:** Your MLOps Pipeline Is Your Agentic AI Guardrail
**Speaker:** Michael R Forrester, Accenture
**Status:** Accepted
**Slot:** 2026-05-12, 2:30 PM
**Format:** 30-minute Talk, Beginner level

## Thesis

The MLOps pipeline already implements most of what teams are trying to reinvent for agentic systems. Map the stages directly to the controls you would want around an autonomous agent and the structure lines up almost one-to-one. The talk extends that mapping into the **Agentic Covenants Matrix**: three enforcement layers (in-agent, client-side hooks, server-side) crossed with five concerns (identity, authorization, blast radius, approval gating, supply chain). Fifteen cells. The matrix is scoped to NIST CSF 2.0's Protect function; companion frameworks cover Detect, Respond, and Recover.

The matrix and broader prevention model live in their own repo: [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants). This LLMday repo references that framework rather than reproducing it.

## Repo contents

- `mlops-as-agentic-guardrail.md`: the published article (Opinion piece, ready for Micropub).
- `presentations/llmday-austin-2026-deck-v19.pptx`: the slide deck (16 slides with speaker notes). Only the latest version is retained; earlier drafts are intentionally not kept.
- `docs/outline.md`: as-delivered slide outline derived from the deck.
- `demo/`: live terminal demo for the six-gate arc walked during the talk. Five gates run live on stage; the sixth is on slide. See `demo/README.md` for the student-facing walkthrough and `demo/demo-runbook.md` for the speaker runbook.
- `examples/`: working hook scripts the audience can take home. `examples/claude-hooks/` has seven Claude Code lifecycle hooks (session-start, PreToolUse, PostToolUse, PostCompact, Stop) plus an example `settings.json`; `examples/git-hooks/` has a tiered pre-commit / pre-push pair with a deploy script. Maps directly to Demos 1 and 2 from the talk. See `examples/README.md` for the per-script breakdown and install steps.
- `CLAUDE.md`: project context and writing standards for AI-assisted edits.
- `PROJECT_STATE.md`: current status and what comes next.

## Related work

- **Agentic Covenants Framework:** [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants), the canonical source for the matrix and prevention model.
- **Sister talks delivered the same week in Austin:**
    - SREday Austin (2026-05-11): "The Day an AI Agent Deleted My Cluster", the long-form SRE retelling of the incident this talk references.
    - KCD Texas (2026-05-15): "The 90-Minute IDP" hands-on workshop.

## Workflow

Work on `staging`. Open a PR to merge `staging` into `main`. Direct pushes to `main` are blocked by branch protection.

## License

Article and supporting prose in this repo are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution: Michael R Forrester, 2026. See `LICENSE` for the full text.
