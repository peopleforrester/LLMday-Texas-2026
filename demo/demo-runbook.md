# LLMday Austin Demo Runbook (EKS)

Printed reference for the speaker. Keep on the lectern.

## Tonight (one-time provisioning)

```bash
cd <repo>/demo
bash provision-cluster.sh   # 12-15 min. Cluster + Falco + OTel.
```

Verify when it finishes:
```bash
aws eks describe-cluster --name llmday-demo --region us-east-2 --query 'cluster.status'   # ACTIVE
```

## Pre-show checklist (10 min before going on)

- [ ] AWS credentials valid: `aws sts get-caller-identity` returns expected identity
- [ ] Region pinned: `echo ${AWS_REGION:-us-east-2}` returns `us-east-2`
- [ ] Cluster status ACTIVE: `aws eks describe-cluster --name llmday-demo --region us-east-2 --query 'cluster.status'`
- [ ] `cd <repo>/demo && bash setup.sh` completed clean (target: under 60 seconds; all `✅` lines in the verify block)
- [ ] Four-pane tmux layout visible at 22pt font
- [ ] CloudWatch tail pane connected: `aws logs tail /aws/eks/llmday-demo/cluster --region us-east-2 --follow --filter-pattern '{ $.responseStatus.code = 403 }'`
- [ ] `bash demo.sh --dry-run` shows all dialogue without errors
- [ ] `bash demo.sh` runs end-to-end in rehearsal (do this at least twice)
- [ ] Backup video on USB stick attached to laptop
- [ ] Token TTL > 1 hour: `kubectl --kubeconfig=.local/kubeconfig get deployments -n production` returns successfully

If token TTL is low, run `bash reset.sh` to refresh.

## Tmux pane layout (target)

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│  demo.sh (Claude Code session)      │  kubectl get pods -A -w             │
│  agent thinking, prompts, denies    │  cluster watch                      │
├─────────────────────────────────────┼─────────────────────────────────────┤
│  git log -p (iac-repo)              │  CloudWatch audit tail              │
│  (Beat 2 lights up here)            │  (Beat 3 lights up here)            │
└─────────────────────────────────────┴─────────────────────────────────────┘
```

Top-left runs `bash demo.sh`. Other three panes start in `watch`/`tail` mode before going on stage.

## On stage

1. SLIDE for "Demo: three layers" visible
2. Switch display to terminal
3. **SAY:** *"What you're watching is a real EKS Auto Mode cluster running Kubernetes 1.33. Same configuration you'd run in production. This is also a scripted recreation: the agent dialogue is scripted so the timing matches my narration. The hooks are real. The Git rejection is real. The K8s denial is real. Let me show you."*
4. Press SPACE to begin Beat 1
5. Narrate **over** the agent's typing — don't read what's on screen verbatim
6. **When the hook fires (red bold output)**, pause your narration, let the audience read, then resume:
   *"That's the PreToolUse hook. Bash. Reads tool-call JSON on stdin. Denies the call before kubectl ran. The agent reads the deny and adapts."*
7. Press SPACE to advance to Beat 2
8. Same pattern: narrate over the typing, pause on the deny, explain.
   *"Two enforcement reasons. The path is protected AND the committer email is non-human. Either alone would have blocked it. The repo is configured to reject this exact pattern."*
9. Press SPACE to advance to Beat 3
10. Same pattern. Pause longer — this is the closer:
    *"No webhook. No controller. No custom code. CEL expression in the API server. The deny came from EKS itself."*
11. Point at the bottom-right pane: *"And that deny just hit CloudWatch. Same audit log your SIEM pulls from."*
12. End of demo. Switch back to slides.

## TIME CHECK at 6:00

You should be **at the start of Beat 3** by 6:00 into the demo. If not, Beat 3 still runs to completion (it's scripted) — but trim narration on the final two `@say:agent` lines.

## If something breaks

- **Hook doesn't fire** — standalone tests passed during `setup.sh`. Check `KUBECONFIG`. If genuinely broken, switch to backup video.
- **demo.sh crashes mid-beat** — `bash demo.sh --resume-beat=2` skips ahead.
- **Wrong pane gets focus** — `tmux select-pane -L/-R/-U/-D`. Stay calm.
- **AWS credentials expire** — refresh credentials, re-run `bash setup.sh`, restart `demo.sh`.
- **CloudWatch tail lags** — narrate "audit entry on its way to CloudWatch" instead of waiting on stage.
- **Total live demo failure** — backup video on USB. Narrate over it. The audience cannot tell the difference if you don't tell them.

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

Runs `helm uninstall` on Falco and OTel, then `eksctl delete cluster`. Takes ~10 minutes. Stops the AWS billing meter.
