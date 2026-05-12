#!/usr/bin/env bash
# ABOUTME: v4.7 setup: wait for GitOps tree to sync, build kubeconfigs, hydrate iac-repo, verify.
# ABOUTME: Runs after provision-cluster.sh. ~15 min budget for full GitOps sync, then ~30s of demo state.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
REGION="${AWS_REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-llmday-demo}"
TOKEN_TTL="${TOKEN_TTL:-1h}"
SYNC_TIMEOUT="${SYNC_TIMEOUT:-1200}"   # 20 min by default
AWS_PROFILE_FLAG=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE_FLAG="--profile $AWS_PROFILE"
fi

echo "==> LLMday demo setup (v4.7, EKS, GitOps)"

# Prereqs
for cmd in aws kubectl git jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not on PATH" >&2; exit 1; }
done

# Cluster check
if ! aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "ERROR: cluster $CLUSTER_NAME not found. Run provision-cluster.sh first." >&2
  exit 1
fi

mkdir -p "$DEMO_LOCAL"

# Operator kubeconfig (AWS-creds-backed)
aws eks update-kubeconfig $AWS_PROFILE_FLAG \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --kubeconfig "$DEMO_LOCAL/operator-kubeconfig" >/dev/null
chmod 600 "$DEMO_LOCAL/operator-kubeconfig"
export KUBECONFIG="$DEMO_LOCAL/operator-kubeconfig"

# ----- Wait for ArgoCD apps to be Healthy + Synced --------------------------
echo "==> waiting for GitOps tree to be fully synced (timeout ${SYNC_TIMEOUT}s)"
START=$SECONDS
while [ $((SECONDS - START)) -lt "$SYNC_TIMEOUT" ]; do
  if ! kubectl -n argocd get applications >/dev/null 2>&1; then
    echo "   ArgoCD CRDs not yet available; waiting..."
    sleep 10
    continue
  fi
  TOTAL=$(kubectl -n argocd get applications -o name 2>/dev/null | wc -l)
  HEALTHY=$(kubectl -n argocd get applications -o jsonpath='{range .items[?(@.status.health.status=="Healthy")]}H{end}' 2>/dev/null | wc -c)
  SYNCED=$(kubectl -n argocd get applications -o jsonpath='{range .items[?(@.status.sync.status=="Synced")]}S{end}' 2>/dev/null | wc -c)

  UNHEALTHY=$(kubectl -n argocd get applications \
    -o jsonpath='{range .items[?(@.status.health.status!="Healthy")]}{.metadata.name}{" "}{end}' 2>/dev/null)
  UNSYNCED=$(kubectl -n argocd get applications \
    -o jsonpath='{range .items[?(@.status.sync.status!="Synced")]}{.metadata.name}{" "}{end}' 2>/dev/null)

  if [ -z "${UNHEALTHY// }" ] && [ -z "${UNSYNCED// }" ] && [ "$TOTAL" -gt 0 ]; then
    echo "✅ all $TOTAL Applications Healthy + Synced"
    break
  fi
  printf "   [t+%ds] total=%d healthy_chars=%d synced_chars=%d\n" \
    "$((SECONDS - START))" "$TOTAL" "$HEALTHY" "$SYNCED"
  [ -n "${UNHEALTHY// }" ] && echo "      unhealthy: $UNHEALTHY"
  [ -n "${UNSYNCED// }" ]  && echo "      unsynced:  $UNSYNCED"
  sleep 20
done

if [ $((SECONDS - START)) -ge "$SYNC_TIMEOUT" ]; then
  echo "ERROR: GitOps sync did not complete within ${SYNC_TIMEOUT}s. Check ArgoCD UI." >&2
  echo "       kubectl --kubeconfig=$DEMO_LOCAL/operator-kubeconfig -n argocd get applications" >&2
  exit 1
fi

# ----- Demo state -----------------------------------------------------------
echo "==> generating $TOKEN_TTL projected token for claude-agent"
TOKEN=$(kubectl -n staging create token claude-agent \
  --duration "$TOKEN_TTL" \
  --audience https://kubernetes.default.svc)
echo "$TOKEN" > "$DEMO_LOCAL/agent-token"
chmod 600 "$DEMO_LOCAL/agent-token"

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

echo "==> hydrating .local/iac-repo from template"
rm -rf "$DEMO_LOCAL/iac-repo"
cp -r "$DEMO_ROOT/iac-repo-template" "$DEMO_LOCAL/iac-repo"
pushd "$DEMO_LOCAL/iac-repo" >/dev/null
git init -q
git config core.hooksPath ".git/hooks"
git config user.email "platform-team@example.com"
git config user.name "platform-team"
git config commit.gpgsign false 2>/dev/null || true
mkdir -p .git/hooks
cp "$DEMO_LOCAL/iac-repo/hooks/pre-commit" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git add . && git commit -q -m "initial state: model v1.2.0 in production"
popd >/dev/null

# ----- Verification ---------------------------------------------------------
verify_pass() { echo "    ✅ $1"; }
verify_fail() { echo "    ❌ $1" >&2; FAIL=1; }
FAIL=0

echo ""
echo "==> verification"

# Agent RBAC
[[ "$(kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" auth can-i delete deployments -n staging 2>/dev/null)" == "yes" ]] \
  && verify_pass "agent has delete on deployments in staging (intentionally over-scoped)" \
  || verify_fail "agent missing delete on deployments in staging"

[[ "$(kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" auth can-i get deployments -n production 2>/dev/null)" == "yes" ]] \
  && verify_pass "agent can read production" \
  || verify_fail "agent cannot read production"

# Layer 1
if bash "$DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh" < "$DEMO_ROOT/dialogue/beat1-toolcall.json" 2>/dev/null; then
  verify_fail "Layer 1 hook should have denied (exit 2)"
else
  [[ $? -eq 2 ]] && verify_pass "Layer 1 hook denies with exit 2"
fi

# Layer 2 — fresh ephemeral repo
TESTREPO=$(mktemp -d)
(
  cd "$TESTREPO"
  git init -q
  git config core.hooksPath ".git/hooks"
  git config user.email "claude-agent@anthropic.local"
  git config user.name "claude-agent"
  cp "$DEMO_ROOT/iac-repo-template/hooks/pre-commit" .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  mkdir -p infrastructure/production
  echo ok > infrastructure/production/test.yaml
  git add .
  git commit -m "test" 2>/dev/null
)
if [ $? -eq 0 ]; then
  verify_fail "Layer 2 hook should have denied non-human commit"
else
  verify_pass "Layer 2 hook denies non-human committer on protected path"
fi
rm -rf "$TESTREPO"

# Layer 3 — live VAP
tmp="$DEMO_LOCAL/.verify-prod.yaml"
cat > "$tmp" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: verify-canary
  namespace: production
spec:
  replicas: 1
  selector: {matchLabels: {app: verify-canary}}
  template:
    metadata: {labels: {app: verify-canary, "app.kubernetes.io/name": verify, "app.kubernetes.io/version": v0}}
    spec:
      containers:
      - name: c
        image: nginxinc/nginx-unprivileged:1.27-alpine
        resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {cpu: 50m, memory: 64Mi}}
YAML
if kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" apply -f "$tmp" 2>/dev/null; then
  verify_fail "Layer 3 VAP should have denied agent SA apply to production"
else
  verify_pass "Layer 3 VAP denies agent SA writes to production"
fi
rm -f "$tmp"

# VAP exists
kubectl get validatingadmissionpolicy deny-agent-writes-to-production >/dev/null 2>&1 \
  && verify_pass "VAP deny-agent-writes-to-production exists" \
  || verify_fail "VAP missing"

# Kyverno policies
KYV_COUNT=$(kubectl get clusterpolicies -o name 2>/dev/null | wc -l)
[[ "$KYV_COUNT" -ge 6 ]] && verify_pass "Kyverno ClusterPolicies: $KYV_COUNT installed" \
  || verify_fail "Kyverno ClusterPolicies: only $KYV_COUNT (expected >= 6)"

# Model server
kubectl -n production get inferenceservice model-server >/dev/null 2>&1 \
  && verify_pass "KServe InferenceService model-server present in production" \
  || verify_fail "InferenceService model-server missing"

echo ""
if [[ $FAIL -eq 1 ]]; then
  echo "==> setup FAILED — fix the ❌ items above" >&2
  exit 1
fi
echo "==> setup complete"
echo "    Run:    bash $DEMO_ROOT/demo.sh"
echo "    Reset:  bash $DEMO_ROOT/reset.sh"
echo "    Tear:   bash $DEMO_ROOT/teardown.sh   (deletes the cluster — only after the talk)"
