# Architecture - Self-Hosted GitHub Actions Runners

Technical architecture and design documentation for the self-hosted runners infrastructure.

## Overview

This project implements GitHub Actions self-hosted runners using:
- **Podman** for container orchestration (Docker-free)
- **Systemd Quadlets** for service management (RHEL 9+ best practice)
- **Multi-layered security** with pre-installed scanning tools

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Host System (RHEL 9+)                      │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                      Systemd                                 │ │
│  │  ┌──────────────────────┐  ┌──────────────────────┐         │ │
│  │  │ Quadlet Generator    │  │  Service Manager      │         │ │
│  │  │ /usr/lib/systemd/    │──│  systemctl            │         │ │
│  │  │ system-generators/   │  │                       │         │ │
│  │  └──────────────────────┘  └──────────────────────┘         │ │
│  │           │                          │                        │ │
│  │           │ reads .container files   │ controls services      │ │
│  │           ▼                          ▼                        │ │
│  │  ┌────────────────────────────────────────────────┐          │ │
│  │  │  /etc/containers/systemd/                      │          │ │
│  │  │  ├── github-runner-debian.container            │          │ │
│  │  │  └── github-runner-oracle.container            │          │ │
│  │  └────────────────────────────────────────────────┘          │ │
│  └──────────────────────────────┬───────────────────────────────┘ │
│                                  │                                 │
│  ┌──────────────────────────────▼─────────────────────────────┐  │
│  │                         Podman                              │  │
│  │  ┌────────────────────┐        ┌────────────────────┐      │  │
│  │  │ Container:         │        │ Container:         │      │  │
│  │  │ github-runner-     │        │ github-runner-     │      │  │
│  │  │ debian             │        │ oracle             │      │  │
│  │  │                    │        │                    │      │  │
│  │  │ - Python 3.14      │        │ - Oracle Linux 10  │      │  │
│  │  │ - Debian Trixie    │        │ - Python 3.14      │      │  │
│  │  │ - Go 1.25          │        │ - Go 1.25          │      │  │
│  │  │ - Security Tools   │        │ - Mock (RPM)       │      │  │
│  │  │ - DEB build tools  │        │ - Security Tools   │      │  │
│  │  │                    │        │                    │      │  │
│  │  │ GitHub Actions     │        │ GitHub Actions     │      │  │
│  │  │ Runner 2.329.0     │        │ Runner 2.329.0     │      │  │
│  │  └────────────────────┘        └────────────────────┘      │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                  │                                 │
│  Volume Mounts:                  │                                 │
│  /opt/projects/repositories ────►│ /workspace (rw)                │
│  /run/podman/podman.sock ───────►│ /var/run/docker.sock           │
└───────────────────────────────────┴─────────────────────────────────┘
                                    │
                                    ▼
                           GitHub.com API
                    (runner registration & job polling)
```

## Component Details

### 1. Systemd Quadlets

**What are Quadlets?**
- RHEL 9+ feature for managing Podman containers via systemd
- Declarative `.container` files describe container configuration
- Systemd automatically generates service units

**Location**: `/etc/containers/systemd/*.container`

**Key Features**:
- Automatic restart on failure (`Restart=always`)
- Dependency management (`After=network-online.target`)
- Resource limits (CPU, memory)
- Journal logging integration

**Advantages over docker-compose**:
- Native systemd integration (no external orchestrator)
- Boot-time auto-start
- Better resource accounting
- Integrated logging with journald

### 2. Container Images

#### Debian Runner (`github-runner-debian`)

**Base**: `python:3.14-trixie`
**Size**: ~7.5 GB
**Purpose**: Security scanning, DEB packages, general CI/CD

**Pre-installed Tools**:

**Languages & Runtimes**:
- Python 3.14 (base image)
- Go 1.25.1
- Node.js 25
- .NET SDK 8.0
- GraalVM JDK 25

**Security Tools** (11 total):
- **SAST**: Semgrep, gosec, staticcheck, CodeQL
- **Secrets**: Gitleaks 8.28.0, TruffleHog 3.90.3
- **Vulnerabilities**: govulncheck, OSV-Scanner v2, Nancy, Grype 0.101.1, Trivy
- **SBOM**: Syft 1.34.2 (CycloneDX + SPDX)
- **Signing**: Cosign 3.0.2 (Sigstore)
- **License**: go-licenses

**Build Tools**:
- debootstrap (clean DEB builds)
- golangci-lint, markdownlint, yamllint, hadolint
- protoc 33.0

**Package Building**:
- debhelper, devscripts, fakeroot, dpkg-dev
- lintian (DEB package validation)

#### Oracle Linux Runner (`github-runner-oracle`)

**Base**: `oraclelinux:10`
**Size**: ~3.8 GB
**Purpose**: RPM packages with mock, SELinux support

**Pre-installed Tools**:

**RPM Build Stack**:
- mock (clean RPM builds for EL8/9/10)
- rpm-build, rpmdevtools, rpmlint
- SELinux policy development tools

**Languages**:
- Python 3.14 (compiled from source)
- Go 1.25.1
- .NET SDK 8.0
- protoc 33.0

**Security Tools**: Same 11 tools as Debian runner

**Container Tools**:
- Podman (for nested containers)
- Buildah, Skopeo
- Docker CE (for GitHub Actions compatibility)

### 3. Volume Mounts

**Workspace Volume**:
```
Host: /opt/projects/repositories
Container: /workspace
Options: rw,z (read-write with SELinux relabeling)
```

Purpose: Access ocserv-agent source code for builds

**Socket Mount** (Debian):
```
Host: /run/podman/podman.sock
Container: /var/run/docker.sock
Options: rw
```

Purpose: Docker-in-Docker compatibility for container actions

**Socket Mount** (Oracle):
```
Host: /run/podman/podman.sock
Container: /run/podman/podman.sock
Options: rw
```

Purpose: Podman-in-podman for mock builds

### 4. Network Configuration

**Mode**: Bridge (default)

**Outbound Connections**:
- `api.github.com:443` - Runner registration & job polling
- `github.com:443` - Git operations
- `objects.githubusercontent.com:443` - Artifact downloads
- Package repositories - Tool installations

**Inbound**: None required (runners poll GitHub)

### 5. Runner Lifecycle

```
┌─────────────────────┐
│ System Boot         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Systemd starts      │
│ quadlet generator   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Read .container     │
│ files               │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Generate systemd    │
│ service units       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Start containers    │
│ via Podman          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Container: Run      │
│ entrypoint.sh       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Check for .runner   │
│ configuration       │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │           │
  Yes│           │No
     │           │
     ▼           ▼
┌────────┐  ┌────────────────┐
│ Skip   │  │ Run config.sh  │
│ config │  │ (register)     │
└────┬───┘  └────────┬───────┘
     │              │
     └──────┬───────┘
            │
            ▼
     ┌──────────────┐
     │ Run run.sh   │
     │ (start)      │
     └──────┬───────┘
            │
            ▼
     ┌──────────────┐
     │ Poll GitHub  │
     │ for jobs     │
     └──────┬───────┘
            │
            │ (loop)
            ▼
     ┌──────────────┐
     │ Execute job  │
     │ if available │
     └──────┬───────┘
            │
            │ (repeat)
            └─────►
```

### 6. Security Model

**Multi-Layer Security Scanning**:

1. **Pre-commit** (local developer checks)
   - Gitleaks, TruffleHog (secrets)
   - golangci-lint, semgrep (SAST)

2. **CI Build Time** (in GitHub Actions)
   - CodeQL, gosec, staticcheck (SAST)
   - govulncheck, OSV-Scanner, Nancy (dependencies)
   - Semgrep (multi-language SAST)

3. **Post-build** (after compilation)
   - Grype (binary vulnerability scanning)
   - Syft (SBOM generation)

4. **Runtime** (container scanning)
   - Trivy (image scanning)
   - Cosign (signature verification)

**Container Security**:
- Rootless mode capable (UserNS=auto)
- SELinux support (can be enabled/disabled)
- No privileged mode required (except for mock/Docker-in-Docker)
- Minimal attack surface

**Resource Isolation**:
- CPU quotas via systemd
- Memory limits via systemd
- Tmpfs for temporary files (size-limited)

### 7. Data Flow

**Job Execution Flow**:

```
GitHub Repository
       │
       │ 1. Workflow triggered
       ▼
GitHub Actions API
       │
       │ 2. Job queued
       ▼
Runner (polling)
       │
       │ 3. Job acquired
       ▼
Workspace Setup
  ├── Clone repository
  ├── Setup environment
  └── Download artifacts
       │
       │ 4. Execute steps
       ▼
Job Steps
  ├── Checkout code
  ├── Run scripts
  ├── Build artifacts
  └── Run tests
       │
       │ 5. Upload results
       ▼
GitHub Actions API
  ├── Job logs
  ├── Artifacts
  └── Status updates
       │
       │ 6. Complete
       ▼
Job Result
```

**Artifact Storage**:
- Build artifacts: Container ephemeral storage
- Logs: Systemd journal (`journalctl`)
- Workspace: Mounted volume (persists across jobs)

## Scaling Considerations

**Horizontal Scaling**:
- Add more runners by cloning `.container` files
- Update RUNNER_NAME and service name
- Load balancing automatic (GitHub distributes jobs)

**Vertical Scaling**:
- Adjust CPUQuota and Memory in .container files
- Consider dedicated build cache volumes
- Monitor resource usage with `systemctl status`

**Capacity Planning**:
- Each runner can handle 1 job at a time
- Average job duration: 5-15 minutes
- Recommend 1 runner per 10 daily workflow runs

## Monitoring

**System-Level Monitoring**:
```bash
# Service health
systemctl status github-runner-*.service

# Resource usage
systemctl show github-runner-debian.service --property=MemoryCurrent
systemctl show github-runner-debian.service --property=CPUUsageNSec

# Container stats
podman stats
```

**Log Monitoring**:
```bash
# Real-time logs
journalctl -u github-runner-debian.service -f

# Error logs only
journalctl -u github-runner-debian.service -p err

# Export logs
journalctl -u github-runner-debian.service --since="1 hour ago" > logs.txt
```

**GitHub Monitoring**:
- Settings → Actions → Runners (online/offline status)
- Workflow run logs
- Runner utilization metrics (with GitHub Enterprise)

## Maintenance

**Regular Maintenance**:
1. **Update container images** (monthly):
   ```bash
   sudo make rebuild
   sudo make restart
   ```

2. **Monitor disk usage**:
   ```bash
   podman system df
   podman image prune -a  # Clean old images
   ```

3. **Review logs** (weekly):
   ```bash
   journalctl -u github-runner-*.service --since="7 days ago" -p warning
   ```

4. **Regenerate tokens** (before expiry):
   ```bash
   make token  # Every hour if runners restart
   ```

**Version Updates**:
- GitHub Actions Runner: Update `RUNNER_VERSION` in Containerfile
- Security tools: Update version variables in Containerfile
- Rebuild images after updates

## Troubleshooting Architecture

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Related Documentation

- [SETUP.md](SETUP.md) - Installation and configuration
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [Podman Quadlet Docs](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [GitHub Actions Runner Docs](https://docs.github.com/en/actions/hosting-your-own-runners)
