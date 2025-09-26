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
./convert.sh <RELEASE_NAME> <NAMESPACE>
```

Example:
```bash
./convert.sh ingress-nginx ingress-nginx
```

### Convert All Releases

```bash
./all.sh
```

This will automatically discover and convert all Helm releases across all namespaces.

## Output Structure

The tool generates a FluxCD-compatible directory structure:

```
output/
├── infrastructure/
│   ├── sources/
│   │   └── helm/
│   │       ├── ingress-nginx-repository.yaml
│   │       └── cert-manager-repository.yaml
│   └── controllers/
│       ├── ingress-nginx/
│       │   └── helmrelease.yaml
│       └── cert-manager/
│           └── helmrelease.yaml
└── apps/
    └── <app-namespace>/
        └── <app-name>/
            └── helmrelease.yaml
```

### Directory Organization

- **infrastructure/sources/helm/**: HelmRepository resources defining Helm chart repositories
- **infrastructure/controllers/**: System-level controllers (ingress, cert-manager, monitoring, etc.)
- **apps/**: Application-specific HelmReleases organized by namespace

## Generated Resources

### HelmRelease Example

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
  values:
    controller:
      service:
        type: LoadBalancer
    # ... your custom values
```

### HelmRepository Example

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

## Integration with FluxCD

After generating the manifests:

1. **Review Generated Files**: Inspect the output directory to ensure configurations are correct

2. **Commit to Git Repository**:
   ```bash
   cp -r output/* /path/to/your-flux-repo/clusters/production/
   git add .
   git commit -m "Migrate Helm releases to FluxCD"
   git push
   ```

3. **Configure Flux to Monitor the Repository**:
   ```bash
   flux create source git flux-system \
     --url=https://github.com/yourusername/your-flux-repo \
     --branch=main \
     --interval=1m
   ```

4. **Apply Kustomization**:
   ```bash
   flux create kustomization infrastructure \
     --source=flux-system \
     --path="./clusters/production/infrastructure" \
     --prune=true \
     --interval=10m
   ```

## Migration Strategy

### Recommended Approach

1. **Test in Development**: Run the migration in a development cluster first
2. **Gradual Migration**: Migrate one release at a time in production
3. **Verify State**: Ensure FluxCD successfully reconciles each release
4. **Clean Up**: Once verified, remove the original Helm releases:
   ```bash
   helm uninstall <RELEASE_NAME> -n <NAMESPACE>
   ```

### Important Considerations

- FluxCD will take over management of the resources
- Ensure no conflicting operators or controllers are managing the same resources
- Back up your cluster state before migration
- Review and adjust the generated `interval` values based on your needs

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