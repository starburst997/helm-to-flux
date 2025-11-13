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

## Prerequisites

- Kubernetes cluster with existing Helm releases
- `helm` CLI installed and configured
- `kubectl` access to your cluster
- `jq` for JSON processing
- FluxCD v2 installed in your cluster (or planning to install)

## Installation

```bash
git clone https://github.com/yourusername/helm-to-flux
cd helm-to-flux
chmod +x convert.sh all.sh
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

## Output Structure

The tool generates a FluxCD-compatible directory structure following GitOps best practices:

```
clusters/
├── my_cluster/                          # Cluster-specific Kustomizations
│   ├── infrastructure/
│   │   ├── sources.yaml                 # Kustomization for HelmRepository sources
│   │   ├── ingress-nginx.yaml           # Kustomization for ingress-nginx
│   │   └── cert-manager.yaml            # Kustomization for cert-manager
│   └── apps/
│       ├── myapp.yaml                   # Kustomization for myapp
│       └── another-app.yaml             # Kustomization for another-app
└── resources/
    └── my_cluster/
        ├── infrastructure/
        │   ├── sources/
        │   │   ├── ingress-nginx.yaml   # HelmRepository resource
        │   │   └── cert-manager.yaml    # HelmRepository resource
        │   ├── ingress-nginx/
        │   │   └── helm.yaml             # HelmRelease for ingress-nginx
        │   └── cert-manager/
        │       └── helm.yaml             # HelmRelease for cert-manager
        └── apps/
            ├── myapp/
            │   └── helm.yaml             # HelmRelease for myapp
            └── another-app/
                └── helm.yaml             # HelmRelease for another-app
```

### Directory Organization

- **`clusters/<cluster>/`**: Contains Kustomization resources that FluxCD monitors
  - **`infrastructure/`**: Kustomizations for infrastructure components
  - **`apps/`**: Kustomizations for applications

- **`clusters/resources/<cluster>/`**: Contains the actual Kubernetes manifests
  - **`infrastructure/sources/`**: HelmRepository resources defining Helm chart repositories
  - **`infrastructure/<name>/`**: Infrastructure component HelmReleases (ingress, cert-manager, monitoring, etc.)
  - **`apps/<name>/`**: Application-specific HelmReleases

Each Kustomization in `clusters/<cluster>/` points to its corresponding resources in `clusters/resources/<cluster>/` via the `path` specification.

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

### HelmRelease Example

Located at `clusters/resources/<cluster>/<type>/<name>/helm.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 30m
  chart:
    spec:
      chart: ingress-nginx
      version: "4.7.1"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
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
    controller:
      service:
        type: LoadBalancer
    # ... your custom values
```

### HelmRepository Example

Located at `clusters/resources/<cluster>/infrastructure/sources/<name>.yaml`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 30m
  url: https://kubernetes.github.io/ingress-nginx
```

### Sources Kustomization

A special Kustomization is created for HelmRepository sources:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: sources
  namespace: flux-system
spec:
  interval: 3m
  retryInterval: 2m
  wait: true
  path: "./clusters/resources/my_cluster/infrastructure/sources"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

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

   # Or if you need to copy from a separate output directory
   cp -r clusters/* /path/to/your-flux-repo/clusters/
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

4. **Apply Kustomizations**:
   ```bash
   # Apply the sources Kustomization first (HelmRepository resources)
   kubectl apply -f clusters/my_cluster/infrastructure/sources.yaml

   # Apply infrastructure Kustomizations
   kubectl apply -f clusters/my_cluster/infrastructure/

   # Apply application Kustomizations
   kubectl apply -f clusters/my_cluster/apps/
   ```

   Alternatively, you can create a root Kustomization that watches the cluster directory:
   ```bash
   flux create kustomization cluster \
     --source=flux-system \
     --path="./clusters/my_cluster" \
     --prune=true \
     --interval=10m
   ```

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