#!/bin/bash

# Default values
CLUSTER_NAME="my_cluster"
OUTPUT_ROOT="clusters"
ALLOW_OVERWRITE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --allow-overwrite)
            ALLOW_OVERWRITE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [--cluster CLUSTER_NAME] [--output-dir OUTPUT_DIR] [--allow-overwrite] <RELEASE> <NAMESPACE>"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check if release and namespace are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 [--cluster CLUSTER_NAME] [--output-dir OUTPUT_DIR] [--allow-overwrite] <RELEASE> <NAMESPACE>"
    echo ""
    echo "Options:"
    echo "  --cluster CLUSTER_NAME     Name of the cluster (default: my_cluster)"
    echo "  --output-dir OUTPUT_DIR    Root output directory (default: clusters)"
    echo "  --allow-overwrite          Allow overwriting existing files (default: false)"
    echo ""
    echo "Arguments:"
    echo "  RELEASE                    Helm release name"
    echo "  NAMESPACE                  Kubernetes namespace"
    exit 1
fi

RELEASE="$1"
NAMESPACE="$2"

# List of infrastructure/system namespaces
INFRASTRUCTURE_NAMESPACES="external-secrets kube-system kube-public kube-node-lease flux-system cert-manager ingress-nginx monitoring logging istio-system linkerd"

# Determine if this is infrastructure or app
IS_INFRASTRUCTURE=false
for ns in $INFRASTRUCTURE_NAMESPACES; do
    if [[ "$NAMESPACE" == "$ns" ]] || [[ "$NAMESPACE" == *"-system"* ]] || [[ "$NAMESPACE" == *"ingress"* ]] || [[ "$NAMESPACE" == *"cert-manager"* ]] || [[ "$NAMESPACE" == *"monitoring"* ]]; then
        IS_INFRASTRUCTURE=true
        break
    fi
done

# Set output paths based on type
if [ "$IS_INFRASTRUCTURE" = true ]; then
    RESOURCE_TYPE="infrastructure"
else
    RESOURCE_TYPE="apps"
fi

# Define directory structure (using RELEASE for now, will update after detecting FluxCD name)
KUSTOMIZATION_DIR="$OUTPUT_ROOT/$CLUSTER_NAME/$RESOURCE_TYPE"

# Create output directories (RESOURCE_DIR will be created later after we know the final name)
mkdir -p "$KUSTOMIZATION_DIR"

echo "Processing $RELEASE in namespace $NAMESPACE..."
echo "  Type: $RESOURCE_TYPE"
echo "  Cluster: $CLUSTER_NAME"

# Get release info
CHART=$(helm list -n $NAMESPACE -o json | jq -r ".[] | select(.name==\"$RELEASE\") | .chart")
if [ -z "$CHART" ]; then
    echo "Error: Release $RELEASE not found in namespace $NAMESPACE"
    exit 1
fi

# Check if this release was deployed by FluxCD and extract original metadata
FLUXCD_HELMRELEASE=""
FLUXCD_CHART_NAME=""
FLUXCD_VERSION_SPEC=""
FLUXCD_REPO_NAME=""
FLUXCD_REPO_NAMESPACE=""

# Try to find the FluxCD HelmRelease
if command -v kubectl &> /dev/null; then
    # First check if the release name exists as a HelmRelease in the same namespace
    FLUXCD_HELMRELEASE=$(kubectl get helmrelease "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null || echo "")

    # If not found, check for HelmRelease that matches by spec.releaseName
    if [ -z "$FLUXCD_HELMRELEASE" ] || [ "$FLUXCD_HELMRELEASE" = "" ]; then
        FLUXCD_HELMRELEASE=$(kubectl get helmrelease -A -o json 2>/dev/null | jq -r --arg release "$RELEASE" --arg ns "$NAMESPACE" '.items[] | select(.metadata.namespace == $ns and (.spec.releaseName // .metadata.name) == $release)' 2>/dev/null | head -1 || echo "")
    fi

    # If still not found, try to find by stripping the namespace suffix from release name
    # FluxCD sometimes creates releases with pattern: <helmrelease-name>-<namespace>
    if [ -z "$FLUXCD_HELMRELEASE" ] || [ "$FLUXCD_HELMRELEASE" = "" ]; then
        # Try removing -namespace suffix
        POSSIBLE_HELMRELEASE_NAME=$(echo "$RELEASE" | sed "s/-$NAMESPACE$//")
        if [ "$POSSIBLE_HELMRELEASE_NAME" != "$RELEASE" ]; then
            FLUXCD_HELMRELEASE=$(kubectl get helmrelease "$POSSIBLE_HELMRELEASE_NAME" -n "$NAMESPACE" -o json 2>/dev/null || echo "")
        fi
    fi

    if [ ! -z "$FLUXCD_HELMRELEASE" ] && [ "$FLUXCD_HELMRELEASE" != "" ]; then
        FLUXCD_CHART_NAME=$(echo "$FLUXCD_HELMRELEASE" | jq -r '.spec.chart.spec.chart' 2>/dev/null || echo "")
        FLUXCD_VERSION_SPEC=$(echo "$FLUXCD_HELMRELEASE" | jq -r '.spec.chart.spec.version' 2>/dev/null || echo "")
        FLUXCD_REPO_NAME=$(echo "$FLUXCD_HELMRELEASE" | jq -r '.spec.chart.spec.sourceRef.name' 2>/dev/null || echo "")
        FLUXCD_REPO_NAMESPACE=$(echo "$FLUXCD_HELMRELEASE" | jq -r '.spec.chart.spec.sourceRef.namespace' 2>/dev/null || echo "")
        FLUXCD_HELMRELEASE_NAME=$(echo "$FLUXCD_HELMRELEASE" | jq -r '.metadata.name' 2>/dev/null || echo "")

        echo "  Found FluxCD HelmRelease: $FLUXCD_HELMRELEASE_NAME"
        echo "  Chart: $FLUXCD_CHART_NAME, Version: $FLUXCD_VERSION_SPEC"
    fi
fi

# Extract chart name and version from helm
# The chart field is like "chartname-1.2.3", we need to extract the name without version
CHART_VERSION_FROM_HELM=$(echo $CHART | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$')

# Use FluxCD chart name if available, otherwise extract from chart string
if [ ! -z "$FLUXCD_CHART_NAME" ]; then
    CHART_NAME="$FLUXCD_CHART_NAME"
else
    # Try to get chart name from helm chart metadata
    HELM_SECRET_CHART_NAME=$(kubectl get secret -n "$NAMESPACE" -l owner=helm,name="$RELEASE" -o json 2>/dev/null | jq -r '.items[0].data.release' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null | jq -r '.chart.metadata.name' 2>/dev/null || echo "")

    if [ ! -z "$HELM_SECRET_CHART_NAME" ] && [ "$HELM_SECRET_CHART_NAME" != "null" ]; then
        CHART_NAME="$HELM_SECRET_CHART_NAME"
        echo "  Extracted chart name from Helm secret: $CHART_NAME"
    else
        # Fallback to removing version from chart string
        CHART_NAME=$(echo $CHART | sed 's/-[0-9]*\.[0-9]*\.[0-9]*$//')
    fi
fi

# Use FluxCD version spec if available, otherwise use the deployed version
if [ ! -z "$FLUXCD_VERSION_SPEC" ] && [ "$FLUXCD_VERSION_SPEC" != "null" ]; then
    CHART_VERSION="$FLUXCD_VERSION_SPEC"
else
    CHART_VERSION="$CHART_VERSION_FROM_HELM"
fi

echo "  Chart: $CHART_NAME"
echo "  Version: $CHART_VERSION"

# Determine the HelmRelease name to use
# If we found a FluxCD HelmRelease, use its name; otherwise use the Helm release name
HELMRELEASE_NAME="$RELEASE"
if [ ! -z "$FLUXCD_HELMRELEASE_NAME" ] && [ "$FLUXCD_HELMRELEASE_NAME" != "null" ]; then
    HELMRELEASE_NAME="$FLUXCD_HELMRELEASE_NAME"
    echo "  Using HelmRelease name: $HELMRELEASE_NAME (from FluxCD)"
fi

# Now that we know the final HelmRelease name, set the resource directory
RESOURCE_DIR="$OUTPUT_ROOT/resources/$CLUSTER_NAME/$RESOURCE_TYPE/$HELMRELEASE_NAME"
mkdir -p "$RESOURCE_DIR"

# Try to get repository URL and name
REPO_URL=""
REPO_NAME=""

# If we have FluxCD repository info, try to get the URL from the HelmRepository
if [ ! -z "$FLUXCD_REPO_NAME" ] && [ "$FLUXCD_REPO_NAME" != "null" ]; then
    REPO_NAME="$FLUXCD_REPO_NAME"

    # Try to get the HelmRepository URL
    if [ ! -z "$FLUXCD_REPO_NAMESPACE" ] && [ "$FLUXCD_REPO_NAMESPACE" != "null" ]; then
        REPO_URL=$(kubectl get helmrepository "$FLUXCD_REPO_NAME" -n "$FLUXCD_REPO_NAMESPACE" -o json 2>/dev/null | jq -r '.spec.url' 2>/dev/null || echo "")

        if [ ! -z "$REPO_URL" ] && [ "$REPO_URL" != "null" ]; then
            echo "  Found repository from FluxCD: $REPO_NAME ($REPO_URL)"
        fi
    fi
fi

# If we still don't have repository info, use Claude CLI to find the official source
if [ -z "$REPO_URL" ] || [ "$REPO_URL" = "" ]; then
    echo "  Searching for official Helm chart repository using Claude CLI..."

    if command -v claude &> /dev/null; then
        # Use Claude to search for the official repository
        CLAUDE_PROMPT="Search the internet for the official Helm chart repository for the chart named '$CHART_NAME' version '$CHART_VERSION'. I need the exact Helm repository URL (not the GitHub repo, but the actual Helm chart repository URL like https://charts.example.com). Please respond with ONLY the repository URL if found, or 'NOT_FOUND' if you cannot find an official source. Do not include any explanation, just the URL or NOT_FOUND."

        CLAUDE_RESPONSE=$(echo "$CLAUDE_PROMPT" | claude --model sonnet 2>/dev/null | tr -d '\n\r' | xargs)

        if [ ! -z "$CLAUDE_RESPONSE" ] && [ "$CLAUDE_RESPONSE" != "NOT_FOUND" ] && [[ "$CLAUDE_RESPONSE" =~ ^https?:// ]]; then
            REPO_URL="$CLAUDE_RESPONSE"
            # Extract a reasonable repo name from the URL (e.g., charts.jetstack.io -> jetstack)
            REPO_NAME=$(echo "$REPO_URL" | sed -E 's|https?://||' | sed 's|/.*||' | sed 's/^charts\.//' | sed 's/\.io$//' | sed 's/\.com$//' | sed 's/\.github\.io$//' | sed 's/\./-/g')
            echo "  Found official repository via Claude: $REPO_NAME ($REPO_URL)"
        else
            echo "  Could not find official repository for $CHART_NAME"
            REPO_URL="UNKNOWN"
            REPO_NAME="UNKNOWN"
        fi
    else
        echo "  Warning: Claude CLI not available, cannot search for official repository"
        REPO_URL="UNKNOWN"
        REPO_NAME="UNKNOWN"
    fi
fi

# Function to check if file exists and skip if overwrite not allowed
check_file_exists() {
    local filepath="$1"
    if [ -f "$filepath" ] && [ "$ALLOW_OVERWRITE" = false ]; then
        echo "  Skipping: $filepath (already exists)"
        return 0  # File exists, skip
    fi
    return 1  # File doesn't exist or overwrite allowed
}

# Determine the namespace for the HelmRepository
# Use the same namespace as the HelmRelease (not FluxCD's namespace)
HELM_REPO_NAMESPACE="$NAMESPACE"

# We'll add the HelmRepository to the helm.yaml file directly, so just prepare the variables
if [ "$REPO_URL" = "UNKNOWN" ]; then
    echo "  Warning: Could not determine repository URL for $RELEASE. HelmRelease will have UNKNOWN sourceRef."
    REPO_NAME="UNKNOWN"
elif [ -z "$REPO_URL" ]; then
    echo "  Warning: Could not determine repository URL for $RELEASE. You'll need to create the HelmRepository manually."
    REPO_NAME="${HELMRELEASE_NAME}-repo"  # Use a placeholder name
else
    echo "  Repository: $REPO_NAME in namespace $HELM_REPO_NAMESPACE"
fi

# Get helm values, excluding the USER-SUPPLIED VALUES header
USER_VALUES=$(helm get values $RELEASE -n $NAMESPACE | grep -v "^USER-SUPPLIED VALUES:$")

# Filter out default values by comparing YAML structures
VALUES=""

if [ -z "$USER_VALUES" ] || [ "$USER_VALUES" = "null" ]; then
    # No user values at all
    VALUES=""
    echo "  No custom values found (using all defaults)"
else
    # We have user values - need to check if they're just defaults or actual customizations
    if [ "$REPO_URL" != "UNKNOWN" ] && [ ! -z "$REPO_URL" ] && [ ! -z "$REPO_NAME" ] && [ ! -z "$CHART_NAME" ]; then
        echo "  Comparing values with chart defaults to filter out redundant values..."

        # Check if yq and jq are available
        if ! command -v yq &> /dev/null || ! command -v jq &> /dev/null; then
            echo "  Warning: yq or jq not available, including all user values"
            VALUES="$USER_VALUES"
        else
            # Create temporary directory and files
            TEMP_DIR=$(mktemp -d)
            TEMP_DEFAULT_VALUES="$TEMP_DIR/default-values.yaml"
            TEMP_USER_VALUES="$TEMP_DIR/user-values.yaml"

            # Add helm repo temporarily for comparison
            TEMP_REPO_NAME="temp-repo-$$-$(date +%s)"
            helm repo add "$TEMP_REPO_NAME" "$REPO_URL" 2>/dev/null || true
            helm repo update "$TEMP_REPO_NAME" 2>/dev/null || true

            # Get default values from chart
            if helm show values "$TEMP_REPO_NAME/$CHART_NAME" --version "$CHART_VERSION" > "$TEMP_DEFAULT_VALUES" 2>/dev/null; then
                # Save user values
                echo "$USER_VALUES" > "$TEMP_USER_VALUES"

                # Convert YAML to JSON for comparison
                yq eval -o=json "$TEMP_DEFAULT_VALUES" > "$TEMP_DIR/default.json" 2>/dev/null
                yq eval -o=json "$TEMP_USER_VALUES" > "$TEMP_DIR/current.json" 2>/dev/null

                # Use jq to recursively compare and extract only differences
                jq --slurpfile defaults "$TEMP_DIR/default.json" --slurpfile current "$TEMP_DIR/current.json" -n '
                    def remove_empty:
                        if type == "object" then
                            with_entries(select(.value != {} and .value != [] and .value != null and .value != ""))
                            | with_entries(.value |= remove_empty)
                            | if . == {} then empty else . end
                        elif type == "array" then
                            map(remove_empty)
                            | if . == [] then empty else . end
                        else
                            .
                        end;

                    def diff($default; $current):
                        if ($default | type) != ($current | type) then
                            $current
                        elif ($default | type) == "object" then
                            reduce ($current | to_entries[]) as $item ({};
                                if ($default | has($item.key)) then
                                    if ($default[$item.key] == $item.value) then
                                        .
                                    else
                                        (diff($default[$item.key]; $item.value)) as $subdiff |
                                        if $subdiff != null and $subdiff != {} and $subdiff != [] then
                                            . + {($item.key): $subdiff}
                                        else
                                            .
                                        end
                                    end
                                else
                                    . + {($item.key): $item.value}
                                end
                            )
                        elif $default == $current then
                            empty
                        else
                            $current
                        end;

                    diff($defaults[0]; $current[0]) | remove_empty // {}
                ' > "$TEMP_DIR/diff.json" 2>/dev/null

                # Convert back to YAML
                if [ -s "$TEMP_DIR/diff.json" ]; then
                    DIFF_CONTENT=$(cat "$TEMP_DIR/diff.json")
                    if [ "$DIFF_CONTENT" = "{}" ] || [ "$DIFF_CONTENT" = "null" ]; then
                        VALUES=""
                        echo "  Values are identical to defaults - omitting values section"
                    else
                        VALUES=$(yq eval '.' -P -o=yaml "$TEMP_DIR/diff.json" 2>/dev/null)
                        if [ -z "$VALUES" ]; then
                            echo "  Warning: Could not extract differences, including all user values"
                            VALUES="$USER_VALUES"
                        else
                            echo "  Found custom values that differ from defaults - including only differences"
                        fi
                        # Filter out */managed-by keys
                        if [ ! -z "$VALUES" ]; then
                            VALUES=$(echo "$VALUES" | yq eval 'del(.. | select(has("managed-by")).managed-by)' 2>/dev/null || echo "$VALUES")
                        fi
                    fi
                else
                    VALUES=""
                    echo "  Values are identical to defaults - omitting values section"
                fi
            else
                echo "  Warning: Could not fetch default values for comparison, including all user values"
                VALUES="$USER_VALUES"
                # Filter out */managed-by keys
                if [ ! -z "$VALUES" ]; then
                    VALUES=$(echo "$VALUES" | yq eval 'del(.. | select(has("managed-by")).managed-by)' 2>/dev/null || echo "$VALUES")
                fi
            fi

            # Cleanup
            helm repo remove "$TEMP_REPO_NAME" 2>/dev/null || true
            rm -rf "$TEMP_DIR"
        fi
    else
        # Can't compare without repo info, include all user values
        echo "  Warning: Cannot compare with defaults (no repository info), including all user values"
        VALUES="$USER_VALUES"
        # Filter out */managed-by keys
        if [ ! -z "$VALUES" ]; then
            VALUES=$(echo "$VALUES" | yq eval 'del(.. | select(has("managed-by")).managed-by)' 2>/dev/null || echo "$VALUES")
        fi
    fi
fi

# Generate Kustomization file for this release
KUSTOMIZATION_FILE="$KUSTOMIZATION_DIR/$HELMRELEASE_NAME.yaml"
if ! check_file_exists "$KUSTOMIZATION_FILE"; then
    cat > "$KUSTOMIZATION_FILE" <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: $HELMRELEASE_NAME
  namespace: flux-system
spec:
  dependsOn:
    - name: secrets
  interval: 3m
  retryInterval: 2m
  timeout: 5m
  wait: true
  path: "./clusters/resources/$CLUSTER_NAME/$RESOURCE_TYPE/$HELMRELEASE_NAME"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
EOF
    echo "  Created Kustomization: $KUSTOMIZATION_FILE"
fi

# Generate HelmRelease
#
# Old defaults:
# install:
#    createNamespace: true
#    remediation:
#      retries: 3
#  upgrade:
#    cleanupOnFail: true
#    remediation:
#      retries: 3
#  test:
#    enable: true
#  rollback:
#    timeout: 10m
#    recreate: true
#    cleanupOnFail: true
#
HELM_RELEASE_FILE="$RESOURCE_DIR/helm.yaml"
if check_file_exists "$HELM_RELEASE_FILE"; then
    echo "  Skipped HelmRelease (already exists)"
elif [ -z "$VALUES" ] || [ "$VALUES" = "null" ]; then
  # No custom values, generate without values section
  if [ "$REPO_NAME" = "UNKNOWN" ]; then
    cat > "$HELM_RELEASE_FILE" <<EOF
# NOTE: Could not determine the Helm repository for this chart.
# Please update the sourceRef below with the correct HelmRepository.
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $HELMRELEASE_NAME
  namespace: $NAMESPACE
spec:
  interval: 5m
  targetNamespace: $NAMESPACE
  install:
    createNamespace: true
  chart:
    spec:
      chart: $CHART_NAME
      version: "$CHART_VERSION"
      sourceRef:
        kind: HelmRepository
        name: UNKNOWN  # TODO: Replace with actual HelmRepository name
        namespace: $HELM_REPO_NAMESPACE
      interval: 1m
  upgrade:
    remediation:
      remediateLastFailure: true
  test:
    enable: true
EOF
  else
    # Include HelmRepository at the top of the file
    cat > "$HELM_RELEASE_FILE" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: $REPO_NAME
  namespace: $HELM_REPO_NAMESPACE
spec:
  interval: 30m
  url: $REPO_URL
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $HELMRELEASE_NAME
  namespace: $NAMESPACE
spec:
  interval: 5m
  targetNamespace: $NAMESPACE
  install:
    createNamespace: true
  chart:
    spec:
      chart: $CHART_NAME
      version: "$CHART_VERSION"
      sourceRef:
        kind: HelmRepository
        name: $REPO_NAME
        namespace: $HELM_REPO_NAMESPACE
      interval: 1m
  upgrade:
    remediation:
      remediateLastFailure: true
  test:
    enable: true
EOF
  fi
  echo "  Created HelmRelease: $HELM_RELEASE_FILE"
else
  # Has custom values, include them
  if [ "$REPO_NAME" = "UNKNOWN" ]; then
    cat > "$HELM_RELEASE_FILE" <<EOF
# NOTE: Could not determine the Helm repository for this chart.
# Please update the sourceRef below with the correct HelmRepository.
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $HELMRELEASE_NAME
  namespace: $NAMESPACE
spec:
  interval: 5m
  targetNamespace: $NAMESPACE
  install:
    createNamespace: true
  chart:
    spec:
      chart: $CHART_NAME
      version: "$CHART_VERSION"
      sourceRef:
        kind: HelmRepository
        name: UNKNOWN  # TODO: Replace with actual HelmRepository name
        namespace: $HELM_REPO_NAMESPACE
      interval: 1m
  upgrade:
    remediation:
      remediateLastFailure: true
  test:
    enable: true
  values:
$(echo "$VALUES" | sed 's/^/    /')
EOF
  else
    # Include HelmRepository at the top of the file
    cat > "$HELM_RELEASE_FILE" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: $REPO_NAME
  namespace: $HELM_REPO_NAMESPACE
spec:
  interval: 30m
  url: $REPO_URL
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $HELMRELEASE_NAME
  namespace: $NAMESPACE
spec:
  interval: 5m
  targetNamespace: $NAMESPACE
  install:
    createNamespace: true
  chart:
    spec:
      chart: $CHART_NAME
      version: "$CHART_VERSION"
      sourceRef:
        kind: HelmRepository
        name: $REPO_NAME
        namespace: $HELM_REPO_NAMESPACE
      interval: 1m
  upgrade:
    remediation:
      remediateLastFailure: true
  test:
    enable: true
  values:
$(echo "$VALUES" | sed 's/^/    /')
EOF
  fi
  echo "  Created HelmRelease: $HELM_RELEASE_FILE"
fi

# If repository is UNKNOWN, extract all manifests as individual files in the resource folder
if [ "$REPO_NAME" = "UNKNOWN" ]; then
    echo ""
    echo "  Extracting manifests as individual files (repository unknown)..."

    # Get the manifest and split into separate files directly in RESOURCE_DIR
    helm get manifest "$RELEASE" -n "$NAMESPACE" > "$RESOURCE_DIR/all-manifests.yaml" 2>/dev/null

    if [ -f "$RESOURCE_DIR/all-manifests.yaml" ] && [ -s "$RESOURCE_DIR/all-manifests.yaml" ]; then
        # Split manifests using a simple shell loop
        resource_num=1
        current_file=""
        while IFS= read -r line || [ -n "$line" ]; do
            if [ "$line" = "---" ]; then
                if [ ! -z "$current_file" ]; then
                    resource_num=$((resource_num + 1))
                fi
                current_file="$RESOURCE_DIR/resource-$(printf '%03d' $resource_num).yaml"
                continue
            fi
            if [ ! -z "$current_file" ]; then
                echo "$line" >> "$current_file"
            fi
        done < "$RESOURCE_DIR/all-manifests.yaml"

        # Remove the combined file
        rm -f "$RESOURCE_DIR/all-manifests.yaml"

        # Remove empty files
        find "$RESOURCE_DIR" -type f -size 0 -delete 2>/dev/null || true

        # Rename files based on their content (kind and name)
        for file in "$RESOURCE_DIR"/resource-*.yaml; do
            if [ -f "$file" ]; then
                # Extract kind and name from the YAML
                KIND=$(grep -m 1 "^kind:" "$file" | awk '{print tolower($2)}' | tr -d '\r' | tr -d '\n')
                NAME=$(grep -m 1 "^  name:" "$file" | awk '{print $2}' | tr -d '\r' | tr -d '\n')

                if [ ! -z "$KIND" ] && [ ! -z "$NAME" ]; then
                    NEW_NAME="$RESOURCE_DIR/${KIND}-${NAME}.yaml"
                    mv "$file" "$NEW_NAME" 2>/dev/null || true
                    echo "    Extracted: ${KIND}-${NAME}.yaml"
                fi
            fi
        done

        # Clean up any remaining numbered files
        rm -f "$RESOURCE_DIR"/resource-*.yaml 2>/dev/null || true

        MANIFEST_COUNT=$(find "$RESOURCE_DIR" -type f -name "*.yaml" ! -name "helm.yaml" | wc -l | tr -d ' ')
        if [ "$MANIFEST_COUNT" -gt 0 ]; then
            echo "  Extracted $MANIFEST_COUNT manifest file(s) to resource folder"
        else
            echo "  Warning: No manifests were extracted"
        fi
    else
        echo "  Warning: Could not extract manifests (no manifest data)"
    fi
fi

echo ""
echo "Conversion complete for $RELEASE!"
echo "  Kustomization: $KUSTOMIZATION_FILE"
echo "  HelmRelease: $HELM_RELEASE_FILE"
if [ "$REPO_NAME" = "UNKNOWN" ]; then
    echo "  Note: Manifests extracted to resource folder (repository unknown)"
fi