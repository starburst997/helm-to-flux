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

# Generate HelmRelease
cat <<EOF > output/$RELEASE-helmrelease.yaml
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
$(helm get values $RELEASE -n $NAMESPACE | sed 's/^/    /')
EOF