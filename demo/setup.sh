#!/usr/bin/env bash
# ABOUTME: Fast setup for the LLMday demo against an existing EKS cluster.
# ABOUTME: Run after provision-cluster.sh. Builds kubeconfigs, applies manifests, verifies layers.

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

echo "==> LLMday demo setup (EKS)"
echo "    DEMO_ROOT=$DEMO_ROOT"
echo "    DEMO_LOCAL=$DEMO_LOCAL"
echo "    REGION=$REGION CLUSTER=$CLUSTER_NAME"
echo ""

# ----- Prerequisites ---------------------------------------------------------
for cmd in aws kubectl git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not on PATH" >&2
    exit 1
  fi
done

# Verify cluster exists (from provision-cluster.sh)
if ! aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "ERROR: cluster '$CLUSTER_NAME' not found in $REGION." >&2
  echo "       run: bash $DEMO_ROOT/provision-cluster.sh" >&2
  exit 1
fi

mkdir -p "$DEMO_LOCAL"

# ----- Operator kubeconfig (AWS-creds-backed) --------------------------------
echo "==> wiring operator kubeconfig (aws eks get-token)"
aws eks update-kubeconfig $AWS_PROFILE_FLAG \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --kubeconfig "$DEMO_LOCAL/operator-kubeconfig" >/dev/null
chmod 600 "$DEMO_LOCAL/operator-kubeconfig"
export KUBECONFIG="$DEMO_LOCAL/operator-kubeconfig"

# ----- Apply manifests in order ---------------------------------------------
echo "==> applying namespaces"
kubectl apply -f "$DEMO_ROOT/manifests/00-namespaces.yaml" >/dev/null

echo "==> applying quota"
kubectl apply -f "$DEMO_ROOT/manifests/10-quota.yaml" >/dev/null

echo "==> applying RBAC (agent SA + scoped role)"
kubectl apply -f "$DEMO_ROOT/manifests/20-rbac.yaml" >/dev/null

echo "==> applying production workload"
kubectl apply -f "$DEMO_ROOT/manifests/30-workloads.yaml" >/dev/null

echo "==> applying ValidatingAdmissionPolicy"
kubectl apply -f "$DEMO_ROOT/manifests/40-vap-production-guard.yaml" >/dev/null

echo "==> waiting for production model-server (120s)"
kubectl -n production wait --for=condition=Available deployment/model-server --timeout=120s

# ----- Agent token + agent kubeconfig (K8s SA JWT, NOT AWS creds) -----------
echo "==> issuing $TOKEN_TTL projected token for claude-agent"
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

# ----- Hydrate IaC repo ------------------------------------------------------
echo "==> hydrating .local/iac-repo from template"
rm -rf "$DEMO_LOCAL/iac-repo"
cp -r "$DEMO_ROOT/iac-repo-template" "$DEMO_LOCAL/iac-repo"

pushd "$DEMO_LOCAL/iac-repo" >/dev/null
git init -q
# IMPORTANT: override any global core.hooksPath setting. Without this, a host
# global hooks dir silently bypasses the per-repo pre-commit hook and Beat 2
# fails to fire on stage.
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

# ----- Claude Code settings (best-effort) -----------------------------------
if [[ -d "$HOME/.claude" ]]; then
  sed "s|\$DEMO_ROOT|$DEMO_ROOT|g" "$DEMO_ROOT/claude-hooks/settings.json" \
    > "$HOME/.claude/llmday-demo-settings.json"
  echo "    (info) wrote $HOME/.claude/llmday-demo-settings.json (reference)"
fi

# ----- Verification ----------------------------------------------------------
echo ""
echo "==> verification"

verify_pass() { echo "    ✅ $1"; }
verify_fail() { echo "    ❌ $1" >&2; FAIL=1; }
FAIL=0

# Cluster active
status=$(aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" \
  --query 'cluster.status' --output text)
if [[ "$status" == "ACTIVE" ]]; then
  verify_pass "EKS cluster $CLUSTER_NAME status: ACTIVE"
else
  verify_fail "EKS cluster $CLUSTER_NAME status: $status"
fi

# Audit logging
audit=$(aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" \
  --query 'cluster.logging.clusterLogging[?contains(types, `audit`)].enabled' --output text)
if [[ "$audit" == "True" ]]; then
  verify_pass "audit logging is enabled (CloudWatch)"
else
  verify_fail "audit logging not enabled"
fi

# Agent can edit in staging
if [[ "$(kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" auth can-i delete deployments -n staging 2>/dev/null)" == "yes" ]]; then
  verify_pass "agent has delete on deployments in staging (intentionally over-scoped)"
else
  verify_fail "agent missing delete on deployments in staging"
fi

# Agent can read production
if [[ "$(kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" auth can-i get deployments -n production 2>/dev/null)" == "yes" ]]; then
  verify_pass "agent can read production (needed for Beat 1)"
else
  verify_fail "agent cannot read production"
fi

# VAP exists
if kubectl get validatingadmissionpolicy deny-agent-writes-to-production >/dev/null 2>&1; then
  verify_pass "VAP deny-agent-writes-to-production exists"
else
  verify_fail "VAP missing"
fi

# Layer 1 standalone
if bash "$DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh" < "$DEMO_ROOT/dialogue/beat1-toolcall.json" 2>/dev/null; then
  verify_fail "Layer 1 hook should have denied (exit 2)"
else
  rc=$?
  if [[ $rc -eq 2 ]]; then
    verify_pass "Layer 1 hook denies kubectl-vs-prod with exit 2"
  else
    verify_fail "Layer 1 hook returned $rc (expected 2)"
  fi
fi

# Layer 2 standalone
if (
  cd "$DEMO_LOCAL/iac-repo"
  sed -i 's|model-server:v1.2.0|model-server:v1.3.0|' infrastructure/production/model-server.yaml
  git add infrastructure/production/model-server.yaml
  git -c user.email=claude-agent@anthropic.local -c user.name=claude-agent \
    commit -m "test" 2>/dev/null
) ; then
  verify_fail "Layer 2 hook should have denied the commit"
else
  verify_pass "Layer 2 hook rejects non-human committer on protected path"
  (cd "$DEMO_LOCAL/iac-repo" && git checkout -- infrastructure/production/model-server.yaml && git reset HEAD >/dev/null)
fi

# Layer 3 standalone (live VAP check)
tmp_yaml="$DEMO_LOCAL/.verify-prod-update.yaml"
cat > "$tmp_yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: verify-canary
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: verify-canary
  template:
    metadata:
      labels:
        app: verify-canary
    spec:
      containers:
      - name: c
        image: nginxinc/nginx-unprivileged:1.27-alpine
YAML
if kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" apply -f "$tmp_yaml" 2>/dev/null; then
  verify_fail "Layer 3 VAP should have denied the apply"
else
  verify_pass "Layer 3 VAP denies agent SA writes to production"
fi
rm -f "$tmp_yaml"

echo ""
if [[ $FAIL -eq 1 ]]; then
  echo "==> setup FAILED — fix the ❌ items above" >&2
  exit 1
fi
echo "==> setup complete"
echo ""
echo "Run:    bash $DEMO_ROOT/demo.sh"
echo "Reset:  bash $DEMO_ROOT/reset.sh"
echo "Tear:   bash $DEMO_ROOT/teardown.sh   (deletes the EKS cluster — only after the talk)"
