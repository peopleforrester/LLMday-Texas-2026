# FAQ · Questions the Audience Asks About the Live Demo

Common questions raised during and after the talk, with the actual answers from how the demo was built. If your question isn't here and it should be, open an issue or wait for `qa.md` to be populated post-event.

## On the demo itself

### Why is the "model server" running `nginx`?

The narrative doesn't depend on it being a real model. The agent's attack is *"modify a `Deployment` in the production namespace"* — that surface is satisfied by any workload that's a Deployment in production. nginx is fast to pull, has a small image, and ships with `curl` + `wget` + `nslookup` inside the container, which is exactly what Beat 5 (the NetworkPolicy egress test) needs.

The v4.7 build spec called for a real KServe `InferenceService` running sklearn iris. KServe was dropped because its Helm chart isn't published at a stable URL, raw manifests weren't worth the effort for an 11-minute live block, and KServe being absent doesn't change a single beat. The decision is documented inline in `demo/gitops/manifests/workloads/model-server.yaml`. See `docs/SPEC.md`'s *"What was dropped"* section.

### Why is Beat 6 (output / content) only on slide?

Two reasons. First, a live content-filtering demo needs a real LLM serving in the cluster, a gateway in front of it (Envoy AI Gateway / NeMo Guardrails / LLM Guard), a prompt that exercises the filter, and rehearsal. That's a 6-10 hour build with low margin for error, not a fit for an 11-minute live block. Second, the talk's thesis is about infrastructure-layer controls (Demos 1-5); Beat 6 is a different layer (content / what the model says), called out explicitly on slide 16 so the audience knows the matrix has six rows, not five.

### What about Tetragon? It's running in the cluster.

Tetragon is installed as a DaemonSet for eBPF runtime observability. It's not the responder in this demo — that's Falco + Falco Talon. Tetragon could enforce kernel-level policies (`TracingPolicyEnforce` with SIGKILL on a `tcp_connect` syscall, for example), but enforcement isn't visible to a projector audience the way Talon's `kubernetes:terminate` is (a pod disappears on screen). Tetragon stays in the cluster as observability infrastructure; Talon is the enforcer in Beat 4.

### Why does Beat 4 use a custom Falco rule instead of the stock `Terminal shell in container`?

The stock Falco rule excludes a long list of process names (`shell_binaries`, `jenkins_plugin_install_binaries`, `fluentbit_binaries`, etc.) and excludes specific user IDs to keep noise low for the typical fleet. The demo scenario hits enough of those exclusions that the stock rule didn't fire reliably during prep. The custom rule (`Agent exec in production` in `demo/gitops/values/falco-values.yaml`) is tighter: shell binary spawned with `containerd-shim` as parent (the kubectl-exec syscall signature) inside a pod in the `production` namespace. Talon's binding catches both the custom rule and the stock rule, so either path lands.

### Why is the NetworkPolicy using `ipBlock` for DNS instead of `namespaceSelector: kube-system`?

EKS Auto Mode runs DNS on the node OS itself (Bottlerocket), not as a `kube-system` Deployment. There is no `kube-dns` Service and no `coredns` pod for a `namespaceSelector` to match. DNS queries from production pods hit `10.100.0.10` (the cluster service CIDR), which gets routed to the node-local resolver. The `ipBlock: 10.100.0.0/16` rule covers that path. If you copy this NetworkPolicy to a non-Auto-Mode cluster, switch back to a `namespaceSelector: kube-system + port 53` rule.

### Why did Beat 5 fail silently on stage (or in rehearsal)?

Two ways this can happen, both fixed in this repo:

1. **Agent token expired.** The default `TOKEN_TTL` in `setup.sh` and `reset.sh` is 1 hour. If your rehearsal runs past that, `kubectl` returns `Unauthorized` and the demo's per-command badge used to paint that green. Override with `TOKEN_TTL=8h bash reset.sh`. (The badge also got fixed: auth/RBAC failures now paint `⚠ ERROR (kubectl auth or RBAC)`, not `✓ ALLOWED`.)
2. **NetworkPolicy controller wasn't on.** EKS Auto Mode accepts `networking.k8s.io/v1 NetworkPolicy` resources but doesn't enforce them unless the `amazon-vpc-cni` ConfigMap in `kube-system` has `enable-network-policy-controller: "true"`. That ConfigMap is now GitOps-managed at `demo/gitops/manifests/cluster-config/vpc-cni-network-policy.yaml`. Verify with `kubectl -n production get policyendpoints` (expect at least one entry).

## On the broader matrix

### What does this look like outside Kubernetes?

The Agentic Covenants Matrix is platform-agnostic. The three layers (in-agent, client-side, server-side) cross with five concerns (identity, authorization, blast radius, approval gating, supply chain), and every cell has a non-Kubernetes implementation. Slide 11 of the deck shows the parallel mapping for SageMaker / MLflow / a generic CI/CD environment. The companion repo is [github.com/peopleforrester/agentic-covenants](https://github.com/peopleforrester/agentic-covenants); the canonical matrix lives there.

### How does this fit with NIST CSF?

The matrix is scoped to NIST CSF 2.0's **Protect** function on purpose. The framework has five functions (Govern, Identify, Protect, Detect, Respond, Recover); most "AI guardrail" content blurs them. Drift detection and rollback automation are Detect and Recover concerns and live in separate matrices that compose with this one rather than being mixed in. The article (`mlops-as-agentic-guardrail.md`) is explicit about the scoping.

### What about RBAC? Isn't that already the answer?

RBAC matters but isn't sufficient. Beats 1 and 2 fire before any RBAC check happens (the hook and the git commit live on the agent's workstation). Beat 3 specifically demonstrates an **intentionally over-scoped RBAC role** for the agent — it has full CRUD on Deployments in production — and shows that the server-side ValidatingAdmissionPolicy is what catches the write despite RBAC saying yes. Beat 4 extends this: the same over-scoped role grants `pods/exec`, and runtime detection-and-response (Falco + Talon) is what catches the exec. The line on slide 11 captures it: *"The admission policy is the line that holds when RBAC has drifted."*

## On reproducing this

### Can I run the demo without a real EKS cluster?

Beats 1 and 2 (in-agent hook, git pre-commit) need only Bash and git. The hooks under `examples/` install locally and run against any repo. Beats 3-5 need a real Kubernetes cluster with admission webhooks, a CNI that supports `NetworkPolicy`, and Falco's modern eBPF driver. EKS Auto Mode is what this repo's `provision-cluster.sh` builds; other CNCF clusters (kind / k3d / vanilla EKS / GKE) would work with adapted manifests, but the `amazon-vpc-cni` ConfigMap (Beat 5's enable knob) is EKS-specific.

### How much does running the live cluster cost?

Roughly $14-17 for a 24-hour cluster lifetime: EKS control plane ($0.10/hr × 24), two to three c6a.large Auto Mode nodes ($0.16-0.25/hr × 24), modest CloudWatch + EBS. Tear down within 24 hours and billing stops. `bash demo/teardown.sh` does an `eksctl delete cluster` plus a `.local/` cleanup. Full cost model in `docs/SPEC.md`.

### Why are some ArgoCD apps showing `OutOfSync` or `Degraded`?

Cosmetic drift, not enforcement-affecting. Common culprits:

- `kyverno` and `kyverno-policies`: the webhook `failurePolicy` got patched to `Ignore` during pre-talk debugging; the chart's default is `Fail`. Either is fine for the demo because Kyverno is in audit mode.
- `jaeger`, `otel`, `loki`: in-memory deployments whose health probes are flaky despite the pods being up.
- `argo-workflows`: chart 1.0.13 had a deploy-vs-image-version mismatch at one point; the controller now runs `v4.0.5` cleanly. If it ever drifts, force-sync the Application.

None of these are on the demo's enforcement path.
