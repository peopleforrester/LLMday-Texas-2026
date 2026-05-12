# LLMday Austin Live Demo Build Spec — v4.8

**Talk:** Your MLOps Pipeline is your Agentic AI Guardrail
**Date:** Tue May 12, 2026
**Venue:** The Sunset Room, Austin
**Speaker:** Michael Forrester
**Demo block:** ~11 minutes, mid-talk, five live beats (with a sixth on slide)
**Spec version:** v4.8 — adds Beat 4 (Falco custom rule + Falco Talon response) and Beat 5 (EKS Auto Mode NetworkPolicy egress allowlist), and reconciles what actually shipped vs. the v4.7 intent (KServe and SPIRE were dropped from the build; model-server is a plain Deployment running nginx)

---

## Cluster topology — EKS Auto Mode, K8s 1.35

- Cluster: `llmday-demo`, region `us-east-2`, version `1.35`
- Compute: pure EKS Auto Mode. Karpenter provisions `c6a.large` instances (4 GiB each) from two NodePools: `general-purpose` (untainted, runs everything) and `system` (tainted `CriticalAddonsOnly`, runs AWS-managed add-ons). The cluster currently runs 2-3 nodes at steady state; Karpenter scales up as memory requests demand.
- Bootstrap: procedural `provision-cluster.sh` creates the cluster, installs ArgoCD only, applies the root Application. Everything else flows from GitOps reconciliation.

Memory budget (approximate steady state across the `general-purpose` node pool):

| Component | Memory limit |
|---|---|
| ArgoCD application-controller | 8 GiB |
| ArgoCD server / repo-server / applicationset-controller | 1-8 GiB each |
| Kyverno admission + cleanup + background + reports controllers | 0.5-8 GiB each |
| Falco DaemonSet + Falcosidekick | ~700 MiB total |
| Falco Talon (response engine, runs on the `system` node via toleration) | ~256 MiB |
| Tetragon DaemonSet | ~400 MiB |
| kube-prometheus-stack | ~1.5 GiB |
| Loki + Promtail | ~700 MiB |
| Jaeger all-in-one | 256 MiB |
| OTel Collector | 256 MiB |
| cert-manager | 256 MiB |
| Argo Workflows controller + server | ~256 MiB |
| Kubeflow Model Registry | ~256 MiB |
| model-server Deployment (3× `nginxinc/nginx-unprivileged:1.27-alpine`) | ~256 MiB |
| EKS Auto Mode add-ons + system overhead | ~1.5 GiB |

The 11-minute demo flow uses the same five live beats listed in "The narrative" below. The expanded MLOps surface (Argo Workflows, Model Registry, Loki) is background credibility — the audience sees it in `kubectl get pods -A` and the ArgoCD app list.

---

## GitOps bootstrap

Procedural phase installs ArgoCD only. The root Application reconciles everything else from `demo/gitops/apps/`, ordered by sync waves. Nineteen Applications, the actual wave assignments from the committed Application manifests:

| Wave | Apps |
|---|---|
| -10 | namespaces (with PSS labels), cluster-config (the `amazon-vpc-cni` enable-network-policy-controller ConfigMap) |
| -4 | cert-manager (installCRDs), kyverno (installCRDs) |
| -3 | kyverno-policies, rbac |
| -2 | falco (with falcosidekick + customRules), tetragon |
| -1 | falco-talon (response engine for Falco events), cert-issuers |
|  0 | admission (VAP + binding), network-policies (production egress allowlist) |
|  1 | loki, kube-prometheus-stack |
|  2 | argo-workflows, otel |
|  3 | jaeger, kubeflow-model-registry |
|  4 | model-server (plain Deployment + WorkflowTemplate) |

`ServerSideApply=true` in syncOptions is mandatory (Kyverno CRDs exceed 256 KB).

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
Lives in `demo/gitops/manifests/vap/`. Matches Deployments / pods / services / configmaps in `apps` and the core API group, plus `serving.kserve.io/v1beta1/inferenceservices` (kept for design generality even though KServe isn't installed in this build):

```yaml
matchConstraints:
  resourceRules:
    - apiGroups: ["apps", ""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE", "DELETE"]
      resources: ["deployments", "pods", "services", "configmaps"]
    - apiGroups: ["serving.kserve.io"]
      apiVersions: ["v1beta1"]
      operations: ["CREATE", "UPDATE", "DELETE"]
      resources: ["inferenceservices"]
```

So whether the agent tries `kubectl edit deployment` or (in a future build with KServe re-added) `kubectl edit inferenceservice`, the same Forbidden response comes back. `PATCH` was deliberately excluded — Kubernetes 1.35's VAP implementation rejects `PATCH` in the operations array; `UPDATE` covers the same surface for our purposes. `matchConditions` narrow further to (a) writes to `production`, (b) the `claude-agent` ServiceAccount specifically (so built-in controllers like the kube-system ReplicaSet controller are not caught).

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

## What v4.7 added on top of v4.6 (intent; some pieces dropped — see "What's deliberately NOT included")

**Falcosidekick** routes Falco events into Prometheus metrics and (in v4.8) on to Falco Talon. Flipped via `falcosidekick.enabled=true` on the Falco helm chart.

**Kubeflow Model Registry (standalone Hub component)** pre-loaded with the model versions v1.0.0 through v1.3.0. v1.2.0 is in production; v1.3.0 is the version the agent tries to promote.

**Loki + Promtail** completes the observability triad (metrics + traces + logs).

**Argo Workflows** is the "right path" verbal reference. A `WorkflowTemplate` named `promote-model-to-production` is pre-loaded, not executed, just shown during the wrap: "this is the path the agent should have used."

**VAP CEL** is resource-type-agnostic on purpose: it would also match `serving.kserve.io/v1beta1/inferenceservices` if KServe were installed. KServe ended up being dropped (see below); the VAP CEL stays general so re-adding KServe later is a one-line catalog change.

---

## What v4.8 adds on top of v4.7

**Falco custom rules + Falco Talon response (Beat 4).** Falco runs as a DaemonSet on every node, with a tight custom rule mounted via the chart's `customRules` value. Falcosidekick is wired to forward events to Talon. Talon binds the Falco rule names to `kubernetes:terminate`. Together they form a runtime detection-and-response loop that catches `kubectl exec` into production pods within seconds; the ReplicaSet self-heals.

**EKS Auto Mode NetworkPolicy enforcement (Beat 5).** A ConfigMap (`amazon-vpc-cni` in `kube-system`, key `enable-network-policy-controller: "true"`) turns on the embedded Auto Mode Network Policy Controller. A standard `networking.k8s.io/v1 NetworkPolicy` on the production namespace default-denies egress and allows only DNS plus intra-namespace plus model-registry traffic. PolicyEndpoints generate automatically once the ConfigMap is in place.

**Three demo runners.** `demo.sh` (scripted dialogue across all five live beats, hands-free SPACE advance), `demo-claude.sh` (live Claude Code CLI agent, hands the same scenario to a real agent for rehearsal and recording), `demo-settings.sh` (file-walk through every enforcement file with syntax highlighting). The same `lib/` primitives back all three.

---

## What's deliberately NOT included (and what was dropped)

- **KServe** — was the v4.7 intent (InferenceService running sklearn iris). Dropped from the GitOps tree: KServe's Helm chart isn't published at a stable URL, raw manifests weren't justified for an 11-minute demo, and the narrative isn't materially affected because the agent's attack surface is "modify a Deployment in production", which a plain Deployment satisfies. The model-server is now `nginxinc/nginx-unprivileged:1.27-alpine` × 3 replicas. The decision is documented inline in `demo/gitops/manifests/workloads/model-server.yaml`.
- **SPIRE server + agent** — was the v4.7 intent (in-cluster identity-of-record). Dropped because the talk's identity story is satisfied by the agent's Kubernetes ServiceAccount projected token; SPIFFE IDs weren't load-bearing for any beat.
- **Full Kubeflow** — 20+ components, too heavy. The standalone Model Registry alone carries the artifact-registry narrative.
- **Knative + Istio** — were prereqs for KServe Standard mode. Both irrelevant now that KServe was dropped.
- **vLLM / GPU-backed LLM serving** — demo isn't about LLMs; the model-server is a stand-in for "any workload in production" that the agent might attack.
- **Pixie, Tempo, Feast, Backstage** — memory/time cost not justified by an 11-minute demo.
- **Cilium CNI swap** — EKS Auto Mode uses its own embedded CNI; swapping breaks the managed-networking story. Tetragon runs alongside the Auto Mode CNI fine. NetworkPolicy enforcement is provided by the Auto Mode controller (Beat 5).

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
| Falco helm chart | 8.x with `falcosidekick.enabled=true`, `customRules` populated, `falcosidekick.config.talon.address` pointed at the falco-talon service |
| Falco Talon helm chart | 0.4.x (app v0.3.x), with `config.rulesOverride` binding Falco rule names to `kubernetes:terminate` |
| Tetragon helm chart | v1.7.0+ |
| Kyverno | helm chart 3.8.x (Kyverno 1.18.x), `crds.install=true` |
| cert-manager | helm chart latest, `crds.enabled=true` |
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
    │       ├── workloads/                    # model-server Deployment (plain nginx) + WorkflowTemplate
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
- [ ] `.local/kubeconfig` valid; `.local/agent-token` TTL covers the talk window
- [ ] `.local/iac-repo/.git/hooks/pre-commit` exists and is executable
- [ ] `production` namespace has the `model-server` Deployment running 3/3 replicas (nginx-unprivileged)
- [ ] VAP `deny-agent-writes-to-production` applied and bound; agent RBAC includes `pods/exec` (over-scoped on purpose for Beat 4)

### Beat enforcement
- [ ] Beat 1: hook denies kubectl-vs-prod fixture, exit 2, `PRETOOLUSE_HOOK_DENY` in stderr
- [ ] Beat 2: non-human committer + protected path commit fails with `GIT_HOOK_DENY`
- [ ] Beat 3 (Deployment): `kubectl apply` of a Deployment to `production` returns Forbidden within 2s
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
| EKS Auto Mode (2-3× c6a.large, on-demand) | $0.16-0.25 | $4-6 |
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

The agent dialogue is scripted. The enforcement is real. **The cluster is real.** Real EKS Auto Mode, real Bottlerocket nodes, real Kubernetes 1.35, real GitOps via ArgoCD, a real Deployment in production whose state the agent tries to mutate, real Kyverno policies in audit mode alongside a real native VAP doing the deny, real Tetragon eBPF, real Falco runtime detection with Falco Talon doing the kill, real NetworkPolicy on production dropping unauthorized egress. Five deterministic gates enforcing what an AI agent can do across all of it.

*Don't use probabilistic AI to enforce deterministic requirements. Build the gates programmatically, test them the same way you test your code, and let the agent run.*
