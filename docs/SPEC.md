# LLMday Austin Live Demo Build Spec — v4.8

**Talk:** Your MLOps Pipeline is your Agentic AI Guardrail
**Date:** Tue May 12, 2026
**Venue:** The Sunset Room, Austin
**Speaker:** Michael Forrester
**Demo block:** ~11 minutes, mid-talk, five live beats (with a sixth on slide)
**Spec version:** v4.8 — adds Beat 4 (Falco custom rule + Falco Talon response) and Beat 5 (EKS Auto Mode NetworkPolicy egress allowlist) on top of v4.7's KServe / Model Registry / Argo Workflows MLOps surface

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

## The narrative

ML engineer asks the agent to ship model v1.3.0 to production. Five gates catch it live; a sixth is shown on slide for the output / content layer.

1. **Beat 1 (in-agent)** — Claude Code PreToolUse hook denies the dangerous tool call before execution
2. **Beat 2 (client-side)** — Git pre-commit hook rejects the agent's commit on a protected path
3. **Beat 3 (server-side · admission)** — Kubernetes ValidatingAdmissionPolicy denies the agent's direct API call at the API server
4. **Beat 4 (server-side · runtime)** — Custom Falco rule fires on `kubectl exec` into a production pod; Falco Talon terminates the pod via `kubernetes:terminate`; the ReplicaSet self-heals
5. **Beat 5 (server-side · network)** — NetworkPolicy egress allowlist drops outbound traffic to an unauthorized destination; runtime does not fire, the pod stays alive, the destination is the gate
6. **Beat 6 (output, on slide)** — LLM Guard / NeMo Guardrails / Envoy AI Gateway catches what the model says, not what the agent does. Not run live; referenced on the closing slide.

The agent dialogue is scripted. The enforcement is real. The cluster is a real Kubernetes 1.35 MLOps platform.

---

## The five live beats

### Beat 1: PreToolUse hook (in-agent)
Real bash script at `demo/claude-hooks/pretool-use-block-prod.sh`. Reads tool-call JSON, exits 2 with stderr deny on dangerous patterns.

### Beat 2: Git pre-commit hook (client-side)
Real `pre-commit` template at `demo/iac-repo-template/hooks/pre-commit`. Rejects non-human committer emails and protected paths. `setup.sh` sets `core.hooksPath` inside the hydrated repo to defeat any host global hooks dir.

### Beat 3: ValidatingAdmissionPolicy (server-side · admission)
Lives in `demo/gitops/manifests/vap/`. Matches both Deployments AND `serving.kserve.io/v1beta1/inferenceservices`:

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

### Beat 4: Falco custom rule + Falco Talon (server-side · runtime)
Falco is installed via `gitops/values/falco-values.yaml`. The chart's `customRules` value mounts an `llmday-rules.yaml` file into every Falco pod at `/etc/falco/rules.d/`. Two rules in that file:

- `Agent exec in production` — fires when a shell binary (`sh`, `bash`, `ksh`, `zsh`, `dash`, `ash`) spawns inside a pod in the `production` namespace with `containerd-shim` as its parent. That's the syscall signature of a `kubectl exec`.
- `Read sensitive file in production` — backup trigger; fires on reads of `/etc/shadow`, `/etc/sudoers`, or `/etc/sudoers.d/*` from a production pod.

Falco Talon is installed via `gitops/values/falco-talon-values.yaml`. The chart's `config.rulesOverride` value defines an action (`kubernetes:terminate`, grace 5 seconds) and bindings that map the Falco rule names above to that action. Falcosidekick is wired to forward events to Talon via the `talon.address` config on the Falco chart (`http://falco-talon:2803`).

The flow on stage: agent runs `kubectl exec POD -- /bin/sh -c "..."`, Falco emits the event, falcosidekick `POST`s to Talon, Talon calls the K8s API to delete the pod, the ReplicaSet replaces it within seconds. No admission webhook involved — the Deployment never changed.

### Beat 5: NetworkPolicy egress allowlist (server-side · network)
Two pieces:

- `gitops/manifests/cluster-config/vpc-cni-network-policy.yaml` — a ConfigMap in `kube-system` (`amazon-vpc-cni`) with `enable-network-policy-controller: "true"`. This is the EKS Auto Mode knob that turns on NetworkPolicy enforcement. Without it, NetworkPolicy resources are accepted but generate zero PolicyEndpoints and no packet filtering.
- `gitops/manifests/networkpolicies/netpol.yaml` — a standard `networking.k8s.io/v1 NetworkPolicy` on the production namespace. Default-deny egress. Allow rules: DNS (UDP+TCP/53 to the cluster service CIDR via `ipBlock` — EKS Auto Mode runs DNS on the node OS, not as a kube-system pod, so the `namespaceSelector: kube-system` idiom does NOT match here), intra-namespace production traffic, and the `kubeflow` (model registry) namespace.

The flow on stage: agent runs `wget https://huggingface.co/...` from inside a production pod. DNS resolves (allowed). TCP SYN dropped (huggingface.co IP isn't on the allowlist). wget times out. Falco does not fire, Talon does not run, the pod stays alive. The destination was the only thing the policy cared about.

---

## What v4.7 added on top of v4.6

**Falcosidekick** routes Falco events into Prometheus metrics. Flipped via `falcosidekick.enabled=true` on the Falco helm chart.

**KServe (raw deployment mode)** as the production workload. The model-server is now a real `InferenceService` running sklearn iris, not nginx pretending. Annotation `serving.kserve.io/deploymentMode: RawDeployment` avoids Knative+Istio.

**Kubeflow Model Registry (standalone Hub component)** pre-loaded with the model versions v1.0.0 through v1.3.0. v1.2.0 is in production; v1.3.0 is the version the agent tries to promote.

**Loki + Promtail** completes the observability triad (metrics + traces + logs).

**Argo Workflows** is the "right path" verbal reference. A `WorkflowTemplate` named `promote-model-to-production` is pre-loaded — not executed, just shown during the wrap: "this is the path the agent should have used."

**VAP expanded** to match InferenceServices (see Beat 3 above).

---

## What v4.8 adds on top of v4.7

**Falco custom rules + Falco Talon response (Beat 4).** Falco runs as a DaemonSet on every node, with a tight custom rule mounted via the chart's `customRules` value. Falcosidekick is wired to forward events to Talon. Talon binds the Falco rule names to `kubernetes:terminate`. Together they form a runtime detection-and-response loop that catches `kubectl exec` into production pods within seconds; the ReplicaSet self-heals.

**EKS Auto Mode NetworkPolicy enforcement (Beat 5).** A ConfigMap (`amazon-vpc-cni` in `kube-system`, key `enable-network-policy-controller: "true"`) turns on the embedded Auto Mode Network Policy Controller. A standard `networking.k8s.io/v1 NetworkPolicy` on the production namespace default-denies egress and allows only DNS plus intra-namespace plus model-registry traffic. PolicyEndpoints generate automatically once the ConfigMap is in place.

**Three demo runners.** `demo.sh` (scripted dialogue across all five live beats, hands-free SPACE advance), `demo-claude.sh` (live Claude Code CLI agent, hands the same scenario to a real agent for rehearsal and recording), `demo-settings.sh` (file-walk through every enforcement file with syntax highlighting). The same `lib/` primitives back all three.

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
│   ├── SPEC.md                              # this file (v4.8)
│   └── outline.md                           # as-delivered slide outline (v19 deck)
├── presentations/
│   └── llmday-austin-2026-deck-v19.pptx     # 16 slides, six-demo arc (five live)
└── demo/
    ├── README.md                             # student-facing demo walkthrough
    ├── provision-cluster.sh                  # cluster + ArgoCD only
    ├── setup.sh                              # waits for sync, then sets up demo state
    ├── reset.sh                              # between-runs reset
    ├── teardown.sh                           # eksctl delete cluster
    ├── demo.sh                               # primary runner: scripted dialogue, five live beats
    ├── demo-claude.sh                        # live Claude Code CLI agent variant
    ├── demo-settings.sh                      # file-walk variant
    ├── demo-runbook.md                       # speaker runbook
    ├── .gitignore
    ├── lib/                                  # say, pause, colors, memes (shared primitives)
    ├── dialogue/                             # scripted text for beats 1-5
    ├── claude-hooks/                         # Beat 1: PreToolUse hook + settings
    ├── iac-repo-template/                    # Beat 2: template for the git repo
    ├── gitops/
    │   ├── bootstrap/
    │   │   └── root-app.yaml                 # the seed Application
    │   ├── apps/                             # Applications with sync waves
    │   ├── values/                           # Helm values per component
    │   │   ├── falco-values.yaml             # Beat 4: customRules llmday-rules.yaml
    │   │   └── falco-talon-values.yaml       # Beat 4: rulesOverride bindings
    │   └── manifests/
    │       ├── namespaces/
    │       ├── kyverno-policies/             # 6 baseline ClusterPolicies
    │       ├── tracing-policies/             # 3 Tetragon TracingPolicies
    │       ├── cert-issuers/
    │       ├── vap/                          # Beat 3: VAP + Binding
    │       ├── cluster-config/               # Beat 5: vpc-cni-network-policy.yaml
    │       ├── networkpolicies/              # Beat 5: production egress allowlist
    │       ├── rbac/                         # agent SA + Role + RoleBinding (incl. pods/exec)
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

### Beat enforcement
- [ ] Beat 1: hook denies kubectl-vs-prod fixture, exit 2, `PRETOOLUSE_HOOK_DENY` in stderr
- [ ] Beat 2: non-human committer + protected path commit fails with `GIT_HOOK_DENY`
- [ ] Beat 3 (Deployment): `kubectl apply` of a Deployment to `production` returns Forbidden within 2s
- [ ] Beat 3 (InferenceService): `kubectl apply` of an InferenceService to `production` returns Forbidden within 2s
- [ ] CloudWatch audit log contains the matching deny entries within 60s
- [ ] Beat 4: Falco DaemonSet has `/etc/falco/rules.d/llmday-rules.yaml` mounted on every pod
- [ ] Beat 4: Talon log shows `2 rule(s) has/have been successfully loaded` (or 4 with backup bindings)
- [ ] Beat 4: `kubectl exec POD -- /bin/sh -c "id"` against a production model-server pod triggers a Talon `kubernetes:terminate` within ~5 seconds; ReplicaSet replaces the pod
- [ ] Beat 5: `kubectl -n kube-system get cm amazon-vpc-cni -o jsonpath='{.data.enable-network-policy-controller}'` returns `true`
- [ ] Beat 5: `kubectl -n production get policyendpoints` shows at least one
- [ ] Beat 5: `wget https://huggingface.co/api/models` from a production pod times out at ~6s while DNS resolves and intra-namespace traffic to a peer pod succeeds

### Demo runner
- [ ] `bash demo.sh --dry-run` plays all five live beats cleanly
- [ ] `bash demo.sh` runs end-to-end with SPACE at each pause (10-12 min total for Beats 1-5)
- [ ] `bash demo-settings.sh` walks all enforcement files without errors
- [ ] `bash demo-claude.sh` rehearsal run completes; live agent exercises Beats 1-5 and prints a summary

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
