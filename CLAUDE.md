# LLMday Texas 2026: Project Context for Claude Code

This repo holds the talk artifacts for the LLMday Austin 2026 talk "Your MLOps Pipeline Is Your Agentic AI Guardrail." 30-minute slot, Beginner level, scheduled 2026-05-12 at 2:30 PM.

## What lives here

- `mlops-as-agentic-guardrail.md`: the canonical article (Opinion piece) with the Agentic Covenants Matrix mapping. Ready for Micropub publication.
- `presentations/llmday-austin-2026-deck-v19.pptx`: the slide deck as delivered. 16 slides, six-demo arc (five live, one on slide).
- `docs/outline.md`: as-delivered slide outline derived from the deck.
- `demo/`: the live terminal demo (EKS Auto Mode + GitOps), runs the five live gates from the deck on a real cluster.
- `PROJECT_STATE.md`: current status and remaining work.

## What does NOT live here

- The Eight Guardrails framework reference, the cluster deletion forensic evidence, and the related Ignite-format presentation are in sibling repos. See `README.md` for paths. Do not duplicate that material here; reference it.
- The Agentic Covenants Framework lives at `github.com/peopleforrester/agentic-covenants`. **Reference it, but do not pull content from it into this repo.** The framework repo is the canonical source of the matrix and prevention model; this repo points at it. If you find yourself wanting to copy text or definitions from that repo into LLMday materials, stop and link instead.

## Writing standards for the article and any derivative prose

These apply to `mlops-as-agentic-guardrail.md`, README, blog posts, and any text-only prose that ships through Micropub or similar publication paths. **Slide deck bodies are exempt** (the AI-flavored rhetoric on the slides is intentional theme work, part of "the game"). **Speaker notes are NOT exempt**: they are spoken aloud, so they follow the same standards as prose. If you scan the deck, scan body and notes separately.

- No em-dashes in the prose artifacts listed in the section header above. Use commas, colons, parentheses, periods. The slide deck is exempt.
- No AI-isms: avoid "delve", "under the hood", "genuinely", "in today's landscape", and constructions like "the question isn't X, the question is Y".
- Avoid parallel closing sentence pairs.
- Article titles use a content-type prefix: "Opinion: ..." or "Walkthrough: ...".
- No HTML comments or scaffolding metadata in the deliverable.

## Git workflow

Active branch: `staging`. Merge to `main` only via PR. Direct push to `main` is blocked by GitHub branch protection.
