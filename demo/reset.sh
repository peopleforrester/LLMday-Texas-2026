#!/usr/bin/env bash
# ABOUTME: Between-rehearsal-runs reset for the LLMday demo.
# ABOUTME: Re-hydrates the iac-repo and refreshes the projected token; keeps the cluster.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
CLUSTER_NAME="llmday-demo"
TOKEN_TTL="${TOKEN_TTL:-1h}"

if [[ ! -d "$DEMO_LOCAL" ]]; then
  echo "ERROR: $DEMO_LOCAL not found. Run 'bash $DEMO_ROOT/setup.sh' first." >&2
  exit 1
fi

if ! k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
  echo "ERROR: k3d cluster '$CLUSTER_NAME' not found. Run 'bash $DEMO_ROOT/setup.sh' first." >&2
  exit 1
fi

echo "==> resetting iac-repo"
rm -rf "$DEMO_LOCAL/iac-repo"
cp -r "$DEMO_ROOT/iac-repo-template" "$DEMO_LOCAL/iac-repo"

pushd "$DEMO_LOCAL/iac-repo" >/dev/null
git init -q
# Override any global core.hooksPath so the per-repo pre-commit fires.
git config core.hooksPath ".git/hooks"
git config user.email "platform-team@example.com"
git config user.name  "platform-team"
git config commit.gpgsign false 2>/dev/null || true
mkdir -p .git/hooks
cp "$DEMO_LOCAL/iac-repo/hooks/pre-commit" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git add .
git commit -q -m "initial state: model v1.2.0 in production"
popd >/dev/null

echo "==> refreshing projected token (TTL=$TOKEN_TTL)"
kubectl -n staging create token claude-agent \
  --duration "$TOKEN_TTL" \
  --audience https://kubernetes.default.svc > "$DEMO_LOCAL/agent-token"
chmod 600 "$DEMO_LOCAL/agent-token"

# Rewrite kubeconfig with the fresh token (server + CA unchanged)
TOKEN=$(cat "$DEMO_LOCAL/agent-token")
SERVER=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
cat > "$DEMO_LOCAL/kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: $CLUSTER_NAME
  cluster:
    server: $SERVER
    certificate-authority-data: $CA
users:
- name: claude-agent
  user:
    token: $TOKEN
contexts:
- name: claude-agent@$CLUSTER_NAME
  context:
    cluster: $CLUSTER_NAME
    user: claude-agent
    namespace: staging
current-context: claude-agent@$CLUSTER_NAME
EOF
chmod 600 "$DEMO_LOCAL/kubeconfig"

# Clean any prior Beat 3 runtime artifact
rm -f "$DEMO_LOCAL/beat3-prod-update.yaml"

echo "==> reset complete. Ready for another rehearsal run."
