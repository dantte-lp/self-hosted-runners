# Troubleshooting - Self-Hosted GitHub Actions Runners

Common issues, solutions, and debugging techniques for self-hosted runners.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Runner Registration Problems](#runner-registration-problems)
- [Container Issues](#container-issues)
- [Networking Problems](#networking-problems)
- [Performance Issues](#performance-issues)
- [Security and Permissions](#security-and-permissions)
- [Advanced Debugging](#advanced-debugging)

## Quick Diagnostics

Run these commands first to gather diagnostic information:

```bash
# 1. Check service status
sudo systemctl status github-runner-debian.service
sudo systemctl status github-runner-oracle.service

# 2. View recent logs
sudo journalctl -u github-runner-debian.service -n 50 --no-pager

# 3. Check container status
sudo podman ps -a

# 4. Verify environment file exists
cat pods/shared/.env | grep RUNNER_TOKEN

# 5. Test GitHub connectivity
curl -I https://api.github.com

# 6. Check disk space
df -h /var/lib/containers
podman system df
```

## Common Issues

### Issue: Runner Token Expired

**Symptoms**:
- Service starts but runner shows offline in GitHub
- Logs show "Bad credentials" or "Unauthorized"
- Error: "401 Unauthorized"

**Cause**: Runner tokens expire after 1 hour

**Solution**:

```bash
# 1. Generate new token
make token

# 2. Update .env file
vi pods/shared/.env
# Set: RUNNER_TOKEN=<new-token>

# 3. Restart services
sudo systemctl restart github-runner-debian.service
sudo systemctl restart github-runner-oracle.service

# 4. Verify registration
sudo journalctl -u github-runner-debian.service -n 20 | grep "Connected to GitHub"
```

**Prevention**: Consider using a GitHub App installation token for long-running runners.

---

### Issue: Service Fails to Start

**Symptoms**:
- `systemctl start` returns immediately
- Service shows "failed" status
- Error: "Start request repeated too quickly"

**Diagnosis**:

```bash
# Check systemd status
sudo systemctl status github-runner-debian.service

# View detailed error logs
sudo journalctl -u github-runner-debian.service -xe

# Check if container exists
sudo podman ps -a | grep github-runner-debian
```

**Common Causes & Solutions**:

1. **Missing .env file**:
   ```bash
   # Check if file exists
   ls -la pods/shared/.env

   # Create from example
   cp pods/shared/env.example pods/shared/.env
   vi pods/shared/.env  # Edit configuration
   ```

2. **Container image not built**:
   ```bash
   # Check if image exists
   podman images | grep github-runner

   # Build if missing
   make build
   ```

3. **Systemd quadlet file corrupted**:
   ```bash
   # Reinstall quadlet files
   sudo make uninstall
   sudo make install
   sudo systemctl daemon-reload
   ```

---

### Issue: Runner Shows Offline in GitHub

**Symptoms**:
- Runner appears in GitHub but with gray "Offline" status
- Service is running but no jobs are picked up

**Diagnosis**:

```bash
# 1. Check if runner process is actually running
sudo podman exec -it github-runner-debian ps aux | grep run.sh

# 2. Check network connectivity from inside container
sudo podman exec -it github-runner-debian curl -I https://api.github.com

# 3. View runner logs
sudo podman logs github-runner-debian

# 4. Check runner configuration
sudo podman exec -it github-runner-debian cat .runner
```

**Solutions**:

1. **Token expired** - Regenerate token (see above)

2. **Network connectivity issue**:
   ```bash
   # Test from host
   curl -v https://api.github.com

   # Check firewall rules
   sudo firewall-cmd --list-all

   # Allow HTTPS if blocked
   sudo firewall-cmd --add-service=https --permanent
   sudo firewall-cmd --reload
   ```

3. **Runner process crashed**:
   ```bash
   # Restart container
   sudo systemctl restart github-runner-debian.service

   # Check logs for crash reason
   sudo journalctl -u github-runner-debian.service -n 100
   ```

---

### Issue: Container Build Fails

**Symptoms**:
- `make build` fails with errors
- Network timeouts during downloads
- "No space left on device"

**Solutions**:

1. **Network timeouts**:
   ```bash
   # Increase timeout and retry
   podman build --timeout 1h -t github-runner-debian:latest \
     -f pods/github-runner-debian/Containerfile \
     pods/github-runner-debian/
   ```

2. **Disk space issues**:
   ```bash
   # Check available space
   df -h /var/lib/containers

   # Clean old images
   podman system prune -a --force

   # Remove build cache
   podman builder prune --all --force
   ```

3. **Repository connection failures**:
   ```bash
   # Test specific downloads manually
   curl -I https://go.dev/dl/go1.25.1.linux-amd64.tar.gz
   curl -I https://github.com/gitleaks/gitleaks/releases/

   # Check DNS resolution
   dig github.com
   dig go.dev
   ```

## Runner Registration Problems

### Issue: "Runner already exists"

**Symptoms**:
- Error: "A runner exists with the same name"
- Registration fails even with --replace flag

**Solution**:

```bash
# 1. Remove runner from GitHub UI
# Go to Settings → Actions → Runners → Click runner → Remove

# 2. Or use --replace flag (already in entrypoint.sh)
# The entrypoint should handle this automatically

# 3. Clean local registration
sudo podman exec -it github-runner-debian rm -f .runner .credentials*

# 4. Restart service
sudo systemctl restart github-runner-debian.service
```

---

### Issue: "Invalid Runner Group"

**Symptoms**:
- Error: "Runner group 'Default' not found"

**Solution**:

```bash
# Check if you're using organization runners
# Organization runners need proper group configuration

# For repository runners, use:
RUNNER_GROUP=Default

# For organization runners, check available groups:
gh api orgs/YOUR_ORG/actions/runner-groups --jq '.runner_groups[].name'

# Update .env with correct group name
vi pods/shared/.env
```

## Container Issues

### Issue: "Permission Denied" Inside Container

**Symptoms**:
- Jobs fail with permission errors
- Cannot write to /workspace
- Mock builds fail

**Solutions**:

1. **SELinux context issues**:
   ```bash
   # Check SELinux labels
   ls -Z /opt/projects/repositories

   # Relabel if needed
   sudo chcon -R -t container_file_t /opt/projects/repositories

   # Or use :z flag in .container file (already set)
   # Volume=/opt/projects/repositories:/workspace:rw,z
   ```

2. **User ID mismatch**:
   ```bash
   # Check container user
   sudo podman exec -it github-runner-debian id

   # Should be: uid=1001(runner) gid=1001(runner)

   # Check host permissions
   ls -ld /opt/projects/repositories

   # Fix ownership if needed
   sudo chown -R $(id -u):$(id -g) /opt/projects/repositories
   ```

---

### Issue: Podman Socket Not Accessible

**Symptoms**:
- Docker commands fail inside container
- Error: "Cannot connect to the Docker daemon"

**Solutions**:

1. **Enable Podman socket**:
   ```bash
   # Enable and start Podman socket
   sudo systemctl enable --now podman.socket

   # Verify socket exists
   ls -la /run/podman/podman.sock

   # Restart service
   sudo systemctl restart github-runner-debian.service
   ```

2. **Check socket permissions**:
   ```bash
   # Socket should be accessible
   sudo ls -la /run/podman/podman.sock

   # Should show: srw-rw---- root root
   ```

## Networking Problems

### Issue: Cannot Connect to GitHub

**Symptoms**:
- Timeout connecting to api.github.com
- SSL certificate errors
- DNS resolution failures

**Solutions**:

1. **Test network connectivity**:
   ```bash
   # From host
   curl -v https://api.github.com

   # From container
   sudo podman exec -it github-runner-debian curl -v https://api.github.com
   ```

2. **DNS issues**:
   ```bash
   # Check DNS resolution
   dig api.github.com

   # Use alternate DNS in container
   # Edit .container file and add:
   # Dns=8.8.8.8
   # Dns=8.8.4.4

   sudo systemctl daemon-reload
   sudo systemctl restart github-runner-debian.service
   ```

3. **Proxy configuration**:
   ```bash
   # If behind corporate proxy, add to .env:
   HTTP_PROXY=http://proxy.example.com:8080
   HTTPS_PROXY=http://proxy.example.com:8080
   NO_PROXY=localhost,127.0.0.1
   ```

## Performance Issues

### Issue: Slow Build Times

**Symptoms**:
- Builds take significantly longer than expected
- High CPU/memory usage
- Container unresponsive

**Solutions**:

1. **Check resource limits**:
   ```bash
   # View current limits
   systemctl show github-runner-debian.service --property=MemoryCurrent
   systemctl show github-runner-debian.service --property=CPUUsageNSec

   # Increase limits in .container file:
   CPUQuota=800%  # Allow 8 cores
   Memory=16G     # Allow 16GB RAM

   sudo systemctl daemon-reload
   sudo systemctl restart github-runner-debian.service
   ```

2. **Add build caches**:
   ```bash
   # For Go builds, mount Go cache
   # Add to .container file:
   Volume=/var/cache/go-build:/root/.cache/go-build:rw,z
   Volume=/var/cache/go-mod:/go/pkg/mod:rw,z

   # For npm builds
   Volume=/var/cache/npm:/root/.npm:rw,z
   ```

3. **Storage driver optimization**:
   ```bash
   # Check current driver
   podman info --format '{{.Store.GraphDriverName}}'

   # overlay2 is fastest (if supported)
   # vfs is slower but more compatible (default for rootless)
   ```

---

### Issue: Disk Space Filling Up

**Symptoms**:
- "No space left on device" errors
- Builds fail unexpectedly
- Slow performance

**Solutions**:

```bash
# 1. Check usage
podman system df
df -h /var/lib/containers

# 2. Clean old containers
podman container prune --force

# 3. Clean old images
podman image prune -a --force

# 4. Clean build cache
podman builder prune --all --force

# 5. Clean volumes
podman volume prune --force

# 6. Check for large log files
du -sh /var/log/journal/*
journalctl --vacuum-size=500M

# 7. Set up automatic cleanup
# Add to cron:
0 2 * * * /usr/bin/podman system prune -a --force --filter "until=24h"
```

## Security and Permissions

### Issue: SELinux Denials

**Symptoms**:
- Permission denied errors
- AVC denial messages in audit log
- Container fails to access volumes

**Diagnosis**:

```bash
# Check SELinux status
sestatus

# View recent denials
sudo ausearch -m avc -ts recent

# Check SELinux labels
ls -Z /opt/projects/repositories
```

**Solutions**:

1. **Temporary**: Disable SELinux (not recommended):
   ```bash
   sudo setenforce 0  # Permissive mode
   ```

2. **Proper fix**: Relabel volumes:
   ```bash
   # Relabel repository directory
   sudo chcon -R -t container_file_t /opt/projects/repositories

   # Or use :z flag in .container (already set)
   ```

3. **Create custom policy** (advanced):
   ```bash
   # Generate policy from denials
   sudo ausearch -m avc -ts recent | audit2allow -M my-runner-policy
   sudo semodule -i my-runner-policy.pp
   ```

## Advanced Debugging

### Enable Debug Logging

**For Podman**:
```bash
# Edit .container file, add:
Environment=PODMAN_LOG_LEVEL=debug

# Restart service
sudo systemctl daemon-reload
sudo systemctl restart github-runner-debian.service

# View debug logs
sudo journalctl -u github-runner-debian.service -n 100
```

**For GitHub Actions Runner**:
```bash
# Set debug mode in .env:
ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ACTIONS_STEP_DEBUG=true

# Restart service
sudo systemctl restart github-runner-debian.service
```

### Interactive Container Debugging

```bash
# Access running container
sudo podman exec -it github-runner-debian /bin/bash

# Check runner configuration
cd /home/runner
ls -la
cat .runner

# Check environment
env | grep RUNNER

# Test GitHub connectivity
curl -v https://api.github.com

# Check runner process
ps aux | grep run.sh

# Exit
exit
```

### Capture Full Logs

```bash
# Export last hour of logs
sudo journalctl -u github-runner-debian.service \
  --since="1 hour ago" \
  --output=verbose \
  > runner-debug.log

# Export with specific log level
sudo journalctl -u github-runner-debian.service \
  -p debug \
  --since="1 hour ago" \
  > runner-debug.log
```

### Health Check

Create a health check script:

```bash
#!/bin/bash
# health-check.sh

echo "=== Runner Health Check ==="
echo ""

# 1. Service status
echo "1. Service Status:"
systemctl is-active github-runner-debian.service
systemctl is-active github-runner-oracle.service
echo ""

# 2. Container status
echo "2. Container Status:"
podman ps --filter "name=github-runner" --format "table {{.Names}}\t{{.Status}}"
echo ""

# 3. Disk space
echo "3. Disk Space:"
df -h /var/lib/containers | grep -v tmpfs
echo ""

# 4. Runner connectivity
echo "4. GitHub Connectivity:"
curl -s -o /dev/null -w "%{http_code}" https://api.github.com
echo ""

# 5. Memory usage
echo "5. Memory Usage:"
systemctl show github-runner-debian.service --property=MemoryCurrent --value | numfmt --to=iec
systemctl show github-runner-oracle.service --property=MemoryCurrent --value | numfmt --to=iec
echo ""

echo "=== Health Check Complete ==="
```

## Getting Help

If issues persist:

1. **Collect diagnostic information**:
   ```bash
   # Create diagnostics bundle
   mkdir runner-diagnostics
   systemctl status github-runner-*.service > runner-diagnostics/status.txt
   journalctl -u github-runner-debian.service -n 200 > runner-diagnostics/debian-logs.txt
   journalctl -u github-runner-oracle.service -n 200 > runner-diagnostics/oracle-logs.txt
   podman ps -a > runner-diagnostics/containers.txt
   podman images > runner-diagnostics/images.txt
   cat pods/shared/.env | grep -v RUNNER_TOKEN > runner-diagnostics/config.txt
   tar czf runner-diagnostics.tar.gz runner-diagnostics/
   ```

2. **Open an issue** with:
   - Diagnostic bundle
   - Steps to reproduce
   - Expected vs actual behavior
   - System information (OS, Podman version)

3. **Community resources**:
   - GitHub Discussions
   - RHEL/Oracle Linux forums
   - Podman community

## Related Documentation

- [SETUP.md](SETUP.md) - Installation guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical architecture
- [Podman Troubleshooting](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [GitHub Actions Troubleshooting](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/monitoring-and-troubleshooting-self-hosted-runners)
