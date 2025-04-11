#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipelines | Ensures that the exit status of the last command that threw a non-zero exit code is returned.
set -o pipefail

# --- Configuration ---
# Define namespace for Argo CD (use environment variable or default)
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Define Argo CD Helm chart version to ensure reproducibility
ARGOCD_CHART_VERSION="7.8.23"  # Find latest stable version for argo-cd chart

ARGOCD_HELM_REPO="https://argoproj.github.io/argo-helm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helper Functions ---
ensure_namespace() {
  local ns=$1
  echo "Ensuring namespace '$ns' exists..."
  # Use dry-run and apply to make namespace creation idempotent
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

add_helm_repo() {
    local name=$1
    local url=$2
    echo "Adding Helm repo '$name' from '$url'..."
    if ! helm repo list | grep -q "^${name}\s"; then
        helm repo add "$name" "$url"
    else
        echo "Helm repo '$name' already exists."
    fi
}
# --- End Helper Functions ---

# 1. Add Argo CD Helm Repository
add_helm_repo "argo" "$ARGOCD_HELM_REPO"

echo "Updating Helm repositories..."
helm repo update "argo"

# 2. Ensure Argo CD Namespace Exists
ensure_namespace "$ARGOCD_NAMESPACE"

# 3. Install/Upgrade Argo CD using Helm
echo "Installing/Upgrading Argo CD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE" \
  --version "$ARGOCD_CHART_VERSION" \
  --values ${SCRIPT_DIR}/install/argocd-values.yaml \
  --wait --timeout 10m
echo "Argo CD installed/upgraded successfully."

# Example: Get initial Argo CD admin password (if not configured via values)
ARGO_PASS=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)
echo "#########################################################################"
echo "######### Fetching initial Argo CD admin password: $ARGO_PASS ###########"
echo "#########################################################################"

echo "Creating Argo CD Application for Tekton..."
kubectl apply -n $ARGOCD_NAMESPACE -f ${SCRIPT_DIR}/apps/tekton-app.yaml
echo "Creating Argo CD ApplicationSets..."
kubectl apply -n $ARGOCD_NAMESPACE -f ${SCRIPT_DIR}/appsets/github-token.yaml
kubectl apply -n $ARGOCD_NAMESPACE -f ${SCRIPT_DIR}/appsets/appset.yaml
echo "Creating Argo CD Application for CI Pipelines..."
TEKTON_PIPELINES_NAMESPACE="${TEKTON_PIPELINES_NAMESPACE:-tekton-pipelines}"
counter=0
while ! kubectl wait --for=condition=Available --all deployments \
  -n ${TEKTON_PIPELINES_NAMESPACE} --timeout=2m; do
    echo "waiting for Tekton to be online... attempt $((++counter))"
    sleep 1
done
kubectl apply -n $ARGOCD_NAMESPACE -f ${SCRIPT_DIR}/apps/tekton-ci-pipelines.yaml