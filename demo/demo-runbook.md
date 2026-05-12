# LLMday Austin Demo Runbook (v4.7, EKS, GitOps)

Printed reference for the speaker. Keep on the lectern.

## Tonight (one-time provisioning, ~25-30 min total)

```bash
cd <repo>/demo
bash provision-cluster.sh   # ~14 min: EKS Auto Mode + ArgoCD + root-app apply
# Then either:
bash setup.sh               # waits for full GitOps sync (~15 min), generates agent token, verifies all 3 layers
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
- [ ] `bash demo.sh --dry-run` plays cleanly
- [ ] `bash demo.sh` rehearsed at least twice
- [ ] Backup video on USB stick attached
- [ ] Token TTL > 1 hour: `kubectl --kubeconfig=.local/kubeconfig get inferenceservice -n production` succeeds

If token TTL is low, run `bash reset.sh` to refresh.

## Tmux pane layout

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│  demo.sh (Claude Code session)      │  kubectl get pods -A -w             │
│  agent thinking, prompts, denies    │  cluster watch                      │
├─────────────────────────────────────┼─────────────────────────────────────┤
│  cd .local/iac-repo && git log -p   │  CloudWatch audit tail              │
│  (Beat 2 lights up here)            │  (Beat 3 lights up here)            │
└─────────────────────────────────────┴─────────────────────────────────────┘
```

Top-left runs `bash demo.sh`. Other three panes start in `watch`/`tail` mode before going on stage.

## On stage

1. SLIDE for "Demo: three layers" visible
2. Switch display to terminal
3. **SAY:**
   > *"What you're watching is a real EKS Auto Mode cluster running Kubernetes 1.35. Real MLOps platform: KServe InferenceService backed by a Kubeflow Model Registry, ArgoCD reconciling from git, Kyverno + native admission policies, Tetragon eBPF runtime, Falco. This is also a scripted recreation: the agent dialogue is scripted so the timing matches my narration. The hooks are real. The Git rejection is real. The K8s denial is real. Let me show you."*
4. Press SPACE to begin Beat 1
5. Narrate **over** the agent's typing — don't read what's on screen verbatim
6. **When the hook fires (red bold output)**, pause your narration, let the audience read, then resume:
   > *"That's the PreToolUse hook. Bash. Reads tool-call JSON on stdin. Denies the call before kubectl ran. The agent reads the deny and adapts."*
7. Press SPACE to advance to Beat 2
8. Same pattern:
   > *"Two enforcement reasons. The path is protected AND the committer email is non-human. Either alone would have blocked it. The repo is configured to reject this exact pattern."*
9. Press SPACE to advance to Beat 3
10. Pause longer — closer:
    > *"No webhook. No controller. No custom code. CEL expression in the API server. The deny came from EKS itself."*
11. Point at the bottom-right pane:
    > *"And that deny just hit CloudWatch. Same audit log your SIEM pulls from."*
12. **The "right path" wrap** (verbal — point at the cluster, not the slides):
    > *"This is the path the agent should have used."*
    > *Optionally show:* `kubectl --kubeconfig=.local/operator-kubeconfig -n argo get workflowtemplate promote-model-to-production -o yaml | head -30`
    > *"An Argo Workflow that fetches from the registry, runs eval, signs the artifact with cosign, opens a PR to gitops-prod. ArgoCD reconciles the merged PR. Same agent identity. Different routing — through deterministic gates the team already configured."*
13. End of demo. Switch back to slides.

## TIME CHECK at 6:00

You should be **at the start of Beat 3** by 6:00 into the demo. If not, Beat 3 still runs (it's scripted) — but trim narration on the final two `@say:agent` lines.

## If something breaks

- **Hook doesn't fire** — standalone tests passed during `setup.sh`. Check `KUBECONFIG`. Worst case, backup video.
- **demo.sh crashes mid-beat** — `bash demo.sh --resume-beat=2` skips ahead.
- **Wrong pane focus** — `tmux select-pane -L/-R/-U/-D`. Stay calm.
- **AWS creds expire** — refresh, re-run `bash setup.sh`, restart `demo.sh`.
- **ArgoCD app goes OutOfSync mid-demo** — irrelevant to the demo's enforcement path. Ignore unless someone asks; then narrate: "ArgoCD is reconciling; doesn't affect what you just saw."
- **CloudWatch tail lags** — narrate "audit entry on its way to CloudWatch" instead of waiting on stage.
- **Total live demo failure** — backup video on USB. Narrate over it.

## Recovery commands

```bash
bash demo.sh --resume-beat=2     # skip Beat 1
bash demo.sh --resume-beat=3     # skip Beat 1 and 2
bash demo.sh --dry-run           # print all dialogue, no execution
TYPE_DELAY_MS=10 bash demo.sh    # faster typing
bash reset.sh                    # refresh iac-repo and token without rebuilding cluster
```

## After the talk

```bash
bash teardown.sh
```

`eksctl delete cluster` (~10 min) + `.local/` wipe. Billing stops when the control plane is gone.
