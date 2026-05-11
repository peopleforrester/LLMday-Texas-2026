#!/usr/bin/env bash
# ABOUTME: One-shot bootstrap for the LLMday demo: cluster, manifests, kubeconfig, iac-repo.
# ABOUTME: All paths repo-relative via $DEMO_ROOT; ephemeral artifacts written to .local/.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
CLUSTER_NAME="llmday-demo"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.35.4-k3s1}"
TOKEN_TTL="${TOKEN_TTL:-1h}"

echo "==> LLMday demo setup"
echo "    DEMO_ROOT=$DEMO_ROOT"
echo "    DEMO_LOCAL=$DEMO_LOCAL"
echo "    cluster=$CLUSTER_NAME image=$K3S_IMAGE token-ttl=$TOKEN_TTL"
echo ""

# ----- Prerequisites ---------------------------------------------------------
for cmd in k3d kubectl git jq awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not on PATH" >&2
    exit 1
  fi
done

# ----- Clean ephemeral state -------------------------------------------------
echo "==> resetting $DEMO_LOCAL"
rm -rf "$DEMO_LOCAL"
mkdir -p "$DEMO_LOCAL"

# ----- Cluster ---------------------------------------------------------------
echo "==> creating k3d cluster '$CLUSTER_NAME'"
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
k3d cluster create "$CLUSTER_NAME" \
  --image "$K3S_IMAGE" \
  --no-lb \
  --k3s-arg "--disable=traefik@server:0" \
  --k3s-arg "--disable=servicelb@server:0" \
  --volume "$DEMO_ROOT/manifests/audit-policy.yaml:/etc/rancher/k3s/audit-policy.yaml@server:0" \
  --k3s-arg "--kube-apiserver-arg=audit-log-path=/var/log/k8s-audit.log@server:0" \
  --k3s-arg "--kube-apiserver-arg=audit-policy-file=/etc/rancher/k3s/audit-policy.yaml@server:0"

# ----- Manifests -------------------------------------------------------------
echo "==> applying namespaces"
kubectl apply -f "$DEMO_ROOT/manifests/00-namespaces.yaml"

echo "==> applying quota"
kubectl apply -f "$DEMO_ROOT/manifests/10-quota.yaml"

echo "==> applying RBAC (agent SA + scoped role)"
kubectl apply -f "$DEMO_ROOT/manifests/20-rbac.yaml"

echo "==> applying production workloads"
kubectl apply -f "$DEMO_ROOT/manifests/30-workloads.yaml"

echo "==> applying VAP production guard"
kubectl apply -f "$DEMO_ROOT/manifests/40-vap-production-guard.yaml"

echo "==> applying observability (OTel; Falco best-effort)"
kubectl apply -f "$DEMO_ROOT/manifests/observability/otel-collector.yaml"
# Falco may fail on WSL2 or hosts without bpf/kernel-headers. Don't block setup.
kubectl apply -f "$DEMO_ROOT/manifests/observability/falco-daemonset.yaml" || \
  echo "    (warn) Falco apply failed; demo does not depend on Falco firing."

# ----- Wait for workloads ----------------------------------------------------
echo "==> waiting for production model-server (30s)"
kubectl -n production wait --for=condition=Available deployment/model-server --timeout=30s || true

# ----- Agent token + kubeconfig ---------------------------------------------
echo "==> issuing 1h projected token for claude-agent"
kubectl -n staging create token claude-agent \
  --duration "$TOKEN_TTL" \
  --audience https://kubernetes.default.svc > "$DEMO_LOCAL/agent-token"
chmod 600 "$DEMO_LOCAL/agent-token"

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

# ----- Hydrate IaC repo ------------------------------------------------------
echo "==> hydrating .local/iac-repo from template"
cp -r "$DEMO_ROOT/iac-repo-template" "$DEMO_LOCAL/iac-repo"

pushd "$DEMO_LOCAL/iac-repo" >/dev/null
git init -q
# IMPORTANT: override any global core.hooksPath setting (the host may
# have a global hooks directory configured for other repos). Without
# this, the iac-repo's pre-commit hook is silently bypassed and Beat 2
# of the demo fails to fire.
git config core.hooksPath ".git/hooks"
git config user.email "platform-team@example.com"
git config user.name  "platform-team"
git config commit.gpgsign false 2>/dev/null || true

# Install the pre-commit hook
mkdir -p .git/hooks
cp "$DEMO_LOCAL/iac-repo/hooks/pre-commit" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

git add .
git commit -q -m "initial state: model v1.2.0 in production"
popd >/dev/null

# ----- Verification ----------------------------------------------------------
echo ""
echo "==> verification"

verify_pass() { echo "    ✅ $1"; }
verify_fail() { echo "    ❌ $1" >&2; FAIL=1; }
FAIL=0

# Cluster up
if kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" get nodes >/dev/null 2>&1; then
  verify_pass "kubeconfig works"
else
  verify_fail "kubeconfig does not authenticate"
fi

# Agent can edit in staging
if [[ "$(kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" auth can-i delete deployments -n staging 2>/dev/null)" == "yes" ]]; then
  verify_pass "agent has delete on deployments in staging (intentionally over-scoped)"
else
  verify_fail "agent missing delete on deployments in staging"
fi

# Agent CAN read production (per RBAC)
if [[ "$(kubectl --kubeconfig="$DEMO_LOCAL/kubeconfig" auth can-i get deployments -n production 2>/dev/null)" == "yes" ]]; then
  verify_pass "agent can read production (needed for Beat 1's initial list)"
else
  verify_fail "agent cannot read production"
fi

# VAP exists
if kubectl get validatingadmissionpolicy deny-agent-writes-to-production >/dev/null 2>&1; then
  verify_pass "VAP deny-agent-writes-to-production exists"
else
  verify_fail "VAP missing"
fi

# Layer 1 standalone test
if bash "$DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh" < "$DEMO_ROOT/dialogue/beat1-toolcall.json" 2>/dev/null; then
  verify_fail "Layer 1 hook should have denied (exit 2) but returned 0"
else
  rc=$?
  if [[ $rc -eq 2 ]]; then
    verify_pass "Layer 1 hook denies kubectl-vs-production with exit 2"
  else
    verify_fail "Layer 1 hook returned $rc (expected 2)"
  fi
fi

# Layer 2 standalone test
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
  # Reset the test mutation
  (cd "$DEMO_LOCAL/iac-repo" && git checkout -- infrastructure/production/model-server.yaml && git reset HEAD)
fi

# Layer 3 standalone test (only if production has model-server)
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

# ----- Claude Code settings install (best-effort) ---------------------------
if [[ -d "$HOME/.claude" ]]; then
  # Inject DEMO_ROOT into the settings.json before writing
  sed "s|\$DEMO_ROOT|$DEMO_ROOT|g" "$DEMO_ROOT/claude-hooks/settings.json" \
    > "$HOME/.claude/llmday-demo-settings.json"
  echo "    (info) Wrote $HOME/.claude/llmday-demo-settings.json (reference; merge into settings.json if running Claude Code as the demo agent)"
fi

echo ""
if [[ $FAIL -eq 1 ]]; then
  echo "==> setup FAILED — fix the ❌ items above before running demo.sh" >&2
  exit 1
fi
echo "==> setup complete"
echo "    DEMO_ROOT=$DEMO_ROOT"
echo "    DEMO_LOCAL=$DEMO_LOCAL"
echo ""
echo "Run:    bash $DEMO_ROOT/demo.sh"
echo "Reset:  bash $DEMO_ROOT/reset.sh"
echo "Tear:   bash $DEMO_ROOT/teardown.sh"
