#!/usr/bin/env bash
# ABOUTME: Deletes the EKS Auto Mode cluster and wipes .local/.
# ABOUTME: Run AFTER the talk, not before. Cluster delete takes ~10 minutes.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
REGION="${AWS_REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-llmday-demo}"
AWS_PROFILE_FLAG=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE_FLAG="--profile $AWS_PROFILE"
fi

echo "==> tearing down LLMday demo (EKS)"

# ----- Helm uninstalls (release Auto Mode nodes faster) ---------------------
if command -v helm >/dev/null 2>&1 && [[ -f "$DEMO_LOCAL/operator-kubeconfig" ]]; then
  export KUBECONFIG="$DEMO_LOCAL/operator-kubeconfig"
  helm uninstall otel -n otel 2>/dev/null || true
  helm uninstall falco -n falco 2>/dev/null || true
fi

# ----- Delete the EKS cluster -----------------------------------------------
if command -v eksctl >/dev/null 2>&1 && \
   aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "    deleting EKS cluster '$CLUSTER_NAME' in $REGION (this takes ~10 minutes)"
  eksctl delete cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME"
else
  echo "    cluster '$CLUSTER_NAME' not found in $REGION; nothing to delete"
fi

# ----- Local cleanup --------------------------------------------------------
if [[ -d "$DEMO_LOCAL" ]]; then
  echo "    removing $DEMO_LOCAL"
  rm -rf "$DEMO_LOCAL"
fi

if [[ -f "$HOME/.claude/llmday-demo-settings.json" ]]; then
  echo "    removing $HOME/.claude/llmday-demo-settings.json"
  rm -f "$HOME/.claude/llmday-demo-settings.json"
fi

echo "==> teardown complete"
