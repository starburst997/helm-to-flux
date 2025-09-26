#!/bin/bash

# Check if arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <RELEASE> <NAMESPACE>"
    exit 1
fi

RELEASE="$1"
NAMESPACE="$2"

# Create output directory if it doesn't exist
mkdir -p output

# Get release info
CHART=$(helm list -n $NAMESPACE -o json | jq -r ".[] | select(.name==\"$RELEASE\") | .chart")
REPO_URL=$(helm show chart $CHART 2>/dev/null | grep -E "^home:" | cut -d' ' -f2 | sed 's|/[^/]*$||')

# Get helm values, excluding the USER-SUPPLIED VALUES header
VALUES=$(helm get values $RELEASE -n $NAMESPACE | grep -v "^USER-SUPPLIED VALUES:$")

# Generate HelmRelease
if [ -z "$VALUES" ] || [ "$VALUES" = "null" ]; then
  # No custom values, generate without values section
  cat > output/$RELEASE-helmrelease.yaml <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $RELEASE
  namespace: $NAMESPACE
spec:
  interval: 30m
  chart:
    spec:
      chart: $(echo $CHART | cut -d'-' -f1-2)
      version: "$(echo $CHART | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$')"
      sourceRef:
        kind: HelmRepository
        name: $RELEASE
        namespace: flux-system
  install:
    createNamespace: true
EOF
else
  # Has custom values, include them
  cat > output/$RELEASE-helmrelease.yaml <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $RELEASE
  namespace: $NAMESPACE
spec:
  interval: 30m
  chart:
    spec:
      chart: $(echo $CHART | cut -d'-' -f1-2)
      version: "$(echo $CHART | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$')"
      sourceRef:
        kind: HelmRepository
        name: $RELEASE
        namespace: flux-system
  install:
    createNamespace: true
  values:
$(echo "$VALUES" | sed 's/^/    /')
EOF
fi