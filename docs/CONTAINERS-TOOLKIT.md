# Containers Ecosystem Tools Guide

This guide covers the usage of additional containers ecosystem tools integrated into the self-hosted runners project: **Buildah**, **Skopeo**, and **crun**.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Buildah - Advanced Image Building](#buildah---advanced-image-building)
- [Skopeo - Registry Operations](#skopeo---registry-operations)
- [crun - High-Performance Runtime](#crun---high-performance-runtime)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

The Containers ecosystem (https://github.com/containers) provides several powerful tools that complement Podman:

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **Buildah** | Advanced image building | Multi-arch builds, Dockerfile-less builds, fine-grained control |
| **Skopeo** | Registry operations | Inspect, copy, sync images without running containers |
| **crun** | OCI runtime | Fast, lightweight, fully-featured container runtime |

## Installation

### Oracle Linux / RHEL / Fedora

```bash
# Install all tools
sudo dnf install -y buildah skopeo crun

# Verify installation
make validate-tools
```

### Verification

```bash
$ make validate-tools
Validating containers ecosystem tools...
Podman: podman version 4.9.4-rhel
Buildah: buildah version 1.35.4 (image-spec 1.1.0, runtime-spec 1.2.0)
Skopeo: skopeo version 1.14.5
crun: crun version 1.14.4
```

## Buildah - Advanced Image Building

Buildah provides more control over the image building process compared to `podman build`.

### Basic Usage

#### Build with Buildah

```bash
# Standard build (equivalent to podman build)
make build-buildah

# Or manually
buildah build --format docker --layers -t github-runner-debian:latest \
    -f pods/github-runner-debian/Containerfile \
    pods/github-runner-debian/
```

#### Multi-Architecture Builds

Build images for multiple architectures (amd64, arm64):

```bash
# Build for multiple platforms
make build-multiarch

# Custom platforms
make build-multiarch PLATFORMS=linux/amd64,linux/arm64,linux/arm/v7

# Push multi-arch manifest to registry
make build-multiarch REGISTRY=ghcr.io/yourorg
make push REGISTRY=ghcr.io/yourorg
```

### Advanced Buildah Features

#### 1. Dockerfile-less Builds

Create images without a Dockerfile:

```bash
# Create a working container
container=$(buildah from debian:bookworm)

# Run commands in the container
buildah run $container apt-get update
buildah run $container apt-get install -y python3 python3-pip

# Configure the image
buildah config --entrypoint '["/usr/bin/python3"]' $container
buildah config --label version=1.0 $container

# Commit the image
buildah commit $container my-custom-image:latest
```

#### 2. Fine-Grained Layer Control

```bash
# Build with explicit caching control
buildah build \
    --layers \
    --cache-from localhost/github-runner-debian:latest \
    -t github-runner-debian:latest \
    -f pods/github-runner-debian/Containerfile \
    pods/github-runner-debian/
```

#### 3. Rootless Builds

```bash
# Build as non-root user (more secure)
buildah build \
    --isolation chroot \
    -t github-runner-debian:latest \
    -f pods/github-runner-debian/Containerfile \
    pods/github-runner-debian/
```

### Buildah vs Podman Build

| Feature | Podman Build | Buildah |
|---------|-------------|---------|
| Dockerfile support | ✅ | ✅ |
| Multi-arch builds | ⚠️ Limited | ✅ Native |
| Dockerfile-less builds | ❌ | ✅ |
| Fine-grained control | ⚠️ | ✅ |
| Scripting | ⚠️ | ✅ Excellent |
| Simplicity | ✅ | ⚠️ More complex |

## Skopeo - Registry Operations

Skopeo allows you to work with container images and registries without pulling the entire image.

### Basic Operations

#### 1. Inspect Images

Inspect remote images without downloading:

```bash
# Inspect local images
make inspect

# Inspect remote image
skopeo inspect docker://docker.io/python:3.14-trixie

# Inspect image in OCI layout
skopeo inspect oci:/path/to/oci/layout

# Get specific information (using jq)
skopeo inspect docker://python:3.14-trixie | jq '.Size'
```

#### 2. Copy Images

Copy images between registries without pulling them locally:

```bash
# Copy from Docker Hub to local registry
skopeo copy \
    docker://python:3.14-trixie \
    docker://localhost:5000/python:3.14-trixie

# Copy from local to remote registry
skopeo copy \
    containers-storage:localhost/github-runner-debian:latest \
    docker://ghcr.io/yourorg/github-runner-debian:latest \
    --dest-creds=username:token

# Copy with compression
skopeo copy --compress \
    containers-storage:localhost/github-runner-debian:latest \
    dir:/path/to/export
```

#### 3. Push/Pull Images

```bash
# Push to registry (using Makefile)
make push REGISTRY=ghcr.io/yourorg

# Or manually
skopeo copy \
    containers-storage:localhost/github-runner-debian:latest \
    docker://ghcr.io/yourorg/github-runner-debian:latest

# Pull from registry
make pull REGISTRY=ghcr.io/yourorg
```

#### 4. Sync Between Registries

Synchronize images between different registries:

```bash
# Sync using Makefile
make sync SRC_REGISTRY=ghcr.io/yourorg DST_REGISTRY=quay.io/yourorg

# Or manually
skopeo sync --src docker --dest docker \
    ghcr.io/yourorg/github-runner-debian:latest \
    quay.io/yourorg/
```

### Advanced Skopeo Operations

#### 1. Delete Images from Registry

```bash
# Delete remote image
skopeo delete docker://ghcr.io/yourorg/github-runner-debian:old-tag
```

#### 2. List Tags

```bash
# List all tags for an image
skopeo list-tags docker://ghcr.io/yourorg/github-runner-debian
```

#### 3. Image Verification

```bash
# Get image digest
skopeo inspect docker://python:3.14-trixie | jq -r '.Digest'

# Verify image signature (with Cosign)
cosign verify --key cosign.pub ghcr.io/yourorg/github-runner-debian:latest
```

## crun - High-Performance Runtime

crun is a fast and lightweight OCI runtime written in C.

### Using crun with Podman

```bash
# Configure Podman to use crun
cat > ~/.config/containers/containers.conf <<EOF
[engine]
runtime = "crun"
EOF

# Verify
podman info | grep -i runtime

# Or specify per-container
podman run --runtime crun ...
```

### Performance Comparison

| Runtime | Startup Time | Memory Usage | Features |
|---------|-------------|--------------|----------|
| **runc** | ~100ms | ~10MB | Standard, well-tested |
| **crun** | ~20ms | ~1MB | Fast, low memory |
| **kata** | ~500ms | ~130MB | VM-based isolation |

### Benefits of crun

- **Faster startup**: ~5x faster than runc
- **Lower memory**: ~10x less memory overhead
- **Full features**: Supports all OCI runtime features
- **Better performance**: Optimized for containerized workloads

## Best Practices

### Image Building

1. **Use multi-stage builds** to reduce final image size:
```dockerfile
FROM python:3.14-trixie AS builder
RUN pip install --no-cache-dir package

FROM python:3.14-slim
COPY --from=builder /usr/local/lib/python3.14 /usr/local/lib/python3.14
```

2. **Clean caches** after package installation:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends package \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
```

3. **Combine RUN commands** to reduce layers:
```dockerfile
# Bad: Multiple layers
RUN apt-get update
RUN apt-get install -y package1
RUN apt-get install -y package2

# Good: Single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
        package1 \
        package2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### Registry Operations

1. **Use digest references** for reproducible builds:
```bash
# Instead of tags (mutable)
docker pull python:3.14-trixie

# Use digests (immutable)
docker pull python@sha256:abc123...
```

2. **Verify images** before deployment:
```bash
skopeo inspect docker://ghcr.io/yourorg/image:latest | jq '.Digest'
cosign verify --key cosign.pub ghcr.io/yourorg/image:latest
```

3. **Use image signing** for security:
```bash
# Sign image with Cosign
cosign sign --key cosign.key ghcr.io/yourorg/github-runner-debian:latest

# Verify signature
cosign verify --key cosign.pub ghcr.io/yourorg/github-runner-debian:latest
```

### Multi-Architecture Support

1. **Build for common architectures**:
```bash
# Build for AMD64 and ARM64
make build-multiarch PLATFORMS=linux/amd64,linux/arm64
```

2. **Use manifest lists** for automatic platform selection:
```bash
# Podman/Docker automatically selects the right architecture
docker pull ghcr.io/yourorg/github-runner-debian:latest
```

## Image Size Optimization

The project has been optimized to reduce image sizes significantly:

### Optimization Techniques Applied

1. **Removed unnecessary packages**:
   - Use `--no-install-recommends` (Debian/Ubuntu)
   - Removed valgrind, vim, nano from runtime images

2. **Cleaned package caches**:
   - `apt-get clean && rm -rf /var/lib/apt/lists/*` (Debian)
   - `dnf clean all` (Oracle Linux)
   - `npm cache clean --force`
   - `go clean -cache -modcache`
   - `rm -rf /root/.cache/*`

3. **Combined RUN commands**:
   - Reduced number of layers
   - Cleaned up temporary files in the same layer

4. **Removed unnecessary files**:
   - Documentation directories (`/opt/graalvm/man`, `/opt/java-tools/*/docs`)
   - Source files (`/opt/graalvm/lib/src.zip`)
   - Build artifacts

5. **Made heavy tools optional**:
   - GraalVM (kept for universal testing)
   - Java tools (kept for universal testing)

### Expected Size Reduction

| Component | Before | After | Savings |
|-----------|--------|-------|---------|
| Debian Runner | ~10GB | ~7-8GB | ~20-30% |
| Oracle Runner | ~8GB | ~5-6GB | ~25-35% |

## Troubleshooting

### Buildah Issues

**Problem**: Permission denied errors during build

```bash
# Solution: Use rootless mode
buildah build --isolation chroot ...
```

**Problem**: Multi-arch build fails

```bash
# Solution: Install qemu-user-static
sudo dnf install -y qemu-user-static
```

### Skopeo Issues

**Problem**: Authentication failed

```bash
# Solution: Login to registry
skopeo login ghcr.io

# Or provide credentials inline
skopeo copy --dest-creds=username:token ...
```

**Problem**: TLS certificate verification failed

```bash
# Solution: Use insecure option (for testing only!)
skopeo copy --dest-tls-verify=false ...
```

### crun Issues

**Problem**: crun not available

```bash
# Check if crun is installed
crun --version

# If not, install it
sudo dnf install -y crun
```

**Problem**: Podman still uses runc

```bash
# Configure default runtime
mkdir -p ~/.config/containers
cat > ~/.config/containers/containers.conf <<EOF
[engine]
runtime = "crun"
EOF

# Restart Podman service
systemctl --user restart podman
```

## Additional Resources

- [Buildah Documentation](https://buildah.io/)
- [Skopeo GitHub](https://github.com/containers/skopeo)
- [crun GitHub](https://github.com/containers/crun)
- [Podman Documentation](https://docs.podman.io/)
- [OCI Image Specification](https://github.com/opencontainers/image-spec)
- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)

## Examples

### Complete Workflow: Build, Push, and Deploy

```bash
# 1. Build images with Buildah (multi-arch)
make build-multiarch PLATFORMS=linux/amd64,linux/arm64

# 2. Inspect images
make inspect

# 3. Push to registry
make push REGISTRY=ghcr.io/yourorg

# 4. Verify push
skopeo inspect docker://ghcr.io/yourorg/github-runner-debian:latest

# 5. Pull on another system
make pull REGISTRY=ghcr.io/yourorg

# 6. Deploy with systemd
sudo make install
sudo systemctl start github-runner-debian.service
```

### Image Migration Between Registries

```bash
# Migrate all runner images from Docker Hub to GitHub Container Registry
skopeo sync --src docker --dest docker \
    docker.io/yourorg/github-runner-debian:latest \
    ghcr.io/yourorg/

skopeo sync --src docker --dest docker \
    docker.io/yourorg/github-runner-oracle:latest \
    ghcr.io/yourorg/
```

### Automated Image Updates

```bash
#!/bin/bash
# update-runners.sh - Automated runner image update script

set -e

REGISTRY="ghcr.io/yourorg"

echo "Pulling latest changes..."
git pull

echo "Building images with Buildah..."
make build-buildah

echo "Inspecting images..."
make inspect

echo "Pushing to registry..."
make push REGISTRY=$REGISTRY

echo "Restarting runners..."
sudo systemctl restart github-runner-debian.service
sudo systemctl restart github-runner-oracle.service

echo "Update complete!"
```

---

**Need help?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open an issue on GitHub.
