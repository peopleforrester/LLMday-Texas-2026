# Glossary

One-line definitions for the terms that show up in the demo and the slide deck without being explained in front of the audience. Sorted alphabetically.

### `amazon-vpc-cni` (ConfigMap)

A `kube-system` ConfigMap that the EKS Auto Mode CNI reads at startup and on change. Setting `enable-network-policy-controller: "true"` turns on NetworkPolicy enforcement; without it, `NetworkPolicy` resources are accepted by the API but generate no PolicyEndpoints and no packet filtering. See `demo/gitops/manifests/cluster-config/vpc-cni-network-policy.yaml`.

### ArgoCD

GitOps controller for Kubernetes. Reads manifests from this repo's `demo/gitops/` tree and applies them to the cluster. The "app of apps" pattern is bootstrapped by `provision-cluster.sh` and reconciles everything else.

### Bottlerocket

AWS's minimal Linux distribution for container hosts. The EKS Auto Mode nodes in this demo run Bottlerocket. Notable for the demo: DNS is resolved on the node OS itself, not by a kube-system pod, which is why Beat 5's NetworkPolicy uses `ipBlock` for DNS.

### CEL (Common Expression Language)

The expression language Kubernetes ValidatingAdmissionPolicy uses for its `validations` and `matchConditions`. Beat 3's VAP uses CEL to express "deny if the request namespace is production AND the user is the agent SA".

### eBPF

In-kernel programmable hooks. Falco's modern driver uses eBPF to capture syscalls without a kernel module. Tetragon also uses eBPF for observability and (optionally) enforcement.

### EKS Auto Mode

AWS's managed mode for EKS clusters where AWS handles the CNI, EBS CSI, node provisioning (via Karpenter), and a curated set of add-ons. Replaces self-managed `aws-node` DaemonSet, EBS CSI install, and Cluster Autoscaler. This demo runs on Auto Mode.

### Falco

CNCF runtime security tool. Watches host and container syscalls via eBPF; emits JSON events when its rules match. Beat 4's custom rule (`Agent exec in production`) is defined in `demo/gitops/values/falco-values.yaml` under `customRules`.

### Falcosidekick

The router that ships Falco events to downstream systems. Bundled with the Falco chart. In this demo, Falcosidekick forwards events to Falco Talon over HTTP via the `talon.address` config option.

### Falco Talon

The response engine that takes action on Falco events. Receives event JSON from Falcosidekick over HTTP, matches against its own rules, and runs an "actionner" (`kubernetes:terminate`, `kubernetes:label`, etc.). Beat 4's binding maps the Falco rule name to `kubernetes:terminate` against the originating pod.

### `ipBlock` (NetworkPolicy peer)

A CIDR-based egress allow rule in a `NetworkPolicy`. The alternative is `namespaceSelector` / `podSelector`. EKS Auto Mode's DNS lives on the node OS, not as a pod, so `ipBlock: 10.100.0.0/16` is the only correct way to allow DNS without overly opening other traffic.

### `kubectl exec deploy/<name>`

A kubectl shorthand that resolves `deploy/<name>` to one of the Deployment's pods server-side. Used in Beat 4 and Beat 5 instead of `$(kubectl get pods -o jsonpath ...)` to avoid fragile bash substitution when the inner kubectl fails.

### Karpenter

The autoscaler EKS Auto Mode uses to provision nodes on demand. NodePools (`general-purpose`, `system`) and NodeClass (`default`) drive what instance types are picked. The `system` NodePool has a `CriticalAddonsOnly` taint; pods running there need a matching toleration (Falco Talon has one).

### Kyverno

A Kubernetes policy engine. This demo runs Kyverno alongside the native ValidatingAdmissionPolicy as belt-and-suspenders, mostly in audit mode. The VAP does the live deny in Beat 3; Kyverno's policies generate `PolicyReport` resources for the audit side.

### NodeClass / NodePool (Karpenter)

`NodePool` defines requirements (instance category, generation, OS, architecture); `NodeClass` defines the underlying infra config (subnets, security groups, ephemeral storage, network policy mode). The `NodeClass.spec.networkPolicy` field is `DefaultAllow` here, which means pods get traffic until a `NetworkPolicy` selects them.

### `PolicyEndpoint` (`networking.k8s.aws/v1alpha1`)

The internal resource the EKS Auto Mode NetworkPolicy controller generates from a standard `networking.k8s.io/v1 NetworkPolicy`. Distributes the policy to the per-node CNI agents for enforcement. If `kubectl -n production get policyendpoints` returns empty, the controller isn't enabled.

### PostCompact (Claude Code hook)

A Claude Code lifecycle event that fires after the agent's history is compacted. Used by `examples/claude-hooks/auto-reanchor.sh` to re-emit `CLAUDE.md` / `PROJECT_STATE.md` / git state so the agent doesn't forget the rules after a compaction.

### PostToolUse / PreToolUse (Claude Code hook)

Lifecycle events around the agent calling a tool. `PreToolUse` fires before the tool runs and can block via exit code 2 (Beat 1's hook does this). `PostToolUse` fires after and can only emit warnings (the validate-file and check-aboutme hooks do this).

### PSS (Pod Security Standards)

Kubernetes-built-in security profiles: `privileged`, `baseline`, `restricted`. Set per-namespace via labels (e.g., `pod-security.kubernetes.io/enforce: restricted`). The production namespace in this demo enforces `restricted`, which is why ad-hoc curl pods need an explicit `securityContext` to be admitted.

### ServiceAccount projected token

A short-lived JWT bound to a Kubernetes ServiceAccount, issued by `kubectl create token`. The demo's agent kubeconfig uses one of these (`.local/agent-token`) instead of long-lived credentials. Default TTL in `setup.sh` is 1h; override with `TOKEN_TTL=8h bash reset.sh` for a rehearsal window.

### Sync wave (ArgoCD)

The `argocd.argoproj.io/sync-wave` annotation orders Application creation. Negative waves go first. In this demo: -10 namespaces and cluster-config, -4 cert-manager and kyverno (CRDs), -3 policies and RBAC, -2 falco and tetragon, -1 falco-talon and cert-issuers, 0 admission and network-policies, 1-4 the rest.

### Tetragon

CNCF eBPF observability tool. Watches kernel events; can enforce via `TracingPolicyEnforce` (SIGKILL on specific syscalls). This demo runs Tetragon as observability, not enforcement; the enforcement path is Falco + Talon.

### VAP / ValidatingAdmissionPolicy

Native Kubernetes admission control as of v1.30+, GA in v1.31. CEL expressions evaluated in the API server itself — no webhook, no controller, no custom code. Beat 3's deny comes from a VAP at `demo/gitops/manifests/vap/vap.yaml`.

### ValidatingAdmissionPolicyBinding

The resource that scopes a VAP to specific namespaces or resources. The VAP + Binding pair is what actually fires; a VAP alone doesn't enforce.
