#!/usr/bin/env bash
# ABOUTME: v4.7 teardown: eksctl delete cluster + wipe .local/.
# ABOUTME: ArgoCD apps go with the cluster; no separate helm uninstall needed.

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

if command -v eksctl >/dev/null 2>&1 && \
   aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "    deleting EKS cluster '$CLUSTER_NAME' in $REGION (~10 minutes)"
  eksctl delete cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME"
else
  echo "    cluster '$CLUSTER_NAME' not present in $REGION; nothing to delete"
fi

if [[ -d "$DEMO_LOCAL" ]]; then
  echo "    removing $DEMO_LOCAL"
  rm -rf "$DEMO_LOCAL"
fi

echo "==> teardown complete"
