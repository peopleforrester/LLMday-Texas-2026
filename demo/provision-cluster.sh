#!/usr/bin/env bash
# ABOUTME: One-time EKS Auto Mode provisioning for the LLMday demo.
# ABOUTME: Run once tonight on Megumi. Takes ~15 minutes. Get coffee.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
REGION="${AWS_REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-llmday-demo}"
K8S_VERSION="${K8S_VERSION:-1.33}"
AWS_PROFILE_FLAG=""
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_PROFILE_FLAG="--profile $AWS_PROFILE"
fi

echo "==> LLMday demo: EKS Auto Mode provisioning"
echo "    DEMO_ROOT=$DEMO_ROOT"
echo "    REGION=$REGION"
echo "    CLUSTER_NAME=$CLUSTER_NAME"
echo "    K8S_VERSION=$K8S_VERSION"
echo "    AWS_PROFILE=${AWS_PROFILE:-default}"
echo ""

# ----- Prerequisites ---------------------------------------------------------
for cmd in aws eksctl kubectl helm jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not on PATH" >&2
    exit 1
  fi
done

# Verify AWS auth
if ! aws sts get-caller-identity $AWS_PROFILE_FLAG --region "$REGION" >/dev/null 2>&1; then
  echo "ERROR: 'aws sts get-caller-identity' failed. Configure AWS credentials first." >&2
  exit 1
fi

mkdir -p "$DEMO_LOCAL"

# ----- If cluster already exists, refuse to clobber --------------------------
if aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "==> cluster '$CLUSTER_NAME' already exists in $REGION."
  echo "    skipping cluster create; will refresh metadata, audit logging, and Helm charts."
  CLUSTER_EXISTS=1
else
  CLUSTER_EXISTS=0
fi

# ----- Create cluster --------------------------------------------------------
if [[ $CLUSTER_EXISTS -eq 0 ]]; then
  echo "==> creating EKS Auto Mode cluster (12-15 min)"
  eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --version "$K8S_VERSION" \
    --enable-auto-mode \
    --with-oidc \
    --tags "Project=llmday-austin,Owner=mforrester,Ephemeral=true"
fi

# ----- Enable audit logging to CloudWatch -----------------------------------
echo "==> enabling audit + authenticator log export to CloudWatch"
aws eks update-cluster-config $AWS_PROFILE_FLAG \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --logging '{"clusterLogging":[{"types":["audit","authenticator"],"enabled":true}]}' \
  >/dev/null || echo "    (info) logging may already be enabled; that's fine"

aws eks wait cluster-active $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME"

# ----- Cache cluster metadata -----------------------------------------------
aws eks describe-cluster $AWS_PROFILE_FLAG --region "$REGION" --name "$CLUSTER_NAME" \
  > "$DEMO_LOCAL/cluster-info.json"

# ----- Wire kubectl to the cluster (operator context for Helm installs) -----
aws eks update-kubeconfig $AWS_PROFILE_FLAG \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --kubeconfig "$DEMO_LOCAL/operator-kubeconfig"
export KUBECONFIG="$DEMO_LOCAL/operator-kubeconfig"

# ----- Install observability add-ons via Helm -------------------------------
echo "==> installing Falco (Helm)"
helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  -f "$DEMO_ROOT/manifests/observability/falco-values.yaml" \
  --wait --timeout 5m

echo "==> installing OpenTelemetry collector (Helm)"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update >/dev/null
helm repo update >/dev/null
helm upgrade --install otel open-telemetry/opentelemetry-collector \
  --namespace otel --create-namespace \
  -f "$DEMO_ROOT/manifests/observability/otel-values.yaml" \
  --wait --timeout 5m

# ----- Summary --------------------------------------------------------------
echo ""
echo "==> provisioning complete"
echo "    Cluster:  $CLUSTER_NAME (region $REGION, version $K8S_VERSION)"
echo "    Auto Mode: enabled"
echo "    Audit logging: enabled (CloudWatch)"
echo "    Falco:    helm release 'falco' in namespace 'falco'"
echo "    OTel:     helm release 'otel'  in namespace 'otel'"
echo ""
echo "Next step:  bash $DEMO_ROOT/setup.sh"
