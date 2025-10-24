# Self-Hosted GitHub Actions Runners - Setup Guide

Complete setup guide for deploying GitHub Actions self-hosted runners using Podman and systemd quadlets.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Configuration](#configuration)
- [Starting Runners](#starting-runners)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

**Operating System** (one of):
- RHEL 9.0 or later
- Oracle Linux 9.0 or later
- Fedora 38 or later
- Rocky Linux 9.0 or later
- AlmaLinux 9.0 or later

**Software**:
- Podman 4.4+ (with quadlet support)
- Systemd 247+
- GitHub CLI (`gh`) - for token generation
- Git

**Hardware** (recommended):
- CPU: 4+ cores
- RAM: 8GB+ (16GB recommended for concurrent builds)
- Disk: 50GB+ free space (for container images and build caches)

**Network**:
- Outbound HTTPS access to:
  - github.com
  - api.github.com
  - objects.githubusercontent.com
  - Package repositories (for tool installations)

### Permission Requirements

- **Root access** for systemd service installation
- **GitHub repository access** with one of:
  - Repository admin permissions
  - "Manage self-hosted runners" permission

## Quick Start

For experienced users, here's the fastest path to running runners:

```bash
# 1. Clone repository
git clone https://github.com/yourusername/self-hosted-runners.git
cd self-hosted-runners

# 2. Install (builds images and installs systemd units)
sudo make install

# 3. Configure environment
cp pods/shared/env.example pods/shared/.env

# 4. Generate and set runner token
RUNNER_TOKEN=$(make token)
# Edit .env and set: RUNNER_TOKEN=<token from above>
vi pods/shared/.env

# 5. Start runners
sudo make start

# 6. Enable auto-start on boot
sudo make enable

# 7. Check status
sudo make status
```

Runners should now appear in your GitHub repository under Settings → Actions → Runners.

## Detailed Installation

### Step 1: Clone Repository

```bash
cd /opt/projects/repositories
git clone https://github.com/yourusername/self-hosted-runners.git
cd self-hosted-runners
```

### Step 2: Verify Prerequisites

Run the prerequisite check:

```bash
make check-prereqs
```

Expected output:
```
Checking prerequisites...
Podman version: podman version 4.9.4-rhel
Systemd version: systemd 252 (252-46.0.1.el9_5.3)
Quadlet support: OK
All prerequisites met!
```

If any checks fail, install the missing components:

**Install Podman** (if missing):
```bash
# RHEL/Oracle Linux
sudo dnf install podman

# Fedora
sudo dnf install podman

# Debian/Ubuntu (backports may be needed for quadlets)
sudo apt install podman
```

**Install GitHub CLI** (for token generation):
```bash
# RHEL/Oracle Linux
sudo dnf install gh

# Fedora
sudo dnf install gh

# Debian/Ubuntu
sudo apt install gh
```

### Step 3: Build Container Images

Build both runner images:

```bash
make build
```

This will:
1. Build `github-runner-debian:latest` (Debian Trixie base, ~7.5GB)
2. Build `github-runner-oracle:latest` (Oracle Linux 10 base, ~3.8GB)

Build time: 15-30 minutes depending on network speed.

**Note**: Images include all security tools pre-installed. See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

### Step 4: Install Systemd Services

Install systemd quadlet units:

```bash
sudo make install
```

This will:
1. Build container images (if not already built)
2. Copy `.container` files to `/etc/containers/systemd/`
3. Reload systemd daemon
4. Register services

Verify services are registered:

```bash
systemctl list-unit-files | grep github-runner
```

Expected output:
```
github-runner-debian.service     disabled        disabled
github-runner-oracle.service     disabled        disabled
```

## Configuration

### Environment Variables

Create environment configuration:

```bash
cp pods/shared/env.example pods/shared/.env
```

Edit `pods/shared/.env` and configure:

```bash
# Required: GitHub repository URL
REPO_URL=https://github.com/dantte-lp/ocserv-agent

# Required: Runner registration token (generate with make token)
RUNNER_TOKEN=your-token-here

# Optional: Custom runner names
DEBIAN_RUNNER_NAME=debian-runner-ocserv-agent
ORACLE_RUNNER_NAME=oraclelinux-runner-ocserv-agent

# Optional: Custom labels
DEBIAN_RUNNER_LABELS=self-hosted,linux,x64,debian,docker,security-scan,deb-build
ORACLE_RUNNER_LABELS=self-hosted,linux,x64,oracle-linux,rpm-build,mock,podman,el10

# Optional: Runner group
RUNNER_GROUP=Default
```

### Generate Runner Token

GitHub runner tokens expire after **1 hour**. Generate a fresh token:

```bash
./scripts/generate-token.sh
```

Or using make:

```bash
make token
```

**Copy the token** and update `pods/shared/.env`:

```bash
RUNNER_TOKEN=<paste-your-token-here>
```

**Alternative**: Use environment variable (for testing):

```bash
export RUNNER_TOKEN=$(make token | tail -1)
sudo -E systemctl start github-runner-debian.service
```

### Advanced Configuration

#### Resource Limits

Edit `.container` files to set CPU/memory limits:

**CPU Quota** (4 cores max):
```ini
# In github-runner-debian.container
CPUQuota=400%
```

**Memory Limit** (8GB):
```ini
# In github-runner-debian.container
Memory=8G
MemorySwap=8G
```

#### Custom Volumes

Add build cache volumes for faster builds:

**For Debian runner** (DEB builds):
```ini
# In github-runner-debian.container [Container] section
Volume=/var/cache/deb-builds:/cache:rw,z
```

**For Oracle runner** (RPM builds with mock):
```ini
# In github-runner-oracle.container [Container] section
Volume=/var/cache/mock:/var/cache/mock:rw,z
```

#### Security Options

If builds fail with permission errors, you may need to adjust security settings:

```ini
# In .container files [Container] section
SecurityLabelDisable=true  # Already set by default
AddCapability=SYS_ADMIN    # For mock/container builds
```

## Starting Runners

### Start Services

Start both runners:

```bash
sudo systemctl start github-runner-debian.service
sudo systemctl start github-runner-oracle.service
```

Or using make:

```bash
sudo make start
```

### Enable Auto-Start on Boot

Enable services to start automatically on system boot:

```bash
sudo systemctl enable github-runner-debian.service
sudo systemctl enable github-runner-oracle.service
```

Or using make:

```bash
sudo make enable
```

### Start Individual Runners

Start only one runner:

```bash
# Debian runner only
sudo systemctl start github-runner-debian.service

# Oracle runner only
sudo systemctl start github-runner-oracle.service
```

## Verification

### Check Service Status

View service status:

```bash
sudo systemctl status github-runner-debian.service
sudo systemctl status github-runner-oracle.service
```

Or using make:

```bash
sudo make status
```

Expected output:
```
● github-runner-debian.service - GitHub Actions Self-Hosted Runner (Debian Trixie)
     Loaded: loaded (/etc/containers/systemd/github-runner-debian.container; enabled)
     Active: active (running) since Thu 2025-10-24 10:00:00 UTC; 5min ago
```

### Check Container Status

View running containers:

```bash
sudo podman ps
```

Expected output:
```
CONTAINER ID  IMAGE                                      COMMAND     CREATED        STATUS        PORTS       NAMES
abc123def456  localhost/github-runner-debian:latest                  5 minutes ago  Up 5 minutes              github-runner-debian
def789ghi012  localhost/github-runner-oracle:latest                  5 minutes ago  Up 5 minutes              github-runner-oracle
```

### Check Runner Registration

Verify runners appear in GitHub:

1. Navigate to your repository
2. Go to **Settings** → **Actions** → **Runners**
3. Look for:
   - `debian-runner-ocserv-agent` (green dot = online)
   - `oraclelinux-runner-ocserv-agent` (green dot = online)

### View Logs

Monitor runner logs:

```bash
# Follow logs for both runners
sudo make logs

# Debian runner only
sudo make logs-debian

# Oracle runner only
sudo make logs-oracle

# View last 100 lines
sudo journalctl -u github-runner-debian.service -n 100

# Follow logs in real-time
sudo journalctl -u github-runner-debian.service -f
```

Expected log output:
```
🏃 GitHub Actions Self-Hosted Runner (Debian)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Repository: https://github.com/dantte-lp/ocserv-agent
Runner Name: debian-runner-ocserv-agent
Labels: self-hosted,linux,x64,debian,docker

✅ Runner configured
🚀 Starting runner...
√ Connected to GitHub
```

## Troubleshooting

### Runner Token Expired

**Symptom**: Runner fails to register with "Bad credentials" error

**Solution**: Generate a new token (tokens expire after 1 hour):

```bash
# Generate new token
make token

# Update .env
vi pods/shared/.env  # Set new RUNNER_TOKEN

# Restart services
sudo systemctl restart github-runner-debian.service
sudo systemctl restart github-runner-oracle.service
```

### Container Build Fails

**Symptom**: `make build` fails with network errors

**Solution**: Check network connectivity and retry:

```bash
# Test connectivity
curl -I https://github.com
curl -I https://go.dev

# Clean and rebuild
make clean
make build
```

### Permission Denied Errors

**Symptom**: Container fails to start with permission errors

**Solution**: Check SELinux labels on volumes:

```bash
# Verify SELinux context
ls -Z /opt/projects/repositories

# If incorrect, relabel
sudo chcon -R -t container_file_t /opt/projects/repositories

# Or add :z flag to volumes in .container files
Volume=/opt/projects/repositories:/workspace:rw,z
```

### Service Won't Start

**Symptom**: `systemctl start` fails immediately

**Solution**: Check journal logs for details:

```bash
sudo journalctl -u github-runner-debian.service -xe
```

Common causes:
- Missing `.env` file
- Invalid RUNNER_TOKEN
- Container image not built
- Port conflicts

### Runner Shows Offline in GitHub

**Symptom**: Runner registered but shows offline (gray dot)

**Possible Causes**:

1. **Service not running**:
   ```bash
   sudo systemctl status github-runner-debian.service
   sudo systemctl start github-runner-debian.service  # If stopped
   ```

2. **Token expired**:
   - Tokens expire after 1 hour
   - Generate new token and restart service

3. **Network connectivity**:
   ```bash
   # From inside container
   sudo podman exec -it github-runner-debian bash
   curl -I https://api.github.com
   ```

4. **Runner configuration issue**:
   ```bash
   # Check container logs
   sudo podman logs github-runner-debian
   ```

For more troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Next Steps

After successful setup:

1. **Test Runners**: Trigger a GitHub Actions workflow to verify runners work
2. **Configure Workflows**: Update `.github/workflows/*.yml` to use `runs-on: self-hosted`
3. **Monitor**: Set up monitoring for runner health and capacity
4. **Scale**: Add more runners if needed by cloning .container files
5. **Secure**: Review security settings and apply organizational policies

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - How runners work internally
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [README.md](../README.md) - Project overview
- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [GitHub Actions Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
