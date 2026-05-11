# LLMday Austin Demo · Three-Layer Pipeline Guardrails (EKS Auto Mode)

A live, scripted terminal demo for the talk *"Your MLOps Pipeline is your Agentic AI Guardrail"* delivered at LLMday Austin on May 12, 2026.

The demo shows three layers of an existing MLOps pipeline catching an AI agent that tries to ship a model update to production:

1. **Claude Code PreToolUse hook** — denies the dangerous tool call before execution
2. **Git pre-commit hook** — rejects the agent's commit on a protected path
3. **Kubernetes ValidatingAdmissionPolicy** — denies the agent's direct API call at the EKS API server

The agent dialogue is scripted (for predictable timing on stage). The enforcement at every layer is real. The cluster is a real **Amazon EKS Auto Mode** cluster running Kubernetes 1.33.

The full build contract is at `../docs/SPEC.md` (v4.2).

---

## Prerequisites

On Megumi (the laptop you'll present from):

- AWS CLI v2 configured (`aws sts get-caller-identity` returns a valid identity)
- `eksctl >= 0.225`
- `kubectl >= 1.33`
- `helm >= 3.18`
- `git`, `bash`, `awk`, `jq`
- An AWS region picked. Default: `us-east-2`.
- IAM permissions sufficient to create EKS clusters and the IAM roles Auto Mode needs (`eksctl create cluster --enable-auto-mode` handles the boilerplate; you need the permission to create those resources).

---

## Quick start

```bash
cd <repo>/demo

# 1) One-time tonight (12-15 min)
bash provision-cluster.sh     # creates the EKS Auto Mode cluster, installs Falco + OTel

# 2) Every time (~60 seconds)
bash setup.sh                 # applies demo manifests, issues 1h agent token, verifies all 3 layers

# 3) On stage
bash demo.sh                  # press SPACE at each beat transition

# 4) Between rehearsal runs (optional)
bash reset.sh                 # re-hydrates iac-repo, refreshes the agent token

# 5) After the talk (10 min, costs you nothing to run later)
bash teardown.sh              # deletes the cluster + .local/
```

Environment overrides:
- `AWS_REGION` (default `us-east-2`)
- `AWS_PROFILE`
- `CLUSTER_NAME` (default `llmday-demo`)
- `K8S_VERSION` (default `1.33`)
- `TOKEN_TTL` (default `1h`)
- `TYPE_DELAY_MS` (default `30` — speed up typing animation for rehearsal)

---

## What's in here

### Checked into the repo

| Path | What it is |
|---|---|
| `provision-cluster.sh` | One-time EKS Auto Mode + Helm install. Run tonight. |
| `setup.sh` | Applies demo manifests to the existing cluster. Builds kubeconfigs. Verifies all three layers. |
| `reset.sh` | Re-hydrates iac-repo and refreshes the agent token. Cluster stays up. |
| `teardown.sh` | `eksctl delete cluster` + `.local/` cleanup. **Run only after the talk.** |
| `demo.sh` | The runner Michael executes on stage. Plays scripted dialogue, real enforcement. |
| `demo-runbook.md` | Speaker's printed runbook for stage |
| `lib/` | bash primitives: typing animation, pause-on-spacebar, ANSI colors |
| `dialogue/` | The three scripted beats, plus a JSON fixture for Beat 1 |
| `claude-hooks/` | The PreToolUse hook script + reference settings.json |
| `iac-repo-template/` | Template for the inner IaC repo that Beat 2 hits |
| `manifests/` | Kubernetes YAML applied to the EKS cluster |
| `manifests/observability/` | Helm values files for Falco and OTel |

### Generated at setup time (gitignored)

Anything in `.local/`:

| Path | What it is |
|---|---|
| `.local/operator-kubeconfig` | Operator kubeconfig (uses AWS credentials via `aws eks get-token`) |
| `.local/kubeconfig` | Agent kubeconfig (uses a K8s ServiceAccount projected token, **not** AWS creds) |
| `.local/agent-token` | 1-hour projected ServiceAccount token, refreshed by `setup.sh`/`reset.sh` |
| `.local/cluster-info.json` | Cached `aws eks describe-cluster` output |
| `.local/iac-repo/` | Hydrated copy of `iac-repo-template/` with a real `.git/` and the pre-commit hook installed |

The `.local/` directory is gitignored. Never check it in.

---

## The three beats

### Beat 1 — Claude Code PreToolUse hook

The agent is asked to ship model v1.3.0 to production. It tries `kubectl set image deployment/model-server -n production`. The PreToolUse hook intercepts the tool call before execution, denies it, and returns a stderr explaining why.

**What fires:** `claude-hooks/pretool-use-block-prod.sh`

### Beat 2 — Git pre-commit hook

Blocked from kubectl, the agent edits `infrastructure/production/model-server.yaml` and runs `git commit`. The pre-commit hook rejects the commit because the path is protected AND because the committer email is `claude-agent@anthropic.local`.

**What fires:** `.local/iac-repo/.git/hooks/pre-commit` (copied from `iac-repo-template/hooks/pre-commit` at setup time, with an explicit `core.hooksPath` override that defeats any host-global hooks dir)

### Beat 3 — Kubernetes ValidatingAdmissionPolicy

The agent writes the manifest to a file and applies it via `kubectl`. The EKS API server denies the apply via a `ValidatingAdmissionPolicy` bound to the `production` namespace.

**What fires:** `manifests/40-vap-production-guard.yaml` (deployed by `setup.sh` to the EKS cluster)

The deny is also visible in the CloudWatch tail in the bottom-right tmux pane.

---

## Architecture conventions

- **Repo-relative paths.** Every script resolves `$DEMO_ROOT` as `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`. No hardcoded absolute paths.
- **Ephemeral artifacts in `.local/`.** Anything generated by setup lives in `.local/` and is gitignored.
- **Two kubeconfigs.** `operator-kubeconfig` uses AWS credentials (for `setup.sh`, `kubectl apply`, debugging). `kubeconfig` (the agent's) uses a short-lived ServiceAccount projected token (what `demo.sh` runs against).
- **Real enforcement.** All three layers are real scripts and real K8s resources. Only the agent's dialogue is scripted.

---

## Eight Guardrails coverage

This demo lives three of the Eight Guardrails. The other five are addressed by the repo's policies and the deployment pattern:

1. ✅ **PreToolUse hook** — demonstrated in Beat 1
2. ✅ **Git pre-commit hook** — demonstrated in Beat 2
3. ✅ **K8s admission policy** — demonstrated in Beat 3
4. **IaC-only infrastructure changes** — referenced by Beat 2's protected paths
5. **Least-privilege RBAC** — agent SA is scoped to `staging` only (see `manifests/20-rbac.yaml`)
6. **Automated rollback** — ArgoCD pattern, mentioned on the deck
7. **Audit logging** — EKS audit log exported to CloudWatch by `provision-cluster.sh`
8. **Tested in CI** — the hook scripts have unit tests (Layer 1 and Layer 2 are exercised standalone in `setup.sh`'s verify block)

---

## Troubleshooting

**`provision-cluster.sh` fails on `eksctl create cluster`**

Check your AWS credentials (`aws sts get-caller-identity`) and EKS cluster quota in the chosen region. The Auto Mode feature requires permission to create IAM roles.

**`setup.sh` says cluster not found**

Run `provision-cluster.sh` first. Setup expects an already-provisioned cluster.

**Hook doesn't fire in Beat 1**

Test the hook standalone:
```bash
bash claude-hooks/pretool-use-block-prod.sh < dialogue/beat1-toolcall.json
echo "exit code: $?"
```
Expected: exit code 2, stderr contains `PRETOOLUSE_HOOK_DENY`.

**Beat 2 git commit succeeds when it shouldn't**

The pre-commit hook may not be installed, or your host has a global `core.hooksPath` overriding the per-repo one. `setup.sh` sets `core.hooksPath` inside the iac-repo to defeat that. Verify:
```bash
cd .local/iac-repo
git config --get core.hooksPath   # should print ".git/hooks"
ls -l .git/hooks/pre-commit       # should be executable
```

**VAP doesn't deny in Beat 3**

Verify the policy is applied:
```bash
kubectl --kubeconfig=.local/operator-kubeconfig get validatingadmissionpolicy
kubectl --kubeconfig=.local/operator-kubeconfig get validatingadmissionpolicybinding
```

**Token expired mid-demo**

`reset.sh` refreshes the token. The token has a 1-hour TTL by default; refresh between the talk and Q&A if you're running long.

**AWS credentials expired mid-demo**

Re-run `aws sso login` or `aws-vault exec ...` to refresh and run `setup.sh` again (it'll regenerate the operator kubeconfig).

---

## Cost

EKS control plane + Auto Mode + a couple of small nodes + CloudWatch: roughly **$5-6 for a 24-hour cluster lifetime**. Cheap. Tear down after the talk and it stops billing.

---

## Related

- **Build spec:** `../docs/SPEC.md` (v4.2)
- **Talk slides:** `../presentations/llmday-austin-2026-mlops-pipeline-guardrail-v06.pptx`
- **Sister talks:**
  - SREday Austin · *The Day an AI Agent Deleted My Cluster* (May 11, 2026)
  - KCD Texas · *The 90-Minute IDP* (May 15, 2026)

---

## License

This demo is part of the LLMday Texas 2026 repo and is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution: Michael R Forrester, 2026. The Eight Guardrails Framework and the Agentic Covenants Matrix referenced here are Michael R Forrester's original work, maintained at [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants).
