# LLMday Austin Demo · Three-Layer Pipeline Guardrails (EKS Auto Mode + GitOps)

A live, scripted terminal demo for the talk *"Your MLOps Pipeline is your Agentic AI Guardrail"* delivered at LLMday Austin on May 12, 2026.

The demo shows three layers of an existing MLOps pipeline catching an AI agent that tries to ship a model update to production:

1. **Claude Code PreToolUse hook** — denies the dangerous tool call before execution
2. **Git pre-commit hook** — rejects the agent's commit on a protected path
3. **Kubernetes ValidatingAdmissionPolicy** — denies the agent's direct API call at the EKS API server

The agent dialogue is scripted (for predictable timing on stage). The enforcement is real. The cluster is a real **Amazon EKS Auto Mode** cluster running Kubernetes 1.35, bootstrapped via **GitOps (ArgoCD app-of-apps with sync waves)** to a full MLOps platform.

Build spec: `../docs/SPEC.md` (v4.7).

---

## Prerequisites

On the machine you'll run the demo from (your laptop, a VPS, or this Claude Code shell — they're all just SSH endpoints):

- AWS CLI v2 configured
- `aws sts get-caller-identity` returns a valid identity
- `eksctl >= 0.225`, `kubectl >= 1.35`, `helm >= 3.21`, `git`, `bash`, `awk`, `jq`
- IAM permissions to create EKS clusters and the IAM roles Auto Mode needs

---

## Quick start

```bash
cd <repo>/demo

# 1) Once tonight (~25-30 min total)
bash provision-cluster.sh     # creates the cluster, installs ArgoCD, applies root-app
bash setup.sh                 # waits for the 21 ArgoCD apps to Healthy+Synced, issues agent token, verifies all 3 layers

# 2) On stage
bash demo.sh                  # press SPACE at each beat transition

# 3) Between rehearsal runs (optional)
bash reset.sh                 # re-hydrates iac-repo, refreshes the agent token

# 4) After the talk (~10 min)
bash teardown.sh              # eksctl delete cluster + .local/ wipe
```

Environment overrides:
- `AWS_REGION` (default `us-east-2`)
- `AWS_PROFILE`
- `CLUSTER_NAME` (default `llmday-demo`)
- `K8S_VERSION` (default `1.35`)
- `TOKEN_TTL` (default `1h`)
- `SYNC_TIMEOUT` (default `1200` — 20 min budget for the full GitOps sync)
- `TYPE_DELAY_MS` (default `30` — speed up typing animation for rehearsal)

---

## What's in here

### Tracked in the repo

| Path | What it is |
|---|---|
| `provision-cluster.sh` | One-time EKS Auto Mode + ArgoCD install + root-app apply (~14 min) |
| `setup.sh` | Waits for the 21 Applications to be Healthy+Synced, then sets up demo state and verifies all 3 layers |
| `reset.sh` | Re-hydrates iac-repo and refreshes the agent token. Cluster stays up. |
| `teardown.sh` | `eksctl delete cluster` + `.local/` cleanup |
| `demo.sh` | The runner. Plays scripted dialogue, real enforcement. |
| `demo-runbook.md` | Speaker's printed runbook |
| `lib/` | bash primitives: typing animation, pause-on-spacebar, ANSI colors |
| `dialogue/` | The three scripted beats + Beat 1's JSON fixture |
| `claude-hooks/` | Layer 1: PreToolUse hook + reference settings |
| `iac-repo-template/` | Template for Beat 2's git repo |
| `gitops/bootstrap/root-app.yaml` | The seed Application |
| `gitops/apps/` | 21 Application manifests with sync-wave annotations |
| `gitops/values/` | Helm values per platform component |
| `gitops/manifests/` | Raw YAML: namespaces, Kyverno policies, Tetragon TracingPolicies, cert issuer, VAP, RBAC, KServe workload, model registry data |

### Generated at setup time (gitignored)

Everything under `.local/`:

| Path | What it is |
|---|---|
| `.local/operator-kubeconfig` | Operator kubeconfig (uses AWS credentials via `aws eks get-token`) |
| `.local/kubeconfig` | Agent kubeconfig (uses a K8s ServiceAccount projected token) |
| `.local/agent-token` | 1-hour projected SA token |
| `.local/cluster-info.json` | Cached `aws eks describe-cluster` output |
| `.local/iac-repo/` | Hydrated copy of `iac-repo-template/` with real `.git/` |
| `.local/provision.log` | Log of the last `provision-cluster.sh` run |

---

## What the cluster runs

After `provision-cluster.sh` + GitOps sync completes, the cluster has:

**Enforcement / security**
- Native Kubernetes ValidatingAdmissionPolicy (matches Deployments AND KServe InferenceServices)
- Kyverno with 6 baseline ClusterPolicies (Audit mode, in addition to native VAP)
- Tetragon with 3 TracingPolicies (sigkill on shell-in-mlops; alert on IMDS access and /etc writes)
- Falco DaemonSet for runtime detection
- Falcosidekick routing Falco events to Prometheus

**Identity / certs**
- SPIRE server + agent (the in-cluster identity-of-record)
- cert-manager + self-signed ClusterIssuer

**Observability**
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics)
- Loki (single-binary) + Promtail for logs
- Jaeger all-in-one for traces
- OpenTelemetry Collector
- EKS audit log exported to CloudWatch

**MLOps**
- KServe controller (raw deployment mode)
- `model-server` InferenceService in `production`, sklearn iris model
- Kubeflow Model Registry (standalone ConfigMap state with v1.0.0 through v1.3.0)
- Argo Workflows + a `WorkflowTemplate` named `promote-model-to-production` (verbal reference only)

**GitOps**
- ArgoCD reconciling 21 Applications via the root app-of-apps
- `ServerSideApply=true` for Kyverno's large CRDs

The audience won't see most of this UI during the 8-minute demo. They'll see that it's *there*, in `kubectl get pods -A` and ArgoCD's app list.

---

## The three beats

### Beat 1 — Claude Code PreToolUse hook
Agent tries `kubectl set image deployment/model-server -n production`. The hook intercepts before execution and exits 2 with stderr deny.

**What fires:** `claude-hooks/pretool-use-block-prod.sh`

### Beat 2 — Git pre-commit hook
Agent edits `infrastructure/production/model-server.yaml`, runs `git commit`. The hook rejects on two grounds: protected path + non-human committer email.

**What fires:** `.local/iac-repo/.git/hooks/pre-commit` (copied from `iac-repo-template/hooks/pre-commit` at setup time, with `core.hooksPath` override to defeat any host global hooks dir)

### Beat 3 — Kubernetes ValidatingAdmissionPolicy
Agent writes the manifest and applies via `kubectl`. The EKS API server denies it via VAP. The deny appears in CloudWatch within ~30s.

**What fires:** `gitops/manifests/vap/vap.yaml` (reconciled by ArgoCD)

---

## Architecture conventions

- **GitOps from minute one.** `provision-cluster.sh` installs ArgoCD only. Everything else is GitOps. Apps reconcile in sync-wave order.
- **Repo-relative paths.** Every script resolves `$DEMO_ROOT` as `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`.
- **Ephemeral artifacts in `.local/`.** Anything generated by setup is gitignored.
- **Two kubeconfigs.** `operator-kubeconfig` for setup and `kubectl` debugging (AWS-creds-backed). `kubeconfig` (agent's) is what `demo.sh` runs against (short-lived SA token).
- **Real enforcement.** All three layers are real scripts and real K8s resources. Only the agent's dialogue is scripted.

---

## Troubleshooting

**`provision-cluster.sh` failed at `eksctl create cluster`** — check AWS creds and EKS cluster quota in the region. Auto Mode requires permission to create IAM roles.

**`setup.sh` says GitOps sync didn't complete in time** — open the ArgoCD UI (or run `kubectl --kubeconfig=.local/operator-kubeconfig get applications -n argocd`) and inspect which app is stuck. Common causes: CRDs not yet registered (wait wave), Helm chart version mismatch, image pull issues. `ServerSideApply=true` is set in root-app.yaml and should already handle Kyverno's large CRDs.

**Hook doesn't fire in Beat 1** — test the hook standalone:
```bash
bash claude-hooks/pretool-use-block-prod.sh < dialogue/beat1-toolcall.json
echo "exit code: $?"   # expect 2
```

**Beat 2 git commit succeeds when it shouldn't** — your host has a global `core.hooksPath` overriding the per-repo one. `setup.sh` sets `core.hooksPath` inside the iac-repo to defeat that. Verify:
```bash
cd .local/iac-repo
git config --get core.hooksPath   # should print ".git/hooks"
```

**VAP doesn't deny in Beat 3** — verify the policy and binding are applied:
```bash
kubectl --kubeconfig=.local/operator-kubeconfig get validatingadmissionpolicy
kubectl --kubeconfig=.local/operator-kubeconfig get validatingadmissionpolicybinding
```

**Token expired** — `reset.sh` refreshes the token. 1-hour TTL by default.

**AWS credentials expired** — re-run `aws sso login` (or refresh `aws-vault`), then re-run `setup.sh`. It regenerates the operator kubeconfig.

---

## Cost

EKS control plane + Auto Mode + workload pods + CloudWatch + EBS: roughly **$14-17 for a 24-hour cluster lifetime**. Tear down after the talk and billing stops.

---

## Related

- **Build spec:** `../docs/SPEC.md` (v4.7)
- **Talk slides:** `../presentations/llmday-austin-2026-mlops-pipeline-guardrail-v06.pptx`
- **Sister talks:** SREday Austin yesterday, KCD Texas Friday

---

## License

CC BY 4.0. Attribution: Michael R Forrester, 2026. The Eight Guardrails Framework and the Agentic Covenants Matrix are Michael R Forrester's original work at [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants).
