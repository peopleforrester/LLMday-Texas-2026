#!/usr/bin/env bash
# ABOUTME: Between-rehearsal-runs reset for the LLMday demo (EKS).
# ABOUTME: Re-hydrates iac-repo and refreshes the agent token. Keeps the cluster.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
REGION="${AWS_REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-llmday-demo}"
TOKEN_TTL="${TOKEN_TTL:-1h}"
AWS_PROFILE_FLAG=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE_FLAG="--profile $AWS_PROFILE"
fi

if [[ ! -d "$DEMO_LOCAL" ]]; then
  echo "ERROR: $DEMO_LOCAL not found. Run 'bash $DEMO_ROOT/setup.sh' first." >&2
  exit 1
fi

if ! aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "ERROR: cluster '$CLUSTER_NAME' not found in $REGION." >&2
  echo "       run: bash $DEMO_ROOT/provision-cluster.sh" >&2
  exit 1
fi

# Use the operator kubeconfig from .local
export KUBECONFIG="$DEMO_LOCAL/operator-kubeconfig"

echo "==> resetting iac-repo"
rm -rf "$DEMO_LOCAL/iac-repo"
cp -r "$DEMO_ROOT/iac-repo-template" "$DEMO_LOCAL/iac-repo"

pushd "$DEMO_LOCAL/iac-repo" >/dev/null
git init -q
git config core.hooksPath ".git/hooks"
git config user.email "platform-team@example.com"
git config user.name  "platform-team"
git config commit.gpgsign false 2>/dev/null || true
# Initial commit FIRST, then install hook. Hook would deny on the
# initial commit because the template contains files under
# infrastructure/production/.
git add .
git commit -q -m "initial state: model v1.2.0 in production"
mkdir -p .git/hooks
cp "$DEMO_LOCAL/iac-repo/hooks/pre-commit" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
popd >/dev/null

echo "==> refreshing projected token (TTL=$TOKEN_TTL)"
kubectl -n staging create token claude-agent \
  --duration "$TOKEN_TTL" \
  --audience https://kubernetes.default.svc > "$DEMO_LOCAL/agent-token"
chmod 600 "$DEMO_LOCAL/agent-token"

TOKEN=$(cat "$DEMO_LOCAL/agent-token")
SERVER=$(aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" \
  --query 'cluster.endpoint' --output text)
CA=$(aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" \
  --query 'cluster.certificateAuthority.data' --output text)

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

rm -f "$DEMO_LOCAL/beat3-prod-update.yaml"

echo "==> reset complete. Ready for another rehearsal run."
