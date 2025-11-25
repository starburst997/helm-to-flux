# Helm to Flux Migrator

A streamlined tool to help migrate existing Helm releases in Kubernetes clusters to FluxCD GitOps-managed HelmReleases.

## Overview

This project provides automated scripts to extract your current Helm deployments and convert them into FluxCD HelmRelease manifests, following GitOps best practices. It's designed for teams transitioning from traditional Helm deployments to a GitOps workflow with FluxCD.

## Features

- 🔄 **Automatic Conversion**: Extracts all Helm releases from your cluster and converts them to FluxCD HelmRelease format
- 📁 **Best Practice Structure**: Generates output following FluxCD's recommended directory structure
- 🎯 **Selective Migration**: Convert specific releases or bulk migrate all releases at once
- 🔧 **Values Preservation**: Maintains your custom Helm values during migration
- 📦 **Repository Generation**: Creates corresponding HelmRepository resources for each release
- 🤖 **AI-Powered Repository Detection**: Uses Claude AI to find official Helm chart repositories when not detected from FluxCD
- 📊 **Export & Compare**: Export all manifests and compare deployments before/after changes
- 🔍 **Manifest Extraction**: Automatically extracts Kubernetes manifests when repository is unknown

## Prerequisites

- Kubernetes cluster with existing Helm releases
- `helm` CLI installed and configured
- `kubectl` access to your cluster
- `jq` for JSON processing
- `yq` for YAML processing (value comparison) - [Installation Guide](https://github.com/mikefarah/yq)
- `claude` CLI (optional, for AI-powered repository detection) - [Installation Guide](https://docs.anthropic.com/en/docs/developer-tools/claude-cli)
- FluxCD v2 installed in your cluster (or planning to install)

## Installation

```bash
git clone https://github.com/yourusername/helm-to-flux
cd helm-to-flux
chmod +x *.sh
```

## Usage

### Convert a Single Release

```bash
./convert.sh [OPTIONS] <RELEASE_NAME> <NAMESPACE>
```

Options:

- `--cluster CLUSTER_NAME`: Name of the cluster (default: `my_cluster`)
- `--output-dir OUTPUT_DIR`: Root output directory (default: `clusters`)
- `--allow-overwrite`: Allow overwriting existing files (default: disabled)

Example:

```bash
./convert.sh ingress-nginx ingress-nginx
./convert.sh --cluster production --output-dir my-gitops ingress-nginx ingress-nginx
```

### Convert All Releases

```bash
./all.sh [OPTIONS]
```

Options:

- `--cluster CLUSTER_NAME`: Name of the cluster (default: `my_cluster`)
- `--output-dir OUTPUT_DIR`: Root output directory (default: `clusters`)
- `--allow-overwrite`: Allow overwriting existing files (default: disabled)

Example:

```bash
./all.sh
./all.sh --cluster production --output-dir my-gitops
```

This will automatically discover and convert all Helm releases across all namespaces.

## Utility Scripts

### Export All Manifests

Export raw Kubernetes manifests for all Helm releases without converting to FluxCD format. Useful for backup, comparison, or debugging.

```bash
./export-all.sh [OUTPUT_DIR]
```

- `OUTPUT_DIR`: Output directory (default: `export`)

Example:

```bash
./export-all.sh                    # Export to ./export/
./export-all.sh backup-20250113    # Export to ./backup-20250113/
```

The script extracts all manifests from every Helm release and organizes them by namespace and release name:

```
export/
├── cert-manager/
│   └── cert-manager/
│       ├── deployment-cert-manager.yaml
│       ├── service-cert-manager.yaml
│       └── ...
└── ingress-nginx/
    └── ingress-nginx/
        ├── deployment-ingress-nginx-controller.yaml
        └── ...
```

### Compare Exports

Compare two export directories to identify differences between deployments. Perfect for:
- Validating FluxCD deployments match original Helm deployments
- Detecting configuration drift
- Reviewing changes before/after upgrades

```bash
./compare-exports.sh <EXPORT_DIR_1> <EXPORT_DIR_2>
```

Example:

```bash
# Export before changes
./export-all.sh export-before

# Make changes to your cluster
helm upgrade myapp ...

# Export after changes
./export-all.sh export-after

# Compare
./compare-exports.sh export-before export-after
```

The script provides:
- List of identical releases
- List of releases with differences (including number of changed files and lines)
- Releases only in one export
- Exit code 0 if identical, 1 if different

Sample output:

```
[cert-manager/cert-manager] IDENTICAL
[ingress-nginx/ingress-nginx] DIFFERENT (2 files, ~15 lines)

SUMMARY
Identical releases: 5
Different releases: 1
```

## Output Structure

The tool generates a FluxCD-compatible directory structure following GitOps best practices:

```
clusters/
├── my_cluster/                          # Cluster-specific Kustomizations
│   ├── infrastructure/
│   │   ├── ingress-nginx.yaml           # Kustomization for ingress-nginx
│   │   └── cert-manager.yaml            # Kustomization for cert-manager
│   └── apps/
│       ├── myapp.yaml                   # Kustomization for myapp
│       └── another-app.yaml             # Kustomization for another-app
└── resources/
    └── my_cluster/
        ├── infrastructure/
        │   ├── ingress-nginx/
        │   │   └── helm.yaml             # HelmRepository + HelmRelease
        │   └── cert-manager/
        │       └── helm.yaml             # HelmRepository + HelmRelease
        └── apps/
            ├── myapp/
            │   └── helm.yaml             # HelmRepository + HelmRelease
            └── another-app/
                ├── helm.yaml             # HelmRelease (with UNKNOWN repo)
                ├── deployment-another-app.yaml  # Extracted manifest
                └── service-another-app.yaml     # Extracted manifest
```

### Directory Organization

- **`clusters/<cluster>/`**: Contains Kustomization resources that FluxCD monitors

  - **`infrastructure/`**: Kustomizations for infrastructure components
  - **`apps/`**: Kustomizations for applications

- **`clusters/resources/<cluster>/`**: Contains the actual Kubernetes manifests
  - **`<type>/<name>/helm.yaml`**: HelmRepository + HelmRelease in a single file (separated by `---`)
  - **`<type>/<name>/*.yaml`**: Individual Kubernetes manifests (when repository is unknown)

Each Kustomization in `clusters/<cluster>/` points to its corresponding resources in `clusters/resources/<cluster>/` via the `path` specification.

### Repository Detection

The tool intelligently handles Helm repository detection:

1. **FluxCD HelmRelease Found**: Extracts the original repository URL and configuration
2. **Claude CLI Search**: If not found via FluxCD, uses Claude AI to search for the official repository
3. **Unknown Repository**: If no official source is found, the HelmRelease is created with `UNKNOWN` sourceRef and all Kubernetes manifests are extracted as individual files for manual recreation

When a repository cannot be determined, manifests are extracted directly into the resource folder alongside `helm.yaml`.

## Generated Resources

### Kustomization Example

Each release gets a Kustomization that tells FluxCD where to find its resources:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  dependsOn:
    - name: secrets
  interval: 3m
  retryInterval: 2m
  timeout: 5m
  wait: true
  path: "./clusters/resources/my_cluster/infrastructure/ingress-nginx"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### HelmRepository + HelmRelease Example

Located at `clusters/resources/<cluster>/<type>/<name>/helm.yaml` (both resources in one file):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 30m
  url: https://kubernetes.github.io/ingress-nginx
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 5m
  targetNamespace: ingress-nginx
  install:
    createNamespace: true
  chart:
    spec:
      chart: ingress-nginx
      version: ">=4.0.0"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: ingress-nginx
      interval: 1m
  upgrade:
    remediation:
      remediateLastFailure: true
  test:
    enable: true
  values:
    controller:
      service:
        type: LoadBalancer
    # ... your custom values
```

Note: The HelmRepository is in the **same namespace** as the HelmRelease for better organization and isolation.

## Integration with FluxCD

After generating the manifests:

1. **Review Generated Files**: Inspect the output directory to ensure configurations are correct

2. **Commit to Git Repository**:

   ```bash
   # If you generated directly in your GitOps repo
   cd /path/to/your-flux-repo
   git add clusters/
   git commit -m "Migrate Helm releases to FluxCD"
   git push
   ```

3. **Configure Flux to Monitor the Repository** (if not already done):

   ```bash
   flux create source git flux-system \
     --url=https://github.com/yourusername/your-flux-repo \
     --branch=main \
     --interval=1m
   ```

   Note: Each `helm.yaml` file contains both the HelmRepository and HelmRelease, so FluxCD will automatically create the repository before deploying the release.

## Migration Strategy

### Recommended Approach

1. **Test in Development**: Run the migration in a development cluster first

   ```bash
   ./all.sh --cluster dev
   ```

2. **Gradual Migration**: For production, migrate one release at a time

   ```bash
   ./convert.sh --cluster production ingress-nginx ingress-nginx
   ```

3. **Review Generated Files**: Check the Kustomizations and HelmReleases before committing

   ```bash
   # Review the generated structure
   tree clusters/
   # Review individual files
   cat clusters/production/infrastructure/ingress-nginx.yaml
   cat clusters/resources/production/infrastructure/ingress-nginx/helm.yaml
   ```

4. **Commit and Push**: Add to your GitOps repository

   ```bash
   git add clusters/
   git commit -m "Add ingress-nginx FluxCD configuration"
   git push
   ```

5. **Verify State**: Ensure FluxCD successfully reconciles each release

   ```bash
   flux get kustomizations
   flux get helmreleases -A
   ```

6. **Clean Up**: Once verified, remove the original Helm releases
   ```bash
   helm uninstall <RELEASE_NAME> -n <NAMESPACE>
   ```

### Important Considerations

- **Overwrite Protection**: By default, the tool won't overwrite existing files. Use `--allow-overwrite` to force updates
- **FluxCD Takeover**: FluxCD will adopt and manage existing resources without recreating them
- **No Downtime**: The migration process is designed to be seamless with no service interruption
- **Dependencies**: The generated Kustomizations include a `dependsOn` for secrets - adjust as needed
- **Backup**: Back up your cluster state before migration
- **Review**: Always review and adjust the generated configurations based on your needs

## Troubleshooting

### Common Issues

**Missing Chart Information**

- Ensure Helm repositories are up-to-date: `helm repo update`

**Invalid YAML Output**

- Check if the Helm release has complex values that need manual adjustment

**FluxCD Reconciliation Fails**

- Verify the HelmRepository URL is accessible
- Check that the chart version exists in the repository
- Review FluxCD controller logs: `flux logs -f`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- FluxCD team for their excellent GitOps toolkit
- Kubernetes SIG-Apps for Helm
- Community contributors

## Support

For issues, questions, or suggestions, please open an issue on GitHub.
