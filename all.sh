#!/bin/bash

# Default values
CLUSTER_NAME="my_cluster"
OUTPUT_ROOT="clusters"
ALLOW_OVERWRITE_FLAG=""

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
            ALLOW_OVERWRITE_FLAG="--allow-overwrite"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--cluster CLUSTER_NAME] [--output-dir OUTPUT_DIR] [--allow-overwrite]"
            echo ""
            echo "Converts all Helm releases in the cluster to FluxCD HelmRelease format."
            echo ""
            echo "Options:"
            echo "  --cluster CLUSTER_NAME     Name of the cluster (default: my_cluster)"
            echo "  --output-dir OUTPUT_DIR    Root output directory (default: clusters)"
            echo "  --allow-overwrite          Allow overwriting existing files (default: false)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Converting all Helm releases to FluxCD format"
echo "  Cluster: $CLUSTER_NAME"
echo "  Output directory: $OUTPUT_ROOT"
echo "  Allow overwrite: ${ALLOW_OVERWRITE_FLAG:-false}"
echo ""

helm list -A -o json | jq -r '.[] | "\(.name) \(.namespace)"' | while read name ns; do
  echo "===================="
  echo "Extracting $name from $ns"
  ./convert.sh --cluster "$CLUSTER_NAME" --output-dir "$OUTPUT_ROOT" $ALLOW_OVERWRITE_FLAG "$name" "$ns"
  echo ""
done

echo "===================="
echo "All releases converted successfully!"
echo "Output directory: $OUTPUT_ROOT"