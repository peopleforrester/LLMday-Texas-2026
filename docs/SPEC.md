# LLMday Austin Live Demo Build Spec — v4.2

**Talk:** Your MLOps Pipeline is your Agentic AI Guardrail
**Date:** Tue May 12, 2026
**Venue:** The Sunset Room, Austin
**Speaker:** Michael Forrester
**Demo block:** ~8 minutes, mid-talk, three beats
**Spec version:** v4.2 — runs on real EKS Auto Mode (was k3d in v4.1)

---

## What changed v4.1 → v4.2

The demo target moves from k3d to **Amazon EKS Auto Mode**. Same three layers, same scripted dialogue, same hybrid pacing, same acceptance criteria. The cluster is real production-grade infrastructure that the audience runs in their own environments.

**Why the change matters for the talk:**

LLMday's audience is ML engineers, data engineers, and engineering managers evaluating AI agent adoption. Most of them run EKS, GKE, or AKS in production. When the demo runs on k3d, they have to translate "would this work on EKS?" in their heads. When it runs on real EKS, that translation is done. The credibility upgrade is real.

| | v4.1 (k3d) | v4.2 (EKS Auto Mode) |
|---|---|---|
| Cluster platform | k3d local | Amazon EKS, Auto Mode enabled |
| Kubernetes version | v1.35.4 | v1.33 (EKS current default) |
| Compute | local Docker containers | EC2 instances managed by Auto Mode (Karpenter under the hood) |
| Node OS | k3s default | Bottlerocket (AWS-managed) |
| Cluster bootstrap | `k3d cluster create` (~90 sec) | `eksctl create cluster --enable-auto-mode` (~12-15 min) |
| Bootstrap timing | tonight or morning of | **tonight, pre-provisioned** |
| Demo-time setup | runs `setup.sh`, builds everything | runs `setup.sh`, applies to existing cluster (~30 sec) |
| Audit log destination | local file | CloudWatch Logs |
| Add-ons | manual install (Falco, OTel) | Falco + OTel Helm install on existing cluster |
| Backup if AWS unreachable | n/a | backup video (mandatory) |
| Estimated demo cost | $0 | ~$3-5 total (cluster ~24 hr lifetime) |

**Audience credibility line for the talk:**
> "What you're watching is a real EKS Auto Mode cluster running Kubernetes 1.33. Same ValidatingAdmissionPolicy you'd configure in production. The agent is hitting the same admission webhook your cluster uses today."

That line lands harder than "this is a local k3d cluster."

---

## Prerequisites (Michael's laptop and AWS account)

Before tonight's pre-provisioning:

- AWS CLI v2 configured with credentials that can create EKS clusters
- `aws sts get-caller-identity` returns a valid identity
- AWS region: `us-east-2` (Ohio — close to Austin, cheap, broadly supported)
- `eksctl >= 0.225` installed (`eksctl version`)
- `kubectl >= 1.33` installed
- `helm >= 3.18` installed (for Falco and OTel)
- `git`, `bash`, `awk`, `jq`, `aws-vault` or `aws sso` for credential handling
- AWS account quotas: at least 4 vCPUs available in the chosen region, EKS cluster quota not at limit

**One-time IAM setup (do this once for your AWS account):**

The IAM user/role you use must have, at minimum:
- `AmazonEKSClusterAdminPolicy` (or equivalent custom policy)
- IAM permissions to create roles and policies for EKS Auto Mode (Auto Mode creates a node role, cluster role, and Pod Identity associations)
- `iam:CreateOpenIDConnectProvider`, `iam:CreateRole`, `iam:AttachRolePolicy`

The `eksctl create cluster --enable-auto-mode` command handles the boilerplate IAM setup automatically; you just need the permission to create those resources.

---

## Repo positioning

Demo lives in `github.com/peopleforrester/LLMday-Texas-2026` at `demo/`, alongside the slides and the spec. The Eight Guardrails Framework stays separate at `github.com/peopleforrester/agentic-covenants`.

```
LLMday-Texas-2026/
├── README.md
├── presentations/
│   └── llmday-austin-2026-mlops-pipeline-guardrail-v06.pptx
├── docs/
│   ├── SPEC.md                              # this file
│   └── outline.md
└── demo/                                    # THE DEMO
    ├── README.md
    ├── provision-cluster.sh                  # heavy lift, run once tonight on Megumi
    ├── setup.sh                              # fast, applies to existing cluster
    ├── reset.sh                              # between-runs reset
    ├── teardown.sh                           # deletes EKS cluster (~10 min)
    ├── demo.sh                               # the runner Michael executes on stage
    ├── demo-runbook.md
    ├── .gitignore
    ├── lib/
    ├── dialogue/                             # paths use $DEMO_LOCAL
    ├── claude-hooks/
    ├── iac-repo-template/
    ├── manifests/
    │   ├── 00-namespaces.yaml
    │   ├── 10-quota.yaml
    │   ├── 20-rbac.yaml
    │   ├── 30-workloads.yaml
    │   ├── 40-vap-production-guard.yaml      # VAP is native K8s, unchanged shape
    │   └── observability/
    │       ├── falco-values.yaml             # Helm values for Falco install
    │       └── otel-values.yaml              # Helm values for OTel collector
    └── .local/                               # GITIGNORED — runtime artifacts
        ├── kubeconfig                        # agent's kubeconfig (K8s SA JWT, not AWS creds)
        ├── operator-kubeconfig               # Michael's kubeconfig (uses AWS creds via aws eks get-token)
        ├── agent-token
        ├── audit-stream.log                  # tail of CloudWatch audit log (optional)
        ├── cluster-info.json                 # ARN, endpoint, region, etc.
        └── iac-repo/                         # hydrated copy of iac-repo-template
```

---

## The narrative (unchanged from v4.1)

ML engineer asks the agent to ship model v1.3.0 to production. Three layers catch it:

1. **Beat 1** — Claude Code PreToolUse hook denies the dangerous tool call before execution
2. **Beat 2** — Git pre-commit hook rejects the agent's commit on a protected path
3. **Beat 3** — Kubernetes ValidatingAdmissionPolicy denies the agent's direct API call at the API server

The agent dialogue is scripted. The enforcement is real. Now also: the cluster is real.

---

## Cluster topology — EKS Auto Mode v1.33

**Cluster name:** `llmday-demo`
**Region:** `us-east-2`
**Kubernetes version:** `1.33`
**Mode:** Auto Mode enabled (Karpenter, ALB controller, EBS CSI, EFS CSI, VPC CNI all managed by AWS)

**Provisioning via eksctl** (`provision-cluster.sh`):

```bash
eksctl create cluster \
  --name llmday-demo \
  --region us-east-2 \
  --version 1.33 \
  --enable-auto-mode \
  --with-oidc \
  --tags "Project=llmday-austin,Owner=mforrester,Ephemeral=true"
```

Auto Mode provisions everything: control plane, default node pool (Karpenter-based), the AWS-managed add-ons. Takes 12-15 minutes. Run it tonight.

**Why Auto Mode for this demo (and most production new clusters in May 2026):**

- AWS manages Karpenter, AWS Load Balancer Controller, EBS/EFS CSI drivers, VPC CNI — fewer moving parts to break during the demo
- Bottlerocket OS on nodes — AWS handles OS patching
- Pod-driven scaling without manual node group config — workloads provision the compute they need
- Built-in security defaults — IAM roles configured for least privilege out of the box
- Maximum node runtime 21 days with automatic replacement
- Supports DaemonSets (we need this for Falco), unlike Fargate

**What we add on top** (`setup.sh`):

- Two namespaces: `production`, `staging` (both with Pod Security Standards `restricted`)
- `model-server` Deployment in production (3 replicas, digest-pinned image, full pod hardening)
- ResourceQuota on `staging`
- Agent ServiceAccount in `staging` with scoped Role
- The ValidatingAdmissionPolicy (Layer 3)
- CloudWatch Logs streaming for the API server audit log

Falco and OTel are installed by `provision-cluster.sh` so the runtime detection and metrics layer is already in place before the talk.

---

## Agent identity

**Demo agent identity is a Kubernetes ServiceAccount, NOT AWS Pod Identity.**

Reason: the demo's agent runs externally (Claude Code on Michael's laptop) and calls kubectl against the EKS API server. It does not run as a pod inside the cluster. So the agent's identity is a `kubectl --kubeconfig` token, which is a K8s SA token, not an AWS credential.

Pod Identity is the May 2026 right answer for **in-cluster workloads** that need AWS API access. We mention it verbally:

> "If this agent were running INSIDE the cluster as a pod, it would use EKS Pod Identity to talk to AWS services. Pod Identity is the 2026 default — better than IRSA, simpler, granular per-pod. The principle is the same: deterministic credentials, scoped, no long-lived secrets. For this demo the agent is external, so we use a scoped Kubernetes ServiceAccount token instead."

That sentence ties the cloud-native identity story to the same "scoped, deterministic" principle as the rest of the talk.

**ServiceAccount + scoped Role + 1h projected token:** generated by `setup.sh` via `kubectl create token claude-agent --namespace staging --duration 1h`, written to `$DEMO_LOCAL/agent-token`, embedded in `$DEMO_LOCAL/kubeconfig` for `demo.sh` to use.

---

## The three layers — what changes on EKS vs k3d

### Layer 1: PreToolUse hook — UNCHANGED

Same bash script. Reads tool-call JSON from stdin, exits 2 with stderr deny. Lives in the repo at `claude-hooks/pretool-use-block-prod.sh`. No EKS dependency at all.

### Layer 2: Git pre-commit hook — UNCHANGED

Same template script. Same `.local/iac-repo/` hydration pattern. Same enforcement. No EKS dependency.

### Layer 3: ValidatingAdmissionPolicy — RUNS ON EKS

VAP is native Kubernetes (GA since 1.30). Identical concept works on EKS:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deny-agent-writes-to-production
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups:   ["apps", ""]
        apiVersions: ["v1"]
        operations:  ["CREATE", "UPDATE", "DELETE", "PATCH"]
        resources:   ["deployments", "pods", "services", "configmaps"]
  matchConditions:
    - name: only-production-namespace
      expression: "request.namespace == 'production'"
  validations:
    - expression: >-
        !request.userInfo.username.startsWith('system:serviceaccount:')
        || request.userInfo.username.startsWith('system:serviceaccount:argocd:')
        || request.userInfo.username.startsWith('system:serviceaccount:mlops-pipeline:')
      message: "Production namespace writes are restricted to ArgoCD and the MLOps pipeline service accounts. Agent ServiceAccount principals must route through one of those."
      reason: Forbidden
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: deny-agent-writes-to-production-binding
spec:
  policyName: deny-agent-writes-to-production
  validationActions: [Deny, Audit]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: production
```

**The audience credibility moment:** when the deny message appears in the terminal, Michael says: *"That deny came from the EKS API server. Same admission webhook your production cluster runs."*

---

## Observability — runs on EKS the same way

**API server audit log:** EKS exports audit logs to CloudWatch Logs. Enabled in `provision-cluster.sh` via `aws eks update-cluster-config --logging ...`. No K8s-side audit-policy.yaml is needed (the audit policy is managed server-side by AWS).

The bottom-right tmux pane during the demo tails CloudWatch:
```bash
aws logs tail /aws/eks/llmday-demo/cluster --follow --filter-pattern 'deny' --region us-east-2
```

When the VAP fires in Beat 3, this pane shows the audit annotation appearing in CloudWatch in near real-time. *"That deny is in your SIEM in 30 seconds. Same path as everything else your cluster logs."*

**Falco DaemonSet:** Installed by `provision-cluster.sh` via Helm:
```bash
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  -f manifests/observability/falco-values.yaml
```

**OTel collector:** Installed by `provision-cluster.sh` via Helm:
```bash
helm upgrade --install otel open-telemetry/opentelemetry-collector \
  --namespace otel --create-namespace \
  -f manifests/observability/otel-values.yaml
```

---

## Scripts — what changes

### provision-cluster.sh (NEW — run once tonight)

Creates the EKS Auto Mode cluster, enables audit logging to CloudWatch, installs Falco and OTel via Helm. ~12-15 minutes total. Writes cluster metadata to `.local/cluster-info.json`.

### setup.sh (UPDATED — fast, applies to existing cluster)

Verifies the cluster exists, generates an operator kubeconfig via `aws eks update-kubeconfig`, applies the demo manifests, issues a 1h projected token for the agent, hydrates the iac-repo with the pre-commit hook installed (with the `core.hooksPath` override to defeat any host global hooks), and verifies all three layers fire standalone. Target runtime: under 60 seconds.

### reset.sh (UPDATED — between-runs reset)

Re-hydrates the iac-repo, refreshes the agent token, rewrites the kubeconfig with the fresh token. Cluster stays up.

### teardown.sh (UPDATED — deletes EKS cluster)

`helm uninstall` Falco and OTel, then `eksctl delete cluster`. Runs ~10 minutes. **Run this AFTER the talk, not before.**

### demo.sh — UNCHANGED from v4.1

The runner is platform-agnostic. It reads dialogue files and executes commands via `eval`. Whether those commands hit k3d or EKS makes no difference to the runner. Only the banner text changes from "local k3d cluster" to "EKS Auto Mode (us-east-2)".

---

## Dialogue files — UNCHANGED from v4.1

Paths still resolve via `$DEMO_ROOT` and `$DEMO_LOCAL`. The dialogue files don't know or care that the cluster is EKS instead of k3d. The `@run kubectl --kubeconfig=$DEMO_LOCAL/kubeconfig apply -f ...` line works against any Kubernetes cluster.

---

## CloudWatch audit log tail (NEW in v4.2)

Bottom-right tmux pane:

```bash
aws logs tail /aws/eks/llmday-demo/cluster \
  --region us-east-2 \
  --follow \
  --format short \
  --filter-pattern '{ $.responseStatus.code = 403 }'
```

This shows only the 403 Forbidden responses (where VAP denials show up). When Beat 3 fires, the audit entry appears in this pane within a few seconds.

If CloudWatch latency is an issue (sometimes audit logs lag 30-60 seconds), have a fallback: just show the kubectl error response in the top-right pane and narrate that the audit entry is also in CloudWatch.

---

## Cost model

| Item | Hourly | Demo lifetime (~24 hr) |
|---|---|---|
| EKS control plane | $0.10 | $2.40 |
| Auto Mode management fee | ~$0.06 (small instances) | $1.44 |
| EC2 (t3.medium x 2 for demo workload + add-ons) | ~$0.08 | $1.92 |
| CloudWatch Logs ingestion | minimal | <$0.50 |
| **Total** | | **~$5-6** |

Cheap. Far cheaper than the cost of a bad demo. Tear down within 24 hours of provisioning and there's no further cost.

---

## Speaker runbook excerpt — updates

```markdown
## Pre-show checklist (10 min before going on)
- [ ] Cluster status: `aws eks describe-cluster --name llmday-demo --region us-east-2 --query 'cluster.status'` returns ACTIVE
- [ ] Setup ran clean: `bash setup.sh` completed in under 60 seconds
- [ ] Four-pane tmux layout visible at 22pt font
- [ ] CloudWatch tail in bottom-right pane is connected and streaming
- [ ] `bash demo.sh --dry-run` shows all dialogue without errors
- [ ] `bash demo.sh` runs end-to-end in rehearsal (do this at least twice)
- [ ] Backup video on USB stick
- [ ] Token TTL > 1 hour
- [ ] AWS credentials valid: `aws sts get-caller-identity` returns expected identity
- [ ] Region pinned correctly: `echo $AWS_REGION` returns us-east-2

## During demo (additions to v4.1 runbook)

- Before Beat 1 starts, briefly say: "This is a real EKS Auto Mode cluster running Kubernetes 1.33. Same configuration you'd run in production." 5 seconds. Builds credibility.
- During Beat 3, when VAP fires, narrate: "That deny just hit CloudWatch. Same audit log your SIEM pulls from." Point at the bottom-right pane.
```

---

## Acceptance criteria — updated

### Provisioning verification
- [ ] `provision-cluster.sh` completes successfully (one-time, ~12-15 min)
- [ ] `aws eks describe-cluster` returns `ACTIVE` status
- [ ] Auto Mode enabled
- [ ] Audit logging enabled
- [ ] Falco DaemonSet running in `falco` namespace
- [ ] OTel collector running in `otel` namespace

### Setup verification (run after every `setup.sh`)
- [ ] `.local/kubeconfig` exists and is valid
- [ ] `.local/agent-token` has TTL > 55 minutes
- [ ] `.local/iac-repo/.git/hooks/pre-commit` exists and is executable
- [ ] `production` namespace has `model-server` deployment with 3 replicas
- [ ] VAP `deny-agent-writes-to-production` is applied and bound

### Layer 1 standalone test (unchanged from v4.1)
- [ ] `bash claude-hooks/pretool-use-block-prod.sh < dialogue/beat1-toolcall.json` exits 2 with `PRETOOLUSE_HOOK_DENY` in stderr

### Layer 2 standalone test (unchanged from v4.1)
- [ ] Attempting `git commit` on a protected path with the agent email fails with `GIT_HOOK_DENY`

### Layer 3 standalone test (now on EKS)
- [ ] `kubectl --kubeconfig=.local/kubeconfig apply -f <production-deployment>` returns `Forbidden` from VAP within 2 seconds
- [ ] CloudWatch Logs contains the matching audit entry within 60 seconds

### Demo runner (unchanged from v4.1)
- [ ] `bash demo.sh` runs from start to end without errors when SPACE is pressed at each pause
- [ ] Total runtime 7-9 minutes
- [ ] All three `@run` lines produce visible real output

### Backup video
- [ ] Record after acceptance criteria pass
- [ ] USB stick tested on Michael's laptop

---

## Risk register — EKS-specific additions

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AWS regional outage during demo | Very low | Catastrophic | Backup video. Different region pre-provisioned as deeper backup is overkill; trust the backup video. |
| AWS credentials expire mid-talk | Low | High | Use `aws-vault` or `aws sso` with TTL longer than the talk slot. Verify in pre-show checklist. |
| EKS API throttling | Very low | Medium | Demo runs ~5 kubectl calls total. Throttling threshold is way higher. |
| CloudWatch audit log lag (30-60s) | Medium | Low | Fall back to narrating: "audit entry is on its way to CloudWatch." Don't wait for it on stage. |
| Auto Mode provisioning new node during demo | Low | Low | Auto Mode is fast (~30 sec). If it happens during the demo, it's actually a credibility moment: "and AWS just spun up a node to handle the load." |
| Cluster cost overruns | Very low | Low | Total estimated $5-6 for 24 hours. Even 3x is still trivial. Teardown after the talk closes it out. |

---

## What stays the same from v4.1

- The three-beat narrative
- The scripted dialogue with real enforcement
- The hybrid pacing (auto-type, spacebar at beat transitions)
- The runner script (`demo.sh`) — banner text aside
- The dialogue files (paths still resolve via env vars)
- The Eight Guardrails framing on slide 8 of the deck
- The acceptance criteria for each layer
- The backup video plan

---

## What's deliberately NOT in v4.2

- **No Karpenter custom configuration.** Auto Mode handles it. If you wanted to demo Karpenter NodePools, that's a different talk.
- **No Pod Identity demo.** The demo agent is external (not a pod), so Pod Identity isn't applicable. Mentioned verbally as the in-cluster equivalent.
- **No Fargate.** DaemonSet support matters (Falco). Auto Mode wins on this.
- **No multi-region failover.** Backup video covers the catastrophic case.
- **No ArgoCD installation.** The VAP excludes ArgoCD by name, but we don't run a real ArgoCD pod. The talk mentions it; the demo doesn't need it.

---

## Closing principle (unchanged)

The agent dialogue is scripted. The enforcement is real. **Now the cluster is real too.**

The audience sees the principle live across three layers, with real EKS audit logs, real Bottlerocket nodes, real VAP enforcement at the API server. The probabilistic part (the agent) is fragile, scripted for timing. The deterministic part (the gates) is real, reliable, and stops the agent every time — on the same infrastructure they run in production.

*Don't use probabilistic AI to enforce deterministic requirements. Build the gates programmatically, test them the same way you test your code, and let the agent run.*
