#!/bin/bash

# ==============================================================================
# uninstall.sh - Uninstall GitHub Actions runners
# ==============================================================================
#
# This script removes systemd quadlet files and stops running services.
# It must be run as root (or with sudo).
#
# Usage:
#   sudo ./scripts/uninstall.sh
#   sudo make uninstall  # Alternative using Makefile
#
# ==============================================================================

set -e

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Paths
SYSTEMD_DIR="/etc/containers/systemd"

echo -e "${CYAN}GitHub Actions Runner Uninstallation${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Use: sudo ./scripts/uninstall.sh"
    exit 1
fi

# Confirmation prompt
read -p "Are you sure you want to uninstall GitHub Actions runners? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${YELLOW}Uninstallation cancelled${NC}"
    exit 0
fi

# Stop services
echo -e "${CYAN}Stopping services...${NC}"

if systemctl is-active --quiet github-runner-debian.service; then
    echo -e "${YELLOW}Stopping github-runner-debian.service...${NC}"
    systemctl stop github-runner-debian.service
    echo -e "${GREEN}✅ Stopped${NC}"
else
    echo -e "${YELLOW}github-runner-debian.service is not running${NC}"
fi

if systemctl is-active --quiet github-runner-oracle.service; then
    echo -e "${YELLOW}Stopping github-runner-oracle.service...${NC}"
    systemctl stop github-runner-oracle.service
    echo -e "${GREEN}✅ Stopped${NC}"
else
    echo -e "${YELLOW}github-runner-oracle.service is not running${NC}"
fi

echo ""

# Disable services
echo -e "${CYAN}Disabling services...${NC}"

if systemctl is-enabled --quiet github-runner-debian.service 2>/dev/null; then
    echo -e "${YELLOW}Disabling github-runner-debian.service...${NC}"
    systemctl disable github-runner-debian.service
    echo -e "${GREEN}✅ Disabled${NC}"
fi

if systemctl is-enabled --quiet github-runner-oracle.service 2>/dev/null; then
    echo -e "${YELLOW}Disabling github-runner-oracle.service...${NC}"
    systemctl disable github-runner-oracle.service
    echo -e "${GREEN}✅ Disabled${NC}"
fi

echo ""

# Remove quadlet files
echo -e "${CYAN}Removing systemd quadlet units...${NC}"

if [ -f "$SYSTEMD_DIR/github-runner-debian.container" ]; then
    echo -e "${YELLOW}Removing github-runner-debian.container...${NC}"
    rm -f "$SYSTEMD_DIR/github-runner-debian.container"
    echo -e "${GREEN}✅ Removed${NC}"
fi

if [ -f "$SYSTEMD_DIR/github-runner-oracle.container" ]; then
    echo -e "${YELLOW}Removing github-runner-oracle.container...${NC}"
    rm -f "$SYSTEMD_DIR/github-runner-oracle.container"
    echo -e "${GREEN}✅ Removed${NC}"
fi

echo ""

# Reload systemd daemon
echo -e "${CYAN}Reloading systemd daemon...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✅ Systemd daemon reloaded${NC}"

echo ""

# Optional: Remove container images
read -p "Do you want to remove container images? (yes/no): " -r
echo
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${CYAN}Removing container images...${NC}"

    if podman images | grep -q "github-runner-debian"; then
        echo -e "${YELLOW}Removing github-runner-debian:latest...${NC}"
        podman rmi github-runner-debian:latest 2>/dev/null || true
        echo -e "${GREEN}✅ Removed${NC}"
    fi

    if podman images | grep -q "github-runner-oracle"; then
        echo -e "${YELLOW}Removing github-runner-oracle:latest...${NC}"
        podman rmi github-runner-oracle:latest 2>/dev/null || true
        echo -e "${GREEN}✅ Removed${NC}"
    fi

    echo ""
    echo -e "${CYAN}Pruning unused images...${NC}"
    podman image prune -f
    echo -e "${GREEN}✅ Pruned${NC}"
fi

echo ""
echo -e "${GREEN}✅ Uninstallation complete!${NC}"
echo ""
echo -e "${YELLOW}Note: Configuration files in pods/shared/ were not removed${NC}"
echo -e "${YELLOW}Remove them manually if needed: rm -f pods/shared/.env${NC}"
