# LLMday Austin Demo · Three-Layer Pipeline Guardrails

A live, scripted terminal demo for the talk *"Your MLOps Pipeline is your Agentic AI Guardrail"* delivered at LLMday Austin on May 12, 2026.

The demo shows three layers of an existing MLOps pipeline catching an AI agent that tries to ship a model update to production:

1. **Claude Code PreToolUse hook** — denies the dangerous tool call before execution
2. **Git pre-commit hook** — rejects the agent's commit on a protected path
3. **Kubernetes ValidatingAdmissionPolicy** — denies the agent's direct API call at the API server

The agent dialogue is scripted (for predictable timing on stage). The enforcement at every layer is real.

---

## Quick start

```bash
# Prerequisites: k3d, kubectl, git, bash, awk, jq
bash setup.sh         # creates the k3d cluster, applies manifests, generates kubeconfig
bash demo.sh          # runs the demo. Press SPACE at each beat transition.
bash teardown.sh      # removes the cluster and cleans .local/
```

That's it. The demo runs from this directory wherever the repo is cloned.

---

## What's in here

### Checked into the repo

| Path | What it is |
|---|---|
| `setup.sh` | One-shot bootstrap: creates k3d cluster, applies manifests, generates kubeconfig, hydrates iac-repo |
| `reset.sh` | Between-rehearsal-runs reset: refreshes the iac-repo and the token without rebuilding the cluster |
| `teardown.sh` | Removes the cluster and deletes `.local/` |
| `demo.sh` | The runner Michael executes on stage. Plays scripted dialogue, real enforcement |
| `demo-runbook.md` | Speaker's printed runbook for stage |
| `lib/` | bash primitives: typing animation, pause-on-spacebar, ANSI colors |
| `dialogue/` | The three scripted beats, plus a JSON fixture for Beat 1 |
| `claude-hooks/` | The PreToolUse hook script + reference settings.json |
| `iac-repo-template/` | Template for the inner IaC repo that Beat 2 hits |
| `manifests/` | All Kubernetes YAML applied by setup.sh |

### Generated at setup time (gitignored)

Anything in `.local/`:

| Path | What it is |
|---|---|
| `.local/kubeconfig` | Kubeconfig pointing at the agent's projected token |
| `.local/agent-token` | 1-hour projected ServiceAccount token, refreshed by setup |
| `.local/audit.log` | Tail of the K8s API server audit log |
| `.local/iac-repo/` | Hydrated copy of `iac-repo-template/` with a real `.git/` directory and the pre-commit hook installed |

The `.local/` directory is in `.gitignore`. Never check it in.

---

## The three beats

### Beat 1 — Claude Code PreToolUse hook

The agent is asked to ship model v1.3.0 to production. It tries the obvious thing: `kubectl set image deployment/model-server -n production`. The PreToolUse hook intercepts the tool call before execution, denies it, and returns a stderr explaining why.

**What fires:** `claude-hooks/pretool-use-block-prod.sh`

The hook reads a tool-call JSON on stdin and exits with code 2 if the tool input matches one of three dangerous patterns: direct kubectl against production, direct registry mutation, or direct file edits on `infrastructure/production/`.

### Beat 2 — Git pre-commit hook

Blocked from kubectl, the agent tries the IaC path. It edits `infrastructure/production/model-server.yaml` to bump the image tag and runs `git commit`. The pre-commit hook rejects the commit because the path is protected AND because the committer email is `claude-agent@anthropic.local` (non-human identity).

**What fires:** `.local/iac-repo/.git/hooks/pre-commit` (copied from `iac-repo-template/hooks/pre-commit` at setup time)

The hook checks each staged file against `PROTECTED_PATHS` and the configured user email. Either condition triggers an exit 1 with a stderr deny.

### Beat 3 — Kubernetes ValidatingAdmissionPolicy

Out of local options, the agent bypasses the PreToolUse hook by writing the manifest to a file and applying it. The K8s API server itself denies the apply via a `ValidatingAdmissionPolicy` bound to the `production` namespace.

**What fires:** `manifests/40-vap-production-guard.yaml`

Native to K8s 1.30+. CEL-evaluated. No webhook, no controller. The policy denies writes to `production` from any `system:serviceaccount:` principal that isn't ArgoCD or the MLOps pipeline.

---

## Running the demo

### First time setup

```bash
bash setup.sh
```

Takes about 90 seconds. Verifies all three layers fire correctly when tested standalone. If any acceptance check fails, setup exits non-zero.

### Running the demo

```bash
bash demo.sh
```

The runner prints a Claude Code-style banner, then waits for SPACE to begin Beat 1. Press SPACE between beats. Auto-pace within each beat (typing animations).

### Faster typing for rehearsal

```bash
TYPE_DELAY_MS=10 bash demo.sh
```

### Skip beats during testing

```bash
bash demo.sh --resume-beat=2     # Start at Beat 2
bash demo.sh --dry-run           # Print all dialogue, don't execute commands
```

### Between rehearsal runs

```bash
bash reset.sh                    # Refresh state, keep the cluster
```

### After the talk

```bash
bash teardown.sh
```

---

## Architecture conventions

- **Repo-relative paths:** Every script resolves `$DEMO_ROOT` as `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`. No hardcoded absolute paths.
- **Ephemeral artifacts in `.local/`:** Anything generated by `setup.sh` lives in `.local/` and is gitignored.
- **Layer isolation:** Each of the three layers can be tested standalone without running the full demo. See the acceptance criteria in the build spec.
- **Real enforcement:** The hooks and policies are real bash scripts and real K8s resources. Only the agent's dialogue is scripted.

---

## Eight Guardrails coverage

This demo lives three of the Eight Guardrails. The other five are addressed by the repo's policies and the deployment pattern:

1. ✅ **PreToolUse hook** — demonstrated in Beat 1
2. ✅ **Git pre-commit hook** — demonstrated in Beat 2
3. ✅ **K8s admission policy** — demonstrated in Beat 3
4. **IaC-only infrastructure changes** — referenced by Beat 2's protected paths
5. **Least-privilege RBAC** — agent SA is scoped to `staging` only (see `manifests/20-rbac.yaml`)
6. **Automated rollback** — ArgoCD pattern, mentioned on slide 8
7. **Audit logging** — K8s API server audit log enabled via `manifests/audit-policy.yaml`
8. **Tested in CI** — the hook scripts have unit tests in this repo (see `tests/`)

---

## Troubleshooting

**`setup.sh` fails on `k3d cluster create`**

The cluster name `llmday-demo` may already exist. Run `k3d cluster delete llmday-demo` and try again, or run `bash teardown.sh` first.

**Hook doesn't fire in Beat 1**

Test the hook standalone:
```bash
bash claude-hooks/pretool-use-block-prod.sh < dialogue/beat1-toolcall.json
echo "exit code: $?"
```
Expected: exit code 2, stderr contains `PRETOOLUSE_HOOK_DENY`.

**Beat 2 git commit succeeds when it shouldn't**

The pre-commit hook may not be installed. Check:
```bash
ls -l .local/iac-repo/.git/hooks/pre-commit
```
Should be executable. If missing, re-run `setup.sh`.

**VAP doesn't deny in Beat 3**

Verify the policy is applied and bound:
```bash
kubectl get validatingadmissionpolicy
kubectl get validatingadmissionpolicybinding
```

**Token expired mid-demo**

`reset.sh` refreshes the token. The token has a 1-hour TTL by default; for long Q&A sessions, you may need to refresh between the talk and Q&A.

---

## Related

- **Talk slides:** `llmday-austin-2026-deck-v11.pptx` (sibling artifact, not in this repo)
- **Build spec:** `llmday-demo-build-spec-v4.1.md` (the contract this demo is built from)
- **Sister talks:**
  - SREday Austin · *The Day an AI Agent Deleted My Cluster* (May 11, 2026)
  - KCD Texas · *The 90-Minute IDP* (May 15, 2026)

---

## License

Whatever the parent `agentic-covenants` repo uses. The Eight Guardrails Framework documented here is Michael Forrester's original work.
