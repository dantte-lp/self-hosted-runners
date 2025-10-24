# Kubernetes YAML Integration with Quadlet

This guide explains how to use Kubernetes YAML files with Podman Quadlet for running GitHub Actions runners.

## Table of Contents

- [Why Kubernetes YAML?](#why-kubernetes-yaml)
- [Architecture](#architecture)
- [Migration Guide](#migration-guide)
- [Usage](#usage)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Why Kubernetes YAML?

### Advantages over .container files

| Feature | `.container` files | `.kube` files (K8s YAML) |
|---------|-------------------|--------------------------|
| **Kubernetes compatible** | ❌ No | ✅ Yes |
| **Portable** | Podman only | ✅ Podman + K8s |
| **Industry standard** | Podman-specific | ✅ Standard YAML |
| **ConfigMaps/Secrets** | Limited | ✅ Full support |
| **Multi-container pods** | No | ✅ Yes |
| **Resource limits** | Basic | ✅ Full K8s spec |
| **Testing** | Podman only | ✅ minikube/kind |

### When to use Kubernetes YAML

✅ **Use Kubernetes YAML if:**
- You plan to migrate to Kubernetes later
- You want standard, portable configuration
- You need ConfigMaps and Secrets
- You have DevOps team familiar with K8s
- You want to test configs in minikube/kind

❌ **Stick with .container if:**
- Simple single-container setup
- No plans for Kubernetes
- Prefer Podman-native format

## Architecture

### File Structure

```
self-hosted-runners/
├── pods/
│   ├── kube-yaml/                    # NEW: Kubernetes YAML approach
│   │   ├── github-runner-debian.yaml # K8s Pod definition
│   │   ├── github-runner-debian.kube # Quadlet Kube unit
│   │   ├── github-runner-oracle.yaml # K8s Pod definition
│   │   └── github-runner-oracle.kube # Quadlet Kube unit
│   │
│   ├── github-runner-debian/          # OLD: .container approach
│   │   ├── Containerfile
│   │   ├── entrypoint.sh
│   │   └── github-runner-debian.container
│   │
│   └── github-runner-oracle/
│       ├── Containerfile
│       ├── entrypoint.sh
│       └── github-runner-oracle.container
```

### How it works

```
┌────────────────────────────────────────────────────────────────┐
│  1. Create Kubernetes YAML                                      │
│     pods/kube-yaml/github-runner-debian.yaml                   │
│     (Standard K8s Pod specification)                            │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│  2. Create Quadlet .kube file                                   │
│     pods/kube-yaml/github-runner-debian.kube                   │
│     [Kube]                                                      │
│     Yaml=/etc/containers/systemd/github-runner-debian.yaml    │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│  3. Install to systemd directory                                │
│     sudo cp *.kube *.yaml /etc/containers/systemd/             │
│     sudo systemctl daemon-reload                                │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│  4. Quadlet generator processes .kube files                     │
│     /usr/lib/systemd/system-generators/podman-system-generator │
│     Reads: /etc/containers/systemd/*.kube                       │
│     Reads: /etc/containers/systemd/*.yaml                       │
│     Generates: github-runner-debian.service                     │
└─────────────────────┬──────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────────────┐
│  5. Systemd manages the service                                 │
│     systemctl start github-runner-debian.service               │
│     └─> podman play kube github-runner-debian.yaml             │
│         └─> Creates Pod with container(s)                       │
└────────────────────────────────────────────────────────────────┘
```

## Migration Guide

### Step-by-step migration from .container to .kube

#### 1. Verify current setup

```bash
# List current services
sudo systemctl list-units 'github-runner-*'

# Stop current runners
sudo systemctl stop github-runner-debian.service
sudo systemctl stop github-runner-oracle.service
```

#### 2. Install new Kubernetes YAML files

```bash
cd /opt/projects/repositories/self-hosted-runners

# Copy Kubernetes YAML and .kube files to systemd directory
sudo cp pods/kube-yaml/github-runner-debian.yaml /etc/containers/systemd/
sudo cp pods/kube-yaml/github-runner-debian.kube /etc/containers/systemd/
sudo cp pods/kube-yaml/github-runner-oracle.yaml /etc/containers/systemd/
sudo cp pods/kube-yaml/github-runner-oracle.kube /etc/containers/systemd/
```

#### 3. Remove old .container files (optional)

```bash
# Backup first
sudo cp /etc/containers/systemd/github-runner-debian.container ~/backup/
sudo cp /etc/containers/systemd/github-runner-oracle.container ~/backup/

# Remove old files
sudo rm /etc/containers/systemd/github-runner-debian.container
sudo rm /etc/containers/systemd/github-runner-oracle.container
```

#### 4. Reload systemd and start new services

```bash
# Reload systemd to process new .kube files
sudo systemctl daemon-reload

# Start new services
sudo systemctl start github-runner-debian.service
sudo systemctl start github-runner-oracle.service

# Enable auto-start
sudo systemctl enable github-runner-debian.service
sudo systemctl enable github-runner-oracle.service
```

#### 5. Verify

```bash
# Check status
sudo systemctl status github-runner-debian.service
sudo systemctl status github-runner-oracle.service

# Check pods
podman pod ps

# Check logs
sudo journalctl -u github-runner-debian.service -f
```

## Usage

### Managing runners with systemd

```bash
# Start/Stop/Restart
sudo systemctl start github-runner-debian.service
sudo systemctl stop github-runner-debian.service
sudo systemctl restart github-runner-debian.service

# Enable/Disable auto-start
sudo systemctl enable github-runner-debian.service
sudo systemctl disable github-runner-debian.service

# Check status
sudo systemctl status github-runner-debian.service

# View logs
sudo journalctl -u github-runner-debian.service -f
```

### Managing with podman play kube (manual testing)

```bash
# Play (start) a Kubernetes YAML
podman play kube pods/kube-yaml/github-runner-debian.yaml

# Stop and remove
podman play kube --down pods/kube-yaml/github-runner-debian.yaml

# List pods
podman pod ps

# Inspect pod
podman pod inspect github-runner-debian
```

### Updating configuration

```bash
# 1. Edit Kubernetes YAML
sudo vi /etc/containers/systemd/github-runner-debian.yaml

# 2. Reload systemd
sudo systemctl daemon-reload

# 3. Restart service
sudo systemctl restart github-runner-debian.service
```

## Testing

### Test in Kubernetes (minikube/kind)

The same YAML files can be tested in Kubernetes!

```bash
# Start minikube
minikube start

# Apply ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: runner-config
data:
  REPO_URL: "https://github.com/dantte-lp/ocserv-agent"
  RUNNER_TOKEN: "your-token-here"
  RUNNER_GROUP: "Default"
EOF

# Apply Pod
kubectl apply -f pods/kube-yaml/github-runner-debian.yaml

# Check status
kubectl get pods
kubectl logs github-runner-debian

# Clean up
kubectl delete -f pods/kube-yaml/github-runner-debian.yaml
```

### Validate YAML syntax

```bash
# Install yamllint
sudo dnf install -y yamllint

# Validate YAML
yamllint pods/kube-yaml/github-runner-debian.yaml

# Test with podman play kube --dry-run (if available)
podman play kube --dry-run pods/kube-yaml/github-runner-debian.yaml
```

## Troubleshooting

### Common issues

#### 1. Service fails to start

```bash
# Check systemd logs
sudo journalctl -u github-runner-debian.service -n 50

# Check generated service file
ls -la /run/systemd/generator/github-runner-debian.service
cat /run/systemd/generator/github-runner-debian.service

# Check Quadlet generator logs
sudo journalctl -u systemd-generator -n 50
```

#### 2. Pod not created

```bash
# List all pods
podman pod ps --all

# Check pod logs
podman pod logs github-runner-debian

# Inspect pod
podman pod inspect github-runner-debian
```

#### 3. Volume mount issues

```bash
# Check if host paths exist
ls -la /opt/projects/repositories
ls -la /run/podman/podman.sock

# Check SELinux labels
ls -laZ /opt/projects/repositories

# Relabel if needed
sudo chcon -R -t container_file_t /opt/projects/repositories
```

#### 4. Image not found

```bash
# List images
podman images | grep github-runner

# Build images if missing
make build

# Update imagePullPolicy in YAML to 'Never' for local images
```

### Debug mode

```bash
# Enable debug logging for Podman
export PODMAN_DEBUG=1

# Test manually
podman play kube --log-level=debug pods/kube-yaml/github-runner-debian.yaml

# Check what Quadlet would generate
/usr/lib/systemd/system-generators/podman-system-generator --dryrun /tmp/test
```

## Advanced Features

### Using Secrets for RUNNER_TOKEN

Create a Kubernetes Secret:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: runner-token
type: Opaque
stringData:
  RUNNER_TOKEN: "your-github-runner-token-here"
```

Reference in Pod:

```yaml
spec:
  containers:
  - name: github-runner-debian
    envFrom:
    - secretRef:
        name: runner-token
```

### Multi-container Pods

Example: Runner + Log shipper

```yaml
spec:
  containers:
  - name: github-runner-debian
    image: localhost/github-runner-debian:latest
    # ...runner config...

  - name: log-shipper
    image: fluent/fluent-bit:latest
    volumeMounts:
    - name: logs
      mountPath: /var/log/runner
```

### Resource Quotas

```yaml
resources:
  requests:
    memory: "4Gi"
    cpu: "2"
  limits:
    memory: "8Gi"
    cpu: "4"
```

## References

- [Podman play kube documentation](https://docs.podman.io/en/latest/markdown/podman-play-kube.1.html)
- [Quadlet .kube units](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html#kube-units-kube)
- [Kubernetes Pod specification](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/)
- [Podman Kubernetes YAML support](https://docs.podman.io/en/latest/markdown/podman-kube.1.html)

---

**Need help?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open an issue on GitHub.
