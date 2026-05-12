# LLMday Austin Demo Runbook · Six Gates, Five Live (EKS, GitOps)

Printed reference for the speaker. Keep on the lectern.

## Tonight (one-time provisioning, ~25-30 min total)

```bash
cd <repo>/demo
bash provision-cluster.sh   # ~14 min: EKS Auto Mode + ArgoCD + root-app apply
# Then either:
bash setup.sh               # waits for full GitOps sync (~15 min), generates agent token, verifies the enforcement chain
# Or watch the sync first, then setup:
kubectl --kubeconfig=.local/operator-kubeconfig -n argocd get applications -w
```

After everything is Healthy+Synced, do a `bash demo.sh --dry-run` to verify dialogue renders, then a full rehearsal.

## Pre-show checklist (10 min before going on)

- [ ] AWS credentials valid: `aws sts get-caller-identity` returns expected identity
- [ ] Region pinned: `echo ${AWS_REGION:-us-east-2}` returns `us-east-2`
- [ ] Cluster status ACTIVE: `aws eks describe-cluster --name llmday-demo --region us-east-2 --query 'cluster.status'`
- [ ] All ArgoCD apps Healthy+Synced: `kubectl --kubeconfig=.local/operator-kubeconfig -n argocd get applications`
- [ ] `cd <repo>/demo && bash setup.sh` completed clean (all `✅` lines in the verify block)
- [ ] Four-pane tmux layout visible at 22pt font
- [ ] CloudWatch tail pane connected: `aws logs tail /aws/eks/llmday-demo/cluster --region us-east-2 --follow --filter-pattern '{ $.responseStatus.code = 403 }'`
- [ ] Falco custom rule mounted: `kubectl -n falco exec ds/falco -c falco -- ls /etc/falco/rules.d/` shows `llmday-rules.yaml`
- [ ] Talon loaded its bindings: `kubectl -n falco logs deploy/falco-talon --tail=5 | grep 'rule(s) has/have been successfully loaded'`
- [ ] NetworkPolicy Controller on: `kubectl -n kube-system get cm amazon-vpc-cni -o jsonpath='{.data.enable-network-policy-controller}'` prints `true`
- [ ] PolicyEndpoints generated: `kubectl -n production get policyendpoints` shows at least one
- [ ] `bash demo.sh --dry-run` plays cleanly
- [ ] `bash demo.sh` rehearsed at least twice
- [ ] Backup video on USB stick attached
- [ ] Token TTL covers the talk window: `kubectl --kubeconfig=.local/kubeconfig get inferenceservice -n production` succeeds

If token TTL is low, run `TOKEN_TTL=8h bash reset.sh` to refresh.

## Tmux pane layout

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│  demo.sh                            │  kubectl get pods -A -w             │
│  scripted agent + real enforcement  │  cluster watch                      │
├─────────────────────────────────────┼─────────────────────────────────────┤
│  cd .local/iac-repo && git log -p   │  CloudWatch audit tail +            │
│  (Beat 2 lights up here)            │  falco-talon log tail               │
│                                     │  (Beats 3 / 4 light up here)        │
└─────────────────────────────────────┴─────────────────────────────────────┘
```

Top-left runs `bash demo.sh`. Other three panes start in `watch`/`tail` mode before going on stage. For the falco-talon tail in the bottom-right:

```bash
kubectl --kubeconfig=.local/operator-kubeconfig -n falco logs deploy/falco-talon -f \
  | grep --line-buffered -iE 'match|action|terminate|rule'
```

## On stage

1. SLIDE for "Demo 1 of 6 · LIVE" (PreToolUse hook) visible
2. Switch display to terminal
3. **SAY:**
   > *"What you're watching is a real EKS Auto Mode cluster running Kubernetes 1.35. Real MLOps platform: KServe InferenceService backed by a Kubeflow Model Registry, ArgoCD reconciling from git, Kyverno plus native admission policies, Tetragon eBPF runtime, Falco with Falco Talon, NetworkPolicy on production. This is a scripted recreation. The agent dialogue is scripted so the timing matches my narration. The hooks, the git rejection, the K8s denial, the Falco-and-Talon kill, the NetworkPolicy drop — all real. Let me show you."*
4. Press SPACE to begin Beat 1.
5. Narrate **over** the agent's typing. Do not read what's on screen verbatim.
6. **When the hook fires (red bold output)**, pause, let the audience read, then resume:
   > *"That's the PreToolUse hook. Bash. Reads tool-call JSON on stdin. Denies the call before kubectl ran. The agent reads the deny and adapts."*
7. Press SPACE to advance to Beat 2.
   > *"Two enforcement reasons. The path is protected and the committer email is non-human. Either alone would have blocked it. The repo is configured to reject this exact pattern."*
8. Press SPACE to advance to Beat 3.
   > *"No webhook. No controller. No custom code. CEL expression in the API server. The deny came from EKS itself."*
9. Point at the bottom-right pane:
   > *"And that deny just hit CloudWatch. Same audit log your SIEM pulls from."*
10. Press SPACE to advance to Beat 4.
    > *"Admission only sees what changes in the cluster spec. The agent stops trying to change the spec and just exec's into a pod that's already there. The shell binary spawns. Falco's custom rule sees it on the syscall stream, falcosidekick forwards the event to Talon, Talon calls the API to delete the pod. The ReplicaSet replaces it. No human in the loop."*
11. Press SPACE to advance to Beat 5.
    > *"This one is different in kind. The agent doesn't do anything dangerous at the syscall level. It just tries to talk to an outside destination. DNS resolves — the cluster service CIDR is allowed. The TCP SYN to huggingface.co never opens. It's not on the production egress allowlist. Falco didn't fire. Talon didn't run. The pod stayed alive. The destination was the only thing the policy cared about."*
12. **The "right path" wrap** (verbal — point at the cluster, not the slides):
    > *"This is the path the agent should have used."*
    > *Optionally show:* `kubectl --kubeconfig=.local/operator-kubeconfig -n argo get workflowtemplate promote-model-to-production -o yaml | head -30`
    > *"An Argo Workflow that fetches from the registry, runs eval, signs the artifact with cosign, opens a PR to gitops-prod. ArgoCD reconciles the merged PR. Same agent identity. Different routing, through the deterministic gates the team already configured."*
13. End of live demo. Switch back to slides for Beat 6 (output / LLM Guard, on slide):
    > *"Layers 1 through 5 keep the agent from breaking the system. Layer 6 keeps the system from saying things it shouldn't."*

## TIME CHECK

- 3:00 in: at the start of Beat 2.
- 5:00 in: at the start of Beat 3.
- 6:30 in: at the start of Beat 4.
- 8:00 in: at the start of Beat 5.
- 9:00 in: closing the live block.

If you're behind at any of those gates, the next beats still run (everything is scripted); trim narration on the agent's `::thinking::` lines.

## If something breaks

- **Hook doesn't fire** — standalone tests passed during `setup.sh`. Check `KUBECONFIG`. Worst case, backup video.
- **demo.sh crashes mid-beat** — `bash demo.sh --resume-beat=N` skips ahead to Beat N (1-5).
- **Falco doesn't fire in Beat 4** — give the DaemonSet ~60s after any rollout for the eBPF probe to attach. If still silent: `kubectl -n falco logs ds/falco -c falco --since=60s | head` should show events; if empty, the modern eBPF driver didn't load on that node.
- **Talon doesn't act on a Falco event** — `kubectl -n falco logs deploy/falco-falcosidekick --tail=20 | grep Talon` should show `POST OK (200)`. If not, falcosidekick lost its TALON_ADDRESS env var; restart it.
- **NetworkPolicy doesn't drop in Beat 5** — `kubectl -n production get policyendpoints` should show at least one. If empty, the EKS Auto Mode Network Policy Controller is off; check `kubectl -n kube-system get cm amazon-vpc-cni`.
- **Wrong pane focus** — `tmux select-pane -L/-R/-U/-D`. Stay calm.
- **AWS creds expire** — refresh, re-run `bash setup.sh`, restart `demo.sh`.
- **ArgoCD app goes OutOfSync mid-demo** — irrelevant to the demo's enforcement path. Ignore unless someone asks; then narrate: *"ArgoCD is reconciling; doesn't affect what you just saw."*
- **CloudWatch tail lags** — narrate *"audit entry on its way to CloudWatch"* instead of waiting on stage.
- **Total live demo failure** — backup video on USB. Narrate over it.

## Recovery commands

```bash
bash demo.sh --resume-beat=2     # skip Beat 1
bash demo.sh --resume-beat=3     # skip Beats 1-2
bash demo.sh --resume-beat=4     # skip Beats 1-3
bash demo.sh --resume-beat=5     # skip Beats 1-4
bash demo.sh --dry-run           # print all dialogue, no execution
TYPE_DELAY_MS=10 bash demo.sh    # faster typing
TOKEN_TTL=8h bash reset.sh       # refresh iac-repo and token without rebuilding cluster
```

## After the talk

```bash
bash teardown.sh
```

`eksctl delete cluster` (~10 min) plus `.local/` wipe. Billing stops when the control plane is gone.
