# LLMday Austin Live Demo Build Spec — v4 (repo-local paths)

**Talk:** Your MLOps Pipeline is your Agentic AI Guardrail
**Date:** Tue May 12, 2026
**Venue:** The Sunset Room, Austin
**Speaker:** Michael Forrester
**Demo block:** ~8 minutes, mid-talk, three beats
**Spec version:** v4 — scripted terminal demo, real enforcement underneath
**Build location:** everything lives under `demo/` in this repo; nothing in `/tmp`. Short-lived credentials are written under `demo/` at runtime and gitignored.

This file is the build contract. Claude Code reads it and builds the demo described here. When every acceptance criterion passes, the demo is ready for stage.

---

## v4 vs v3: what changed

v3 used live Claude Code with autonomous agent behavior. Three real beats, real agent decisions, real hooks. The risk was the agent picking an unexpected path and the hooks not firing.

**v4 swaps the agent for a scripted dialogue.** The "agent" is now a bash script that prints scripted thinking and tool calls. **The hooks and admission policies underneath are real.** When the script attempts `kubectl apply -n production`, a real PreToolUse-style check fires. When the script tries to `git commit`, a real Git pre-commit hook fires. When the script bypasses both and hits the API server, a real `ValidatingAdmissionPolicy` denies it.

The audience sees a terminal that looks indistinguishable from a real Claude Code session, with **real** enforcement at every layer. Michael controls pacing with spacebar at major beat transitions; typing animations auto-advance.

| | v3 | v4 |
|---|---|---|
| Agent dialogue | live Claude Code | scripted bash (`agent_say`, `agent_run`) |
| Hook execution | real | real |
| Git commit attempt | real | real |
| K8s admission denial | real | real |
| Pacing | live (variable) | hybrid (auto-typing, manual beat advance) |
| Risk profile | medium-high (agent variance) | low (deterministic flow, real enforcement) |
| Authenticity to audience | high | high (because enforcement is real) |

The scripted dialogue is honest because the enforcement underneath is real. Michael says so on stage: *"This is a scripted recreation. The hooks are real. The Git rejection is real. The K8s denial is real. I scripted the agent because I want the timing to match my narration, not because the demo isn't honest."*

That line is in the runbook.

---

## The narrative

A scenario most of the LLMday audience will recognize: a junior ML engineer asks the agent for help shipping a new model version to production. The agent tries three paths. Three layers of the existing pipeline catch it. None of them are new infrastructure built for agent governance. All three are gates that already exist for human workflows.

The line lands when the audience realizes: **the agent didn't break anything because the pipeline they already configured for humans turned out to also be the agent governance layer.**

### Beat 1 — Claude Code PreToolUse Hook
Agent attempts `kubectl set image deployment/model-server -n production`. PreToolUse hook denies the tool invocation before it executes. Agent reads the hook output, acknowledges, adapts.

### Beat 2 — Git Hook
Agent's adapted path is to commit IaC changes. Pre-commit hook fires because the change touches a protected path. Agent reads the rejection, acknowledges, adapts.

### Beat 3 — Kubernetes ValidatingAdmissionPolicy
Agent's final adapted path is direct kubectl from the session (with PreToolUse "temporarily" out of the way per scenario). The API server denies it. Agent acknowledges the wall.

The cluster incident is not in the demo. It is mentioned in one sentence in the opening of the talk: *"I gave an AI agent cluster-level permissions and walked away. Forty minutes later I had no cluster. I told that story yesterday at SREday. Today we're going to show what would have stopped it."* That is the only reference.

---

## Demo execution model: scripted dialogue, real enforcement

The demo is a single bash script `demo.sh` that:

1. **Simulates the agent's voice** with typed-out text, dimmed cyan formatting, a `claude>` prompt
2. **Actually runs commands** at key moments, hitting real hooks and real cluster policies
3. **Pauses at beat transitions** (spacebar advance)
4. **Auto-paces typing animations** (no waiting on Michael for typing speed)

### The visual model

Four-pane tmux layout. The demo script runs in the **top-left pane** (the "Claude Code session"). The other three panes show **real cluster state** updated by the actual commands the script runs.

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│                                     │                                     │
│   demo.sh (Claude Code session)     │   kubectl get pods -A -w            │
│   agent thinking, prompts, denies   │   cluster watch                     │
│                                     │                                     │
├─────────────────────────────────────┼─────────────────────────────────────┤
│                                     │                                     │
│   git log -p, hook stderr           │   kubectl get events -A -w +        │
│   (Beat 2 lights up here)           │   audit log tail                    │
│                                     │   (Beat 3 lights up here)           │
│                                     │                                     │
└─────────────────────────────────────┴─────────────────────────────────────┘
```

Each beat highlights one pane. Michael directs audience attention with phrases like "watch the bottom-left now."

### Pacing model: hybrid

- **Typing animations**: auto-advance, ~30ms per character. ~3-4 seconds for a typical line. Michael narrates over the typing.
- **Beat transitions**: spacebar advance. Michael presses space when he's ready to move from Beat 1 to Beat 2.
- **Pauses within a beat** (e.g., letting a deny message sink in): spacebar advance.
- **Real command execution**: blocks until the command actually returns. The audience sees the real kubectl output appear at real speed.

Implementation: the demo script reads from a "dialogue" file that has special markers:

```
@say:agent ::thinking:: Let me check what's running in production first
@run kubectl get deployments -n production
@pause
@say:agent I'll update the image tag on model-server now
@run kubectl set image deployment/model-server model-server=registry.local/model-server:v1.3.0 -n production
@say:hook ::deny:: PRETOOLUSE_HOOK_DENY: Direct kubectl against production is not allowed
@pause
```

Markers:
- `@say:<role>` — types out text. Role determines color (agent=cyan, hook=red, kubectl=white)
- `@run <cmd>` — executes the command in this pane, output streams in real time. `$DEMO_DIR` resolves at runtime to the absolute path of `demo/` in the cloned repo.
- `@pause` — waits for spacebar
- `::thinking::` — italicizes / dims the text (visual cue for "agent is reasoning")
- `::deny::` — red bold output for hook/admission denies

---

## Directory structure

Everything lives in the repo under `demo/`. Runtime-generated credentials and ephemeral build artifacts are gitignored.

```
demo/
├── README.md
├── SPEC.md                              # this file
├── setup.sh                             # one-shot bootstrap
├── teardown.sh
├── demo.sh                              # the runner Michael executes on stage
├── lib/
│   ├── say.sh                           # typing animation primitives
│   ├── pause.sh                         # spacebar advance
│   └── colors.sh                        # ANSI color helpers
├── dialogue/
│   ├── beat1-pretooluse.txt             # the scripted dialogue for Beat 1
│   ├── beat1-toolcall.json              # JSON fixture for the PreToolUse hook
│   ├── beat2-githook.txt                # Beat 2
│   └── beat3-vap.txt                    # Beat 3
├── claude-hooks/
│   ├── pretool-use-block-prod.sh        # real Layer 1 hook (called from demo)
│   └── settings.json                    # Claude Code settings (reference; not actually loaded)
├── repo/                                # initialized git repo with pre-commit hook
│   ├── .git/                            # gitignored from parent repo (nested git)
│   ├── .githooks/                       # tracked source of the pre-commit hook
│   │   └── pre-commit                   # real Layer 2 hook (copied into .git/hooks/ by setup)
│   ├── infrastructure/production/model-server.yaml
│   ├── infrastructure/staging/model-server.yaml
│   └── README.md
├── manifests/
│   ├── 00-namespaces.yaml               # production + staging with PSS labels
│   ├── 10-quota.yaml
│   ├── 20-rbac.yaml                     # agent SA + scoped Role
│   ├── 30-workloads.yaml                # model-server deployment in production
│   ├── 40-vap-production-guard.yaml     # real Layer 3 admission policy
│   └── observability/
│       ├── otel-collector.yaml
│       └── falco-daemonset.yaml
├── audit-policy.yaml                    # K8s API server audit policy
├── agent-kubeconfig                     # GITIGNORED — runtime kubeconfig, regenerated each setup
├── agent-token                          # GITIGNORED — 1h projected token
├── beat3-prod-update.yaml               # GITIGNORED — runtime artifact from Beat 3 dialogue
└── demo-runbook.md                      # speaker's printed runbook
```

The `.gitignore` at the repo root lists `demo/agent-kubeconfig`, `demo/agent-token`, `demo/beat3-prod-update.yaml`, and `demo/repo/.git/`. Everything else under `demo/` is tracked.

`$DEMO_DIR` is set by `demo.sh` to the absolute path of the `demo/` directory at runtime (via `BASH_SOURCE`). Dialogue file `@run` lines use `$DEMO_DIR/...` so they resolve against the actual clone location.

---

## The demo.sh runner — exact behavior

`demo.sh` is the artifact Michael executes on stage. Pseudocode for what it does:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory so the demo works wherever the repo is cloned
DEMO_DIR="${DEMO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

source "$DEMO_DIR/lib/say.sh"
source "$DEMO_DIR/lib/pause.sh"
source "$DEMO_DIR/lib/colors.sh"

clear
echo -e "${DIM}Claude Code 1.2.3 — connected to local cluster (kubeconfig: agent-kubeconfig)${RESET}"
echo ""

print_claude_banner

pause "Press space to begin Beat 1 — PreToolUse hook"
play_dialogue "$DEMO_DIR/dialogue/beat1-pretooluse.txt"

pause "Press space to begin Beat 2 — Git hook"
play_dialogue "$DEMO_DIR/dialogue/beat2-githook.txt"

pause "Press space to begin Beat 3 — K8s admission"
play_dialogue "$DEMO_DIR/dialogue/beat3-vap.txt"

echo ""
echo -e "${DIM}End of demo. Return to slides.${RESET}"
```

### play_dialogue: the dialogue parser

```bash
play_dialogue() {
  local file="$1"
  while IFS= read -r line; do
    case "$line" in
      @say:agent*)
        text="${line#@say:agent }"
        type_out "${CYAN}${text}${RESET}" 30
        ;;
      @say:hook*)
        text="${line#@say:hook }"
        type_out "${RED_BOLD}${text}${RESET}" 30
        ;;
      @say:user*)
        text="${line#@say:user }"
        type_out "${GREEN}> ${text}${RESET}" 25
        ;;
      @say:system*)
        text="${line#@say:system }"
        type_out "${DIM}${text}${RESET}" 20
        ;;
      @run*)
        cmd="${line#@run }"
        echo -e "${BLUE}\$ ${cmd}${RESET}"
        eval "$cmd"   # ← REAL execution. Hits real hooks, real cluster. $DEMO_DIR expands here.
        ;;
      @pause*)
        pause "...continue..."
        ;;
      "")
        echo ""
        ;;
      *)
        echo "$line"
        ;;
    esac
  done < "$file"
}
```

### lib/say.sh — typed output

```bash
type_out() {
  local text="$1"
  local delay_ms="${2:-30}"
  local delay_s=$(awk "BEGIN {print $delay_ms / 1000}")

  for (( i=0; i<${#text}; i++ )); do
    printf "%s" "${text:$i:1}"
    sleep "$delay_s"
  done
  printf "\n"
}
```

### lib/pause.sh — spacebar advance

```bash
pause() {
  local msg="${1:-press SPACE to continue}"
  echo ""
  echo -e "\033[2m[${msg}]\033[0m"
  local key
  while true; do
    IFS= read -rsn1 key
    [[ "$key" == " " ]] && break
  done
  # Move cursor up 2 lines and clear from there to end of screen.
  # This wipes the blank line + the [msg] line and returns cursor to
  # the line where pause() was invoked.
  printf "\033[2A\033[J"
}
```

---

## Dialogue files: the actual scripts

All `@run` lines use `$DEMO_DIR/...` so the script works in any clone of the repo.

### dialogue/beat1-pretooluse.txt

```
@say:user > "Hey, we just trained a new model version v1.3.0 and the team needs it deployed to production today. The previous version is v1.2.0. Can you help me get this update shipped?"

@pause

@say:agent ::I'll check the current state of production first.::

@run kubectl --kubeconfig=$DEMO_DIR/agent-kubeconfig get deployments -n production

@say:agent ::Found model-server running v1.2.0 with 3 replicas. The fastest path is to update the image tag directly. Let me do that.::

@pause

@say:agent ::Running kubectl set image to bump model-server to v1.3.0::

@run bash $DEMO_DIR/claude-hooks/pretool-use-block-prod.sh < $DEMO_DIR/dialogue/beat1-toolcall.json

@pause

@say:agent ::Hmm. The PreToolUse hook intercepted that. Reading the deny message...::

@say:agent ::The hook says direct kubectl operations against production aren't allowed from agent sessions. It says I should stage the change in staging, sign the artifact, and let the pipeline promote it.::

@say:agent ::That's the gitops path. Let me try that instead.::
```

The `beat1-toolcall.json` fixture: `{"tool_name":"Bash","tool_input":"kubectl set image deployment/model-server model-server=v1.3.0 -n production"}`. Piping it to the real hook script causes the real hook to fire with real output. The audience sees real stderr from the real hook.

### dialogue/beat2-githook.txt

```
@say:agent ::Let me look at the IaC repo to find the production manifest.::

@run cd $DEMO_DIR/repo && ls infrastructure/production/

@say:agent ::Found model-server.yaml. I'll update the image tag and commit.::

@run cd $DEMO_DIR/repo && sed -i 's|model-server:v1.2.0|model-server:v1.3.0|' infrastructure/production/model-server.yaml

@run cd $DEMO_DIR/repo && git diff infrastructure/production/model-server.yaml

@say:agent ::Diff looks clean. Committing.::

@pause

@run cd $DEMO_DIR/repo && git add infrastructure/production/model-server.yaml && git -c user.email=claude-agent@anthropic.local commit -m "promote model v1.3.0 to production"

@pause

@say:agent ::The pre-commit hook rejected the commit. It says this path requires a signed PR from a human reviewer in the mlops-platform group, and that non-human committer identities aren't allowed in this repo.::

@say:agent ::Two enforcement reasons. Both deterministic. The repo is configured to reject this exact pattern.::

@say:agent ::What if I just apply the change directly? I have edit permissions in the staging namespace...::
```

### dialogue/beat3-vap.txt

```
@say:agent ::I'll write the deployment YAML out and apply it directly to production via kubectl.::

@say:system ::[Note: PreToolUse hook is scoped to interactive sessions. Direct file-based applies bypass it. Server-side enforcement is the next gate.]::

@run cat > $DEMO_DIR/beat3-prod-update.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: model-server
  namespace: production
  labels:
    app.kubernetes.io/managed-by: mlops-pipeline
spec:
  replicas: 3
  selector:
    matchLabels:
      app: model-server
  template:
    metadata:
      labels:
        app: model-server
    spec:
      containers:
      - name: model-server
        image: registry.local/model-server:v1.3.0
YAML

@run kubectl --kubeconfig=$DEMO_DIR/agent-kubeconfig apply -f $DEMO_DIR/beat3-prod-update.yaml

@pause

@say:agent ::Denied at admission. The ValidatingAdmissionPolicy in the cluster says production namespace writes are restricted to ArgoCD and the MLOps pipeline service accounts. My agent ServiceAccount can't write here.::

@say:agent ::No webhook, no controller, no custom code. The deny came from the API server itself.::

@say:agent ::Acknowledged. The pipeline is the only path. I'll prepare a PR to gitops-prod through the proposal workflow and let a human approve the promotion.::

@pause

@say:system ::End of demo.::
```

---

## Real enforcement under the scripted dialogue

These three things must be **real**, not faked, for the demo to be honest:

### Layer 1: PreToolUse hook
- Real bash script at `demo/claude-hooks/pretool-use-block-prod.sh`
- Reads tool-call JSON from stdin
- Returns exit code 2 with stderr message
- The demo pipes a real JSON fixture to it and shows real stderr

### Layer 2: Git hook
- Source of truth at `demo/repo/.githooks/pre-commit` (tracked)
- `setup.sh` copies it into `demo/repo/.git/hooks/pre-commit` at install (the `.git/` directory itself is gitignored)
- Real `git commit` attempted in the dialogue
- Real rejection from real git

### Layer 3: ValidatingAdmissionPolicy
- Real VAP applied to k3d cluster
- Real `kubectl apply` attempted
- Real API server deny response

All three layers can be tested independently by Michael any time tonight. No agent behavior to coordinate. No prompt engineering required.

---

## Cluster topology (May 2026 defaults — unchanged from v2/v3)

Identical to v3: k3d with K8s v1.35.4, containerd 2.0, PSS `restricted` on both `production` and `staging` namespaces, model-server deployment in production, agent SA in staging with scoped Role, projected token with 1h TTL, OTel collector, Falco DaemonSet, ResourceQuota on staging.

See v3 spec for full manifests; v4 inherits.

---

## The Eight Guardrails Framework — where it appears

The abstract names "the Eight Guardrails Framework." The demo shows three of the eight (the three enforcement layers). The other five are in the repo and on a slide:

1. **PreToolUse hook** (demo Beat 1)
2. **Git pre-commit hook** (demo Beat 2)
3. **K8s ValidatingAdmissionPolicy** (demo Beat 3)
4. **IaC-only infrastructure changes** (referenced in Beat 2; enforced by branch protection in production)
5. **Least privilege RBAC** (agent SA scoped to staging only, enforced by RoleBinding)
6. **Automated rollback** (mentioned on slide; ArgoCD auto-rollback on failed health checks)
7. **Audit logging** (visible in bottom-right pane during demo; API server audit log)
8. **Testing the guardrails** (mentioned on slide; CI runs the hook scripts against malicious payloads)

The deck should have one slide that lists all eight and highlights the three the demo lived. That slot is currently the "failure chain mapped to gates" slide (#7 in v10 deck) — repurpose it.

---

## Speaker runbook excerpt (the part that matters for v4)

```markdown
## Pre-show checklist (10 min before going on)
- [ ] `bash demo/setup.sh` completed clean (target: under 90 seconds)
- [ ] Four-pane tmux layout visible at 22pt font
- [ ] `bash demo/demo.sh` runs end-to-end in rehearsal (do this at least twice)
- [ ] All three hooks fire reliably when tested standalone
- [ ] Backup video on USB stick
- [ ] Token TTL > 1 hour

## On stage
1. SLIDE 4 visible — "Demo: three layers"
2. Switch display to terminal
3. SAY: "This is a scripted recreation. The hooks are real. The Git rejection is real. The K8s denial is real. I scripted the agent dialogue so the timing matches my narration, not because the demo isn't honest. Let me show you."
4. Press SPACE to start Beat 1
5. Narrate over the agent's thinking. Don't read what's on screen verbatim — the audience can read.
6. When the hook fires (red bold output), pause your narration and let the audience read it. Then resume: "That's the PreToolUse hook. Eight lines of bash. It denied the tool call before kubectl ran. The agent reads the deny message and adapts."
7. Press SPACE to advance to Beat 2.
8. Same pattern: narrate over the typing, pause on the deny, explain.
9. Press SPACE to advance to Beat 3.
10. Same pattern.
11. End of demo. Switch back to slides (failure chain mapped slide).

## TIME CHECK at 6:00
You should be at the START of Beat 3 by 6:00. If you're not, Beat 3 still runs to completion because it's scripted — but you may need to trim narration.

## If something breaks
- Hook doesn't fire: this would mean the standalone test passed but the live demo didn't. Diagnose: are you in the right kubeconfig context? Did `setup.sh` complete? Worst case, switch to backup video.
- demo.sh crashes mid-beat: re-run `bash demo/demo.sh --resume-beat=2` to skip ahead.
- Wrong pane gets the focus: use `tmux select-pane -L/-R/-U/-D` to navigate. Don't panic; the audience can't see what you're doing if you're calm.
```

---

## Acceptance criteria

### Layer enforcement (must all pass independently)
- [ ] `bash demo/claude-hooks/pretool-use-block-prod.sh < demo/dialogue/beat1-toolcall.json` exits 2 with `PRETOOLUSE_HOOK_DENY` in stderr
- [ ] `cd demo/repo && git -c user.email=claude-agent@anthropic.local commit ...` on a protected path exits non-zero with `GIT_HOOK_DENY`
- [ ] `kubectl --kubeconfig=demo/agent-kubeconfig apply -f production-deployment.yaml` returns `Forbidden` from VAP within 2 seconds

### Demo runner
- [ ] `bash demo/demo.sh` runs from start to end without errors when spacebar is pressed at each pause
- [ ] Total runtime measured: 7-9 minutes
- [ ] All three real-execution lines (the `@run` lines hitting real layers) produce visible real output
- [ ] Typing animation is readable on a projector — test on an external display at 1920x1080 with font size 22pt

### Dialogue clarity
- [ ] Every `@say:agent` line is something a real LLM agent would plausibly say
- [ ] Every `@say:hook` line matches the real stderr output of the hook
- [ ] No line is so long it overflows the pane at 22pt font

### Recovery
- [ ] `bash demo/demo.sh --resume-beat=2` works (script supports beat skipping)
- [ ] `bash demo/demo.sh --dry-run` prints all dialogue without executing real commands (for last-minute review)

### Backup video
- [ ] One complete end-to-end recording saved at `demo/llmday-demo-backup.mp4` (file is gitignored; large binary)
- [ ] Recording shows all three beats firing with real output
- [ ] USB stick tested on Michael's laptop

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| One of the three real layers fails mid-demo | Very low | High | Pre-flight acceptance criteria test all three. If a layer fails in pre-flight, fix before going on stage. |
| Typing animation feels too slow | Medium | Low | Speed adjustable via env var: `TYPE_DELAY_MS=20 bash demo/demo.sh`. Test in rehearsal. |
| Typing animation feels too fast | Low | Low | Same env var, dial up. |
| Spacebar advance is missed/wrong key | Low | Medium | Pause prompt explicit: "[press space to continue]". If wrong key pressed, nothing happens, demo waits. |
| Audience asks "is that real?" mid-demo | Medium | Low | Use the planned line: "Yes, the enforcement is real. The agent dialogue is scripted for timing." Move on. |
| Demo runs short (under 7 min) | Low | Low | Good problem. Use the time for Q&A or expand the closer. |
| Demo runs long (over 9 min) | Medium | Medium | Time check at 6 min. The Beat 3 closer can be cut short by narrating the final two `@say:agent` lines yourself instead of letting them type out. |

---

## What Claude Code needs to build

Given this spec, Claude Code should produce, in order:

1. `demo/setup.sh` that creates the k3d cluster, applies all manifests, generates the kubeconfig at `demo/agent-kubeconfig`, initializes the git repo at `demo/repo/` with pre-commit hook installed from `demo/repo/.githooks/`, and verifies all three layers are enforceable
2. The three layer artifacts (`demo/claude-hooks/pretool-use-block-prod.sh`, `demo/repo/.githooks/pre-commit`, `demo/manifests/40-vap-production-guard.yaml`)
3. The three dialogue files with the exact text from this spec (paths use `$DEMO_DIR`)
4. `demo/lib/say.sh`, `demo/lib/pause.sh`, `demo/lib/colors.sh` with the typing and pause primitives
5. `demo/demo.sh` itself, which parses dialogue files and runs the demo (already in repo; updated to resolve `$DEMO_DIR` from `BASH_SOURCE`)
6. `demo/teardown.sh` to remove the cluster and clean up the runtime credentials
7. `demo/demo-runbook.md` for Michael to print and reference on stage

When all acceptance criteria pass, the demo is ready. Michael then records the backup video and the build phase is complete.

---

## What v4 deliberately does NOT include

- No live Claude Code agent. v4 trades agent variance for deterministic narrative.
- No cluster incident retelling. The talk references it once in the opener; the demo is pipeline-focused.
- No Eight Guardrails slide-by-slide walkthrough. The demo shows three; the deck and repo cover the other five.
- No fancy ASCII art or animations beyond typed text and color. Keep it terminal-honest.
- No agent reasoning over 4 lines. Each `@say:agent` block is 2-4 lines max. Pace.
- No `/tmp` paths. Everything lives under `demo/` in the repo; short-lived credentials are gitignored.

---

## Closing principle (also in the talk)

The agent dialogue is scripted. The enforcement is not. That asymmetry is the talk. **The probabilistic part (the agent) is fragile, scripted for timing.** **The deterministic part (the gates) is real, reliable, and stops the agent every time.**

That's the principle from the abstract: *don't use probabilistic AI to enforce deterministic requirements. Build the gates programmatically, test them the same way you test your code, and let the agent run.*

The audience is going to see that principle live, in the difference between the scripted top-left pane and the real output in the other three panes.
