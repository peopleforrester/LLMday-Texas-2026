#!/usr/bin/env bash
# ABOUTME: Removes the k3d cluster and wipes .local/ for the LLMday demo.
# ABOUTME: Safe to re-run; missing cluster or .local is not an error.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
CLUSTER_NAME="llmday-demo"

echo "==> tearing down LLMday demo"

if command -v k3d >/dev/null 2>&1 && k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
  echo "    deleting k3d cluster '$CLUSTER_NAME'"
  k3d cluster delete "$CLUSTER_NAME"
else
  echo "    k3d cluster '$CLUSTER_NAME' not present"
fi

if [[ -d "$DEMO_LOCAL" ]]; then
  echo "    removing $DEMO_LOCAL"
  rm -rf "$DEMO_LOCAL"
fi

if [[ -f "$HOME/.claude/llmday-demo-settings.json" ]]; then
  echo "    removing $HOME/.claude/llmday-demo-settings.json"
  rm -f "$HOME/.claude/llmday-demo-settings.json"
fi

echo "==> teardown complete"
