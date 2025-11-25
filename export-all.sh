#!/bin/bash

# Default output directory
OUTPUT_DIR="export"

# Parse arguments
if [ $# -gt 0 ]; then
    OUTPUT_DIR="$1"
fi

echo "Exporting all Helm release manifests to: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temp files for counters (to persist across subshell)
STATS_FILE=$(mktemp)
echo "0 0 0" > "$STATS_FILE"  # TOTAL_RELEASES TOTAL_MANIFESTS FAILED_RELEASES

# Get all Helm releases
while read name ns; do
    # Read current stats
    read TOTAL_RELEASES TOTAL_MANIFESTS FAILED_RELEASES < "$STATS_FILE"
    TOTAL_RELEASES=$((TOTAL_RELEASES + 1))

    echo "===================="
    echo "Exporting: $name (namespace: $ns)"

    # Create release directory
    RELEASE_DIR="$OUTPUT_DIR/$ns/$name"
    mkdir -p "$RELEASE_DIR"

    # Get the manifest and split into separate files
    helm get manifest "$name" -n "$ns" > "$RELEASE_DIR/all-manifests.yaml" 2>/dev/null

    if [ -f "$RELEASE_DIR/all-manifests.yaml" ] && [ -s "$RELEASE_DIR/all-manifests.yaml" ]; then
        # Split manifests using a simple shell loop
        resource_num=1
        current_file=""
        while IFS= read -r line || [ -n "$line" ]; do
            if [ "$line" = "---" ]; then
                if [ ! -z "$current_file" ]; then
                    resource_num=$((resource_num + 1))
                fi
                current_file="$RELEASE_DIR/resource-$(printf '%03d' $resource_num).yaml"
                continue
            fi
            if [ ! -z "$current_file" ]; then
                echo "$line" >> "$current_file"
            fi
        done < "$RELEASE_DIR/all-manifests.yaml"

        # Remove the combined file
        rm -f "$RELEASE_DIR/all-manifests.yaml"

        # Remove empty files
        find "$RELEASE_DIR" -type f -size 0 -delete 2>/dev/null || true

        # Rename files based on their content (kind and name)
        for file in "$RELEASE_DIR"/resource-*.yaml; do
            if [ -f "$file" ]; then
                # Extract kind and name from the YAML
                KIND=$(grep -m 1 "^kind:" "$file" | awk '{print tolower($2)}' | tr -d '\r' | tr -d '\n')
                NAME=$(grep -m 1 "^  name:" "$file" | awk '{print $2}' | tr -d '\r' | tr -d '\n')

                if [ ! -z "$KIND" ] && [ ! -z "$NAME" ]; then
                    NEW_NAME="$RELEASE_DIR/${KIND}-${NAME}.yaml"
                    mv "$file" "$NEW_NAME" 2>/dev/null || true
                    echo "  Extracted: ${KIND}-${NAME}.yaml"
                fi
            fi
        done

        # Clean up any remaining numbered files
        rm -f "$RELEASE_DIR"/resource-*.yaml 2>/dev/null || true

        MANIFEST_COUNT=$(find "$RELEASE_DIR" -type f -name "*.yaml" | wc -l | tr -d ' ')
        TOTAL_MANIFESTS=$((TOTAL_MANIFESTS + MANIFEST_COUNT))

        if [ "$MANIFEST_COUNT" -gt 0 ]; then
            echo "  Exported $MANIFEST_COUNT manifest(s)"
        else
            echo "  Warning: No manifests were extracted"
            FAILED_RELEASES=$((FAILED_RELEASES + 1))
        fi
    else
        echo "  Warning: Could not extract manifests (no manifest data)"
        FAILED_RELEASES=$((FAILED_RELEASES + 1))
        rm -rf "$RELEASE_DIR"
    fi

    # Save updated stats
    echo "$TOTAL_RELEASES $TOTAL_MANIFESTS $FAILED_RELEASES" > "$STATS_FILE"

    echo ""
done < <(helm list -A -o json | jq -r '.[] | "\(.name) \(.namespace)"')

# Read final stats
read TOTAL_RELEASES TOTAL_MANIFESTS FAILED_RELEASES < "$STATS_FILE"
rm -f "$STATS_FILE"

echo "===================="
echo "Export complete!"
echo "  Output directory: $OUTPUT_DIR"
echo "  Total releases processed: $TOTAL_RELEASES"
echo "  Total manifests extracted: $TOTAL_MANIFESTS"
if [ "$FAILED_RELEASES" -gt 0 ]; then
    echo "  Failed releases: $FAILED_RELEASES"
fi
