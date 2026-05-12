#!/usr/bin/env bash
# ABOUTME: v4.7 provisioning: EKS Auto Mode + managed node group, then ArgoCD only.
# ABOUTME: Everything else flows from GitOps via the root Application.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
REGION="${AWS_REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-llmday-demo}"
K8S_VERSION="${K8S_VERSION:-1.35}"
AWS_PROFILE_FLAG=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE_FLAG="--profile $AWS_PROFILE"
fi

mkdir -p "$DEMO_LOCAL"
exec > >(tee -a "$DEMO_LOCAL/provision.log") 2>&1

echo "==> [1/3] LLMday demo v4.7: EKS Auto Mode + managed node group"
echo "    DEMO_ROOT=$DEMO_ROOT"
echo "    REGION=$REGION CLUSTER=$CLUSTER_NAME VERSION=$K8S_VERSION"
echo ""

# ----- Prerequisites ---------------------------------------------------------
for cmd in aws eksctl kubectl helm git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not on PATH" >&2
    exit 1
  fi
done

if ! aws sts get-caller-identity $AWS_PROFILE_FLAG --region "$REGION" >/dev/null 2>&1; then
  echo "ERROR: AWS credentials not valid" >&2
  exit 1
fi

# ----- Cluster create (or reuse) --------------------------------------------
if aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "==> cluster $CLUSTER_NAME already exists; skipping create"
else
  echo "==> creating cluster (~12 min)"
  eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --version "$K8S_VERSION" \
    --enable-auto-mode \
    --with-oidc \
    --nodegroup-name platform-nodes \
    --node-type t3.large \
    --nodes 2 \
    --nodes-min 2 \
    --nodes-max 2 \
    --node-ami-family Bottlerocket \
    --tags "Project=llmday-austin,Owner=mforrester,Ephemeral=true"
fi

echo "==> enabling audit + authenticator log export to CloudWatch"
aws eks update-cluster-config $AWS_PROFILE_FLAG \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --logging '{"clusterLogging":[{"types":["audit","authenticator"],"enabled":true}]}' \
  >/dev/null || echo "    (info) logging may already be enabled"

aws eks wait cluster-active $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME"
aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" > "$DEMO_LOCAL/cluster-info.json"

# Operator kubeconfig (uses AWS creds)
aws eks update-kubeconfig $AWS_PROFILE_FLAG \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --kubeconfig "$DEMO_LOCAL/operator-kubeconfig" >/dev/null
chmod 600 "$DEMO_LOCAL/operator-kubeconfig"
export KUBECONFIG="$DEMO_LOCAL/operator-kubeconfig"

# ----- ArgoCD only (everything else is GitOps) ------------------------------
echo "==> [2/3] installing ArgoCD (the only Helm install)"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f "$DEMO_ROOT/gitops/values/argocd-bootstrap-values.yaml" \
  --wait --timeout 10m

kubectl -n argocd wait --for=condition=Available --timeout=5m \
  deployment/argocd-server deployment/argocd-repo-server \
  deployment/argocd-applicationset-controller 2>/dev/null \
  || kubectl -n argocd wait --for=condition=Available --timeout=5m \
       deployment/argocd-server deployment/argocd-repo-server

# ----- Bootstrap the GitOps tree --------------------------------------------
echo "==> [3/3] applying root Application; ArgoCD takes over from here"
kubectl apply -f "$DEMO_ROOT/gitops/bootstrap/root-app.yaml"

echo ""
echo "==> provisioning script complete"
echo "    cluster: $CLUSTER_NAME (region $REGION, v$K8S_VERSION)"
echo "    ArgoCD installed and reconciling root-app."
echo ""
echo "Watch sync:  kubectl --kubeconfig $DEMO_LOCAL/operator-kubeconfig get applications -n argocd -w"
echo "Next step:   bash $DEMO_ROOT/setup.sh    (waits for Healthy+Synced, then sets up demo state)"
