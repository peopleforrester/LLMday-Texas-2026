# LLMday Austin Live Demo Build Spec — v4.7

**Talk:** Your MLOps Pipeline is your Agentic AI Guardrail
**Date:** Tue May 12, 2026
**Venue:** The Sunset Room, Austin
**Speaker:** Michael Forrester
**Demo block:** ~8 minutes, mid-talk, three beats
**Spec version:** v4.7 — adds real MLOps components (KServe, Kubeflow Model Registry, Argo Workflows), Loki logs, Falcosidekick on top of v4.6's GitOps bootstrap

---

## Cluster topology — EKS Auto Mode + managed node group, K8s 1.35

- Cluster: `llmday-demo`, region `us-east-2`, version `1.35`
- Compute: EKS Auto Mode **and** a managed node group of 2× t3.large for predictable platform pods
- Bootstrap: procedural `provision-cluster.sh` creates the cluster, installs ArgoCD only, applies the root Application. Everything else flows from GitOps reconciliation.

Memory budget (~7.1 GB on 16 GB total managed node group capacity):

| Component | Memory request |
|---|---|
| Falco DaemonSet + Falcosidekick | ~700 Mi |
| Tetragon DaemonSet | ~400 Mi |
| kube-prometheus-stack | ~1.5 GB |
| Loki + Promtail | ~700 Mi |
| Jaeger all-in-one | 256 Mi |
| OTel Collector | 256 Mi |
| ArgoCD | ~700 Mi |
| Kyverno | ~512 Mi |
| SPIRE server + agent | 256 Mi |
| cert-manager | 256 Mi |
| KServe controller | ~256 Mi |
| Argo Workflows controller + server | ~256 Mi |
| Kubeflow Model Registry | ~256 Mi |
| model-server (KServe InferenceService, sklearn iris) | ~512 Mi |
| EKS Auto Mode add-ons + system overhead | ~1.5 GB |

The 8-minute demo flow is unchanged from v4.1. The expanded MLOps surface is background credibility.

---

## GitOps bootstrap

Procedural phase installs ArgoCD only. The root Application reconciles everything else from `demo/gitops/apps/`, ordered by sync waves:

| Wave | Apps |
|---|---|
| -10 | namespaces (with PSS labels) |
| -5 | spire-crds, kserve-crd |
| -4 | kyverno (installCRDs), cert-manager (installCRDs), spire-server, kserve-controller |
| -3 | kyverno-policies, spire-agent, rbac, kserve-runtimes |
| -2 | falco (with falcosidekick), tetragon |
| -1 | cert-issuers |
| 0 | admission (VAP + binding + quotas) |
| 1 | kube-prometheus-stack, loki |
| 2 | otel, argo-workflows |
| 3 | jaeger, kubeflow-model-registry |
| 4 | model-server (KServe InferenceService) + WorkflowTemplate |

`ServerSideApply=true` in syncOptions is mandatory (Kyverno CRDs exceed 256KB).

Total wave-sync time on freshly provisioned cluster: ~14-19 min after `provision-cluster.sh` returns.

---

## The narrative (unchanged from v4.1)

ML engineer asks the agent to ship model v1.3.0 to production. Three layers catch it:

1. **Beat 1** — Claude Code PreToolUse hook denies the dangerous tool call before execution
2. **Beat 2** — Git pre-commit hook rejects the agent's commit on a protected path
3. **Beat 3** — Kubernetes ValidatingAdmissionPolicy denies the agent's direct API call at the API server

The agent dialogue is scripted. The enforcement is real. The cluster is a real Kubernetes 1.35 MLOps platform.

---

## The three layers

### Layer 1: PreToolUse hook
Real bash script at `demo/claude-hooks/pretool-use-block-prod.sh`. Reads tool-call JSON, exits 2 with stderr deny on dangerous patterns.

### Layer 2: Git pre-commit hook
Real `pre-commit` template at `demo/iac-repo-template/hooks/pre-commit`. Rejects non-human committer emails and protected paths. `setup.sh` sets `core.hooksPath` inside the hydrated repo to defeat any host global hooks dir.

### Layer 3: ValidatingAdmissionPolicy
Lives in `demo/gitops/manifests/vap/`. Now matches both Deployments AND `serving.kserve.io/v1beta1/inferenceservices`:

```yaml
matchConstraints:
  resourceRules:
    - apiGroups: ["apps", ""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE", "DELETE", "PATCH"]
      resources: ["deployments", "pods", "services", "configmaps"]
    - apiGroups: ["serving.kserve.io"]
      apiVersions: ["v1beta1"]
      operations: ["CREATE", "UPDATE", "DELETE", "PATCH"]
      resources: ["inferenceservices"]
```

So whether the agent tries `kubectl edit deployment` or `kubectl edit inferenceservice`, the same Forbidden response comes back. The gate is resource-type-agnostic.

---

## What v4.7 adds on top of v4.6

**Falcosidekick** routes Falco events into Prometheus metrics. Flipped via `falcosidekick.enabled=true` on the Falco helm chart.

**KServe (raw deployment mode)** as the production workload. The model-server is now a real `InferenceService` running sklearn iris, not nginx pretending. Annotation `serving.kserve.io/deploymentMode: RawDeployment` avoids Knative+Istio.

**Kubeflow Model Registry (standalone Hub component)** pre-loaded with the model versions v1.0.0 through v1.3.0. v1.2.0 is in production; v1.3.0 is the version the agent tries to promote.

**Loki + Promtail** completes the observability triad (metrics + traces + logs).

**Argo Workflows** is the "right path" verbal reference. A `WorkflowTemplate` named `promote-model-to-production` is pre-loaded — not executed, just shown during the wrap: "this is the path the agent should have used."

**VAP expanded** to match InferenceServices (see Layer 3 above).

---

## What's deliberately NOT included

- **Full Kubeflow** — 20+ components, too heavy. The standalone Model Registry alone gives the artifact-registry narrative.
- **Knative + Istio** — only needed for KServe Standard mode. Raw mode covers everything.
- **vLLM / GPU-backed LLM serving** — demo isn't about LLMs; sklearn iris is right-sized.
- **Pixie, Tempo, Feast, Backstage** — memory/time cost not justified by an 8-minute demo.
- **Cilium CNI swap** — EKS Auto Mode uses VPC CNI; swapping breaks the managed-networking story. Tetragon runs alongside VPC CNI just fine.

---

## Connection architecture (v4.4 carryover)

```
Audience ←─HDMI─ Laptop ──autossh→ netcup/sandbox VPS ──aws cli→ EKS (us-east-2)
                  thin client      tmux + repo + tools          K8s 1.35
```

Laptop is a thin client. Demo state lives on the server side. tmux session survives SSH disconnects; autossh handles wifi flap. AWS credentials live on the server, never the laptop.

---

## Tool versions

Pinned floors. Use latest patch within the line.

| Tool | Floor |
|---|---|
| Kubernetes (EKS) | 1.35 |
| eksctl | >= 0.225 |
| kubectl | >= 1.35 |
| Helm | >= 3.21 (or 4.x) |
| AWS CLI | v2 latest |
| Falco helm chart | 8.x with `falcosidekick.enabled=true` |
| Tetragon helm chart | v1.7.0+ |
| Kyverno | helm chart 3.7.x (Kyverno 1.17.x), `crds.install=true` |
| cert-manager | helm chart latest, `crds.enabled=true` |
| SPIRE | `spire-crds` chart + `spire` chart |
| KServe | `kserve-crd` chart + `kserve-resources` chart, RawDeployment mode |
| Argo Workflows | v3.6.x, `crds.install=true` |
| Kubeflow Model Registry | standalone manifests (no helm chart at the time of writing) |
| Loki | grafana/loki chart (single-binary deployment mode) |
| OpenTelemetry Collector | open-telemetry/opentelemetry-collector chart |
| kube-prometheus-stack | latest |
| Jaeger | jaegertracing/jaeger chart, all-in-one in-memory |
| ArgoCD | argo/argo-cd chart, v8.x |
| Bottlerocket OS | AWS-managed |

---

## Repo layout

```
LLMday-Texas-2026/
├── docs/
│   └── SPEC.md                              # this file (v4.7)
├── presentations/
│   └── llmday-austin-2026-mlops-pipeline-guardrail-v06.pptx
└── demo/
    ├── README.md
    ├── provision-cluster.sh                  # cluster + ArgoCD only
    ├── setup.sh                              # waits for sync, then sets up demo state
    ├── reset.sh                              # between-runs reset
    ├── teardown.sh                           # eksctl delete cluster
    ├── demo.sh                               # the runner
    ├── demo-runbook.md
    ├── .gitignore
    ├── lib/                                  # say, pause, colors (unchanged)
    ├── dialogue/                             # beats 1/2/3 (paths via $DEMO_LOCAL)
    ├── claude-hooks/                         # PreToolUse hook + settings
    ├── iac-repo-template/                    # template for Beat 2's git repo
    ├── gitops/
    │   ├── bootstrap/
    │   │   └── root-app.yaml                 # the seed Application
    │   ├── apps/                             # ~21 Applications with sync waves
    │   ├── values/                           # Helm values per component
    │   └── manifests/
    │       ├── namespaces/
    │       ├── kyverno-policies/             # 6 baseline ClusterPolicies
    │       ├── tracing-policies/             # 3 Tetragon TracingPolicies
    │       ├── cert-issuers/
    │       ├── vap/                          # VAP + Binding + ResourceQuotas
    │       ├── rbac/                         # agent SA + Role + RoleBinding
    │       ├── workloads/                    # KServe InferenceService + WorkflowTemplate
    │       └── model-registry/               # pre-loaded model versions
    └── .local/                                # GITIGNORED runtime artifacts
        ├── kubeconfig
        ├── operator-kubeconfig
        ├── agent-token
        ├── cluster-info.json
        └── iac-repo/
```

---

## Acceptance criteria

### Provisioning verification
- [ ] `provision-cluster.sh` completes; cluster ACTIVE; ArgoCD bootstrapped; root-app applied
- [ ] All ArgoCD Applications reach `Healthy` + `Synced` (within 15 min budget enforced by `setup.sh`)

### Setup verification
- [ ] `.local/kubeconfig` valid; `.local/agent-token` TTL > 55 min
- [ ] `.local/iac-repo/.git/hooks/pre-commit` exists and is executable
- [ ] `production` namespace has `model-server` InferenceService (KServe) backing pods Ready
- [ ] VAP `deny-agent-writes-to-production` applied and bound

### Layer enforcement
- [ ] Layer 1: hook denies kubectl-vs-prod fixture, exit 2, `PRETOOLUSE_HOOK_DENY` in stderr
- [ ] Layer 2: non-human committer + protected path commit fails with `GIT_HOOK_DENY`
- [ ] Layer 3 (Deployment): `kubectl apply` of a Deployment to `production` returns Forbidden within 2s
- [ ] Layer 3 (InferenceService): `kubectl apply` of an InferenceService to `production` returns Forbidden within 2s
- [ ] CloudWatch audit log contains the matching deny entries within 60s

### Demo runner
- [ ] `bash demo.sh --dry-run` plays all three beats cleanly
- [ ] `bash demo.sh` runs end-to-end with SPACE at each pause (7-9 min total)

### Backup video
- [ ] Recorded after acceptance, USB-tested on the laptop that's going on stage

---

## Cost model

| Item | Hourly | 24-hour lifetime |
|---|---|---|
| EKS control plane | $0.10 | $2.40 |
| 2× t3.large managed node group | $0.17 | $4.00 |
| Auto Mode burst | $0-1 | $0-2 |
| CloudWatch + EBS | minimal | <$3 |
| **Total** | | **~$14-17** |

Tear down within 24 hours and billing stops.

---

## Risk register (highlights)

| Risk | Mitigation |
|---|---|
| Wifi flap | autossh + tmux; pause typing during reconnect window |
| Wifi down | backup video on USB |
| Laptop fails | SSH from phone/borrowed laptop to the tmux session on the VPS |
| Server outage | backup video |
| ArgoCD app stuck OutOfSync | `setup.sh` waits 15 min and fails loud; most failures self-resolve on retry; `ServerSideApply=true` guards Kyverno CRD size |
| Platform component fails to start | Not on demo's critical path — narrate around it |
| AWS creds expire | use long-lived creds on the VPS, not 1-hour SSO |

---

## Closing principle

The agent dialogue is scripted. The enforcement is real. **The cluster is real.** Real EKS, real Bottlerocket nodes, real Kubernetes 1.35, real GitOps via ArgoCD, real KServe InferenceService backed by a Model Registry, real VAP, real Kyverno policies, real Tetragon eBPF, real Falco runtime detection — and three deterministic gates enforcing what an AI agent can do across all of it.

*Don't use probabilistic AI to enforce deterministic requirements. Build the gates programmatically, test them the same way you test your code, and let the agent run.*
