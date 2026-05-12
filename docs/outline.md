# Talk Outline: Your MLOps Pipeline Is Your Agentic AI Guardrail

As-delivered outline derived from the v19 slide deck. The deck at `../presentations/llmday-austin-2026-deck-v19.pptx` and its speaker notes are the canonical artifacts. This file is the readable summary for anyone landing in the repo without PowerPoint.

Slot: 2026-05-12, 2:30 PM, 30 minutes, Beginner. 16 slides. The demo block is the spine of the talk: six gates, five run live, the sixth is shown on slide.

## Section 1: Open and backstory (~2 min, slides 1-2)

- Slide 1: Title. Open straight into the inversion. No long bio. Single anchor line: *"In an era of unprecedented agentic capability, the question isn't whether your pipeline is ready, it's whether you've trained the right reflexes."*
- Slide 2: Brief SREday backstory. Yesterday's talk was the cluster-deletion incident. Today's talk is what would have stopped it. QR to the SREday talk repo for anyone who wants the long form.

## Section 2: The pipeline you already run (~2 min, slides 3-4)

- Slide 3: CI/CD is the analogy the audience already has. MLOps is what's actually running. Both are the same machinery. The thesis lands here.
- Slide 4: "Same controls. New actor." Mapping table from MLOps stages to Agentic Covenants to the demos that show each one live. The table is the spine of the rest of the talk.

## Section 3: Live demo block, first three gates (~6 min, slides 5-7)

- Slide 5: **Demo 1 of 6** (LIVE). PreToolUse hook. Layer: in-agent. Agent tries `kubectl set image` against production; the hook intercepts before the call leaves the agent's shell.
- Slide 6: **Demo 2 of 6** (LIVE). Git pre-commit hook. Layer: client-side. Agent's next attempt is the IaC path: edit `infrastructure/production/`, commit. Hook denies on two grounds (protected path and non-human committer).
- Slide 7: **Demo 3 of 6** (LIVE). K8s ValidatingAdmissionPolicy. Layer: server-side, admission. Agent gives up on local paths and applies directly to the API server. CEL expression denies the request inside the API server itself.

## Section 4: Bridge to runtime and network (~1 min, slide 8)

- Slide 8: Bridge. *"Demos 1 through 5: infrastructure controlled. But the agent doesn't just act. It also talks. What happens when the words coming out are the unsafe part?"* This is the structural pivot from the infrastructure block to Beat 6 (output / content).

## Section 5: Monday morning playbook (~1 min, slide 9)

- Slide 9: "Monday morning. Three ways in." Path 01 for teams with an MLOps pipeline: walk the six gates on your most-embarrassing pipeline. 30 minutes. Find which gates exist, which are missing, which are configured for humans only.

## Section 6: Live demo block, runtime and network (~5 min, slides 10-11)

- Slide 10: **Demo 4 of 6** (LIVE). Runtime · Falco + Talon. Layer: server-side, runtime. Admission accepted the manifest; runtime decides the behavior. Agent execs into the model-server pod; the Falco custom rule fires on the shell-binary spawn; Talon terminates the pod; the ReplicaSet self-heals.
- Slide 11: **Demo 5 of 6** (LIVE). Network · NetworkPolicy. Layer: server-side, network. Agent does nothing unsafe at the syscall level; it just runs `wget` to an external destination. DNS resolves, the TCP connect is dropped. Runtime did not fire. Nothing was unsafe. The destination was not on the list.

## Section 7: The three places in the chain (~3 min, slides 12-14)

- Slide 12: (Visual transition slide.)
- Slide 13: "Three places in the chain." Client-side, app/agent, server-side. Three ways to think about where the gate goes along the chain. Frame Demos 1-5 against these three placements: in-agent at the agent's shell, client-side at the commit, server-side spanning admission, runtime, and network.
- Slide 14: "Three ways teams use AI." Inject AI into workflows (coding agents, automation) versus the autonomous-agent case the talk is about. Bounded blast radius versus the production-touching case. This slide reframes the audience's mental model.

## Section 8: Resources and the sixth gate (~3 min, slides 15-16)

- Slide 15: "Read the long version." Personal site (`michaelrishiforrester.com`), articles on platform engineering and agentic AI guardrails.
- Slide 16: **Demo 6 of 6** (ON SLIDE). Output · LLM Guard. Layer: output. The only gate in the chain that enforces content, not infrastructure. The closing two-liner: *"Layers 1 through 5 keep the agent from breaking the system. Layer 6 keeps the system from saying things it shouldn't."*

## Recap (~1 min, embedded in slide 17 if rendered, otherwise verbal close)

- "Six gates. Five live." Each demo blocks a different attack on the same target. Same agent identity. Different routing through deterministic gates the team already configured.

## Timing target

Content ~30 minutes plus Q&A buffer. Live demo block is the long bar: about 11 minutes total across Demos 1-5. If running long, trim narration on the agent's `::thinking::` lines in the dialogue rather than cutting beats.

## Sister talks referenced from this deck

- SREday Austin (2026-05-11): "The Day an AI Agent Deleted My Cluster"
- KCD Texas (2026-05-15): "The 90-Minute IDP" hands-on workshop
