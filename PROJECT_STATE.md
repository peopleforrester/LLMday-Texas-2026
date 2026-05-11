# Project State

## Current Status

Talk is scheduled for 2026-05-12 at 2:30 PM. As of 2026-05-11 all artifacts are ready: the article is reconciled with the slide deck, the v06 deck is in the repo, the README reflects the as-delivered framing, the outline file mirrors the deck's 19-slide flow, and a senior-review pass has been applied. No outstanding work blocks delivery.

## Talk Slot

- Event: LLMday Austin 2026
- Date: 2026-05-12
- Time: 2:30 PM
- Duration: 30 minutes
- Level: Beginner
- Status: Accepted, deck ready for delivery
- Speaker affiliation: Accenture (as of 2026-05-11)

## Done

- [x] Captured the accepted CFP abstract
- [x] Wrote the LLMday article (`mlops-as-agentic-guardrail.md`) as an Opinion piece with the MLOps stage to Agentic Covenant mapping
- [x] Reconciled the article with the delivered framework: three layers (in-agent, client-side hooks, server-side) and five concerns (identity, authorization, blast radius, approval gating, supply chain)
- [x] Built and committed the v06 slide deck (19 slides with speaker notes) under `presentations/`
- [x] Reconciled README with the deck: Accenture affiliation, Agentic Covenants Matrix framing, sister-talk references
- [x] Initialized GitHub remote, set `staging` as default branch, enabled `main` protection, added CC BY 4.0 LICENSE and topic tags
- [x] Replaced the outline stub with an as-delivered 19-slide outline derived from the deck
- [x] Scoped the writing-standards rule in `CLAUDE.md` to prose only (slide deck rhetoric is intentional theme work)
- [x] Senior-review pass: em-dash sweep across all prose, title-casing normalization, `.gitignore` negation for tracked deck path, stale-state cleanup, deck-version retention note

## Next (post-delivery)

- [ ] Publish the article via Micropub after the talk
- [ ] Capture any audience Q&A worth folding back into the article or the agentic-covenants framework repo
- [ ] Decide whether to retain `docs/outline.md` long-term or convert it into a published recap

## Verification Method

- Article and README writing standards verified by grep scan for em-dashes (U+2014) and banned terms (zero hits across all prose).
- Speaker notes scanned for the same banned terms (zero hits); slide bodies intentionally exempt per `CLAUDE.md`.
- Repo state verified against git log and remote (`main` and `staging` synced).
- The deck file path and 19-slide count verified by direct inspection of the unzipped pptx XML.

## What is NOT verified

- The article has not yet been published through the Micropub pipeline.
- The deck has not been rehearsed end-to-end with a timer in this session; rehearsal is owned by Michael offline.
- The bypass examples in the deck (`--no-verify`, equivalent commands, lockfile pinning) are argued in slides 9, 10, and 15 but not demoed live; this is intentional given the T-1 time budget.
