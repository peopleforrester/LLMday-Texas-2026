# LLMday Austin Demo · Six Gates, Five Live (EKS Auto Mode + GitOps)

A live, scripted terminal demo for the talk *"Your MLOps Pipeline is your Agentic AI Guardrail"* delivered at LLMday Austin on May 12, 2026.

The demo shows six gates of an existing MLOps pipeline catching an AI agent that tries to ship a model update to production. Five run live; the sixth is shown on slide. The six gates span the three architectural layers from the Agentic Covenants Matrix (in-agent, client-side, server-side):

| Demo | Gate | Layer |
|---|---|---|
| 1 | Claude Code PreToolUse hook | In-agent |
| 2 | Git pre-commit hook | Client-side |
| 3 | Kubernetes ValidatingAdmissionPolicy | Server-side · admission |
| 4 | Falco custom rule + Falco Talon response | Server-side · runtime |
| 5 | Kubernetes NetworkPolicy egress allowlist | Server-side · network |
| 6 | LLM Guard / NeMo Guardrails (output filter) | Output (shown on slide) |

The agent dialogue is scripted, for predictable timing on stage. The enforcement is real. The cluster is a real **Amazon EKS Auto Mode** cluster running Kubernetes 1.35, bootstrapped via **GitOps (ArgoCD app-of-apps with sync waves)** to a full MLOps platform. Falco's custom rule, Falco Talon's response binding, the EKS Auto Mode NetworkPolicy enable flag, and the production egress allowlist are all GitOps-managed under `gitops/`.

Build spec: `../docs/SPEC.md`.

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
bash setup.sh                 # waits for the ArgoCD apps to Healthy+Synced, issues agent token, verifies the enforcement chain

# 2) On stage
bash demo.sh                  # press SPACE at each beat transition (scripted dialogue, five live demos)

# Optional alternatives
bash demo-claude.sh           # hands the same scenario to a live Claude Code agent (variable behavior, real cost)
bash demo-settings.sh         # walks the enforcement files on disk, beat by beat (file-walk mode)

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
| `setup.sh` | Waits for the ArgoCD apps to be Healthy+Synced, then sets up demo state and verifies the enforcement chain (hook, git, VAP, Falco/Talon, NetworkPolicy) |
| `reset.sh` | Re-hydrates iac-repo and refreshes the agent token. Cluster stays up. |
| `teardown.sh` | `eksctl delete cluster` + `.local/` cleanup |
| `demo.sh` | Primary runner. Plays scripted dialogue across all five live beats with one-key advance. |
| `demo-claude.sh` | Live-agent variant. Hands the scenario to a real Claude Code CLI session via `claude -p`; the agent attempts every path and prints what fired. Costs API credits; not for stage, use for rehearsal and recording. |
| `demo-settings.sh` | File-walk variant. Slow-prints each enforcement file (hook, git hook, VAP, Falco rules, Talon binding, vpc-cni enable, NetworkPolicy) with syntax highlighting and auto-pause. |
| `demo-runbook.md` | Speaker's printed runbook |
| `lib/` | bash primitives: typing animation, pause-on-spacebar, ANSI colors, shared ASCII memes |
| `dialogue/` | Scripted dialogue files for all five live beats plus Beat 1's JSON fixture |
| `claude-hooks/` | Beat 1: PreToolUse hook + reference settings |
| `iac-repo-template/` | Template for Beat 2's git repo |
| `gitops/bootstrap/root-app.yaml` | The seed Application |
| `gitops/apps/` | ArgoCD Application manifests with sync-wave annotations |
| `gitops/values/` | Helm values per platform component, including `falco-values.yaml` (Beat 4 custom rule) and `falco-talon-values.yaml` (Beat 4 response binding) |
| `gitops/manifests/` | Raw YAML: namespaces, Kyverno policies, Tetragon TracingPolicies, cert issuer, VAP (Beat 3), RBAC, model-server Deployment, model registry data, `cluster-config/` (Beat 5 vpc-cni enable), `networkpolicies/` (Beat 5 production egress allowlist) |

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
- Native Kubernetes ValidatingAdmissionPolicy on Deployments and pods in the production namespace. The CEL is resource-type-agnostic; the VAP also matches KServe InferenceServices by design, even though KServe isn't installed in this build (see "MLOps" below). Demo 3.
- Kyverno with 6 baseline ClusterPolicies (Audit mode, in addition to native VAP)
- Tetragon with 3 TracingPolicies (sigkill on shell-in-mlops; alert on IMDS access and /etc writes)
- Falco DaemonSet for runtime detection, plus a custom rule mounted via the chart's `customRules` value that fires on shell binaries spawned inside production pods with containerd-shim as parent. Demo 4.
- Falcosidekick routing Falco events to Prometheus and to Falco Talon
- Falco Talon as the response engine, with `kubernetes:terminate` bindings against the custom rule names. Demo 4.
- EKS Auto Mode Network Policy Controller enabled via the `amazon-vpc-cni` ConfigMap, plus a production-namespace `NetworkPolicy` that default-denies egress and allows only DNS (via ipBlock against the cluster service CIDR) plus intra-namespace and model-registry traffic. Demo 5.

**Identity / certs**
- cert-manager + self-signed ClusterIssuer

**Observability**
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics)
- Loki (single-binary) + Promtail for logs
- Jaeger all-in-one for traces
- OpenTelemetry Collector
- EKS audit log exported to CloudWatch

**MLOps**
- `model-server` plain `Deployment` in `production`, running `nginxinc/nginx-unprivileged:1.27-alpine`. KServe was dropped from the GitOps tree because its Helm chart isn't published at a stable URL; raw manifests weren't justified for this demo. The narrative isn't materially affected: the agent tries to modify a Deployment in production, the gates fire. The model-server manifest documents the decision inline.
- Kubeflow Model Registry (standalone ConfigMap state with v1.0.0 through v1.3.0)
- Argo Workflows + a `WorkflowTemplate` named `promote-model-to-production` (verbal reference only)

**GitOps**
- ArgoCD reconciling 19 Applications via the root app-of-apps
- `ServerSideApply=true` for Kyverno's large CRDs

The audience won't see most of this UI during the 8-minute demo. They'll see that it's *there*, in `kubectl get pods -A` and ArgoCD's app list.

---

## The five live beats (and the sixth on slide)

### Beat 1 — Claude Code PreToolUse hook (in-agent)
Agent tries `kubectl set image deployment/model-server -n production`. The hook intercepts before execution and exits 2 with stderr deny.

**What fires:** `claude-hooks/pretool-use-block-prod.sh`

### Beat 2 — Git pre-commit hook (client-side)
Agent edits `infrastructure/production/model-server.yaml`, runs `git commit`. The hook rejects on two grounds: protected path and non-human committer email.

**What fires:** `.local/iac-repo/.git/hooks/pre-commit`, copied from `iac-repo-template/hooks/pre-commit` at setup time, with `core.hooksPath` override to defeat any host global hooks dir.

### Beat 3 — Kubernetes ValidatingAdmissionPolicy (server-side, admission)
Agent writes the manifest to a file and applies it via `kubectl apply -f`. The EKS API server denies it via the native VAP. The deny appears in CloudWatch within about 30 seconds.

**What fires:** `gitops/manifests/vap/vap.yaml`, reconciled by ArgoCD.

### Beat 4 — Falco custom rule + Falco Talon (server-side, runtime)
Agent realizes admission has nothing to validate if the Deployment isn't being modified, so it `kubectl exec`s into a model-server pod. The custom Falco rule "Agent exec in production" fires on the shell-binary spawn. Falcosidekick forwards the event to Falco Talon over HTTP, and Talon calls `kubernetes:terminate` against the originating pod. The ReplicaSet self-heals.

**What fires:** `gitops/values/falco-values.yaml` (the `customRules.llmday-rules.yaml` block) plus `gitops/values/falco-talon-values.yaml` (the `config.rulesOverride` rule binding).

### Beat 5 — NetworkPolicy egress allowlist (server-side, network)
Agent does nothing unsafe at the syscall level. It just runs `wget https://huggingface.co/...` from inside a production pod. DNS resolves, but the TCP SYN is dropped at the wire because huggingface.co is not on the production egress allowlist. Falco does not fire and Talon does not run. The pod stays alive; the destination was the issue.

**What fires:** `gitops/manifests/cluster-config/vpc-cni-network-policy.yaml` (the EKS Auto Mode Network Policy Controller enable knob) plus `gitops/manifests/networkpolicies/netpol.yaml` (the production egress allowlist).

### Beat 6 — Output / content (slide only)
Layers 1 through 5 catch agent actions on the infrastructure side. Beat 6 catches what the model says. The deck references LLM Guard, NeMo Guardrails, and Envoy AI Gateway as the production implementations; this demo does not run it live. Closing line on the slide: *"Layers 1 through 5 keep the agent from breaking the system. Layer 6 keeps the system from saying things it shouldn't."*

---

## Architecture conventions

- **GitOps from minute one.** `provision-cluster.sh` installs ArgoCD only. Everything else is GitOps. Apps reconcile in sync-wave order.
- **Repo-relative paths.** Every script resolves `$DEMO_ROOT` as `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`.
- **Ephemeral artifacts in `.local/`.** Anything generated by setup is gitignored.
- **Two kubeconfigs.** `operator-kubeconfig` for setup and `kubectl` debugging (AWS-creds-backed). `kubeconfig` (agent's) is what `demo.sh` runs against (short-lived SA token).
- **Real enforcement.** Every live beat exercises a real script or real K8s resource. Only the agent's dialogue is scripted.

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

**Falco rule doesn't fire in Beat 4** — give the Falco DaemonSet a minute to attach its eBPF probes after any rollout. Then check the custom rule is present in each pod and that events are flowing:
```bash
kubectl -n falco exec ds/falco -c falco -- ls /etc/falco/rules.d/   # expect llmday-rules.yaml
kubectl -n falco logs ds/falco -c falco --since=60s | grep '"rule":"Agent exec in production"' | head
```

**Talon doesn't kill the pod in Beat 4** — verify Talon loaded the rule bindings and that falcosidekick is forwarding:
```bash
kubectl -n falco logs deploy/falco-talon --tail=10 | grep 'rule(s) has/have been successfully loaded'
kubectl -n falco logs deploy/falco-falcosidekick --tail=20 | grep -i 'Talon - POST'
```

**NetworkPolicy doesn't block in Beat 5** — most common cause is the EKS Auto Mode Network Policy Controller is off. Check the enable ConfigMap and that PolicyEndpoints are being generated:
```bash
kubectl -n kube-system get cm amazon-vpc-cni -o jsonpath='{.data.enable-network-policy-controller}'   # expect "true"
kubectl -n production get policyendpoints                                                              # expect at least one
```

**Token expired** — `reset.sh` refreshes the token. 1-hour TTL by default; `TOKEN_TTL=8h bash reset.sh` for a longer rehearsal window.

**AWS credentials expired** — re-run `aws sso login` (or refresh `aws-vault`), then re-run `setup.sh`. It regenerates the operator kubeconfig.

---

## Cost

EKS control plane + Auto Mode + workload pods + CloudWatch + EBS: roughly **$14-17 for a 24-hour cluster lifetime**. Tear down after the talk and billing stops.

---

## Related

- **Build spec:** `../docs/SPEC.md`
- **Talk slides:** `../presentations/llmday-austin-2026-deck-v19.pptx`
- **Sister talks:** SREday Austin (May 11), KCD Texas (May 15)

---

## License

CC BY 4.0. Attribution: Michael R Forrester, 2026. The Eight Guardrails Framework and the Agentic Covenants Matrix are Michael R Forrester's original work at [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants).
