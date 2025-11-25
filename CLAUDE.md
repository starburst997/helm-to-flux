# Helm to Flux Migrator - Developer Guide

## Project Purpose

This is a tool for migrating existing Helm releases from a Kubernetes cluster to FluxCD GitOps-managed HelmReleases. The tool extracts deployed Helm releases and converts them into FluxCD-compatible manifests following best practices.

## Core Scripts

### Main Scripts

- **`convert.sh`**: Converts a single Helm release to FluxCD format

  - Extracts chart name, version, and repository URL
  - Detects if release was deployed by FluxCD and preserves metadata
  - Uses Claude CLI to find official Helm repositories when not detected
  - **IMPORTANT**: Should filter out default values and only include user-supplied custom values
  - Generates both Kustomization and HelmRelease+HelmRepository resources

- **`all.sh`**: Batch conversion of all Helm releases in the cluster
  - Iterates through all releases and calls `convert.sh` for each

### Utility Scripts

- **`export-all.sh`**: Exports raw Kubernetes manifests from all Helm releases (for backup/comparison)
- **`compare-exports.sh`**: Compares two export directories to detect differences

## Output Directory Structure

The tool follows FluxCD best practices with this structure:

```
clusters/
├── <cluster>/                         # Cluster-specific Kustomizations
│   ├── infrastructure/                # Infrastructure components
│   │   └── <release>.yaml             # Kustomization pointing to resources
│   └── apps/                          # Application releases
│       └── <release>.yaml             # Kustomization pointing to resources
└── resources/
    └── <cluster>/
        ├── infrastructure/
        │   └── <release>/
        │       └── helm.yaml          # HelmRepository + HelmRelease (in one file)
        └── apps/
            └── <release>/
                └── helm.yaml          # HelmRepository + HelmRelease (in one file)
```

## Key Features

### 1. Repository Detection

The tool uses a three-tier approach:

1. First checks if FluxCD HelmRelease exists and extracts repository info
2. If not found, uses Claude CLI to search for official Helm chart repository
3. If still not found, marks as "UNKNOWN" and extracts all manifests as individual files

### 2. Value Filtering (CRITICAL)

The tool MUST filter out default Helm chart values and only include user-supplied custom values in the generated `helm.yaml`. This keeps files concise and readable.

**How it should work:**

- Fetch default values from the chart using `helm show values`
- Fetch user-supplied values using `helm get values`
- Compare and extract only the differences
- Only include non-default values in the final HelmRelease

**Current Issue:** The value filtering in `convert.sh` (lines 239-397) may not be working correctly, as demonstrated by the `external-secrets` example which included 271 lines of default values.

**Reference Implementation:** See `test-external-secrets-values.sh` for a working example of proper value comparison using `helm template` to render and compare outputs.

### 3. Namespace Classification

Automatically categorizes releases as "infrastructure" or "apps" based on namespace patterns:

- Infrastructure: `kube-system`, `flux-system`, `cert-manager`, `external-secrets`, `ingress-*`, `*-system`, `monitoring`, etc.
- Apps: Everything else

## Important Implementation Details

### HelmRepository Namespace

HelmRepository resources are created in the **same namespace as the HelmRelease** (not in `flux-system`). This provides better organization and isolation.

### Single File Per Release

Each release has a single `helm.yaml` containing both HelmRepository and HelmRelease separated by `---`. This simplifies management.

### FluxCD Metadata Preservation

When a release was already deployed by FluxCD, the tool preserves the original:

- HelmRelease name
- Chart name and version spec
- Repository configuration

### Overwrite Protection

By default, the tool won't overwrite existing files. Use `--allow-overwrite` flag to force updates.

## Dependencies

- `helm` - Helm CLI
- `kubectl` - Kubernetes CLI
- `jq` - JSON processor
- `yq` - YAML processor (for value comparison)
- `claude` CLI - For AI-powered repository detection (optional)

## Common Issues

### Default Values Not Filtered

**Symptom:** Generated `helm.yaml` files contain hundreds of lines of default values.

**Cause:** The value comparison logic in `convert.sh` may not be comparing values correctly or fetching the wrong default values.

**Solution:** The comparison uses `yq` and `jq` to recursively compare YAML structures:

1. Add Helm repository temporarily
2. Fetch default values: `helm show values <repo>/<chart> --version <version>`
3. Extract current values: `helm get values <release> -n <namespace>`
4. Convert both to JSON using `yq`
5. Recursively compare using `jq` to extract only non-default values
6. Convert back to YAML for the final output
7. Only include values that differ from defaults

### Repository Detection Fails

**Symptom:** Release created with "UNKNOWN" repository and manifests extracted.

**Cause:** Chart repository not found in FluxCD resources or via Claude search.

**Solution:** Manually update the `sourceRef` in the generated `helm.yaml` or ensure the chart has an official public repository.

## Testing

To test value filtering for a specific release:

1. Run the test script pattern: `./test-external-secrets-values.sh`
2. Compare rendered output with/without values
3. Verify only actual differences are included

## Output Files to Ignore

As defined in `.gitignore`:

- `*.yaml` - Generated YAML files
- `clusters/`, `clusters_*/` - Output directories
- `output/`, `output_*/` - Legacy output directories
- `export/`, `export_*/` - Manifest export directories
- `*.txt` - Temporary comparison files

These are all generated outputs from running the conversion scripts during testing.
