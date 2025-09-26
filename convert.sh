#!/bin/bash

# Check if arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <RELEASE> <NAMESPACE>"
    exit 1
fi

RELEASE="$1"
NAMESPACE="$2"

# List of infrastructure/system namespaces
INFRASTRUCTURE_NAMESPACES="kube-system kube-public kube-node-lease flux-system cert-manager ingress-nginx monitoring logging istio-system linkerd"

# Determine if this is infrastructure or app
IS_INFRASTRUCTURE=false
for ns in $INFRASTRUCTURE_NAMESPACES; do
    if [[ "$NAMESPACE" == "$ns" ]] || [[ "$NAMESPACE" == *"ingress"* ]] || [[ "$NAMESPACE" == *"cert-manager"* ]] || [[ "$NAMESPACE" == *"monitoring"* ]]; then
        IS_INFRASTRUCTURE=true
        break
    fi
done

# Set output paths based on type
if [ "$IS_INFRASTRUCTURE" = true ]; then
    HELMRELEASE_DIR="output/infrastructure/controllers/$RELEASE"
    REPO_DIR="output/infrastructure/sources/helm"
else
    HELMRELEASE_DIR="output/apps/$NAMESPACE/$RELEASE"
    REPO_DIR="output/infrastructure/sources/helm"
fi

# Create output directories
mkdir -p "$HELMRELEASE_DIR"
mkdir -p "$REPO_DIR"

echo "Processing $RELEASE in namespace $NAMESPACE..."

# Get release info
CHART=$(helm list -n $NAMESPACE -o json | jq -r ".[] | select(.name==\"$RELEASE\") | .chart")
if [ -z "$CHART" ]; then
    echo "Error: Release $RELEASE not found in namespace $NAMESPACE"
    exit 1
fi

# Extract chart name and version
CHART_NAME=$(echo $CHART | sed 's/-[0-9]*\.[0-9]*\.[0-9]*$//')
CHART_VERSION=$(echo $CHART | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$')

# Try to get repository URL from helm
REPO_URL=""
REPO_NAME=""

# First, try to find the repo from helm repo list
HELM_REPOS=$(helm repo list -o json 2>/dev/null || echo "[]")
if [ "$HELM_REPOS" != "[]" ]; then
    # Try to match by chart name
    for repo in $(echo "$HELM_REPOS" | jq -r '.[].name'); do
        CHARTS_IN_REPO=$(helm search repo "$repo/" -o json 2>/dev/null | jq -r ".[].name" | cut -d'/' -f2)
        if echo "$CHARTS_IN_REPO" | grep -q "^$CHART_NAME$"; then
            REPO_NAME="$repo"
            REPO_URL=$(echo "$HELM_REPOS" | jq -r ".[] | select(.name==\"$repo\") | .url")
            break
        fi
    done
fi

# If we couldn't find the repo, try to get it from the chart
if [ -z "$REPO_URL" ]; then
    # Try to get the home URL from the chart (less reliable but better than nothing)
    CHART_INFO=$(helm show chart "$REPO_NAME/$CHART_NAME" 2>/dev/null || helm show chart "$CHART_NAME" 2>/dev/null)
    if [ ! -z "$CHART_INFO" ]; then
        HOME_URL=$(echo "$CHART_INFO" | grep "^home:" | sed 's/^home: *//')
        if [ ! -z "$HOME_URL" ]; then
            # Try to derive repo URL from home URL (heuristic)
            case "$HOME_URL" in
                *github.com/kubernetes/ingress-nginx*)
                    REPO_URL="https://kubernetes.github.io/ingress-nginx"
                    ;;
                *github.com/jetstack/cert-manager*)
                    REPO_URL="https://charts.jetstack.io"
                    ;;
                *github.com/prometheus-community*)
                    REPO_URL="https://prometheus-community.github.io/helm-charts"
                    ;;
                *github.com/grafana/helm-charts*)
                    REPO_URL="https://grafana.github.io/helm-charts"
                    ;;
                *)
                    # Generic GitHub pages pattern
                    if [[ "$HOME_URL" =~ github.com/([^/]+)/([^/]+) ]]; then
                        OWNER="${BASH_REMATCH[1]}"
                        REPO="${BASH_REMATCH[2]}"
                        REPO_URL="https://$OWNER.github.io/$REPO"
                    fi
                    ;;
            esac
        fi
    fi
fi

# Use release name as repository name if we don't have one
if [ -z "$REPO_NAME" ]; then
    REPO_NAME="$RELEASE"
fi

# Generate HelmRepository resource if we have a URL
if [ ! -z "$REPO_URL" ]; then
    cat > "$REPO_DIR/$REPO_NAME-repository.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: $REPO_NAME
  namespace: flux-system
spec:
  interval: 30m
  url: $REPO_URL
EOF
    echo "Created HelmRepository: $REPO_DIR/$REPO_NAME-repository.yaml"
else
    echo "Warning: Could not determine repository URL for $RELEASE. You'll need to create the HelmRepository manually."
    REPO_NAME="$RELEASE"  # Use release name as a placeholder
fi

# Get helm values, excluding the USER-SUPPLIED VALUES header
VALUES=$(helm get values $RELEASE -n $NAMESPACE | grep -v "^USER-SUPPLIED VALUES:$")

# Generate HelmRelease
if [ -z "$VALUES" ] || [ "$VALUES" = "null" ]; then
  # No custom values, generate without values section
  cat > "$HELMRELEASE_DIR/helmrelease.yaml" <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $RELEASE
  namespace: $NAMESPACE
spec:
  interval: 30m
  chart:
    spec:
      chart: $CHART_NAME
      version: "$CHART_VERSION"
      sourceRef:
        kind: HelmRepository
        name: $REPO_NAME
        namespace: flux-system
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  test:
    enable: true
  rollback:
    timeout: 10m
    recreate: true
    cleanupOnFail: true
EOF
else
  # Has custom values, include them
  cat > "$HELMRELEASE_DIR/helmrelease.yaml" <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $RELEASE
  namespace: $NAMESPACE
spec:
  interval: 30m
  chart:
    spec:
      chart: $CHART_NAME
      version: "$CHART_VERSION"
      sourceRef:
        kind: HelmRepository
        name: $REPO_NAME
        namespace: flux-system
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  test:
    enable: true
  rollback:
    timeout: 10m
    recreate: true
    cleanupOnFail: true
  values:
$(echo "$VALUES" | sed 's/^/    /')
EOF
fi

echo "Created HelmRelease: $HELMRELEASE_DIR/helmrelease.yaml"
echo "Conversion complete for $RELEASE"