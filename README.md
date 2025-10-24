# Self-Hosted GitHub Actions Runners

Production-ready self-hosted GitHub Actions runners for the [ocserv-agent](https://github.com/dantte-lp/ocserv-agent) project, deployed as **Podman pods** with **systemd quadlets** for automatic startup and management.

## Overview

This repository provides two self-hosted runners optimized for different build tasks:

- **github-runner-debian**: Debian Trixie-based runner for security scanning, DEB packages, and general CI/CD
- **github-runner-oracle**: Oracle Linux 10-based runner for RPM packages with `mock` and SELinux support

## Architecture

- **Podman pods** for container orchestration (no Docker required)
- **Systemd quadlets** for service management (RHEL 9+ best practice)
- **Automatic restart** on failures and system boot
- **Pre-installed security tools**: Semgrep, Gitleaks, TruffleHog, Grype, Syft, Cosign, etc.
- **Build tools**: Go 1.25, protoc, mock (RPM), debootstrap (DEB)

## Quick Start

### Prerequisites

**Required:**
- RHEL 9+ / Oracle Linux 9+ / Fedora 38+ (for systemd quadlets)
- Podman 4.4+ (with quadlet support)
- GitHub personal access token with `repo` scope

**Optional (for advanced features):**
- Buildah - Multi-architecture image builds
- Skopeo - Registry operations and image management
- crun - High-performance container runtime

Install optional tools:
```bash
sudo dnf install -y buildah skopeo crun
make validate-tools  # Verify installation
```

### Installation

1. **Clone the repository**:
```bash
git clone https://github.com/yourusername/self-hosted-runners.git
cd self-hosted-runners
```

2. **Configure environment**:
```bash
cp pods/shared/env.example pods/shared/.env
# Edit .env and set RUNNER_TOKEN
```

3. **Install systemd units**:
```bash
sudo make install
```

4. **Start runners**:
```bash
sudo systemctl daemon-reload
sudo systemctl start github-runner-debian.service
sudo systemctl start github-runner-oracle.service
```

5. **Enable auto-start on boot**:
```bash
sudo systemctl enable github-runner-debian.service
sudo systemctl enable github-runner-oracle.service
```

## Management

### Basic Operations

#### Check status
```bash
sudo systemctl status github-runner-debian.service
sudo systemctl status github-runner-oracle.service

# Or using Makefile
make status
```

#### View logs
```bash
sudo journalctl -u github-runner-debian.service -f
sudo journalctl -u github-runner-oracle.service -f

# Or using Makefile
make logs          # Both runners
make logs-debian   # Debian only
make logs-oracle   # Oracle only
```

#### Restart runners
```bash
sudo systemctl restart github-runner-debian.service
sudo systemctl restart github-runner-oracle.service

# Or using Makefile
sudo make restart
```

#### Stop runners
```bash
sudo systemctl stop github-runner-debian.service
sudo systemctl stop github-runner-oracle.service

# Or using Makefile
sudo make stop
```

### Advanced Operations ⭐ NEW

#### Build with Buildah
```bash
# Build using Buildah instead of Podman
make build-buildah

# Build multi-architecture images
make build-multiarch PLATFORMS=linux/amd64,linux/arm64
```

#### Registry Operations with Skopeo
```bash
# Inspect images
make inspect

# Push to registry
make push REGISTRY=ghcr.io/yourorg

# Pull from registry
make pull REGISTRY=ghcr.io/yourorg

# Sync between registries
make sync SRC_REGISTRY=ghcr.io/yourorg DST_REGISTRY=quay.io/yourorg
```

#### Validate Tools
```bash
# Check available containers ecosystem tools
make validate-tools
```

See [docs/CONTAINERS-TOOLKIT.md](docs/CONTAINERS-TOOLKIT.md) for more examples.

## Directory Structure

```
self-hosted-runners/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── Makefile                           # Easy management commands
├── docs/
│   ├── SETUP.md                       # Detailed setup guide
│   ├── ARCHITECTURE.md                # Architecture documentation
│   └── TROUBLESHOOTING.md            # Common issues and solutions
├── pods/
│   ├── github-runner-debian/          # Debian runner
│   │   ├── Containerfile              # Image definition
│   │   ├── entrypoint.sh              # Container entrypoint
│   │   └── github-runner-debian.container  # Quadlet container unit
│   ├── github-runner-oracle/          # Oracle Linux runner
│   │   ├── Containerfile              # Image definition
│   │   ├── entrypoint.sh              # Container entrypoint
│   │   └── github-runner-oracle.container  # Quadlet container unit
│   └── shared/
│       ├── env.example                # Environment variables template
│       └── .env                       # Your configuration (gitignored)
└── scripts/
    ├── install.sh                     # Install systemd units
    ├── uninstall.sh                   # Remove systemd units
    └── generate-token.sh              # Get GitHub runner token
```

## Features

### Containers Ecosystem Integration ⭐ NEW

Enhanced with tools from [containers.github.io](https://github.com/containers):

- **Buildah** - Advanced image building with multi-architecture support
- **Skopeo** - Registry operations (inspect, copy, sync images)
- **crun** - High-performance OCI runtime (~5x faster startup than runc)

See [docs/CONTAINERS-TOOLKIT.md](docs/CONTAINERS-TOOLKIT.md) for usage examples.

### Image Size Optimization ⭐ NEW

Optimized Containerfiles for smaller image sizes:
- **Debian Runner**: 7.92 GB (includes 8 JVM SDKs via SDKMAN)
- **Oracle Runner**: 8.12 GB (includes 8 JVM SDKs via SDKMAN)

Optimizations include:
- Combined RUN commands to reduce layers
- Aggressive cache cleaning (apt, dnf, npm, go, pip, SDKMAN)
- Removed unnecessary documentation and source files
- Use of `--no-install-recommends` flag
- Cleaned up temporary files in each layer
- SDKMAN cache flushing (`sdk flush archives && sdk flush temp`)

### Security Tools (Pre-installed)

Both runners include:
- **SAST**: Semgrep, gosec, staticcheck, CodeQL
- **Secret scanning**: Gitleaks 8.28.0, TruffleHog 3.90.3
- **Vulnerability scanning**: govulncheck, OSV-Scanner v2, Nancy, Grype 0.101.1, Trivy
- **SBOM generation**: Syft 1.34.2 (CycloneDX + SPDX)
- **Container signing**: Cosign 3.0.2 (Sigstore)
- **License compliance**: go-licenses

### Build Tools

**github-runner-debian**:
- Python 3.14, Go 1.25, protoc 33.0, Node.js 25, .NET SDK 8.0
- **JVM Tools (via SDKMAN 🆕)**: GraalVM JDK 25.0.1, Gradle 9.1.0, Maven 3.9.11, Kotlin 2.2.21, Scala 3.7.3, SpringBoot 3.5.7, Micronaut 4.10.0, JBang 0.132.1
- debootstrap for clean DEB builds
- Docker/Podman support
- golangci-lint, markdownlint, yamllint, hadolint

**github-runner-oracle**:
- Go 1.25, protoc 33.0, Node.js 25, .NET SDK 8.0
- **JVM Tools (via SDKMAN 🆕)**: GraalVM JDK 25.0.1, Gradle 9.1.0, Maven 3.9.11, Kotlin 2.2.21, Scala 3.7.3, SpringBoot 3.5.7, Micronaut 4.10.0, JBang 0.132.1
- mock for clean RPM builds (EL8/9/10)
- RPM development tools
- SELinux policy tools

## Configuration

### Environment Variables

Create `pods/shared/.env` from `env.example`:

```bash
# Repository to register runners with
REPO_URL=https://github.com/dantte-lp/ocserv-agent

# Runner registration token (get with scripts/generate-token.sh)
RUNNER_TOKEN=your-token-here

# Runner names (optional, defaults provided)
DEBIAN_RUNNER_NAME=debian-runner-ocserv-agent
ORACLE_RUNNER_NAME=oraclelinux-runner-ocserv-agent

# Runner labels (optional, defaults provided)
DEBIAN_RUNNER_LABELS=self-hosted,linux,x64,debian,docker
ORACLE_RUNNER_LABELS=self-hosted,linux,x64,oracle-linux,rpm-build,mock,podman

# Runner group (optional, default: Default)
RUNNER_GROUP=Default
```

### Get Runner Token

```bash
# Using GitHub CLI (recommended)
./scripts/generate-token.sh

# Or manually
gh api --method POST /repos/dantte-lp/ocserv-agent/actions/runners/registration-token --jq '.token'
```

## Systemd Integration

This project uses **systemd quadlets** (RHEL 9+ feature) for seamless Podman integration:

- **Auto-start on boot**: Runners start automatically when the system boots
- **Auto-restart on failure**: Systemd automatically restarts crashed containers
- **Resource limits**: CPU and memory limits via systemd
- **Logging**: Integrated with journalctl for centralized logging
- **Dependency management**: Proper startup ordering

### Quadlet Files Location

- System-wide: `/etc/containers/systemd/`
- User-specific: `~/.config/containers/systemd/`

This project installs to `/etc/containers/systemd/` for system-wide runners.

## Requirements

### System Requirements

- **OS**: RHEL 9+, Oracle Linux 9+, Fedora 38+, or compatible
- **Podman**: 4.4+ with quadlet support
- **Systemd**: 247+ (for quadlet)
- **CPU**: 4+ cores recommended
- **RAM**: 8GB+ recommended
- **Disk**: 50GB+ for container images and build caches

### Network Requirements

- Outbound HTTPS to github.com
- Outbound HTTPS to api.github.com
- Outbound HTTPS to package repositories (for tool installation)

## Upgrading

To upgrade runner images with latest security tools:

```bash
# Pull latest changes
git pull

# Rebuild containers
sudo make rebuild

# Restart services
sudo systemctl restart github-runner-debian.service
sudo systemctl restart github-runner-oracle.service
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

### Quick Checks

1. **Verify Podman version**:
```bash
podman --version  # Should be 4.4+
```

2. **Check systemd quadlet support**:
```bash
systemctl --version  # Should be 247+
ls /usr/lib/systemd/system-generators/*quadlet*
```

3. **View runner logs**:
```bash
sudo journalctl -u github-runner-debian.service -n 100
```

4. **Check container status**:
```bash
sudo podman ps -a
```

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Projects

- [ocserv-agent](https://github.com/dantte-lp/ocserv-agent) - Main project using these runners
- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [RHEL 9 Podman Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/)

## Support

- **Issues**: https://github.com/yourusername/self-hosted-runners/issues
- **Discussions**: https://github.com/yourusername/self-hosted-runners/discussions
- **Security**: See SECURITY.md for reporting security issues

---

**Status**: Production Ready ✅
**Maintained by**: Pavel Lavrukhin
**Last Updated**: October 2025
